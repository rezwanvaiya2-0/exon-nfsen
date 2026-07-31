#!/bin/bash
# =============================================================================
# NfSen Docker Entrypoint
# Following the working guide exactly
# =============================================================================

NFSEN_BASEDIR="/var/nfsen"

echo "========================================================================="
echo "  NfSen 1.3.6p1 + NfDump 1.6.17 Docker Container"
echo "  Ubuntu 20.04"
echo "========================================================================="

# ---------------------------------------------------------------------------
# Configure NetFlow sources from environment variable
# ---------------------------------------------------------------------------
if [ -n "$NFSEN_SOURCES" ] && [ "$NFSEN_SOURCES" != "2055:exonhost_microtik:#0000ff" ]; then
    echo "[INFO] Configuring NetFlow sources from NFSEN_SOURCES env var..."
    SOURCES_STR="%sources = ("
    IFS=',' read -ra SOURCE_ARRAY <<< "$NFSEN_SOURCES"
    for src in "${SOURCE_ARRAY[@]}"; do
        IFS=':' read -ra PARTS <<< "$src"
        PORT="${PARTS[0]}"
        LABEL="${PARTS[1]}"
        COLOR="${PARTS[2]:-#0000ff}"
        IP="${PARTS[3]:-}"
        if [ -n "$IP" ]; then
            SOURCES_STR+="\n    '${LABEL}' => { 'port' => '${PORT}', 'col' => '${COLOR}', 'type' => 'netflow', 'IP' => '${IP}' },"
        else
            SOURCES_STR+="\n    '${LABEL}' => { 'port' => '${PORT}', 'col' => '${COLOR}', 'type' => 'netflow' },"
        fi
    done
    SOURCES_STR+="\n);"
    sed -i "/^%sources/,/^);/c\\${SOURCES_STR}" "${NFSEN_BASEDIR}/etc/nfsen.conf" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Ensure required directories exist
# ---------------------------------------------------------------------------
mkdir -p "${NFSEN_BASEDIR}/var/run"
mkdir -p "${NFSEN_BASEDIR}/profiles-data/live"
mkdir -p "${NFSEN_BASEDIR}/profiles-stat/live"
mkdir -p "${NFSEN_BASEDIR}/profiles-stat"
mkdir -p "${NFSEN_BASEDIR}/var"

# Remove stale socket/PID files
rm -f "${NFSEN_BASEDIR}/var/run/nfsen.comm" 2>/dev/null || true
rm -f "${NFSEN_BASEDIR}/var/run/nfsend.pid" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Fix permissions — FAST on restart
# ---------------------------------------------------------------------------
# A recursive chown/chmod of the whole /var/nfsen used to run on EVERY start.
# Once nfcapd has written flow data (gigabytes of files in the nfsen-data /
# nfsen-stat / nfsen-var volumes), that single pass costs 60s+ of CPU+IO on
# every boot — the main reason container starts got slow. Files inside the
# volumes already keep the correct ownership between restarts, so the full
# recursive pass now runs ONLY on the very first start, when the volumes are
# still empty (and it is instant).
if [ -z "$(ls -A "${NFSEN_BASEDIR}/profiles-data/live" 2>/dev/null)" ]; then
    echo "[INFO] Empty data volume detected (first run) - applying full permissions..."
    chown -R www-data:www-data "${NFSEN_BASEDIR}" 2>/dev/null || true
    chown -R netflow:www-data "${NFSEN_BASEDIR}/profiles-data/live/" 2>/dev/null || true
    chmod -R 775 "${NFSEN_BASEDIR}" 2>/dev/null || true
fi
# New sources added at runtime (nfsen reconfig) create fresh live/<source> dirs
# that may not be netflow-owned yet. Fix them ONE level deep on every start —
# this never recurses into flow data, so it stays instant even on big volumes.
chown netflow:www-data "${NFSEN_BASEDIR}"/profiles-data/live/* 2>/dev/null || true
chown www-data:www-data "${NFSEN_BASEDIR}"/profiles-stat/live/* 2>/dev/null || true
chmod 777 "${NFSEN_BASEDIR}/var/run" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Start Apache (guide: systemctl start apache2)
# ---------------------------------------------------------------------------
echo "[INFO] Starting Apache on port 8070..."
rm -f /var/run/apache2/apache2.pid 2>/dev/null || true
apache2ctl start
echo "[OK] Apache started."

# ---------------------------------------------------------------------------
# Start NfSen (guide: /var/nfsen/bin/nfsen start)
# ---------------------------------------------------------------------------
echo "[INFO] Starting NfSen..."
if [ -f "${NFSEN_BASEDIR}/bin/nfsen" ]; then
    # Run reconfig first to sync config with existing data directories
    ${NFSEN_BASEDIR}/bin/nfsen reconfig 2>&1 || echo "[WARN] nfsen reconfig failed"
    ${NFSEN_BASEDIR}/bin/nfsen start 2>&1 || echo "[WARN] nfsen start failed"
    sleep 2
    if [ -f "${NFSEN_BASEDIR}/var/run/nfsend.pid" ]; then
        echo "[OK] NfSen daemon running."
    else
        echo "[WARN] NfSen daemon not running. Check logs."
    fi
fi

# ---------------------------------------------------------------------------
# Service status
# ---------------------------------------------------------------------------
echo "========================================================================="
echo "  Service Status:"
if pgrep -x apache2 > /dev/null; then
    echo "  ✓ Apache (port 8070) ........ running"
else
    echo "  ✗ Apache .................... NOT running"
fi
if [ -f "${NFSEN_BASEDIR}/var/run/nfsend.pid" ]; then
    echo "  ✓ nfsend .................... running"
else
    echo "  ✗ nfsend .................... NOT running"
fi
echo "========================================================================="
echo "  Web UI: http://<YOUR_IP>:8070/nfsen.php"
echo "========================================================================="

# Trap for graceful shutdown
trap 'echo "Shutting down..."; ${NFSEN_BASEDIR}/bin/nfsen stop 2>/dev/null; apache2ctl stop; exit 0' SIGTERM SIGINT

# Keep container running
exec tail -f /var/log/apache2/error.log \
            /var/log/apache2/access.log \
            "${NFSEN_BASEDIR}/var/nfsen.log" 2>/dev/null || \
    exec sleep infinity
