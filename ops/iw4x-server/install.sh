#!/usr/bin/env bash
set -euo pipefail

OPS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$(cd "$OPS/.." && pwd)"

usage() {
  echo "usage: install.sh <server base dir> <iw4x game dir> [--port 28961] [--name hostname] [--unit iw4x-server] [--config shotcaller.toml]" >&2
  exit 2
}

[ $# -ge 2 ] || usage
BASE="$1"
STEAM_GAME_DIR="$2"
shift 2
PORT=28961
NAME="^2TDM ^7Bots and friends"
UNIT=iw4x-server
SHOTCALLER_CONFIG="$HOME/.config/shotcaller/shotcaller.toml"
while [ $# -gt 0 ]; do
  case "$1" in
    --port) PORT="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --unit) UNIT="$2"; shift 2 ;;
    --config) SHOTCALLER_CONFIG="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[ -f "$STEAM_GAME_DIR/iw4x.exe" ] || { echo "no iw4x.exe in $STEAM_GAME_DIR" >&2; exit 1; }
[ -f "$STEAM_GAME_DIR/userraw/z_svr_bots.iwd" ] || { echo "Bot Warfare (userraw/z_svr_bots.iwd) is missing from $STEAM_GAME_DIR" >&2; exit 1; }

# Fills a template, replacing every @NAME@ with the matching shell variable.
render() {
  sed -e "s#@BASE@#$BASE#g" -e "s#@PORT@#$PORT#g" -e "s#@UNIT@#$UNIT#g" -e "s#@HOSTNAME@#$NAME#g" \
    -e "s#@MOTD@#Team Deathmatch against bots, humans welcome.#g" -e "s#@STEAM_GAME_DIR@#$STEAM_GAME_DIR#g" \
    -e "s#@SHOTCALLER_CONFIG@#$SHOTCALLER_CONFIG#g" -e "s#@ROTATION@#$ROTATION#g" -e "s#@POOL@#$POOL#g" "$1"
}

# Copies the game install without the player's own profile and files that belong to a client.
copy_game() {
  mkdir -p "$BASE/game" "$BASE/home"
  rsync -a --exclude=/players/ --exclude=/steam_appid.txt --exclude=/zone-conversion.log \
    --exclude=/userraw/logs/ --exclude=/userraw/demos/ "$STEAM_GAME_DIR/" "$BASE/game/"
}

# Creates the Wine prefix the server runs in, headless.
make_prefix() {
  WINEPREFIX="$BASE/prefix" WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=d;winemenubuilder.exe=d" \
    xvfb-run -a wineboot --init >/dev/null 2>&1 || true
  WINEPREFIX="$BASE/prefix" wineserver -w || true
}

# Prints the map ids of a rotation, space separated, which is the pool the map vote offers.
pool_of() {
  printf '%s\n' "$1" | grep -o 'map [a-z0-9_]*' | sed 's/^map //' | paste -sd' '
}

# Writes the config and a fresh random rcon password that is never printed.
write_config() {
  ROTATION="$("$OPS/iw4x-server/maps.sh" "$BASE/game")"
  POOL="$(pool_of "$ROTATION")"
  render "$OPS/iw4x-server/server.cfg.template" > "$BASE/game/userraw/server.cfg"
  if [ ! -f "$BASE/game/userraw/secrets.cfg" ]; then
    (umask 077; printf 'set rcon_password "%s"\n' "$(openssl rand -hex 16)" > "$BASE/game/userraw/secrets.cfg")
  fi
  render "$OPS/iw4x-server/server.env.template" > "$BASE/server.env"
}

# Installs the scripts and the systemd units, rendered for this base directory.
install_units() {
  install -m 755 "$OPS/iw4x-server/run.sh" "$OPS/iw4x-server/update.sh" "$BASE/"
  mkdir -p "$HOME/.config/systemd/user"
  render "$OPS/systemd/iw4x-server.service.in" > "$HOME/.config/systemd/user/$UNIT.service"
  render "$OPS/systemd/iw4x-update.service.in" > "$HOME/.config/systemd/user/$UNIT-update.service"
  install -m 644 "$OPS/systemd/iw4x-update.timer" "$HOME/.config/systemd/user/$UNIT-update.timer"
  systemctl --user daemon-reload
}

mkdir -p "$BASE"
copy_game
make_prefix
"$REPO/scripts/install-gsc.sh" "$BASE/game"
write_config
install_units
echo "installed $UNIT in $BASE on UDP $PORT, LAN only until LAN_ONLY=0 in $BASE/server.env"
echo "start it with: systemctl --user enable --now $UNIT; update timer: systemctl --user enable --now $UNIT-update.timer"
