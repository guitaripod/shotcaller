#!/usr/bin/env bash
set -euo pipefail

GUEST_IP="${VM_GUEST_IP:-10.44.0.2}"
HOST_IP="${VM_HOST_IP:-10.44.0.1}"
DNS="${VM_GUEST_DNS:-9.9.9.9}"
LLM_PORT="${VM_LLM_PORT:-8081}"
BASE="$HOME/server"
CONFIG="$HOME/.config/shotcaller/shotcaller.toml"

# The guest's one interface, whatever the cloud image called it.
iface() {
  ip -o link show | awk -F': ' '$2 != "lo" { print $2; exit }'
}

# Gives the guest a fixed address on the private bridge, ahead of the DHCP file cloud-init writes at boot.
write_network() {
  sudo tee "/etc/systemd/network/05-iw4x.network" >/dev/null <<EOF
[Match]
Name=$(iface)

[Network]
Address=$GUEST_IP/24
Gateway=$HOST_IP
DNS=$DNS
EOF
  sudo tee /etc/cloud/cloud.cfg.d/99-iw4x-network.cfg >/dev/null <<'EOF'
network: {config: disabled}
EOF
}

# The guest has a resolver now, so stop the fail-fast stub that keeps the game from hanging on a dropped query.
write_resolver() {
  sudo rm -f /etc/resolv.conf
  printf 'nameserver %s\noptions timeout:1 attempts:1\n' "$DNS" | sudo tee /etc/resolv.conf >/dev/null
}

# Points the sidecar at the host over the bridge instead of the old QEMU forward.
rewrite_sidecar() {
  [ -f "$CONFIG" ] || return 0
  sed -i "s#^base_url = .*#base_url = \"http://$HOST_IP:$LLM_PORT/v1\"#" "$CONFIG"
}

# Lets the host reach the IW4MAdmin page over the bridge, and drops the forward address it no longer uses.
allow_admin() {
  [ -d "$HOME/iw4madmin/app" ] || return 0
  python3 - "$HOME/iw4madmin/app" <<'PY'
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("setup", Path.home() / "shotcaller/ops/iw4madmin/setup.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.patch(Path(sys.argv[1]), Path.home() / "server/game/userraw/games_mp.log", ["127.0.0.1", "::1", "10.44.0.1"])
PY
}

# Leaves the tunnel relay switched off: on the bridge the game port is forwarded straight to the guest.
drop_relay() {
  systemctl --user disable --now iw4x-guest-relay 2>/dev/null || true
}

# Lists the server publicly now that it can reach the nodes.
list_publicly() {
  sed -i 's#^LAN_ONLY=.*#LAN_ONLY="0"#' "$BASE/server.env"
}

write_network
write_resolver
rewrite_sidecar
allow_admin
drop_relay
list_publicly
echo "guest prepared for $GUEST_IP on the bridge"
