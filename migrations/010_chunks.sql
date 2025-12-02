-- ============================================
-- Chunks: Semantic Chunking with Graph Edges
-- ============================================

\c brain_graph

BEGIN;

-- ============================================
-- NODE CHUNKS TABLE
-- ============================================

CREATE TABLE IF NOT EXISTS node_chunks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    node_id UUID NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
    
    -- Position & Ordering
    chunk_index INTEGER NOT NULL,
    
    -- Content
    content TEXT NOT NULL,
    summary TEXT,              -- LLM-generated one-sentence summary
    keywords TEXT[],           -- Extracted keywords for BM25/facets
    
    -- Language (for FTS)
    language VARCHAR(10) DEFAULT 'en',
    
    -- Position in original document
    char_start INTEGER,
    char_end INTEGER,
    token_count INTEGER,
    
    -- Chunking strategy
    chunking_method chunking_method NOT NULL,
    overlap_tokens INTEGER DEFAULT 0,
    
    -- Structure info
    section_path TEXT,         -- "Chapter 3 > Methods > 2.1"
    heading TEXT,              -- Nearest heading above
    
    -- Code-specific (for code_ast, code_function, code_class)
    code_metadata JSONB,       -- {"language": "python", "symbol": "UserService.get_user", "type": "method"}
    
    -- Timestamps
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    
    UNIQUE (node_id, chunk_index)
);

-- ============================================
-- CHUNK INDEXES
-- ============================================

-- Primary access patterns
CREATE INDEX IF NOT EXISTS idx_chunks_node_idx ON node_chunks(node_id, chunk_index);
CREATE INDEX IF NOT EXISTS idx_chunks_node ON node_chunks(node_id);

-- Keyword search
CREATE INDEX IF NOT EXISTS idx_chunks_keywords ON node_chunks USING GIN (keywords);

-- Code chunks
CREATE INDEX IF NOT EXISTS idx_chunks_code ON node_chunks USING GIN (code_metadata) 
    WHERE code_metadata IS NOT NULL;

-- Chunking method filter
CREATE INDEX IF NOT EXISTS idx_chunks_method ON node_chunks(chunking_method);

-- FTS on summary (English)
CREATE INDEX IF NOT EXISTS idx_chunks_summary_fts ON node_chunks 
    USING GIN (to_tsvector('english', COALESCE(summary, '')));

-- FTS on content (English)
CREATE INDEX IF NOT EXISTS idx_chunks_content_fts ON node_chunks 
    USING GIN (to_tsvector('english', content));

-- German FTS indexes (conditional)
CREATE INDEX IF NOT EXISTS idx_chunks_content_fts_de ON node_chunks 
    USING GIN (to_tsvector('german', content))
    WHERE language = 'de';

CREATE INDEX IF NOT EXISTS idx_chunks_summary_fts_de ON node_chunks 
    USING GIN (to_tsvector('german', COALESCE(summary, '')))
    WHERE language = 'de';

-- ============================================
-- COMMENTS
-- ============================================

COMMENT ON TABLE node_chunks IS 'Semantic chunks for fine-grained retrieval. Linked via chunk_edges.';
COMMENT ON COLUMN node_chunks.summary IS 'LLM-generated one-sentence summary for compact embeddings';
COMMENT ON COLUMN node_chunks.keywords IS 'Extracted keywords for BM25 boost and faceted search';
COMMENT ON COLUMN node_chunks.code_metadata IS 'For code: language, symbol name, type (class/method/function)';

-- ============================================
-- CHUNK EDGES (Chunk-to-Chunk relationships)
-- ============================================

CREATE TABLE IF NOT EXISTS chunk_edges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_chunk_id UUID NOT NULL REFERENCES node_chunks(id) ON DELETE CASCADE,
    target_chunk_id UUID NOT NULL REFERENCES node_chunks(id) ON DELETE CASCADE,
    edge_type VARCHAR(50) NOT NULL,
    properties JSONB DEFAULT '{}',
    created_by VARCHAR(10) DEFAULT 'system' CHECK (created_by IN ('user', 'system', 'ast')),
    created_at TIMESTAMP DEFAULT NOW(),
    
    UNIQUE (source_chunk_id, target_chunk_id, edge_type)
);

CREATE INDEX IF NOT EXISTS idx_chunk_edges_source ON chunk_edges(source_chunk_id);
CREATE INDEX IF NOT EXISTS idx_chunk_edges_target ON chunk_edges(target_chunk_id);
CREATE INDEX IF NOT EXISTS idx_chunk_edges_type ON chunk_edges(edge_type);
CREATE INDEX IF NOT EXISTS idx_chunk_edges_source_type ON chunk_edges(source_chunk_id, edge_type);

COMMENT ON TABLE chunk_edges IS 'Graph edges between chunks. Types:
  Structural: NEXT, PREV
  Code: CALLS, IMPORTS, INHERITS, DEFINES, USES
  Text: REFERENCES, SUMMARIZES, SUPPORTS, CONTRADICTS';

-- ============================================
-- NODE-TO-CHUNK EDGES (CONTAINS relationship)
-- ============================================

CREATE TABLE IF NOT EXISTS node_chunk_edges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    node_id UUID NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
    chunk_id UUID NOT NULL REFERENCES node_chunks(id) ON DELETE CASCADE,
    edge_type VARCHAR(50) NOT NULL DEFAULT 'CONTAINS',
    properties JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT NOW(),
    
    UNIQUE (node_id, chunk_id, edge_type)
);

CREATE INDEX IF NOT EXISTS idx_node_chunk_edges_node ON node_chunk_edges(node_id);
CREATE INDEX IF NOT EXISTS idx_node_chunk_edges_chunk ON node_chunk_edges(chunk_id);

COMMENT ON TABLE node_chunk_edges IS 'Edges from nodes to their chunks (CONTAINS) and cross-references';

-- ============================================
-- ADD FK TO node_embeddings
-- ============================================

DO $$
BEGIN
    -- Add FK constraint if not exists
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'node_embeddings_chunk_id_fkey'
    ) THEN
        ALTER TABLE node_embeddings 
            ADD CONSTRAINT node_embeddings_chunk_id_fkey 
            FOREIGN KEY (chunk_id) REFERENCES node_chunks(id) ON DELETE CASCADE;
        RAISE NOTICE '✓ Added FK constraint: node_embeddings.chunk_id → node_chunks.id';
    END IF;
END $$;

-- Source part constraint
DO $$
BEGIN
    -- Drop old constraint if exists
    ALTER TABLE node_embeddings DROP CONSTRAINT IF EXISTS node_embeddings_source_chk;
    
    -- Add new constraint
    ALTER TABLE node_embeddings
        ADD CONSTRAINT node_embeddings_source_chk
        CHECK (
            (chunk_id IS NULL AND source_part IN ('full', 'title', 'summary'))
            OR
            (chunk_id IS NOT NULL AND source_part IN ('chunk:content', 'chunk:summary'))
        );
    RAISE NOTICE '✓ Added source_part constraint';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '○ source_part constraint already exists or failed: %', SQLERRM;
END $$;

-- Unique constraint for embeddings including chunk_id
DO $$
BEGIN
    ALTER TABLE node_embeddings 
        DROP CONSTRAINT IF EXISTS node_embeddings_node_id_modality_model_name_source_part_key;
    
    ALTER TABLE node_embeddings
        DROP CONSTRAINT IF EXISTS node_embeddings_unique_embedding;
        
    ALTER TABLE node_embeddings
        ADD CONSTRAINT node_embeddings_unique_embedding
        UNIQUE NULLS NOT DISTINCT (node_id, chunk_id, modality, model_name, source_part);
    RAISE NOTICE '✓ Added unique constraint for embeddings';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '○ Unique constraint handling: %', SQLERRM;
END $$;

COMMIT;

DO $$
BEGIN
    RAISE NOTICE '✓ Chunk tables created:';
    RAISE NOTICE '  • node_chunks (with summary, keywords, language)';
    RAISE NOTICE '  • chunk_edges (NEXT, PREV, CALLS, etc.)';
    RAISE NOTICE '  • node_chunk_edges (CONTAINS)';
    RAISE NOTICE '  • Updated node_embeddings with chunk_id FK';
END $$;
