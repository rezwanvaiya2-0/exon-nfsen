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

## Adding a Router Source (Manual)

Replace `NAME`, `IP`, `PORT`, and `COLOR` with your values:

```bash
docker cp exon-nfsen:/var/nfsen/etc/nfsen.conf /tmp/nfsen.conf && \
sed -i 's/^);$/    '"'"'NAME'"'"' => { '"'"'port'"'"' => '"'"'PORT'"'"', '"'"'IP'"'"' => '"'"'IP_ADDRESS'"'"', '"'"'col'"'"' => '"'"'#COLOR'"'"', '"'"'type'"'"' => '"'"'netflow'"'"' },/' /tmp/nfsen.conf && \
docker cp /tmp/nfsen.conf exon-nfsen:/var/nfsen/etc/nfsen.conf && \
docker exec exon-nfsen /var/nfsen/bin/nfsen restart && \
echo "✓ Done"
```

### Example

```bash
docker cp exon-nfsen:/var/nfsen/etc/nfsen.conf /tmp/nfsen.conf && \
sed -i 's/^);$/    '"'"'router1'"'"' => { '"'"'port'"'"' => '"'"'2055'"'"', '"'"'IP'"'"' => '"'"'103.159.36.253'"'"', '"'"'col'"'"' => '"'"'#32CD32'"'"', '"'"'type'"'"' => '"'"'netflow'"'"' },/' /tmp/nfsen.conf && \
docker cp /tmp/nfsen.conf exon-nfsen:/var/nfsen/etc/nfsen.conf && \
docker exec exon-nfsen /var/nfsen/bin/nfsen restart && \
echo "✓ Done"
```

### Add a source without IP (local NetFlow only)

```bash
docker cp exon-nfsen:/var/nfsen/etc/nfsen.conf /tmp/nfsen.conf && \
sed -i 's/^);$/    '"'"'NAME'"'"' => { '"'"'port'"'"' => '"'"'PORT'"'"', '"'"'col'"'"' => '"'"'#COLOR'"'"', '"'"'type'"'"' => '"'"'netflow'"'"' },/' /tmp/nfsen.conf && \
docker cp /tmp/nfsen.conf exon-nfsen:/var/nfsen/etc/nfsen.conf && \
docker exec exon-nfsen /var/nfsen/bin/nfsen restart && \
echo "✓ Done"
```

## Removing a Router Source

```bash
docker cp exon-nfsen:/var/nfsen/etc/nfsen.conf /tmp/nfsen.conf && \
sed -i "/'ROUTERNAME' =>/d" /tmp/nfsen.conf && \
docker cp /tmp/nfsen.conf exon-nfsen:/var/nfsen/etc/nfsen.conf && \
docker exec exon-nfsen /var/nfsen/bin/nfsen restart && \
echo "✓ Removed"
```

Example with router named `router1`:
```bash
docker cp exon-nfsen:/var/nfsen/etc/nfsen.conf /tmp/nfsen.conf && \
sed -i "/'router1' =>/d" /tmp/nfsen.conf && \
docker cp /tmp/nfsen.conf exon-nfsen:/var/nfsen/etc/nfsen.conf && \
docker exec exon-nfsen /var/nfsen/bin/nfsen restart && \
echo "✓ Removed"
```

## Listing All Sources

```bash
docker exec exon-nfsen grep -A 20 '%sources' /var/nfsen/etc/nfsen.conf
```

## Checking NfSen Status

```bash
docker exec exon-nfsen /var/nfsen/bin/nfsen status
```

---

## Port Exposing

If you use a port other than `2055`, update `docker-compose.yml`:

```yaml
ports:
  - "8070:8070"
  - "2055:2055/udp"
  - "2056:2056/udp"   # Add this for each new port
```

Then restart:
```bash
docker-compose down && docker-compose up -d
```

---

## Important Notes

- **Config changes persist** as long as the container exists
- **Re-running `docker-compose build`** will reset the config — re-run the add commands after a rebuild
- **Data in volumes** (NetFlow data, stats, logs) survives rebuilds

## Troubleshooting

| Problem | Fix |
|---|---|
| Web UI shows `nfsend connect() error` | Run: `docker exec exon-nfsen /var/nfsen/bin/nfsen restart` |
| Port already in use | Change Apache port in `docker-compose.yml` |
| Can't access port 8070 | Check firewall: `ufw allow 8070/tcp` |
| NfSen not starting | Check logs: `docker logs exon-nfsen --tail 30` |
| Need to add multiple routers | Run the `Adding a Router Source` command again with different values |
