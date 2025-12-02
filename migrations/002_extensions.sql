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

-- ULID Generator (pure SQL implementation)
-- Generates 26-character ULIDs: 10 char timestamp + 16 char randomness
-- Format: TTTTTTTTTTRRRRRRRRRRRRRRRR (Crockford's Base32)
CREATE OR REPLACE FUNCTION generate_ulid()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    encoding   TEXT := '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
    timestamp  BIGINT;
    output     TEXT := '';
    bytes      BYTEA;
    v          BIGINT;
BEGIN
    -- Current timestamp in milliseconds (48 bits)
    timestamp := (EXTRACT(EPOCH FROM clock_timestamp()) * 1000)::BIGINT;

    -- Encode timestamp as 10 base32 characters (big-endian)
    FOR i IN 0..9 LOOP
        output := output || substr(encoding, ((timestamp >> (5 * (9 - i))) & 31)::INT + 1, 1);
    END LOOP;

    -- Generate 80 random bits as 10 bytes
    bytes := gen_random_bytes(10);

    -- Encode 16 base32 characters from 10 bytes (80 bits)
    -- Each base32 char = 5 bits, so 16 chars = 80 bits
    FOR i IN 0..15 LOOP
        -- Calculate which bits to extract
        v := get_byte(bytes, (i * 5) / 8)::BIGINT << 8;
        IF ((i * 5) / 8) + 1 < 10 THEN
            v := v | get_byte(bytes, ((i * 5) / 8) + 1)::BIGINT;
        END IF;
        v := (v >> (11 - ((i * 5) % 8))) & 31;
        output := output || substr(encoding, v::INT + 1, 1);
    END LOOP;

    RETURN output;
END;
$$;

DO $$
BEGIN
    RAISE NOTICE '✓ ULID generator function created';
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
