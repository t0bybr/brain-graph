#!/bin/bash

echo "🔒 Setting up SELinux contexts for Podman..."

# Directories that need container access
DIRS=(
    "docker/traefik/certs"
    "docker/traefik/dynamic"
    "docker/postgres"
    "docker/prometheus/data"
    "docker/grafana/data"
    "docker/redis"
    "storage"
    "migrations"
    "backend"
    "frontend"
)

# Check if SELinux is enabled
if ! command -v getenforce &> /dev/null; then
    echo "⚠️  SELinux tools not found, skipping..."
    exit 0
fi

if [ "$(getenforce)" == "Disabled" ]; then
    echo "ℹ️  SELinux is disabled, skipping..."
    exit 0
fi

echo "SELinux is $(getenforce)"

# Set contexts
for dir in "${DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo "Setting context for $dir..."
        sudo chcon -R -t container_file_t "$dir" || {
            echo "⚠️  Failed to set context for $dir (might need sudo)"
        }
    else
        echo "⚠️  Directory $dir doesn't exist yet, skipping..."
    fi
done

# Verify
echo ""
echo "📋 Verifying contexts:"
for dir in "${DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo "  $dir:"
        ls -Zd "$dir" | awk '{print "    " $0}'
    fi
done

echo ""
echo "✅ SELinux contexts configured!"
