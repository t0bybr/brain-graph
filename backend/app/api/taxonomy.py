from datetime import datetime
from typing import Any, Dict, List, Literal, Optional

from app.database import get_db
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

router = APIRouter()


class CategoryCreate(BaseModel):
    name: str
    path: str = Field(
        description="Slash separated path, e.g. 'tech/programming/python'"
    )
    parent_id: Optional[int] = None
    topic_importance: int = Field(default=5, ge=1, le=10)
    change_velocity: int = Field(default=5, ge=1, le=10)
    usage_focus: int = Field(default=5, ge=1, le=10)
    keywords: List[str] = Field(default_factory=list)
    related_categories: List[Any] = Field(default_factory=list)


class CategoryResponse(BaseModel):
    id: int
    name: str
    path: str
    level: int
    parent_id: Optional[int] = None
    topic_importance: int
    change_velocity: int
    usage_focus: int
    keywords: List[str] = Field(default_factory=list)
    related_categories: List[Any] = Field(default_factory=list)
    created_at: datetime


class NodeCategoryAssignment(BaseModel):
    node_id: str
    category_id: int
    confidence: float = Field(default=1.0, ge=0.0, le=1.0)
    assigned_by: Literal["user", "llm"] = Field(default="user", description="user|llm")


class NodeCategoryResponse(BaseModel):
    node_id: str
    category: CategoryResponse
    confidence: float
    assigned_by: str
    assigned_at: datetime


def _level_from_path(path: str) -> int:
    """Translate a path like 'a/b/c' into a hierarchy level (0-indexed)."""
    segments = [p for p in path.split("/") if p]
    return max(len(segments) - 1, 0)


@router.get("/", response_model=List[CategoryResponse])
async def list_categories(db=Depends(get_db)):
    """List all taxonomy categories ordered by path."""

    rows = await db.fetch(
        """
        SELECT id, name, path, level, parent_id, topic_importance,
               change_velocity, usage_focus, keywords, related_categories, created_at
        FROM taxonomy
        ORDER BY path
    """
    )
    return [CategoryResponse(**dict(r)) for r in rows]


@router.get("/{category_id}", response_model=CategoryResponse)
async def get_category(category_id: int, db=Depends(get_db)):
    """Get a single taxonomy category."""

    row = await db.fetchrow(
        """
        SELECT id, name, path, level, parent_id, topic_importance,
               change_velocity, usage_focus, keywords, related_categories, created_at
        FROM taxonomy
        WHERE id = $1
    """,
        category_id,
    )

    if not row:
        raise HTTPException(status_code=404, detail="Category not found")

    return CategoryResponse(**dict(row))


@router.post("/", response_model=CategoryResponse)
async def create_category(payload: CategoryCreate, db=Depends(get_db)):
    """Create a taxonomy category. Level is derived from the provided path."""

    level = _level_from_path(payload.path)
    if level > 5:
        raise HTTPException(
            status_code=400, detail="Maximum supported taxonomy depth is 5"
        )

    row = await db.fetchrow(
        """
        INSERT INTO taxonomy (
            name, parent_id, level, path, topic_importance,
            change_velocity, usage_focus, keywords, related_categories
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        RETURNING id, name, path, level, parent_id, topic_importance,
                  change_velocity, usage_focus, keywords, related_categories, created_at
    """,
        payload.name,
        payload.parent_id,
        level,
        payload.path,
        payload.topic_importance,
        payload.change_velocity,
        payload.usage_focus,
        payload.keywords,
        payload.related_categories,
    )

    if not row:
        raise HTTPException(status_code=500, detail="Category could not be created")

    return CategoryResponse(**dict(row))


@router.post("/assign", response_model=NodeCategoryResponse)
async def assign_category(assignment: NodeCategoryAssignment, db=Depends(get_db)):
    """Assign a taxonomy category to a node with confidence."""

    row = await db.fetchrow(
        """
        INSERT INTO node_categories (node_id, category_id, confidence, assigned_by)
        VALUES ($1::text, $2, $3, $4)
        ON CONFLICT (node_id, category_id) DO UPDATE
        SET confidence = EXCLUDED.confidence,
            assigned_by = EXCLUDED.assigned_by,
            assigned_at = NOW()
        RETURNING node_id, category_id, confidence, assigned_by, assigned_at
    """,
        assignment.node_id,
        assignment.category_id,
        assignment.confidence,
        assignment.assigned_by,
    )

    if not row:
        raise HTTPException(status_code=500, detail="Could not assign category")

    category = await get_category(row["category_id"], db)

    return NodeCategoryResponse(
        node_id=row["node_id"],
        category=category,
        confidence=row["confidence"],
        assigned_by=row["assigned_by"],
        assigned_at=row["assigned_at"],
    )


@router.get("/node/{node_id}", response_model=List[NodeCategoryResponse])
async def list_node_categories(
    node_id: str,
    db=Depends(get_db),
):
    """List categories linked to a node."""

    rows = await db.fetch(
        """
        SELECT nc.node_id,
               nc.category_id,
               nc.confidence,
               nc.assigned_by,
               nc.assigned_at,
               t.id,
               t.name,
               t.path,
               t.level,
               t.parent_id,
               t.topic_importance,
               t.change_velocity,
               t.usage_focus,
               t.keywords,
               t.related_categories,
               t.created_at
        FROM node_categories nc
        JOIN taxonomy t ON t.id = nc.category_id
        WHERE nc.node_id = $1::text
        ORDER BY t.path
    """,
        node_id,
    )

    return [
        NodeCategoryResponse(
            node_id=row["node_id"],
            category=CategoryResponse(
                id=row["id"],
                name=row["name"],
                path=row["path"],
                level=row["level"],
                parent_id=row["parent_id"],
                topic_importance=row["topic_importance"],
                change_velocity=row["change_velocity"],
                usage_focus=row["usage_focus"],
                keywords=row["keywords"],
                related_categories=row["related_categories"],
                created_at=row["created_at"],
            ),
            confidence=row["confidence"],
            assigned_by=row["assigned_by"],
            assigned_at=row["assigned_at"],
        )
        for row in rows
    ]


@router.delete("/assign")
async def remove_assignment(
    node_id: str = Query(...),
    category_id: int = Query(...),
    db=Depends(get_db),
):
    """Remove a node/category assignment."""

    result = await db.execute(
        """
        DELETE FROM node_categories
        WHERE node_id = $1::text AND category_id = $2
    """,
        node_id,
        category_id,
    )

    if result == "DELETE 0":
        raise HTTPException(status_code=404, detail="Assignment not found")

    return {"status": "deleted", "node_id": node_id, "category_id": category_id}
