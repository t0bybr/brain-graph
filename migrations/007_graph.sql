-- ============================================
-- Graph: Edges, Entities, Relationships
-- ============================================

\c brain_graph

BEGIN;

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

-- History table
CREATE TABLE IF NOT EXISTS graph_edges_history (LIKE graph_edges);

-- ============================================
-- EDGE INDEXES
-- ============================================

CREATE INDEX IF NOT EXISTS idx_edges_source ON graph_edges(source_id);
CREATE INDEX IF NOT EXISTS idx_edges_target ON graph_edges(target_id);
CREATE INDEX IF NOT EXISTS idx_edges_type ON graph_edges(edge_type);
CREATE INDEX IF NOT EXISTS idx_edges_source_type ON graph_edges(source_id, edge_type);
CREATE INDEX IF NOT EXISTS idx_edges_target_type ON graph_edges(target_id, edge_type);
CREATE INDEX IF NOT EXISTS idx_edges_properties ON graph_edges USING GIN (properties);
CREATE INDEX IF NOT EXISTS idx_edges_created_by ON graph_edges(created_by);

CREATE INDEX IF NOT EXISTS idx_edges_history_source ON graph_edges_history(source_id);
CREATE INDEX IF NOT EXISTS idx_edges_history_target ON graph_edges_history(target_id);
CREATE INDEX IF NOT EXISTS idx_edges_history_type ON graph_edges_history(edge_type);
CREATE INDEX IF NOT EXISTS idx_edges_history_sys_period ON graph_edges_history USING GIST (sys_period);

COMMENT ON TABLE graph_edges IS 'Graph relationships between nodes. Types include:
  LINKS_TO, SIMILAR_TO, IN_CATEGORY, PART_OF, CREATED_DURING, 
  AT_LOCATION, AUTHORED, MENTIONED_IN, SYNTHESIZES, CONSOLIDATES, 
  SUPERSEDES, HAS_IMAGE, ILLUSTRATED_BY, REFERENCES, etc.';

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

CREATE INDEX IF NOT EXISTS idx_rejected_edges_expires ON rejected_edges(expires_at)
    WHERE expires_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_rejected_edges_rejected_by ON rejected_edges(rejected_by);

COMMENT ON TABLE rejected_edges IS 'Tracks user-rejected or invalid edge suggestions to avoid re-proposing';

-- ============================================
-- GRAPH NODES (Mirror for AGE tracking)
-- ============================================

CREATE TABLE IF NOT EXISTS graph_nodes (
    node_id UUID PRIMARY KEY REFERENCES nodes(id) ON DELETE CASCADE,
    graph_label VARCHAR(50) NOT NULL,
    created_in_graph_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_graph_nodes_label ON graph_nodes(graph_label);

COMMENT ON TABLE graph_nodes IS 'Mirror of nodes that exist in AGE graph database';

-- ============================================
-- ENTITIES (NER/Named Entity Recognition)
-- ============================================

CREATE TABLE IF NOT EXISTS entities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_type VARCHAR(50) NOT NULL,  -- PERSON, ORG, LOCATION, PROJECT, EVENT
    canonical_name TEXT NOT NULL,
    normalized_name TEXT NOT NULL,  -- lowercase, trimmed for dedup
    
    metadata JSONB DEFAULT '{}',
    merged_into UUID REFERENCES entities(id) ON DELETE SET NULL,
    
    created_at TIMESTAMP DEFAULT NOW(),
    
    UNIQUE (entity_type, normalized_name)
);

CREATE INDEX IF NOT EXISTS idx_entities_type ON entities(entity_type);
CREATE INDEX IF NOT EXISTS idx_entities_canonical ON entities(canonical_name);
CREATE INDEX IF NOT EXISTS idx_entities_metadata ON entities USING GIN (metadata);

COMMENT ON TABLE entities IS 'Named entities: PERSON, ORG, LOCATION, PROJECT, EVENT extracted via NER';

-- ============================================
-- NODE <-> ENTITY RELATIONSHIPS
-- ============================================

CREATE TABLE IF NOT EXISTS node_entities (
    node_id UUID NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
    entity_id UUID NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
    role VARCHAR(50) NOT NULL,  -- author, mentioned, location, etc.
    confidence FLOAT CHECK (confidence BETWEEN 0 AND 1),
    source VARCHAR(100),  -- which NER model extracted this
    span_start INTEGER,   -- character position in text
    span_end INTEGER,
    created_at TIMESTAMP DEFAULT NOW(),
    
    PRIMARY KEY (node_id, entity_id, role)
);

CREATE INDEX IF NOT EXISTS idx_node_entities_node ON node_entities(node_id);
CREATE INDEX IF NOT EXISTS idx_node_entities_entity ON node_entities(entity_id);
CREATE INDEX IF NOT EXISTS idx_node_entities_role ON node_entities(role);
CREATE INDEX IF NOT EXISTS idx_node_entities_confidence ON node_entities(confidence DESC);

COMMENT ON TABLE node_entities IS 'Links nodes to extracted entities with role and confidence';

COMMIT;

DO $$
BEGIN
    RAISE NOTICE '✓ Graph tables created:';
    RAISE NOTICE '  • graph_edges + history';
    RAISE NOTICE '  • rejected_edges';
    RAISE NOTICE '  • graph_nodes';
    RAISE NOTICE '  • entities + node_entities';
END $$;
