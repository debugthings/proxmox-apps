#!/usr/bin/env bash
# Create LXC and install WiFi Control. Run on Proxmox VE host as root.
set -euo pipefail

REPO_RAW="${DEBUGTHINGS_SCRIPTS_URL:-https://raw.githubusercontent.com/debugthings/proxmox-apps/main}"
source <(curl -fsSL "${REPO_RAW}/lib/common.sh")

APP="WiFi Control"
HOSTNAME="${HOSTNAME:-wifi-control}"
MEMORY="${MEMORY:-512}"
DISK="${DISK:-4}"
CORES="${CORES:-1}"

echo "========================================"
echo "  ${APP} — Proxmox LXC installer"
echo "========================================"
echo

deploy_app "wifi-control" 3002 "$APP"
