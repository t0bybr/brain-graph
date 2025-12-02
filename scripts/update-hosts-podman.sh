#!/bin/bash

echo "📝 Updating /etc/hosts for pk.ms..."

HOSTS_FILE="/etc/hosts"
BACKUP_FILE="/etc/hosts.backup.$(date +%Y%m%d_%H%M%S)"

# Backup existing hosts file
sudo cp "$HOSTS_FILE" "$BACKUP_FILE"
echo "✅ Backed up to: $BACKUP_FILE"

# Check if entries already exist
if grep -q "pk.ms" "$HOSTS_FILE"; then
    echo "⚠️  pk.ms entries already exist in $HOSTS_FILE"
    echo ""
    echo "Current entries:"
    grep "pk.ms" "$HOSTS_FILE"
    echo ""
    read -p "Replace existing entries? (y/n): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Remove old entries
        sudo sed -i '/pk.ms/d' "$HOSTS_FILE"
        echo "✅ Removed old entries"
    else
        echo "Cancelled"
        exit 0
    fi
fi

# Add new entries
echo "Adding new entries..."
sudo tee -a "$HOSTS_FILE" > /dev/null <<EOF

# Brain Graph - Local Development (Podman)
127.0.0.1 pk.ms
127.0.0.1 api.pk.ms
127.0.0.1 traefik.pk.ms
127.0.0.1 grafana.pk.ms
127.0.0.1 prometheus.pk.ms
127.0.0.1 flower.pk.ms
127.0.0.1 jina.pk.ms
127.0.0.1 siglip.pk.ms
127.0.0.1 codebert.pk.ms
127.0.0.1 whisper.pk.ms
EOF

echo "✅ Added entries!"
echo ""
echo "Current pk.ms entries:"
grep "pk.ms" "$HOSTS_FILE"
echo ""
echo "✅ Done! You can now access:"
echo "   https://pk.ms:8443"
echo "   https://api.pk.ms:8443"
echo ""
