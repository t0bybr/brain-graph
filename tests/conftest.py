import pytest
import asyncio
import asyncpg
import httpx
from typing import AsyncGenerator
import os

# Test configuration
TEST_DATABASE_URL = os.getenv(
    "TEST_DATABASE_URL",
    "postgresql://postgres:postgres@localhost:5432/brain_graph_test"
)

@pytest.fixture(scope="session")
def event_loop():
    """Create event loop for async tests"""
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()

@pytest.fixture(scope="session")
async def db_pool():
    """Create database connection pool for tests"""
    pool = await asyncpg.create_pool(
        TEST_DATABASE_URL,
        min_size=1,
        max_size=5
    )
    yield pool
    await pool.close()

@pytest.fixture
async def db(db_pool):
    """Get database connection for each test"""
    async with db_pool.acquire() as conn:
        # Start transaction
        tr = conn.transaction()
        await tr.start()

        yield conn

        # Rollback after test
        await tr.rollback()

@pytest.fixture
async def client():
    """HTTP client for API testing"""
    async with httpx.AsyncClient(
        base_url="http://localhost:8000",
        timeout=30.0
    ) as client:
        yield client

@pytest.fixture
def sample_node_data():
    """Sample node data for testing"""
    return {
        "type": "TextNode",
        "title": "Test Node",
        "text_content": "This is test content",
        "metadata": {"test": True}
    }
