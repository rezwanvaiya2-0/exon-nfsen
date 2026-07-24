# Exon-NfSen - Dockerized NfSen NetFlow Analyzer

**NfSen 1.3.6p1 + NfDump 1.6.17** on Ubuntu 20.04 — fully Dockerized.

## Quick Start

```bash
git clone https://github.com/rezwanvaiya2-0/exon-nfsen.git
cd exon-nfsen
docker-compose up -d --build
```

Access: **http://\<YOUR_IP\>:8070/nfsen.php**

Timezone: **Asia/Dhaka**

---

## ⚠️ First Time Setup: Remove Default Source

The container comes with a **default source** `exonhost_microtik` listening on port **2055**. Before you can add your own routers, you **must remove this default source** first.

> **Why?** Multiple sources cannot share the same port. The default source occupies port 2055, so your new router source on the same port will conflict.

Remove it with this one-liner (works on any host — no `sed` required):

```bash
docker exec exon-nfsen bash -c "sed -i \"/'exonhost_microtik' =>/d\" /var/nfsen/etc/nfsen.conf && /var/nfsen/bin/nfsen reconfig && echo '✓ Removed'"
```

> 💡 This is exactly the command you confirmed works above!

Verify it's gone:
```bash
docker exec exon-nfsen grep -A 5 '%sources' /var/nfsen/etc/nfsen.conf
```

---

## Managing Router Sources (Recommended)

Use the `manage-sources.sh` script to add, remove, and list NetFlow sources reliably:

```bash
chmod +x manage-sources.sh
```

### Adding a Source

```bash
# With IP (for a remote router)
./manage-sources.sh add --name router1 --port 2055 --ip 103.159.36.253 --color '#32CD32'

# Without IP (local NetFlow only - only works as the FIRST/only source)
./manage-sources.sh add --name local_router --port 2055 --color '#0000ff'
```

### Removing a Source

```bash
./manage-sources.sh remove --name router1
```

### Listing All Sources

```bash
./manage-sources.sh list
```

### Checking Status

```bash
./manage-sources.sh status
```

### Reconfig / Restart

```bash
./manage-sources.sh reconfig
./manage-sources.sh restart
```

---

## ⚠️ Important: IP Requirement for Multiple Sources

When you have **more than one source** configured, **NfSen requires ALL sources to have an `IP` field**.

The `manage-sources.sh` script handles this automatically:
- When you add a source **with an IP**, it auto-fills `IP => '0.0.0.0'` on any existing sources that lack it.
- When you add a source **without an IP** and other sources already have IPs, it assigns `IP => '0.0.0.0'` to the new source too.

> **Recommendation:** After the script runs, verify the IPs are correct for your setup:
> ```bash
> docker exec exon-nfsen grep -A 20 '%sources' /var/nfsen/etc/nfsen.conf
> ```
> Then update any auto-filled `0.0.0.0` IPs with the actual source IPs by editing the config directly or re-adding with `--ip`.

---

## Manual Commands (Alternative)

If you prefer raw commands, here are two ways to add/remove sources.

> ⚠️ **Host `sed` may not be installed!** If you get `Command 'sed' not found`, use the **`docker exec` method** instead (no host tools needed).

### Add a source with IP

#### Method 1: Docker exec (recommended — works on any host)

```bash
docker exec exon-nfsen bash -c "sed -i \"/^);$/i\\    'NAME' => { 'port' => '2055', 'IP' => 'IP_ADDRESS', 'col' => '#32CD32', 'type' => 'netflow' },\" /var/nfsen/etc/nfsen.conf && /var/nfsen/bin/nfsen reconfig && echo '✓ Done'"
```

#### Method 2: Docker cp (uses host sed)

```bash
docker cp exon-nfsen:/var/nfsen/etc/nfsen.conf /tmp/nfsen.conf && \
sed -i "/^);$/i\\    'NAME' => { 'port' => '2055', 'IP' => 'IP_ADDRESS', 'col' => '#32CD32', 'type' => 'netflow' }," /tmp/nfsen.conf && \
docker cp /tmp/nfsen.conf exon-nfsen:/var/nfsen/etc/nfsen.conf && \
docker exec exon-nfsen /var/nfsen/bin/nfsen reconfig && \
echo "✓ Done"
```

> ⚠️ **If you have existing sources without IP, this will fail!** You must first add `'IP' => '0.0.0.0'` to all existing sources. Use the `manage-sources.sh` script to avoid this issue.

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

## Port Exposing

If you use a port other than `2055`, update `docker-compose.yml`:

```yaml
ports:
  - "8070:8070"
  - "2055:2055/udp"
  - "2056:2056/udp"
```

Then restart:
```bash
docker-compose down && docker-compose up -d
```

---

## Notes

- Config changes persist as long as the container exists
- Rebuilding the image resets config — re-run the add commands
- NetFlow data in Docker volumes survives rebuilds

## Troubleshooting

| Problem | Fix |
|---|---|
| Web UI shows `nfsend connect() error` | `docker exec exon-nfsen /var/nfsen/bin/nfsen restart` |
| Config changes not showing after reconfig | `docker exec exon-nfsen /var/nfsen/bin/nfsen restart` (full restart if reconfig didn't work) |
| `Error: missing parameter 'IP' for multiple sources collector` | Use `./manage-sources.sh add --name ... --ip ...` (auto-fills missing IPs) |
| `Reconfig: No changes found!` | The source name doesn't exist — check with `./manage-sources.sh list` |
| `Command 'sed' not found` | Your host lacks `sed`. Use the **Docker exec** method instead (no host tools needed). See [Remove a source](#remove-a-source) |
| Port already in use | Change Apache port in `docker-compose.yml` |
| Can't access port 8070 | Check firewall: `ufw allow 8070/tcp` |
| NfSen not starting | `docker logs exon-nfsen --tail 30` |
