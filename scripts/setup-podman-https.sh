#!/bin/bash

set -e

echo "🚀 Complete Podman + HTTPS Setup for Fedora Silverblue"
echo "======================================================="
echo ""

# Check OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$VARIANT_ID" == "silverblue" ]]; then
        echo "✅ Running on Fedora Silverblue"
    else
        echo "⚠️  Not Silverblue, but continuing..."
    fi
fi
echo ""

# 1. Check prerequisites
echo "1️⃣  Checking prerequisites..."
echo ""

MISSING_DEPS=()

# Podman
if ! command -v podman &> /dev/null; then
    MISSING_DEPS+=("podman")
fi

# podman-compose
if ! command -v podman-compose &> /dev/null; then
    echo "⚠️  podman-compose not found"
    echo "   Install: pip3 install --user podman-compose"
    MISSING_DEPS+=("podman-compose")
fi

# mkcert
if ! command -v mkcert &> /dev/null; then
    echo "⚠️  mkcert not found"
    MISSING_DEPS+=("mkcert")
fi

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo ""
    echo "❌ Missing dependencies: ${MISSING_DEPS[*]}"
    echo ""
    echo "Install commands:"
    echo "  podman-compose: pip3 install --user podman-compose"
    echo "  mkcert:        brew install mkcert nss"
    echo ""
    exit 1
fi

echo "✅ All prerequisites installed"
echo ""

# 2. Setup .env
echo "2️⃣  Setting up environment..."
if [ ! -f .env ]; then
    cp .env.example .env
    echo "✅ Created .env file"
else
    echo "⚠️  .env already exists"
fi
echo ""

# 3. Create directories
echo "3️⃣  Creating directories..."
mkdir -p docker/traefik/certs
mkdir -p docker/traefik/dynamic
mkdir -p docker/prometheus/data
mkdir -p docker/grafana/data
mkdir -p docker/postgres
mkdir -p docker/redis
mkdir -p storage
mkdir -p migrations
echo "✅ Directories created"
echo ""

# 4. Setup Podman networks
echo "4️⃣  Setting up Podman networks..."
podman network exists brain_graph_network || podman network create brain_graph_network
podman network exists traefik_public || podman network create traefik_public
echo "✅ Networks ready"
echo ""

# 5. Enable Podman socket
echo "5️⃣  Enabling Podman socket..."
if [ ! -S "$XDG_RUNTIME_DIR/podman/podman.sock" ]; then
    systemctl --user enable --now podman.socket
    sleep 2
fi
echo "✅ Podman socket enabled"
echo ""

# 6. Setup SSL certificates
echo "6️⃣  Setting up SSL certificates with mkcert..."
./scripts/setup-local-https-podman.sh
echo ""

# 7. Setup SELinux contexts
echo "7️⃣  Setting up SELinux contexts..."
./scripts/setup-selinux-contexts.sh
echo ""

# 8. Update /etc/hosts
echo "8️⃣  Updating /etc/hosts..."
./scripts/update-hosts-podman.sh
echo ""

# 9. Verify setup
echo "9️⃣  Verifying setup..."
echo ""

echo "Checking certificate files..."
if [ -f docker/traefik/certs/cert.pem ] && [ -f docker/traefik/certs/key.pem ]; then
    echo "  ✅ Certificates exist"
    ls -lh docker/traefik/certs/
else
    echo "  ❌ Certificates missing!"
    exit 1
fi
echo ""

echo "Checking SELinux contexts..."
if command -v getenforce &> /dev/null && [ "$(getenforce)" != "Disabled" ]; then
    ls -Zd docker/traefik/certs/ | grep container_file_t && echo "  ✅ Correct SELinux context" || echo "  ⚠️  Wrong SELinux context"
else
    echo "  ℹ️  SELinux disabled or not available"
fi
echo ""

echo "Checking /etc/hosts..."
grep -q "pk.ms" /etc/hosts && echo "  ✅ Hosts file updated" || echo "  ❌ Hosts file not updated"
echo ""

# 10. Summary
echo "🎉 Setup complete!"
echo ""
echo "======================================================="
echo "Next steps:"
echo ""
echo "1. Start services:"
echo "   make start"
echo ""
echo "2. Wait for services to be healthy (may take 1-2 minutes)"
echo ""
echo "3. Access your services:"
echo "   🌐 Frontend:      https://pk.ms:8443"
echo "   📚 API Docs:      https://api.pk.ms:8443/docs"
echo "   🎛️  Traefik:      http://localhost:9080/dashboard/"
echo "   📊 Grafana:       https://grafana.pk.ms:8443"
echo "   📈 Prometheus:    https://prometheus.pk.ms:8443"
echo "   🌸 Flower:        https://flower.pk.ms:8443"
echo ""
echo "4. Your browser will trust the certificates automatically!"
echo ""
echo "Troubleshooting:"
echo "  - Check logs:    make logs"
echo "  - Check status:  podman ps"
echo "  - Check certs:   ls -lZ docker/traefik/certs/"
echo ""
echo "======================================================="
