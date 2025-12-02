-- ============================================
-- Triggers: Timestamps & Temporal Versioning
-- ============================================

\c brain_graph

BEGIN;

-- ============================================
-- UPDATED_AT TRIGGER
-- ============================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply to nodes
DROP TRIGGER IF EXISTS update_nodes_updated_at ON nodes;
CREATE TRIGGER update_nodes_updated_at
    BEFORE UPDATE ON nodes
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Apply to chunks
DROP TRIGGER IF EXISTS update_chunks_updated_at ON node_chunks;
CREATE TRIGGER update_chunks_updated_at
    BEFORE UPDATE ON node_chunks
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- TEMPORAL VERSIONING TRIGGERS
-- ============================================
-- These require the temporal_tables extension

DO $$
BEGIN
    -- Check if versioning function exists
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'versioning') THEN
        
        -- Nodes versioning
        DROP TRIGGER IF EXISTS nodes_versioning_trigger ON nodes;
        CREATE TRIGGER nodes_versioning_trigger
            BEFORE INSERT OR UPDATE OR DELETE ON nodes
            FOR EACH ROW EXECUTE FUNCTION versioning('sys_period', 'nodes_history', true);
        RAISE NOTICE '✓ nodes_versioning_trigger created';
        
        -- Taxonomy versioning
        DROP TRIGGER IF EXISTS taxonomy_versioning_trigger ON taxonomy;
        CREATE TRIGGER taxonomy_versioning_trigger
            BEFORE INSERT OR UPDATE OR DELETE ON taxonomy
            FOR EACH ROW EXECUTE FUNCTION versioning('sys_period', 'taxonomy_history', true);
        RAISE NOTICE '✓ taxonomy_versioning_trigger created';
        
        -- Graph edges versioning
        DROP TRIGGER IF EXISTS edges_versioning_trigger ON graph_edges;
        CREATE TRIGGER edges_versioning_trigger
            BEFORE INSERT OR UPDATE OR DELETE ON graph_edges
            FOR EACH ROW EXECUTE FUNCTION versioning('sys_period', 'graph_edges_history', true);
        RAISE NOTICE '✓ edges_versioning_trigger created';
        
    ELSE
        RAISE WARNING '○ temporal_tables extension not available - versioning triggers not created';
        RAISE NOTICE '  Install temporal_tables to enable history tracking';
    END IF;
END $$;

COMMIT;

DO $$
DECLARE
    trigger_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO trigger_count
    FROM information_schema.triggers 
    WHERE trigger_schema = 'public';
    
    RAISE NOTICE '✓ Triggers configured: % total', trigger_count;
END $$;
