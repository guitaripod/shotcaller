#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: install.sh <iw4x game dir> [config path]" >&2
  echo "installs the GSC mod, the shotcaller command and a systemd user unit" >&2
  exit 2
}

[ $# -ge 1 ] || usage
GAME_DIR="$1"
CONFIG="${2:-$HOME/.config/shotcaller/shotcaller.toml}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT/scripts/install-gsc.sh" "$GAME_DIR"

uv tool install --editable --force "$ROOT"
shotcaller --version

mkdir -p "$(dirname "$CONFIG")"
if [ ! -f "$CONFIG" ]; then
  sed "s#/path/to/iw4x/game#$GAME_DIR#" "$ROOT/examples/shotcaller.toml" > "$CONFIG"
  echo "wrote $CONFIG: set rcon_port and model, then run: shotcaller eval"
fi

mkdir -p "$HOME/.config/systemd/user"
install -m 644 "$ROOT/systemd/shotcaller.service" "$HOME/.config/systemd/user/shotcaller.service"
systemctl --user daemon-reload
echo "unit installed; after 'shotcaller eval' passes: systemctl --user enable --now shotcaller"
