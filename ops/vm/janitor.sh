#!/usr/bin/env bash
set -euo pipefail

DIR="${VM_DIR:-/mnt/nvme8tb/iw4x-vm}"
GUEST="${VM_GUEST_IP:-10.44.0.2}"
GAME_PORT="${VM_GAME_PORT:-28961}"
HOST_LAN="${VM_HOST_LAN:-192.168.1.197}"
BACKUP_DIR="${VM_BACKUP_DIR:-/mnt/nvme8tb/iw4x-backup}"
LOG_LIMIT_MB="${VM_LOG_LIMIT_MB:-256}"
KEEP_BACKUPS="${VM_KEEP_BACKUPS:-14}"
STATE="$DIR/janitor.state"
MODE="${1:-run}"

say() {
  printf '%s %s\n' "$(date +%H:%M:%S)" "$*"
}

# Reads one value out of the small state file, or prints nothing.
state_get() {
  [ -f "$STATE" ] || return 0
  sed -n "s/^$1=//p" "$STATE" | head -1
}

# Replaces one value in the state file, keeping the others.
state_set() {
  local tmp="$STATE.tmp" key value

  mkdir -p "$(dirname "$STATE")"
  : > "$tmp"

  for key in fails wan backup restarted; do
    if [ "$key" = "$1" ]; then
      printf '%s=%s\n' "$key" "$2" >> "$tmp"
    else
      value="$(state_get "$key")"
      [ -n "$value" ] && printf '%s=%s\n' "$key" "$value" >> "$tmp"
    fi
  done

  mv "$tmp" "$STATE"
}

# Runs a command in the guest over the bridge address.
guest() {
  ssh -p 22 -i "$DIR/id_ed25519" -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$DIR/known_hosts" \
    -o BatchMode=yes -o ConnectTimeout=5 -o LogLevel=ERROR "iw4x@$GUEST" "$@"
}

# Whether the game answers a status query, which is the cheapest proof that the whole chain is up.
game_up() {
  python3 - "$GUEST" "$GAME_PORT" <<'PY'
import socket, sys
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(2)
s.sendto(b"\xff\xff\xff\xffgetinfo x", (sys.argv[1], int(sys.argv[2])))
try:
    s.recvfrom(65535)
    raise SystemExit(0)
except Exception:
    raise SystemExit(1)
PY
}

# Whether anybody is playing, so maintenance never interrupts a match.
humans() {
  python3 - "$GUEST" "$GAME_PORT" <<'PY'
import re, socket, sys
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(2)
s.sendto(b"\xff\xff\xff\xffgetinfo x", (sys.argv[1], int(sys.argv[2])))
try:
    data, _ = s.recvfrom(65535)
except Exception:
    print(-1)
    raise SystemExit(0)
info = data.decode("latin-1").split("\n")[1]
kv = dict(zip(*[iter(info.split("\\")[1:])] * 2))
print(kv.get("clients", "0"))
PY
}

# Whether the router still forwards the game port to this machine, and the address it hands out.
port_forward() {
  command -v upnpc >/dev/null 2>&1 || return 0

  if ! timeout 20 upnpc -l 2>/dev/null | grep -q "UDP $GAME_PORT->.*:$GAME_PORT"; then
    if [ "$MODE" = run ]; then
      if timeout 20 upnpc -a "$HOST_LAN" "$GAME_PORT" "$GAME_PORT" UDP >/dev/null 2>&1; then
        say "re-added the UDP $GAME_PORT forward after the router lost it"
      else
        say "WARN the router refused the forward for UDP $GAME_PORT"
      fi
    else
      say "WARN the UDP $GAME_PORT forward is missing"
    fi
  fi

  local ip last
  ip="$(timeout 20 upnpc -l 2>/dev/null | sed -n 's/^ExternalIPAddress = //p' | head -1)"
  last="$(state_get wan)"

  if [ -n "$ip" ] && [ "$ip" != "$last" ]; then
    say "WAN address is $ip (was ${last:-unknown})"
    state_set wan "$ip"
  fi
}

# Keeps the guest the size it was planned at, and gives the log room to breathe.
housekeeping() {
  local size players
  size="$(guest 'stat -c %s $HOME/server/game/userraw/games_mp.log 2>/dev/null || echo 0' 2>/dev/null || echo 0)"
  players="$(humans)"

  if [ "${size:-0}" -gt $((LOG_LIMIT_MB * 1024 * 1024)) ] && [ "$players" = 0 ]; then
    if [ "$MODE" = run ]; then
      say "rotating games_mp.log (${size} bytes, nobody playing)"
      guest 'mv -f $HOME/server/game/userraw/games_mp.log $HOME/server/game/userraw/games_mp.log.1; systemctl --user restart iw4x-server' >/dev/null
    else
      say "would rotate games_mp.log (${size} bytes)"
    fi
  fi
}

# Copies what cannot be rebuilt: the admin database, the sidecar's config and journal, the server config.
backup() {
  local today stamp last
  stamp="$(date +%F)"
  today="$BACKUP_DIR/$stamp"
  last="$(state_get backup)"

  [ "$last" = "$stamp" ] && return 0

  if [ "$MODE" != run ]; then
    say "would back up to $today"
    return 0
  fi

  mkdir -p "$today"
  rsync -a -e "ssh -p 22 -i $DIR/id_ed25519 -o UserKnownHostsFile=$DIR/known_hosts -o BatchMode=yes -o LogLevel=ERROR" \
    "iw4x@$GUEST:server/game/userraw/server.cfg" \
    "iw4x@$GUEST:iw4madmin/app/Database/Database.db" \
    "iw4x@$GUEST:.config/shotcaller/shotcaller.toml" \
    "iw4x@$GUEST:server/game/userraw/scriptdata/shotcaller/" \
    "$today/" 2>/dev/null || say "WARN the backup copy failed"

  state_set backup "$stamp"
  say "backed up to $today"

  ls -1dt "$BACKUP_DIR"/*/ 2>/dev/null | tail -n +$((KEEP_BACKUPS + 1)) | while read -r old; do
    rm -rf "$old"
  done
}

# Restarts the VM when the guest stopped answering three runs in a row, with cooldown so it cannot loop.
supervise() {
  local fails last now
  fails="$(state_get fails)"
  last="$(state_get restarted)"

  if game_up; then
    fails=0
  else
    fails=$(( ${fails:-0} + 1 ))
  fi

  state_set fails "$fails"

  if [ "$fails" -ge 3 ]; then
    now="$(date +%s)"

    if [ -z "$last" ] || [ $((now - last)) -gt 900 ]; then
      if [ "$MODE" = run ]; then
        say "guest stopped answering; restarting iw4x-vm"
        systemctl --user restart iw4x-vm
        state_set restarted "$now"
      else
        say "would restart iw4x-vm"
      fi
    fi
  fi
}

# Reports the size of everything the server occupies, for a human reading it.
report() {
  local size players ip
  size="$(guest 'stat -c %s $HOME/server/game/userraw/games_mp.log 2>/dev/null || echo 0' 2>/dev/null || echo 0)"
  players="$(humans)"
  ip="$(timeout 20 upnpc -l 2>/dev/null | sed -n 's/^ExternalIPAddress = //p' | head -1)"

  if ! ip link show "${VM_TAP:-iw4x0}" >/dev/null 2>&1; then
    say "WARN the tap is missing: sudo ops/vm/net.sh up"
  fi

  say "guest $(game_up && echo up || echo DOWN) | humans ${players} | log $(( ${size:-0} / 1024 / 1024 )) MB | wan ${ip:-unknown}"
  guest 'df -h / | tail -1; systemctl --user is-active iw4x-server shotcaller shotcaller-watchdog iw4madmin | tr "\n" " "' 2>/dev/null || true
}

case "$MODE" in
  check) report ;;
  run) port_forward; supervise; housekeeping; backup ;;
  report) report ;;
  *) echo "usage: janitor.sh [run|check]" >&2; exit 2 ;;
esac
