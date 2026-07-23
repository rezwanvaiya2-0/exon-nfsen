#!/bin/bash
# =============================================================================
# NfSen Source Management Script
# Uses docker cp to avoid quoting issues and hanging
# Shows live step-by-step progress
# =============================================================================

NFSEN_BASEDIR="/var/nfsen"
NFSEN_CONF="${NFSEN_BASEDIR}/etc/nfsen.conf"
TMP_CONF="/tmp/nfsen_sources.conf"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

step() {
    echo -e "\n${BLUE}[$(date '+%H:%M:%S')]${NC} ${CYAN}▶ $1${NC}"
}

ok() {
    echo -e "${GREEN}  ✓ $1${NC}"
}

warn() {
    echo -e "${YELLOW}  ⚠ $1${NC}"
}

fail() {
    echo -e "${RED}  ✗ $1${NC}"
}

cmd() {
    echo -e "  ${YELLOW}\$ $1${NC}"
}

spinner() {
    local PID=$1
    local MSG=$2
    local SPIN="/-\\|"
    local i=0
    while kill -0 "$PID" 2>/dev/null; do
        printf "\r  ${CYAN}%s${NC} ${MSG}..." "${SPIN:$i:1}"
        i=$(( (i+1) % 4 ))
        sleep 0.3
    done
    printf "\r  ${GREEN}✓${NC} ${MSG}... done    \n"
}

check_running() {
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q exon-nfsen; then
        fail "Container 'exon-nfsen' not running"
        exit 1
    fi
}

# Copy config out, edit (cmd must write to stdout), copy back
edit_config() {
    step "1/3: Copying config file from container"
    cmd "docker cp exon-nfsen:$NFSEN_CONF $TMP_CONF"
    docker cp exon-nfsen:"$NFSEN_CONF" "$TMP_CONF" 2>/dev/null || { fail "Failed to copy config from container"; return 1; }
    ok "Config copied to $TMP_CONF"

    step "2/3: Editing config file"
    local EDIT_CMD=("$@")
    echo -e "  ${YELLOW}\$ ${EDIT_CMD[0]} ${EDIT_CMD[1]} ...${NC}"
    "$@" "$TMP_CONF" > "${TMP_CONF}.new" || { fail "Edit failed"; rm -f "$TMP_CONF"; return 1; }
    mv "${TMP_CONF}.new" "$TMP_CONF"
    ok "Config edited successfully"

    step "3/3: Copying config back to container"
    cmd "docker cp $TMP_CONF exon-nfsen:$NFSEN_CONF"
    docker cp "$TMP_CONF" exon-nfsen:"$NFSEN_CONF" || { fail "Failed to copy config back"; return 1; }
    rm -f "$TMP_CONF"
    ok "Config copied back to container"
}

timeout_exec() {
    local TIMEOUT=$1
    shift
    local DESC="$1"
    shift
    cmd "docker exec exon-nfsen $@ (timeout: ${TIMEOUT}s)"
    timeout $TIMEOUT docker exec exon-nfsen "$@" 2>&1 | grep -v 'redefined\|sockaddr_in6\|setlogsock\|Invalid argument' | tail -5 &
    local PID=$!
    spinner $PID "$DESC"
    wait $PID
    local RC=$?
    [ $RC -eq 124 ] && warn "Command timed out after ${TIMEOUT}s - continuing"
    [ $RC -eq 0 ] && ok "$DESC"
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
            *) fail "Unknown: $1"; exit 1 ;;
        esac
    done
    [ -z "$NAME" ] && { fail "--name required"; exit 1; }

    echo -e "\n${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${CYAN}  ADDING NETFLOW SOURCE${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo -e "  Name:   ${YELLOW}$NAME${NC}"
    echo -e "  Port:   ${YELLOW}$PORT${NC}"
    echo -e "  IP:     ${YELLOW}${IP:-localhost}${NC}"
    echo -e "  Color:  ${YELLOW}$COLOR${NC}"

    check_running
    echo ""

    # Step 1-3: Edit config via docker cp
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
        fail "Failed to add source to config"
        return 1
    fi
    ok "Source '$NAME' added to nfsen.conf"

    # Step 4: Reconfigure
    echo ""
    step "4/5: Reconfiguring NfSen daemon"
    timeout_exec 20 "Reconfiguring" /var/nfsen/bin/nfsen reconfig

    # Step 5: Restart
    echo ""
    step "5/5: Restarting NfSen daemon"
    timeout_exec 15 "Restarting" /var/nfsen/bin/nfsen restart

    # Final status
    echo ""
    echo -e "${CYAN}───────────────────────────────────────${NC}"
    echo -e "${GREEN}  ✓ Source '${NAME}' fully added!${NC}"
    echo -e "${CYAN}───────────────────────────────────────${NC}"
    echo ""
    docker exec exon-nfsen /var/nfsen/bin/nfsen status 2>&1 | grep -E 'version|running|Collector|nfsen daemon|pid' | grep -v grep || true
}

# ============================================================================
# COMMAND: list
# ============================================================================
cmd_list() {
    check_running
    echo -e "\n${CYAN}Configured sources:${NC}"
    echo -e "${CYAN}────────────────${NC}"
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
    [ -z "$NAME" ] && { fail "--name required"; exit 1; }

    echo -e "\n${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${CYAN}  REMOVING NETFLOW SOURCE${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo -e "  Name: ${YELLOW}$NAME${NC}"

    check_running
    echo ""

    # Edit config to remove source
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
        ok "Source '$NAME' removed from config"

        echo ""
        step "Reconfiguring NfSen"
        timeout_exec 20 "Reconfiguring" /var/nfsen/bin/nfsen reconfig

        echo ""
        step "Restarting NfSen"
        timeout_exec 15 "Restarting" /var/nfsen/bin/nfsen restart

        echo ""
        echo -e "${GREEN}  ✓ Source '${NAME}' fully removed!${NC}"
    else
        fail "Source '$NAME' not found in config"
    fi
}

# ============================================================================
# COMMAND: status
# ============================================================================
cmd_status() {
    check_running
    echo -e "\n${CYAN}NfSen Status:${NC}"
    echo -e "${CYAN}─────────────${NC}"
    docker exec exon-nfsen bash -c "/var/nfsen/bin/nfsen status 2>&1 | grep -E 'version|running|Collector|nfsen daemon|pid'"
    echo ""
    docker exec exon-nfsen bash -c "netstat -tulpn 2>/dev/null | grep nfcapd | awk '{print \$4}' | head -5 || echo 'no nfcapd listeners'"
}

# ============================================================================
# COMMAND: reconfig
# ============================================================================
cmd_reconfig() {
    check_running
    echo -e "\n${CYAN}Reconfiguring NfSen...${NC}"
    timeout_exec 20 "Reconfiguring" /var/nfsen/bin/nfsen reconfig
    ok "Done"
}

# ============================================================================
# COMMAND: restart
# ============================================================================
cmd_restart() {
    check_running
    echo -e "\n${CYAN}Restarting NfSen...${NC}"
    timeout_exec 15 "Restarting" /var/nfsen/bin/nfsen restart
    ok "Done"
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
