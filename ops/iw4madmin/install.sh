#!/usr/bin/env bash
set -euo pipefail

OPS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="2026.2.4.1-prerelease"
ASSET="IW4MAdmin-2026.2.4.1.zip"
SHA256="5c00c45297e3ee80cbc3d042561253a4673319ff3c5e641ab89aae6a1977fe1e"

usage() {
  echo "usage: install.sh <iw4madmin dir> <server game dir> <udp port> [--allow <address>]..." >&2
  exit 2
}

[ $# -ge 3 ] || usage
DEST="$1"
GAME_DIR="$2"
PORT="$3"
shift 3
ALLOW=()
while [ $# -gt 0 ]; do
  case "$1" in
    --allow) ALLOW+=(--allow "$2"); shift 2 ;;
    *) usage ;;
  esac
done

# Downloads the pinned release and refuses to continue unless its checksum matches.
fetch_release() {
  mkdir -p "$DEST/dl"
  curl -sSL -o "$DEST/dl/$ASSET" "https://github.com/RaidMax/IW4M-Admin/releases/download/$VERSION/$ASSET"
  echo "$SHA256  $DEST/dl/$ASSET" | sha256sum -c - >/dev/null
  mkdir -p "$DEST/app"
  unzip -q -o "$DEST/dl/$ASSET" -d "$DEST/app"
}

# Installs the .NET and ASP.NET Core runtimes next to IW4MAdmin so nothing system-wide changes.
fetch_runtimes() {
  curl -sSL -o "$DEST/dl/dotnet-install.sh" https://dot.net/v1/dotnet-install.sh
  chmod +x "$DEST/dl/dotnet-install.sh"
  "$DEST/dl/dotnet-install.sh" --runtime aspnetcore --channel 10.0 --install-dir "$DEST/dotnet" --no-path >/dev/null
  "$DEST/dl/dotnet-install.sh" --runtime dotnet --channel 10.0 --install-dir "$DEST/dotnet" --no-path >/dev/null
}

fetch_release
fetch_runtimes
install -m 644 "$DEST/app/GameFiles/AntiCheat/IW4x/userraw/scripts/_customcallbacks.gsc" "$GAME_DIR/userraw/scripts/_customcallbacks.gsc"
python3 "$OPS/iw4madmin/setup.py" --app "$DEST/app" --dotnet "$DEST/dotnet" --game-dir "$GAME_DIR" --port "$PORT" "${ALLOW[@]}"
mkdir -p "$HOME/.config/systemd/user"
sed "s#@IW4MADMIN@#$DEST#g" "$OPS/systemd/iw4madmin.service.in" > "$HOME/.config/systemd/user/iw4madmin.service"
systemctl --user daemon-reload
echo "IW4MAdmin installed in $DEST. Start it: systemctl --user enable --now iw4madmin; webfront http://127.0.0.1:1624"
echo "Claim ownership first: join the server and type !owner before the server is public."
