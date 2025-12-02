import hashlib
from typing import Any, Dict, List, Literal, Optional

from app.database import get_db
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

router = APIRouter()


class SearchRequest(BaseModel):
    query: str
    limit: int = Field(default=20, ge=1, le=200)
    mode: Literal["node", "chunk"] = "node"
    use_vector: bool = False
    query_embedding: Optional[List[float]] = None
    alpha: float = Field(default=0.5, ge=0.0, le=1.0)
    model_name: str = "jina-embeddings-v2"
    node_types: Optional[List[str]] = None
    language: str = "en"
    include_context: bool = True
    context_size: int = Field(default=1, ge=0, le=3)


class SearchResult(BaseModel):
    node_id: str
    title: Optional[str] = None
    node_type: Optional[str] = None
    chunk_id: Optional[str] = None
    content: Optional[str] = None
    summary: Optional[str] = None
    bm25_score: Optional[float] = None
    vector_score: Optional[float] = None
    hybrid_score: Optional[float] = None
    context_before: Optional[str] = None
    context_after: Optional[str] = None


def _vector_literal(values: List[float]) -> str:
    """Convert a Python list into pgvector literal."""
    return "[" + ",".join(f"{v:.6f}" for v in values) + "]"


def _deterministic_embedding(text: str, dimension: int) -> List[float]:
    """Fallback embedding generator based on hashing; deterministic for tests/offline use."""
    base = hashlib.sha256(text.encode("utf-8")).digest()
    values: List[float] = []
    for i in range(dimension):
        seed = hashlib.sha256(base + i.to_bytes(4, "big")).digest()
        int_val = int.from_bytes(seed[:4], "big")
        values.append((int_val % 2000) / 1000.0 - 1.0)  # Range roughly [-1, 1]
    return values


async def _get_model_info(db, model_name: str) -> Dict[str, Any]:
    row = await db.fetchrow(
        """
        SELECT model_name, modality, dimension
        FROM embedding_models
        WHERE model_name = $1 AND is_active = TRUE
    """,
        model_name,
    )
    if not row:
        raise HTTPException(status_code=400, detail=f"Unknown embedding model {model_name}")
    return dict(row)


@router.post("/", response_model=List[SearchResult])
async def search(request: SearchRequest, db=Depends(get_db)):
    """Hybrid/BM25 search for nodes or chunks."""

    if request.mode == "chunk":
        results = await _search_chunks(request, db)
    else:
        results = await _search_nodes(request, db)

    # Track access for found nodes
    for result in results:
        try:
            await db.execute("SELECT track_node_access($1)", result.node_id)
        except Exception:
            # Tracking is best-effort; avoid breaking search
            pass

    return results


async def _search_nodes(request: SearchRequest, db) -> List[SearchResult]:
    if request.use_vector or request.query_embedding:
        try:
            return await _hybrid_node_search(request, db)
        except Exception:
            # Fallback to BM25 if vector search fails (e.g., pgvector missing)
            pass

    return await _bm25_node_search(request, db)


async def _bm25_node_search(request: SearchRequest, db) -> List[SearchResult]:
    """Prefer ParadeDB BM25 index, fallback to tsvector."""
    # Attempt ParadeDB/pg_search index
    try:
        rows = await db.fetch(
            """
            SELECT id AS node_id,
                   type::text AS node_type,
                   title,
                   paradedb.score(id) AS bm25_score
            FROM nodes_search_idx.search($1)
            WHERE ($2::text[] IS NULL OR type::text = ANY($2::text[]))
            ORDER BY bm25_score DESC
            LIMIT $3
        """,
            request.query,
            request.node_types,
            request.limit,
        )
    except Exception:
        rows = await db.fetch(
            """
            SELECT id AS node_id,
                   type::text AS node_type,
                   title,
                   ts_rank_cd(
                       to_tsvector('english', COALESCE(title, '') || ' ' || COALESCE(text_content, '')),
                       plainto_tsquery('english', $1)
                   ) AS bm25_score
            FROM nodes
            WHERE to_tsvector('english', COALESCE(title, '') || ' ' || COALESCE(text_content, ''))
                  @@ plainto_tsquery('english', $1)
              AND ($2::text[] IS NULL OR type::text = ANY($2::text[]))
            ORDER BY bm25_score DESC
            LIMIT $3
        """,
            request.query,
            request.node_types,
            request.limit,
        )

    results: List[SearchResult] = []
    for row in rows:
        data = dict(row)
        results.append(
            SearchResult(
                node_id=data["node_id"],
                node_type=data.get("node_type"),
                title=data.get("title"),
                bm25_score=data.get("bm25_score"),
            )
        )

    return results


async def _hybrid_node_search(request: SearchRequest, db) -> List[SearchResult]:
    model = await _get_model_info(db, request.model_name)
    query_embedding = request.query_embedding or _deterministic_embedding(
        request.query, model["dimension"]
    )
    vector_literal = _vector_literal(query_embedding)

    rows = await db.fetch(
        """
        SELECT * FROM hybrid_search(
            $1,
            $2::vector,
            $3,
            $4,
            $5,
            $6::node_type[]
        )
    """,
        request.query,
        vector_literal,
        request.model_name,
        request.alpha,
        request.limit,
        request.node_types,
    )

    results: List[SearchResult] = []
    for row in rows:
        data = dict(row)
        results.append(
            SearchResult(
                node_id=data["node_id"],
                node_type=data.get("node_type"),
                title=data.get("title"),
                bm25_score=data.get("bm25_score"),
                vector_score=data.get("vector_score"),
                hybrid_score=data.get("hybrid_score"),
            )
        )

    return results


async def _search_chunks(request: SearchRequest, db) -> List[SearchResult]:
    if request.use_vector or request.query_embedding:
        try:
            return await _hybrid_chunk_search(request, db)
        except Exception:
            pass

    rows = await db.fetch(
        """
        SELECT * FROM search_chunks($1, $2::node_type[], $3, $4, $5, $6)
    """,
        request.query,
        request.node_types,
        request.language,
        request.limit,
        request.include_context,
        request.context_size,
    )

    results: List[SearchResult] = []
    for row in rows:
        data = dict(row)
        results.append(
            SearchResult(
                node_id=data["node_id"],
                title=data.get("node_title"),
                chunk_id=data.get("chunk_id"),
                content=data.get("content"),
                summary=data.get("summary"),
                bm25_score=data.get("bm25_score"),
                context_before=data.get("context_before"),
                context_after=data.get("context_after"),
            )
        )

    return results


async def _hybrid_chunk_search(request: SearchRequest, db) -> List[SearchResult]:
    model = await _get_model_info(db, request.model_name)
    query_embedding = request.query_embedding or _deterministic_embedding(
        request.query, model["dimension"]
    )
    vector_literal = _vector_literal(query_embedding)

    rows = await db.fetch(
        """
        SELECT * FROM hybrid_search_chunks(
            $1,
            $2::vector,
            $3,
            $4,
            $5,
            $6
        )
    """,
        request.query,
        vector_literal,
        request.model_name,
        request.alpha,
        request.limit,
        request.language,
    )

    results: List[SearchResult] = []
    for row in rows:
        data = dict(row)
        results.append(
            SearchResult(
                node_id=data["node_id"],
                title=data.get("node_title"),
                chunk_id=data.get("chunk_id"),
                content=data.get("content"),
                summary=data.get("summary"),
                bm25_score=data.get("bm25_score"),
                vector_score=data.get("vector_score"),
                hybrid_score=data.get("hybrid_score"),
            )
        )

    return results
