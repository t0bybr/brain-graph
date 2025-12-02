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

init_dagrations
echo "Running migrations..."
docker-compose exec -T postgres psql -U postgres -d brain_graph -f /docker-entrypoint-initdb.d/000_init_database.sql || true
docker-compose exec -T postgres psql -U postgres -d brain_graph -f /docker-entrypoint-initdb.d/001_pre_init.sql || true
docker-compose exec -T postgres psql -U postgres -d brain_graph -f /docker-entrypoint-initdb.d/002_brain_graph_complete_v3.sql

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
