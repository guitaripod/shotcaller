# ops: an always-on IW4x server

Scripts and systemd units that turn a machine with Wine, rsync and an IW4x install into a self-updating server. [docs/HOSTING.md](../docs/HOSTING.md) explains the choices.

```
ops/iw4x-server/install.sh   build a server directory from the game install, write config, install units
ops/iw4x-server/run.sh       what the unit runs: xvfb-run + wine iw4x.exe -dedicated
ops/iw4x-server/update.sh    sync from the game install and restart, but only when the server is empty
ops/iw4x-server/maps.sh      print a sv_mapRotation of every map the install ships
ops/iw4madmin/install.sh     IW4MAdmin with the anti-cheat, pinned and checksum-verified
ops/vm/vm.sh                 run everything in an isolated QEMU guest (see docs/HOSTING.md)
ops/systemd/                 unit templates
```

## Install

```sh
ops/iw4x-server/install.sh <server dir> <iw4x game dir> [--port 28961] [--name hostname] [--unit iw4x-server] [--config shotcaller.toml]
scripts/install.sh <server dir>/game
ops/iw4madmin/install.sh <iw4madmin dir> <server dir>/game <port> [--allow <tunnel address>]
```

Then follow the checklist in [docs/HOSTING.md](../docs/HOSTING.md#checklist-before-listing-publicly).

The installer writes a random rcon password into `userraw/secrets.cfg` (mode 600). It never prints it; read it from there.

## Sandbox

The game server unit hides your home, other disks and the session bus from the game process and makes everything but the server directory read-only. See [Is it safe for the machine?](../docs/HOSTING.md#is-it-safe-for-the-machine) for what that does and does not cover.

## Files the update keeps

`update.sh` never overwrites `userraw/server.cfg`, `secrets.cfg`, `games_mp.log`, `scriptdata/`, `logs/`, `demos/`, `players/`, `steam_appid.txt`, and the shotcaller and IW4MAdmin scripts. Everything else follows the game install.
