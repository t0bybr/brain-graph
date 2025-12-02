-- ============================================
-- Taxonomy & Categories
-- ============================================

\c brain_graph

BEGIN;

-- ============================================
-- TAXONOMY (WITH TEMPORAL)
-- ============================================

CREATE TABLE IF NOT EXISTS taxonomy (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    parent_id INTEGER REFERENCES taxonomy(id) ON DELETE CASCADE,
    level INTEGER NOT NULL CHECK (level >= 0 AND level <= 5),
    path TEXT UNIQUE NOT NULL,  -- e.g., "tech/programming/python"
    
    -- Meta Fields (for decay computation)
    topic_importance INTEGER DEFAULT 5 CHECK (topic_importance BETWEEN 1 AND 10),
    change_velocity INTEGER DEFAULT 5 CHECK (change_velocity BETWEEN 1 AND 10),
    usage_focus INTEGER DEFAULT 5 CHECK (usage_focus BETWEEN 1 AND 10),
    
    -- Discovery helpers
    keywords TEXT[],
    related_categories JSONB DEFAULT '[]',
    
    -- Timestamps
    created_at TIMESTAMP DEFAULT NOW(),
    sys_period tstzrange NOT NULL DEFAULT tstzrange(current_timestamp, null)
);

-- History table
CREATE TABLE IF NOT EXISTS taxonomy_history (LIKE taxonomy);

-- ============================================
-- INDEXES
-- ============================================

CREATE INDEX IF NOT EXISTS idx_taxonomy_parent ON taxonomy(parent_id);
CREATE INDEX IF NOT EXISTS idx_taxonomy_path ON taxonomy(path);
CREATE INDEX IF NOT EXISTS idx_taxonomy_level ON taxonomy(level);
CREATE INDEX IF NOT EXISTS idx_taxonomy_change_velocity ON taxonomy(change_velocity);
CREATE INDEX IF NOT EXISTS idx_taxonomy_keywords ON taxonomy USING GIN (keywords);

CREATE INDEX IF NOT EXISTS idx_taxonomy_history_id ON taxonomy_history(id);
CREATE INDEX IF NOT EXISTS idx_taxonomy_history_sys_period ON taxonomy_history USING GIST (sys_period);

-- ============================================
-- COMMENTS
-- ============================================

COMMENT ON TABLE taxonomy IS 'Hierarchical category tree with decay parameters';
COMMENT ON COLUMN taxonomy.topic_importance IS 'Overall topic importance (1-10)';
COMMENT ON COLUMN taxonomy.change_velocity IS 'How quickly content becomes outdated (1-10): 1-3=stable, 4-7=medium, 8-10=fast';
COMMENT ON COLUMN taxonomy.usage_focus IS 'Weight of usage frequency in ranking (1-10)';

-- ============================================
-- NODE CATEGORIES (Many-to-Many)
-- ============================================

CREATE TABLE IF NOT EXISTS node_categories (
    node_id UUID REFERENCES nodes(id) ON DELETE CASCADE,
    category_id INTEGER REFERENCES taxonomy(id) ON DELETE CASCADE,
    confidence FLOAT NOT NULL CHECK (confidence BETWEEN 0 AND 1),
    assigned_by VARCHAR(10) NOT NULL CHECK (assigned_by IN ('user', 'llm')),
    assigned_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (node_id, category_id)
);

CREATE INDEX IF NOT EXISTS idx_node_categories_node ON node_categories(node_id);
CREATE INDEX IF NOT EXISTS idx_node_categories_category ON node_categories(category_id);
CREATE INDEX IF NOT EXISTS idx_node_categories_confidence ON node_categories(confidence DESC);

COMMENT ON TABLE node_categories IS 'Maps nodes to taxonomy categories with confidence scores';

COMMIT;

DO $$
BEGIN
    RAISE NOTICE '✓ Taxonomy tables created: taxonomy, taxonomy_history, node_categories';
END $$;
