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

nfsen_reconfig() {
    docker exec exon-nfsen /var/nfsen/bin/nfsen reconfig 2>&1 | grep -v 'redefined\|sockaddr_in6\|setlogsock\|Invalid argument' | tail -3
}

nfsen_restart() {
    docker exec exon-nfsen /var/nfsen/bin/nfsen restart 2>&1 | grep -v 'redefined\|sockaddr_in6\|setlogsock\|Invalid argument' | head -5
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

    # Use heredoc passed via stdin to avoid quoting issues
    docker exec -i exon-nfsen bash << 'SCRIPT'
NAME="'"$NAME"'"
PORT="'"$PORT"'"
IP="'"$IP"'"
COLOR="'"$COLOR"'"
CONF="/var/nfsen/etc/nfsen.conf"

# Check if already exists
if grep -q "'$NAME' =>" "$CONF"; then
    echo "Source '$NAME' already exists. Skipping."
    exit 0
fi

# Build source line
LINE="    '${NAME}' => { 'port' => '${PORT}', 'col' => '${COLOR}', 'type' => 'netflow' }"
[ -n "$IP" ] && LINE="    '${NAME}' => { 'port' => '${PORT}', 'col' => '${COLOR}', 'type' => 'netflow', 'IP' => '${IP}' }"

# Insert before the closing ); using awk
awk -v l="$LINE" '/^\);$/ { print l ","; print; next } { print }' "$CONF" > "${CONF}.tmp" && mv "${CONF}.tmp" "$CONF"
echo "OK"
SCRIPT

    local RESULT=$?
    if [ $RESULT -eq 0 ]; then
        echo -e "${GREEN}✓ Added source '${NAME}'${NC}"
        echo -e "${CYAN}Reconfiguring NfSen...${NC}"
        nfsen_reconfig
        echo -e "${CYAN}Restarting NfSen...${NC}"
        nfsen_restart
    else
        echo -e "${RED}✗ Failed to add source '${NAME}'${NC}"
    fi
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

    docker exec -i exon-nfsen bash << 'SCRIPT'
NAME="'"$NAME"'"
CONF="/var/nfsen/etc/nfsen.conf"

if ! grep -q "'$NAME' =>" "$CONF" 2>/dev/null; then
    echo "Source '$NAME' not found."
    exit 1
fi

grep -v "'$NAME' =>" "$CONF" > "${CONF}.tmp" && mv "${CONF}.tmp" "$CONF"
echo "OK"
SCRIPT

    local RESULT=$?
    if [ $RESULT -eq 0 ]; then
        echo -e "${GREEN}✓ Removed source '${NAME}'${NC}"
        echo -e "${CYAN}Reconfiguring NfSen...${NC}"
        nfsen_reconfig
        echo -e "${CYAN}Restarting NfSen...${NC}"
        nfsen_restart
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
    echo -e "${CYAN}Reconfiguring NfSen...${NC}"
    nfsen_reconfig
}

# ============================================================================
# COMMAND: restart
# ============================================================================
cmd_restart() {
    check_running
    echo -e "${CYAN}Restarting NfSen...${NC}"
    nfsen_restart
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
