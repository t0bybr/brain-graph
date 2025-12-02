-- ============================================
-- Types (ENUMs)
-- ============================================

\c brain_graph

BEGIN;

-- Drop existing types if they exist (for clean migrations)
DROP TYPE IF EXISTS node_type CASCADE;
DROP TYPE IF EXISTS signal_type CASCADE;
DROP TYPE IF EXISTS score_type CASCADE;
DROP TYPE IF EXISTS chunking_method CASCADE;

-- Node types
CREATE TYPE node_type AS ENUM (
    -- Content Nodes
    'TextNode',
    'ImageNode',
    'AudioNode',
    'VideoNode',
    
    -- Communication Nodes
    'EmailNode',
    'MessageNode',
    
    -- Knowledge Nodes
    'BookNode',
    'PaperNode',
    'ArticleNode',
    
    -- Structural Nodes (Hubs)
    'PersonNode',
    'TripNode',
    'EventNode',
    'ProjectNode',
    'LocationNode',
    'OrganizationNode',
    
    -- Meta Nodes
    'SummaryNode',
    'TopicNode',
    'ConsolidationNode',
    'TrendNode',
    
    -- Chunk Node (for graph representation)
    'ChunkNode'
);

-- Signal types for tracking user interactions
CREATE TYPE signal_type AS ENUM (
    'view',
    'edit',
    'search_click',
    'share',
    'link_created',
    'mention',
    'export',
    'tag_added'
);

-- Score types for computed metrics
CREATE TYPE score_type AS ENUM (
    'decay',
    'importance',
    'novelty',
    'quality',
    'forecast_interest',
    'community_relevance'
);

-- Chunking methods
CREATE TYPE chunking_method AS ENUM (
    'semantic',           -- Embedding-based boundaries (Chonkie)
    'fixed',              -- Fixed token/character count
    'sentence',           -- Sentence-based
    'paragraph',          -- Paragraph-based
    'markdown_header',    -- Markdown ## hierarchy
    'code_ast',           -- Tree-sitter AST
    'code_function',      -- Function/method level
    'code_class',         -- Class level
    'page'                -- PDF/Doc page-based
);

COMMIT;

DO $$
BEGIN
    RAISE NOTICE '✓ Types created: node_type, signal_type, score_type, chunking_method';
END $$;
