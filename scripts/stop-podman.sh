#!/bin/bash

echo "Stopping Brain Graph (Podman)..."
podman-compose -f podman-compose.yml down

echo "✅ Stopped"
