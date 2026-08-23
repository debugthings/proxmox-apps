#!/usr/bin/env bash
# Shared helpers for debugthings Proxmox LXC scripts.
# Sourced by ct/*.sh on the Proxmox VE host (run as root).
set -euo pipefail

REPO_RAW="${DEBUGTHINGS_SCRIPTS_URL:-https://raw.githubusercontent.com/debugthings/proxmox-apps/main}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

msg_info()  { echo -e "${YELLOW}→${NC} $*"; }
msg_ok()    { echo -e "${GREEN}✓${NC} $*"; }
msg_error() { echo -e "${RED}✗${NC} $*" >&2; }

require_proxmox_host() {
  if [[ "$(id -u)" -ne 0 ]]; then
    msg_error "Run as root on the Proxmox VE host."
    exit 1
  fi
  if ! command -v pct >/dev/null 2>&1; then
    msg_error "pct not found — this must run on Proxmox VE."
    exit 1
  fi
}

next_free_ctid() {
  local id=100
  while pct status "$id" >/dev/null 2>&1; do
    id=$((id + 1))
  done
  echo "$id"
}

ensure_debian_template() {
  local storage="${TEMPLATE_STORAGE:-local}"
  if [[ -z "${TEMPLATE:-}" ]]; then
    pveam update >/dev/null
    TEMPLATE="$(pveam available --section system | awk '/debian-12-standard.*amd64/ {print $2}' | tail -1)"
  fi
  if [[ -z "$TEMPLATE" ]]; then
    msg_error "No debian-12-standard amd64 template found. Set TEMPLATE= manually."
    exit 1
  fi
  if ! pveam list "$storage" 2>/dev/null | grep -q "$TEMPLATE"; then
    msg_info "Downloading template $TEMPLATE ..."
    pveam download "$storage" "$TEMPLATE"
  fi
  msg_ok "Template ready: $TEMPLATE"
}

create_debian_ct() {
  local ctid="${CTID:-$(next_free_ctid)}"
  CTID="$ctid"

  if pct status "$ctid" >/dev/null 2>&1; then
    msg_error "CT $ctid already exists. Set CTID= to a free ID."
    exit 1
  fi

  ensure_debian_template

  local storage="${STORAGE:-local-lvm}"
  local template_storage="${TEMPLATE_STORAGE:-local}"
  local bridge="${BRIDGE:-vmbr0}"
  local ip="${IP:-dhcp}"
  local memory="${MEMORY:-512}"
  local swap="${SWAP:-128}"
  local cores="${CORES:-1}"
  local disk="${DISK:-4}"
  local hostname="${HOSTNAME:-app}"
  local unprivileged="${UNPRIVILEGED:-1}"
  local onboot="${ONBOOT:-1}"
  local ssh_key="${SSH_PUBKEY:-${HOME}/.ssh/authorized_keys}"

  local net="name=eth0,bridge=${bridge},ip=${ip}"
  local -a args=(
    "$ctid"
    "${template_storage}:vztmpl/${TEMPLATE}"
    --hostname "$hostname"
    --memory "$memory"
    --swap "$swap"
    --cores "$cores"
    --rootfs "${storage}:${disk}"
    --net0 "$net"
    --unprivileged "$unprivileged"
    --onboot "$onboot"
    --features nesting=0
    --ostype debian
    --start 0
  )

  if [[ -n "${CT_PASSWORD:-}" ]]; then
    args+=(--password "$CT_PASSWORD")
  fi
  if [[ -f "$ssh_key" ]]; then
    args+=(--ssh-public-keys "$ssh_key")
  fi

  msg_info "Creating CT $ctid ($hostname) ..."
  pct create "${args[@]}"
  pct start "$ctid"
  msg_ok "CT $ctid started"
}

wait_for_network() {
  local ctid="$1"
  msg_info "Waiting for network in CT $ctid ..."
  local i
  for i in $(seq 1 40); do
    if pct exec "$ctid" -- ping -c1 -W1 1.1.1.1 >/dev/null 2>&1; then
      msg_ok "Network ready"
      return 0
    fi
    sleep 2
  done
  msg_error "Network not ready after 80s"
  exit 1
}

run_install_in_ct() {
  local ctid="$1"
  local install_name="$2"
  local url="${REPO_RAW}/install/${install_name}-install.sh"

  msg_info "Running install script in CT $ctid ..."
  pct exec "$ctid" -- bash -c "curl -fsSL '$url' | bash"
  msg_ok "Install finished"
}

print_ct_summary() {
  local ctid="$1"
  local port="$2"
  local label="$3"

  echo
  echo "========================================"
  msg_ok "${label} deployed in CT ${ctid}"
  echo "========================================"
  echo "  pct enter ${ctid}"
  if [[ "${IP:-dhcp}" == "dhcp" ]]; then
    echo -n "  IP: "
    pct exec "$ctid" -- hostname -I 2>/dev/null | awk '{print $1}' || echo "(dhcp)"
  else
    echo "  IP: ${IP%%/*}"
  fi
  echo "  URL: http://<ip>:${port}"
  echo
}

deploy_app() {
  local install_name="$1"
  local port="$2"
  local label="$3"

  require_proxmox_host
  create_debian_ct
  wait_for_network "$CTID"
  run_install_in_ct "$CTID" "$install_name"
  print_ct_summary "$CTID" "$port" "$label"
}
