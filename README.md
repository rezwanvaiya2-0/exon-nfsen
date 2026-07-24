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
| `Error: missing parameter 'IP' for multiple sources collector` | Add `'IP' => '0.0.0.0'` to all existing sources manually. See [IP Requirement](#-important-ip-requirement-for-multiple-sources) |
| `Reconfig: No changes found!` | The source name doesn't exist — check with `docker exec exon-nfsen grep -A 20 '%sources' /var/nfsen/etc/nfsen.conf` |
| `Command 'sed' not found` | Your host lacks `sed`. Use the **Docker exec** method instead (no host tools needed). See [Remove a source](#remove-a-source) |
| Port already in use | Change Apache port in `docker-compose.yml` |
| Can't access port 8070 | Check firewall: `ufw allow 8070/tcp` |
| NfSen not starting | `docker logs exon-nfsen --tail 30` |
