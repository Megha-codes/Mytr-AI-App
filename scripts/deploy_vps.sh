#!/bin/bash
set -e

# Deploy backend to VPS via SSH.
# Usage: VPS_HOST=root@1.2.3.4 ./scripts/deploy_vps.sh
#
# Prerequisites on the VPS:
#   apt install docker.io docker-compose-plugin git -y
#   Clone the repo to /opt/mytr

VPS_HOST="${VPS_HOST:?Set VPS_HOST=user@host}"
REMOTE_DIR="/opt/mytr"

echo "==> Syncing code to $VPS_HOST:$REMOTE_DIR"
rsync -az --exclude='.git' --exclude='venv' --exclude='frontend' \
  "$(dirname "$0")/../" "$VPS_HOST:$REMOTE_DIR/"

echo "==> Running migrations"
ssh "$VPS_HOST" bash -s <<'ENDSSH'
  cd /opt/mytr
  # Run all migration files in order
  for f in backend/migrations/*.sql; do
    echo "  Applying $f"
    docker compose -f docker-compose.prod.yml exec -T db \
      psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f "/dev/stdin" < "$f" || true
  done
ENDSSH

echo "==> Rebuilding and restarting backend"
ssh "$VPS_HOST" bash -s <<'ENDSSH'
  cd /opt/mytr
  docker compose -f docker-compose.prod.yml build backend
  docker compose -f docker-compose.prod.yml up -d
  docker compose -f docker-compose.prod.yml ps
ENDSSH

echo ""
echo "==> Deployed. Check logs with:"
echo "  ssh $VPS_HOST 'docker compose -f /opt/mytr/docker-compose.prod.yml logs -f backend'"
