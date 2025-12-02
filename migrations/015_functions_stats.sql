-- ============================================
-- Statistics & Monitoring Functions
-- ============================================

\c brain_graph

BEGIN;

-- ============================================
-- GRAPH STATISTICS
-- ============================================

CREATE OR REPLACE FUNCTION get_graph_statistics()
RETURNS TABLE(
    stat_name TEXT,
    stat_value BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 'total_nodes'::TEXT, COUNT(*)::BIGINT FROM nodes
    UNION ALL
    SELECT 'total_chunks'::TEXT, COUNT(*)::BIGINT FROM node_chunks
    UNION ALL
    SELECT 'total_edges'::TEXT, COUNT(*)::BIGINT FROM graph_edges
    UNION ALL
    SELECT 'chunk_edges'::TEXT, COUNT(*)::BIGINT FROM chunk_edges
    UNION ALL
    SELECT 'node_chunk_edges'::TEXT, COUNT(*)::BIGINT FROM node_chunk_edges
    UNION ALL
    SELECT 'total_embeddings'::TEXT, COUNT(*)::BIGINT FROM node_embeddings
    UNION ALL
    SELECT 'node_embeddings'::TEXT, COUNT(*)::BIGINT FROM node_embeddings WHERE chunk_id IS NULL
    UNION ALL
    SELECT 'chunk_embeddings'::TEXT, COUNT(*)::BIGINT FROM node_embeddings WHERE chunk_id IS NOT NULL
    UNION ALL
    SELECT 'active_models'::TEXT, COUNT(*)::BIGINT FROM embedding_models WHERE is_active = TRUE
    UNION ALL
    SELECT 'entities'::TEXT, COUNT(*)::BIGINT FROM entities
    UNION ALL
    SELECT 'documents'::TEXT, COUNT(*)::BIGINT FROM documents
    UNION ALL
    SELECT 'archived_nodes'::TEXT, COUNT(*)::BIGINT FROM nodes
        WHERE (decay_metadata->'lifecycle'->>'archived')::BOOLEAN = TRUE
    UNION ALL
    SELECT 'obsolete_nodes'::TEXT, COUNT(*)::BIGINT FROM nodes
        WHERE (decay_metadata->'lifecycle'->>'marked_obsolete')::BOOLEAN = TRUE;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_graph_statistics IS 'Get key graph statistics for monitoring';

-- ============================================
-- NODE TYPE DISTRIBUTION
-- ============================================

CREATE OR REPLACE FUNCTION get_node_type_distribution()
RETURNS TABLE(
    node_type node_type,
    count BIGINT,
    percentage NUMERIC
) AS $$
DECLARE
    total BIGINT;
BEGIN
    SELECT COUNT(*) INTO total FROM nodes;
    
    RETURN QUERY
    SELECT 
        n.type,
        COUNT(*)::BIGINT,
        ROUND(COUNT(*) * 100.0 / NULLIF(total, 0), 2)
    FROM nodes n
    GROUP BY n.type
    ORDER BY COUNT(*) DESC;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_node_type_distribution IS 'Get distribution of node types';

-- ============================================
-- EMBEDDING COVERAGE
-- ============================================

CREATE OR REPLACE FUNCTION get_embedding_coverage()
RETURNS TABLE(
    model_name TEXT,
    node_embeddings BIGINT,
    chunk_embeddings BIGINT,
    total BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        ne.model_name::TEXT,
        COUNT(*) FILTER (WHERE ne.chunk_id IS NULL)::BIGINT,
        COUNT(*) FILTER (WHERE ne.chunk_id IS NOT NULL)::BIGINT,
        COUNT(*)::BIGINT
    FROM node_embeddings ne
    GROUP BY ne.model_name
    ORDER BY COUNT(*) DESC;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_embedding_coverage IS 'Get embedding coverage by model';

-- ============================================
-- DECAY SCORE DISTRIBUTION
-- ============================================

CREATE OR REPLACE FUNCTION get_decay_distribution()
RETURNS TABLE(
    bucket TEXT,
    count BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        CASE 
            WHEN ns.value >= 0.8 THEN 'high (0.8-1.0)'
            WHEN ns.value >= 0.5 THEN 'medium (0.5-0.8)'
            WHEN ns.value >= 0.2 THEN 'low (0.2-0.5)'
            ELSE 'very_low (0-0.2)'
        END AS bucket,
        COUNT(*)::BIGINT
    FROM node_scores ns
    WHERE ns.score_type = 'decay'
    GROUP BY 1
    ORDER BY 1;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_decay_distribution IS 'Get distribution of decay scores';

-- ============================================
-- HEALTH CHECK
-- ============================================

CREATE OR REPLACE FUNCTION health_check()
RETURNS TABLE(
    check_name TEXT,
    status TEXT,
    details TEXT
) AS $$
DECLARE
    age_available BOOLEAN;
    paradedb_available BOOLEAN;
    temporal_available BOOLEAN;
BEGIN
    -- Check AGE
    SELECT age_cypher_available() INTO age_available;
    RETURN QUERY SELECT 
        'age_extension'::TEXT,
        CASE WHEN age_available THEN 'OK' ELSE 'DISABLED' END,
        CASE WHEN age_available THEN 'Graph queries available' ELSE 'Using relational fallback' END;
    
    -- Check ParadeDB
    SELECT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_search') INTO paradedb_available;
    RETURN QUERY SELECT 
        'paradedb'::TEXT,
        CASE WHEN paradedb_available THEN 'OK' ELSE 'DISABLED' END,
        CASE WHEN paradedb_available THEN 'BM25 search available' ELSE 'Using tsvector fallback' END;
    
    -- Check temporal_tables
    SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'versioning') INTO temporal_available;
    RETURN QUERY SELECT 
        'temporal_tables'::TEXT,
        CASE WHEN temporal_available THEN 'OK' ELSE 'DISABLED' END,
        CASE WHEN temporal_available THEN 'History tracking active' ELSE 'No history tracking' END;
    
    -- Check node count
    RETURN QUERY SELECT 
        'nodes'::TEXT,
        'INFO'::TEXT,
        (SELECT COUNT(*)::TEXT || ' nodes' FROM nodes);
    
    -- Check chunk count
    RETURN QUERY SELECT 
        'chunks'::TEXT,
        'INFO'::TEXT,
        (SELECT COUNT(*)::TEXT || ' chunks' FROM node_chunks);
    
    -- Check embedding count
    RETURN QUERY SELECT 
        'embeddings'::TEXT,
        'INFO'::TEXT,
        (SELECT COUNT(*)::TEXT || ' embeddings' FROM node_embeddings);
    
    -- Check for expired scores
    RETURN QUERY SELECT 
        'expired_scores'::TEXT,
        CASE WHEN (SELECT COUNT(*) FROM node_scores WHERE expires_at < NOW()) > 100 
             THEN 'WARNING' ELSE 'OK' END,
        (SELECT COUNT(*)::TEXT || ' expired scores' FROM node_scores WHERE expires_at < NOW());
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION health_check IS 'System health check for monitoring';

COMMIT;

DO $$
BEGIN
    RAISE NOTICE '✓ Statistics functions created:';
    RAISE NOTICE '  • get_graph_statistics';
    RAISE NOTICE '  • get_node_type_distribution';
    RAISE NOTICE '  • get_embedding_coverage';
    RAISE NOTICE '  • get_decay_distribution';
    RAISE NOTICE '  • health_check';
END $$;
