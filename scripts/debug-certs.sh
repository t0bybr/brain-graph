#!/bin/bash

echo "🔍 Certificate Debugging"
echo "========================"
echo ""

# Check mkcert CA
echo "1. mkcert CA Location:"
if command -v mkcert &> /dev/null; then
    CA_ROOT=$(mkcert -CAROOT)
    echo "   $CA_ROOT"
    ls -lh "$CA_ROOT"
else
    echo "   ❌ mkcert not found"
fi
echo ""

# Check generated certs
echo "2. Generated Certificates:"
CERT_DIR="docker/traefik/certs"
if [ -d "$CERT_DIR" ]; then
    ls -lhZ "$CERT_DIR"

    if [ -f "$CERT_DIR/cert.pem" ]; then
        echo ""
        echo "   Certificate details:"
        openssl x509 -in "$CERT_DIR/cert.pem" -text -noout | grep -A2 "Subject:"
        openssl x509 -in "$CERT_DIR/cert.pem" -text -noout | grep -A10 "Subject Alternative Name:"
    fi
else
    echo "   ❌ Certificate directory not found"
fi
echo ""

# Check SELinux
echo "3. SELinux Status:"
if command -v getenforce &> /dev/null; then
    echo "   Mode: $(getenforce)"
    if [ "$(getenforce)" != "Disabled" ]; then
        echo "   Context of cert dir:"
        ls -Zd "$CERT_DIR"
    fi
else
    echo "   ℹ️  SELinux tools not available"
fi
echo ""

# Check /etc/hosts
echo "4. /etc/hosts entries:"
grep "pk.ms" /etc/hosts 2>/dev/null || echo "   ❌ No pk.ms entries found"
echo ""

# Check Podman container
echo "5. Traefik Container (if running):"
if podman ps --format "{{.Names}}" | grep -q brain_graph_traefik; then
    echo "   ✅ Container running"

    # Check if certs are mounted
    echo ""
    echo "   Mounted volumes:"
    podman inspect brain_graph_traefik | jq -r '.[0].Mounts[] | select(.Destination | contains("certs")) | "   \(.Source) → \(.Destination)"'

    # Check if files exist in container
    echo ""
    echo "   Files in container:"
    podman exec brain_graph_traefik ls -lh /certs/
else
    echo "   ⚠️  Container not running"
fi
echo ""

# Test HTTPS
echo "6. Test HTTPS Connection:"
if command -v curl &> /dev/null; then
    echo "   Testing https://pk.ms:8443 ..."
    curl -sI https://pk.ms:8443 2>&1 | head -5
else
    echo "   ℹ️  curl not available"
fi
echo ""

echo "========================"
