-- ============================================
-- Embeddings: Models & Vectors
-- ============================================

\c brain_graph

BEGIN;

-- ============================================
-- EMBEDDING MODELS (Domain-Specific Registry)
-- ============================================

CREATE TABLE IF NOT EXISTS embedding_models (
    id SERIAL PRIMARY KEY,
    model_name VARCHAR(100) UNIQUE NOT NULL,
    model_version VARCHAR(50),
    modality VARCHAR(20) NOT NULL CHECK (modality IN ('text', 'image', 'audio', 'video', 'graph', 'multimodal')),
    dimension INTEGER NOT NULL,
    
    -- Capabilities
    supports_text BOOLEAN DEFAULT FALSE,
    supports_image BOOLEAN DEFAULT FALSE,
    supports_audio BOOLEAN DEFAULT FALSE,
    supports_cross_modal BOOLEAN DEFAULT FALSE,
    
    -- Performance
    avg_tokens_per_sec INTEGER,
    requires_gpu BOOLEAN DEFAULT TRUE,
    vram_required_gb INTEGER,
    
    -- Config
    endpoint_url TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    is_default BOOLEAN DEFAULT FALSE,
    
    -- Metadata
    description TEXT,
    added_at TIMESTAMP DEFAULT NOW(),
    
    CHECK (
        (modality = 'text' AND supports_text) OR
        (modality = 'image' AND supports_image) OR
        (modality = 'audio' AND supports_audio) OR
        (modality = 'graph') OR
        (modality = 'multimodal')
    )
);

CREATE INDEX IF NOT EXISTS idx_models_active ON embedding_models(is_active) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_models_modality ON embedding_models(modality);
CREATE INDEX IF NOT EXISTS idx_models_default ON embedding_models(modality, is_default) WHERE is_default = TRUE;

COMMENT ON TABLE embedding_models IS 'Registry of available embedding models for multi-modal content';

-- ============================================
-- SEED DEFAULT MODELS
-- ============================================

INSERT INTO embedding_models (
    model_name, model_version, modality, dimension,
    supports_text, supports_image, supports_audio, supports_cross_modal,
    is_active, is_default, vram_required_gb, endpoint_url, description
) VALUES
('jina-embeddings-v2', '2.0', 'text', 768,
 TRUE, FALSE, FALSE, FALSE,
 TRUE, TRUE, 4,
 'http://jina:8000/embed',
 'Jina v2 - 8k context, state-of-the-art text understanding'),

('siglip-so400m', '1.0', 'image', 1152,
 FALSE, TRUE, FALSE, FALSE,
 TRUE, TRUE, 8,
 'http://siglip:8000/embed',
 'Google SigLIP - State-of-the-art vision encoder'),

('graphcodebert-base', '1.0', 'text', 768,
 TRUE, FALSE, FALSE, FALSE,
 TRUE, TRUE, 4,
 'http://codebert:8000/embed',
 'GraphCodeBERT - Code syntax + semantics understanding'),

('whisper-large-v3', 'v3', 'audio', 1280,
 FALSE, FALSE, TRUE, FALSE,
 TRUE, TRUE, 10,
 'http://whisper:8000/embed',
 'OpenAI Whisper encoder - Speech understanding'),

('graphsage', 'v1', 'graph', 256,
 FALSE, FALSE, FALSE, FALSE,
 TRUE, TRUE, 8,
 NULL,
 'GraphSAGE - Learn from graph structure'),

('colpali', '1.0', 'multimodal', 128,
 TRUE, TRUE, FALSE, FALSE,
 FALSE, FALSE, 12,
 'http://colpali:8000/embed',
 'ColPali - Document layout + text understanding (optional)')
ON CONFLICT (model_name) DO NOTHING;

-- ============================================
-- NODE EMBEDDINGS (Multi-Model, Multi-Modal)
-- ============================================

CREATE TABLE IF NOT EXISTS node_embeddings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    node_id UUID NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
    
    -- Optional: Chunk reference (NULL for node-level embeddings)
    chunk_id UUID,  -- FK will be added after chunks table exists
    
    -- Model Info
    modality VARCHAR(20) NOT NULL,
    model_name VARCHAR(100) NOT NULL REFERENCES embedding_models(model_name) ON DELETE CASCADE,
    
    -- Source part indicator
    -- Node-level: 'full', 'title', 'summary'
    -- Chunk-level: 'chunk:content', 'chunk:summary'
    source_part VARCHAR(50) NOT NULL,
    
    -- Vector
    dimension INTEGER NOT NULL,
    embedding vector NOT NULL,
    
    -- Metadata
    content_hash VARCHAR(64) NOT NULL,
    generated_at TIMESTAMP DEFAULT NOW(),
    last_accessed TIMESTAMP DEFAULT NOW(),
    
    -- Quality Metrics
    generation_time_ms INTEGER,
    token_count INTEGER,
    
    CHECK (vector_dims(embedding) = dimension)
);

-- ============================================
-- INDEXES
-- ============================================

CREATE INDEX IF NOT EXISTS idx_embeddings_node_modality ON node_embeddings(node_id, modality);
CREATE INDEX IF NOT EXISTS idx_embeddings_model ON node_embeddings(model_name);
CREATE INDEX IF NOT EXISTS idx_embeddings_last_accessed ON node_embeddings(last_accessed);
CREATE INDEX IF NOT EXISTS idx_embeddings_node_model ON node_embeddings(node_id, model_name);
CREATE INDEX IF NOT EXISTS idx_embeddings_source_part ON node_embeddings(source_part);

-- Chunk embeddings index (for later)
CREATE INDEX IF NOT EXISTS idx_embeddings_chunk ON node_embeddings(chunk_id) 
    WHERE chunk_id IS NOT NULL;

COMMENT ON TABLE node_embeddings IS 'Multi-modal embeddings with model-specific indexes';
COMMENT ON COLUMN node_embeddings.source_part IS 'Which part was embedded: full, title, summary, chunk:content, chunk:summary';
COMMENT ON COLUMN node_embeddings.chunk_id IS 'Reference to chunk for chunk-level embeddings (NULL for node-level)';

-- NOTE: HNSW indexes will be created in 016_indexes_hnsw.sql after data exists

COMMIT;

DO $$
DECLARE
    model_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO model_count FROM embedding_models WHERE is_active = TRUE;
    RAISE NOTICE '✓ Embeddings tables created';
    RAISE NOTICE '  • embedding_models: % active models', model_count;
    RAISE NOTICE '  • node_embeddings: ready for vectors';
END $$;
