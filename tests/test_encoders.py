import httpx
import pytest

ENCODER_URLS = {
    "jina": "http://localhost:8001",
    "siglip": "http://localhost:8002",
    "codebert": "http://localhost:8003",
    "whisper": "http://localhost:8005",
}


@pytest.mark.asyncio
async def test_jina_health():
    """Test Jina encoder health"""
    async with httpx.AsyncClient() as client:
        try:
            response = await client.get(f"{ENCODER_URLS['jina']}/health", timeout=10.0)
            assert response.status_code == 200
            assert response.json()["status"] == "healthy"
        except httpx.ConnectError:
            pytest.skip("Jina encoder not running")


@pytest.mark.asyncio
async def test_jina_embedding():
    """Test Jina text embedding"""
    async with httpx.AsyncClient() as client:
        try:
            response = await client.post(
                f"{ENCODER_URLS['jina']}/embed",
                json={"texts": ["Hello world", "Test text"]},
                timeout=30.0,
            )
            assert response.status_code == 200
            data = response.json()

            assert "embeddings" in data
            assert len(data["embeddings"]) == 2
            assert data["dimension"] == 768
            assert len(data["embeddings"][0]) == 768
        except httpx.ConnectError:
            pytest.skip("Jina encoder not running")


@pytest.mark.asyncio
async def test_siglip_health():
    """Test SigLIP encoder health"""
    async with httpx.AsyncClient() as client:
        try:
            response = await client.get(
                f"{ENCODER_URLS['siglip']}/health", timeout=10.0
            )
            assert response.status_code == 200
            assert response.json()["status"] == "healthy"
        except httpx.ConnectError:
            pytest.skip("SigLIP encoder not running")
