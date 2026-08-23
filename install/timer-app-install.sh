#!/usr/bin/env bash
# Install Timer App inside a Debian LXC. Run as root inside the container.
set -euo pipefail

INSTALL_URL="${TIMER_APP_INSTALL_URL:-https://raw.githubusercontent.com/debugthings/timer-app/master/install.sh}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root inside the LXC container." >&2
  exit 1
fi

echo "==> Installing Timer App from ${INSTALL_URL}"
curl -fsSL "$INSTALL_URL" | bash
