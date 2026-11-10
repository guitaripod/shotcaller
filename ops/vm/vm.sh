#!/usr/bin/env bash
set -euo pipefail

OPS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$(cd "$OPS/.." && pwd)"
DIR="${VM_DIR:-$HOME/iw4x-vm}"
CPUS="${VM_CPUS:-4}"
MEM_MB="${VM_MEM_MB:-4096}"
DISK_GB="${VM_DISK_GB:-60}"
GAME_PORT="${VM_GAME_PORT:-28961}"
SSH_PORT="${VM_SSH_PORT:-2222}"
TUNNEL_PORT="${VM_TUNNEL_PORT:-28962}"
ADMIN_PORT="${VM_ADMIN_PORT:-1624}"
LLM_PORT="${VM_LLM_PORT:-8081}"
SEED_PORT="${VM_SEED_PORT:-8099}"
IMAGE_URL="https://cloud.debian.org/images/cloud/trixie/latest"
IMAGE_NAME="debian-13-genericcloud-amd64.qcow2"

usage() {
  cat >&2 <<EOF
usage: vm.sh <command>
  image                  download and verify the Debian cloud image
  create                 make the disk, the ssh key and the cloud-init seed
  provision <server dir> boot with open network, install packages, push the server and shotcaller, shut down
  install <server dir>   do the install and push step against a guest already booted with the open network
  refresh                push the current code to the running guest and rerun its installer
  run                    boot the isolated production guest in the foreground (what the unit runs)
  args <open|run|tap>    print the qemu arguments for a mode, one per line
  ssh [command]          ssh into the running guest
  stop                   shut the guest down cleanly
  unit [vm|relay]        print the systemd user unit that runs the guest, or the UDP relay in front of it
  relay                  run the host side of the UDP tunnel in the foreground (what the relay unit runs)
  env                    print the server.env lines that make update.sh sync into the guest
environment: VM_DIR (default \$HOME/iw4x-vm), VM_CPUS, VM_MEM_MB, VM_DISK_GB, VM_GAME_PORT, VM_SSH_PORT, VM_ADMIN_PORT, VM_LLM_PORT
EOF
  exit 2
}

# The address the guest answers on: the host forward while it is cut off, its bridge address once it is on the tap.
guest_host() {
  if [ "${VM_NET:-run}" = tap ]; then
    echo "${VM_GUEST_IP:-10.44.0.2}"
  else
    echo "127.0.0.1"
  fi
}

# The ssh port: the host forward in closed mode, the guest's own 22 on the bridge.
guest_port() {
  if [ "${VM_NET:-run}" = tap ]; then
    echo 22
  else
    echo "$SSH_PORT"
  fi
}

# Runs a command in the guest over ssh, using the key made by create.
guest() {
  ssh -p "$(guest_port)" -i "$DIR/id_ed25519" -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$DIR/known_hosts" \
    -o BatchMode=yes -o ConnectTimeout=5 -o LogLevel=ERROR "iw4x@$(guest_host)" "$@"
}

# Copies files to the guest with rsync over the same ssh connection settings.
push() {
  rsync -a -e "ssh -p $(guest_port) -i $DIR/id_ed25519 -o UserKnownHostsFile=$DIR/known_hosts -o BatchMode=yes -o LogLevel=ERROR" "$@"
}

# Prints the arguments both modes share: KVM, resources, the disk and no display, one per line.
common_args() {
  printf '%s\n' -machine q35,accel=kvm -cpu host -smp "$CPUS" -m "$MEM_MB" -display none \
    -serial "file:$DIR/console.log" -name iw4x -pidfile "$DIR/qemu.pid" \
    -drive "file=$DIR/disk.qcow2,if=virtio,format=qcow2,discard=unmap" -device virtio-rng-pci
}

# Prints the provisioning network: outbound access through the host, ssh on host loopback only.
open_net() {
  printf '%s\n' -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22" -device virtio-net-pci,netdev=n0
}

# Prints the production network: restrict=on cuts the guest off from the host, the LAN and the internet,
# leaving only the forwards named here: the game port in, ssh and the admin page on host loopback, and
# the model server out through one socat per connection.
closed_net() {
  local forwards="hostfwd=tcp:127.0.0.1:$SSH_PORT-:22,hostfwd=tcp:127.0.0.1:$TUNNEL_PORT-:28962,hostfwd=tcp:127.0.0.1:$ADMIN_PORT-:1624"
  forwards="$forwards,guestfwd=tcp:10.0.2.100:$LLM_PORT-cmd:socat - TCP:127.0.0.1:$LLM_PORT"
  printf '%s\n' -netdev "user,id=n0,restrict=on,$forwards" -device virtio-net-pci,netdev=n0
}

# Prints the bridge network: the tap made by net.sh, which gives the guest its own address so the server can
# announce itself to the other nodes and list, and so players keep their real addresses.
tap_net() {
  printf '%s\n' -netdev "tap,id=n0,ifname=${VM_TAP:-iw4x0},script=no,downscript=no" -device virtio-net-pci,netdev=n0
}

# Prints the full qemu argument list for a mode.
args() {
  common_args
  case "${1:-}" in
    open) open_net ;;
    run) closed_net ;;
    tap) tap_net ;;
    *) usage ;;
  esac
}

# Downloads the cloud image and refuses to continue unless its checksum matches the published one.
fetch_image() {
  mkdir -p "$DIR"
  [ -f "$DIR/base.qcow2" ] && return
  curl -sSL -o "$DIR/SHA512SUMS" "$IMAGE_URL/SHA512SUMS"
  curl -sSL -o "$DIR/base.qcow2" "$IMAGE_URL/$IMAGE_NAME"
  local want
  want="$(grep " $IMAGE_NAME\$" "$DIR/SHA512SUMS" | cut -d' ' -f1)"
  echo "$want  $DIR/base.qcow2" | sha512sum -c - >/dev/null
}

# Makes the guest disk on top of the base image, the ssh key, and the cloud-init seed that creates the user.
create() {
  fetch_image
  [ -f "$DIR/disk.qcow2" ] && { echo "$DIR/disk.qcow2 exists; remove it to start over" >&2; exit 1; }
  qemu-img create -q -f qcow2 -b "$DIR/base.qcow2" -F qcow2 "$DIR/disk.qcow2" "${DISK_GB}G"
  [ -f "$DIR/id_ed25519" ] || ssh-keygen -q -t ed25519 -N '' -C iw4x-vm -f "$DIR/id_ed25519"
  rm -f "$DIR/known_hosts"
  mkdir -p "$DIR/seed"
  printf 'instance-id: iw4x-%s\nlocal-hostname: iw4x\n' "$(date +%s)" > "$DIR/seed/meta-data"
  sed "s#@PUBKEY@#$(cat "$DIR/id_ed25519.pub")#" "$OPS/vm/user-data.template" > "$DIR/seed/user-data"
}

# Waits until the guest answers ssh.
wait_for_ssh() {
  local i
  for i in $(seq 1 120); do
    guest true 2>/dev/null && return
    sleep 3
  done
  echo "the guest did not answer ssh; see $DIR/console.log" >&2
  exit 1
}

# Boots once with the open network and the seed served from the host, and waits for cloud-init to finish.
first_boot() {
  python3 -m http.server "$SEED_PORT" --bind 127.0.0.1 --directory "$DIR/seed" >/dev/null 2>&1 &
  local seed=$!
  trap 'kill $seed 2>/dev/null || true' RETURN
  local -a a
  mapfile -t a < <(args open)
  qemu-system-x86_64 "${a[@]}" -smbios "type=1,serial=ds=nocloud;s=http://10.0.2.2:$SEED_PORT/" -daemonize
  wait_for_ssh
  guest 'cloud-init status --wait' >/dev/null || true
}

# Prints the packages the seed asks for, one per line.
packages() {
  sed -n '/^packages:/,/^write_files:/p' "$OPS/vm/user-data.template" | sed -n 's/^  - //p'
}

# Installs the seed's packages again with apt, because cloud-init gives up on the whole list when one download fails.
ensure_packages() {
  guest "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $(packages | paste -sd' ')" >/dev/null
}

# Pushes the server directory, shotcaller, IW4MAdmin and their configs, and runs the installer inside the guest.
install_in_guest() {
  local server="$1" wheel
  uv build --wheel --out-dir "$DIR/dist" "$REPO" >/dev/null 2>&1
  wheel="$(ls -t "$DIR"/dist/*.whl | head -1)"
  guest 'mkdir -p ~/server/game ~/dist ~/shotcaller ~/.config/shotcaller ~/.local/share/shotcaller'
  push --info=progress2 --exclude=/players/ --exclude=/userraw/logs/ --exclude=/userraw/games_mp.log \
    --exclude=/userraw/scriptdata/shotcaller/ "$server/game/" iw4x@127.0.0.1:server/game/
  push "$wheel" iw4x@127.0.0.1:dist/
  push --exclude=.git --exclude=__pycache__ --exclude=.pytest_cache "$REPO/" iw4x@127.0.0.1:shotcaller/
  push "$HOME/.config/shotcaller/shotcaller.toml" iw4x@127.0.0.1:.config/shotcaller/host.toml
  push "$HOME/.local/share/shotcaller/reports/" iw4x@127.0.0.1:.local/share/shotcaller/reports/
  [ -d "${IW4MADMIN_DIR:-}" ] && push --exclude=dl/ --exclude=Database/ --exclude=Log/ "$IW4MADMIN_DIR/" iw4x@127.0.0.1:iw4madmin/
  guest "LLM_PORT=$LLM_PORT bash ~/shotcaller/ops/vm/guest-install.sh"
}

# Installs into a guest that is already up with the open network, then shuts it down.
install_and_stop() {
  ensure_packages
  install_in_guest "$1"
  guest 'sudo systemctl poweroff' || true
  sleep 15
}

# Pushes the current shotcaller and ops code to a running guest and reruns the guest installer, leaving the game files alone.
refresh() {
  local wheel
  uv build --wheel --out-dir "$DIR/dist" "$REPO" >/dev/null 2>&1
  wheel="$(ls -t "$DIR"/dist/*.whl | head -1)"
  push "$wheel" iw4x@127.0.0.1:dist/
  push --exclude=.git --exclude=__pycache__ --exclude=.pytest_cache "$REPO/" iw4x@127.0.0.1:shotcaller/
  guest "LLM_PORT=$LLM_PORT bash ~/shotcaller/ops/vm/guest-install.sh"
  guest 'systemctl --user restart iw4x-server shotcaller shotcaller-watchdog iw4x-guest-relay'
}

# Provisions a fresh guest from a populated server directory and leaves it shut down, ready for run.
provision() {
  local server="${1:?usage: vm.sh provision <server dir>}"
  create
  first_boot
  install_and_stop "$server"
}

# Boots the isolated production guest in the foreground.
run() {
  local -a a
  mapfile -t a < <(args run)
  exec qemu-system-x86_64 "${a[@]}"
}

# Asks the guest to power off, then makes sure the process is gone.
stop() {
  guest 'sudo systemctl poweroff' 2>/dev/null || true
  local i pid
  pid="$(cat "$DIR/qemu.pid" 2>/dev/null || true)"
  for i in $(seq 1 30); do
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || return 0
    sleep 2
  done
  kill "$pid" 2>/dev/null || true
}

# Runs the host side of the UDP tunnel: the public game port in, the guest's tunnel port behind it.
relay() {
  exec python3 "$OPS/vm/udp_tunnel.py" host --listen "0.0.0.0:$GAME_PORT" --tunnel "127.0.0.1:$TUNNEL_PORT"
}

# Prints a user unit for the host: the guest's qemu process (vm) or the UDP relay (relay), with the directories this machine has hidden from it.
unit() {
  local d hidden=""
  for d in /mnt /media /run/media /srv /run/user; do
    [ -d "$d" ] && hidden="$hidden$d "
  done
  local name="${1:-vm}"
  sed -e "s#@DIR@#$DIR#g" -e "s#@REPO@#$REPO#g" -e "s#@PORT@#$GAME_PORT#g" -e "s#@HIDDEN@#${hidden% }#g" "$OPS/systemd/iw4x-$name.service.in"
}

# Prints the server.env lines that point update.sh at the guest.
env_lines() {
  printf 'REMOTE_SSH="-p %s -i %s -o UserKnownHostsFile=%s -o BatchMode=yes -o LogLevel=ERROR"\n' "$(guest_port)" "$DIR/id_ed25519" "$DIR/known_hosts"
  printf 'REMOTE_USER="iw4x"\nREMOTE_HOST="%s"\nREMOTE_BASE="server"\n' "$(guest_host)"
}

cmd="${1:-}"
[ -n "$cmd" ] || usage
shift
case "$cmd" in
  image) fetch_image ;;
  create) create ;;
  provision) provision "$@" ;;
  install) install_and_stop "${1:?usage: vm.sh install <server dir>}" ;;
  run) run ;;
  refresh) refresh ;;
  args) args "$@" ;;
  ssh) guest "$@" ;;
  tap) tap ;;
  untap) untap ;;
  stop) stop ;;
  env) env_lines ;;
  unit) unit "$@" ;;
  relay) relay ;;
  *) usage ;;
esac
