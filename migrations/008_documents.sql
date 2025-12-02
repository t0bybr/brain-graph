-- ============================================
-- Documents & Layout Blocks
-- ============================================

\c brain_graph

BEGIN;

-- ============================================
-- DOCUMENTS (PDFs, Scans, etc.)
-- ============================================

CREATE TABLE IF NOT EXISTS documents (
    id TEXT PRIMARY KEY DEFAULT generate_ulid(),
    node_id TEXT REFERENCES nodes(id) ON DELETE SET NULL,
    
    -- Source info
    source_path TEXT,
    source_url TEXT,
    mime_type VARCHAR(100),
    file_size_bytes BIGINT,
    
    -- Document properties
    page_count INTEGER,
    language VARCHAR(10),
    
    -- Processing info
    processed_by VARCHAR(100),  -- e.g., 'unstructured', 'marker', 'pypdf'
    processed_at TIMESTAMP,
    
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_documents_node ON documents(node_id);
CREATE INDEX IF NOT EXISTS idx_documents_mime ON documents(mime_type);

COMMENT ON TABLE documents IS 'Source document metadata for PDFs, scans, etc.';

-- ============================================
-- DOCUMENT BLOCKS (Layout-Aware Extraction)
-- ============================================

CREATE TABLE IF NOT EXISTS document_blocks (
    id TEXT PRIMARY KEY DEFAULT generate_ulid(),
    document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    
    -- Position
    page INTEGER NOT NULL,
    block_index INTEGER NOT NULL,
    
    -- Content
    block_type VARCHAR(50),  -- text, image, table, header, footer, etc.
    text_content TEXT,
    
    -- Bounding box (normalized 0-1)
    bbox_x0 FLOAT,
    bbox_y0 FLOAT,
    bbox_x1 FLOAT,
    bbox_y1 FLOAT,
    
    -- Raw extraction output
    raw_output JSONB,
    confidence FLOAT,
    
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_blocks_document_page ON document_blocks(document_id, page, block_index);
CREATE INDEX IF NOT EXISTS idx_blocks_type ON document_blocks(block_type);

-- Full-text search on blocks
ALTER TABLE document_blocks ADD COLUMN IF NOT EXISTS text_tokens tsvector
    GENERATED ALWAYS AS (to_tsvector('english', COALESCE(text_content, ''))) STORED;
CREATE INDEX IF NOT EXISTS idx_blocks_fts ON document_blocks USING GIN (text_tokens);

COMMENT ON TABLE document_blocks IS 'Document layout blocks (text, image, table) with bbox coordinates';

COMMIT;

DO $$
BEGIN
    RAISE NOTICE '✓ Document tables created: documents, document_blocks';
END $$;
