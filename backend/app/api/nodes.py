from datetime import datetime
from typing import Any, Dict, List, Optional

from app.database import get_db
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

router = APIRouter()


class NodeCreate(BaseModel):
    """Payload for creating a node. IDs are ULIDs generated in the database."""

    type: str
    title: str
    text_content: Optional[str] = None
    image_url: Optional[str] = None
    audio_url: Optional[str] = None
    video_url: Optional[str] = None
    metadata: Dict[str, Any] = Field(default_factory=dict)
    decay_metadata: Optional[Dict[str, Any]] = None
    synthesis_metadata: Optional[Dict[str, Any]] = None


class NodeUpdate(BaseModel):
    """Partial update payload."""

    title: Optional[str] = None
    text_content: Optional[str] = None
    image_url: Optional[str] = None
    audio_url: Optional[str] = None
    video_url: Optional[str] = None
    metadata: Optional[Dict[str, Any]] = None
    decay_metadata: Optional[Dict[str, Any]] = None
    synthesis_metadata: Optional[Dict[str, Any]] = None


class NodeResponse(BaseModel):
    """Minimal node representation returned by the API."""

    id: str
    type: str
    title: str
    text_content: Optional[str]
    image_url: Optional[str] = None
    audio_url: Optional[str] = None
    video_url: Optional[str] = None
    metadata: Dict[str, Any] = Field(default_factory=dict)
    decay_metadata: Optional[Dict[str, Any]] = None
    synthesis_metadata: Optional[Dict[str, Any]] = None
    created_at: datetime
    updated_at: datetime


@router.post("/", response_model=NodeResponse)
async def create_node(node: NodeCreate, db=Depends(get_db)):
    """Create a new node using the ULID primary key from the database."""

    columns = ["type", "title", "metadata"]
    values = [node.type, node.title, node.metadata]

    optional_fields = {
        "text_content": node.text_content,
        "image_url": node.image_url,
        "audio_url": node.audio_url,
        "video_url": node.video_url,
        "decay_metadata": node.decay_metadata,
        "synthesis_metadata": node.synthesis_metadata,
    }

    for col, val in optional_fields.items():
        if val is not None:
            columns.append(col)
            values.append(val)

    placeholders = ", ".join(f"${i+1}" for i in range(len(values)))
    column_list = ", ".join(columns)

    result = await db.fetchrow(
        f"""
        INSERT INTO nodes ({column_list})
        VALUES ({placeholders})
        RETURNING id, type::text AS type, title, text_content, image_url, audio_url, video_url,
                  metadata, decay_metadata, synthesis_metadata, created_at, updated_at
    """,
        *values,
    )

    if not result:
        raise HTTPException(status_code=500, detail="Node could not be created")

    return NodeResponse(**dict(result))


@router.get("/{node_id}", response_model=NodeResponse)
async def get_node(node_id: str, db=Depends(get_db)):
    """Get node by ULID."""

    result = await db.fetchrow(
        """
        SELECT id, type::text AS type, title, text_content, image_url, audio_url, video_url,
               metadata, decay_metadata, synthesis_metadata, created_at, updated_at
        FROM nodes
        WHERE id = $1::text
    """,
        node_id,
    )

    if not result:
        raise HTTPException(status_code=404, detail="Node not found")

    # Track access for decay calculations
    await db.execute("SELECT track_node_access($1)", node_id)

    return NodeResponse(**dict(result))


@router.get("/", response_model=List[NodeResponse])
async def list_nodes(
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    node_type: Optional[str] = Query(None, description="Filter by node_type enum"),
    db=Depends(get_db),
):
    """List nodes with pagination and optional type filter."""

    results = await db.fetch(
        """
        SELECT id, type::text AS type, title, text_content, image_url, audio_url, video_url,
               metadata, decay_metadata, synthesis_metadata, created_at, updated_at
        FROM nodes
        WHERE ($1::text IS NULL OR type::text = $1)
        ORDER BY created_at DESC
        LIMIT $2 OFFSET $3
    """,
        node_type,
        limit,
        offset,
    )

    return [NodeResponse(**dict(r)) for r in results]


@router.patch("/{node_id}", response_model=NodeResponse)
async def update_node(node_id: str, payload: NodeUpdate, db=Depends(get_db)):
    """Partial update for a node."""

    updates = []
    values = []

    for field, value in payload.model_dump(exclude_unset=True).items():
        updates.append(f"{field} = ${len(values) + 1}")
        values.append(value)

    if not updates:
        return await get_node(node_id, db)  # Nothing to update

    values.append(node_id)

    result = await db.fetchrow(
        f"""
        UPDATE nodes
        SET {", ".join(updates)}
        WHERE id = ${len(values)}::text
        RETURNING id, type::text AS type, title, text_content, image_url, audio_url, video_url,
                  metadata, decay_metadata, synthesis_metadata, created_at, updated_at
    """,
        *values,
    )

    if not result:
        raise HTTPException(status_code=404, detail="Node not found")

    return NodeResponse(**dict(result))


@router.delete("/{node_id}")
async def delete_node(node_id: str, db=Depends(get_db)):
    """Delete a node and cascading edges/embeddings."""

    result = await db.execute(
        """
        DELETE FROM nodes WHERE id = $1::text
    """,
        node_id,
    )

    if result == "DELETE 0":
        raise HTTPException(status_code=404, detail="Node not found")

    return {"status": "deleted", "id": node_id}
