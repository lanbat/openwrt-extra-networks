#!/bin/sh
# Push an alert when VPN (split-routing) status changes (up ↔ down).
# Runs every 5 minutes via cron. Installed by install.sh when NOTIFY_URL is set.
# Reads VPN config from /etc/split-routing/config; exits silently if absent.

VPN_CFG=/etc/split-routing/config
[ -f "$VPN_CFG" ] || exit 0

BASE_DIR=/etc/extra-networks
STATE_FILE="${BASE_DIR}/vpn-state"

unset VPN_IFACE ROUTE_TABLE FWMARK NOTIFY_URL
. "$VPN_CFG"

[ -z "${VPN_IFACE:-}" ] && exit 0

# Fall back to the first extra-networks NOTIFY_URL if the VPN config doesn't set one
if [ -z "${NOTIFY_URL:-}" ]; then
    for _conf in "${BASE_DIR}"/*-notify.conf; do
        [ -f "$_conf" ] || continue
        unset NOTIFY_URL
        . "$_conf"
        [ -n "${NOTIFY_URL:-}" ] && break
    done
fi
[ -z "${NOTIFY_URL:-}" ] && exit 0

_if_up=no; ip link show "$VPN_IFACE" 2>/dev/null | grep -q "LOWER_UP" && _if_up=yes
_rule=no;  ip rule show 2>/dev/null | grep -q "lookup ${ROUTE_TABLE:-}" && _rule=yes
_rt=no;    ip route show table "${ROUTE_TABLE:-}" 2>/dev/null | grep -q "^default" && _rt=yes

[ "$_if_up$_rule$_rt" = yesyesyes ] && _state=up || _state=down

_last=$(cat "$STATE_FILE" 2>/dev/null || echo "")
[ "$_state" = "$_last" ] && exit 0
printf '%s\n' "$_state" > "$STATE_FILE"

_router_ip=$(ip addr show br-lan 2>/dev/null | awk '/inet / { split($2,a,"/"); print a[1]; exit }')
_dashboard_url="http://${_router_ip:-192.168.1.1}/cgi-bin/status"

if [ "$_state" = up ]; then
    curl -sf -X POST "$NOTIFY_URL" \
        -H "Title: VPN up — ${VPN_IFACE}" \
        -H "Priority: default" \
        -H "Tags: white_check_mark" \
        -H "Actions: view, Dashboard, ${_dashboard_url}" \
        -d "Type: VPN status

VPN (${VPN_IFACE}) came back up.
Dashboard: ${_dashboard_url}" >/dev/null &
else
    curl -sf -X POST "$NOTIFY_URL" \
        -H "Title: VPN down — ${VPN_IFACE}" \
        -H "Priority: high" \
        -H "Tags: warning" \
        -H "Actions: view, Dashboard, ${_dashboard_url}" \
        -d "Type: VPN status

VPN (${VPN_IFACE}) went down. Check the connection.
Dashboard: ${_dashboard_url}" >/dev/null &
fi
