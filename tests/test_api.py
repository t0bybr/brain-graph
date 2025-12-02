import pytest


@pytest.mark.asyncio
async def test_health_endpoint(client):
    """Test health check endpoint"""
    response = await client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"


@pytest.mark.asyncio
async def test_create_node_api(client, sample_node_data):
    """Test node creation via API"""
    response = await client.post("/api/nodes/", json=sample_node_data)

    assert response.status_code == 200
    data = response.json()

    assert "id" in data
    assert isinstance(data["id"], str)
    assert len(data["id"]) == 26  # ULID length
    assert data["type"] == sample_node_data["type"]
    assert data["title"] == sample_node_data["title"]


@pytest.mark.asyncio
async def test_get_node_api(client, sample_node_data):
    """Test getting node via API"""
    # Create node first
    create_response = await client.post("/api/nodes/", json=sample_node_data)
    node_id = create_response.json()["id"]

    # Get node
    response = await client.get(f"/api/nodes/{node_id}")

    assert response.status_code == 200
    data = response.json()
    assert data["id"] == node_id
    assert data["title"] == sample_node_data["title"]


@pytest.mark.asyncio
async def test_list_nodes_api(client, sample_node_data):
    """Test listing nodes via API"""
    # Create a few nodes
    for i in range(3):
        node_data = sample_node_data.copy()
        node_data["title"] = f"Test Node {i}"
        await client.post("/api/nodes/", json=node_data)

    # List nodes
    response = await client.get("/api/nodes/")

    assert response.status_code == 200
    data = response.json()
    assert len(data) >= 3


@pytest.mark.asyncio
async def test_delete_node_api(client, sample_node_data):
    """Test deleting node via API"""
    # Create node
    create_response = await client.post("/api/nodes/", json=sample_node_data)
    node_id = create_response.json()["id"]

    # Delete node
    response = await client.delete(f"/api/nodes/{node_id}")

    assert response.status_code == 200
    assert response.json()["status"] == "deleted"

    # Verify deletion
    get_response = await client.get(f"/api/nodes/{node_id}")
    assert get_response.status_code == 404


@pytest.mark.asyncio
async def test_search_api(client, sample_node_data):
    """Test search endpoint"""
    # Create test nodes
    for i in range(5):
        node_data = sample_node_data.copy()
        node_data["title"] = f"Search Test {i}"
        node_data["text_content"] = f"Content about artificial intelligence {i}"
        await client.post("/api/nodes/", json=node_data)

    # Search
    response = await client.post(
        "/api/search/", json={"query": "artificial intelligence", "limit": 10}
    )

    assert response.status_code == 200
    results = response.json()
    assert len(results) > 0
    assert "node_id" in results[0]
    assert "similarity" in results[0] or "bm25_score" in results[0]
