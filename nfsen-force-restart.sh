#!/bin/bash
# =============================================================================
# NfSen Force Restart — reliable restart even when the socket is dead
#
# When disk fills up, the NfSen communication socket breaks and
# "nfsen stop" fails. This script force-kills the daemon directly,
# cleans up stale files, then starts fresh.
#
# Usage:  bash nfsen-force-restart.sh
#         (works from the host, no rebuild needed)
# =============================================================================

CONTAINER="exon-nfsen"

echo "========================================"
echo "  NfSen Force Restart"
echo "========================================"

# Check container is running
if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "$CONTAINER"; then
    echo "[ERROR] Container '$CONTAINER' is not running!"
    echo "        Start it first: docker start $CONTAINER"
    exit 1
fi

echo "[1/4] Force-stopping any stale nfsend daemon..."
docker exec "$CONTAINER" bash -c "
    pkill -f nfsend 2>/dev/null || true
    sleep 1
    rm -f /var/nfsen/var/run/nfsen.comm /var/nfsen/var/run/nfsend.pid
" && echo "  ✓ Done" || echo "  ✓ Done (no process was running)"

echo "[2/4] Reconfiguring NfSen..."
docker exec "$CONTAINER" /var/nfsen/bin/nfsen reconfig 2>&1 | grep -v 'redefined\|setlogsock' && echo "  ✓ Done" || echo "  ✓ Done"

echo "[3/4] Starting NfSen..."
docker exec "$CONTAINER" /var/nfsen/bin/nfsen start 2>&1 | grep -v 'redefined\|setlogsock' || true

echo "[4/4] Checking status..."
sleep 2
docker exec "$CONTAINER" bash -c "
    if [ -f /var/nfsen/var/run/nfsend.pid ]; then
        echo '  ✓ NfSen daemon is RUNNING (PID: '"\$(cat /var/nfsen/var/run/nfsend.pid)"')'
    else
        echo '  ✗ NfSen daemon is NOT running'
        echo '  Check logs: docker logs exon-nfsen --tail 20'
    fi
"

echo "========================================"
echo "  Done!"
echo "  Web UI: http://<YOUR_IP>:8070/nfsen.php"
echo "========================================"
