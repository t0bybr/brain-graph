-- ============================================
-- Pre-Migration Setup
-- Run AFTER 000_init_database.sql (NO TRANSACTION!)
-- ============================================

\c brain_graph

-- Set search_path for the app role
DO $$
BEGIN
    EXECUTE 'ALTER ROLE brain_graph_app SET search_path TO ag_catalog, "$user", public';
    RAISE NOTICE 'Search path configured for brain_graph_app';
EXCEPTION
    WHEN undefined_object THEN
        RAISE WARNING 'Role brain_graph_app does not exist yet';
END
$$;

-- Verify
SELECT rolname, rolconfig
FROM pg_roles
WHERE rolname = 'brain_graph_app';
