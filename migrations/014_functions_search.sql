-- ============================================
-- Search Functions: Hybrid, Vector, Chunks
-- ============================================

\c brain_graph

BEGIN;

-- ============================================
-- CHUNK HELPER FUNCTIONS
-- ============================================

-- Get chunks with context (PREV/NEXT)
CREATE OR REPLACE FUNCTION get_chunk_with_context(
    p_chunk_id TEXT,
    p_context_before INTEGER DEFAULT 1,
    p_context_after INTEGER DEFAULT 1
)
RETURNS TABLE (
    chunk_id TEXT,
    node_id TEXT,
    chunk_index INTEGER,
    content TEXT,
    summary TEXT,
    is_target BOOLEAN
) AS $$
DECLARE
    v_node_id TEXT;
    v_chunk_index INTEGER;
BEGIN
    -- Get target chunk info
    SELECT nc.node_id, nc.chunk_index 
    INTO v_node_id, v_chunk_index
    FROM node_chunks nc 
    WHERE nc.id = p_chunk_id;
    
    IF NOT FOUND THEN
        RETURN;
    END IF;
    
    -- Return context window
    RETURN QUERY
    SELECT 
        nc.id,
        nc.node_id,
        nc.chunk_index,
        nc.content,
        nc.summary,
        (nc.id = p_chunk_id) AS is_target
    FROM node_chunks nc
    WHERE nc.node_id = v_node_id
      AND nc.chunk_index BETWEEN (v_chunk_index - p_context_before) 
                              AND (v_chunk_index + p_context_after)
    ORDER BY nc.chunk_index;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION get_chunk_with_context IS 'Get a chunk with surrounding context chunks for RAG';

-- Get all chunks for a node
CREATE OR REPLACE FUNCTION get_node_chunks(p_node_id TEXT)
RETURNS TABLE (
    chunk_id TEXT,
    chunk_index INTEGER,
    content TEXT,
    summary TEXT,
    keywords TEXT[],
    heading TEXT,
    token_count INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        nc.id,
        nc.chunk_index,
        nc.content,
        nc.summary,
        nc.keywords,
        nc.heading,
        nc.token_count
    FROM node_chunks nc
    WHERE nc.node_id = p_node_id
    ORDER BY nc.chunk_index;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION get_node_chunks IS 'Get all chunks for a node in order';

-- Auto-create NEXT/PREV/CONTAINS edges
CREATE OR REPLACE FUNCTION create_chunk_sequence_edges(p_node_id TEXT)
RETURNS INTEGER AS $$
DECLARE
    edge_count INTEGER := 0;
    prev_chunk_id TEXT := NULL;
    curr RECORD;
BEGIN
    -- First: Create CONTAINS edges from node to all chunks
    INSERT INTO node_chunk_edges (node_id, chunk_id, edge_type)
    SELECT p_node_id, id, 'CONTAINS'
    FROM node_chunks 
    WHERE node_id = p_node_id
    ON CONFLICT (node_id, chunk_id, edge_type) DO NOTHING;
    
    -- Then: Create NEXT/PREV edges between chunks
    FOR curr IN 
        SELECT id FROM node_chunks 
        WHERE node_id = p_node_id 
        ORDER BY chunk_index
    LOOP
        IF prev_chunk_id IS NOT NULL THEN
            -- Create NEXT edge (prev → curr)
            INSERT INTO chunk_edges (source_chunk_id, target_chunk_id, edge_type, created_by)
            VALUES (prev_chunk_id, curr.id, 'NEXT', 'system')
            ON CONFLICT (source_chunk_id, target_chunk_id, edge_type) DO NOTHING;
            
            -- Create PREV edge (curr → prev)
            INSERT INTO chunk_edges (source_chunk_id, target_chunk_id, edge_type, created_by)
            VALUES (curr.id, prev_chunk_id, 'PREV', 'system')
            ON CONFLICT (source_chunk_id, target_chunk_id, edge_type) DO NOTHING;
            
            edge_count := edge_count + 2;
        END IF;
        prev_chunk_id := curr.id;
    END LOOP;
    
    RETURN edge_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION create_chunk_sequence_edges IS 'Auto-create CONTAINS + NEXT/PREV edges for a node''s chunks';

-- ============================================
-- CHUNK SEARCH (BM25)
-- ============================================

CREATE OR REPLACE FUNCTION search_chunks(
    p_query TEXT,
    p_node_types node_type[] DEFAULT NULL,
    p_language VARCHAR(10) DEFAULT 'en',
    p_limit INTEGER DEFAULT 20,
    p_include_context BOOLEAN DEFAULT TRUE,
    p_context_size INTEGER DEFAULT 1
)
RETURNS TABLE (
    chunk_id TEXT,
    node_id TEXT,
    node_title TEXT,
    chunk_index INTEGER,
    content TEXT,
    summary TEXT,
    heading TEXT,
    bm25_score REAL,
    context_before TEXT,
    context_after TEXT
) AS $$
BEGIN
    RETURN QUERY
    WITH ranked_chunks AS (
        SELECT 
            nc.id AS cid,
            nc.node_id AS nid,
            n.title AS ntitle,
            nc.chunk_index AS cidx,
            nc.content AS ccontent,
            nc.summary AS csummary,
            nc.heading AS cheading,
            ts_rank_cd(
                CASE WHEN p_language = 'de' 
                     THEN to_tsvector('german', nc.content)
                     ELSE to_tsvector('english', nc.content)
                END,
                CASE WHEN p_language = 'de'
                     THEN plainto_tsquery('german', p_query)
                     ELSE plainto_tsquery('english', p_query)
                END
            ) AS score
        FROM node_chunks nc
        JOIN nodes n ON nc.node_id = n.id
        WHERE (
            CASE WHEN p_language = 'de'
                 THEN to_tsvector('german', nc.content) @@ plainto_tsquery('german', p_query)
                 ELSE to_tsvector('english', nc.content) @@ plainto_tsquery('english', p_query)
            END
            OR nc.keywords && string_to_array(p_query, ' ')
        )
        AND (p_node_types IS NULL OR n.type = ANY(p_node_types))
        ORDER BY score DESC
        LIMIT p_limit
    )
    SELECT 
        rc.cid,
        rc.nid,
        rc.ntitle,
        rc.cidx,
        rc.ccontent,
        rc.csummary,
        rc.cheading,
        rc.score,
        CASE WHEN p_include_context THEN (
            SELECT string_agg(nc2.content, ' ' ORDER BY nc2.chunk_index)
            FROM node_chunks nc2
            WHERE nc2.node_id = rc.nid 
              AND nc2.chunk_index BETWEEN rc.cidx - p_context_size AND rc.cidx - 1
        ) END AS ctx_before,
        CASE WHEN p_include_context THEN (
            SELECT string_agg(nc2.content, ' ' ORDER BY nc2.chunk_index)
            FROM node_chunks nc2
            WHERE nc2.node_id = rc.nid 
              AND nc2.chunk_index BETWEEN rc.cidx + 1 AND rc.cidx + p_context_size
        ) END AS ctx_after
    FROM ranked_chunks rc;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION search_chunks IS 'BM25 search on chunks with optional context expansion';

-- ============================================
-- HYBRID SEARCH ON CHUNKS
-- ============================================

CREATE OR REPLACE FUNCTION hybrid_search_chunks(
    p_query TEXT,
    p_query_embedding vector,
    p_model_name VARCHAR(100) DEFAULT 'jina-embeddings-v2',
    p_alpha FLOAT DEFAULT 0.5,          -- 0 = BM25 only, 1 = vector only
    p_limit INTEGER DEFAULT 20,
    p_language VARCHAR(10) DEFAULT 'en'
)
RETURNS TABLE (
    chunk_id TEXT,
    node_id TEXT,
    node_title TEXT,
    content TEXT,
    summary TEXT,
    bm25_score FLOAT,
    vector_score FLOAT,
    hybrid_score FLOAT
) AS $$
BEGIN
    RETURN QUERY
    WITH bm25_results AS (
        SELECT 
            nc.id AS cid,
            ts_rank_cd(
                to_tsvector(CASE WHEN p_language = 'de' THEN 'german' ELSE 'english' END, nc.content),
                plainto_tsquery(CASE WHEN p_language = 'de' THEN 'german' ELSE 'english' END, p_query)
            ) AS bm25_sc
        FROM node_chunks nc
        WHERE to_tsvector(CASE WHEN p_language = 'de' THEN 'german' ELSE 'english' END, nc.content) 
              @@ plainto_tsquery(CASE WHEN p_language = 'de' THEN 'german' ELSE 'english' END, p_query)
    ),
    vector_results AS (
        SELECT 
            ne.chunk_id AS cid,
            1 - (ne.embedding <=> p_query_embedding) AS vec_sc
        FROM node_embeddings ne
        WHERE ne.chunk_id IS NOT NULL
          AND ne.model_name = p_model_name
          AND ne.source_part = 'chunk:content'
        ORDER BY ne.embedding <=> p_query_embedding
        LIMIT p_limit * 3
    ),
    combined AS (
        SELECT 
            COALESCE(b.cid, v.cid) AS cid,
            COALESCE(b.bm25_sc, 0) AS bm25_sc,
            COALESCE(v.vec_sc, 0) AS vec_sc,
            (1 - p_alpha) * COALESCE(b.bm25_sc, 0) + p_alpha * COALESCE(v.vec_sc, 0) AS hybrid
        FROM bm25_results b
        FULL OUTER JOIN vector_results v ON b.cid = v.cid
    )
    SELECT 
        c.cid,
        nc.node_id,
        n.title,
        nc.content,
        nc.summary,
        c.bm25_sc,
        c.vec_sc,
        c.hybrid
    FROM combined c
    JOIN node_chunks nc ON c.cid = nc.id
    JOIN nodes n ON nc.node_id = n.id
    ORDER BY c.hybrid DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION hybrid_search_chunks IS 'Hybrid BM25 + vector search on chunks';

-- ============================================
-- HYBRID SEARCH ON NODES (legacy/convenience)
-- ============================================

CREATE OR REPLACE FUNCTION hybrid_search(
    p_query TEXT,
    p_query_embedding vector,
    p_model_name VARCHAR(100) DEFAULT 'jina-embeddings-v2',
    p_alpha FLOAT DEFAULT 0.5,
    p_limit INTEGER DEFAULT 20,
    p_node_types node_type[] DEFAULT NULL
)
RETURNS TABLE (
    node_id TEXT,
    node_type node_type,
    title TEXT,
    bm25_score FLOAT,
    vector_score FLOAT,
    hybrid_score FLOAT
) AS $$
BEGIN
    RETURN QUERY
    WITH bm25_results AS (
        SELECT 
            n.id AS nid,
            ts_rank_cd(
                to_tsvector('english', COALESCE(n.title, '') || ' ' || COALESCE(n.text_content, '')),
                plainto_tsquery('english', p_query)
            ) AS bm25_sc
        FROM nodes n
        WHERE to_tsvector('english', COALESCE(n.title, '') || ' ' || COALESCE(n.text_content, '')) 
              @@ plainto_tsquery('english', p_query)
        AND (p_node_types IS NULL OR n.type = ANY(p_node_types))
    ),
    vector_results AS (
        SELECT 
            ne.node_id AS nid,
            1 - (ne.embedding <=> p_query_embedding) AS vec_sc
        FROM node_embeddings ne
        WHERE ne.model_name = p_model_name
          AND ne.chunk_id IS NULL  -- Node-level embeddings only
          AND ne.source_part IN ('full', 'title', 'summary')
        ORDER BY ne.embedding <=> p_query_embedding
        LIMIT p_limit * 3
    ),
    combined AS (
        SELECT 
            COALESCE(b.nid, v.nid) AS nid,
            COALESCE(b.bm25_sc, 0) AS bm25_sc,
            COALESCE(v.vec_sc, 0) AS vec_sc,
            (1 - p_alpha) * COALESCE(b.bm25_sc, 0) + p_alpha * COALESCE(v.vec_sc, 0) AS hybrid
        FROM bm25_results b
        FULL OUTER JOIN vector_results v ON b.nid = v.nid
    )
    SELECT 
        c.nid,
        n.type,
        n.title,
        c.bm25_sc,
        c.vec_sc,
        c.hybrid
    FROM combined c
    JOIN nodes n ON c.nid = n.id
    WHERE (p_node_types IS NULL OR n.type = ANY(p_node_types))
    ORDER BY c.hybrid DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION hybrid_search IS 'Hybrid BM25 + vector search on nodes (use hybrid_search_chunks for chunk-level)';

-- ============================================
-- MODEL SELECTION
-- ============================================

CREATE OR REPLACE FUNCTION get_models_for_node(p_node_type node_type)
RETURNS TABLE(
    model_name TEXT,
    source_part TEXT,
    priority INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT m.model_name::TEXT, m.source_part::TEXT, m.priority
    FROM (
        VALUES
            -- Text nodes
            ('TextNode', 'jina-embeddings-v2', 'full', 1),
            ('TextNode', 'jina-embeddings-v2', 'title', 2),
            
            -- Image nodes
            ('ImageNode', 'siglip-so400m', 'visual', 1),
            ('ImageNode', 'jina-embeddings-v2', 'title', 2),
            
            -- Audio nodes
            ('AudioNode', 'whisper-large-v3', 'audio', 1),
            ('AudioNode', 'jina-embeddings-v2', 'title', 2),
            
            -- Code-related
            ('TextNode', 'graphcodebert-base', 'full', 3),
            
            -- Knowledge nodes
            ('BookNode', 'jina-embeddings-v2', 'summary', 1),
            ('PaperNode', 'jina-embeddings-v2', 'summary', 1),
            ('ArticleNode', 'jina-embeddings-v2', 'summary', 1)
    ) AS m(node_type, model_name, source_part, priority)
    WHERE m.node_type = p_node_type::TEXT
    ORDER BY m.priority;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION get_models_for_node IS 'Get recommended embedding models for a node type';

COMMIT;

DO $$
BEGIN
    RAISE NOTICE '✓ Search functions created:';
    RAISE NOTICE '  • get_chunk_with_context / get_node_chunks';
    RAISE NOTICE '  • create_chunk_sequence_edges';
    RAISE NOTICE '  • search_chunks (BM25)';
    RAISE NOTICE '  • hybrid_search_chunks';
    RAISE NOTICE '  • hybrid_search (node-level)';
    RAISE NOTICE '  • get_models_for_node';
END $$;
