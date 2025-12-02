-- ============================================
-- HNSW Vector Indexes (Post-Data)
-- Run AFTER embeddings exist
-- ============================================

\c brain_graph

-- ============================================
-- HNSW INDEX CREATION FUNCTION
-- ============================================

CREATE OR REPLACE FUNCTION create_hnsw_indexes()
RETURNS TEXT AS $$
DECLARE
    result TEXT := '';
    emb_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO emb_count FROM node_embeddings;
    
    IF emb_count = 0 THEN
        RETURN 'No embeddings yet - HNSW indexes will be created when embeddings are added';
    END IF;
    
    -- Jina (text)
    BEGIN
        CREATE INDEX IF NOT EXISTS idx_emb_jina_hnsw ON node_embeddings
        USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64)
        WHERE model_name = 'jina-embeddings-v2';
        result := result || '✓ Jina HNSW; ';
    EXCEPTION WHEN OTHERS THEN
        result := result || '✗ Jina: ' || SQLERRM || '; ';
    END;

    -- SigLIP (image)
    BEGIN
        CREATE INDEX IF NOT EXISTS idx_emb_siglip_hnsw ON node_embeddings
        USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64)
        WHERE model_name = 'siglip-so400m';
        result := result || '✓ SigLIP HNSW; ';
    EXCEPTION WHEN OTHERS THEN
        result := result || '✗ SigLIP: ' || SQLERRM || '; ';
    END;

    -- CodeBERT (code)
    BEGIN
        CREATE INDEX IF NOT EXISTS idx_emb_codebert_hnsw ON node_embeddings
        USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64)
        WHERE model_name = 'graphcodebert-base';
        result := result || '✓ CodeBERT HNSW; ';
    EXCEPTION WHEN OTHERS THEN
        result := result || '✗ CodeBERT: ' || SQLERRM || '; ';
    END;

    -- Whisper (audio)
    BEGIN
        CREATE INDEX IF NOT EXISTS idx_emb_whisper_hnsw ON node_embeddings
        USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64)
        WHERE model_name = 'whisper-large-v3';
        result := result || '✓ Whisper HNSW; ';
    EXCEPTION WHEN OTHERS THEN
        result := result || '✗ Whisper: ' || SQLERRM || '; ';
    END;

    -- GraphSAGE (graph)
    BEGIN
        CREATE INDEX IF NOT EXISTS idx_emb_graphsage_hnsw ON node_embeddings
        USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64)
        WHERE model_name = 'graphsage';
        result := result || '✓ GraphSAGE HNSW; ';
    EXCEPTION WHEN OTHERS THEN
        result := result || '✗ GraphSAGE: ' || SQLERRM || '; ';
    END;

    RETURN result;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION create_hnsw_indexes IS 'Create HNSW vector indexes (run after embeddings exist)';

-- ============================================
-- TRY TO CREATE INDEXES NOW
-- ============================================

DO $$
DECLARE
    result TEXT;
BEGIN
    SELECT create_hnsw_indexes() INTO result;
    RAISE NOTICE 'HNSW Index Status: %', result;
END $$;

-- ============================================
-- VERIFICATION
-- ============================================

DO $$
DECLARE
    idx RECORD;
BEGIN
    RAISE NOTICE '============================================';
    RAISE NOTICE 'Vector indexes:';
    FOR idx IN 
        SELECT indexname, indexdef 
        FROM pg_indexes 
        WHERE tablename = 'node_embeddings' 
        AND indexdef LIKE '%hnsw%'
    LOOP
        RAISE NOTICE '  • %', idx.indexname;
    END LOOP;
    RAISE NOTICE '============================================';
END $$;
