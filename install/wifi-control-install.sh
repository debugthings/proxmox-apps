#!/usr/bin/env bash
# Install WiFi Control inside a Debian LXC. Run as root inside the container.
set -euo pipefail

INSTALL_URL="${WIFI_CONTROL_INSTALL_URL:-https://raw.githubusercontent.com/debugthings/wifi-control/main/install.sh}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root inside the LXC container." >&2
  exit 1
fi

echo "==> Installing WiFi Control from ${INSTALL_URL}"
curl -fsSL "$INSTALL_URL" | bash
