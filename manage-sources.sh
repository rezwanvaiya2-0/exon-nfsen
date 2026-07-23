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

docker_exec() {
    if [ -f /.dockerenv ]; then
        "$@"
    else
        docker exec exon-nfsen "$@"
    fi
}

check_running() {
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q exon-nfsen; then
        echo -e "${RED}Container 'exon-nfsen' not running.${NC}"
        exit 1
    fi
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
    
    local ENTRY="    '${NAME}' => { 'port' => '${PORT}', 'col' => '${COLOR}', 'type' => 'netflow' }"
    [ -n "$IP" ] && ENTRY="    '${NAME}' => { 'port' => '${PORT}', 'col' => '${COLOR}', 'type' => 'netflow', 'IP' => '${IP}' }"
    
    docker_exec bash -c "sed -i '/^);/i ${ENTRY},' '${NFSEN_CONF}'"
    echo -e "${GREEN}✓ Added source '${NAME}'${NC}"
    docker_exec "${NFSEN_BASEDIR}/bin/nfsen" reconfig 2>/dev/null || true
    docker_exec "${NFSEN_BASEDIR}/bin/nfsen" restart 2>/dev/null || true
}

# ============================================================================
# COMMAND: list
# ============================================================================
cmd_list() {
    check_running
    echo -e "${CYAN}Sources:${NC}"
    docker_exec bash -c "grep -A 20 '%sources' '${NFSEN_CONF}' | head -25"
}

# ============================================================================
# COMMAND: remove
# ============================================================================
cmd_remove() {
    local NAME=""
    while [[ $# -gt 0 ]]; do case "$1" in --name) NAME="$2"; shift 2;; *) shift;; esac; done
    [ -z "$NAME" ] && { echo -e "${RED}--name required${NC}"; exit 1; }
    check_running
    docker_exec bash -c "sed -i \"/'${NAME}' =>/d\" '${NFSEN_CONF}'"
    echo -e "${GREEN}✓ Removed source '${NAME}'${NC}"
    docker_exec "${NFSEN_BASEDIR}/bin/nfsen" reconfig 2>/dev/null || true
    docker_exec "${NFSEN_BASEDIR}/bin/nfsen" restart 2>/dev/null || true
}

# ============================================================================
# COMMAND: status
# ============================================================================
cmd_status() {
    check_running
    echo -e "${CYAN}NfSen Status:${NC}"
    docker_exec bash -c "${NFSEN_BASEDIR}/bin/nfsen status 2>/dev/null || echo 'stopped'"
    docker_exec bash -c "netstat -tulpn 2>/dev/null | grep nfcapd || echo 'no nfcapd listeners'"
}

# ============================================================================
# COMMAND: reconfig
# ============================================================================
cmd_reconfig() {
    check_running
    docker_exec "${NFSEN_BASEDIR}/bin/nfsen" reconfig
    docker_exec "${NFSEN_BASEDIR}/bin/nfsen" restart
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
    help|--help|-h)
        echo "Usage:"
        echo "  ./manage-sources.sh add --name RouterName [--port 2055] [--ip x.x.x.x] [--color #0000ff]"
        echo "  ./manage-sources.sh remove --name RouterName"
        echo "  ./manage-sources.sh list"
        echo "  ./manage-sources.sh status"
        echo "  ./manage-sources.sh reconfig"
        ;;
    *) echo -e "${RED}Usage: $0 [add|remove|list|status|reconfig|help]${NC}"; exit 1 ;;
esac
