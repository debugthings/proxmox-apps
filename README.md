# debugthings Proxmox LXC scripts

Slim, self-hosted [community-scripts](https://github.com/community-scripts/ProxmoxVE)-style installers for homelab apps. Run on your **Proxmox VE host** as root to create a Debian LXC and install an app in one step.

## Quick install (one command per app)

On the Proxmox host:

```bash
# Timer App — http://<ct-ip>:3001
bash -c "$(curl -fsSL https://raw.githubusercontent.com/debugthings/proxmox-apps/main/ct/timer-app.sh)"

# WiFi Control — http://<ct-ip>:3002
bash -c "$(curl -fsSL https://raw.githubusercontent.com/debugthings/proxmox-apps/main/ct/wifi-control.sh)"

# St. Vrain Lunch Menu — http://<ct-ip>:8080
bash -c "$(curl -fsSL https://raw.githubusercontent.com/debugthings/proxmox-apps/main/ct/lunchmenu.sh)"
```

## Disaster recovery menu

Install multiple apps interactively:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/debugthings/proxmox-apps/main/install-all.sh)"
```

## Interactive installer

Each `ct/*.sh` script prompts on a TTY (community-scripts style):

1. **Default** — next free CTID (starting search at 100), DHCP, app resource defaults; confirms before create
2. **Advanced** — choose CTID, hostname, storage, bridge, IP, memory, disk, cores

Silent / scripted installs:

```bash
NONINTERACTIVE=1 bash -c "$(curl -fsSL https://raw.githubusercontent.com/debugthings/proxmox-apps/main/ct/wifi-control.sh)"
```

## Configuration (environment variables)

Env vars set defaults shown in the interactive prompts (or the full config when `NONINTERACTIVE=1`):

| Variable | Default | Description |
|---|---|---|
| `CTID` | next free ID (`pvesh /cluster/nextid`) | Container ID (skips existing CTs **and** VMs) |
| `CT_HOSTNAME` | app name | LXC hostname (do not use `HOSTNAME` — that is the PVE node name) |
| `STORAGE` | `local-lvm` | Rootfs storage |
| `TEMPLATE_STORAGE` | `local` | Template storage |
| `BRIDGE` | `vmbr0` | Network bridge |
| `IP` | `dhcp` | `dhcp` or `192.168.1.50/24,gw=192.168.1.1` |
| `MEMORY` | per app | RAM in MB |
| `CORES` | per app | CPU cores |
| `DISK` | per app | Disk GB |
| `SSH_PUBKEY` | `~/.ssh/authorized_keys` | Root SSH key in CT |
| `NONINTERACTIVE` | `0` | `1` = skip prompts |

Example — static IP, non-interactive:

```bash
NONINTERACTIVE=1 CTID=150 IP=192.168.1.60/24,gw=192.168.1.1 bash -c "$(curl -fsSL https://raw.githubusercontent.com/debugthings/proxmox-apps/main/ct/timer-app.sh)"
```

## What each script does

1. Downloads a Debian 12 template if needed
2. Creates and starts an unprivileged LXC
3. Waits for network
4. Bootstraps `ca-certificates` + `curl` inside the CT (templates omit curl)
5. Runs the matching `install/*-install.sh` inside the container

App install scripts pull from the canonical GitHub repos (`debugthings/timer-app`, `debugthings/wifi-control`, `debugthings/stvraincalendarapi`).

## Apps

| Script | App repo | Port | Default RAM |
|---|---|---|---|
| `ct/timer-app.sh` | [timer-app](https://github.com/debugthings/timer-app) | 3001 | 1024 MB |
| `ct/wifi-control.sh` | [wifi-control](https://github.com/debugthings/wifi-control) | 3002 | 512 MB |
| `ct/lunchmenu.sh` | [stvraincalendarapi](https://github.com/debugthings/stvraincalendarapi) | 8080 | 768 MB |

## Re-install on an existing container

To install the app inside a container you already created:

```bash
pct exec <CTID> -- bash -c "$(curl -fsSL https://raw.githubusercontent.com/debugthings/proxmox-apps/main/install/timer-app-install.sh)"
```

## License

MIT
