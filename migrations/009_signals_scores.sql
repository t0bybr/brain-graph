-- ============================================
-- Signals, Scores, Searches
-- ============================================

\c brain_graph

BEGIN;

-- ============================================
-- NODE SIGNALS (Time-Series Events)
-- ============================================

CREATE TABLE IF NOT EXISTS node_signals (
    id TEXT PRIMARY KEY DEFAULT generate_ulid(),
    node_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
    signal_type signal_type NOT NULL,
    value FLOAT DEFAULT 1.0,
    metadata JSONB DEFAULT '{}',
    timestamp TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_signals_node_ts ON node_signals(node_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_signals_type_ts ON node_signals(signal_type, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_signals_recent ON node_signals(timestamp DESC);

COMMENT ON TABLE node_signals IS 'Time-series user interaction signals for decay computation';

-- ============================================
-- NODE SCORES (Derived Metrics)
-- ============================================

CREATE TABLE IF NOT EXISTS node_scores (
    node_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
    score_type score_type NOT NULL,
    model_name VARCHAR(100) DEFAULT 'default',
    value FLOAT NOT NULL,
    confidence FLOAT,
    metadata JSONB DEFAULT '{}',
    computed_at TIMESTAMP DEFAULT NOW(),
    expires_at TIMESTAMP,
    
    PRIMARY KEY (node_id, score_type, model_name)
);

CREATE INDEX IF NOT EXISTS idx_scores_type_value ON node_scores(score_type, value DESC);
CREATE INDEX IF NOT EXISTS idx_scores_expires ON node_scores(expires_at) WHERE expires_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_scores_node_type ON node_scores(node_id, score_type);

COMMENT ON TABLE node_scores IS 'Computed scores: decay, importance, novelty, quality, forecast_interest';

-- ============================================
-- SEARCHES (Persistent & Auto-Updating)
-- ============================================

CREATE TABLE IF NOT EXISTS searches (
    id TEXT PRIMARY KEY DEFAULT generate_ulid(),
    node_id TEXT REFERENCES nodes(id) ON DELETE CASCADE,  -- Optional linked SearchNode
    title TEXT NOT NULL,
    query JSONB NOT NULL,  -- Full search parameters
    is_persistent BOOLEAN DEFAULT FALSE,
    auto_update BOOLEAN DEFAULT FALSE,
    update_frequency INTERVAL,
    last_updated TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    execution_count INTEGER DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_searches_persistent ON searches(is_persistent);
CREATE INDEX IF NOT EXISTS idx_searches_auto_update ON searches(auto_update) WHERE auto_update = true;
CREATE INDEX IF NOT EXISTS idx_searches_node_id ON searches(node_id) WHERE node_id IS NOT NULL;

COMMENT ON TABLE searches IS 'Saved searches that can auto-update and create SearchNode results';

COMMIT;

DO $$
BEGIN
    RAISE NOTICE '✓ Signal/Score tables created: node_signals, node_scores, searches';
END $$;
