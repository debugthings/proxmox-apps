#!/usr/bin/env bash
# Create LXC and install Timer App. Run on Proxmox VE host as root.
set -euo pipefail

REPO_RAW="${DEBUGTHINGS_SCRIPTS_URL:-https://raw.githubusercontent.com/debugthings/proxmox-apps/main}"
source <(curl -fsSL "${REPO_RAW}/lib/common.sh")

APP="Timer App"
HOSTNAME="${HOSTNAME:-timer-app}"
MEMORY="${MEMORY:-1024}"
DISK="${DISK:-8}"
CORES="${CORES:-1}"

echo "========================================"
echo "  ${APP} — Proxmox LXC installer"
echo "========================================"
echo

deploy_app "timer-app" 3001 "$APP"
