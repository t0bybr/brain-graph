async def store_embedding(
    self,
    node_id: UUID,
    modality: str,
    model_name: str,
    source_part: str,
    embedding: List[float],
    content_hash: str,
) -> UUID:
    """Store embedding and ensure HNSW index exists"""

    # Store embedding
    embedding_id = await self._store_to_db(...)

    # After first embedding, create HNSW indexes
    await self._ensure_hnsw_indexes()

    return embedding_id


async def _ensure_hnsw_indexes(self):
    """Create HNSW indexes if they don't exist yet"""
    try:
        result = await self.db.execute("SELECT create_hnsw_indexes()")
        print(f"HNSW index status: {result}")
    except Exception as e:
        print(f"HNSW index creation skipped: {e}")
