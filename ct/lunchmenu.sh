#!/usr/bin/env bash
# Create LXC and install St. Vrain Lunch Menu calendar. Run on Proxmox VE host as root.
set -euo pipefail

REPO_RAW="${DEBUGTHINGS_SCRIPTS_URL:-https://raw.githubusercontent.com/debugthings/proxmox-apps/main}"
source <(curl -fsSL "${REPO_RAW}/lib/common.sh?$(date +%s)")

APP="St. Vrain Lunch Menu"
CT_HOSTNAME="${CT_HOSTNAME:-lunchmenu}"
MEMORY="${MEMORY:-768}"
DISK="${DISK:-6}"
CORES="${CORES:-1}"

echo "========================================"
echo "  ${APP} — Proxmox LXC installer"
echo "========================================"
echo

deploy_app "lunchmenu" 8080 "$APP"
