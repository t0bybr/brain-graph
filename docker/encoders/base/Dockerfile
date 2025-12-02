# =====================================
# Base-Image für alle Encoder-Container
# =====================================
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# System-Dependencies (minimal)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    build-essential \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# Gemeinsame Python-Dependencies:
# - torch (CPU-Variante, passt für deine W5700 ohne ROCm)
# - transformers & Co. für HF-Modelle
# - fastapi/uvicorn, falls die Encoder HTTP-APIs sind
RUN pip install --no-cache-dir \
    torch --index-url https://download.pytorch.org/whl/cpu \
    # torch==2.1.2 \
    "transformers>=4.44.0" \
    sentencepiece \
    sentence-transformers \
    accelerate \
    fastapi \
    "uvicorn[standard]" \
    einops
