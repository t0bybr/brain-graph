import hashlib
from datetime import datetime
from typing import List, Optional

from app.database import get_db
from app.services.embedding_service import EmbeddingService
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

router = APIRouter()


class EmbeddingCreate(BaseModel):
    node_id: str
    modality: str
    model_name: str
    source_part: str
    embedding: List[float]
    content_hash: Optional[str] = None
    chunk_id: Optional[str] = None
    generation_time_ms: Optional[int] = None
    token_count: Optional[int] = None


class EmbeddingResponse(BaseModel):
    id: str
    node_id: str
    chunk_id: Optional[str] = None
    modality: str
    model_name: str
    source_part: str
    dimension: int
    generated_at: datetime


class GenerateEmbeddingsRequest(BaseModel):
    node_id: str
    model_name: Optional[str] = Field(
        default=None,
        description="Force a specific model; defaults to recommendation or default model",
    )


@router.get("/models")
async def list_models(db=Depends(get_db)):
    """Return available embedding models."""
    service = EmbeddingService(db)
    return await service.list_models()


@router.post("/", response_model=EmbeddingResponse)
async def create_embedding(payload: EmbeddingCreate, db=Depends(get_db)):
    """Store a provided embedding vector."""
    service = EmbeddingService(db)
    content_hash = payload.content_hash or hashlib.sha256(
        ("|".join(str(v) for v in payload.embedding)).encode("utf-8")
    ).hexdigest()

    try:
        row = await service.store_embedding(
            node_id=payload.node_id,
            modality=payload.modality,
            model_name=payload.model_name,
            source_part=payload.source_part,
            embedding=payload.embedding,
            content_hash=content_hash,
            chunk_id=payload.chunk_id,
            generation_time_ms=payload.generation_time_ms,
            token_count=payload.token_count,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    return EmbeddingResponse(**row)


@router.post("/generate", response_model=List[EmbeddingResponse])
async def generate_embeddings(
    payload: GenerateEmbeddingsRequest, db=Depends(get_db)
):
    """Generate embeddings for a node using recommended/default models."""
    service = EmbeddingService(db)
    try:
        rows = await service.generate_for_node(
            node_id=payload.node_id,
            model_name=payload.model_name,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    return [EmbeddingResponse(**row) for row in rows]
