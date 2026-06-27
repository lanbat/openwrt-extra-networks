#!/bin/sh
# Allow LAN devices to reach a specific service on an isolated network.
# The rule is temporary and auto-removed via cron when the duration expires.
#
# Usage:
#   sh allow-service.sh <network> <guest-ip> <proto> <port> <duration>
#   sh allow-service.sh remove <rule-name>
#   sh allow-service.sh list
#
# Duration: 1h, 6h, 24h, 2d, 7d, 30d
#
# Examples:
#   sh allow-service.sh guest 192.168.3.105 tcp 22 24h
#   sh allow-service.sh guest 192.168.3.105 tcp 80 7d
#   sh allow-service.sh remove allow_lan_guest_192_168_3_105_22_tcp
#   sh allow-service.sh list

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── remove ────────────────────────────────────────────────────────────────────

if [ "${1:-}" = remove ]; then
    [ -z "${2:-}" ] && { echo "Usage: sh allow-service.sh remove <rule-name>"; exit 1; }
    RULE="$2"
    uci -q delete firewall."$RULE" || { echo "ERROR: rule not found: $RULE"; exit 1; }
    uci commit firewall
    fw4 reload >/dev/null
    ( crontab -l 2>/dev/null | grep -v "# $RULE" ) | crontab -
    echo "Removed: $RULE"
    exit 0
fi

# ── list ──────────────────────────────────────────────────────────────────────

if [ "${1:-}" = list ]; then
    found=0
    for s in $(uci show firewall 2>/dev/null \
               | awk -F= '/^firewall\.allow_lan_/ { gsub(/\..*/, "", $1); print $1 }' \
               | sort -u | sed 's/^firewall\.//'); do
        name=$(uci -q get firewall."$s".name 2>/dev/null || true)
        dst=$(uci -q get firewall."$s".dest_ip 2>/dev/null || true)
        port=$(uci -q get firewall."$s".dest_port 2>/dev/null || true)
        proto=$(uci -q get firewall."$s".proto 2>/dev/null || true)
        expiry=$(crontab -l 2>/dev/null | awk -v r="$s" '$0 ~ "# "r { print $2":"$1, "on", $4"/"$3; exit }')
        printf '  %-45s  %s:%s/%s  expires %s\n' "${name:-$s}" "${dst:-?}" "${port:-?}" "${proto:-?}" "${expiry:-permanent}"
        found=1
    done
    [ "$found" -eq 0 ] && echo "  No active service allowances."
    exit 0
fi

# ── add ───────────────────────────────────────────────────────────────────────

[ $# -lt 5 ] && {
    echo "Usage: sh allow-service.sh <network> <guest-ip> <proto> <port> <duration>"
    echo "       sh allow-service.sh remove <rule-name>"
    echo "       sh allow-service.sh list"
    exit 1
}

IFACE="$1"
DEST_IP="$2"
PROTO="$3"
PORT="$4"
DURATION="$5"

# Validate proto
case "$PROTO" in tcp|udp) ;; *) echo "ERROR: proto must be tcp or udp"; exit 1 ;; esac

# Parse duration → seconds
case "$DURATION" in
    *d)  _secs=$(( ${DURATION%d} * 86400 )) ;;
    *h)  _secs=$(( ${DURATION%h} * 3600 )) ;;
    *m)  _secs=$(( ${DURATION%m} * 60 )) ;;
    *)   echo "ERROR: duration format: 1h, 6h, 24h, 2d, 7d"; exit 1 ;;
esac

# Build a stable rule name from the parameters
_ip_slug=$(echo "$DEST_IP" | tr '.' '_')
RULE_NAME="allow_lan_${IFACE}_${_ip_slug}_${PORT}_${PROTO}"

# Idempotent: remove existing rule with same name first
uci -q delete firewall."$RULE_NAME" 2>/dev/null || true
( crontab -l 2>/dev/null | grep -v "# $RULE_NAME" ) | crontab -

uci set firewall."$RULE_NAME"=rule
uci set firewall."$RULE_NAME".name="Temp-LAN-to-${IFACE}-${DEST_IP}-${PORT}"
uci set firewall."$RULE_NAME".src=lan
uci set firewall."$RULE_NAME".dest="$IFACE"
uci set firewall."$RULE_NAME".dest_ip="$DEST_IP"
uci set firewall."$RULE_NAME".proto="$PROTO"
uci set firewall."$RULE_NAME".dest_port="$PORT"
uci set firewall."$RULE_NAME".target=ACCEPT
uci commit firewall
fw4 reload >/dev/null

# Schedule removal
_exp=$(( $(date +%s) + _secs ))
_exp_str=$(date -d "@$_exp" '+%M %H %d %m' 2>/dev/null) || {
    _h=$(( $(date +%H | sed 's/^0*//') ))
    _m=$(( $(date +%M | sed 's/^0*//') ))
    _tot_m=$(( _h * 60 + _m + _secs / 60 ))
    _exp_h=$(( (_tot_m / 60) % 24 ))
    _exp_m=$(( _tot_m % 60 ))
    _exp_day=$(date +%d | sed 's/^0//')
    [ $(( _tot_m / 60 )) -ge 24 ] && _exp_day=$(( _exp_day + 1 ))
    _exp_str="$(printf '%02d %02d %02d' "$_exp_m" "$_exp_h" "$_exp_day") $(date +%m)"
}
read -r _cmin _chour _cday _cmon <<EOF
$_exp_str
EOF

CRON_LINE="$_cmin $_chour $_cday $_cmon * sh $SCRIPT_DIR/allow-service.sh remove $RULE_NAME  # $RULE_NAME"
( crontab -l 2>/dev/null; echo "$CRON_LINE" ) | crontab -

_exp_human=$(date -d "@$_exp" '+%H:%M on %d/%m/%Y' 2>/dev/null \
             || printf '%02d:%02d on %s/%s' "$_chour" "$_cmin" "$_cday" "$_cmon")

dst_name=$(awk -v ip="$DEST_IP" '$3==ip { print $4; exit }' /tmp/dhcp.leases 2>/dev/null)
echo "Allowed:  LAN → ${dst_name:+$dst_name (}${DEST_IP}${dst_name:+)}:${PORT}/${PROTO}"
echo "Expires:  $_exp_human"
echo "Remove:   sh $SCRIPT_DIR/allow-service.sh remove $RULE_NAME"
