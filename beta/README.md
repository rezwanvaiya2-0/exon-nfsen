# Beta - Working Dockerized NfSen Project

This is a **complete working copy** of the exon-nfsen Docker project.

Use this as a reference if the main project files are modified or if you need a clean backup of the working Docker setup.

## Quick Start

```bash
cd beta
docker-compose up -d --build
```

Access: `http://<YOUR_IP>:8070/nfsen.php`

## Adding Router Sources

Edit `config/nfsen.conf` and add sources under `%sources`:

```perl
%sources = (
    'exonhost_microtik' => { 'port' => '2055', 'col' => '#0000ff', 'type' => 'netflow' },
    'router1'           => { 'port' => '2055', 'IP' => 'x.x.x.x', 'col' => '#32CD32', 'type' => 'netflow' },
);
```

Then restart NfSen:
```bash
docker exec exon-nfsen /var/nfsen/bin/nfsen restart
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Builds NfSen 1.3.6p1 + NfDump 1.6.17 on Ubuntu 20.04 |
| `docker-compose.yml` | Container setup with volumes and ports (8070 + 2055/udp) |
| `config/nfsen.conf` | NfSen configuration with sources |
| `config/000-default.conf` | Apache virtual host on port 8070 |
| `config/ports.conf` | Apache port configuration |
| `entrypoint.sh` | Starts Apache and NfSen daemon |
| `manage-sources.sh` | Script to add/remove/list router sources |
