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

## Configuration (environment variables)

All `ct/*.sh` scripts accept overrides on the Proxmox host:

| Variable | Default | Description |
|---|---|---|
| `CTID` | next free ID | Container ID |
| `HOSTNAME` | app name | LXC hostname |
| `STORAGE` | `local-lvm` | Rootfs storage |
| `TEMPLATE_STORAGE` | `local` | Template storage |
| `BRIDGE` | `vmbr0` | Network bridge |
| `IP` | `dhcp` | `dhcp` or `192.168.1.50/24,gw=192.168.1.1` |
| `MEMORY` | per app | RAM in MB |
| `CORES` | per app | CPU cores |
| `DISK` | per app | Disk GB |
| `SSH_PUBKEY` | `~/.ssh/authorized_keys` | Root SSH key in CT |

Example — static IP:

```bash
CTID=150 IP=192.168.1.60/24,gw=192.168.1.1 bash -c "$(curl -fsSL https://raw.githubusercontent.com/debugthings/proxmox-apps/main/ct/timer-app.sh)"
```

## What each script does

1. Downloads a Debian 12 template if needed
2. Creates and starts an unprivileged LXC
3. Waits for network
4. Runs the matching `install/*-install.sh` inside the container

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
