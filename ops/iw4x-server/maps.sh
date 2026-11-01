#!/usr/bin/env bash
set -euo pipefail

# Prints a server rotation string with every multiplayer map that has both a map zone and a loadscreen zone in a game directory.
rotation() {
  local game_dir="$1"
  local gametype="${2:-war}"
  find "$game_dir/zone" "$game_dir/main" -iname 'mp_*.ff' 2>/dev/null \
    | sed 's#.*/##; s/\.ff$//' | sort -u > /dev/shm/shotcaller-maps.$$
  grep -E '_load$' /dev/shm/shotcaller-maps.$$ | sed 's/_load$//' | while read -r map; do
    grep -qx "$map" /dev/shm/shotcaller-maps.$$ && printf 'gametype %s map %s ' "$gametype" "$map"
  done
  rm -f /dev/shm/shotcaller-maps.$$
}

rotation "${1:?usage: maps.sh <game dir> [gametype]}" "${2:-war}" | sed 's/ $//'
echo
