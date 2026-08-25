#!/usr/bin/env bash
# Shared helpers for debugthings Proxmox LXC scripts.
# Sourced by ct/*.sh on the Proxmox VE host (run as root).
set -euo pipefail

REPO_RAW="${DEBUGTHINGS_SCRIPTS_URL:-https://raw.githubusercontent.com/debugthings/proxmox-apps/main}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

msg_info()  { echo -e "${YELLOW}→${NC} $*"; }
msg_ok()    { echo -e "${GREEN}✓${NC} $*"; }
msg_error() { echo -e "${RED}✗${NC} $*" >&2; }
msg_ask()   { echo -ne "${CYAN}?${NC} $*"; }

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

ctid_in_use() {
  pct status "$1" >/dev/null 2>&1
}

list_storages() {
  pvesm status 2>/dev/null | awk 'NR>1 {print $1}' | tr '\n' ' '
}

ask_value() {
  # ask_value VAR "Prompt" "default"
  local var="$1" prompt="$2" default="${3:-}"
  local reply
  if [[ -n "$default" ]]; then
    msg_ask "${prompt} [${default}]: "
  else
    msg_ask "${prompt}: "
  fi
  read -r reply || true
  if [[ -z "$reply" ]]; then
    reply="$default"
  fi
  printf -v "$var" '%s' "$reply"
}

ask_yes_no() {
  # ask_yes_no VAR "Prompt" "Y"|"N"
  local var="$1" prompt="$2" default="${3:-Y}"
  local reply hint
  if [[ "${default^^}" == "Y" ]]; then hint="Y/n"; else hint="y/N"; fi
  msg_ask "${prompt} [${hint}]: "
  read -r reply || true
  reply="${reply:-$default}"
  case "${reply,,}" in
    y|yes) printf -v "$var" '1' ;;
    *)     printf -v "$var" '0' ;;
  esac
}

print_settings_summary() {
  echo
  echo "----------------------------------------"
  echo "  Container settings"
  echo "----------------------------------------"
  echo "  CTID:              ${CTID}"
  echo "  Hostname:          ${HOSTNAME}"
  echo "  Storage:           ${STORAGE}"
  echo "  Template storage:  ${TEMPLATE_STORAGE}"
  echo "  Bridge:            ${BRIDGE}"
  echo "  IP:                ${IP}"
  echo "  Memory / Swap:     ${MEMORY} MB / ${SWAP} MB"
  echo "  Cores / Disk:      ${CORES} / ${DISK} GB"
  echo "  Unprivileged:      ${UNPRIVILEGED}"
  echo "  Start on boot:     ${ONBOOT}"
  echo "----------------------------------------"
  echo
}

# Interactive Default / Advanced settings (community-scripts style).
# Skip with NONINTERACTIVE=1 or when stdin is not a TTY (use env defaults).
gather_settings() {
  local suggested
  suggested="$(next_free_ctid)"

  CTID="${CTID:-$suggested}"
  HOSTNAME="${HOSTNAME:-app}"
  STORAGE="${STORAGE:-local-lvm}"
  TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-local}"
  BRIDGE="${BRIDGE:-vmbr0}"
  IP="${IP:-dhcp}"
  MEMORY="${MEMORY:-512}"
  SWAP="${SWAP:-128}"
  CORES="${CORES:-1}"
  DISK="${DISK:-4}"
  UNPRIVILEGED="${UNPRIVILEGED:-1}"
  ONBOOT="${ONBOOT:-1}"

  if [[ "${NONINTERACTIVE:-0}" == "1" ]]; then
    msg_info "NONINTERACTIVE=1 — using defaults (CTID=${CTID})"
    return 0
  fi

  if [[ ! -t 0 ]]; then
    msg_info "No TTY — using defaults (CTID=${CTID}). Pass env vars or run interactively."
    return 0
  fi

  local mode confirm
  echo "Install mode:"
  echo "  1) Default   — next free CTID (${suggested}), DHCP, app defaults"
  echo "  2) Advanced  — choose CTID, storage, network, resources"
  echo
  ask_value mode "Select" "1"

  case "$mode" in
    2|a|A|advanced|Advanced)
      echo
      msg_info "Available storages: $(list_storages)"
      echo
      while true; do
        ask_value CTID "Container ID" "$suggested"
        if [[ ! "$CTID" =~ ^[0-9]+$ ]]; then
          msg_error "CTID must be numeric."
          continue
        fi
        if ctid_in_use "$CTID"; then
          msg_error "CT ${CTID} already exists."
          suggested="$(next_free_ctid)"
          continue
        fi
        break
      done
      ask_value HOSTNAME "Hostname" "$HOSTNAME"
      ask_value STORAGE "Rootfs storage" "$STORAGE"
      ask_value TEMPLATE_STORAGE "Template storage" "$TEMPLATE_STORAGE"
      ask_value BRIDGE "Bridge" "$BRIDGE"
      echo "  IP examples: dhcp   or   192.168.1.50/24,gw=192.168.1.1"
      ask_value IP "IP config" "$IP"
      ask_value MEMORY "Memory (MB)" "$MEMORY"
      ask_value SWAP "Swap (MB)" "$SWAP"
      ask_value CORES "CPU cores" "$CORES"
      ask_value DISK "Disk (GB)" "$DISK"
      ask_value UNPRIVILEGED "Unprivileged (1/0)" "$UNPRIVILEGED"
      ask_value ONBOOT "Start on boot (1/0)" "$ONBOOT"
      ;;
    *)
      CTID="$suggested"
      # Keep app-provided HOSTNAME/MEMORY/DISK/CORES; network defaults
      ;;
  esac

  print_settings_summary
  ask_yes_no confirm "Create container with these settings?" "Y"
  if [[ "$confirm" != "1" ]]; then
    msg_error "Aborted."
    exit 1
  fi
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
  if pct status "$CTID" >/dev/null 2>&1; then
    msg_error "CT $CTID already exists. Pick another ID."
    exit 1
  fi

  ensure_debian_template

  local storage="${STORAGE}"
  local template_storage="${TEMPLATE_STORAGE}"
  local bridge="${BRIDGE}"
  local ip="${IP}"
  local memory="${MEMORY}"
  local swap="${SWAP}"
  local cores="${CORES}"
  local disk="${DISK}"
  local hostname="${HOSTNAME}"
  local unprivileged="${UNPRIVILEGED}"
  local onboot="${ONBOOT}"
  local ssh_key="${SSH_PUBKEY:-${HOME}/.ssh/authorized_keys}"

  local net="name=eth0,bridge=${bridge},ip=${ip}"
  local -a args=(
    "$CTID"
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

  msg_info "Creating CT $CTID ($hostname) ..."
  pct create "${args[@]}"
  pct start "$CTID"
  msg_ok "CT $CTID started"
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
  if [[ "${IP}" == "dhcp" ]]; then
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
  gather_settings
  create_debian_ct
  wait_for_network "$CTID"
  run_install_in_ct "$CTID" "$install_name"
  print_ct_summary "$CTID" "$port" "$label"
}
