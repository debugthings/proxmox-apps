#!/usr/bin/env bash
# Install WiFi Control inside a Debian LXC. Run as root inside the container.
set -euo pipefail

INSTALL_URL="${WIFI_CONTROL_INSTALL_URL:-https://raw.githubusercontent.com/debugthings/wifi-control/main/install.sh}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root inside the LXC container." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
if ! command -v curl >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y --no-install-recommends ca-certificates curl
fi

echo "==> Installing WiFi Control from ${INSTALL_URL}"
curl -fsSL "$INSTALL_URL" | bash
