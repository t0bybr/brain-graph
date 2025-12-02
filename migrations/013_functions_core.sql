-- ============================================
-- Core Functions: Decay, Signals, Temporal
-- ============================================

\c brain_graph

BEGIN;

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
    decay_score := COALESCE(
        (node_record.decay_metadata->'decay_config'->>'baseline_relevance')::FLOAT,
        1.0
    );
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

-- Batch compute decay scores
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

COMMIT;

DO $$
BEGIN
    RAISE NOTICE '✓ Core functions created:';
    RAISE NOTICE '  • track_node_access';
    RAISE NOTICE '  • compute_decay_score / compute_and_store_decay_scores';
    RAISE NOTICE '  • get_graph_at_time';
    RAISE NOTICE '  • mark_node_superseded';
    RAISE NOTICE '  • cleanup_expired_scores / cleanup_old_signals';
END $$;
