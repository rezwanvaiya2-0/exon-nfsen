#!/bin/bash
# =============================================================================
# Exonhost / Rezwan credit banner.
# Prints a boxed "popup" message so the docker build step shows only
# `RUN /usr/local/bin/exonhost-banner.sh 3` instead of raw echo commands.
#
# Usage:
#   banner.sh            print the popup (no pause)
#   banner.sh <seconds>  print the popup, then pause for <seconds> so it stays
#                        visible during `docker compose build`
# =============================================================================

W=60   # inner width (top/bottom border = W dashes, text field = W-2)

box_top()    { printf '╔'; printf '═%.0s' $(seq 1 $W); printf '╗\n'; }
box_bottom() { printf '╚'; printf '═%.0s' $(seq 1 $W); printf '╝\n'; }
box_empty()  { printf '║'; printf ' %.0s' $(seq 1 $W); printf '║\n'; }
box_line()   { printf '║ %-*s ║\n' $((W - 2)) "$1"; }

echo ""
box_top
box_empty
box_line "  Exonhost - The Best Hosting Provider"
box_line "      in Bangladesh"
box_empty
box_line "  This project was created by Rezwan"
box_line "  Facebook: https://web.facebook.com/rezwanvaiya"
box_empty
box_line "  Made during HSC exam - keep prayer for me"
box_line "  for the result. Good luck!"
box_empty
box_bottom
echo ""

# Optional pause so the popup stays on screen during the docker build
if [ -n "${1:-}" ] && [ "${1}" -gt 0 ] 2>/dev/null; then
    sleep "${1}"
fi
