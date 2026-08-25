#!/usr/bin/env bash
# Create LXC and install WiFi Control. Run on Proxmox VE host as root.
set -euo pipefail

REPO_RAW="${DEBUGTHINGS_SCRIPTS_URL:-https://raw.githubusercontent.com/debugthings/proxmox-apps/main}"
# Cache-bust: raw.githubusercontent.com caches ~5 minutes
source <(curl -fsSL "${REPO_RAW}/lib/common.sh?$(date +%s)")

APP="WiFi Control"
CT_HOSTNAME="${CT_HOSTNAME:-wifi-control}"
MEMORY="${MEMORY:-512}"
DISK="${DISK:-4}"
CORES="${CORES:-1}"

echo "========================================"
echo "  ${APP} — Proxmox LXC installer"
echo "========================================"
echo

deploy_app "wifi-control" 3002 "$APP"
