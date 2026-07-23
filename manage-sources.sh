#!/bin/bash
# =============================================================================
# NfSen Source Management Script
# Use this script to add, list, and remove NetFlow sources
# =============================================================================

NFSEN_BASEDIR="/var/nfsen"
NFSEN_CONF="${NFSEN_BASEDIR}/etc/nfsen.conf"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

check_running() {
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q exon-nfsen; then
        echo -e "${RED}Container 'exon-nfsen' not running.${NC}"
        exit 1
    fi
}

timeout_exec() {
    local TIMEOUT=$1
    shift
    timeout $TIMEOUT docker exec exon-nfsen "$@" 2>&1 | grep -v 'redefined\|sockaddr_in6\|setlogsock\|Invalid argument' | tail -5
    local RC=$?
    if [ $RC -eq 124 ]; then
        echo -e "${YELLOW}(command timed out after ${TIMEOUT}s - continuing)${NC}"
    fi
    return 0
}

# ============================================================================
# COMMAND: add
# ============================================================================
cmd_add() {
    local NAME="" PORT="2055" IP="" COLOR="#0000ff"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name) NAME="$2"; shift 2 ;;
            --port) PORT="$2"; shift 2 ;;
            --ip) IP="$2"; shift 2 ;;
            --color) COLOR="$2"; shift 2 ;;
            *) echo -e "${RED}Unknown: $1${NC}"; exit 1 ;;
        esac
    done
    [ -z "$NAME" ] && { echo -e "${RED}--name required${NC}"; exit 1; }
    check_running

    # Add source to config (fast - < 1 second)
    echo -e "${CYAN}Adding source '${NAME}'...${NC}"
    docker exec -i \
        -e NFSEN_NAME="$NAME" \
        -e NFSEN_PORT="$PORT" \
        -e NFSEN_IP="$IP" \
        -e NFSEN_COLOR="$COLOR" \
        exon-nfsen bash << 'SCRIPT'
CONF="/var/nfsen/etc/nfsen.conf"
if grep -q "'$NFSEN_NAME' =>" "$CONF" 2>/dev/null; then
    echo "EXISTS"
    exit 0
fi
LINE="    '${NFSEN_NAME}' => { 'port' => '${NFSEN_PORT}', 'col' => '${NFSEN_COLOR}', 'type' => 'netflow' }"
[ -n "$NFSEN_IP" ] && LINE="    '${NFSEN_NAME}' => { 'port' => '${NFSEN_PORT}', 'col' => '${NFSEN_COLOR}', 'type' => 'netflow', 'IP' => '${NFSEN_IP}' }"
awk -v l="$LINE" '!found && /^\);$/ { print l ","; print; found=1; next } { print }' "$CONF" > "${CONF}.tmp" && mv "${CONF}.tmp" "$CONF"
echo "DONE"
SCRIPT

    local RESULT=$?
    echo -e "${GREEN}✓ Source '${NAME}' added${NC}"

    # Reconfigure (may take 10-15 seconds)
    echo -e "${CYAN}Reconfiguring NfSen (may take 10-15s)...${NC}"
    timeout_exec 20 /var/nfsen/bin/nfsen reconfig
    echo -e "${GREEN}✓ Reconfigured${NC}"

    # Restart (may take 5-10 seconds)
    echo -e "${CYAN}Restarting NfSen (may take 5-10s)...${NC}"
    timeout_exec 15 /var/nfsen/bin/nfsen restart
    echo -e "${GREEN}✓ Restarted${NC}"

    # Show final status
    echo ""
    docker exec exon-nfsen /var/nfsen/bin/nfsen status 2>&1 | grep -E 'version|running|Collector|nfsen daemon|pid' | grep -v grep || true
}

# ============================================================================
# COMMAND: list
# ============================================================================
cmd_list() {
    check_running
    echo -e "${CYAN}Configured sources:${NC}"
    docker exec exon-nfsen bash -c "grep -A 30 '%sources' '${NFSEN_CONF}' | grep \"'\" | head -25"
}

# ============================================================================
# COMMAND: remove
# ============================================================================
cmd_remove() {
    local NAME=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name) NAME="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    [ -z "$NAME" ] && { echo -e "${RED}--name required${NC}"; exit 1; }
    check_running

    echo -e "${CYAN}Removing source '${NAME}'...${NC}"
    docker exec -i -e NFSEN_NAME="$NAME" exon-nfsen bash << 'SCRIPT'
CONF="/var/nfsen/etc/nfsen.conf"
if ! grep -q "'$NFSEN_NAME' =>" "$CONF" 2>/dev/null; then echo "NOTFOUND"; exit 1; fi
grep -v "'$NFSEN_NAME' =>" "$CONF" > "${CONF}.tmp" && mv "${CONF}.tmp" "$CONF"
echo "REMOVED"
SCRIPT

    local RESULT=$?
    if [ $RESULT -eq 0 ]; then
        echo -e "${GREEN}✓ Source '${NAME}' removed${NC}"
        echo -e "${CYAN}Reconfiguring NfSen...${NC}"
        timeout_exec 20 /var/nfsen/bin/nfsen reconfig
        echo -e "${CYAN}Restarting NfSen...${NC}"
        timeout_exec 15 /var/nfsen/bin/nfsen restart
        docker exec exon-nfsen /var/nfsen/bin/nfsen status 2>&1 | grep -E 'version|running|Collector|nfsen daemon|pid' | grep -v grep || true
    else
        echo -e "${RED}✗ Source '${NAME}' not found${NC}"
    fi
}

# ============================================================================
# COMMAND: status
# ============================================================================
cmd_status() {
    check_running
    echo -e "${CYAN}NfSen Status:${NC}"
    docker exec exon-nfsen bash -c "/var/nfsen/bin/nfsen status 2>&1 | grep -E 'version|running|Collector|nfsen daemon|pid'"
    echo ""
    docker exec exon-nfsen bash -c "netstat -tulpn 2>/dev/null | grep nfcapd | awk '{print \$4}' | head -5 || echo 'no nfcapd listeners'"
}

# ============================================================================
# COMMAND: reconfig
# ============================================================================
cmd_reconfig() {
    check_running
    echo -e "${CYAN}Reconfiguring NfSen (may take 10-15s)...${NC}"
    timeout_exec 20 /var/nfsen/bin/nfsen reconfig
    echo -e "${GREEN}✓ Done${NC}"
}

# ============================================================================
# COMMAND: restart
# ============================================================================
cmd_restart() {
    check_running
    echo -e "${CYAN}Restarting NfSen (may take 5-10s)...${NC}"
    timeout_exec 15 /var/nfsen/bin/nfsen restart
    echo -e "${GREEN}✓ Done${NC}"
}

# ============================================================================
# Main
# ============================================================================
case "$1" in
    add) shift; cmd_add "$@" ;;
    remove) shift; cmd_remove "$@" ;;
    list) cmd_list ;;
    status) cmd_status ;;
    reconfig) cmd_reconfig ;;
    restart) cmd_restart ;;
    help|--help|-h)
        echo "Usage:"
        echo "  ./manage-sources.sh add --name RouterName [--port 2055] [--ip x.x.x.x] [--color #0000ff]"
        echo "  ./manage-sources.sh remove --name RouterName"
        echo "  ./manage-sources.sh list"
        echo "  ./manage-sources.sh status"
        echo "  ./manage-sources.sh reconfig"
        echo "  ./manage-sources.sh restart"
        ;;
    *) echo -e "${RED}Usage: $0 [add|remove|list|status|reconfig|restart|help]${NC}"; exit 1 ;;
esac
