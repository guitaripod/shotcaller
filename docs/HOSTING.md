# Hosting and operations

How to run the server for other people. The kit in [`ops/`](../ops) automates the parts below; this page says what it does and why.

## Where to host

| | Home desktop | VPS |
| --- | --- | --- |
| Home IP exposed | yes, to every player and to the public server list | no |
| Shares CPU, disk and uplink with your own gaming | yes (the server idles at about 0.2 core and 650 MB, but a download or a game session on the same uplink shows) | no |
| Model | local, nothing to set up | the sidecar runs on the VPS and `[llm] base_url` points to your GPU box over a tunnel (Tailscale or WireGuard); if the tunnel is down the static baseline takes over |
| Cost | none | a small VPS, 1 vCPU and 1 GB is enough for the dedicated server under Wine |

For a private group, a home host with `LAN_ONLY=1` or a port forward to friends is fine. For strangers, use a VPS: forwarding a port from home publishes your address, and a hang, a ban-evading cheater or an exploit then lands on the machine you live on (see [Is it safe for the machine?](#is-it-safe-for-the-machine)). Everything in `ops/` works the same on either.

## Ports

- **UDP `net_port`** (28961 in the examples): game traffic, rcon, the server list. This is the only port the [official hosting guide](https://docs.iw4x.io/hosting/server-hosting/) opens (its default is 28960, inbound and outbound).
- **TCP `net_port`**: the client's built-in web server answers `/info`, `/list`, `/map` and `/file` here. The official guide never opens it, one community wiki says to forward both, and IW4x's October security release fixed file access outside the game directories and download-password bypasses in that code. Leave it closed; open it only if the server does not appear in the list, or if you serve custom maps or a mod.
- **TCP 1624**: the IW4MAdmin web front. Never forward it. It answers on every interface, so `setup.py` turns on its connection whitelist (loopback only). Reach it through an SSH or Tailscale tunnel and add that address with `--allow`.

`sv_lanOnly 1` keeps the server out of the public list. It is `LAN_ONLY=1` in `server.env`; flip to `0` and restart the unit to list the server.

## Slots and teams

The server fills both teams to six, counting humans: `bots_manage_fill 12`, `bots_manage_fill_mode 0`, `bots_manage_fill_kick 1` and `bots_manage_fill_spec 0` keep the total at 12, and `bots_team custom` with `bots_team_amount 6` and `bots_team_mode 0` keep the axis side at exactly six including humans, so the allies side is six too. A human who joins either team pushes one bot out, and Bot Warfare moves a bot across within about a second if the teams are off by one, so the enemy team is always full. Spectators do not count.

`sv_maxclients` is 18 (the engine limit), not 12: a human needs a free slot to connect, and Bot Warfare only kicks a bot after the human has picked a team, so a server whose slots are all bots cannot be joined. For bigger teams raise `bots_manage_fill` to twice the team size and set `bots_team_amount` to the team size. `bots_skill` stays `0` so shotcaller owns per-bot skill.

Bots are never added or removed by the model. When humans are on both teams the director holds still: any change it could make for one side is unfair to the other.

## Bot names

IW4x names bots from `userraw/bots.txt` (the installer copies `ops/iw4x-server/bots.txt`): one name per line, at most 15 characters, and an optional clan tag after a comma (`Rhino,LMC` shows as `[LMC]Rhino`). A line without a comma gets no tag; the `[BOT]` tag only appears when the file is empty and the names come from the master server. `sv_randomBotNames 1` shuffles the list at start. The name list is read once when the first bot is added, so changing it needs a server restart.

What still gives a bot away: the scoreboard shows ping `-1` for bots (the engine reports it that way, and fixing it would mean patching `iw4x.dll`), and their guid is `botN` in `rcon status`.

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

## What IW4x supports

IW4x is maintained by AlterWare. Its docs cover hosting on Windows and Linux (native `iw4x-launcher` plus `DedicatedServer.sh`), recommend a VPS for public servers (24/7, 5 to 10 Mbps up, about 500 MB RAM, 2 cores, no GPU) and IW4MAdmin for public servers, and call Wine or Proton setup out of scope; help is the IW4x Discord. Running `wine iw4x.exe -dedicated` after `iw4x-launcher --update` is the community pattern (the Pterodactyl egg does exactly that), and the community Docker images are mostly stale. A server shows in the in-game browser once `sv_hostname` is set and `sv_lanOnly` is 0; there is no registration, the decentralized node system accepts up to 15 servers per IP, and servers that break the hosting rules can be delisted (the rules are not in the docs; ask on Discord).

Security history, which is why `update.sh` runs hourly: two client RCEs in 2023, another in the engine fixed in r4773 (December 2024, triggered by joining a malicious server), and release r5243 fixing, for players and dedicated servers, rcon password exposure and guessing, file access outside the game directories, download-password bypass, player impersonation and crashes or memory corruption from crafted input. Keep the server on the current release. Regular rcon sends its password in plaintext (`rconSafe` uses an RSA key instead), and IW4MAdmin needs regular rcon, so keep the rcon port off the internet path you do not control: the UDP port is shared with the game, so the password must stay long and random.

## Is it safe for the machine?

The server is closed-source game code (`iw4x.exe` on the Call of Duty engine) running under Wine, parsing packets from strangers, plus an embedded HTTP server on the TCP game port. Engines of this generation have a history of remote-code-execution bugs, and none of this has been audited. Assume a determined attacker could one day get code running as the server's user. Wine is not a sandbox: by default that user is you, with your home directory, your keys and every disk you have mounted.

`iw4x-server.service` therefore runs in a systemd sandbox (verified from the unit's processes):

- your home, `/mnt`, `/media`, `/srv` and `/run/user` (the session bus and agent sockets) are empty tmpfs; only the server directory is bound back in and writable;
- the rest of the filesystem is read-only, `/tmp` and `/dev` are private, no new privileges, no kernel or clock tuning, no new namespaces, only IP and local sockets.

What the sandbox does not do is stop the network: a compromised server could still talk to anything your machine can reach, which includes the services on `127.0.0.1` (the model server, `opencode`) and the rest of your LAN. If you host strangers from the desktop, the options in order of strength are a VPS, a VM or a dedicated user with firewall rules that keep that user off loopback and the LAN, and then the sandbox alone. The rest of the checklist matters too: forward only UDP, keep TCP 1624 and the rcon password to yourself, keep the IW4x install current (`update.sh`), and leave the IW4MAdmin web front on its loopback-only whitelist.

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
