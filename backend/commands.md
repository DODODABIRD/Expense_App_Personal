# Backend Commands — VPS

Referensi operasi backend Unmurce di VPS: Docker, branch `VPS_Test`, container `expense-backend-app`, network `expense-net`.

Isi file ini ada dua bentuk: fungsi shell yang bisa kamu ketik langsung di VPS, dan blok copy-paste mentah untuk sesi yang tidak memuat `.bashrc`.

---

## 1. Pasang sekali di VPS

Jalankan di VPS (bukan di Windows), lalu buka sesi SSH baru atau `source ~/.bashrc`.

```bash
cat >> ~/.bashrc <<'EOF'

# >>> expense-backend ops >>>
EXP_APP_DIR="$HOME/Expense_App_Personal"
EXP_BACKEND_DIR="$EXP_APP_DIR/backend"
EXP_BRANCH="VPS_Test"
EXP_IMAGE="expense-backend"
EXP_CONTAINER="expense-backend-app"
EXP_NETWORK="expense-net"
EXP_BACKUP_DIR="$HOME/expense-backups"
EXP_HEALTH_URL="http://127.0.0.1:3000/api/public-config"
EXP_DB_CONTAINER=""   # isi manual kalau deteksi otomatis container postgres gagal

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
  git pull origin "$EXP_BRANCH" || { echo "GAGAL: git pull"; return 1; }
  cd "$EXP_BACKEND_DIR" || return 1
  docker tag "$EXP_IMAGE:latest" "$EXP_IMAGE:previous" 2>/dev/null || true
  docker build -t "$EXP_IMAGE:latest" . || { echo "GAGAL: docker build"; return 1; }
  docker rm -f "$EXP_CONTAINER" >/dev/null 2>&1 || true
  _exp_run || { echo "GAGAL: docker run"; return 1; }
  if _exp_wait_healthy; then
    docker image prune -f >/dev/null 2>&1
    echo "OK: backend up (commit $(git -C "$EXP_APP_DIR" rev-parse --short HEAD))"
  else
    echo "GAGAL: health check timeout"
    docker logs --tail 50 "$EXP_CONTAINER"
    return 1
  fi
}

recreate-backend() {
  docker rm -f "$EXP_CONTAINER" >/dev/null 2>&1 || true
  _exp_run || { echo "GAGAL: docker run"; return 1; }
  if _exp_wait_healthy; then
    echo "OK: container dibuat ulang dengan .env.local terbaru"
  else
    echo "GAGAL: health check timeout"
    docker logs --tail 50 "$EXP_CONTAINER"
    return 1
  fi
}

restart-backend() {
  docker restart "$EXP_CONTAINER" || return 1
  _exp_wait_healthy && echo "OK: backend restart" || echo "GAGAL: health check timeout"
}

stop-backend() { docker stop "$EXP_CONTAINER"; }

start-backend() {
  docker start "$EXP_CONTAINER" || return 1
  _exp_wait_healthy && echo "OK: backend start" || echo "GAGAL: health check timeout"
}

logs-backend() { docker logs -f --tail 200 "$EXP_CONTAINER"; }

logs-backend-errors() {
  docker logs --tail 500 "$EXP_CONTAINER" 2>&1 | grep -iE "error|fail|unhandled|exception|exit"
}

status-backend() {
  docker ps -a --filter "name=^${EXP_CONTAINER}$" \
    --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
  _exp_healthy && echo "health: OK" || echo "health: GAGAL"
  docker inspect -f 'created: {{.Created}}' "$EXP_CONTAINER" 2>/dev/null
  echo "commit: $(git -C "$EXP_APP_DIR" rev-parse --short HEAD 2>/dev/null)"
  df -h / | tail -1
}

rollback-backend() {
  docker image inspect "$EXP_IMAGE:previous" >/dev/null 2>&1 \
    || { echo "GAGAL: image :previous tidak ada"; return 1; }
  docker tag "$EXP_IMAGE:previous" "$EXP_IMAGE:latest"
  docker rm -f "$EXP_CONTAINER" >/dev/null 2>&1 || true
  _exp_run || { echo "GAGAL: docker run"; return 1; }
  if _exp_wait_healthy; then
    echo "OK: rollback ke image sebelumnya"
  else
    echo "GAGAL: health check timeout"
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
  [ -n "$db" ] || { echo "GAGAL: container postgres tidak ditemukan"; return 1; }
  url=$(_exp_db_url)
  [ -n "$url" ] || { echo "GAGAL: DATABASE_URL tidak ada di .env.local"; return 1; }
  mkdir -p "$EXP_BACKUP_DIR"
  file="$EXP_BACKUP_DIR/unmurce-$(date +%F-%H%M).sql.gz"
  tmp="$file.tmp"
  if ! docker exec "$db" pg_dump --no-owner --no-privileges "$url" > "$tmp" || [ ! -s "$tmp" ]; then
    rm -f "$tmp"
    echo "GAGAL: pg_dump"
    return 1
  fi
  gzip -c "$tmp" > "$file" && rm -f "$tmp"
  find "$EXP_BACKUP_DIR" -name '*.sql.gz' -mtime +14 -delete
  echo "OK: $file ($(du -h "$file" | cut -f1))"
}

db-shell() {
  local db url
  db=$(_exp_db_container)
  [ -n "$db" ] || { echo "GAGAL: container postgres tidak ditemukan"; return 1; }
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
  docker build -t "$EXP_IMAGE:latest" . || { echo "GAGAL: docker build"; return 1; }
  recreate-backend
}
# <<< expense-backend ops <<<
EOF
source ~/.bashrc
```

---

## 2. Daftar command

| Command | Fungsi |
|---|---|
| `update-backend` | Pull `VPS_Test`, simpan image lama sebagai `:previous`, build, recreate container, health check, prune |
| `recreate-backend` | Buat ulang container tanpa build/pull. Wajib setelah mengubah `.env.local` |
| `restart-backend` | Restart cepat. Env tidak dibaca ulang |
| `stop-backend` / `start-backend` | Stop / start container |
| `logs-backend` | Follow log, 200 baris terakhir |
| `logs-backend-errors` | 500 baris terakhir, difilter baris error |
| `status-backend` | Status container, health, waktu dibuat, commit yang jalan, disk |
| `rollback-backend` | Jalankan image `:previous` |
| `shell-backend` | Masuk shell Alpine di dalam container |
| `env-backend` | Buka `.env.local` di editor |
| `git-info-backend` | Branch, 3 commit terakhir, file yang berubah |
| `backup-db` | `pg_dump` ke `~/expense-backups/unmurce-<tanggal>.sql.gz`, simpan 14 hari |
| `db-shell` | `psql` interaktif ke database |
| `disk-check` | Pemakaian disk host dan Docker |
| `docker-cleanup` | Hapus dangling image + build cache lebih dari 7 hari |
| `first-setup-backend` | Sekali saja: buat network, build, jalankan container |

---

## 3. Copy-paste mentah

Untuk sesi SSH yang tidak memuat `.bashrc`.

### Update backend

```bash
cd ~/Expense_App_Personal && git pull origin VPS_Test && cd backend \
  && docker tag expense-backend:latest expense-backend:previous 2>/dev/null; \
  docker build -t expense-backend:latest . \
  && docker rm -f expense-backend-app 2>/dev/null; \
  docker run -d --name expense-backend-app --network expense-net \
     --restart unless-stopped --env-file .env.local -p 3000:3000 expense-backend:latest \
  && sleep 5 && docker logs --tail 30 expense-backend-app
```

### Recreate container (setelah ubah `.env.local`)

```bash
cd ~/Expense_App_Personal/backend \
  && docker rm -f expense-backend-app 2>/dev/null; \
  docker run -d --name expense-backend-app --network expense-net \
     --restart unless-stopped --env-file .env.local -p 3000:3000 expense-backend:latest \
  && sleep 5 && curl -fsS http://127.0.0.1:3000/api/public-config && echo
```

### Cek status dan health

```bash
docker ps --filter name=expense-backend-app
curl -fsS http://127.0.0.1:3000/api/public-config && echo
docker inspect -f '{{.Created}}' expense-backend-app
git -C ~/Expense_App_Personal log --oneline -1
```

### Log

```bash
docker logs -f --tail 200 expense-backend-app
docker logs --tail 500 expense-backend-app 2>&1 | grep -iE "error|fail|unhandled|exception"
```

### Rollback ke image sebelumnya

```bash
docker tag expense-backend:previous expense-backend:latest \
  && docker rm -f expense-backend-app 2>/dev/null; \
  docker run -d --name expense-backend-app --network expense-net \
     --restart unless-stopped --env-file ~/Expense_App_Personal/backend/.env.local \
     -p 3000:3000 expense-backend:latest \
  && sleep 5 && docker logs --tail 30 expense-backend-app
```

### Backup database

```bash
DB=$(docker ps --format '{{.Names}} {{.Image}}' | awk 'tolower($2) ~ /postgres/ {print $1; exit}')
URL=$(grep -m1 '^DATABASE_URL=' ~/Expense_App_Personal/backend/.env.local | cut -d= -f2- | tr -d '"')
mkdir -p ~/expense-backups
FILE=~/expense-backups/unmurce-$(date +%F-%H%M).sql
docker exec "$DB" pg_dump --no-owner --no-privileges "$URL" > "$FILE" && gzip "$FILE" && ls -lh "$FILE.gz"
```

### Bersihkan disk

```bash
df -h /
docker system df
docker image prune -f
docker builder prune -f --filter until=168h
```

### Setup pertama kali

```bash
docker network create expense-net 2>/dev/null
cd ~/Expense_App_Personal/backend \
  && docker build -t expense-backend:latest . \
  && docker run -d --name expense-backend-app --network expense-net \
     --restart unless-stopped --env-file .env.local -p 3000:3000 expense-backend:latest \
  && sleep 5 && docker logs --tail 30 expense-backend-app
```

---

## 4. Catatan

- `docker restart` tidak membaca ulang `--env-file`. Setelah mengubah `.env.local`, pakai `recreate-backend`.
- `update-backend` menyimpan image lama sebagai `expense-backend:previous` supaya bisa `rollback-backend`. Rollback hanya bisa satu langkah; setelah rollback, tag `:previous` menunjuk image yang sama.
- Upload dan backup asset dari panel `/dodo` ditulis ke `public/asset` dan `data/admin-backups` **di dalam container**, tanpa volume. Semua perubahan itu hilang setiap recreate/update. Kalau mau persisten, tambahkan ke `docker run`:
  `-v ~/Expense_App_Personal/backend/public/asset:/app/public/asset -v ~/expense-backups/assets:/app/data/admin-backups`
- Jangan pakai `docker system prune -a`: perintah itu menghapus image `:previous` dan mematikan rollback. Cukup `docker-cleanup`.
- `docker image prune -f` tidak menghapus build cache. Itu tugas `docker builder prune` di `docker-cleanup`, jadi jalankan `disk-check` secara berkala.
- Test tidak bisa dijalankan di image produksi karena `.dockerignore` mengecualikan `test/`. Jalankan `npm test` di lokal sebelum push ke `VPS_Test`.
- `backup-db` dan `db-shell` mencari container postgres lewat nama image. Kalau image container DB-mu tidak mengandung kata `postgres`, isi `EXP_DB_CONTAINER="nama-container"` di `~/.bashrc`.
- Kalau `git pull` gagal karena ada perubahan lokal di VPS, cek dulu dengan `git-info-backend`. Jangan langsung `reset --hard`.
