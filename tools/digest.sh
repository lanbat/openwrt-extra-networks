#!/bin/sh
# Send a daily traffic digest for all isolated networks.
# Installed as a daily cron entry by install.sh when NOTIFY_URL is set.

BASE_DIR=/etc/extra-networks

_nft_bytes() {
    if [ "$2" = in ]; then
        nft list chain inet fw4 "$1" 2>/dev/null \
            | awk '/iifname.*counter/ { for(i=1;i<=NF;i++) if($i=="bytes") { print $(i+1); exit } }'
    else
        nft list chain inet fw4 "$1" 2>/dev/null \
            | awk '/oifname.*counter/ { for(i=1;i<=NF;i++) if($i=="bytes") { print $(i+1); exit } }'
    fi
}

_human() {
    awk -v b="${1:-0}" 'BEGIN {
        if      (b+0 >= 1073741824) printf "%.1f GB", b/1073741824
        else if (b+0 >= 1048576)   printf "%.1f MB", b/1048576
        else if (b+0 >= 1024)      printf "%.1f KB", b/1024
        else                       printf "%d B",     b+0
    }'
}

_router_ip=$(ip addr show br-lan 2>/dev/null | awk '/inet / { split($2,a,"/"); print a[1]; exit }')
_dashboard_url="http://${_router_ip:-192.168.1.1}/cgi-bin/status"

hostname=$(cat /proc/sys/kernel/hostname 2>/dev/null || echo router)

# VPN status line
VPN_CFG=/etc/split-routing/config
_vpn_line=""
if [ -f "$VPN_CFG" ]; then
    unset VPN_IFACE ROUTE_TABLE FWMARK NOTIFY_URL
    . "$VPN_CFG"
    _if_up=no; ip link show "$VPN_IFACE" 2>/dev/null | grep -q "LOWER_UP" && _if_up=yes
    _rule=no;  ip rule show 2>/dev/null | grep -q "lookup ${ROUTE_TABLE}" && _rule=yes
    _rt=no;    ip route show table "$ROUTE_TABLE" 2>/dev/null | grep -q "^default" && _rt=yes
    if [ "$_if_up$_rule$_rt" = yesyesyes ]; then
        _vpn_line="VPN (${VPN_IFACE}): up"
    else
        _vpn_line="VPN (${VPN_IFACE}): DOWN"
    fi
fi

seen_urls=""
for _conf in "${BASE_DIR}"/*-notify.conf; do
    [ -f "$_conf" ] || continue
    unset NOTIFY_URL SUBNET IFACE_NAME BANDWIDTH_THRESHOLD_MB
    . "$_conf"
    [ -z "${NOTIFY_URL:-}" ] && continue

    _iface="$IFACE_NAME"
    [ -z "$_iface" ] && continue

    _rx=$(_nft_bytes "${_iface}_counter" in)
    _tx=$(_nft_bytes "${_iface}_counter" out)
    _dc=$(awk -v s="${SUBNET}." '$3~s{c++} END{print c+0}' /tmp/dhcp.leases 2>/dev/null)
    _rules=$(uci show firewall 2>/dev/null \
        | grep -c "^firewall\.allow_lan_${_iface}" || echo 0)

    _body="Type: Daily digest

${hostname} — $(date '+%a %d %b %Y')${_vpn_line:+
${_vpn_line}}

${_iface}: $_dc device(s) connected
  ↓ $(_human "$_rx")  ↑ $(_human "$_tx")
  ${_rules} active LAN access rule(s)
Dashboard: ${_dashboard_url}"

    case " $seen_urls " in *" $NOTIFY_URL "*) ;;
    *)
        seen_urls="$seen_urls $NOTIFY_URL"
        curl -sf -X POST "$NOTIFY_URL" \
            -H "Title: Daily digest — ${hostname}" \
            -H "Priority: low" \
            -H "Tags: bar_chart" \
            -H "Actions: view, Dashboard, ${_dashboard_url}" \
            -d "$_body" >/dev/null &
        ;;
    esac
done
