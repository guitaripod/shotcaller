# Changelog

## 0.2.0

### Overlays
- The kill and streak overlays are a compact column of cards on the left instead of a full-width strip: a plate sized to its text, a tier-coloured accent bar, an optional icon, short titles and subtitles, and a chain of three cards that slide, dim and fade.
- The streak is a chip above the cards with a bar filling toward the next milestone; the last-ten-seconds countdown sits under the score bar instead of behind the weapon.
- `MATCH POINT` fires three kills from the real limit and names it (`FIRST TO 7500`) rather than claiming the next kill decides.

### Server
- Twelve slots with ten bots, so the browser shows two free slots and a human always fits.
- `ops/vm/janitor.sh` and its timer keep the parts that do not heal themselves in order: re-adds the router forward, records WAN changes, restarts a silent guest, rotates and gzips the game log when nobody is playing, and copies the admin database, configs and journal to a dated backup, keeping fourteen.

### Hosting
- The guest can run on a private bridge with an nftables guard (`ops/vm/net.sh`, `vm.sh tap`/`untap`), which gives players their real addresses and lets the server list itself publicly.
- `docs/HOSTING.md` documents what public hosting costs in privacy, and the relay is only maintained when the machine is marked public.
