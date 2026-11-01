#!/usr/bin/env bash
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$BASE/server.env"
SHOTCALLER_BIN="${SHOTCALLER_BIN:-shotcaller}"

EXCLUDES=(
  --exclude=/players/
  --exclude=/steam_appid.txt
  --exclude=/zone-conversion.log
  --exclude=/userraw/server.cfg
  --exclude=/userraw/secrets.cfg
  --exclude=/userraw/games_mp.log
  --exclude=/userraw/scriptdata/
  --exclude=/userraw/logs/
  --exclude=/userraw/demos/
  --exclude=/userraw/scripts/mp/shotcaller.gsc
  --exclude=/userraw/scripts/_customcallbacks.gsc
  --exclude=/userraw/maps/mp/shotcaller/
)

# Prints the files the Steam install has that the server copy lacks or has different, one per line.
pending_changes() {
  rsync -a --itemize-changes --dry-run "${EXCLUDES[@]}" "$STEAM_GAME_DIR/" "$BASE/game/" | grep -v '^\.d' || true
}

# Prints how many humans are on the server, or a large number when it cannot be asked.
humans_online() {
  "$SHOTCALLER_BIN" -c "$SHOTCALLER_CONFIG" players 2>/dev/null || echo 99
}

changes="$(pending_changes)"
if [ -z "$changes" ]; then
  echo "server copy is up to date"
  exit 0
fi

echo "$(printf '%s\n' "$changes" | wc -l) files differ from $STEAM_GAME_DIR"
humans="$(humans_online)"
if [ "$humans" != "0" ] && [ "${FORCE:-0}" != "1" ]; then
  echo "$humans humans online: update postponed until the server is empty"
  exit 0
fi

rsync -a "${EXCLUDES[@]}" "$STEAM_GAME_DIR/" "$BASE/game/"
systemctl --user restart "$UNIT"
echo "updated and restarted $UNIT"
