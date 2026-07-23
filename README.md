# Exon-NfSen - Dockerized NfSen NetFlow Analyzer

NfSen 1.3.6p1 + NfDump 1.6.17 on Ubuntu 20.04.

## Quick Start

```bash
git clone https://github.com/rezwanvaiya2-0/exon-nfsen.git
cd exon-nfsen
docker-compose up -d --build
```

Access: `http://<YOUR_IP>:8070/nfsen.php`

## Configure Router Sources

Edit `docker-compose.yml`:
```yaml
environment:
  - NFSEN_SOURCES=2055:MikroTik:#0000ff,9995:Cisco:#00ff00:10.0.0.1
```

Or use the management script:
```bash
./manage-sources.sh add --name "MikroTik" --port 2055 --ip 192.168.1.1
```

## Persistence

Data survives restarts via Docker volumes. To reset:
```bash
docker-compose down -v
```
