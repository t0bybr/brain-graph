import hashlib
from typing import Any, Dict, List, Optional


def _vector_literal(values: List[float]) -> str:
    return "[" + ",".join(f"{v:.6f}" for v in values) + "]"


def _hash_content(content: str, model_name: str, source_part: str) -> str:
    return hashlib.sha256(f"{content}|{model_name}|{source_part}".encode("utf-8")).hexdigest()


def _deterministic_embedding(content: str, dimension: int) -> List[float]:
    """Deterministic vector for offline/testing use."""
    base = hashlib.sha256(content.encode("utf-8")).digest()
    values: List[float] = []
    for i in range(dimension):
        seed = hashlib.sha256(base + i.to_bytes(4, "big")).digest()
        int_val = int.from_bytes(seed[:4], "big")
        values.append((int_val % 2000) / 1000.0 - 1.0)
    return values


class EmbeddingService:
    """Handles embedding selection, generation and persistence."""

    def __init__(self, db):
        self.db = db

    async def list_models(self) -> List[Dict[str, Any]]:
        rows = await self.db.fetch(
            """
            SELECT model_name, model_version, modality, dimension, is_active, is_default
            FROM embedding_models
            ORDER BY is_default DESC, model_name
        """
        )
        return [dict(r) for r in rows]

    async def _select_models(self, node_type: str, model_name: Optional[str]):
        if model_name:
            row = await self.db.fetchrow(
                """
                SELECT model_name, modality, dimension, 'full' AS source_part, 1 AS priority
                FROM embedding_models
                WHERE model_name = $1 AND is_active = TRUE
            """,
                model_name,
            )
            if not row:
                raise ValueError(f"Model {model_name} is not available")
            return [dict(row)]

        rows = await self.db.fetch(
            """
            SELECT gm.model_name,
                   gm.source_part,
                   em.modality,
                   em.dimension,
                   gm.priority
            FROM get_models_for_node($1::node_type) gm
            JOIN embedding_models em ON em.model_name = gm.model_name
            WHERE em.is_active = TRUE
            ORDER BY gm.priority
        """,
            node_type,
        )

        if rows:
            return [dict(r) for r in rows]

        # Fallback: single default model
        fallback = await self.db.fetchrow(
            """
            SELECT model_name, modality, dimension, 'full' AS source_part, 1 AS priority
            FROM embedding_models
            WHERE is_default = TRUE
            ORDER BY added_at DESC NULLS LAST
            LIMIT 1
        """
        )
        return [dict(fallback)] if fallback else []

    async def generate_for_node(
        self, node_id: str, model_name: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        node = await self.db.fetchrow(
            """
            SELECT id, type::text AS type, title, text_content
            FROM nodes
            WHERE id = $1::text
        """,
            node_id,
        )

        if not node:
            raise ValueError("Node not found")

        text_full = " ".join(
            part for part in [node["title"], node["text_content"]] if part
        ).strip()
        if not text_full:
            raise ValueError("Node has no textual content to embed")

        models = await self._select_models(node["type"], model_name)
        if not models:
            raise ValueError("No embedding models available")

        stored: List[Dict[str, Any]] = []

        for model in models:
            content = (
                node["title"]
                if model["source_part"] == "title"
                else text_full
            )
            embedding = _deterministic_embedding(content, model["dimension"])
            content_hash = _hash_content(content, model["model_name"], model["source_part"])

            stored_row = await self.store_embedding(
                node_id=node["id"],
                modality=model["modality"],
                model_name=model["model_name"],
                source_part=model["source_part"],
                embedding=embedding,
                content_hash=content_hash,
                dimension=model["dimension"],
            )
            stored.append(stored_row)

        return stored

    async def store_embedding(
        self,
        node_id: str,
        modality: str,
        model_name: str,
        source_part: str,
        embedding: List[float],
        content_hash: str,
        dimension: Optional[int] = None,
        chunk_id: Optional[str] = None,
        generation_time_ms: Optional[int] = None,
        token_count: Optional[int] = None,
    ) -> Dict[str, Any]:
        """Store embedding and ensure HNSW indexes exist."""

        dimension = dimension or len(embedding)
        vector_literal = _vector_literal(embedding)

        try:
            row = await self.db.fetchrow(
                """
                INSERT INTO node_embeddings (
                    node_id, chunk_id, modality, model_name, source_part,
                    dimension, embedding, content_hash, generation_time_ms, token_count
                )
                VALUES ($1::text, $2, $3, $4, $5, $6, $7::vector, $8, $9, $10)
                ON CONFLICT (node_id, chunk_id, modality, model_name, source_part)
                DO UPDATE SET
                    embedding = EXCLUDED.embedding,
                    content_hash = EXCLUDED.content_hash,
                    generated_at = NOW(),
                    last_accessed = NOW(),
                    dimension = EXCLUDED.dimension,
                    generation_time_ms = COALESCE(EXCLUDED.generation_time_ms, node_embeddings.generation_time_ms),
                    token_count = COALESCE(EXCLUDED.token_count, node_embeddings.token_count)
                RETURNING id, node_id, chunk_id, modality, model_name, source_part, dimension, generated_at
            """,
                node_id,
                chunk_id,
                modality,
                model_name,
                source_part,
                dimension,
                vector_literal,
                content_hash,
                generation_time_ms,
                token_count,
            )
        except Exception as exc:  # pragma: no cover - defensive fallback
            raise ValueError("Failed to store embedding; ensure pgvector is installed") from exc

        await self._ensure_hnsw_indexes()

        return dict(row)

    async def _ensure_hnsw_indexes(self):
        """Create HNSW indexes if they don't exist yet."""
        try:
            await self.db.execute("SELECT create_hnsw_indexes()")
        except Exception:
            # Running without pgvector/hnsw is acceptable in dev/tests
            pass
