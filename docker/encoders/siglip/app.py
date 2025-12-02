import os
from io import BytesIO
from typing import List, Union

import requests
import torch
from fastapi import FastAPI, HTTPException
from PIL import Image
from pydantic import BaseModel
from transformers import AutoModel, AutoProcessor

app = FastAPI(title="SigLIP Vision Encoder")

MODEL_NAME = os.getenv("MODEL_NAME", "google/siglip-so400m-patch14-384")
DEVICE = "cuda" if torch.cuda.is_available() else "cpu"

print(f"Loading model {MODEL_NAME} on {DEVICE}...")
processor = AutoProcessor.from_pretrained(MODEL_NAME)
model = AutoModel.from_pretrained(MODEL_NAME).to(DEVICE)
model.eval()
print("Model loaded successfully!")


class EmbedRequest(BaseModel):
    images: List[str]  # URLs or base64


class EmbedResponse(BaseModel):
    embeddings: List[List[float]]
    model: str
    dimension: int


def load_image(image_source: str) -> Image.Image:
    if image_source.startswith("http"):
        response = requests.get(image_source)
        return Image.open(BytesIO(response.content)).convert("RGB")
    else:
        # Assume file path
        return Image.open(image_source).convert("RGB")


@app.get("/health")
async def health():
    return {"status": "healthy", "model": MODEL_NAME, "device": DEVICE}


@app.post("/embed", response_model=EmbedResponse)
async def embed(request: EmbedRequest):
    try:
        images = [load_image(img) for img in request.images]

        inputs = processor(images=images, return_tensors="pt", padding=True)
        inputs = {k: v.to(DEVICE) for k, v in inputs.items()}

        with torch.no_grad():
            outputs = model.get_image_features(**inputs)
            embeddings = outputs.cpu().numpy()

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
        "service": "SigLIP Vision Encoder",
        "model": MODEL_NAME,
        "dimension": model.config.vision_config.hidden_size,
    }
