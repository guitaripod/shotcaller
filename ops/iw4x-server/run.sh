#!/usr/bin/env bash
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$BASE/server.env"

export WINEPREFIX="$BASE/prefix"
export WINEDEBUG=-all
export WINEDLLOVERRIDES="mscoree,mshtml=d;winemenubuilder.exe=d"
unset DISPLAY WAYLAND_DISPLAY

cd "$BASE/game"
printf 10190 > steam_appid.txt
exec xvfb-run -a -s "-screen 0 1024x768x24 -nolisten tcp" \
  wine ./iw4x.exe -dedicated -stdout \
  +set net_ip 0.0.0.0 +set net_port "$NET_PORT" \
  +set sv_lanOnly "$LAN_ONLY" +exec server.cfg +map_rotate
