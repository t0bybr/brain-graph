#!/bin/bash

echo "📝 Updating /etc/hosts for pk.ms..."

HOSTS_ENTRY="127.0.0.1 pk.ms api.pk.ms traefik.pk.ms grafana.pk.ms prometheus.pk.ms flower.pk.ms jina.pk.ms siglip.pk.ms codebert.pk.ms whisper.pk.ms"

# Check if entry already exists
if grep -q "pk.ms" /etc/hosts; then
    echo "⚠️  pk.ms entries already exist in /etc/hosts"
    echo "   Please verify manually:"
    grep "pk.ms" /etc/hosts
else
    echo "Adding entries to /etc/hosts (needs sudo)..."
    echo "$HOSTS_ENTRY" | sudo tee -a /etc/hosts > /dev/null
    echo "✅ Added!"
fi

echo ""
echo "Current pk.ms entries:"
grep "pk.ms" /etc/hosts
