# Exon-NfSen - Dockerized NfSen NetFlow Analyzer

**NfSen 1.3.6p1 + NfDump 1.6.17** on Ubuntu 20.04 — fully Dockerized.

## Quick Start

```bash
git clone https://github.com/rezwanvaiya2-0/exon-nfsen.git
cd exon-nfsen
docker-compose up -d --build
```

> **`--build` is only needed on the first run.** After that, restarting the container only requires `docker-compose down && docker-compose up -d` (no `--build`). Your sources, config, and data all persist thanks to the data folders next to `docker-compose.yml` (see [Data Folders](#data-folders-bind-mounts)).

Access: **http://\<YOUR_IP\>:8070/nfsen.php**

Timezone: **Asia/Dhaka**

> **UDP ports `2055` and `2056` are pre-opened.** Every router needs its own port, and that port must be added to `docker-compose.yml` before its data can arrive. To connect a router on a **new** port: add the port + source in `docker-compose.yml`, then run `docker compose up -d` — ~3 seconds, **no image rebuild, no data loss**. See [Adding a Router on a New Port](#adding-a-router-on-a-new-port).

---

## Data Folders (Bind Mounts)

Your data now lives in **4 real folders next to `docker-compose.yml`** — no more hidden Docker volumes. You can see, browse, back up, and even mount/unmount them without ever losing data:

| Folder | Inside the container | What it holds |
|---|---|---|
| `nfsen-data/` | `/var/nfsen/profiles-data` | Raw flow records (captured NetFlow files) |
| `nfsen-stat/` | `/var/nfsen/profiles-stat` | RRD graph files (the charts in the Web UI) |
| `nfsen-var/` | `/var/nfsen/var` | Logs, cache, runtime files |
| `nfsen-etc/` | `/var/nfsen/etc` | `nfsen.conf` (router sources config) |

- The folders are created automatically on first start (`docker compose up`), and the entrypoint seeds the default config + demo source when `nfsen-etc/` is empty.
- **Why does `docker volume ls` show nothing?** These 4 folders are **bind mounts**, not Docker volumes. `docker volume ls` only lists *named* volumes — bind mounts are plain host folders and are intentionally invisible there. That is **normal and correct**: the folders themselves *are* the storage. To confirm they are mounted, run `docker inspect exon-nfsen` and look at the `Mounts` section (each shows `"Type": "bind"` with the matching `Source`/`Destination`), or simply `ls` the 4 folders next to `docker-compose.yml`.
- **Mount / unmount freely** — `docker compose stop`, `down`, `up -d`, even `down -v` no longer delete anything: your data lives in the host folders, not inside Docker. Only `rm -rf` of the folders themselves deletes it (and the container should be stopped first — see [Clean up](#clean-up--delete-the-data-folders) below).
- **Back up anytime** (container can keep running): `cp -a nfsen-data nfsen-data-backup` or `tar czf nfsen-backup.tar.gz nfsen-data nfsen-stat nfsen-var nfsen-etc`.

### Clean up / delete the data folders

Because the folders are **bind mounts**, the running container is actively writing to them. So before deleting/cleaning a mounted folder, **unmount it first** (`docker compose down`) — deleting a folder that is still mounted can fail or leave the container in a broken state (it will keep trying to write into a deleted path).

**Option 1 — Delete EVERYTHING (complete clean slate):**

```bash
cd exon-nfsen

# 1) Unmount: stop and remove the container (releases the bind mounts)
docker compose down

# 2) Delete the data folders (this is the ONLY command that removes your data)
rm -rf nfsen-data nfsen-stat nfsen-var nfsen-etc

# 3) Remount fresh: folders are recreated empty and the entrypoint
#    auto-seeds the default config + demo source
sudo docker compose up -d
```

**Option 2 — Only clear the captured flow data (keep config + sources):**

```bash
cd exon-nfsen

# 1) Unmount first
docker compose down

# 2) Delete only the flow data + graphs (keeps nfsen.conf / router sources)
rm -rf nfsen-data/live/* nfsen-stat/live/*

# 3) Remount — same config, empty graphs
sudo docker compose up -d
```

> ℹ️ If the container is **already stopped** (e.g. after `docker compose stop` or `down`), the mounts are already released — you can delete the folders directly without any extra step. The rule is simple: **container stopped = folders free to delete; container running = unmount first.**

### Migrating from the old named volumes

If you already had data in the old Docker volumes and want to move it into the new folders:

```bash
cd exon-nfsen
git pull
# stop the container first
sudo docker compose down

# create the new folders first (docker compose up would create them, but we
# need them NOW so the copies below have a target)
mkdir -p nfsen-data nfsen-stat nfsen-var nfsen-etc

# copy the existing data from each old volume into its new folder
sudo cp -a /var/lib/docker/volumes/exon-nfsen_nfsen-data/_data/. nfsen-data/
sudo cp -a /var/lib/docker/volumes/exon-nfsen_nfsen-stat/_data/. nfsen-stat/
sudo cp -a /var/lib/docker/volumes/exon-nfsen_nfsen-var/_data/. nfsen-var/
sudo cp -a /var/lib/docker/volumes/exon-nfsen_nfsen-etc/_data/. nfsen-etc/

# fix ownership so NfSen can write to the copied data
sudo docker compose up -d
docker exec exon-nfsen chown -R netflow:www-data /var/nfsen/profiles-data/live/ && docker exec exon-nfsen chown -R www-data:www-data /var/nfsen/profiles-stat/live/

# old volumes are now unused - you may delete them to free space
sudo docker volume rm exon-nfsen_nfsen-data exon-nfsen_nfsen-stat exon-nfsen_nfsen-var exon-nfsen_nfsen-etc
```

> ⚠️ If you pull and start **without** migrating, the new folders start empty (your old data stays safe in the named volumes, just not mounted). Do the copy steps above first if you want to keep existing graphs.

---

---

## Managing Router Sources

### Add a source with IP

#### Docker exec (recommended)

Replace `NAME`, `IP_ADDRESS`, and `COLOR` with your values:

```bash
docker exec exon-nfsen bash -c "sed -i \"/^);$/i\\    'NAME' => { 'port' => '2055', 'IP' => 'IP_ADDRESS', 'col' => '#COLOR', 'type' => 'netflow' },\" /var/nfsen/etc/nfsen.conf && /var/nfsen/bin/nfsen reconfig && echo '✓ Done'"
```

> ⚠️ **If you have existing sources without IP, this will fail!** You must first add `'IP' => '0.0.0.0'` to all existing sources before adding a new one with an IP.

---

### Remove a source

#### Docker exec (recommended)

Replace `NAME` with your source name (e.g., `router1`):

```bash
docker exec exon-nfsen bash -c "sed -i \"/'NAME' =>/d\" /var/nfsen/etc/nfsen.conf && /var/nfsen/bin/nfsen reconfig && echo '✓ Removed'"
```

---

### List all sources

```bash
docker exec exon-nfsen grep -A 20 '%sources' /var/nfsen/etc/nfsen.conf
```

### Check NfSen status

```bash
docker exec exon-nfsen /var/nfsen/bin/nfsen status
```

---

## ⚠️ Important: IP Requirement for Multiple Sources

When you have **more than one source** configured, **NfSen requires ALL sources to have an `IP` field**.

If you add a source with an IP while existing sources lack one, the command will fail. Fix this by manually adding `'IP' => '0.0.0.0'` to each existing source first using the same sed method above.

> **Check your current sources:**
> ```bash
> docker exec exon-nfsen grep -A 20 '%sources' /var/nfsen/etc/nfsen.conf
> ```
> Then update any auto-filled `0.0.0.0` IPs with the actual source IPs by editing the config directly.

---

## Adding a Router on a New Port

Only **UDP ports `2055` and `2056`** are open, and a **demo source `router1`** on port 2055 ships by default (so the Web UI shows graph placeholders on first install — no more "no data available"). You can keep it or replace it with your real routers. When you connect a router that sends NetFlow to a **new port**, that port must be opened in `docker-compose.yml` — otherwise the router's packets are dropped and you will see no data.

### Step-by-step (example: new router on port 2070)

1. Edit `docker-compose.yml` on the VPS:

```bash
cd exon-nfsen
nano docker-compose.yml
```

2. Add the new port under `ports:` (only the ports you use are published):

```yaml
    ports:
      - "8070:8070"
      - "2055:2055/udp"
      - "2056:2056/udp"
      - "2070:2070/udp"      # <- new router port
```

3. Add the router source — `docker exec` is the recommended way, and it now **persists forever** (see note below):

```bash
docker exec exon-nfsen bash -c "sed -i \"/^);$/i\\    'myrouter' => { 'port' => '2070', 'col' => '#FF0000', 'type' => 'netflow' },\" /var/nfsen/etc/nfsen.conf && /var/nfsen/bin/nfsen reconfig && echo '✓ Done'"
```

> Prefer the env var? You can set `NFSEN_SOURCES=2070:myrouter:#FF0000` in `docker-compose.yml` instead — but pick **one** method, don't mix.

4. Recreate the container — done:

```bash
docker compose up -d
```

That's it: the port opens **and** the router source is configured automatically. Takes ~3 seconds. (Commands use `docker compose` — Docker v2. If your VPS has the older tool, use `docker-compose` instead.)

> ✅ **No rebuild:** the image is not rebuilt — only the container is recreated, fast and safe.
> ✅ **No data loss:** `docker compose up -d` keeps all your NetFlow data (it lives in the `nfsen-data/` folder next to `docker-compose.yml`).
> ⚠️ **`docker compose down -v` no longer deletes your data** — it now uses bind mounts, and `-v` only removes *named* volumes. Your data only disappears if you `rm -rf` the folders yourself (see [Data Folders](#data-folders-bind-mounts)).

### Replace or remove the demo `router1` source

The container ships with a demo source `router1` listening on port **2055** so the Web UI shows graphs on first install — **no manual setup needed**. It appears automatically on a fresh build, and the entrypoint also seeds it on any container that starts with zero sources (e.g. an older one whose config volume was seeded empty). Once you add your real routers, the fallback never runs again and your sources are never touched. Once you connect your real router, replace or remove the demo with `docker exec`:

```bash
# Remove the demo source
docker exec exon-nfsen bash -c "sed -i \"/'router1' =>/d\" /var/nfsen/etc/nfsen.conf && /var/nfsen/bin/nfsen reconfig && echo '✓ Removed'"
```

Or simply add your real router on port 2055 (see [Add a source with IP](#add-a-source-with-ip)) and ignore the demo until you remove it.

> ⚠️ **To keep the demo gone permanently, keep at least one real source.** If your `%sources` list ever becomes completely empty (e.g. you remove `router1` and have no other routers yet), the demo is re-seeded automatically on the next container start. That's the safety net that guarantees the Web UI always shows graphs — once you have any real router, the demo never comes back.

---

## Notes

- **UDP ports 2055 and 2056** are pre-opened — add more in `docker-compose.yml` as needed (see [Adding a Router on a New Port](#adding-a-router-on-a-new-port))
- A **demo source `router1`** on port 2055 ships by default (seeded automatically if a container has zero sources) so the Web UI shows graphs on first install — remove or replace it with your real routers (see [Replace or remove the demo source](#replace-or-remove-the-demo-router1-source))
- **Router sources added via `docker exec` now persist forever** — `nfsen.conf` lives in the `nfsen-etc/` folder, so it survives restarts, recreates, and even rebuilds. No env vars needed.
- The `NFSEN_SOURCES` env var is **optional** — use it only if you prefer managing sources in `docker-compose.yml` instead of `docker exec`
- **NetFlow data lives in the folders next to `docker-compose.yml`** (`nfsen-data/`, `nfsen-stat/`, `nfsen-var/`, `nfsen-etc/`) and survives rebuilds, recreates, and even `down -v` (see [Data Folders](#data-folders-bind-mounts))
- ⚠️ `docker compose down -v` no longer deletes anything — only `rm -rf nfsen-data nfsen-stat nfsen-var nfsen-etc` does
- ⚠️ `nfsen-etc/nfsen.conf` is seeded from the image only when the folder is **empty** — if you later change `config/nfsen.conf` in the repo, copy it over (`cp config/nfsen.conf nfsen-etc/nfsen.conf`) or delete the file and restart

---

## 🔥 Storage Full — Recover Disk Space

NfSen's NetFlow capture files accumulate quickly. When your VPS disk fills up (100%), `docker exec` commands will fail with:

```
OCI runtime exec failed: write /tmp/runc-processXXXXXX: no space left on device
```

And `nfsen stop` will fail because the Unix socket can't be written to:
```
setlogsock(): type='unix': path not available
```

Don't worry — here's how to recover:

### Step 1: Free a few MB to get Docker working again

Run these **host-level** commands (no `docker exec` needed):

```bash
docker system prune -f
docker builder prune -f
```

If that's not enough, also clean system logs:
```bash
sudo journalctl --vacuum-time=1d
sudo rm -f /var/log/syslog.1 /var/log/kern.log.1 2>/dev/null; true
```

Check if you have enough space now:
```bash
df -h /
```

> You only need **~50MB free** for `docker exec` to work again.

---

### Step 2: Stop everything and delete the data

**Method A — Quick (if `docker stop` works):**

```bash
# Stop the entire container (always works — doesn't need the nfsen socket)
docker stop exon-nfsen

# Delete the flow data directly from the data folders (bind mounts)
rm -rf nfsen-data/live/*
rm -rf nfsen-stat/live/*
rm -rf nfsen-var/*

# Start fresh
docker start exon-nfsen
```

**Method B — Via docker exec (if you already freed some space):**

```bash
# Delete the captured flow data (this frees the most space)
docker exec exon-nfsen bash -c "rm -rf /var/nfsen/profiles-data/live/* /var/nfsen/profiles-stat/live/*"

# Truncate logs too
docker exec exon-nfsen bash -c "truncate -s 0 /var/nfsen/var/nfsen.log"
```

---

### Step 3: Restart NfSen

If `docker stop/start` was used (Method A), the container handles this automatically.

If you used `docker exec` to delete (Method B), restart NfSen manually:

```bash
# Force-kill stale daemon if socket is broken
docker exec exon-nfsen bash -c "\
  pkill -f nfsend 2>/dev/null; sleep 1; \
  rm -f /var/nfsen/var/run/nfsen.comm /var/nfsen/var/run/nfsend.pid; \
  /var/nfsen/bin/nfsen reconfig; \
  /var/nfsen/bin/nfsen start\
"
```

Or simply restart the whole container: `docker restart exon-nfsen`.

---

### Verify recovery

```bash
# Check disk space
df -h /

# Check NfSen status
docker exec exon-nfsen /var/nfsen/bin/nfsen status

# Access Web UI: http://<YOUR_IP>:8070/nfsen.php
```

---

### ⚠️ Prevent this from happening again

NfSen accumulates data fast. To limit storage usage, add a data retention policy:

```bash
# Configure NfSen to keep only 7 days of data
docker exec exon-nfsen bash -c "echo '\$profiletimout = 7;' >> /var/nfsen/etc/nfsen.conf && /var/nfsen/bin/nfsen reconfig"
```

Or **set up a cron job** to auto-delete old data:

```bash
docker exec exon-nfsen bash -c "\
  (crontab -l 2>/dev/null; echo '0 3 * * * find /var/nfsen/profiles-data -type f -mtime +7 -delete') | crontab -\
"
```

> You can change `+7` to any number of days. Higher = more data kept, more disk used.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Web UI shows `Can not initialize globals` / `nfsend connect() error: No such file or directory` / `nfsend - connection failed!!` | The nfsend daemon is not running. On the **first start after switching to the data folders (bind mounts)** this means the `live` profile is missing (an empty `nfsen-stat/` folder hides it and NfSen refuses to start). Fix once: `docker compose up -d --build` — the entrypoint re-seeds the profile automatically. Then check `docker logs exon-nfsen` for `nfsend .... running` |
| Web UI shows `nfsend connect() error` (daemon was running before) | `docker restart exon-nfsen`, or `docker exec exon-nfsen /var/nfsen/bin/nfsen stop && docker exec exon-nfsen /var/nfsen/bin/nfsen start` |
| Config changes not showing after reconfig | `docker exec exon-nfsen /var/nfsen/bin/nfsen stop && docker exec exon-nfsen /var/nfsen/bin/nfsen start` (full restart if reconfig didn't work) |
| `Error: missing parameter 'IP' for multiple sources collector` | Add `'IP' => '0.0.0.0'` to all existing sources manually. See [IP Requirement](#-important-ip-requirement-for-multiple-sources) |
| `Reconfig: No changes found!` | The source name doesn't exist — check with `docker exec exon-nfsen grep -A 20 '%sources' /var/nfsen/etc/nfsen.conf` |
| Port already in use | Change Apache port in `docker-compose.yml` |
| Can't access port 8070 | Check firewall: `ufw allow 8070/tcp` |
| NfSen not starting | `docker logs exon-nfsen --tail 30`, then `docker restart exon-nfsen` |
| `nfsend connect() error` after disk full | Socket is dead. Restart the container: `docker restart exon-nfsen` |
