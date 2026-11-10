#!/usr/bin/env bash
set -euo pipefail

BRIDGE="iw4xbr0"
TAP="iw4x0"
SUBNET="10.44.0.0/24"
HOST_IP="10.44.0.1"
GUEST_IP="10.44.0.2"
GAME_PORT="${VM_GAME_PORT:-28961}"
MODEL_PORT="${VM_LLM_PORT:-8081}"
TABLE="iw4x"

usage() {
  cat >&2 <<EOF
usage: net.sh <command>
  plan     print the bridge, the tap and the nftables rules, for reading
  up       create them and load the rules (needs root)
  down     remove them (needs root)
  status   show the links and the rules as they are now
  unit     print the system service that brings them back at boot
environment: VM_GAME_PORT (default $GAME_PORT), VM_LLM_PORT (default $MODEL_PORT)
EOF
  exit 2
}

# The guest gets its own address on a private bridge with no uplink port, so nothing on this machine or the LAN
# is reachable from it: outbound goes through the host as NAT to the internet, and the one host service it may
# use is the model. Players arrive on the game port and are forwarded to the guest with their real addresses.
ruleset() {
  cat <<EOF
table inet $TABLE {
  chain input {
    type filter hook input priority filter; policy accept;
    iifname "$TAP" ct state established,related accept
    iifname "$TAP" ip daddr $HOST_IP tcp dport $MODEL_PORT accept
    iifname "$TAP" drop
  }

  chain forward {
    type filter hook forward priority filter; policy accept;
    iifname "$TAP" ct state established,related accept
    iifname "$TAP" ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16, 100.64.0.0/10 } drop
    iifname "$TAP" drop
    oifname "$TAP" ct state established,related accept
    oifname "$TAP" accept
  }

  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    ip saddr $SUBNET oifname != "$BRIDGE" masquerade
  }

  chain prerouting {
    type nat hook prerouting priority dstnat; policy accept;
    iifname != { "lo", "$TAP" } udp dport $GAME_PORT dnat ip to $GUEST_IP:$GAME_PORT
  }
}
EOF
}

# Creates the bridge and the tap qemu can open, then loads the rules after checking them.
up() {
  [ "$(id -u)" = 0 ] || { echo "net.sh up needs root: sudo $0 up" >&2; exit 1; }

  ip link show "$BRIDGE" >/dev/null 2>&1 || ip link add "$BRIDGE" type bridge
  ip addr replace "$HOST_IP/24" dev "$BRIDGE"
  ip link set "$BRIDGE" up

  if ! ip link show "$TAP" >/dev/null 2>&1; then
    ip tuntap add dev "$TAP" mode tap user "${SUDO_USER:-$(id -un)}"
  fi

  ip link set "$TAP" master "$BRIDGE"
  ip link set "$TAP" up
  sysctl -qw net.ipv4.ip_forward=1

  ruleset | nft --check -f -
  nft list table inet "$TABLE" >/dev/null 2>&1 && nft delete table inet "$TABLE"
  ruleset | nft -f -
  echo "guest network: $BRIDGE $HOST_IP/24, tap $TAP, guest $GUEST_IP, game port $GAME_PORT"
}

# Removes the rules and the tap; the bridge goes too when nothing else is on it.
down() {
  [ "$(id -u)" = 0 ] || { echo "net.sh down needs root: sudo $0 down" >&2; exit 1; }

  nft list table inet "$TABLE" >/dev/null 2>&1 && nft delete table inet "$TABLE"

  if ip link show "$TAP" >/dev/null 2>&1; then
    ip link set "$TAP" down
    ip link delete "$TAP"
  fi

  if ip link show "$BRIDGE" >/dev/null 2>&1; then
    ip link set "$BRIDGE" down
    ip link delete "$BRIDGE"
  fi

  echo "guest network removed"
}

# Shows what the guest network looks like right now.
status() {
  ip link show "$BRIDGE" 2>/dev/null | head -2 || echo "$BRIDGE: missing"
  ip link show "$TAP" 2>/dev/null | head -2 || echo "$TAP: missing"

  if nft list table inet "$TABLE" >/dev/null 2>&1; then
    nft list table inet "$TABLE"
  else
    echo "rules: not loaded"
  fi
}

# Prints a system service that rebuilds all of it at boot.
unit() {
  cat <<EOF
[Unit]
Description=IW4x guest network: private bridge, tap and the nftables guard
After=network-online.target nftables.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/net.sh up
ExecStop=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/net.sh down

[Install]
WantedBy=multi-user.target
EOF
}

case "${1:-}" in
  plan) ruleset ;;
  up) up ;;
  down) down ;;
  status) status ;;
  unit) unit ;;
  *) usage ;;
esac
