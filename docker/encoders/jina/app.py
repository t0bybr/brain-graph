import os
from typing import List

import torch
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from sentence_transformers import SentenceTransformer

app = FastAPI(title="Jina Embeddings Service")

# Configuration
MODEL_NAME = os.getenv("MODEL_NAME", "jinaai/jina-embeddings-v2-base-en")
DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
MAX_BATCH_SIZE = int(os.getenv("MAX_BATCH_SIZE", "32"))

# Load model
print(f"Loading model {MODEL_NAME} on {DEVICE}...")
model = SentenceTransformer(MODEL_NAME, device=DEVICE)
print("Model loaded successfully!")


class EmbedRequest(BaseModel):
    texts: List[str]


class EmbedResponse(BaseModel):
    embeddings: List[List[float]]
    model: str
    dimension: int


@app.get("/health")
async def health():
    return {"status": "healthy", "model": MODEL_NAME, "device": DEVICE}


@app.post("/embed", response_model=EmbedResponse)
async def embed(request: EmbedRequest):
    if len(request.texts) > MAX_BATCH_SIZE:
        raise HTTPException(
            status_code=400,
            detail=f"Batch size {len(request.texts)} exceeds maximum {MAX_BATCH_SIZE}",
        )

    try:
        embeddings = model.encode(
            request.texts, convert_to_numpy=True, show_progress_bar=False
        )

        return EmbedResponse(
            embeddings=embeddings.tolist(),
            model=MODEL_NAME,
            dimension=embeddings.shape[1],
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/")
async def root():
    return {
        "service": "Jina Embeddings",
        "model": MODEL_NAME,
        "dimension": model.get_sentence_embedding_dimension(),
        "max_batch_size": MAX_BATCH_SIZE,
    }
