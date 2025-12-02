-- ============================================
-- Database & User Initialization
-- Run this FIRST (outside transaction)
-- ============================================

-- Create database if not exists
SELECT 'CREATE DATABASE brain_graph'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'brain_graph')\gexec

-- Connect to brain_graph
\c brain_graph

-- Create user if not exists
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'brain_graph_app') THEN
        CREATE ROLE brain_graph_app WITH LOGIN PASSWORD 'changeme';
        RAISE NOTICE 'Created role brain_graph_app';
    ELSE
        RAISE NOTICE 'Role brain_graph_app already exists';
    END IF;
END
$$;

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE brain_graph TO brain_graph_app;
GRANT ALL ON SCHEMA public TO brain_graph_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO brain_graph_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO brain_graph_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO brain_graph_app;
