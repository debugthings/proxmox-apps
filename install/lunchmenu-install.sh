#!/usr/bin/env bash
# Install St. Vrain Lunch Menu inside a Debian LXC. Run as root inside the container.
set -euo pipefail

REPO_URL="${LUNCHMENU_REPO:-https://github.com/debugthings/stvraincalendarapi.git}"
BRANCH="${LUNCHMENU_BRANCH:-master}"
APP_DIR="${APP_DIR:-/opt/stvrain-lunch-menu}"
ENV_FILE="${ENV_FILE:-/etc/stvrain-lunch-menu.env}"
SERVICE_NAME="stvrain-lunch-menu"
BUILD_DIR="$(mktemp -d)"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

cleanup() { rm -rf "$BUILD_DIR"; }
trap cleanup EXIT

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root inside the LXC container." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

log "Installing dependencies..."
apt-get update -qq
apt-get install -y --no-install-recommends ca-certificates curl git tzdata wget

if ! command -v dotnet >/dev/null 2>&1; then
  log "Installing .NET 10 SDK..."
  curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
  bash /tmp/dotnet-install.sh --channel 10.0 --install-dir /usr/share/dotnet
  ln -sf /usr/share/dotnet/dotnet /usr/local/bin/dotnet
fi

log "Cloning ${REPO_URL} ..."
git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$BUILD_DIR"

log "Publishing self-contained linux-x64 ..."
dotnet publish "$BUILD_DIR/StVrainToICSFunctionApp.csproj" \
  -c Release \
  -r linux-x64 \
  --self-contained true \
  -o "$BUILD_DIR/publish" \
  -p:DebugType=None \
  -p:DebugSymbols=false

STAGE="$BUILD_DIR/publish"
cp "$BUILD_DIR/deploy/lxc/install.sh" "$STAGE/"
cp "$BUILD_DIR/deploy/lxc/stvrain-lunch-menu.service" "$STAGE/"
cp "$BUILD_DIR/deploy/lxc/stvrain-lunch-menu.env.example" "$STAGE/"

TARBALL="/tmp/stvrain-lunch-menu.tar.gz"
tar -czf "$TARBALL" -C "$STAGE" .

log "Running app install.sh ..."
bash "$STAGE/install.sh" "$TARBALL"

log "Lunch menu ready at http://$(hostname -I | awk '{print $1}'):8080"
