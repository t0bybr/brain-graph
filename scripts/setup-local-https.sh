#!/bin/bash

echo "🔐 Setting up local HTTPS for pk.ms..."

# Check if mkcert is installed
if ! command -v mkcert &> /dev/null; then
    echo "❌ mkcert not found!"
    echo ""
    echo "Install with:"
    echo "  macOS:   brew install mkcert nss"
    echo "  Linux:   See https://github.com/FiloSottile/mkcert#installation"
    echo "  Windows: choco install mkcert"
    exit 1
fi

# Create directories
mkdir -p docker/traefik/certs
cd docker/traefik/certs

# Install local CA
echo "Installing local CA (may ask for password)..."
mkcert -install

# Generate certificates for pk.ms and subdomains
echo "Generating certificates..."
mkcert \
    "pk.ms" \
    "*.pk.ms" \
    "localhost" \
    "127.0.0.1" \
    "::1"

# Rename files for Traefik
mv pk.ms+4.pem cert.pem
mv pk.ms+4-key.pem key.pem

cd ../../..

# Update .env
sed -i.bak 's/DOMAIN=localhost/DOMAIN=pk.ms/' .env
sed -i.bak 's/ENABLE_HTTPS=false/ENABLE_HTTPS=true/' .env
sed -i.bak 's/LOCAL_HTTPS=false/LOCAL_HTTPS=true/' .env

echo ""
echo "✅ Certificates created!"
echo ""
echo "Add to /etc/hosts (or C:\Windows\System32\drivers\etc\hosts):"
echo "127.0.0.1 pk.ms api.pk.ms traefik.pk.ms grafana.pk.ms prometheus.pk.ms flower.pk.ms jina.pk.ms siglip.pk.ms codebert.pk.ms whisper.pk.ms"
echo ""
echo "Then restart with: ./scripts/start.sh"
