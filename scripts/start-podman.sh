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

# Wait for PostgreSQL to be ready and complete initialization
echo "Waiting for PostgreSQL initialization..."
until podman exec brain_graph_db pg_isready -U postgres > /dev/null 2>&1; do
    echo -n "."
    sleep 1
done

# Additional check: make sure database is fully initialized and ready
echo -n "Waiting for database initialization to complete"
for i in {1..60}; do
    if podman exec brain_graph_db psql -U postgres -d brain_graph -c "SELECT 1 FROM pg_tables WHERE tablename='nodes' LIMIT 1" > /dev/null 2>&1; then
        echo " ✅"
        echo "✅ Database initialized successfully!"
        break
    fi
    echo -n "."
    sleep 2
    if [ $i -eq 60 ]; then
        echo " ⚠️"
        echo "⚠️  Database initialization may still be in progress"
        echo "    Check logs with: podman logs brain_graph_db"
    fi
done

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
