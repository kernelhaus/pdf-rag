#!/usr/bin/env bash
# Installs and starts the whole PDF search stack inside a fresh Ubuntu (WSL2 or real).
# Idempotent: safe to re-run. Needs root and internet (only for this install step).
#
#   sudo ./install-stack.sh [--conf /etc/pdfsearch/pdfsearch.conf] [--no-service]
set -euo pipefail

CONF=/etc/pdfsearch/pdfsearch.conf
SERVICE=1
while [ $# -gt 0 ]; do
  case "$1" in
    --conf) CONF="$2"; shift 2 ;;
    --no-service) SERVICE=0; shift ;;
    *) echo "unknown arg $1" >&2; exit 2 ;;
  esac
done
[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
[ -f "$CONF" ] || { echo "missing config $CONF" >&2; exit 1; }
# shellcheck disable=SC1090
. "$CONF"

HERE="$(cd "$(dirname "$0")" && pwd)"
RAGFLOW_DIR=/opt/ragflow
APP_DIR=/opt/pdfsearch
log() { echo "[pdfsearch] $*"; }

export DEBIAN_FRONTEND=noninteractive
if ! docker compose version >/dev/null 2>&1; then
  log "Installing Docker, git and Python helpers (needs internet)..."
  apt-get update -y
  apt-get install -y --no-install-recommends docker.io docker-compose-v2 git curl ca-certificates \
    python3 python3-requests python3-tqdm
else
  command -v git >/dev/null || apt-get install -y git
  python3 -c 'import requests, tqdm' 2>/dev/null || { apt-get update -y; apt-get install -y python3-requests python3-tqdm; }
fi

if [ -d /run/systemd/system ]; then
  systemctl enable --now docker
else
  log "systemd not running; assuming Docker is already available."
fi
docker info >/dev/null

# Elasticsearch needs this; persist it across restarts.
sysctl -w vm.max_map_count=262144 >/dev/null || true
echo 'vm.max_map_count=262144' > /etc/sysctl.d/99-pdfsearch.conf

# RAGFlow source (compose files) pinned to a tag.
if [ ! -d "$RAGFLOW_DIR/.git" ]; then
  git clone --depth 1 --branch "$RAGFLOW_TAG" https://github.com/infiniflow/ragflow.git "$RAGFLOW_DIR"
else
  git -C "$RAGFLOW_DIR" fetch --depth 1 origin "refs/tags/$RAGFLOW_TAG:refs/tags/$RAGFLOW_TAG" || true
  git -C "$RAGFLOW_DIR" checkout -q "$RAGFLOW_TAG"
fi

# Our settings live in a marked block appended to RAGFlow's .env (later lines win).
ENVF="$RAGFLOW_DIR/docker/.env"
sed -i '/^# >>> pdfsearch/,/^# <<< pdfsearch/d' "$ENVF"
cat >> "$ENVF" <<EOF
# >>> pdfsearch (managed; edit /etc/pdfsearch/pdfsearch.conf instead)
COMPOSE_PROFILES=elasticsearch,cpu,metadata-mysql,tei-cpu
TEI_MODEL=$TEI_MODEL
MEM_LIMIT=$(( ${MEM_LIMIT_GB:-8} * 1024 * 1024 * 1024 ))
TZ=${TZ:-UTC}
# <<< pdfsearch
EOF

log "Pulling images (several GB, first time only)..."
( cd "$RAGFLOW_DIR/docker" && docker compose pull )
log "Starting the stack..."
( cd "$RAGFLOW_DIR/docker" && docker compose up -d )

# Our scripts
mkdir -p "$APP_DIR" /var/lib/pdfsearch
install -m 0755 "$HERE/provision.py" "$APP_DIR/provision.py"
install -m 0644 "$HERE/../ingest_folder.py" "$APP_DIR/ingest_folder.py" 2>/dev/null || \
  install -m 0644 "$HERE/ingest_folder.py" "$APP_DIR/ingest_folder.py"
python3 "$APP_DIR/provision.py" --conf "$CONF"

if [ "$SERVICE" = 1 ] && [ -d /run/systemd/system ]; then
  install -m 0644 "$HERE/pdfsearch-ingest.service" /etc/systemd/system/pdfsearch-ingest.service
  systemctl daemon-reload
  systemctl enable --now pdfsearch-ingest.service
  log "Background indexer enabled (rescans $PDF_DIR every ${RESCAN_MINUTES:-30} min)."
fi
log "Done. Open http://localhost in a browser."
