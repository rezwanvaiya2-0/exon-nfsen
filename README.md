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

> **No rebuild needed for new routers!** The container exposes a UDP port range `2055–3055`, so you can add up to 1000+ router sources without ever modifying `docker-compose.yml` or rebuilding. Just use `docker exec` to add a source (see [Managing Router Sources](#managing-router-sources)).

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

## Port Range — No Rebuild Needed for New Sources

`docker-compose.yml` exposes a **UDP port range `2055–3055`** (1000+ ports), so you can add up to **1000+ routers** on different ports without ever rebuilding the project.

### Adding a new router source (example: port 2056):

```bash
docker exec exon-nfsen bash -c "sed -i \"/^);\$/i\\    'router2' => { 'port' => '2056', 'col' => '#32CD32', 'type' => 'netflow' },\" /var/nfsen/etc/nfsen.conf && /var/nfsen/bin/nfsen reconfig && echo '✓ Done'"
```

That's it! No compose edits, no rebuild. The port is already exposed by the range.

---

## Notes

- **Port range 2055–3055** is pre-exposed — no need to touch `docker-compose.yml` for new routers
- Config changes persist as long as the container exists (via Docker volumes)
- Rebuilding the image resets nfsen.conf — re-run the add commands
- NetFlow data in Docker volumes survives rebuilds

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

If you used `docker exec` to delete (Method B), run:

```bash
# Use the force-restart script (no rebuild needed)
bash nfsen-force-restart.sh
```

Or manually:
```bash
# Force-kill stale daemon if socket is broken
docker exec exon-nfsen bash -c "\
  pkill -f nfsend 2>/dev/null; sleep 1; \
  rm -f /var/nfsen/var/run/nfsen.comm /var/nfsen/var/run/nfsend.pid; \
  /var/nfsen/bin/nfsen reconfig; \
  /var/nfsen/bin/nfsen start\
"
```

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
| Web UI shows `nfsend connect() error` | `bash nfsen-force-restart.sh` or `docker exec exon-nfsen /var/nfsen/bin/nfsen stop && docker exec exon-nfsen /var/nfsen/bin/nfsen start` |
| Config changes not showing after reconfig | `docker exec exon-nfsen /var/nfsen/bin/nfsen stop && docker exec exon-nfsen /var/nfsen/bin/nfsen start` (full restart if reconfig didn't work) |
| `Error: missing parameter 'IP' for multiple sources collector` | Add `'IP' => '0.0.0.0'` to all existing sources manually. See [IP Requirement](#-important-ip-requirement-for-multiple-sources) |
| `Reconfig: No changes found!` | The source name doesn't exist — check with `docker exec exon-nfsen grep -A 20 '%sources' /var/nfsen/etc/nfsen.conf` |
| `Command 'sed' not found` | Your host lacks `sed`. Use the **Docker exec** method instead (no host tools needed). See [Remove a source](#remove-a-source) |
| Port already in use | Change Apache port in `docker-compose.yml` |
| Can't access port 8070 | Check firewall: `ufw allow 8070/tcp` |
| NfSen not starting | `docker logs exon-nfsen --tail 30` and then `bash nfsen-force-restart.sh` |
| `nfsend connect() error` after disk full | Socket is dead. Run `bash nfsen-force-restart.sh` to force-kill and restart |
