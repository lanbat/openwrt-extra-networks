# openwrt-extra-networks

Manage multiple isolated WiFi networks on OpenWrt from a single script. Each network gets its own subnet, firewall zone, DNS policy, and rate limit — deployed in seconds, no LuCI needed.

Built for households that need more than one level of trust: your own devices, IoT gadgets that shouldn't touch anything, and guests who just need internet.

Works with OpenWrt `fw4` / nftables.

## Networks

| Network | Purpose | DNS | Rate | Allowlist |
|---|---|---|---|---|
| `untrusted` | IoT / misbehaving devices | 1.1.1.3 filtered | 500kbit shared | MAC-based — unlisted devices get nothing |
| `guest` | Visitors | 1.1.1.3 filtered | 10mbit shared / 5mbit per device | none — open to any device |

Each network is a config file. Add a new one by copying an example.

## Features

- **One script, any network** — `sh install.sh configs/guest.conf` deploys a complete isolated network
- **Strict firewall isolation** — each network can reach the internet and nothing else by default
- **WiFi client isolation** — devices on the same network can't reach each other
- **Filtered DNS** — Cloudflare for Families (1.1.1.3) blocks malware and adult content
- **DNS bypass prevention** — port 53 to any unauthorised server is blocked at the firewall
- **Encrypted DNS (DoT)** — optionally route DNS through `https-dns-proxy` for encrypted queries
- **Rate limiting** — aggregate cap + optional per-device cap via nftables; no kernel modules required
- **Port restriction** — limit outbound ports (e.g. web-only guests)
- **MAC allowlist** — for IoT networks: unlisted devices get no lease and are blocked from forwarding
- **LAN → isolated access** — optionally let LAN devices reach isolated devices, never the reverse
- **mDNS reflection** — let guests discover shared services (Chromecast, AirPrint) via avahi
- **Push notifications** — 12 event types via ntfy.sh: new device joined, LAN access request/approval/expiry, allowlist rejection, bandwidth alert, port forwarded/removed, password rotated, daily digest, VPN state change, router reboot
- **Live status dashboard** — web page on the router showing all networks, connected devices with per-device traffic, VPN status, active LAN access rules, and port forwards
- **Traffic counters** — bytes in/out per network since last firewall reload, shown in status
- **Access schedule** — restrict internet to specific hours; auto-blocked outside the window
- **Temporary port forwarding** — expose a LAN host to guests for a fixed time; auto-removed via cron
- **Password rotation** — generate a new key, apply it live, and print a fresh QR code
- **Guest info page** — LAN-accessible HTML page with SSID, password, and QR code
- **WPA3 support** — `sae` for WPA3-only, `sae-mixed` for WPA3+WPA2, `psk+psk2` for legacy
- **Dual-band** — broadcast the same network on both 2.4GHz and 5GHz radios
- **IPv6** — optional DHCPv6 + RA with auto-derived IPv6 DNS
- **No secrets in the repo** — WiFi keys live only in gitignored config files on the router
- **Idempotent installs** — re-running `install.sh` updates an existing network cleanly

## Setup

### 1. Clone onto your router

```sh
cd /root
git clone https://github.com/lanbat/openwrt-extra-networks.git
cd openwrt-extra-networks
```

### 2. Create a config

```sh
cp configs/guest.conf.example configs/guest.conf
vi configs/guest.conf   # set WIFI_KEY, SSID, and anything else
```

### 3. Install

```sh
sh install.sh configs/guest.conf
```

Repeat for each network you want.

## Configuration

Config files live in `configs/` and are gitignored — they never leave the router. Copy an example, fill in `WIFI_KEY`, adjust anything else.

### Required

| Option | Description |
|---|---|
| `WIFI_KEY` | WiFi password (min 8 chars) |
| `IFACE` | UCI interface name — must be unique (e.g. `guest`, `untrusted`) |
| `SSID` | WiFi network name |
| `SUBNET` | First three octets — router gets `.1`, clients `.100`–`.249` (e.g. `192.168.3`) |

### Wireless

| Option | Default | Description |
|---|---|---|
| `RADIO` | `radio0` | `radio0` = 2.4GHz, `radio1` = 5GHz |
| `RADIO_EXTRA` | — | Second radio for dual-band (e.g. `radio1`); leave blank for single-band |
| `ENCRYPTION` | `psk2+psk3` | `sae` = WPA3 only, `sae-mixed` = WPA3+WPA2, `psk+psk2` = WPA2+WPA |
| `ISOLATE` | `yes` | Prevent clients on the same network from reaching each other |

### Network

| Option | Default | Description |
|---|---|---|
| `RATE_LIMIT` | `0` | Aggregate bandwidth cap — `10mbit`, `500kbit`, `0` to disable |
| `RATE_LIMIT_PER_DEVICE` | `0` | Per-device cap; both limits apply simultaneously when set |
| `DNS_SERVER` | `1.1.1.3` | DNS given to clients — `1.1.1.3` filtered, `1.1.1.1` plain |
| `DOT` | `no` | Route DNS through `https-dns-proxy` for encrypted DoT/DoH; requires it to be installed and configured |
| `IPV6` | `no` | Enable IPv6 (DHCPv6 + RA); IPv6 DNS auto-derived from `DNS_SERVER` |
| `ALLOWED_PORTS` | — | Restrict outbound TCP/UDP ports, e.g. `"80 443"`; NTP (123) always allowed |

### Access and isolation

| Option | Default | Description |
|---|---|---|
| `LAN_ACCESS` | `no` | Allow LAN devices to initiate connections to this network (not vice versa) |
| `ALLOWLIST` | `no` | MAC allowlist — only listed devices get a lease or can forward traffic |
| `VLAN_ID` | — | 802.1Q VLAN ID — bridge a tagged wired port into this network alongside WiFi, e.g. `20` |
| `VLAN_TRUNK` | — | Physical interface carrying the VLAN trunk, e.g. `eth0` — required when `VLAN_ID` is set |
| `MDNS` | `no` | Reflect mDNS between LAN and this network; installs avahi-daemon if absent |
| `NOTIFY_URL` | — | ntfy.sh URL — push alert when a new device joins, e.g. `https://ntfy.sh/my-topic` |
| `DEFAULT_DURATION` | `24h` | Pre-selected duration in the approval form (`1h` `6h` `12h` `24h` `2d` `7d` `30d`) |
| `MAX_DURATION` | `30d` | Longest duration available in the approval form — options above this are hidden |
| `REASON_REQUIRED` | `no` | `yes` — approver must enter a reason before access is granted |
| `BANDWIDTH_THRESHOLD_MB` | `0` | Alert when a device transfers this many MB in a session; `0` to disable |

> `ACCESS_HOURS` is set via `tools/access-schedule.sh`, not in the config file.

## Allowlist

When `ALLOWLIST=yes`, only devices listed in `/etc/${IFACE}-allowed-macs` can get a DHCP lease or forward traffic.

Format — one device per line:

```
# mac  ip  description
aa:bb:cc:dd:ee:ff  192.168.2.100  Nest Protect Living Room
11:22:33:44:55:66  192.168.2.101  Nest Protect Bedroom
```

The file lives at `/etc/extra-networks/${IFACE}-allowed-macs`. After editing, apply without restarting:

```sh
ACTION=ifup INTERFACE=untrusted sh /etc/hotplug.d/iface/51-untrusted-macfilter
```

Two-layer enforcement:
1. **DHCP** — dnsmasq ignores DHCP requests from unlisted MACs
2. **nftables** — forwarding from unlisted IPs is dropped even with a manual static IP

## Encrypted DNS (DoT)

When `DOT=yes`, clients are given the router's own IP as their DNS server. Queries go to dnsmasq, which forwards them to `https-dns-proxy` over DoH/DoT — encrypted all the way to the resolver.

External DNS is blocked at the firewall: port 53 to any external server is rejected, and port 853 (DoT bypass) is also blocked. Clients cannot escape.

Requires `https-dns-proxy` to be installed and configured on the router. On this setup it resolves via Mullvad and Quad9.

## mDNS reflection

mDNS multicast packets are confined to a single subnet — a guest on `192.168.3.x` can't discover a Chromecast on `192.168.1.x` because the broadcast stops at the router.

`MDNS=yes` installs and configures `avahi-daemon` to relay mDNS packets between LAN and the isolated network. Guests can then discover and use shared services: Chromecast, AirPrint, game lobbies.

**Note:** avahi reflects all mDNS services, not just specific ones. Guests would see printers, file shares, and other LAN devices that advertise via mDNS. Use `MDNS=yes` only on networks where that level of sharing is intentional.

## Device notifications

Set `NOTIFY_URL` to an [ntfy.sh](https://ntfy.sh) topic URL. Subscribe in the ntfy app on your phone. Each network can have its own topic.

```sh
NOTIFY_URL=https://ntfy.sh/my-unique-topic-name
```

All notifications include a link to the status dashboard. LAN access requests include an **Approve** action button.

| Event | Trigger | Priority |
|---|---|---|
| New device joined | Device gets a DHCP lease | Low |
| LAN access request | LAN device blocked from reaching an isolated device | Default |
| LAN access approved | Access granted via web form or `allow-service.sh` | Default |
| LAN access expired | Temporary rule removed by cron | Low |
| Allowlist rejection | Unlisted device attempts to use the network | High |
| Bandwidth alert | Device exceeds `BANDWIDTH_THRESHOLD_MB` in a session | Default |
| Port forwarded | `expose-port.sh` adds a redirect | Default |
| Port forward removed | Rule expired or `unexpose-port.sh` called | Low |
| Password rotated | `rotate-password.sh` generates a new key | Default |
| Daily digest | Traffic totals and device counts, sent at 08:00 | Low |
| Router reboot | Router comes back online (30s delay) | Low |
| VPN state change | VPN goes down or recovers | High / Default |

### LAN access approval

When a LAN device is blocked from reaching an isolated device, you get a push with an **Approve** button. Tapping it opens a form on the router where you pick how long to allow access and optionally enter a reason. Once submitted, a second push confirms the approval with both devices' IP, MAC, and hostname.

`DEFAULT_DURATION` pre-selects a duration in the form (default `24h`). `MAX_DURATION` hides longer options. Set `REASON_REQUIRED=yes` to make the reason field mandatory — enforced both client-side and server-side.

The approval page (`/cgi-bin/approve-access`) is only reachable from your home LAN — isolated zones have `INPUT=REJECT`.

### Bandwidth alerts

`BANDWIDTH_THRESHOLD_MB` triggers an alert when a device exceeds that many MB in a session. Counters reset on `fw4 reload` or after 24 hours of inactivity. An IP is only alerted once per session.

### Daily digest

Sent every morning at 08:00 with traffic totals (↓/↑), connected device count, and active LAN access rule count for each network. Also includes VPN status if split-routing is configured.

### VPN monitoring

If `/etc/split-routing/config` is present, VPN state is checked every 5 minutes. A high-priority alert fires when the VPN goes down; a default-priority alert fires when it recovers. Uses the `NOTIFY_URL` from the split-routing config if set, otherwise falls back to the first extra-networks topic.

## Status dashboard

When `NOTIFY_URL` is set, a live web dashboard is installed at:

```
http://192.168.1.1/cgi-bin/status
```

The page auto-refreshes every 60 seconds and shows:

- **VPN** — interface and state (up / down / routing fault)
- **Networks** — state, subnet, traffic (↓/↑), connected devices with hostname, IP, MAC, and per-device traffic
- **LAN access rules** — active temporary allowances with expiry time
- **Port forwards** — all active redirects with zone, port, destination, and expiry

Only reachable from LAN — isolated zones have `INPUT=REJECT`.

## VLAN trunk

Set `VLAN_ID` and `VLAN_TRUNK` to bridge a tagged wired port into the network alongside the WiFi SSID. Devices on that VLAN from a managed switch land on the same L2 segment as WiFi clients — same subnet, same firewall rules, same DHCP pool.

```sh
VLAN_ID=20       # tag used on the switch trunk port
VLAN_TRUNK=eth0  # physical interface the trunk arrives on (hardware-specific)
```

The trunk interface name depends on your board — check with `ip link show`. Common values: `eth0`, `eth1`, `lan1`. `install.sh` creates an `8021q` VLAN device (`eth0.20`) and adds it to `br-${IFACE}`; netifd brings it up automatically.

Omit both variables (or leave them blank) for WiFi-only — the feature is entirely opt-in.

## Tools

### Status

```sh
sh tools/status.sh
```

CLI summary of all isolated networks: bridge IP and state, WiFi SSID and encryption, connected clients, DHCP leases, rate limits, traffic counters, access schedule state, port forwards, and LAN access status.

When `NOTIFY_URL` is set, a web dashboard is also available at `http://192.168.1.1/cgi-bin/status` — see [Status dashboard](#status-dashboard).

### Uninstall

```sh
sh tools/uninstall.sh configs/guest.conf
sh tools/uninstall.sh configs/untrusted.conf --purge   # also removes allowed-macs file
```

Removes all UCI sections, nftables files, hotplug scripts, cron entries, and the generated web page for the network.

### QR code

```sh
sh tools/qr.sh configs/guest.conf
```

Prints the WiFi credentials as a QR code in the terminal. Requires `qrencode` (`apk add qrencode`).

### Access schedule

Restrict internet access to specific hours. Enforced via nftables — all forwarding is dropped outside the window. Schedule survives reboots via cron.

```sh
# Restrict guest internet to 8am–11pm
sh tools/access-schedule.sh configs/guest.conf 8-23

# Remove schedule (always on)
sh tools/access-schedule.sh configs/guest.conf always

# Show current schedule and state
sh tools/access-schedule.sh configs/guest.conf status
```

### Allow LAN access to a guest device

When `NOTIFY_URL` is set, blocked LAN→isolated connection attempts trigger a push notification with an **Approve** button. Tapping it opens a browser form on the router. You pick the duration, optionally enter a reason, and submit — the rule is added immediately and removed automatically when it expires. A confirmation push is sent with both devices' IP, MAC, and hostname, plus the duration and reason.

You can also grant access directly from the command line:

```sh
# Allow LAN to reach a guest device on port 22 for 24 hours
sh tools/allow-service.sh guest 192.168.3.105 tcp 22 24h

# List all active temporary allowances
sh tools/allow-service.sh list

# Remove one manually
sh tools/allow-service.sh remove allow_lan_guest_192_168_3_105_22_tcp
```

```
Arguments: <network> <guest-ip> <proto> <port> <duration>

  duration   1h, 6h, 12h, 24h, 2d, 7d, 30d — auto-removed via cron, survives reboots
  proto      tcp or udp
```

Rules are stored in UCI (persist across reboots). If the router reboots after the scheduled removal time has passed, remove the rule manually with `sh tools/allow-service.sh list` then `remove`.

### Expose a port

Forward a specific port from an isolated network to a LAN host — useful for gaming sessions or temporary server access.

```sh
# Permanent
sh tools/expose-port.sh guest 27015 192.168.1.50

# Auto-remove after 2 hours
sh tools/expose-port.sh guest 27015 192.168.1.50 2h

# With protocol and custom name
sh tools/expose-port.sh guest 25565 192.168.1.50 3h tcp minecraft
```

```
Arguments: <src-zone> <port> <dest-ip> [duration] [proto] [name]

  duration   30m, 2h, 1h30m — auto-removed via cron, survives reboots
  proto      tcp, udp, or "tcp udp" (default)
  name       label for the rule (default: expose-<zone>-<port>)
```

Guests connect to the router's zone IP (e.g. `192.168.3.1:27015`) — the router NATs the connection to the LAN host.

### Remove an exposed port

```sh
sh tools/unexpose-port.sh expose-guest-27015

# Or use the custom name
sh tools/unexpose-port.sh minecraft
```

Also cancels any scheduled cron removal.

### Rotate password

Generate a new random password, apply it immediately, and print a QR code.

```sh
sh tools/rotate-password.sh configs/guest.conf
```

Updates the config file in place and reloads wireless. Guests on the old password are disconnected.

### Guest info page

Generate a LAN-accessible webpage with the network name, password, and QR code.

```sh
sh tools/guest-info.sh configs/guest.conf
# → http://192.168.1.1/net/guest.html  (LAN only)
```

The page is served by the router's built-in web server (uhttpd). Isolated network zones have `INPUT=REJECT`, so guests and IoT devices cannot access it — only LAN devices can.

Re-run after rotating the password to update the page.

## Adding a new network

1. Copy an example: `cp configs/guest.conf.example configs/mynetwork.conf`
2. Set `IFACE`, `SSID`, `SUBNET`, `WIFI_KEY` — ensure the subnet doesn't overlap with existing networks
3. Run `sh install.sh configs/mynetwork.conf`

## Notes

- **Rate limiting** uses `nft limit rate` (drop) rather than `tc tbf` — `kmod-sched-core` is not packaged on all platforms. Packets exceeding the cap are dropped rather than queued; for IoT and guest traffic this is acceptable.
- **Traffic counters** reset on `fw4 reload` (which happens on every `install.sh` run). For persistent usage stats, consider `vnstat`.
- **Re-running** `install.sh` on an existing network is safe — it updates all settings cleanly.
- **Wireless sections** are created automatically if they don't exist in UCI. `WIFI_UCI` can be set to reuse a pre-existing section with a different name; omit it for new networks.
