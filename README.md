# Exon-NfSen - Dockerized NfSen NetFlow Analyzer

**NfSen 1.3.6p1 + NfDump 1.6.17** on Ubuntu 20.04 — fully Dockerized.

## Quick Start

```bash
git clone https://github.com/rezwanvaiya2-0/exon-nfsen.git
cd exon-nfsen
docker-compose up -d --build
```

> **`--build` is only needed on the first run.** After that, restarting the container only requires `docker-compose down && docker-compose up -d` (no `--build`). Your sources, config, and data all persist thanks to Docker volumes.

Access: **http://\<YOUR_IP\>:8070/nfsen.php**

Timezone: **Asia/Dhaka**

> **UDP ports `2055` and `2056` are pre-opened.** Every router needs its own port, and that port must be added to `docker-compose.yml` before its data can arrive. To connect a router on a **new** port: add the port + source in `docker-compose.yml`, then run `docker compose up -d` — ~3 seconds, **no image rebuild, no data loss**. See [Adding a Router on a New Port](#adding-a-router-on-a-new-port).

---

## ⚠️ First Time Setup: Remove Default Source

The container comes with a **default source** `exonhost_microtik` listening on port **2055**. Before you can add your own routers, you **must remove this default source** first.

> **Why?** Multiple sources cannot share the same port. The default source occupies port 2055, so your new router source on the same port will conflict.

Remove it with this one-liner (works on any host — no `sed` required):

```bash
docker exec exon-nfsen bash -c "sed -i \"/'exonhost_microtik' =>/d\" /var/nfsen/etc/nfsen.conf && /var/nfsen/bin/nfsen reconfig && echo '✓ Removed'"
```

Verify it's gone:
```bash
docker exec exon-nfsen grep -A 5 '%sources' /var/nfsen/etc/nfsen.conf
```

---

## Managing Router Sources

> ⚠️ **Host `sed` may not be installed!** If you get `Command 'sed' not found`, use the **`docker exec` method** instead (no host tools needed).

### Add a source with IP

#### Method 1: Docker exec (recommended — works on any host)

Replace `NAME`, `IP_ADDRESS`, and `COLOR` with your values:

```bash
docker exec exon-nfsen bash -c "sed -i \"/^);$/i\\    'NAME' => { 'port' => '2055', 'IP' => 'IP_ADDRESS', 'col' => '#COLOR', 'type' => 'netflow' },\" /var/nfsen/etc/nfsen.conf && /var/nfsen/bin/nfsen reconfig && echo '✓ Done'"
```

#### Method 2: Docker cp (uses host sed)

```bash
docker cp exon-nfsen:/var/nfsen/etc/nfsen.conf /tmp/nfsen.conf && \
sed -i "/^);$/i\\    'NAME' => { 'port' => '2055', 'IP' => 'IP_ADDRESS', 'col' => '#COLOR', 'type' => 'netflow' }," /tmp/nfsen.conf && \
docker cp /tmp/nfsen.conf exon-nfsen:/var/nfsen/etc/nfsen.conf && \
docker exec exon-nfsen /var/nfsen/bin/nfsen reconfig && \
echo "✓ Done"
```

> ⚠️ **If you have existing sources without IP, this will fail!** You must first add `'IP' => '0.0.0.0'` to all existing sources before adding a new one with an IP.

---

### Remove a source

#### Method 1: Docker exec (recommended — works on any host)

Replace `NAME` with your source name (e.g., `router1`, `exonhost_microtik`):

```bash
docker exec exon-nfsen bash -c "sed -i \"/'NAME' =>/d\" /var/nfsen/etc/nfsen.conf && /var/nfsen/bin/nfsen reconfig && echo '✓ Removed'"
```

Example — remove the default source:
```bash
docker exec exon-nfsen bash -c "sed -i \"/'exonhost_microtik' =>/d\" /var/nfsen/etc/nfsen.conf && /var/nfsen/bin/nfsen reconfig && echo '✓ Removed'"
```

#### Method 2: Docker cp (uses host sed)

```bash
docker cp exon-nfsen:/var/nfsen/etc/nfsen.conf /tmp/nfsen.conf && \
sed -i "/'ROUTERNAME' =>/d" /tmp/nfsen.conf && \
docker cp /tmp/nfsen.conf exon-nfsen:/var/nfsen/etc/nfsen.conf && \
docker exec exon-nfsen /var/nfsen/bin/nfsen reconfig && \
echo "✓ Removed"
```

> ⚠️ **No trailing space after `\`!** The backslash must be the very last character on the line. A space after `\` will break the command chain.

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

Only **UDP ports `2055` and `2056`** are open by default. When you connect a router that sends NetFlow to a **new port**, that port must be opened in `docker-compose.yml` — otherwise the router's packets are dropped and you will see no data.

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

3. Add the source to `NFSEN_SOURCES` (the container configures it automatically on every start):

```yaml
    environment:
      - NFSEN_SOURCES=2055:exonhost_microtik:#0000ff,2070:myrouter:#FF0000
```

4. Recreate the container — done:

```bash
docker compose up -d
```

That's it: the port opens **and** the router source is configured automatically. Takes ~3 seconds. (Commands use `docker compose` — Docker v2. If your VPS has the older tool, use `docker-compose` instead.)

> ✅ **No rebuild:** the image is not rebuilt — only the container is recreated, fast and safe.
> ✅ **No data loss:** `docker compose up -d` keeps all your NetFlow data (it lives in Docker volumes).
> ⚠️ **The ONLY command that deletes your data is `docker compose down -v`** — never add `-v` unless you want a completely fresh start.

---

## Notes

- **UDP ports 2055 and 2056** are pre-opened — add more in `docker-compose.yml` as needed (see [Adding a Router on a New Port](#adding-a-router-on-a-new-port))
- Sources defined in `NFSEN_SOURCES` are configured automatically on every container start — so manage ALL your sources there (`docker exec` additions get overwritten on restart)
- Rebuilding the image resets nfsen.conf — re-run the add commands
- NetFlow data in Docker volumes survives rebuilds and recreates
- ⚠️ Only `docker compose down -v` deletes data — never add `-v` unless you want a fresh start

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

# Delete the flow data directly from Docker volumes
rm -rf /var/lib/docker/volumes/exon-nfsen_nfsen-data/_data/live/*
rm -rf /var/lib/docker/volumes/exon-nfsen_nfsen-stat/_data/live/*
rm -rf /var/lib/docker/volumes/exon-nfsen_nfsen-var/_data/*

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
| Web UI shows `nfsend connect() error` | `docker restart exon-nfsen`, or `docker exec exon-nfsen /var/nfsen/bin/nfsen stop && docker exec exon-nfsen /var/nfsen/bin/nfsen start` |
| Config changes not showing after reconfig | `docker exec exon-nfsen /var/nfsen/bin/nfsen stop && docker exec exon-nfsen /var/nfsen/bin/nfsen start` (full restart if reconfig didn't work) |
| `Error: missing parameter 'IP' for multiple sources collector` | Add `'IP' => '0.0.0.0'` to all existing sources manually. See [IP Requirement](#-important-ip-requirement-for-multiple-sources) |
| `Reconfig: No changes found!` | The source name doesn't exist — check with `docker exec exon-nfsen grep -A 20 '%sources' /var/nfsen/etc/nfsen.conf` |
| `Command 'sed' not found` | Your host lacks `sed`. Use the **Docker exec** method instead (no host tools needed). See [Remove a source](#remove-a-source) |
| Port already in use | Change Apache port in `docker-compose.yml` |
| Can't access port 8070 | Check firewall: `ufw allow 8070/tcp` |
| NfSen not starting | `docker logs exon-nfsen --tail 30`, then `docker restart exon-nfsen` |
| `nfsend connect() error` after disk full | Socket is dead. Restart the container: `docker restart exon-nfsen` |
