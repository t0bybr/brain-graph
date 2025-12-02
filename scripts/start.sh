#!/bin/bash

echo "🚀 Starting Brain Graph with Traefik..."

# Check if .env exists
if [ ! -f .env ]; then
    echo "❌ .env file not found!"
    echo "Creating from .env.example..."
    cp .env.example .env
    echo "⚠️  Please edit .env with your settings"
    exit 1
fi

# Load environment
source .env

# Create traefik certs directory
mkdir -p docker/traefik/certs
chmod 600 docker/traefik/certs

# Create prometheus/grafana data directories
mkdir -p docker/prometheus/data
mkdir -p docker/grafana/data

# Start infrastructure
echo "Starting infrastructure..."
docker-compose up -d traefik postgres redis prometheus grafana

# Wait for postgres
echo "Waiting for PostgreSQL..."
until docker-compose exec -T postgres pg_isready -U postgres > /dev/null 2>&1; do
    echo -n "."
    sleep 1
done
echo "✅ PostgreSQL ready"

# Run migrations in order
echo "Running migrations..."

# 1. Init database & user
echo "  1/18 Initializing database..."
docker-compose exec -T postgres psql -U postgres < migrations/000_init_database.sql

# 2. Pre-init (search_path)
echo "  2/18 Setting up search path..."
docker-compose exec -T postgres psql -U postgres < migrations/001_pre_init.sql

# Switch to brain_graph database for remaining migrations
echo "  3/18 Installing extensions..."
docker-compose exec -T postgres psql -U postgres -d brain_graph < migrations/002_extensions.sql

echo "  4/18 Creating custom types..."
docker-compose exec -T postgres psql -U postgres -d brain_graph < migrations/003_types.sql

echo "  5/18 Creating core tables..."
docker-compose exec -T postgres psql -U postgres -d brain_graph < migrations/004_core_tables.sql

echo "  6/18 Creating embedding tables..."
docker-compose exec -T postgres psql -U postgres -d brain_graph < migrations/005_embeddings.sql

echo "  7/18 Creating taxonomy tables..."
docker-compose exec -T postgres psql -U postgres -d brain_graph < migrations/006_taxonomy.sql

echo "  8/18 Creating graph tables..."
docker-compose exec -T postgres psql -U postgres -d brain_graph < migrations/007_graph.sql

echo "  9/18 Creating document tables..."
docker-compose exec -T postgres psql -U postgres -d brain_graph < migrations/008_documents.sql

echo " 10/18 Creating signals/scores tables..."
docker-compose exec -T postgres psql -U postgres -d brain_graph < migrations/009_signals_scores.sql

echo " 11/18 Creating chunk tables..."
docker-compose exec -T postgres psql -U postgres -d brain_graph < migrations/010_chunks.sql

echo " 12/18 Creating triggers..."
docker-compose exec -T postgres psql -U postgres -d brain_graph < migrations/011_triggers.sql

echo " 13/18 Setting up Apache AGE..."
docker-compose exec -T postgres psql -U postgres -d brain_graph < migrations/012_age.sql

echo " 14/18 Creating core functions..."
docker-compose exec -T postgres psql -U postgres -d brain_graph < migrations/013_functions_core.sql

echo " 15/18 Creating search functions..."
docker-compose exec -T postgres psql -U postgres -d brain_graph < migrations/014_functions_search.sql

echo " 16/18 Creating stats functions..."
docker-compose exec -T postgres psql -U postgres -d brain_graph < migrations/015_functions_stats.sql

echo " 17/18 Creating HNSW indexes..."
docker-compose exec -T postgres psql -U postgres -d brain_graph < migrations/016_indexes_hnsw.sql

echo " 18/18 Migrations complete ✅"

# Start encoders (Phase 1: Text only for now)
echo "Starting encoders..."
docker-compose up -d jina

# Start application
echo "Starting application..."
docker-compose up -d backend worker beat flower

# Start frontend
echo "Starting frontend..."
docker-compose up -d frontend

# Wait a bit for everything to stabilize
sleep 5

echo ""
echo "✅ Brain Graph is running!"
echo ""
echo "🌐 Services:"
echo "  Frontend:      http://${DOMAIN}"
echo "  API:           http://api.${DOMAIN}"
echo "  API Docs:      http://api.${DOMAIN}/docs"
echo "  Traefik:       http://traefik.${DOMAIN}:8080"
echo "  Grafana:       http://grafana.${DOMAIN}"
echo "  Prometheus:    http://prometheus.${DOMAIN}"
echo "  Flower:        http://flower.${DOMAIN}"
echo ""
echo "🤖 Encoders:"
echo "  Jina:          http://jina.${DOMAIN}"
echo ""
echo "🗄️  Database:     localhost:5432"
echo "🔴 Redis:        localhost:6379"
echo ""

# Add hosts entries reminder for localhost
if [ "$DOMAIN" = "localhost" ]; then
    echo "💡 For subdomain routing on localhost, add to /etc/hosts:"
    echo "   127.0.0.1 api.localhost traefik.localhost grafana.localhost prometheus.localhost flower.localhost jina.localhost"
    echo ""
fi
