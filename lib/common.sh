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

# True if CTID/VMID is taken by an LXC or QEMU guest (any node).
id_in_use() {
  local id="$1"
  [[ -f "/etc/pve/lxc/${id}.conf" ]] && return 0
  [[ -f "/etc/pve/qemu-server/${id}.conf" ]] && return 0
  if [[ -d /etc/pve/nodes ]]; then
    local node_dir
    for node_dir in /etc/pve/nodes/*/; do
      [[ -f "${node_dir}lxc/${id}.conf" ]] && return 0
      [[ -f "${node_dir}qemu-server/${id}.conf" ]] && return 0
    done
  fi
  if command -v pvesh >/dev/null 2>&1; then
    if pvesh get /cluster/resources --type vm --output-format json 2>/dev/null \
      | grep -qE "\"vmid\"[[:space:]]*:[[:space:]]*${id}([,}[:space:]]|$)"; then
      return 0
    fi
  fi
  pct status "$id" >/dev/null 2>&1 && return 0
  command -v qm >/dev/null 2>&1 && qm status "$id" >/dev/null 2>&1 && return 0
  return 1
}

next_free_ctid() {
  local id
  id="$(pvesh get /cluster/nextid 2>/dev/null || echo 100)"
  while id_in_use "$id"; do
    id=$((id + 1))
  done
  echo "$id"
}

list_storages() {
  pvesm status 2>/dev/null | awk 'NR>1 {print $1}' | tr '\n' ' '
}

ask_value() {
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
  echo "  Hostname:          ${CT_HOSTNAME}"
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
# Skip with NONINTERACTIVE=1. Do not use shell HOSTNAME — it is the PVE node name.
gather_settings() {
  local suggested confirm mode
  suggested="$(next_free_ctid)"

  CTID="${CTID:-$suggested}"
  CT_HOSTNAME="${CT_HOSTNAME:-app}"
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
    if id_in_use "$CTID"; then
      msg_error "ID ${CTID} already in use (LXC or VM). Set CTID= to a free ID."
      exit 1
    fi
    msg_info "NONINTERACTIVE=1 — using CTID=${CTID} hostname=${CT_HOSTNAME}"
    return 0
  fi

  # bash -c "$(curl ...)" keeps stdin as the TTY when run from a shell.
  if [[ ! -t 0 ]]; then
    msg_info "No TTY — using defaults (CTID=${CTID}). Use Advanced via a real shell or set env vars."
    if id_in_use "$CTID"; then
      CTID="$(next_free_ctid)"
      msg_info "ID was taken; using next free CTID=${CTID}"
    fi
    return 0
  fi

  echo "Install mode:"
  echo "  1) Default   — next free ID (${suggested}), DHCP, app defaults"
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
        if id_in_use "$CTID"; then
          msg_error "ID ${CTID} already in use (LXC or VM)."
          suggested="$(next_free_ctid)"
          continue
        fi
        break
      done
      ask_value CT_HOSTNAME "Hostname" "$CT_HOSTNAME"
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
  if id_in_use "$CTID"; then
    msg_error "ID $CTID already in use (LXC or VM). Pick another ID."
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
  local hostname="${CT_HOSTNAME}"
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

# Debian templates ship without curl; install scripts are fetched over HTTPS.
bootstrap_ct_base() {
  local ctid="$1"
  msg_info "Bootstrapping apt packages in CT $ctid (curl, ca-certificates) ..."
  pct exec "$ctid" -- bash -c '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y --no-install-recommends ca-certificates curl
  '
  msg_ok "Base packages ready"
}

run_install_in_ct() {
  local ctid="$1"
  local install_name="$2"
  local url="${REPO_RAW}/install/${install_name}-install.sh"

  bootstrap_ct_base "$ctid"
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
