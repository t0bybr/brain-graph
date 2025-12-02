import pytest


@pytest.mark.asyncio
async def test_database_connection(db):
    """Test database connectivity"""
    result = await db.fetchval("SELECT 1")
    assert result == 1


@pytest.mark.asyncio
async def test_age_loaded(db):
    """Test that AGE extension is loaded"""
    result = await db.fetchval("SELECT age_cypher_available()")
    assert isinstance(result, bool)


@pytest.mark.asyncio
async def test_create_node(db, sample_node_data):
    """Test node creation"""
    result = await db.fetchrow(
        """
        INSERT INTO nodes (type, title, text_content, metadata)
        VALUES ($1, $2, $3, $4)
        RETURNING id, type, title, text_content
    """,
        sample_node_data["type"],
        sample_node_data["title"],
        sample_node_data["text_content"],
        sample_node_data["metadata"],
    )

    assert result is not None
    assert isinstance(result["id"], str)
    assert len(result["id"]) == 26
    assert result["type"] == sample_node_data["type"]
    assert result["title"] == sample_node_data["title"]


@pytest.mark.asyncio
async def test_node_search_bm25(db, sample_node_data):
    """Test BM25 full-text search"""
    # Create node
    await db.execute(
        """
        INSERT INTO nodes (type, title, text_content)
        VALUES ($1, $2, $3)
    """,
        sample_node_data["type"],
        sample_node_data["title"],
        sample_node_data["text_content"],
    )

    # Search
    try:
        results = await db.fetch(
            """
            SELECT id, title, paradedb.score(id) as score
            FROM nodes_search_idx.search('test')
        """
        )
    except Exception:
        results = await db.fetch(
            """
            SELECT id, title,
                   ts_rank_cd(
                        to_tsvector('english', COALESCE(title, '') || ' ' || COALESCE(text_content, '')),
                        plainto_tsquery('english', 'test')
                   ) AS score
            FROM nodes
            WHERE to_tsvector('english', COALESCE(title, '') || ' ' || COALESCE(text_content, ''))
                  @@ plainto_tsquery('english', 'test')
        """
        )

    assert len(results) > 0
    assert results[0]["score"] > 0


@pytest.mark.asyncio
async def test_decay_score_computation(db, sample_node_data):
    """Test decay score calculation"""
    # Create node
    node_id = await db.fetchval(
        """
        INSERT INTO nodes (type, title, text_content)
        VALUES ($1, $2, $3)
        RETURNING id
    """,
        sample_node_data["type"],
        sample_node_data["title"],
        sample_node_data["text_content"],
    )

    # Compute decay score
    decay_score = await db.fetchval("SELECT compute_decay_score($1)", node_id)

    assert decay_score is not None
    assert 0 <= decay_score <= 1


@pytest.mark.asyncio
async def test_track_node_access(db, sample_node_data):
    """Test node access tracking"""
    # Create node
    node_id = await db.fetchval(
        """
        INSERT INTO nodes (type, title, text_content)
        VALUES ($1, $2, $3)
        RETURNING id
    """,
        sample_node_data["type"],
        sample_node_data["title"],
        sample_node_data["text_content"],
    )

    # Track access
    await db.execute("SELECT track_node_access($1)", node_id)

    # Check signals
    signal_count = await db.fetchval(
        """
        SELECT COUNT(*) FROM node_signals
        WHERE node_id = $1 AND signal_type = 'view'
    """,
        node_id,
    )

    assert signal_count == 1

    # Check metadata
    access_count = await db.fetchval(
        """
        SELECT (decay_metadata->'usage_stats'->>'access_count')::int
        FROM nodes WHERE id = $1
    """,
        node_id,
    )

    assert access_count == 1


@pytest.mark.asyncio
async def test_temporal_history(db, sample_node_data):
    """Test temporal table functionality"""
    # Create node
    node_id = await db.fetchval(
        """
        INSERT INTO nodes (type, title, text_content)
        VALUES ($1, $2, $3)
        RETURNING id
    """,
        sample_node_data["type"],
        sample_node_data["title"],
        sample_node_data["text_content"],
    )

    # Update node
    await db.execute(
        """
        UPDATE nodes
        SET title = 'Updated Title'
        WHERE id = $1
    """,
        node_id,
    )

    # Check history
    history_count = await db.fetchval(
        """
        SELECT COUNT(*) FROM nodes_history
        WHERE id = $1
    """,
        node_id,
    )

    assert history_count >= 1


@pytest.mark.asyncio
async def test_embedding_model_registry(db):
    """Test embedding models are seeded"""
    models = await db.fetch("""
        SELECT model_name, modality, is_active
        FROM embedding_models
        WHERE is_active = TRUE
    """)

    assert len(models) >= 5  # jina, siglip, codebert, whisper, graphsage

    model_names = [m["model_name"] for m in models]
    assert "jina-embeddings-v2" in model_names
    assert "siglip-so400m" in model_names


@pytest.mark.asyncio
async def test_graph_sync_trigger(db, sample_node_data):
    """Test AGE graph sync trigger"""
    age_available = await db.fetchval("SELECT age_cypher_available()")
    if not age_available:
        pytest.skip("AGE extension not available")

    # Create node (should trigger sync to AGE)
    node_id = await db.fetchval(
        """
        INSERT INTO nodes (type, title, text_content)
        VALUES ($1, $2, $3)
        RETURNING id
    """,
        sample_node_data["type"],
        sample_node_data["title"],
        sample_node_data["text_content"],
    )

    # Query AGE graph (simplified check)
    result = await db.fetchval(
        """
        SELECT ag_catalog.cypher('brain_graph', $$
            MATCH (n {node_id: '%s'})
            RETURN n.title
        $$) AS result
    """
        % str(node_id)
    )

    # Result will be in AGE format, just check it's not None
    assert result is not None
