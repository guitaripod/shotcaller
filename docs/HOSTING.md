# Hosting and operations

How to run the server for other people. The kit in [`ops/`](../ops) automates the parts below; this page says what it does and why.

## Where to host

| | Home desktop | VPS |
| --- | --- | --- |
| Home IP exposed | yes, to every player and to the public server list | no |
| Shares CPU, disk and uplink with your own gaming | yes (the server idles at about 0.2 core and 650 MB, but a download or a game session on the same uplink shows) | no |
| Model | local, nothing to set up | the sidecar runs on the VPS and `[llm] base_url` points to your GPU box over a tunnel (Tailscale or WireGuard); if the tunnel is down the static baseline takes over |
| Cost | none | a small VPS, 1 vCPU and 1 GB is enough for the dedicated server under Wine |

For a private group, a home host with `LAN_ONLY=1` or a port forward to friends is fine. For strangers, use a VPS: forwarding a port from home publishes your address, and a hang or a ban-evading cheater then lands on the machine you live on. Everything in `ops/` works the same on either.

## Ports

- **UDP `net_port`** (28961 in the examples): game traffic, rcon, the server list heartbeat. This is the only port players need.
- **TCP `net_port`**: the IW4x client's built-in web server answers `/info`, `/list`, `/map` and `/file` here. Forward it only if you serve custom maps or a mod; otherwise leave it closed.
- **TCP 1624**: the IW4MAdmin web front. Never forward it. It answers on every interface, so `setup.py` turns on its connection whitelist (loopback only). Reach it through an SSH or Tailscale tunnel and add that address with `--allow`.

`sv_lanOnly 1` keeps the server out of the public list. It is `LAN_ONLY=1` in `server.env`; flip to `0` and restart the unit to list the server.

## Slots

`bots_manage_fill 10` with `bots_manage_fill_mode 0`, `bots_manage_fill_kick 1` and `bots_manage_fill_spec 0` makes humans and bots share one total of 10: each human who joins pushes a bot out, a full room has none, and spectators do not count. `sv_maxclients` is the hard cap (12 on the live server, 18 is the engine limit). `bots_skill` stays `0` so shotcaller owns per-bot skill. Verified with real clients joining a bot-filled room.

Bots are never added or removed by the model. When humans are on both teams the director holds still: any change it could make for one side is unfair to the other.

## Bandwidth

Measured with a counting UDP proxy between headless clients and the server: about 16 kbit/s from the server to each connected client and 1.3 kbit/s back, for connected clients that are idle. That is a floor. Active players send and receive more, and a 12-player firefight was not measured, so budget above it. Even at ten times the floor, 12 players need about 2 Mbit/s of upload.

## Keeping up with IW4x

Players run the current IW4x client, and a server on an older `iw4x.dll` refuses them. The server directory is an rsync copy of the Steam install, which the IW4x launcher keeps current.

`update.sh` (run hourly by the `<unit>-update.timer`) diffs the Steam install against the server copy and, when something differs:

1. does nothing while any human is connected (it asks `shotcaller players`), so a match is never cut short;
2. otherwise syncs the files, leaving the server's own config, secrets, logs, scriptdata and the shotcaller and IW4MAdmin scripts alone, and restarts the unit.

`FORCE=1 ops/iw4x-server/update.sh` skips the empty-room check. The game files themselves (map zones, `iw4x.dll`) come only from the Steam install; update that with the launcher first.

## Fresh clients and missing maps

A client that has IW4x installed already has every map in the rotation: `ops/iw4x-server/maps.sh` builds the rotation from the zone files in the IW4x install (stock maps, the special `_sh` and `_long` maps, and Nuketown from `zone/iw4x/x86/dlc`), so a map the server can load is a map every IW4x install has. Nothing needs a mirror.

For a custom map or mod the client downloads from the server's web server on the game port (`/map` for `.arena`, `.iwd` and `.ff` of the current user map, `/list` and `/file` for a mod's `.iwd` and `mod.ff`; files with `_svr_` in the name are never offered). To send those from a CDN instead, set `sv_wwwDownload 1` and `sv_wwwBaseUrl` to a plain `http://` host (the client rejects `https://` and does not follow redirects).

`z_svr_bots.iwd` (Bot Warfare), the shotcaller scripts and IW4MAdmin's `_customcallbacks.gsc` are server-side only; clients never download them.

## Admin and anti-cheat

`ops/iw4madmin/install.sh <dir> <game dir> <port> [--allow <address>]` installs a pinned, checksum-verified IW4MAdmin release with its own .NET runtime (nothing system-wide changes), answers the first-run wizard, and patches what the wizard cannot ask: web front on and whitelisted, bots ignored, the server's `games_mp.log` as its log, and the stats plugin's server-side anti-cheat on. It installs `iw4madmin.service` and copies `_customcallbacks.gsc` into the server's `userraw/scripts`, which is what feeds hit and kill data to the anti-cheat. The server needs `g_log` and `g_logSync 1` (the server template sets both).

**Before the server is listed:** join once and type `!owner` in chat. The first player to do it becomes the owner; if you list the server first, a stranger can claim it. After that, `!kick`, `!ban`, `!tempban` and `!rcon` work from in-game or the web front.

rcon is password-only. The installer generates 32 hex characters into `userraw/secrets.cfg` (mode 600); keep it out of chat and logs.

## Staying up

- `shotcaller-watchdog.service` runs `shotcaller watchdog`: every `interval_s` it asks rcon `status` and checks that `events.log` is still growing. After `failures` bad checks in a row it restarts the game server unit, then stays quiet for `grace_s` and will not restart again within `cooldown_s`. Configure it under `[watchdog]`.
- The decision journal rotates at `[journal] max_mb` (64 by default) and keeps `backups` older files.
- `iw4madmin.service` restarts itself and waits for the game server to be up.

## Checklist before listing publicly

1. VPS or accepted home exposure; `ufw`/router forwards only UDP `net_port`.
2. `!owner` claimed in IW4MAdmin; webfront reachable only through the tunnel.
3. `shotcaller doctor` all `ok`; `shotcaller eval` run for the configured model.
4. `systemctl --user enable --now iw4x-server shotcaller shotcaller-watchdog iw4madmin <unit>-update.timer`, and `loginctl enable-linger` so they start at boot.
5. `LAN_ONLY=0` in `server.env`, restart the unit.
