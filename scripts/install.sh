#!/usr/bin/env bash
set -euo pipefail

# Root check
if [[ $EUID -ne 0 ]]; then
  echo "[!] Please run as root (sudo)." >&2
  exit 1
fi

echo "[*] Installing prerequisites (Docker + Compose plugin) ..."
if ! command -v docker >/dev/null 2>&1; then
  # Install docker using convenience script
  curl -fsSL https://get.docker.com | sh
fi

if ! docker compose version >/dev/null 2>&1; then
  # Install docker compose plugin on Debian/Ubuntu
  apt-get update -y
  apt-get install -y docker-compose-plugin
fi

# Sysctls for OpenSearch
echo "[*] Applying sysctl tuning ..."
sysctl -w vm.max_map_count=262144 >/dev/null
sysctl -w fs.file-max=65536 >/dev/null
sysctl -w vm.swappiness=1 >/dev/null || true

# Create data dirs
source .env
mkdir -p "${MONGO_DB_PATH}" "${OPENSEARCH_DATA_PATH}" "${GRAYLOG_DATA_PATH}"

echo "[*] Starting the stack ..."
docker compose up -d

echo
echo "[*] Waiting for Graylog to be ready (can take a few minutes) ..."
# Health check loop
for i in {1..60}; do
  if curl -fsS http://127.0.0.1:9000/api/system/cluster/nodes >/dev/null 2>&1; then
    echo "[*] Graylog API is up."
    break
  fi
  sleep 5
done

echo "[*] To auto-provision inputs and dashboards, run:  ./scripts/provision.sh"
echo "[*] Default admin login: admin / admin (CHANGE IT!)."
