#!/bin/sh
# Shared helpers for extra-networks tools. Copied to /etc/extra-networks/_lib.sh by install.sh.
# Source with: . /etc/extra-networks/_lib.sh

# Load NOTIFY_URL (and other fields) from a network's notify.conf.
_load_notify() {
    unset NOTIFY_URL
    _ln_c="/etc/extra-networks/${1}-notify.conf"
    [ -f "$_ln_c" ] && . "$_ln_c"
    true
}

# Send a push notification via ntfy. Requires NOTIFY_URL to be set.
# Usage: _ntfy <title> <priority> <tags> <body> [extra_action]
# extra_action: prepended before the dashboard action, e.g. "view, Approve, URL"
_ntfy() {
    [ -n "${NOTIFY_URL:-}" ] || return 0
    _ntfy_rip=$(ip addr show br-lan 2>/dev/null \
        | awk '/inet / { split($2,a,"/"); print a[1]; exit }')
    _ntfy_dash="http://${_ntfy_rip:-192.168.1.1}/cgi-bin/status"
    curl -sf -X POST "$NOTIFY_URL" \
        -H "Title: $1" \
        -H "Priority: $2" \
        -H "Tags: $3" \
        -H "Actions: ${5:+${5}; }view, Dashboard, ${_ntfy_dash}" \
        -d "$4
Dashboard: ${_ntfy_dash}" >/dev/null &
}
