# Brain Graph Deployment Checklist

## Pre-Deployment

- [ ] Update `.env` with production credentials
- [ ] Review `docker/postgres/postgresql.conf` for hardware
- [ ] Set up backup strategy
- [ ] Configure firewall rules
- [ ] Set up monitoring (Prometheus/Grafana)

## Initial Deployment

1. Clone repository
2. Copy `.env.example` to `.env` and configure
3. Run `make start`
4. Verify health: `curl http://localhost:8000/health`
5. Access docs: http://localhost:8000/docs

## Post-Deployment

- [ ] Run initial decay score computation
- [ ] Set up cron jobs for maintenance
- [ ] Configure SSL/TLS (if exposing)
- [ ] Set up log rotation
- [ ] Test backup restoration

## Maintenance

### Daily

```bash
# Run via cron
docker-compose exec backend python -m app.jobs.daily
```

### Weekly

```bash
docker-compose exec backend python -m app.jobs.weekly
```

### Monthly

```bash
# Backup
./scripts/backup.sh

# Archive old history
docker-compose exec postgres psql -U postgres -d brain_graph -c "SELECT archive_low_relevance_nodes();"
```
