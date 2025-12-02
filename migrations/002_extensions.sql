-- ============================================
-- Extensions
-- Run after 001_pre_init.sql
-- ============================================

\c brain_graph

-- Core extensions (these should always work)
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Temporal tables (requires installation)
DO $$
BEGIN
    CREATE EXTENSION IF NOT EXISTS temporal_tables;
    RAISE NOTICE '✓ temporal_tables extension loaded';
EXCEPTION
    WHEN OTHERS THEN
        RAISE WARNING '✗ temporal_tables not available: %', SQLERRM;
END $$;

-- ParadeDB (optional, for BM25)
DO $$
BEGIN
    CREATE EXTENSION IF NOT EXISTS pg_search;
    RAISE NOTICE '✓ pg_search (ParadeDB) extension loaded';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '○ pg_search not available - will use tsvector fallback';
END $$;

-- Apache AGE (optional, for graph queries)
DO $$
BEGIN
    CREATE EXTENSION IF NOT EXISTS age;
    RAISE NOTICE '✓ age extension loaded';
EXCEPTION
    WHEN OTHERS THEN
        RAISE WARNING '○ age extension not available: %', SQLERRM;
END $$;

-- Verify loaded extensions
DO $$
DECLARE
    ext RECORD;
BEGIN
    RAISE NOTICE '============================================';
    RAISE NOTICE 'Loaded extensions:';
    FOR ext IN SELECT extname, extversion FROM pg_extension ORDER BY extname LOOP
        RAISE NOTICE '  • % (%)', ext.extname, ext.extversion;
    END LOOP;
    RAISE NOTICE '============================================';
END $$;
