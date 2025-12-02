#!/bin/bash

set -e

echo "🚀 Starting Brain Graph with Podman..."

# Load environment
if [ ! -f .env ]; then
    echo "❌ .env file not found!"
    cp .env.example .env
    echo "⚠️  Please edit .env and run again"
    exit 1
fi

source .env

# Ensure XDG_RUNTIME_DIR
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# Check Podman socket
if [ ! -S "$XDG_RUNTIME_DIR/podman/podman.sock" ]; then
    echo "Starting Podman socket..."
    systemctl --user enable --now podman.socket
    sleep 2
fi

# Create networks
echo "Setting up Podman networks..."
podman network exists brain_graph_network || podman network create brain_graph_network
podman network exists traefik_public || podman network create traefik_public

# Create directories
mkdir -p docker/prometheus/data docker/grafana/data docker/traefik/certs storage

# SELinux
if command -v getenforce &> /dev/null && [ "$(getenforce)" != "Disabled" ]; then
    echo "Setting SELinux contexts..."
    sudo chcon -R -t container_file_t ./storage 2>/dev/null || true
    sudo chcon -R -t container_file_t ./docker 2>/dev/null || true
fi

# Start infrastructure
echo "Starting infrastructure..."
podman-compose -f podman-compose.yml up -d traefik postgres redis prometheus grafana

# Wait for PostgreSQL
echo "Waiting for PostgreSQL..."
until podman exec brain_graph_db pg_isready -U postgres > /dev/null 2>&1; do
    echo -n "."
    sleep 1
done
echo " ✅"

# Run migrations in order
echo "Running migrations..."

# 1. Init database & user
echo "  1/3 Initializing database..."
podman exec -i brain_graph_db psql -U postgres < migrations/000_init_database.sql

# 2. Pre-init (search_path)
echo "  2/3 Setting up search path..."
podman exec -i brain_graph_db psql -U postgres < migrations/001_pre_init.sql

# 3. Main schema
echo "  3/3 Creating schema..."
podman exec -i brain_graph_db psql -U postgres -d brain_graph < migrations/002_brain_graph_complete_v3.sql

echo "✅ Migrations complete"

# Start services
# echo "Starting application services..."
# podman-compose -f podman-compose.yml up -d backend worker beat

echo ""
echo "✅ Brain Graph is running!"
echo ""
echo "🌐 Services:"
echo "  API:           http://localhost:8000"
echo "  API Docs:      http://localhost:8000/docs"
echo "  PostgreSQL:    localhost:5432"
echo "  Redis:         localhost:6379"
echo ""
echo "📊 Check status:  podman ps"
echo "📝 View logs:     make logs"
echo ""
