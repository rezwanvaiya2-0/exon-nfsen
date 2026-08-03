#!/bin/bash
# =============================================================================
# Exon-NfSen installer — shows the credit banner + a build confirmation popup
# BEFORE starting the Docker build, then runs the normal compose command.
#
# Usage (on your VPS, inside the exon-nfsen folder):
#     sudo ./install.sh                 # same as: docker compose up -d --build
#     sudo ./install.sh up -d           # plain start, no rebuild
#
# What you see:  credit banner (min 5 seconds) → popup with countdown →
#                press ENTER to continue now, or CTRL+C to cancel the build.
#
# >>> EDIT THIS BLOCK: change the popup text and timing below. <<<
# =============================================================================

# How many seconds the popup stays before the build auto-continues (min 5)
POPUP_SECONDS=10

POPUP_TITLE="NfSen Docker Build - Confirmation"

POPUP_MESSAGE=(
    "This will build and install the NfSen NetFlow Analyzer container."
    ""
    "Press CTRL+C to cancel this build / installation."
    "Press ENTER to continue now."
)

# =============================================================================
# Show the banner + popup
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Credit banner box (no pause - the countdown below provides the wait time)
bash "$SCRIPT_DIR/banner.sh"

echo
echo "================================================================"
echo "   $POPUP_TITLE"
echo "================================================================"
for line in "${POPUP_MESSAGE[@]}"; do
    echo "   $line"
done
echo "================================================================"
echo

# =============================================================================
# Countdown: ENTER continues immediately, CTRL+C cancels, timeout continues.
# =============================================================================
ENTERED=0
for (( i = POPUP_SECONDS; i > 0; i-- )); do
    printf "\r   Starting in %2d seconds... (ENTER to continue / CTRL+C to cancel)  " "$i"
    if read -t 1 -n 1 -r -s; then
        ENTERED=1
        break
    fi
done
printf "\r%-80s\n" ""
if [ "$ENTERED" = "1" ]; then
    echo "   ENTER pressed - continuing now."
else
    echo "   Timeout - continuing automatically."
fi
echo

# =============================================================================
# Run the real compose command (default: up -d --build)
# =============================================================================
if [ "$#" -eq 0 ]; then
    set -- up -d --build
fi

if docker compose version >/dev/null 2>&1; then
    DOCKER_CMD="docker compose"
else
    DOCKER_CMD="docker-compose"
fi

echo "[INFO] Running: $DOCKER_CMD $*"
echo
exec $DOCKER_CMD "$@"
