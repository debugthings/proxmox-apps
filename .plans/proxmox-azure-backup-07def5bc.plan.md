<!-- 07def5bc-46c8-4dcf-917b-40aac64bc118 -->
---
todos:
  - id: "write-config"
    content: "Create /etc/proxmox-azure-backup.conf template with all tunable variables and inline comments"
    status: pending
  - id: "write-script"
    content: "Implement /usr/local/sbin/proxmox-azure-backup.sh with all 5 phases, flock, traps, sequential LXC loop, and summary reporting"
    status: pending
  - id: "write-docs"
    content: "Add script header with rclone.conf example, Azure setup steps, restore procedure, and Archive tier warnings"
    status: pending
  - id: "install-perms"
    content: "Set permissions: script 750 root:root, config 640 root:root, rclone.conf 600, create scratch dir and log file"
    status: pending
isProject: false
---
# Proxmox-to-Azure Archive Backup Script

## Deliverables

| File | Purpose |
|------|---------|
| [`/usr/local/sbin/proxmox-azure-backup.sh`](/usr/local/sbin/proxmox-azure-backup.sh) | Main backup script (root-owned, `chmod 750`) |
| [`/etc/proxmox-azure-backup.conf`](/etc/proxmox-azure-backup.conf) | User-editable config (VMIDs, paths, rclone remote, tuning) |
| [`/var/log/proxmox-azure-backup.log`](/var/log/proxmox-azure-backup.log) | Append-only execution log |
| [`/var/run/proxmox-azure-backup.lock`](/var/run/proxmox-azure-backup.lock) | flock lockfile |
| [`/root/.config/rclone/rclone.conf`](/root/.config/rclone/rclone.conf) | rclone Azure remote definition |

---

## Architecture

```mermaid
flowchart TD
    start([Cron triggers script]) --> lock{flock acquired?}
    lock -->|no| exitBusy[Exit 1: already running]
    lock -->|yes| prereq[Phase 0: Verify deps + remote]
    prereq --> lxcLoop[Phase 1: For each LXC VMID]
    lxcLoop --> vzdump["vzdump --compress zstd → scratch"]
    vzdump --> uploadLxc["rclone copy → Azure Archive"]
    uploadLxc --> delLxc[Delete local .tar.zst]
    delLxc --> lxcLoop
    lxcLoop --> plexMeta[Phase 2: tar|zstd Plex metadata bundle]
    plexMeta --> uploadMeta[rclone copy metadata bundle]
    uploadMeta --> delMeta[Delete local metadata bundle]
    delMeta --> plexMedia[Phase 3B: rclone copy Plex media dirs]
    plexMedia --> report[Phase 4: Summary log + exit code]
    report --> unlock[Release flock]
```

**Sequential LXC flow** (per your choice): each container is dumped, uploaded, and deleted before the next begins. Scratch space only needs to hold one LXC dump + one metadata bundle at a time — critical for a host also storing 24TB of Plex media.

**Plex media uses `rclone copy`** (per your choice): new/changed files upload; remote blobs are never deleted if local files disappear.

---

## Script Design

### Header and safety rails

```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
```

- Source config from `/etc/proxmox-azure-backup.conf` (fail if missing).
- `trap` on `ERR`, `INT`, `TERM` for cleanup logging and optional scratch purge on failure.
- `flock -n 9` on `/var/run/proxmox-azure-backup.lock` — exit immediately if another instance is running.
- All output piped through `tee -a "$LOG_FILE"` with ISO-8601 timestamps via a `log()` helper.

### Config file (`/etc/proxmox-azure-backup.conf`)

Key variables the user must edit:

```bash
# LXC containers to back up (space-separated VMIDs)
LXC_VMIDS=(100 101 102)

# Local scratch (must have space for largest single LXC dump + metadata bundle)
SCRATCH_DIR="/var/tmp/pbs_cloud_scratch"

# rclone remote name (defined in rclone.conf) and Azure container path
RCLONE_REMOTE="azurearchive"
RCLONE_DEST="proxmox-backups"          # container/prefix root

# Plex paths
PLEX_METADATA_DIR="/var/lib/plexmediaserver/Library/Application Support/Plex Media Server"
PLEX_MEDIA_DIRS=(
  "/mnt/media/movies"
  "/mnt/media/tv"
)

# rclone tuning (conservative homelab defaults)
RCLONE_TRANSFERS=4
RCLONE_CHECKERS=8
RCLONE_BUFFER_SIZE="64M"
RCLONE_MULTI_THREAD_CUTOFF="256M"
RCLONE_MULTI_THREAD_STREAMS=4

# vzdump options
VZDUMP_MODE="snapshot"   # snapshot | suspend | stop
VZDUMP_EXTRA_OPTS=""     # e.g. "--exclude-path /mnt/media"
```

---

## Phase 0: Prerequisite Verification

Check binaries exist and are executable:

| Binary | Package |
|--------|---------|
| `rclone` | `curl https://rclone.org/install.sh \| bash` or `apt install rclone` |
| `zstd` | `apt install zstd` |
| `vzdump` | `proxmox-ve` (pre-installed on PVE hosts) |
| `flock` | `util-linux` (pre-installed) |
| `tar` | pre-installed |

Remote health check:

```bash
rclone lsd "${RCLONE_REMOTE}:" --timeout 30s
```

Fail fast with a clear log message if any check fails.

---

## Phase 1: LXC Backup (Sequential)

For each VMID in `LXC_VMIDS`:

1. Verify container exists: `pct status "$vmid"`.
2. Run vzdump into scratch:

```bash
vzdump "$vmid" \
  --mode "$VZDUMP_MODE" \
  --compress zstd \
  --dumpdir "$SCRATCH_DIR" \
  $VZDUMP_EXTRA_OPTS
```

This produces a single monolithic file like `vzdump-lxc-${vmid}-${DATE}.tar.zst` (typically hundreds of MB to several GB — satisfies the >100MB aggregation rule).

3. Immediately upload via rclone copy (Command A — per-container):

```bash
rclone copy "$SCRATCH_DIR/" "${RCLONE_REMOTE}:${RCLONE_DEST}/lxc/" \
  --include "vzdump-lxc-${vmid}-*.tar.zst" \
  --azureblob-access-tier Archive \
  --transfers "$RCLONE_TRANSFERS" \
  --checkers "$RCLONE_CHECKERS" \
  --buffer-size "$RCLONE_BUFFER_SIZE" \
  --multi-thread-cutoff "$RCLONE_MULTI_THREAD_CUTOFF" \
  --multi-thread-streams "$RCLONE_MULTI_THREAD_STREAMS" \
  --log-file "$LOG_FILE" \
  --log-format "date,time" \
  --stats 5m \
  --stats-one-line \
  --retries 5 \
  --low-level-retries 10
```

4. Verify rclone exit code; on success, delete the local `.tar.zst`.
5. On failure, log VMID + filename, set `FAILED=1`, continue or abort (script will abort remaining phases if any LXC step fails — configurable via `ABORT_ON_LXC_FAILURE=true`).

---

## Phase 2: Plex Metadata Bundling

The metadata directory contains millions of tiny files (thumbnails, SQLite DBs, cache). Bundle into one archive:

```bash
METADATA_ARCHIVE="${SCRATCH_DIR}/plex_metadata_$(date +%Y%m%d).tar.zst"

tar -C "$(dirname "$PLEX_METADATA_DIR")" \
  --exclude='Cache' \
  --exclude='Codecs' \
  --exclude='Plug-in Support/Caches' \
  --exclude='Plug-in Support/Data/com.plexapp.system/DataItems' \
  -cf - "$(basename "$PLEX_METADATA_DIR")" \
  | zstd -T0 -19 -o "$METADATA_ARCHIVE"
```

Notes:
- `-T0` uses all CPU cores for compression.
- Level `-19` maximizes compression (metadata is small; CPU cost is negligible vs. 24TB media).
- Excludes are safe regenerable caches; the critical DB (`Plug-in Support/Databases/`) is included.
- Raw media paths under `PLEX_MEDIA_DIRS` are never touched here.

Upload the single bundle (still Command A path):

```bash
rclone copy "$METADATA_ARCHIVE" "${RCLONE_REMOTE}:${RCLONE_DEST}/plex-metadata/" \
  --azureblob-access-tier Archive \
  [... same tuning flags ...]
```

Delete local bundle on success.

---

## Phase 3B: Plex Media Direct Copy

Large video files (multi-GB) need no bundling. Copy each media root:

```bash
for media_dir in "${PLEX_MEDIA_DIRS[@]}"; do
  label="$(basename "$media_dir")"
  rclone copy "$media_dir" "${RCLONE_REMOTE}:${RCLONE_DEST}/plex-media/${label}/" \
    --azureblob-access-tier Archive \
    --transfers "$RCLONE_TRANSFERS" \
    --checkers "$RCLONE_CHECKERS" \
    --buffer-size "$RCLONE_BUFFER_SIZE" \
    --multi-thread-cutoff "$RCLONE_MULTI_THREAD_CUTOFF" \
    --multi-thread-streams "$RCLONE_MULTI_THREAD_STREAMS" \
    --fast-list \
    --log-file "$LOG_FILE" \
    --stats 5m \
    --stats-one-line \
    --retries 5 \
    --low-level-retries 10
done
```

Cost notes for 24TB first run:
- **Write transactions**: one PUT per blob block (large files use block blobs with fewer API calls than millions of tiny files).
- **`--fast-list`**: reduces LIST API calls when comparing existing remote state.
- **Monthly schedule**: minimizes repeated LIST/GET operations.
- **Archive tier**: lowest $/GB storage, but blobs are offline until rehydrated (hours). Document this in script header comments.

---

## Phase 4: Cleanup and Reporting

- Remove any remaining files in `$SCRATCH_DIR` (should be empty if sequential flow succeeded).
- Print summary block to log:

```
=== Backup Summary ===
Start:    2026-03-01T02:00:01-06:00
End:      2026-03-01T14:32:17-06:00
Duration: 12h 32m 16s
LXC:      3/3 succeeded (VMIDs: 100 101 102)
Metadata: OK (1.2 GB uploaded)
Media:    OK (movies: 18TB, tv: 6TB — rclone stats)
Status:   SUCCESS
```

- Track `SECONDS` from bash or `date +%s` delta.
- Exit `0` on full success, `1` on any failure.

---

## rclone Configuration

Place at [`/root/.config/rclone/rclone.conf`](/root/.config/rclone/rclone.conf) (mode `600`):

```ini
[azurearchive]
type = azureblob
account = YOUR_STORAGE_ACCOUNT_NAME
key = YOUR_ACCOUNT_KEY
# OR use SAS token (preferred for least privilege):
# sas_url = https://YOUR_ACCOUNT.blob.core.windows.net/proxmox-backups?sv=...
```

**Setup steps:**

1. Create Azure Storage Account (Standard, LRS is cheapest for archive backups).
2. Create blob container `proxmox-backups`.
3. Generate either an account key or a scoped SAS token (write + list + read on that container only).
4. Test: `rclone lsd azurearchive:proxmox-backups`
5. Test Archive tier upload: `echo test | rclone rcat azurearchive:proxmox-backups/test.txt --azureblob-access-tier Archive`

**Alternative auth** (recommended for production): Azure service principal via `env_auth = true` + environment variables, keeping secrets out of the config file. The script will document this as an optional upgrade path.

---

## Cron Schedule

Edit root crontab (`crontab -e` as root):

```cron
# Proxmox + Plex → Azure Archive backup — 2:00 AM on the 1st of every month
0 2 1 * * /usr/local/sbin/proxmox-azure-backup.sh >> /var/log/proxmox-azure-backup.log 2>&1
```

The script already logs internally via `tee`; the cron redirect is a safety net for anything outside the `log()` function.

**Pre-flight checklist before first cron run:**
- Confirm scratch disk free space >= largest LXC dump (check with a manual `vzdump` dry run).
- Run script manually once: `/usr/local/sbin/proxmox-azure-backup.sh`
- Monitor first 24TB media upload — expect multiple days on typical homelab uplink; consider `screen`/`tmux` for manual first run.

---

## Important Operational Warnings (embedded in script header)

1. **Archive tier rehydration**: restoring any blob requires setting tier to Hot/Cool first (Standard priority: ~15 hours for large blobs). Plan restore time accordingly.
2. **Archive minimum retention**: Azure bills a 180-day minimum storage charge per blob moved to Archive, even if deleted early.
3. **First full media upload**: ~24TB at 100 Mbps ≈ 22 days continuous. Sequential LXC/metadata phases finish in hours; media dominates runtime.
4. **Do not use `rclone sync` on media** — confirmed `copy` mode prevents accidental remote deletion.
5. **Plex metadata restore**: stop Plex, extract bundle over metadata dir, fix ownership (`chown plex:plex`), restart.

---

## Implementation Todos
