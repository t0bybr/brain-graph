.PHONY: help start stop restart logs test test-db test-api test-integration clean setup-https debug-certs verify-certs

help:
	@echo "Brain Graph - Podman Commands:"
	@echo "  make start          - Start with Podman"
	@echo "  make stop           - Stop all services"
	@echo "  make restart        - Restart all services"
	@echo "  make logs           - Show backend logs"
	@echo "  make test           - Run all tests"
	@echo "  make test-db        - Run database tests only"
	@echo "  make test-api       - Run API tests only"
	@echo "  make test-integration - Run integration tests"
	@echo "  make clean          - Clean up containers and volumes"
	@echo "  make setup-https    - Setup HTTPS with Let's Encrypt"
	@echo "  make debug-certs    - Debug SSL certificates"
	@echo "  make verify-certs   - Verify SSL certificates"

start:
	@./scripts/start-podman.sh

stop:
	@./scripts/stop-podman.sh

restart: stop start

logs:
	@podman-compose -f podman-compose.yml logs -f backend

logs-all:
	@podman-compose -f podman-compose.yml logs -f

test:
	@./scripts/test.sh

test-db:
	@pytest tests/test_database.py -v

test-api:
	@pytest tests/test_api.py -v

test-integration:
	@pytest tests/test_integration.py -v -m integration

clean:
	@podman-compose -f podman-compose.yml down -v
	@podman volume prune -f
	@podman network prune -f

shell:
	@podman exec -it brain_graph_backend /bin/bash

db:
	@podman exec -it brain_graph_db psql -U postgres -d brain_graph

setup-https:
	@./scripts/setup-podman-https.sh

debug-certs:
	@./scripts/debug-certs.sh

verify-certs:
	@echo "🔍 Verifying certificate setup..."
	@openssl x509 -in docker/traefik/certs/cert.pem -text -noout | grep -A2 "Subject:"
	@openssl x509 -in docker/traefik/certs/cert.pem -text -noout | grep -A10 "DNS:"
