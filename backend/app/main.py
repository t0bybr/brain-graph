from contextlib import asynccontextmanager

from app.api import edges, embeddings, nodes, search, taxonomy
from app.database import close_db_pool, init_db_pool
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    print("🚀 Starting Brain Graph API...")
    await init_db_pool()
    print("✅ Database pool initialized")

    yield

    # Shutdown
    print("👋 Shutting down...")
    await close_db_pool()
    print("✅ Database pool closed")


app = FastAPI(
    title="Brain Graph API",
    description="Personal Knowledge Management System",
    version="3.0.0",
    lifespan=lifespan,
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Routes
app.include_router(nodes.router, prefix="/api/nodes", tags=["nodes"])
app.include_router(edges.router, prefix="/api/edges", tags=["edges"])
app.include_router(search.router, prefix="/api/search", tags=["search"])
app.include_router(taxonomy.router, prefix="/api/taxonomy", tags=["taxonomy"])
app.include_router(embeddings.router, prefix="/api/embeddings", tags=["embeddings"])


@app.get("/health")
async def health():
    return {"status": "healthy"}


@app.get("/")
async def root():
    return {"name": "Brain Graph API", "version": "3.0.0", "docs": "/docs"}
