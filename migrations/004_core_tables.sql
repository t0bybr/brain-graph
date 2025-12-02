-- ============================================
-- Core Tables: nodes
-- ============================================

\c brain_graph

BEGIN;

-- ============================================
-- NODES TABLE (WITH TEMPORAL & DECAY)
-- ============================================

CREATE TABLE IF NOT EXISTS nodes (
    id TEXT PRIMARY KEY DEFAULT generate_ulid(),
    type node_type NOT NULL,
    title TEXT NOT NULL,
    
    -- Content Storage
    text_content TEXT,
    image_url TEXT,
    audio_url TEXT,
    video_url TEXT,
    
    -- Metadata
    metadata JSONB DEFAULT '{}',
    
    -- Decay Metadata
    decay_metadata JSONB DEFAULT '{
        "decay_config": {
            "method": "taxonomic",
            "half_life_days": 365,
            "baseline_relevance": 1.0,
            "min_relevance": 0.1
        },
        "usage_stats": {
            "access_count": 0,
            "last_accessed": null,
            "last_7_days": 0,
            "last_30_days": 0,
            "last_90_days": 0
        },
        "supersession": {
            "superseded_by": [],
            "supersedes": []
        },
        "lifecycle": {
            "peak_relevance_period": null,
            "marked_obsolete": false,
            "obsolete_reason": null,
            "archived": false
        }
    }',
    
    -- Synthesis Metadata (for Summary/Consolidation nodes)
    synthesis_metadata JSONB DEFAULT NULL,
    
    -- Timestamps
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    
    -- Temporal (for history tracking)
    sys_period tstzrange NOT NULL DEFAULT tstzrange(current_timestamp, null)
);

-- History table for temporal queries
CREATE TABLE IF NOT EXISTS nodes_history (LIKE nodes);

-- ============================================
-- INDEXES
-- ============================================

CREATE INDEX IF NOT EXISTS idx_nodes_type ON nodes(type);
CREATE INDEX IF NOT EXISTS idx_nodes_created_at ON nodes(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_nodes_updated_at ON nodes(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_nodes_metadata ON nodes USING GIN (metadata);
CREATE INDEX IF NOT EXISTS idx_nodes_decay_metadata ON nodes USING GIN (decay_metadata);
CREATE INDEX IF NOT EXISTS idx_nodes_synthesis_metadata ON nodes USING GIN (synthesis_metadata)
    WHERE synthesis_metadata IS NOT NULL;

-- Partial indexes for lifecycle queries
CREATE INDEX IF NOT EXISTS idx_nodes_marked_obsolete ON nodes((decay_metadata->'lifecycle'->>'marked_obsolete'))
    WHERE (decay_metadata->'lifecycle'->>'marked_obsolete')::boolean = true;
CREATE INDEX IF NOT EXISTS idx_nodes_archived ON nodes((decay_metadata->'lifecycle'->>'archived'))
    WHERE (decay_metadata->'lifecycle'->>'archived')::boolean = true;

-- History indexes
CREATE INDEX IF NOT EXISTS idx_nodes_history_id ON nodes_history(id);
CREATE INDEX IF NOT EXISTS idx_nodes_history_sys_period ON nodes_history USING GIST (sys_period);
CREATE INDEX IF NOT EXISTS idx_nodes_history_created_at ON nodes_history(created_at);

-- ============================================
-- COMMENTS
-- ============================================

COMMENT ON TABLE nodes IS 'Core content nodes with decay tracking and temporal history';
COMMENT ON COLUMN nodes.decay_metadata IS 'Tracks relevance decay, usage patterns, supersession, and lifecycle';
COMMENT ON COLUMN nodes.synthesis_metadata IS 'For meta-nodes: source nodes, synthesis method, confidence';

-- ============================================
-- FULL-TEXT SEARCH (ParadeDB or tsvector fallback)
-- ============================================

DO $$
DECLARE
    paradedb_available BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM pg_extension WHERE extname = 'pg_search'
    ) INTO paradedb_available;

    IF paradedb_available THEN
        BEGIN
            EXECUTE 'CREATE INDEX IF NOT EXISTS nodes_search_idx ON nodes
                     USING bm25 (id, title, text_content)
                     WITH (key_field=''id'')';
            RAISE NOTICE '✓ ParadeDB BM25 index created';
        EXCEPTION
            WHEN OTHERS THEN
                RAISE WARNING '✗ ParadeDB BM25 failed: %. Using tsvector fallback.', SQLERRM;
                ALTER TABLE nodes ADD COLUMN IF NOT EXISTS text_tokens tsvector
                    GENERATED ALWAYS AS (
                        setweight(to_tsvector('english', COALESCE(title, '')), 'A') ||
                        setweight(to_tsvector('english', COALESCE(text_content, '')), 'B')
                    ) STORED;
                CREATE INDEX IF NOT EXISTS idx_nodes_fts ON nodes USING GIN (text_tokens);
                RAISE NOTICE '✓ Tsvector fallback index created';
        END;
    ELSE
        RAISE NOTICE '○ ParadeDB not available, using tsvector fallback';
        ALTER TABLE nodes ADD COLUMN IF NOT EXISTS text_tokens tsvector
            GENERATED ALWAYS AS (
                setweight(to_tsvector('english', COALESCE(title, '')), 'A') ||
                setweight(to_tsvector('english', COALESCE(text_content, '')), 'B')
            ) STORED;
        CREATE INDEX IF NOT EXISTS idx_nodes_fts ON nodes USING GIN (text_tokens);
        RAISE NOTICE '✓ Tsvector fallback index created';
    END IF;
END $$;

COMMIT;

DO $$
BEGIN
    RAISE NOTICE '✓ Core tables created: nodes, nodes_history';
END $$;
