#!/bin/bash

echo "⚠️  WARNING: This will delete ALL data!"
read -p "Are you sure? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Cancelled"
    exit 0
fi

echo "Stopping services..."
docker-compose down -v

echo "Removing volumes..."
docker volume rm postgres_postgres_data || true

echo "✅ Reset complete. Run ./scripts/start.sh to initialize fresh."
