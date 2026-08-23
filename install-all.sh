#!/usr/bin/env bash
# Disaster recovery menu — install multiple homelab apps on Proxmox VE.
# Run on the Proxmox host as root.
set -euo pipefail

REPO_RAW="${DEBUGTHINGS_SCRIPTS_URL:-https://raw.githubusercontent.com/debugthings/proxmox-apps/main}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root on the Proxmox VE host." >&2
  exit 1
fi

echo "========================================"
echo "  debugthings — Disaster Recovery"
echo "========================================"
echo
echo "Select apps to install (space-separated numbers, or 'all'):"
echo "  1) Timer App        (port 3001)"
echo "  2) WiFi Control     (port 3002)"
echo "  3) Lunch Menu       (port 8080)"
echo "  q) Quit"
echo
read -r -p "Choice [all]: " choices
choices="${choices:-all}"

install_one() {
  local script="$1"
  echo
  echo ">>> Running ${script} ..."
  bash <(curl -fsSL "${REPO_RAW}/ct/${script}")
}

if [[ "$choices" == "all" ]]; then
  install_one "timer-app.sh"
  install_one "wifi-control.sh"
  install_one "lunchmenu.sh"
  exit 0
fi

for choice in $choices; do
  case "$choice" in
    1) install_one "timer-app.sh" ;;
    2) install_one "wifi-control.sh" ;;
    3) install_one "lunchmenu.sh" ;;
    q|Q) exit 0 ;;
    *) echo "Unknown choice: $choice" >&2; exit 1 ;;
  esac
done

echo
echo "Done."
