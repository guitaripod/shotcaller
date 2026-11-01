#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BASE="$HOME/server"
PORT=28961
LLM_PORT="${LLM_PORT:-8081}"
CONFIG="$HOME/.config/shotcaller/shotcaller.toml"

# Installs shotcaller from the wheel pushed with the repo, with no network.
install_shotcaller() {
  python3 -m venv "$HOME/venv"
  "$HOME/venv/bin/pip" install -q --no-index "$HOME"/dist/*.whl
  mkdir -p "$HOME/.local/bin"
  ln -sf "$HOME/venv/bin/shotcaller" "$HOME/.local/bin/shotcaller"
}

# Rewrites the host's shotcaller config for the guest: its own game directory, the model through the forward.
write_shotcaller_config() {
  sed -e "s#^game_dir = .*#game_dir = \"$BASE/game\"#" \
    -e "s#^base_url = .*#base_url = \"http://10.0.2.100:$LLM_PORT/v1\"#" \
    -e "s#^rcon_host = .*#rcon_host = \"127.0.0.1\"#" "$HOME/.config/shotcaller/host.toml" > "$CONFIG"
}

# Points the pushed IW4MAdmin at the guest's log and lets the forwarded admin page in, then installs its unit.
install_iw4madmin() {
  [ -d "$HOME/iw4madmin/app" ] || return 0
  python3 - "$HOME/iw4madmin/app" "$BASE/game/userraw/games_mp.log" <<'PY'
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("setup", Path.home() / "shotcaller/ops/iw4madmin/setup.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.patch(Path(sys.argv[1]), Path(sys.argv[2]), ["127.0.0.1", "::1", "10.0.2.2"])
PY
  mkdir -p "$HOME/.config/systemd/user"
  sed "s#@IW4MADMIN@#$HOME/iw4madmin#g" "$REPO/ops/systemd/iw4madmin.service.in" > "$HOME/.config/systemd/user/iw4madmin.service"
}

# Makes every name lookup fail at once: the guest has no resolver, and a silently dropped query would stall the game server at start.
disable_dns() {
  sudo systemctl disable --now systemd-resolved 2>/dev/null || true
  sudo rm -f /etc/resolv.conf
  echo 'nameserver 127.0.0.1' | sudo tee /etc/resolv.conf >/dev/null
}

install_shotcaller
write_shotcaller_config
"$REPO/ops/iw4x-server/install.sh" "$BASE" "$BASE/game" --port "$PORT" --unit iw4x-server --config "$CONFIG" --existing
install -m 644 "$REPO/systemd/shotcaller.service" "$HOME/.config/systemd/user/shotcaller.service"
install -m 644 "$REPO/ops/systemd/shotcaller-watchdog.service" "$HOME/.config/systemd/user/shotcaller-watchdog.service"
install -m 644 "$REPO/ops/systemd/iw4x-guest-relay.service" "$HOME/.config/systemd/user/iw4x-guest-relay.service"
install_iw4madmin
sed -i "s#^LAN_ONLY=.*#LAN_ONLY=\"1\"#" "$BASE/server.env"
systemctl --user daemon-reload
systemctl --user enable iw4x-server shotcaller shotcaller-watchdog iw4x-guest-relay
[ -f "$HOME/.config/systemd/user/iw4madmin.service" ] && systemctl --user enable iw4madmin
disable_dns
echo "guest installed; it starts the server, shotcaller and IW4MAdmin at boot"
