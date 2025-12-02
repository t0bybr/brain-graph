#!/bin/bash

echo "🔐 Enabling HTTPS with Let's Encrypt..."

# Check domain
DOMAIN=${1:-$(grep DOMAIN .env | cut -d '=' -f2)}

if [ "$DOMAIN" = "localhost" ]; then
    echo "❌ Cannot enable HTTPS for localhost"
    echo "   Please set a real domain in .env"
    exit 1
fi

echo "Domain: $DOMAIN"
echo "⚠️  Make sure DNS is pointing to this server!"
read -p "Continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Cancelled"
    exit 0
fi

# Update .env
sed -i 's/ENABLE_HTTPS=false/ENABLE_HTTPS=true/' .env

# Restart traefik
docker-compose up -d traefik

echo "✅ HTTPS enabled!"
echo "   Certificates will be requested automatically"
echo "   Check Traefik dashboard for status: http://traefik.$DOMAIN:8080"
```

---

## Service URLs Overview

### Local Development (localhost)
```
Frontend:         http://localhost
API:              http://api.localhost
API Docs:         http://api.localhost/docs
Traefik Dashboard: http://localhost:8080
Grafana:          http://grafana.localhost
Prometheus:       http://prometheus.localhost
Flower:           http://flower.localhost

Encoders:
  Jina:           http://jina.localhost
  SigLIP:         http://siglip.localhost
  CodeBERT:       http://codebert.localhost
  Whisper:        http://whisper.localhost

Direct Access:
  PostgreSQL:     localhost:5432
  Redis:          localhost:6379
```

### Production (braingraph.example.com)
```
Frontend:         https://braingraph.example.com
API:              https://api.braingraph.example.com
Traefik:          https://traefik.braingraph.example.com:8080
Grafana:          https://grafana.braingraph.example.com
Prometheus:       https://prometheus.braingraph.example.com
Flower:           https://flower.braingraph.example.com
