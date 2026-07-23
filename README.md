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

## Router Source Management

### Add a router source

```bash
# No IP required (NetFlow from localhost):
./manage-sources.sh add --name RouterName --port 2055 --color #00ff00

# With specific router IP:
./manage-sources.sh add --name RouterName --port 2055 --ip 192.168.1.1 --color #00ff00
```

| Flag | Description | Default |
|---|---|---|
| `--name` | Router name (appears in web UI) | **Required** |
| `--port` | UDP port for NetFlow data | `2055` |
| `--ip` | Router IP address (optional) | (blank) |
| `--color` | Graph line color (hex) | `#0000ff` |

**Important:** If you use a port other than `2055`, you must also expose it in `docker-compose.yml`:

```yaml
ports:
  - "8070:8070"
  - "2055:2055/udp"
  - "2056:2056/udp"   # Add this line for each new port
```

Then restart the container:
```bash
docker-compose down && docker-compose up -d
```

### Add multiple routers at once

```bash
./manage-sources.sh add --name mikrotik --port 2055 --ip 10.0.0.1 --color #0000ff
./manage-sources.sh add --name cisco-core --port 2056 --ip 10.0.0.2 --color #00ff00
./manage-sources.sh add --name huawei-edge --port 2057 --ip 10.0.0.3 --color #ff0000
```

### List all sources

```bash
./manage-sources.sh list
```

### Remove a source

```bash
./manage-sources.sh remove --name RouterName
```

### Reconfigure after manual edits

If you edit `nfsen.conf` manually inside the container:

```bash
# Edit the config (vi is built-in; install nano: apt-get install -y nano)
docker exec -it exon-nfsen vi /var/nfsen/etc/nfsen.conf

# Apply changes
docker exec exon-nfsen /var/nfsen/bin/nfsen reconfig
docker exec exon-nfsen /var/nfsen/bin/nfsen restart
```

### Restart NfSen

```bash
docker exec exon-nfsen /var/nfsen/bin/nfsen restart
```

### Check NfSen status

```bash
./manage-sources.sh status
```

---

## Examples

### Add two routers with different ports

```bash
./manage-sources.sh add --name uplink-1 --port 2055 --ip 192.168.1.1 --color #0000ff
./manage-sources.sh add --name uplink-2 --port 2056 --ip 192.168.1.2 --color #00ff00
```

### Replace an old router with a new one

```bash
./manage-sources.sh remove --name old-router
./manage-sources.sh add --name new-router --port 2055 --ip 10.10.10.1 --color #ff8800
docker exec exon-nfsen /var/nfsen/bin/nfsen restart
```

---

## Persistence

| Data | Location | Survives restart? | Survives rebuild? |
|---|---|---|---|
| NetFlow data | Docker volume `nfsen-data` | ✅ Yes | ✅ Yes |
| Profile stats | Docker volume `nfsen-stat` | ✅ Yes | ✅ Yes |
| Logs/runtime | Docker volume `nfsen-var` | ✅ Yes | ✅ Yes |
| **Source configs** | Inside container | ✅ Yes | ❌ **No** (re-run `add` commands) |

**Note:** Source configs added via `manage-sources.sh` persist across container restarts and VPS reboots. They are lost only if you rebuild the image (`docker-compose build` or `docker-compose down -v`). After a rebuild, simply re-run your `add` commands.

### Full clean reset

```bash
docker-compose down -v        # Stops container, DELETES all data
docker-compose build --no-cache && docker-compose up -d   # Fresh build
```

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Web UI shows `nfsend connect() error` | Run: `docker exec exon-nfsen /var/nfsen/bin/nfsen restart` |
| Port already in use | Change Apache port in `docker-compose.yml` (e.g., `8080:8070`) |
| Can't access port 8070 | Check firewall: `ufw allow 8070/tcp` |
| NfSen not starting | Check logs: `docker logs exon-nfsen --tail 30` |
| Wrong timezone | Set env var: `TZ=Asia/Dhaka` in `docker-compose.yml` |

---

## LibreNMS Integration

To point LibreNMS to this NfSen instance:

1. In LibreNMS, go to **Device → NetFlow → Add NfSen**
2. Set NfSen URL to: `http://103.187.23.163:8070/nfsen.php`
3. NfSen must be running (check: `docker exec exon-nfsen /var/nfsen/bin/nfsen status`)
