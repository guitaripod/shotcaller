#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: install-gsc.sh <iw4x game dir>" >&2
  exit 2
}

[ $# -eq 1 ] || usage
GAME_DIR="$1"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../gsc" && pwd)"

[ -d "$GAME_DIR/userraw" ] || { echo "no userraw directory in $GAME_DIR" >&2; exit 1; }
[ -f "$GAME_DIR/userraw/z_svr_bots.iwd" ] || { echo "Bot Warfare (z_svr_bots.iwd) is not installed in $GAME_DIR/userraw" >&2; exit 1; }

mkdir -p "$GAME_DIR/userraw/scripts/mp" "$GAME_DIR/userraw/maps/mp/shotcaller"
install -m 644 "$SRC/scripts/mp/shotcaller.gsc" "$GAME_DIR/userraw/scripts/mp/shotcaller.gsc"
install -m 644 "$SRC"/maps/mp/shotcaller/*.gsc "$GAME_DIR/userraw/maps/mp/shotcaller/"
mkdir -p "$GAME_DIR/userraw/scriptdata/shotcaller"

echo "installed shotcaller GSC into $GAME_DIR/userraw"
