#!/bin/sh
# Runs every minute via cron. Scans the system log for blocked LAN→isolated-network
# connection attempts and sends ntfy push notifications for new ones.
#
# Installed automatically by install.sh when NOTIFY_URL is set.

BASE_DIR=/etc/extra-networks
CHECKPOINT=${BASE_DIR}/log-checkpoint
SEEN_FILE=${BASE_DIR}/notified-attempts
TMPLOG=${BASE_DIR}/log-scan.tmp

# Determine repo directory from the stored config
REPO_DIR=$(awk -F= '/^REPO_DIR/ { print $2 }' "${BASE_DIR}/config" 2>/dev/null)

# Count total log lines; reset checkpoint if the log was cleared (reboot)
total=$(logread 2>/dev/null | wc -l)
last=$(cat "$CHECKPOINT" 2>/dev/null || echo 0)
[ "$total" -lt "$last" ] && last=0
echo "$total" > "$CHECKPOINT"
[ "$total" -le "$last" ] && exit 0

# Extract only new lines from this run
new=$(( total - last ))
logread 2>/dev/null | tail -"$new" | grep 'EXTNET-LAN2' > "$TMPLOG" || true

[ -s "$TMPLOG" ] || { rm -f "$TMPLOG"; exit 0; }

while IFS= read -r line; do
    iface=$(echo "$line" | grep -o 'EXTNET-LAN2[^: ]*' | sed 's/EXTNET-LAN2//')
    [ -z "$iface" ] && continue

    conf="${BASE_DIR}/${iface}-notify.conf"
    [ -f "$conf" ] || continue
    unset NOTIFY_URL SUBNET IFACE_NAME
    . "$conf"
    [ -z "${NOTIFY_URL:-}" ] && continue

    src=$(echo "$line" | grep -o 'SRC=[^ ]*' | head -1 | cut -d= -f2)
    dst=$(echo "$line" | grep -o 'DST=[^ ]*' | head -1 | cut -d= -f2)
    proto=$(echo "$line" | grep -o 'PROTO=[^ ]*' | head -1 | cut -d= -f2 | tr '[:upper:]' '[:lower:]')
    port=$(echo "$line" | grep -o 'DPT=[^ ]*' | head -1 | cut -d= -f2)

    [ -z "$src" ] || [ -z "$dst" ] || [ -z "$proto" ] || [ -z "$port" ] && continue

    key="${iface}:${src}:${dst}:${proto}:${port}"
    grep -qxF "$key" "$SEEN_FILE" 2>/dev/null && continue
    printf '%s\n' "$key" >> "$SEEN_FILE"

    # Keep seen file bounded
    if [ "$(wc -l < "$SEEN_FILE" 2>/dev/null)" -gt 500 ]; then
        tail -400 "$SEEN_FILE" > "${SEEN_FILE}.tmp" && mv "${SEEN_FILE}.tmp" "$SEEN_FILE"
    fi

    # Resolve names from DHCP leases
    src_name=$(awk -v ip="$src" '$3==ip { print $4; exit }' /tmp/dhcp.leases 2>/dev/null)
    dst_name=$(awk -v ip="$dst" '$3==ip { print $4; exit }' /tmp/dhcp.leases 2>/dev/null)
    src_label=$([ -n "$src_name" ] && echo "${src_name} (${src})" || echo "$src")
    dst_label=$([ -n "$dst_name" ] && echo "${dst_name} (${dst})" || echo "$dst")

    allow_cmd=""
    [ -n "$REPO_DIR" ] && \
        allow_cmd="sh ${REPO_DIR}/tools/allow-service.sh ${iface} ${dst} ${proto} ${port} 24h"

    curl -sf -X POST "$NOTIFY_URL" \
        -H "Title: Access request — ${iface}" \
        -H "Priority: default" \
        -H "Tags: lock" \
        -d "${src_label} → ${dst_label}:${port}/${proto}

To allow for 24h, run on router:
${allow_cmd}" >/dev/null &

done < "$TMPLOG"

rm -f "$TMPLOG"
