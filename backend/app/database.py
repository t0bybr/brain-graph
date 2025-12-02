import os
from contextlib import asynccontextmanager
from typing import AsyncGenerator

import asyncpg

DATABASE_URL = os.getenv("DATABASE_URL")

_pool: asyncpg.Pool = None


async def init_connection(conn):
    """Called for each new connection in pool"""
    try:
        await conn.execute("LOAD 'age'")
    except asyncpg.exceptions.InsufficientPrivilegeError:
        pass
    except Exception as e:
        print(f"Warning: Could not load AGE: {e}")

    await conn.execute('SET search_path = ag_catalog, "$user", public')

    try:
        await conn.fetchval("SELECT ag_catalog.agtype_in('1')")
    except Exception as e:
        raise RuntimeError(
            "AGE is not available. Ensure 'age' is in shared_preload_libraries"
        ) from e


async def init_db_pool():
    global _pool

    _pool = await asyncpg.create_pool(
        DATABASE_URL, min_size=5, max_size=20, init=init_connection, command_timeout=60
    )

    async with _pool.acquire() as conn:
        result = await conn.fetchval("SELECT 1")
        assert result == 1

    return _pool


async def close_db_pool():
    global _pool
    if _pool:
        await _pool.close()


@asynccontextmanager
async def get_db() -> AsyncGenerator[asyncpg.Connection, None]:
    async with _pool.acquire() as conn:
        yield conn
