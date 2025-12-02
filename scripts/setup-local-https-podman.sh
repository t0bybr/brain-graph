#!/bin/bash

set -e

echo "🔐 Setting up local HTTPS for Podman (pk.ms)..."

# Check if mkcert is installed
if ! command -v mkcert &> /dev/null; then
    echo "❌ mkcert not found!"
    echo ""
    echo "Install with:"
    echo "  brew install mkcert nss"
    echo ""
    echo "Or manually:"
    echo "  mkdir -p ~/.local/bin"
    echo "  cd ~/.local/bin"
    echo "  curl -JLO 'https://dl.filippo.io/mkcert/latest?for=linux/amd64'"
    echo "  chmod +x mkcert-v*-linux-amd64"
    echo "  mv mkcert-v*-linux-amd64 mkcert"
    exit 1
fi

# Create certificate directory
CERT_DIR="docker/traefik/certs"
mkdir -p "$CERT_DIR"
cd "$CERT_DIR"

# Install local CA (asks for sudo password)
echo "Installing local CA..."
mkcert -install

# Get CA location
CA_LOCATION=$(mkcert -CAROOT)
echo "✅ CA installed at: $CA_LOCATION"

# Generate certificates
echo "Generating certificates for pk.ms and subdomains..."
mkcert \
    "pk.ms" \
    "*.pk.ms" \
    "localhost" \
    "127.0.0.1" \
    "::1"

# Rename for Traefik
mv pk.ms+4.pem cert.pem
mv pk.ms+4-key.pem key.pem

# Set correct permissions (important for Podman rootless!)
chmod 644 cert.pem
chmod 600 key.pem

cd ../../..

# SELinux labels (critical for Podman on Fedora!)
if command -v getenforce &> /dev/null && [ "$(getenforce)" != "Disabled" ]; then
    echo "Setting SELinux context for certificates..."
    sudo chcon -R -t container_file_t "$CERT_DIR"

    # Verify
    ls -Z "$CERT_DIR"
fi

# Update .env
if [ -f .env ]; then
    sed -i.bak 's/DOMAIN=localhost/DOMAIN=pk.ms/' .env
    sed -i.bak 's/ENABLE_HTTPS=false/ENABLE_HTTPS=true/' .env
    sed -i.bak 's/LOCAL_HTTPS=false/LOCAL_HTTPS=true/' .env
    rm .env.bak
fi

echo ""
echo "✅ Certificates created successfully!"
echo ""
echo "📁 Certificate files:"
echo "  Cert: $CERT_DIR/cert.pem"
echo "  Key:  $CERT_DIR/key.pem"
echo ""
echo "🔑 CA Root Certificate:"
echo "  Location: $CA_LOCATION"
echo "  rootCA.pem: $CA_LOCATION/rootCA.pem"
echo "  rootCA-key.pem: $CA_LOCATION/rootCA-key.pem"
echo ""
echo "📝 Next steps:"
echo "1. Add to /etc/hosts:"
echo "   sudo nano /etc/hosts"
echo ""
echo "   Add these lines:"
echo "   127.0.0.1 pk.ms api.pk.ms traefik.pk.ms grafana.pk.ms prometheus.pk.ms flower.pk.ms"
echo "   127.0.0.1 jina.pk.ms siglip.pk.ms codebert.pk.ms whisper.pk.ms"
echo ""
echo "2. Start services:"
echo "   make start"
echo ""
echo "3. Access at:"
echo "   https://pk.ms:8443"
echo ""
