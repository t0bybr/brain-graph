from datetime import datetime
from typing import List, Optional
from uuid import UUID

from app.database import get_db
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

router = APIRouter()


class NodeCreate(BaseModel):
    type: str
    title: str
    text_content: Optional[str] = None
    image_url: Optional[str] = None
    audio_url: Optional[str] = None
    video_url: Optional[str] = None
    metadata: dict = {}


class NodeResponse(BaseModel):
    id: UUID
    type: str
    title: str
    text_content: Optional[str]
    created_at: datetime
    updated_at: datetime


@router.post("/", response_model=NodeResponse)
async def create_node(node: NodeCreate, db=Depends(get_db)):
    """Create a new node"""

    result = await db.fetchrow(
        """
        INSERT INTO nodes (type, title, text_content, image_url, audio_url, video_url, metadata)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        RETURNING id, type, title, text_content, created_at, updated_at
    """,
        node.type,
        node.title,
        node.text_content,
        node.image_url,
        node.audio_url,
        node.video_url,
        node.metadata,
    )

    # Track access
    await db.execute("SELECT track_node_access($1)", result["id"])

    return NodeResponse(**dict(result))


@router.get("/{node_id}", response_model=NodeResponse)
async def get_node(node_id: UUID, db=Depends(get_db)):
    """Get node by ID"""

    result = await db.fetchrow(
        """
        SELECT id, type, title, text_content, created_at, updated_at
        FROM nodes
        WHERE id = $1
    """,
        node_id,
    )

    if not result:
        raise HTTPException(status_code=404, detail="Node not found")

    # Track access
    await db.execute("SELECT track_node_access($1)", node_id)

    return NodeResponse(**dict(result))


@router.get("/", response_model=List[NodeResponse])
async def list_nodes(
    limit: int = 50,
    offset: int = 0,
    node_type: Optional[str] = None,
    db=Depends(get_db),
):
    """List nodes with pagination"""

    query = """
        SELECT id, type, title, text_content, created_at, updated_at
        FROM nodes
        WHERE ($1::text IS NULL OR type::text = $1)
        ORDER BY created_at DESC
        LIMIT $2 OFFSET $3
    """

    results = await db.fetch(query, node_type, limit, offset)

    return [NodeResponse(**dict(r)) for r in results]


@router.delete("/{node_id}")
async def delete_node(node_id: UUID, db=Depends(get_db)):
    """Delete node"""

    result = await db.execute(
        """
        DELETE FROM nodes WHERE id = $1
    """,
        node_id,
    )

    if result == "DELETE 0":
        raise HTTPException(status_code=404, detail="Node not found")

    return {"status": "deleted", "id": str(node_id)}
