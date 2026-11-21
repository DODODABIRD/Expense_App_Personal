# expense-backend ops helpers for the VPS.
# Sourced from ~/.bashrc (see Documentation.md -> 5.1); not meant to be executed.
# Edit here, push to VPS_Test, and `git pull` on the VPS; new shells pick it up.

EXP_APP_DIR="$HOME/Expense_App_Personal"
EXP_BACKEND_DIR="$EXP_APP_DIR/backend"
EXP_BRANCH="VPS_Test"
EXP_IMAGE="expense-backend"
EXP_CONTAINER="expense-backend-app"
EXP_NETWORK="expense-net"
EXP_BACKUP_DIR="$HOME/expense-backups"
EXP_HEALTH_URL="http://127.0.0.1:3000/api/public-config"
EXP_DB_CONTAINER=""   # set manually if postgres container auto-detection fails

_exp_healthy() { curl -fsS -m 3 "$EXP_HEALTH_URL" >/dev/null 2>&1; }

_exp_wait_healthy() {
  for _ in $(seq 1 20); do
    _exp_healthy && return 0
    sleep 2
  done
  return 1
}

_exp_run() {
  docker run -d --name "$EXP_CONTAINER" --network "$EXP_NETWORK" \
    --restart unless-stopped --env-file "$EXP_BACKEND_DIR/.env.local" \
    -p 3000:3000 "$EXP_IMAGE:latest"
}

_exp_db_container() {
  if [ -n "$EXP_DB_CONTAINER" ]; then
    echo "$EXP_DB_CONTAINER"
    return
  fi
  docker ps --format '{{.Names}} {{.Image}}' | awk 'tolower($2) ~ /postgres/ {print $1; exit}'
}

_exp_db_url() {
  grep -m1 '^DATABASE_URL=' "$EXP_BACKEND_DIR/.env.local" | cut -d= -f2- | tr -d '"'
}

update-backend() {
  cd "$EXP_APP_DIR" || return 1
  git pull origin "$EXP_BRANCH" || { echo "FAILED: git pull"; return 1; }
  cd "$EXP_BACKEND_DIR" || return 1
  docker tag "$EXP_IMAGE:latest" "$EXP_IMAGE:previous" 2>/dev/null || true
  docker build -t "$EXP_IMAGE:latest" . || { echo "FAILED: docker build"; return 1; }
  docker rm -f "$EXP_CONTAINER" >/dev/null 2>&1 || true
  _exp_run || { echo "FAILED: docker run"; return 1; }
  if _exp_wait_healthy; then
    docker image prune -f >/dev/null 2>&1
    echo "OK: backend up (commit $(git -C "$EXP_APP_DIR" rev-parse --short HEAD))"
  else
    echo "FAILED: health check timeout"
    docker logs --tail 50 "$EXP_CONTAINER"
    return 1
  fi
}

recreate-backend() {
  docker rm -f "$EXP_CONTAINER" >/dev/null 2>&1 || true
  _exp_run || { echo "FAILED: docker run"; return 1; }
  if _exp_wait_healthy; then
    echo "OK: container recreated with the current .env.local"
  else
    echo "FAILED: health check timeout"
    docker logs --tail 50 "$EXP_CONTAINER"
    return 1
  fi
}

restart-backend() {
  docker restart "$EXP_CONTAINER" || return 1
  _exp_wait_healthy && echo "OK: backend restarted" || echo "FAILED: health check timeout"
}

stop-backend() { docker stop "$EXP_CONTAINER"; }

start-backend() {
  docker start "$EXP_CONTAINER" || return 1
  _exp_wait_healthy && echo "OK: backend started" || echo "FAILED: health check timeout"
}

logs-backend() { docker logs -f --tail 200 "$EXP_CONTAINER"; }

logs-backend-errors() {
  docker logs --tail 500 "$EXP_CONTAINER" 2>&1 | grep -iE "error|fail|unhandled|exception|exit"
}

status-backend() {
  docker ps -a --filter "name=^${EXP_CONTAINER}$" \
    --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
  _exp_healthy && echo "health: OK" || echo "health: FAILED"
  docker inspect -f 'created: {{.Created}}' "$EXP_CONTAINER" 2>/dev/null
  echo "commit: $(git -C "$EXP_APP_DIR" rev-parse --short HEAD 2>/dev/null)"
  df -h / | tail -1
}

rollback-backend() {
  docker image inspect "$EXP_IMAGE:previous" >/dev/null 2>&1 \
    || { echo "FAILED: no :previous image"; return 1; }
  docker tag "$EXP_IMAGE:previous" "$EXP_IMAGE:latest"
  docker rm -f "$EXP_CONTAINER" >/dev/null 2>&1 || true
  _exp_run || { echo "FAILED: docker run"; return 1; }
  if _exp_wait_healthy; then
    echo "OK: rolled back to the previous image"
  else
    echo "FAILED: health check timeout"
    docker logs --tail 50 "$EXP_CONTAINER"
    return 1
  fi
}

shell-backend() { docker exec -it "$EXP_CONTAINER" sh; }

env-backend() { "${EDITOR:-nano}" "$EXP_BACKEND_DIR/.env.local"; }

git-info-backend() {
  git -C "$EXP_APP_DIR" branch --show-current
  git -C "$EXP_APP_DIR" log --oneline -3
  git -C "$EXP_APP_DIR" status --short
}

backup-db() {
  local db url file tmp
  db=$(_exp_db_container)
  [ -n "$db" ] || { echo "FAILED: postgres container not found"; return 1; }
  url=$(_exp_db_url)
  [ -n "$url" ] || { echo "FAILED: DATABASE_URL missing from .env.local"; return 1; }
  mkdir -p "$EXP_BACKUP_DIR"
  file="$EXP_BACKUP_DIR/unmurce-$(date +%F-%H%M).sql.gz"
  tmp="$file.tmp"
  if ! docker exec "$db" pg_dump --no-owner --no-privileges "$url" > "$tmp" || [ ! -s "$tmp" ]; then
    rm -f "$tmp"
    echo "FAILED: pg_dump"
    return 1
  fi
  gzip -c "$tmp" > "$file" && rm -f "$tmp"
  find "$EXP_BACKUP_DIR" -name '*.sql.gz' -mtime +14 -delete
  echo "OK: $file ($(du -h "$file" | cut -f1))"
}

db-shell() {
  local db url
  db=$(_exp_db_container)
  [ -n "$db" ] || { echo "FAILED: postgres container not found"; return 1; }
  url=$(_exp_db_url)
  docker exec -it "$db" psql "$url"
}

disk-check() {
  df -h /
  echo
  docker system df
}

docker-cleanup() {
  docker image prune -f
  docker builder prune -f --filter until=168h
}

first-setup-backend() {
  docker network inspect "$EXP_NETWORK" >/dev/null 2>&1 \
    || docker network create "$EXP_NETWORK" || return 1
  cd "$EXP_BACKEND_DIR" || return 1
  docker build -t "$EXP_IMAGE:latest" . || { echo "FAILED: docker build"; return 1; }
  recreate-backend
}
