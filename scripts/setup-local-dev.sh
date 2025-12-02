#!/bin/bash

echo "🚀 Brain Graph - Local Development Setup"
echo "=========================================="
echo ""

# Step 1: Check prerequisites
echo "1️⃣  Checking prerequisites..."

# Docker
if ! command -v docker &> /dev/null; then
    echo "❌ Docker not found! Please install Docker first."
    exit 1
fi

# Docker Compose
if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose not found! Please install Docker Compose first."
    exit 1
fi

# mkcert
if ! command -v mkcert &> /dev/null; then
    echo "❌ mkcert not found!"
    echo ""
    echo "Install with:"
    echo "  macOS:   brew install mkcert nss"
    echo "  Linux:   wget https://github.com/FiloSottile/mkcert/releases/download/v1.4.4/mkcert-v1.4.4-linux-amd64"
    echo "           sudo mv mkcert-v1.4.4-linux-amd64 /usr/local/bin/mkcert"
    echo "           sudo chmod +x /usr/local/bin/mkcert"
    echo "  Windows: choco install mkcert"
    exit 1
fi

echo "✅ All prerequisites found!"
echo ""

# Step 2: Setup .env
echo "2️⃣  Setting up environment..."
if [ ! -f .env ]; then
    cp .env.example .env
    echo "✅ Created .env file"
else
    echo "⚠️  .env already exists, skipping"
fi

# Step 3: Setup SSL certificates
echo ""
echo "3️⃣  Setting up SSL certificates..."
./scripts/setup-local-https.sh

# Step 4: Update hosts file
echo ""
echo "4️⃣  Updating /etc/hosts..."
./scripts/update-hosts.sh

# Step 5: Create directories
echo ""
echo "5️⃣  Creating data directories..."
mkdir -p docker/prometheus/data
mkdir -p docker/grafana/data
mkdir -p storage
chmod -R 755 docker/prometheus/data
chmod -R 755 docker/grafana/data
echo "✅ Directories created"

# Step 6: Start services
echo ""
echo "6️⃣  Starting services..."
./scripts/start.sh

echo ""
echo "=========================================="
echo "✅ Setup complete!"
echo ""
echo "🌐 Access your services at:"
echo "   https://pk.ms              - Frontend"
echo "   https://api.pk.ms/docs     - API Documentation"
echo "   https://traefik.pk.ms:8080 - Traefik Dashboard"
echo "   https://grafana.pk.ms      - Grafana"
echo "   https://prometheus.pk.ms   - Prometheus"
echo "   https://flower.pk.ms       - Celery Flower"
echo ""
echo "🤖 Encoders:"
echo "   https://jina.pk.ms         - Text Encoder"
echo ""
echo "🔐 Your browser will trust these certificates!"
echo ""
