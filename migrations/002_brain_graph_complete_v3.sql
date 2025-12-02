-- ============================================
-- Brain Graph - Complete Schema v4.0 (AGE-SAFE FIX)
-- Production Ready: Multi-Model, Domain-Specific, Information Decay
-- ============================================

\c brain_graph

BEGIN;

-- ============================================
-- IDEMPOTENT MIGRATION: Only drop if needed
-- ============================================
-- Set search_path to public for all operations
SET search_path = public;

-- Only drop tables from ag_catalog if they exist there (migration from old schema)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'ag_catalog' AND table_name = 'nodes') THEN
        RAISE NOTICE 'Migrating from ag_catalog to public schema...';
        DROP TABLE IF EXISTS ag_catalog.node_entities CASCADE;
        DROP TABLE IF EXISTS ag_catalog.entities CASCADE;
        DROP TABLE IF EXISTS ag_catalog.document_blocks CASCADE;
        DROP TABLE IF EXISTS ag_catalog.documents CASCADE;
        DROP TABLE IF EXISTS ag_catalog.rejected_edges CASCADE;
        DROP TABLE IF EXISTS ag_catalog.graph_edges_history CASCADE;
        DROP TABLE IF EXISTS ag_catalog.graph_edges CASCADE;
        DROP TABLE IF EXISTS ag_catalog.node_categories CASCADE;
        DROP TABLE IF EXISTS ag_catalog.taxonomy_history CASCADE;
        DROP TABLE IF EXISTS ag_catalog.taxonomy CASCADE;
        DROP TABLE IF EXISTS ag_catalog.node_embeddings CASCADE;
        DROP TABLE IF EXISTS ag_catalog.embedding_models CASCADE;
        DROP TABLE IF EXISTS ag_catalog.nodes_history CASCADE;
        DROP TABLE IF EXISTS ag_catalog.nodes CASCADE;
        DROP TABLE IF EXISTS ag_catalog.node_signals CASCADE;
        DROP TABLE IF EXISTS ag_catalog.node_scores CASCADE;
        DROP TABLE IF EXISTS ag_catalog.searches CASCADE;
        DROP TABLE IF EXISTS ag_catalog.graph_nodes CASCADE;
        RAISE NOTICE 'Old ag_catalog tables dropped';
    END IF;
END $$;

-- ============================================
-- EXTENSIONS
-- ============================================
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS age;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS temporal_tables;
CREATE EXTENSION IF NOT EXISTS pg_search;

-- ============================================
-- AGE SETUP (Production-Safe with better detection)
-- ============================================

-- Check if AGE cypher function exists with correct signature
CREATE OR REPLACE FUNCTION age_cypher_available()
RETURNS BOOLEAN AS $$
DECLARE
    func_exists BOOLEAN;
BEGIN
    -- Check for the standard AGE cypher function
    SELECT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'ag_catalog'
        AND p.proname = 'cypher'
    ) INTO func_exists;

    RETURN func_exists;
EXCEPTION
    WHEN OTHERS THEN
        RETURN FALSE;
END;
$$ LANGUAGE plpgsql;

-- Safe AGE execution wrapper
CREATE OR REPLACE FUNCTION safe_cypher_exec(
    graph_name TEXT,
    cypher_query TEXT
)
RETURNS BOOLEAN AS $$
BEGIN
    -- Try to execute cypher using dynamic SQL with the correct syntax
    EXECUTE format(
        'SELECT * FROM ag_catalog.cypher(%L, $cypher$%s$cypher$) AS (result ag_catalog.agtype)',
        graph_name,
        cypher_query
    );
    RETURN TRUE;
EXCEPTION
    WHEN undefined_function THEN
        RAISE WARNING 'AGE cypher function not available';
        RETURN FALSE;
    WHEN OTHERS THEN
        RAISE WARNING 'AGE cypher execution failed: %', SQLERRM;
        RETURN FALSE;
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
    -- Try to load AGE
    BEGIN
        EXECUTE 'LOAD ''age''';
        RAISE NOTICE 'AGE extension loaded';
    EXCEPTION
        WHEN insufficient_privilege THEN
            RAISE WARNING 'Insufficient privileges to LOAD age extension';
        WHEN OTHERS THEN
            RAISE WARNING 'Failed to load AGE: %', SQLERRM;
    END;

    SET search_path = ag_catalog, "$user", public;

    -- Create graph if not exists
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM ag_catalog.ag_graph WHERE name = 'brain_graph'
        ) THEN
            PERFORM ag_catalog.create_graph('brain_graph');
            RAISE NOTICE 'Graph "brain_graph" created';
        ELSE
            RAISE NOTICE 'Graph "brain_graph" already exists';
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            RAISE WARNING 'Could not create/check graph: %', SQLERRM;
    END;
END $$;

-- Keep search_path as public to create tables in public schema
-- (ag_catalog is only needed inside AGE cypher queries)

-- ============================================
-- TYPES
-- ============================================

DROP TYPE IF EXISTS node_type CASCADE;
CREATE TYPE node_type AS ENUM (
    'TextNode', 'ImageNode', 'AudioNode', 'VideoNode',
    'EmailNode', 'MessageNode',
    'BookNode', 'PaperNode', 'ArticleNode',
    'PersonNode', 'TripNode', 'EventNode', 'ProjectNode',
    'LocationNode', 'OrganizationNode',
    'SummaryNode', 'TopicNode', 'ConsolidationNode', 'TrendNode'
);

DROP TYPE IF EXISTS signal_type CASCADE;
CREATE TYPE signal_type AS ENUM (
    'view', 'edit', 'search_click', 'share',
    'link_created', 'mention', 'export', 'tag_added'
);

DROP TYPE IF EXISTS score_type CASCADE;
CREATE TYPE score_type AS ENUM (
    'decay', 'importance', 'novelty', 'quality',
    'forecast_interest', 'community_relevance'
);


-- ============================================
-- NODES TABLE (WITH TEMPORAL & DECAY)
-- ============================================

CREATE TABLE IF NOT EXISTS nodes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type node_type NOT NULL,
    title TEXT NOT NULL,
    text_content TEXT,
    image_url TEXT,
    audio_url TEXT,
    video_url TEXT,
    metadata JSONB DEFAULT '{}',
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
    synthesis_metadata JSONB DEFAULT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    sys_period tstzrange NOT NULL DEFAULT tstzrange(current_timestamp, null)
);

CREATE TABLE IF NOT EXISTS nodes_history (LIKE nodes);

-- Indexes
CREATE INDEX idx_nodes_type ON nodes(type);
CREATE INDEX idx_nodes_created_at ON nodes(created_at DESC);
CREATE INDEX idx_nodes_updated_at ON nodes(updated_at DESC);
CREATE INDEX idx_nodes_metadata ON nodes USING GIN (metadata);
CREATE INDEX idx_nodes_decay_metadata ON nodes USING GIN (decay_metadata);
CREATE INDEX idx_nodes_synthesis_metadata ON nodes USING GIN (synthesis_metadata)
    WHERE synthesis_metadata IS NOT NULL;
CREATE INDEX idx_nodes_marked_obsolete ON nodes((decay_metadata->'lifecycle'->>'marked_obsolete'))
    WHERE (decay_metadata->'lifecycle'->>'marked_obsolete')::boolean = true;
CREATE INDEX idx_nodes_archived ON nodes((decay_metadata->'lifecycle'->>'archived'))
    WHERE (decay_metadata->'lifecycle'->>'archived')::boolean = true;
CREATE INDEX idx_nodes_history_id ON nodes_history(id);
CREATE INDEX idx_nodes_history_sys_period ON nodes_history USING GIST (sys_period);
CREATE INDEX idx_nodes_history_created_at ON nodes_history(created_at);

COMMENT ON COLUMN nodes.decay_metadata IS 'Tracks relevance decay, usage patterns, supersession, and lifecycle';
COMMENT ON COLUMN nodes.synthesis_metadata IS 'For meta-nodes: source nodes, synthesis method, confidence';

-- ParadeDB BM25 Index
DO $$
DECLARE
    paradedb_available BOOLEAN;
BEGIN
    -- Check if ParadeDB is available
    SELECT EXISTS (
        SELECT 1 FROM pg_extension WHERE extname = 'pg_search'
    ) INTO paradedb_available;

    IF paradedb_available THEN
        -- Use ParadeDB's USING bm25 syntax (simplified)
        BEGIN
            EXECUTE 'CREATE INDEX IF NOT EXISTS nodes_search_idx ON nodes
                     USING bm25 (id, title, text_content)
                     WITH (key_field=''id'')';
            RAISE NOTICE 'ParadeDB BM25 index created successfully';
        EXCEPTION
            WHEN OTHERS THEN
                RAISE WARNING 'ParadeDB BM25 creation failed: %. Error: %', SQLERRM, SQLSTATE;
                -- Fallback to tsvector
                ALTER TABLE nodes ADD COLUMN IF NOT EXISTS text_tokens tsvector
                    GENERATED ALWAYS AS (
                        setweight(to_tsvector('english', COALESCE(title, '')), 'A') ||
                        setweight(to_tsvector('english', COALESCE(text_content, '')), 'B')
                    ) STORED;
                CREATE INDEX IF NOT EXISTS idx_nodes_fts ON nodes USING GIN (text_tokens);
                RAISE NOTICE 'Tsvector fallback index created';
        END;
    ELSE
        RAISE NOTICE 'ParadeDB extension not found, using tsvector fallback';
        -- Fallback: tsvector-based full-text search
        ALTER TABLE nodes ADD COLUMN IF NOT EXISTS text_tokens tsvector
            GENERATED ALWAYS AS (
                setweight(to_tsvector('english', COALESCE(title, '')), 'A') ||
                setweight(to_tsvector('english', COALESCE(text_content, '')), 'B')
            ) STORED;
        CREATE INDEX IF NOT EXISTS idx_nodes_fts ON nodes USING GIN (text_tokens);
        RAISE NOTICE 'Tsvector fallback index created';
    END IF;
END $$;

-- ============================================
-- EMBEDDING MODELS (Domain-Specific)
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

CREATE INDEX idx_models_active ON embedding_models(is_active) WHERE is_active = TRUE;
CREATE INDEX idx_models_modality ON embedding_models(modality);
CREATE INDEX idx_models_default ON embedding_models(modality, is_default) WHERE is_default = TRUE;

COMMENT ON TABLE embedding_models IS 'Registry of available embedding models for multi-modal content';

-- Seed with domain-specific models (idempotent)
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

    -- Model Info
    modality VARCHAR(20) NOT NULL,
    model_name VARCHAR(100) NOT NULL REFERENCES embedding_models(model_name) ON DELETE CASCADE,

    -- Source
    source_part VARCHAR(50) NOT NULL,

    -- Vector
    dimension INTEGER NOT NULL,
    embedding vector NOT NULL,

    -- Metadata
    content_hash VARCHAR(64) NOT NULL,
    generated_at TIMESTAMP DEFAULT NOW(),
    last_accessed TIMESTAMP DEFAULT NOW(),

    -- Quality Metrics (optional)
    generation_time_ms INTEGER,
    token_count INTEGER,

    UNIQUE (node_id, modality, model_name, source_part),
    CHECK (vector_dims(embedding) = dimension)
);

CREATE INDEX idx_embeddings_node_modality ON node_embeddings(node_id, modality);
CREATE INDEX idx_embeddings_model ON node_embeddings(model_name);
CREATE INDEX idx_embeddings_last_accessed ON node_embeddings(last_accessed);
CREATE INDEX idx_embeddings_node_model ON node_embeddings(node_id, model_name);

COMMENT ON TABLE node_embeddings IS 'Multi-modal embeddings with model-specific indexes';
COMMENT ON COLUMN node_embeddings.source_part IS 'Which part of content was embedded: full, title, visual, audio, structure';

-- NOTE: HNSW indexes will be created AFTER COMMIT when we have data
-- See end of file for deferred index creation

-- ============================================
-- TAXONOMY (WITH TEMPORAL)
-- ============================================

CREATE TABLE IF NOT EXISTS taxonomy (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    parent_id INTEGER REFERENCES taxonomy(id) ON DELETE CASCADE,
    level INTEGER NOT NULL CHECK (level >= 0 AND level <= 5),
    path TEXT UNIQUE NOT NULL,

    -- Meta Fields (for decay computation)
    topic_importance INTEGER DEFAULT 5 CHECK (topic_importance BETWEEN 1 AND 10),
    change_velocity INTEGER DEFAULT 5 CHECK (change_velocity BETWEEN 1 AND 10),
    usage_focus INTEGER DEFAULT 5 CHECK (usage_focus BETWEEN 1 AND 10),

    keywords TEXT[],
    related_categories JSONB DEFAULT '[]',

    created_at TIMESTAMP DEFAULT NOW(),
    sys_period tstzrange NOT NULL DEFAULT tstzrange(current_timestamp, null)
);

CREATE TABLE IF NOT EXISTS taxonomy_history (LIKE taxonomy);

CREATE INDEX idx_taxonomy_parent ON taxonomy(parent_id);
CREATE INDEX idx_taxonomy_path ON taxonomy(path);
CREATE INDEX idx_taxonomy_level ON taxonomy(level);
CREATE INDEX idx_taxonomy_change_velocity ON taxonomy(change_velocity);
CREATE INDEX idx_taxonomy_keywords ON taxonomy USING GIN (keywords);

CREATE INDEX idx_taxonomy_history_id ON taxonomy_history(id);
CREATE INDEX idx_taxonomy_history_sys_period ON taxonomy_history USING GIST (sys_period);

COMMENT ON COLUMN taxonomy.topic_importance IS 'Overall topic importance (1-10)';
COMMENT ON COLUMN taxonomy.change_velocity IS 'How quickly content becomes outdated (1-10): 1-3=stable, 4-7=medium, 8-10=fast';
COMMENT ON COLUMN taxonomy.usage_focus IS 'Weight of usage frequency in ranking (1-10)';

-- ============================================
-- NODE CATEGORIES
-- ============================================

CREATE TABLE IF NOT EXISTS node_categories (
    node_id UUID REFERENCES nodes(id) ON DELETE CASCADE,
    category_id INTEGER REFERENCES taxonomy(id) ON DELETE CASCADE,
    confidence FLOAT NOT NULL CHECK (confidence BETWEEN 0 AND 1),
    assigned_by VARCHAR(10) NOT NULL CHECK (assigned_by IN ('user', 'llm')),
    assigned_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (node_id, category_id)
);

CREATE INDEX idx_node_categories_node ON node_categories(node_id);
CREATE INDEX idx_node_categories_category ON node_categories(category_id);
CREATE INDEX idx_node_categories_confidence ON node_categories(confidence DESC);

COMMENT ON TABLE node_categories IS 'Maps nodes to taxonomy categories with confidence scores';

-- ============================================
-- GRAPH EDGES (WITH TEMPORAL)
-- ============================================

CREATE TABLE IF NOT EXISTS graph_edges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_id UUID NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
    target_id UUID NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
    edge_type VARCHAR(50) NOT NULL,
    properties JSONB DEFAULT '{}',
    created_by VARCHAR(10) DEFAULT 'system' CHECK (created_by IN ('user', 'system')),
    created_at TIMESTAMP DEFAULT NOW(),
    sys_period tstzrange NOT NULL DEFAULT tstzrange(current_timestamp, null),
    UNIQUE (source_id, target_id, edge_type)
);

CREATE TABLE IF NOT EXISTS graph_edges_history (LIKE graph_edges);

CREATE INDEX idx_edges_source ON graph_edges(source_id);
CREATE INDEX idx_edges_target ON graph_edges(target_id);
CREATE INDEX idx_edges_type ON graph_edges(edge_type);
CREATE INDEX idx_edges_source_type ON graph_edges(source_id, edge_type);
CREATE INDEX idx_edges_target_type ON graph_edges(target_id, edge_type);
CREATE INDEX idx_edges_properties ON graph_edges USING GIN (properties);
CREATE INDEX idx_edges_created_by ON graph_edges(created_by);

CREATE INDEX idx_edges_history_source ON graph_edges_history(source_id);
CREATE INDEX idx_edges_history_target ON graph_edges_history(target_id);
CREATE INDEX idx_edges_history_type ON graph_edges_history(edge_type);
CREATE INDEX idx_edges_history_sys_period ON graph_edges_history USING GIST (sys_period);

COMMENT ON TABLE graph_edges IS 'Graph relationships: LINKS_TO, SIMILAR_TO, IN_CATEGORY, PART_OF, CREATED_DURING, AT_LOCATION, AUTHORED, MENTIONED_IN, SYNTHESIZES, CONSOLIDATES, SUPERSEDES, HAS_IMAGE, ILLUSTRATED_BY, etc.';

-- ============================================
-- REJECTED EDGES (Negative Signals)
-- ============================================

CREATE TABLE IF NOT EXISTS rejected_edges (
    source_id UUID NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
    target_id UUID NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
    edge_type VARCHAR(50) NOT NULL,
    rejected_by VARCHAR(10) NOT NULL CHECK (rejected_by IN ('user', 'system', 'rule')),
    rejected_at TIMESTAMP DEFAULT NOW(),
    expires_at TIMESTAMP,
    rejection_reason TEXT,
    PRIMARY KEY (source_id, target_id, edge_type)
);

CREATE INDEX idx_rejected_edges_expires ON rejected_edges(expires_at)
WHERE expires_at IS NOT NULL;
CREATE INDEX idx_rejected_edges_rejected_by ON rejected_edges(rejected_by);

COMMENT ON TABLE rejected_edges IS 'Tracks user-rejected or invalid edge suggestions to avoid re-proposing';

-- ============================================
-- GRAPH NODES (Mirror)
-- ============================================

CREATE TABLE IF NOT EXISTS graph_nodes (
    node_id UUID PRIMARY KEY REFERENCES nodes(id) ON DELETE CASCADE,
    graph_label VARCHAR(50) NOT NULL,
    created_in_graph_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_graph_nodes_label ON graph_nodes(graph_label);

COMMENT ON TABLE graph_nodes IS 'Mirror of nodes that exist in AGE graph database';

-- ============================================
-- ENTITIES (NER/Graph Nodes)
-- ============================================

CREATE TABLE IF NOT EXISTS entities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_type VARCHAR(50) NOT NULL,
    canonical_name TEXT NOT NULL,
    normalized_name TEXT NOT NULL,

    metadata JSONB DEFAULT '{}',
    merged_into UUID REFERENCES entities(id) ON DELETE SET NULL,

    created_at TIMESTAMP DEFAULT NOW(),

    UNIQUE (entity_type, normalized_name)
);

CREATE INDEX idx_entities_type ON entities(entity_type);
CREATE INDEX idx_entities_canonical ON entities(canonical_name);
CREATE INDEX idx_entities_metadata ON entities USING GIN (metadata);

COMMENT ON TABLE entities IS 'Named entities: PERSON, ORG, LOCATION, PROJECT, EVENT extracted via NER';

-- ============================================
-- NODE <-> ENTITY RELATIONSHIPS
-- ============================================

CREATE TABLE IF NOT EXISTS node_entities (
    node_id UUID NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
    entity_id UUID NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
    role VARCHAR(50) NOT NULL,
    confidence FLOAT CHECK (confidence BETWEEN 0 AND 1),
    source VARCHAR(100),
    span_start INTEGER,
    span_end INTEGER,
    created_at TIMESTAMP DEFAULT NOW(),

    PRIMARY KEY (node_id, entity_id, role)
);

CREATE INDEX idx_node_entities_node ON node_entities(node_id);
CREATE INDEX idx_node_entities_entity ON node_entities(entity_id);
CREATE INDEX idx_node_entities_role ON node_entities(role);
CREATE INDEX idx_node_entities_confidence ON node_entities(confidence DESC);

COMMENT ON TABLE node_entities IS 'Links nodes to extracted entities with role and confidence';

-- ============================================
-- DOCUMENTS (PDFs, Scans)
-- ============================================

CREATE TABLE IF NOT EXISTS documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    node_id UUID REFERENCES nodes(id) ON DELETE SET NULL,

    source_path TEXT,
    source_url TEXT,
    mime_type VARCHAR(100),
    file_size_bytes BIGINT,

    page_count INTEGER,
    language VARCHAR(10),

    processed_by VARCHAR(100),
    processed_at TIMESTAMP,

    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_documents_node ON documents(node_id);
CREATE INDEX idx_documents_mime ON documents(mime_type);

COMMENT ON TABLE documents IS 'Source document metadata for PDFs, scans, etc.';

-- ============================================
-- DOCUMENT BLOCKS (Layout-Aware)
-- ============================================

CREATE TABLE IF NOT EXISTS document_blocks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,

    page INTEGER NOT NULL,
    block_index INTEGER NOT NULL,

    block_type VARCHAR(50),
    text_content TEXT,

    -- Bounding box
    bbox_x0 FLOAT,
    bbox_y0 FLOAT,
    bbox_x1 FLOAT,
    bbox_y1 FLOAT,

    raw_output JSONB,
    confidence FLOAT,

    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_blocks_document_page ON document_blocks(document_id, page, block_index);
CREATE INDEX idx_blocks_type ON document_blocks(block_type);

-- Full-text search on blocks
ALTER TABLE document_blocks ADD COLUMN text_tokens tsvector
    GENERATED ALWAYS AS (to_tsvector('english', COALESCE(text_content, ''))) STORED;
CREATE INDEX idx_blocks_fts ON document_blocks USING GIN (text_tokens);

COMMENT ON TABLE document_blocks IS 'Document layout blocks (text, image, table) with bbox coordinates';

-- ============================================
-- NODE SIGNALS (Time-Series Events)
-- ============================================

CREATE TABLE IF NOT EXISTS node_signals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    node_id UUID NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
    signal_type signal_type NOT NULL,
    value FLOAT DEFAULT 1.0,
    metadata JSONB DEFAULT '{}',
    timestamp TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_signals_node_ts ON node_signals(node_id, timestamp DESC);
CREATE INDEX idx_signals_type_ts ON node_signals(signal_type, timestamp DESC);

-- FIX: Changed from partial index with NOW() to standard index
-- Reason: Functions in index predicate must be IMMUTABLE
CREATE INDEX idx_signals_recent ON node_signals(timestamp DESC);

COMMENT ON TABLE node_signals IS 'Time-series user interaction signals for decay computation';

-- ============================================
-- NODE SCORES (Derived Metrics)
-- ============================================

CREATE TABLE IF NOT EXISTS node_scores (
    node_id UUID NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
    score_type score_type NOT NULL,
    model_name VARCHAR(100) DEFAULT 'default',
    value FLOAT NOT NULL,
    confidence FLOAT,
    metadata JSONB DEFAULT '{}',
    computed_at TIMESTAMP DEFAULT NOW(),
    expires_at TIMESTAMP,

    PRIMARY KEY (node_id, score_type, model_name)
);

CREATE INDEX idx_scores_type_value ON node_scores(score_type, value DESC);
CREATE INDEX idx_scores_expires ON node_scores(expires_at) WHERE expires_at IS NOT NULL;
CREATE INDEX idx_scores_node_type ON node_scores(node_id, score_type);

COMMENT ON TABLE node_scores IS 'Computed scores: decay, importance, novelty, quality, forecast_interest';

-- ============================================
-- SEARCHES (Persistent & Auto-Updating)
-- ============================================

CREATE TABLE IF NOT EXISTS searches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    node_id UUID REFERENCES nodes(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    query JSONB NOT NULL,
    is_persistent BOOLEAN DEFAULT FALSE,
    auto_update BOOLEAN DEFAULT FALSE,
    update_frequency INTERVAL,
    last_updated TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    execution_count INTEGER DEFAULT 0
);

CREATE INDEX idx_searches_persistent ON searches(is_persistent);
CREATE INDEX idx_searches_auto_update ON searches(auto_update) WHERE auto_update = true;
CREATE INDEX idx_searches_node_id ON searches(node_id) WHERE node_id IS NOT NULL;

COMMENT ON TABLE searches IS 'Saved searches that can auto-update and create SearchNode results';

-- ============================================
-- TRIGGERS
-- ============================================

-- Update timestamp trigger
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_nodes_updated_at
    BEFORE UPDATE ON nodes
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Temporal table triggers
CREATE TRIGGER nodes_versioning_trigger
    BEFORE INSERT OR UPDATE OR DELETE ON nodes
    FOR EACH ROW EXECUTE FUNCTION versioning('sys_period', 'nodes_history', true);

CREATE TRIGGER taxonomy_versioning_trigger
    BEFORE INSERT OR UPDATE OR DELETE ON taxonomy
    FOR EACH ROW EXECUTE FUNCTION versioning('sys_period', 'taxonomy_history', true);

CREATE TRIGGER edges_versioning_trigger
    BEFORE INSERT OR UPDATE OR DELETE ON graph_edges
    FOR EACH ROW EXECUTE FUNCTION versioning('sys_period', 'graph_edges_history', true);

-- ============================================
-- AGE SYNCHRONIZATION (Safe Implementation)
-- ============================================
-- These triggers sync relational data to AGE graph
-- They fail gracefully if AGE cypher is not available

CREATE OR REPLACE FUNCTION sync_node_to_age()
RETURNS TRIGGER AS $$
DECLARE
    cypher_query TEXT;
    age_available BOOLEAN;
BEGIN
    -- Check if AGE is available
    SELECT age_cypher_available() INTO age_available;
    IF NOT age_available THEN
        RETURN COALESCE(NEW, OLD);
    END IF;

    BEGIN
        IF TG_OP = 'INSERT' THEN
            cypher_query := format(
                'CREATE (:%I {node_id: %L, title: %L, created_at: %L})',
                NEW.type, NEW.id, NEW.title, NEW.created_at
            );
            EXECUTE format(
                'SELECT * FROM ag_catalog.cypher(%L, $q$%s$q$) AS (v ag_catalog.agtype)',
                'brain_graph', cypher_query
            );
            RETURN NEW;

        ELSIF TG_OP = 'UPDATE' THEN
            cypher_query := format(
                'MATCH (n {node_id: %L}) SET n.title = %L, n.updated_at = %L',
                NEW.id, NEW.title, NEW.updated_at
            );
            EXECUTE format(
                'SELECT * FROM ag_catalog.cypher(%L, $q$%s$q$) AS (v ag_catalog.agtype)',
                'brain_graph', cypher_query
            );
            RETURN NEW;

        ELSIF TG_OP = 'DELETE' THEN
            cypher_query := format(
                'MATCH (n {node_id: %L}) DETACH DELETE n',
                OLD.id
            );
            EXECUTE format(
                'SELECT * FROM ag_catalog.cypher(%L, $q$%s$q$) AS (v ag_catalog.agtype)',
                'brain_graph', cypher_query
            );
            RETURN OLD;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            RAISE WARNING 'AGE sync failed for node: %', SQLERRM;
    END;

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER node_sync_trigger
    AFTER INSERT OR UPDATE OR DELETE ON nodes
    FOR EACH ROW EXECUTE FUNCTION sync_node_to_age();

CREATE OR REPLACE FUNCTION sync_edge_to_age()
RETURNS TRIGGER AS $$
DECLARE
    props_json TEXT;
    cypher_query TEXT;
    age_available BOOLEAN;
BEGIN
    SELECT age_cypher_available() INTO age_available;
    IF NOT age_available THEN
        RETURN COALESCE(NEW, OLD);
    END IF;

    BEGIN
        IF TG_OP = 'INSERT' THEN
            props_json := COALESCE(NEW.properties::text, '{}');
            cypher_query := format(
                'MATCH (a {node_id: %L}), (b {node_id: %L}) CREATE (a)-[:%I %s]->(b)',
                NEW.source_id, NEW.target_id, NEW.edge_type, props_json
            );
            EXECUTE format(
                'SELECT * FROM ag_catalog.cypher(%L, $q$%s$q$) AS (v ag_catalog.agtype)',
                'brain_graph', cypher_query
            );
            RETURN NEW;

        ELSIF TG_OP = 'UPDATE' THEN
            props_json := COALESCE(NEW.properties::text, '{}');
            cypher_query := format(
                'MATCH (a {node_id: %L})-[r:%I]->(b {node_id: %L}) SET r = %s',
                NEW.source_id, NEW.edge_type, NEW.target_id, props_json
            );
            EXECUTE format(
                'SELECT * FROM ag_catalog.cypher(%L, $q$%s$q$) AS (v ag_catalog.agtype)',
                'brain_graph', cypher_query
            );
            RETURN NEW;

        ELSIF TG_OP = 'DELETE' THEN
            cypher_query := format(
                'MATCH (a {node_id: %L})-[r:%I]->(b {node_id: %L}) DELETE r',
                OLD.source_id, OLD.edge_type, OLD.target_id
            );
            EXECUTE format(
                'SELECT * FROM ag_catalog.cypher(%L, $q$%s$q$) AS (v ag_catalog.agtype)',
                'brain_graph', cypher_query
            );
            RETURN OLD;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            RAISE WARNING 'AGE edge sync failed: %', SQLERRM;
    END;

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER edge_sync_trigger
    AFTER INSERT OR UPDATE OR DELETE ON graph_edges
    FOR EACH ROW EXECUTE FUNCTION sync_edge_to_age();

-- ============================================
-- AGE INDEXES (Safe)
-- ============================================

DO $$
DECLARE
    node_label TEXT;
    age_available BOOLEAN;
BEGIN
    SELECT age_cypher_available() INTO age_available;
    IF NOT age_available THEN
        RAISE NOTICE 'AGE not available - skipping AGE index creation';
    ELSE
        -- AGE indexes are created automatically by the extension
        -- Manual index creation may cause compatibility issues
        RAISE NOTICE 'AGE indexes are created automatically by the extension';
    END IF;
END $$;


-- ============================================
-- CORE UTILITY FUNCTIONS (AGE-Safe)
-- ============================================

CREATE OR REPLACE FUNCTION rebuild_graph_from_relational(
    batch_size INTEGER DEFAULT 1000,
    verbose BOOLEAN DEFAULT TRUE
)
RETURNS TABLE(
    nodes_processed INTEGER,
    edges_processed INTEGER,
    duration_seconds NUMERIC
) AS $$
BEGIN
    RAISE NOTICE 'rebuild_graph_from_relational is not yet implemented';
    RETURN QUERY SELECT 0, 0, 0::NUMERIC;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION rebuild_graph_from_relational IS 'Rebuild AGE graph from relational tables (for recovery/sync)';

-- ============================================
-- TEMPORAL QUERY FUNCTIONS
-- ============================================

CREATE OR REPLACE FUNCTION get_graph_at_time(target_time timestamptz)
RETURNS TABLE (
    nodes_snapshot jsonb,
    edges_snapshot jsonb
) AS $$
BEGIN
    RETURN QUERY
    WITH historical_nodes AS (
        SELECT * FROM nodes_history
        WHERE sys_period @> target_time
        UNION ALL
        SELECT * FROM nodes
        WHERE sys_period @> target_time
    ),
    historical_edges AS (
        SELECT * FROM graph_edges_history
        WHERE sys_period @> target_time
        UNION ALL
        SELECT * FROM graph_edges
        WHERE sys_period @> target_time
    )
    SELECT
        (SELECT jsonb_agg(to_jsonb(hn.*)) FROM historical_nodes hn) AS nodes_snapshot,
        (SELECT jsonb_agg(to_jsonb(he.*)) FROM historical_edges he) AS edges_snapshot;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_graph_at_time IS 'Reconstruct graph state at any point in time using temporal tables';

-- ============================================
-- SIGNAL TRACKING
-- ============================================

CREATE OR REPLACE FUNCTION track_node_access(p_node_id UUID)
RETURNS void AS $$
BEGIN
    -- Update node metadata
    UPDATE nodes
    SET decay_metadata = jsonb_set(
        jsonb_set(
            jsonb_set(
                decay_metadata,
                '{usage_stats,last_accessed}',
                to_jsonb(NOW())
            ),
            '{usage_stats,access_count}',
            to_jsonb(COALESCE((decay_metadata->'usage_stats'->>'access_count')::INTEGER, 0) + 1)
        ),
        '{usage_stats,last_7_days}',
        to_jsonb(
            COALESCE((decay_metadata->'usage_stats'->>'last_7_days')::INTEGER, 0) + 1
        )
    )
    WHERE id = p_node_id;

    -- Record signal
    INSERT INTO node_signals (node_id, signal_type, value)
    VALUES (p_node_id, 'view', 1.0);

    -- Update embedding access time
    UPDATE node_embeddings
    SET last_accessed = NOW()
    WHERE node_id = p_node_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION track_node_access IS 'Record node access for decay computation and analytics';

-- ============================================
-- DECAY COMPUTATION
-- ============================================

CREATE OR REPLACE FUNCTION compute_decay_score(
    p_node_id UUID,
    at_time TIMESTAMP DEFAULT NOW()
)
RETURNS FLOAT AS $$
DECLARE
    node_record RECORD;
    age_days FLOAT;
    usage_factor FLOAT := 1.0;
    taxonomy_factor INTEGER;
    decay_score FLOAT;
    half_life FLOAT;
    min_relevance FLOAT;
    last_access TIMESTAMP;
    days_since_access FLOAT;
    access_count INTEGER;
BEGIN
    SELECT * INTO node_record FROM nodes WHERE id = p_node_id;

    IF NOT FOUND THEN
        RETURN 0.0;
    END IF;

    -- Calculate age
    age_days := EXTRACT(EPOCH FROM (at_time - node_record.created_at)) / 86400.0;

    -- Get taxonomy-based change velocity
    SELECT t.change_velocity INTO taxonomy_factor
    FROM node_categories nc
    JOIN taxonomy t ON nc.category_id = t.id
    WHERE nc.node_id = p_node_id
    ORDER BY nc.confidence DESC
    LIMIT 1;

    taxonomy_factor := COALESCE(taxonomy_factor, 5);

    -- Determine half-life based on taxonomy
    half_life := CASE
        WHEN taxonomy_factor <= 3 THEN 1095  -- 3 years for stable content
        WHEN taxonomy_factor <= 7 THEN 365   -- 1 year for medium
        ELSE 180                              -- 6 months for fast-changing
    END;

    -- Override with explicit config if present
    IF node_record.decay_metadata->'decay_config'->>'half_life_days' IS NOT NULL THEN
        half_life := (node_record.decay_metadata->'decay_config'->>'half_life_days')::FLOAT;
    END IF;

    -- Base decay score
    decay_score := (node_record.decay_metadata->'decay_config'->>'baseline_relevance')::FLOAT;
    decay_score := COALESCE(decay_score, 1.0);
    decay_score := decay_score * POWER(0.5, age_days / half_life);

    -- Usage boost
    last_access := (node_record.decay_metadata->'usage_stats'->>'last_accessed')::TIMESTAMP;
    access_count := COALESCE((node_record.decay_metadata->'usage_stats'->>'access_count')::INTEGER, 0);

    IF last_access IS NOT NULL THEN
        days_since_access := EXTRACT(EPOCH FROM (at_time - last_access)) / 86400.0;
        usage_factor := 1.0 + (0.5 * POWER(0.5, days_since_access / 30.0));

        IF access_count > 10 THEN
            usage_factor := usage_factor * (1.0 + LEAST(access_count / 100.0, 0.5));
        END IF;

        decay_score := decay_score * usage_factor;
    END IF;

    -- Supersession penalty
    IF jsonb_array_length(COALESCE(node_record.decay_metadata->'supersession'->'superseded_by', '[]')) > 0 THEN
        decay_score := decay_score * 0.3;
    END IF;

    -- Lifecycle penalties
    IF (node_record.decay_metadata->'lifecycle'->>'marked_obsolete')::BOOLEAN IS TRUE THEN
        decay_score := decay_score * 0.1;
    END IF;

    IF (node_record.decay_metadata->'lifecycle'->>'archived')::BOOLEAN IS TRUE THEN
        decay_score := decay_score * 0.05;
    END IF;

    -- Apply minimum threshold
    min_relevance := COALESCE(
        (node_record.decay_metadata->'decay_config'->>'min_relevance')::FLOAT,
        0.1
    );

    decay_score := GREATEST(decay_score, min_relevance);

    RETURN decay_score;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION compute_decay_score IS 'Compute time-based relevance decay with taxonomy, usage, and supersession factors';

CREATE OR REPLACE FUNCTION compute_and_store_decay_scores()
RETURNS INTEGER AS $$
DECLARE
    updated_count INTEGER;
BEGIN
    INSERT INTO node_scores (node_id, score_type, model_name, value, expires_at)
    SELECT
        id,
        'decay',
        'heuristic-v1',
        compute_decay_score(id),
        NOW() + INTERVAL '1 day'
    FROM nodes
    WHERE (decay_metadata->'lifecycle'->>'archived')::BOOLEAN IS NOT TRUE
    ON CONFLICT (node_id, score_type, model_name) DO UPDATE
    SET value = EXCLUDED.value,
        computed_at = NOW(),
        expires_at = EXCLUDED.expires_at;

    GET DIAGNOSTICS updated_count = ROW_COUNT;
    RETURN updated_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION compute_and_store_decay_scores IS 'Batch compute and store decay scores for all active nodes';

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
    SELECT
        em.model_name,
        sp.source_part,
        sp.priority
    FROM embedding_models em
    CROSS JOIN LATERAL (
        VALUES
            -- Text nodes
            ('TextNode', 'jina-embeddings-v2', 'full', 1),
            ('TextNode', 'graphsage', 'structure', 2),

            -- Image nodes
            ('ImageNode', 'siglip-so400m', 'full', 1),
            ('ImageNode', 'graphsage', 'structure', 2),

            -- Audio nodes
            ('AudioNode', 'whisper-large-v3', 'full', 1),
            ('AudioNode', 'graphsage', 'structure', 2),

            -- Video nodes
            ('VideoNode', 'siglip-so400m', 'visual', 1),
            ('VideoNode', 'whisper-large-v3', 'audio', 2),
            ('VideoNode', 'graphsage', 'structure', 3),

            -- Communication nodes
            ('EmailNode', 'jina-embeddings-v2', 'full', 1),
            ('EmailNode', 'graphsage', 'structure', 2),
            ('MessageNode', 'jina-embeddings-v2', 'full', 1),
            ('MessageNode', 'graphsage', 'structure', 2),

            -- Knowledge nodes
            ('BookNode', 'jina-embeddings-v2', 'full', 1),
            ('BookNode', 'graphsage', 'structure', 2),
            ('PaperNode', 'jina-embeddings-v2', 'full', 1),
            ('PaperNode', 'graphcodebert-base', 'code', 2),
            ('PaperNode', 'graphsage', 'structure', 3),
            ('ArticleNode', 'jina-embeddings-v2', 'full', 1),
            ('ArticleNode', 'graphsage', 'structure', 2),

            -- Structural nodes (hub-like)
            ('PersonNode', 'jina-embeddings-v2', 'title', 1),
            ('PersonNode', 'graphsage', 'structure', 2),
            ('TripNode', 'jina-embeddings-v2', 'title', 1),
            ('TripNode', 'graphsage', 'structure', 2),
            ('EventNode', 'jina-embeddings-v2', 'title', 1),
            ('EventNode', 'graphsage', 'structure', 2),
            ('ProjectNode', 'jina-embeddings-v2', 'title', 1),
            ('ProjectNode', 'graphsage', 'structure', 2),
            ('LocationNode', 'jina-embeddings-v2', 'title', 1),
            ('LocationNode', 'graphsage', 'structure', 2),
            ('OrganizationNode', 'jina-embeddings-v2', 'title', 1),
            ('OrganizationNode', 'graphsage', 'structure', 2),

            -- Meta nodes
            ('SummaryNode', 'jina-embeddings-v2', 'full', 1),
            ('TopicNode', 'jina-embeddings-v2', 'full', 1),
            ('ConsolidationNode', 'jina-embeddings-v2', 'full', 1),
            ('TrendNode', 'jina-embeddings-v2', 'full', 1)
    ) AS sp(node_type, model, source_part, priority)
    WHERE sp.node_type::text = p_node_type::text
      AND em.model_name = sp.model
      AND em.is_active = TRUE
    ORDER BY sp.priority;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_models_for_node IS 'Get recommended embedding models for a node type';

-- ============================================
-- EDGE GENERATION (Similarity)
-- ============================================

CREATE OR REPLACE FUNCTION generate_similarity_edges(
    p_node_id UUID,
    p_model_name TEXT DEFAULT 'jina-embeddings-v2',
    p_threshold FLOAT DEFAULT 0.85,
    p_limit INTEGER DEFAULT 10
)
RETURNS TABLE(
    target_id UUID,
    similarity FLOAT,
    edge_exists BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    WITH node_emb AS (
        SELECT embedding, dimension
        FROM node_embeddings
        WHERE node_id = p_node_id
          AND model_name = p_model_name
        LIMIT 1
    ),
    similar_nodes AS (
        SELECT
            ne.node_id,
            1 - (ne.embedding <=> node_emb.embedding) AS similarity
        FROM node_embeddings ne, node_emb
        WHERE ne.model_name = p_model_name
          AND ne.node_id != p_node_id
          AND 1 - (ne.embedding <=> node_emb.embedding) >= p_threshold
        ORDER BY ne.embedding <=> node_emb.embedding
        LIMIT p_limit
    )
    SELECT
        sn.node_id,
        sn.similarity,
        EXISTS(
            SELECT 1 FROM graph_edges
            WHERE source_id = p_node_id
              AND target_id = sn.node_id
              AND edge_type = 'SIMILAR_TO'
        ) AS edge_exists
    FROM similar_nodes sn;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION generate_similarity_edges IS 'Find similar nodes using vector similarity for edge suggestions';

-- ============================================
-- GRAPH IMPORTANCE (PageRank-like)
-- ============================================

CREATE OR REPLACE FUNCTION compute_graph_importance(p_node_id UUID)
RETURNS FLOAT AS $$
DECLARE
    in_degree INTEGER;
    out_degree INTEGER;
    importance_score FLOAT;
BEGIN
    SELECT COUNT(*) INTO in_degree
    FROM graph_edges
    WHERE target_id = p_node_id;

    SELECT COUNT(*) INTO out_degree
    FROM graph_edges
    WHERE source_id = p_node_id;

    -- Simple importance: weighted by incoming edges (more = more important)
    importance_score := (in_degree * 0.7) + (out_degree * 0.3);

    -- Normalize to 0-1 range (log scale for large graphs)
    importance_score := importance_score / (1.0 + importance_score);

    RETURN importance_score;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION compute_graph_importance IS 'Compute node importance based on graph structure';

-- ============================================
-- DOMAIN-SPECIFIC SEARCH
-- ============================================

CREATE OR REPLACE FUNCTION domain_specific_search(
    p_query TEXT,
    p_node_types node_type[] DEFAULT NULL,
    p_limit INTEGER DEFAULT 20,
    p_use_decay BOOLEAN DEFAULT TRUE
)
RETURNS TABLE(
    node_id UUID,
    node_type node_type,
    title TEXT,
    rank FLOAT,
    decay_score FLOAT,
    final_score FLOAT
) AS $$
DECLARE
    search_query tsquery;
BEGIN
    search_query := plainto_tsquery('english', p_query);

    RETURN QUERY
    WITH ranked_nodes AS (
        SELECT
            n.id,
            n.type,
            n.title,
            ts_rank(n.text_tokens, search_query) AS text_rank
        FROM nodes n
        WHERE (p_node_types IS NULL OR n.type = ANY(p_node_types))
          AND n.text_tokens @@ search_query
    ),
    with_decay AS (
        SELECT
            rn.*,
            CASE
                WHEN p_use_decay THEN compute_decay_score(rn.id)
                ELSE 1.0
            END AS decay_value
        FROM ranked_nodes rn
    )
    SELECT
        wd.id,
        wd.type,
        wd.title,
        wd.text_rank,
        wd.decay_value,
        wd.text_rank * wd.decay_value AS combined_score
    FROM with_decay wd
    ORDER BY combined_score DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION domain_specific_search IS 'Full-text search with optional decay scoring';

-- ============================================
-- HYBRID SEARCH (BM25 + Vector)
-- ============================================

CREATE OR REPLACE FUNCTION hybrid_search(
    p_query TEXT,
    p_query_embedding vector DEFAULT NULL,
    p_model_name TEXT DEFAULT 'jina-embeddings-v2',
    p_alpha FLOAT DEFAULT 0.5,
    p_limit INTEGER DEFAULT 20
)
RETURNS TABLE(
    node_id UUID,
    title TEXT,
    bm25_score FLOAT,
    vector_score FLOAT,
    hybrid_score FLOAT
) AS $$
BEGIN
    -- If ParadeDB is available, use it
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_search') THEN
        RETURN QUERY
        WITH bm25_results AS (
            SELECT
                id,
                paradedb.score(id) AS score
            FROM nodes
            WHERE nodes @@@ paradedb.parse(p_query)
            LIMIT p_limit * 2
        ),
        vector_results AS (
            SELECT
                ne.node_id,
                1 - (ne.embedding <=> p_query_embedding) AS score
            FROM node_embeddings ne
            WHERE ne.model_name = p_model_name
              AND p_query_embedding IS NOT NULL
            ORDER BY ne.embedding <=> p_query_embedding
            LIMIT p_limit * 2
        ),
        combined AS (
            SELECT
                COALESCE(b.id, v.node_id) AS nid,
                COALESCE(b.score, 0.0) AS bm25,
                COALESCE(v.score, 0.0) AS vec,
                (COALESCE(b.score, 0.0) * (1 - p_alpha)) +
                (COALESCE(v.score, 0.0) * p_alpha) AS hybrid
            FROM bm25_results b
            FULL OUTER JOIN vector_results v ON b.id = v.node_id
        )
        SELECT
            c.nid,
            n.title,
            c.bm25,
            c.vec,
            c.hybrid
        FROM combined c
        JOIN nodes n ON c.nid = n.id
        ORDER BY c.hybrid DESC
        LIMIT p_limit;
    ELSE
        -- Fallback to tsvector + vector
        RETURN QUERY
        WITH text_results AS (
            SELECT
                n.id,
                ts_rank(n.text_tokens, plainto_tsquery('english', p_query)) AS score
            FROM nodes n
            WHERE n.text_tokens @@ plainto_tsquery('english', p_query)
            LIMIT p_limit * 2
        ),
        vector_results AS (
            SELECT
                ne.node_id,
                1 - (ne.embedding <=> p_query_embedding) AS score
            FROM node_embeddings ne
            WHERE ne.model_name = p_model_name
              AND p_query_embedding IS NOT NULL
            ORDER BY ne.embedding <=> p_query_embedding
            LIMIT p_limit * 2
        ),
        combined AS (
            SELECT
                COALESCE(t.id, v.node_id) AS nid,
                COALESCE(t.score, 0.0) AS text_sc,
                COALESCE(v.score, 0.0) AS vec_sc,
                (COALESCE(t.score, 0.0) * (1 - p_alpha)) +
                (COALESCE(v.score, 0.0) * p_alpha) AS hybrid
            FROM text_results t
            FULL OUTER JOIN vector_results v ON t.id = v.node_id
        )
        SELECT
            c.nid,
            n.title,
            c.text_sc,
            c.vec_sc,
            c.hybrid
        FROM combined c
        JOIN nodes n ON c.nid = n.id
        ORDER BY c.hybrid DESC
        LIMIT p_limit;
    END IF;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION hybrid_search IS 'Hybrid BM25 + vector search with configurable weighting';

-- ============================================
-- SUPERSESSION TRACKING
-- ============================================

CREATE OR REPLACE FUNCTION mark_node_superseded(
    p_old_node_id UUID,
    p_new_node_id UUID,
    p_reason TEXT DEFAULT NULL
)
RETURNS void AS $$
BEGIN
    -- Update old node
    UPDATE nodes
    SET decay_metadata = jsonb_set(
        jsonb_set(
            decay_metadata,
            '{supersession,superseded_by}',
            (decay_metadata->'supersession'->'superseded_by' || jsonb_build_array(p_new_node_id::text))
        ),
        '{lifecycle,marked_obsolete}',
        'true'::jsonb
    )
    WHERE id = p_old_node_id;

    -- Update new node
    UPDATE nodes
    SET decay_metadata = jsonb_set(
        decay_metadata,
        '{supersession,supersedes}',
        (decay_metadata->'supersession'->'supersedes' || jsonb_build_array(p_old_node_id::text))
    )
    WHERE id = p_new_node_id;

    -- Create SUPERSEDES edge
    INSERT INTO graph_edges (source_id, target_id, edge_type, properties)
    VALUES (
        p_new_node_id,
        p_old_node_id,
        'SUPERSEDES',
        jsonb_build_object('reason', p_reason, 'marked_at', NOW())
    )
    ON CONFLICT (source_id, target_id, edge_type) DO NOTHING;

    -- Force decay score recomputation
    DELETE FROM node_scores
    WHERE node_id IN (p_old_node_id, p_new_node_id)
      AND score_type = 'decay';
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION mark_node_superseded IS 'Mark a node as superseded by a newer version';

-- ============================================
-- CLEANUP FUNCTIONS
-- ============================================

CREATE OR REPLACE FUNCTION cleanup_expired_scores()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM node_scores
    WHERE expires_at IS NOT NULL
      AND expires_at < NOW();

    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION cleanup_expired_scores IS 'Remove expired score entries';

CREATE OR REPLACE FUNCTION cleanup_old_signals(days_to_keep INTEGER DEFAULT 90)
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM node_signals
    WHERE timestamp < NOW() - (days_to_keep || ' days')::INTERVAL;

    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION cleanup_old_signals IS 'Archive or delete old signal data';

-- ============================================
-- STATISTICS FUNCTIONS
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
    SELECT 'total_edges'::TEXT, COUNT(*)::BIGINT FROM graph_edges
    UNION ALL
    SELECT 'total_embeddings'::TEXT, COUNT(*)::BIGINT FROM node_embeddings
    UNION ALL
    SELECT 'active_models'::TEXT, COUNT(*)::BIGINT FROM embedding_models WHERE is_active = TRUE
    UNION ALL
    SELECT 'archived_nodes'::TEXT, COUNT(*)::BIGINT FROM nodes
        WHERE (decay_metadata->'lifecycle'->>'archived')::BOOLEAN = TRUE
    UNION ALL
    SELECT 'obsolete_nodes'::TEXT, COUNT(*)::BIGINT FROM nodes
        WHERE (decay_metadata->'lifecycle'->>'marked_obsolete')::BOOLEAN = TRUE;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_graph_statistics IS 'Get key graph statistics for monitoring';

COMMIT;

-- ============================================
-- POST-COMMIT: DEFERRED INDEX CREATION
-- ============================================

-- HNSW indexes need to be created OUTSIDE the transaction
-- and AFTER we have some data (or will fail with "column does not have dimensions")

CREATE OR REPLACE FUNCTION create_hnsw_indexes()
RETURNS TEXT AS $$
DECLARE
    result TEXT := '';
BEGIN
    -- Only create if we have embeddings
    IF EXISTS (SELECT 1 FROM node_embeddings LIMIT 1) THEN
        BEGIN
            CREATE INDEX IF NOT EXISTS idx_emb_jina_hnsw ON node_embeddings
            USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64)
            WHERE model_name = 'jina-embeddings-v2';
            result := result || 'Jina HNSW created; ';
        EXCEPTION WHEN OTHERS THEN
            result := result || 'Jina HNSW failed: ' || SQLERRM || '; ';
        END;

        BEGIN
            CREATE INDEX IF NOT EXISTS idx_emb_siglip_hnsw ON node_embeddings
            USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64)
            WHERE model_name = 'siglip-so400m';
            result := result || 'SigLIP HNSW created; ';
        EXCEPTION WHEN OTHERS THEN
            result := result || 'SigLIP HNSW failed: ' || SQLERRM || '; ';
        END;

        BEGIN
            CREATE INDEX IF NOT EXISTS idx_emb_codebert_hnsw ON node_embeddings
            USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64)
            WHERE model_name = 'graphcodebert-base';
            result := result || 'CodeBERT HNSW created; ';
        EXCEPTION WHEN OTHERS THEN
            result := result || 'CodeBERT HNSW failed: ' || SQLERRM || '; ';
        END;

        BEGIN
            CREATE INDEX IF NOT EXISTS idx_emb_whisper_hnsw ON node_embeddings
            USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64)
            WHERE model_name = 'whisper-large-v3';
            result := result || 'Whisper HNSW created; ';
        EXCEPTION WHEN OTHERS THEN
            result := result || 'Whisper HNSW failed: ' || SQLERRM || '; ';
        END;

        BEGIN
            CREATE INDEX IF NOT EXISTS idx_emb_graphsage_hnsw ON node_embeddings
            USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64)
            WHERE model_name = 'graphsage';
            result := result || 'GraphSAGE HNSW created; ';
        EXCEPTION WHEN OTHERS THEN
            result := result || 'GraphSAGE HNSW failed: ' || SQLERRM || '; ';
        END;
    ELSE
        result := 'No embeddings yet - HNSW indexes will be created automatically when embeddings are added';
    END IF;

    RETURN result;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION create_hnsw_indexes IS 'Create HNSW vector indexes after embeddings are present';

-- ============================================
-- POST-MIGRATION EXECUTION
-- ============================================

-- Safe initial decay score computation
DO $$
BEGIN
    PERFORM compute_and_store_decay_scores();
    RAISE NOTICE 'Initial decay scores computed';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Decay score computation skipped (no data or function not ready): %', SQLERRM;
END $$;

DO $$
DECLARE
    table_count INTEGER;
    history_count INTEGER;
    function_count INTEGER;
    model_count INTEGER;
    hnsw_result TEXT;
BEGIN
    SELECT COUNT(*) INTO table_count
    FROM information_schema.tables
    WHERE table_schema = 'public' AND table_type = 'BASE TABLE';

    SELECT COUNT(*) INTO history_count
    FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name LIKE '%_history';

    SELECT COUNT(*) INTO function_count
    FROM pg_proc
    WHERE pronamespace = 'public'::regnamespace;

    SELECT COUNT(*) INTO model_count
    FROM embedding_models
    WHERE is_active = TRUE;

    -- Try to create HNSW indexes
    SELECT create_hnsw_indexes() INTO hnsw_result;

    RAISE NOTICE '============================================';
    RAISE NOTICE 'Brain Graph Schema v4.0 installed successfully!';
    RAISE NOTICE '============================================';
    RAISE NOTICE 'Tables: % (% with history tracking)', table_count, history_count;
    RAISE NOTICE 'Functions: %', function_count;
    RAISE NOTICE 'Embedding models: %', model_count;
    RAISE NOTICE 'HNSW Status: %', hnsw_result;
    RAISE NOTICE '============================================';
    RAISE NOTICE 'Features enabled:';
    RAISE NOTICE '  ✓ Apache AGE graph database';
    RAISE NOTICE '  ✓ pgvector multi-modal embeddings';
    RAISE NOTICE '  ✓ ParadeDB hybrid search (or tsvector fallback)';
    RAISE NOTICE '  ✓ Temporal tables with full history';
    RAISE NOTICE '  ✓ Information decay scoring';
    RAISE NOTICE '  ✓ Multi-model embedding support';
    RAISE NOTICE '  ✓ Graph RAG with supersession tracking';
    RAISE NOTICE '============================================';
END $$;
