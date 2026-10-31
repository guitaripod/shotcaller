# Overlays and the map vote

Both live entirely in the GSC mod. They need no sidecar and no model, work on a server with only humans, and cost a few HUD elements per player. The overlays are for humans only; bots never see them.

## Kill and streak banners

A banner is a dark strip across the screen with two accent lines, a slammed-in title and an optional subtitle. The strongest event of a kill wins the title; the runner-up becomes the subtitle (`RIP AND TEAR` over `HEADSHOT`).

| Kind | Banners |
| --- | --- |
| Multi-kill (kills within 4.5 s) | `DOUBLE KILL`, `TRIPLE KILL`, `QUAD KILL`, `RIP AND TEAR` (5 or more) |
| Streak (kills without dying) | `KILLING SPREE` 3, `RAMPAGE` 5, `DOMINATING` 7, `UNSTOPPABLE` 10, `GODLIKE` 15, `SLAYER OF HELL` 20 |
| Single kill | `FIRST BLOOD`, `SHUTDOWN` (ended an enemy streak of 5 or more), `GLORY KILL` (knife), `PAYBACK` (killed whoever killed you last), `LONG SHOT` (1800+ units), `HEADSHOT`, `BLOWN APART` (explosive), `POINT BLANK`, `BACK FROM HELL` (a kill after 4+ deaths in a row) |
| Death | red screen flash, `STREAK LOST` after a streak of 3 or more |
| Match flow | `FIGHT` with the map and mode, `YOU TAKE THE LEAD`, `LEAD LOST`, `MATCH POINT` at 85% of the score limit, `ONE MINUTE REMAINING`, `30 SECONDS REMAINING`, a big 10-to-1 countdown |
| Widgets | `KILL STREAK n` on the right from 2 kills, and a faint pulsing red tint from 5 |

Extras per banner, set in the theme: screen flash, camera shake (`earthquake`) and a sound. Each has its own switch.

## Switches and sizing

Set in `server.cfg` or live over rcon. All default to on.

| Dvar | Effect |
| --- | --- |
| `sc_hud` | master switch for every overlay |
| `sc_hud_kills`, `sc_hud_streaks`, `sc_hud_flow`, `sc_hud_death`, `sc_hud_widgets` | one group each |
| `sc_hud_sound`, `sc_hud_shake` | the sound and camera-shake extras |
| `sc_hud_scale` | size multiplier, 0.5 to 2 |
| `sc_vote`, `sc_vote_choices`, `sc_vote_seconds`, `sc_vote_delay`, `sc_vote_pool` | the map vote, below |

## Previewing

`rcon set sc_hud_preview <name>` plays a style on every human so it can be judged without playing for it. Names are any banner id (`ripandtear`, `godlike`, `shutdown`, `fight`, `matchpoint`, ...), plus `all` (every banner in turn), `kills` (a six-kill sequence through the real combo logic), `streak`, `edge`, `countdown` and `vote`.

## Restyling

Everything about how a banner looks is in `gsc/maps/mp/shotcaller/_hud_theme.gsc`: one `case` per id with the words, colors, icon, hold time, weight, sound, shake and flash. Adding a banner is a new case plus an id in `allIds()`. Placement and animation are in `_hud.gsc` (`ensure`, `playBanner`). Fonts that read well here: `hudbig` for titles, `objective` for subtitles and labels, `bigfixed` for numbers. Shaders known to exist in-game and take a tint: `white`, `gradient_fadein`, `line_horizontal`, `killiconheadshot`, `killiconmelee`, `killiconsuicide`, `waypoint_kill`.

## End-of-match map vote

When the match ends, every human gets a full-screen vote over a dimmed scene: four maps from your rotation (never the one just played), a live vote count on each, a timer, and the cursor row highlighted.

- **Fire** moves the cursor down, **Aim** up, **Use** (or Melee) casts or changes your vote.
- The most votes wins; ties are broken at random. With no votes, the game master's pick wins if the sidecar made one, otherwise the normal rotation continues.
- The result is written to `sv_mapRotationCurrent`, so the engine loads it next, and a `vote` event is logged.
- The sidecar's `match` tier can recommend a map (`sc_gm_pick`); it is offered first, tagged `GAME MASTER PICK`.
- The vote starts `sc_vote_delay` (2 s) after the match ends and runs `sc_vote_seconds` (10 s). The server's intermission is about 17 seconds, so the vote, the 1.6 s result and the map load fit.
- `sc_vote_pool` overrides the candidates with a space-separated list of map ids; by default the pool is every map in `sv_mapRotation`.

Map previews as images are not possible: the thumbnail materials live in the front-end fast files and are not loaded in a match. The vote uses typography instead. Display names are in `_mapnames.gsc`; an unknown map falls back to its id tidied up.

## Notes for contributors

- A GSC compile error (even `bad syntax` with no line number) stops the server from loading the map. Always start a scratch server after editing, and read the log for `script compile error`.
- Reserved words bite: assigning a struct field called `size` is a syntax error (`.size` is the array property). `notifyOnPlayerCommand` does not exist in IW4; poll `attackButtonPressed()`, `adsButtonPressed()` and `useButtonPressed()` instead. `println` does not reach `-stdout`; use `printconsole`.
- GSC arrays are passed by value, so a helper cannot grow the caller's array.
- A real client can be driven headlessly: run a second client under Xvfb, join it from a dev script (`menuresponse` team and class), set `sc_hud_preview`, and capture the display with `import -display :81 -window root shot.png`. Fire, Aim and Use can be injected with python-xlib's XTEST, which is how the vote was verified.
