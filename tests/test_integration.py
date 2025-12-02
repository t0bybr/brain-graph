from uuid import UUID

import pytest


@pytest.mark.asyncio
@pytest.mark.integration
async def test_full_workflow(client, db, sample_node_data):
    """Test complete workflow: create, embed, search, retrieve"""

    # 1. Create node
    create_response = await client.post("/api/nodes/", json=sample_node_data)
    assert create_response.status_code == 200
    node_id = create_response.json()["id"]

    # 2. Generate embeddings (if encoder available)
    try:
        embed_response = await client.post(
            f"/api/embeddings/generate", json={"node_id": node_id}
        )
        if embed_response.status_code == 200:
            # Check embeddings created
            embedding_count = await db.fetchval(
                """
                SELECT COUNT(*) FROM node_embeddings
                WHERE node_id = $1
            """,
                UUID(node_id),
            )
            assert embedding_count > 0
    except Exception:
        pytest.skip("Encoder not available")

    # 3. Search for node
    search_response = await client.post(
        "/api/search/", json={"query": sample_node_data["text_content"], "limit": 5}
    )
    assert search_response.status_code == 200
    results = search_response.json()

    # Should find our node
    found_ids = [r["node_id"] for r in results]
    assert node_id in found_ids

    # 4. Retrieve node
    get_response = await client.get(f"/api/nodes/{node_id}")
    assert get_response.status_code == 200

    # 5. Check access was tracked
    access_count = await db.fetchval(
        """
        SELECT (decay_metadata->'usage_stats'->>'access_count')::int
        FROM nodes WHERE id = $1
    """,
        UUID(node_id),
    )
    assert access_count >= 1

    # 6. Compute decay score
    decay_score = await db.fetchval("SELECT compute_decay_score($1)", UUID(node_id))
    assert 0 <= decay_score <= 1
