#!/usr/bin/env bash
# Update/deploy script for the GCP VM.
# Pulls latest code, installs deps, rebuilds the frontend, and gracefully
# reloads under PM2 with near-zero downtime. DB migrations run automatically on
# boot. Run from the repo root on the server:  ./deploy.sh
#
# .env and uploads are gitignored, so `git pull` never touches production
# secrets or uploaded files.
set -euo pipefail

APP_DIR="/opt/app"
DB_NAME="appdb"
BACKUP_DIR="/opt/app-backups"
APP_NAME="app"        # PM2 process name
PORT="5000"

cd "$APP_DIR"

echo "==> [1/5] Backing up the database (rollback safety)"
mkdir -p "$BACKUP_DIR"
ts="$(date +%Y%m%d-%H%M%S)"
# Dump as root via MySQL socket auth (no password needed); run deploy.sh as root.
sudo mysqldump "$DB_NAME" | gzip > "$BACKUP_DIR/$DB_NAME-$ts.sql.gz"
echo "    saved $BACKUP_DIR/$DB_NAME-$ts.sql.gz"

echo "==> [2/5] Pulling latest code"
git fetch --all --tags
git pull --ff-only

echo "==> [3/5] Backend dependencies"
( cd backend && npm ci --omit=dev )

echo "==> [4/5] Frontend build"
( cd frontend && npm ci && npm run build )

echo "==> [5/5] Graceful zero-downtime reload (PM2)"
pm2 reload "$APP_NAME" --update-env
pm2 save

echo "==> Done. Health check:"
sleep 2
curl -fsS "http://127.0.0.1:$PORT/api/health" && echo
echo "If anything looks wrong, roll back with:  git checkout <previous-tag> && ./deploy.sh"
