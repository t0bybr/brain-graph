from datetime import datetime
from typing import Any, Dict, List, Literal, Optional

import asyncpg
from app.database import get_db
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

router = APIRouter()


class EdgeCreate(BaseModel):
    source_id: str
    target_id: str
    edge_type: str
    properties: Dict[str, Any] = Field(default_factory=dict)
    created_by: Literal["user", "system"] = Field(
        default="user", description="creator flag constrained by database"
    )


class EdgeResponse(BaseModel):
    id: str
    source_id: str
    target_id: str
    edge_type: str
    properties: Dict[str, Any] = Field(default_factory=dict)
    created_by: str
    created_at: datetime


@router.post("/", response_model=EdgeResponse)
async def create_edge(edge: EdgeCreate, db=Depends(get_db)):
    """Create a graph edge between two nodes."""

    try:
        row = await db.fetchrow(
            """
            INSERT INTO graph_edges (source_id, target_id, edge_type, properties, created_by)
            VALUES ($1::text, $2::text, $3, $4, $5)
            RETURNING id, source_id, target_id, edge_type, properties, created_by, created_at
        """,
            edge.source_id,
            edge.target_id,
            edge.edge_type,
            edge.properties,
            edge.created_by,
        )
    except asyncpg.exceptions.ForeignKeyViolationError:
        raise HTTPException(
            status_code=400,
            detail="source_id or target_id does not reference an existing node",
        )
    except asyncpg.exceptions.UniqueViolationError:
        raise HTTPException(status_code=409, detail="Edge already exists")

    if not row:
        raise HTTPException(status_code=500, detail="Edge could not be created")

    return EdgeResponse(**dict(row))


@router.get("/{edge_id}", response_model=EdgeResponse)
async def get_edge(edge_id: str, db=Depends(get_db)):
    """Fetch a single edge by its ULID."""

    row = await db.fetchrow(
        """
        SELECT id, source_id, target_id, edge_type, properties, created_by, created_at
        FROM graph_edges
        WHERE id = $1::text
    """,
        edge_id,
    )

    if not row:
        raise HTTPException(status_code=404, detail="Edge not found")

    return EdgeResponse(**dict(row))


@router.get("/", response_model=List[EdgeResponse])
async def list_edges(
    source_id: Optional[str] = Query(None),
    target_id: Optional[str] = Query(None),
    node_id: Optional[str] = Query(
        None, description="Return edges where this node is either source or target"
    ),
    edge_type: Optional[str] = Query(None),
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
    db=Depends(get_db),
):
    """List edges with common filters."""

    clauses = []
    values: List[Any] = []

    def add_clause(condition: str, value: Any):
        values.append(value)
        clauses.append(condition.format(idx=len(values)))

    if node_id:
        add_clause("(source_id = ${idx}::text OR target_id = ${idx}::text)", node_id)
    if source_id:
        add_clause("source_id = ${idx}::text", source_id)
    if target_id:
        add_clause("target_id = ${idx}::text", target_id)
    if edge_type:
        add_clause("edge_type = ${idx}", edge_type)

    where_clause = f"WHERE {' AND '.join(clauses)}" if clauses else ""
    values.extend([limit, offset])

    rows = await db.fetch(
        f"""
        SELECT id, source_id, target_id, edge_type, properties, created_by, created_at
        FROM graph_edges
        {where_clause}
        ORDER BY created_at DESC
        LIMIT ${len(values)-1} OFFSET ${len(values)}
    """,
        *values,
    )

    return [EdgeResponse(**dict(r)) for r in rows]


@router.delete("/{edge_id}")
async def delete_edge(edge_id: str, db=Depends(get_db)):
    """Delete an edge."""

    result = await db.execute(
        "DELETE FROM graph_edges WHERE id = $1::text",
        edge_id,
    )

    if result == "DELETE 0":
        raise HTTPException(status_code=404, detail="Edge not found")

    return {"status": "deleted", "id": edge_id}
