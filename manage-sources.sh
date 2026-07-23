#!/bin/bash
# =============================================================================
# NfSen Source Management Script
# Uses docker cp to avoid quoting issues and hanging
# =============================================================================

NFSEN_BASEDIR="/var/nfsen"
NFSEN_CONF="${NFSEN_BASEDIR}/etc/nfsen.conf"
TMP_CONF="/tmp/nfsen_sources.conf"

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

# Copy config out, edit (cmd must write to stdout), copy back
edit_config() {
    docker cp exon-nfsen:"$NFSEN_CONF" "$TMP_CONF" 2>/dev/null || return 1
    "$@" "$TMP_CONF" > "${TMP_CONF}.new" || { rm -f "$TMP_CONF"; return 1; }
    mv "${TMP_CONF}.new" "$TMP_CONF"
    docker cp "$TMP_CONF" exon-nfsen:"$NFSEN_CONF" && rm -f "$TMP_CONF"
}

timeout_exec() {
    local TIMEOUT=$1
    shift
    timeout $TIMEOUT docker exec exon-nfsen "$@" 2>&1 | grep -v 'redefined\|sockaddr_in6\|setlogsock\|Invalid argument' | tail -5
    local RC=$?
    [ $RC -eq 124 ] && echo -e "${YELLOW}(command timed out after ${TIMEOUT}s - continuing)${NC}"
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

    echo -e "${CYAN}Adding source '${NAME}'...${NC}"

    # Copy config out, edit with awk, copy back
    # \047 = single quote in awk (avoids bash quoting issues entirely)
    edit_config awk -v name="$NAME" -v port="$PORT" -v ip="$IP" -v color="$COLOR" '
    BEGIN { q = "\047" }
    !added && /^\);$/ {
        line = "    " q name q " => { " q "port" q " => " q port q ""
        if (ip != "") line = line ", " q "IP" q " => " q ip q ""
        line = line ", " q "col" q " => " q color q ", " q "type" q " => " q "netflow" q " },"
        print line
        added = 1
    }
    { print }
    '

    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Failed to edit config${NC}"
        return 1
    fi

    echo -e "${GREEN}✓ Source '${NAME}' added to config${NC}"

    # Reconfigure with timeout
    echo -e "${CYAN}Reconfiguring NfSen (may take 10-15s)...${NC}"
    timeout_exec 20 /var/nfsen/bin/nfsen reconfig
    echo -e "${GREEN}✓ Reconfigured${NC}"

    # Restart with timeout
    echo -e "${CYAN}Restarting NfSen (may take 5-10s)...${NC}"
    timeout_exec 15 /var/nfsen/bin/nfsen restart
    echo -e "${GREEN}✓ Restarted${NC}"

    echo ""
    docker exec exon-nfsen /var/nfsen/bin/nfsen status 2>&1 | grep -E 'version|running|Collector|nfsen daemon|pid' | grep -v grep || true
}

# ============================================================================
# COMMAND: list
# ============================================================================
cmd_list() {
    check_running
    echo -e "${CYAN}Configured sources:${NC}"
    docker exec exon-nfsen bash -c "grep -A 30 '%sources' '$NFSEN_CONF' | grep \"'\" | head -25"
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

    # Copy config out, remove matching line, copy back
    edit_config awk -v name="$NAME" '
    BEGIN { q = "\047"; found = 0 }
    {
        if (index($0, q name q " =>")) { found = 1; next }
        print
    }
    END { if (!found) exit 1 }
    '

    local RC=$?
    if [ $RC -eq 0 ]; then
        echo -e "${GREEN}✓ Source '${NAME}' removed${NC}"
        echo -e "${CYAN}Reconfiguring NfSen...${NC}"
        timeout_exec 20 /var/nfsen/bin/nfsen reconfig
        echo -e "${CYAN}Restarting NfSen...${NC}"
        timeout_exec 15 /var/nfsen/bin/nfsen restart
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
