# Overlays and the map vote

Both live entirely in the GSC mod. They need no sidecar and no model, work on a server with only humans, and cost a few HUD elements per player. The overlays are for humans only; bots never see them.

## Kill and streak banners

A banner is a compact card in a column on the left of the screen, clear of the minimap, the score and the crosshair: a dark plate sized to its text, a bright accent bar in the tier's colour, an optional kill icon, a title and an optional subtitle. The strongest event of a kill wins the title; the runner-up becomes the subtitle (`RIP AND TEAR` over `HEADSHOT`). Cards stack three deep, newest at the bottom; older ones slide up, dim and fade.

| Kind | Banners |
| --- | --- |
| Multi-kill (kills within 4.5 s) | `DOUBLE KILL`, `TRIPLE KILL`, `QUAD KILL`, `RIP AND TEAR` (5 or more) |
| Streak (kills without dying) | `KILLING SPREE` 3, `RAMPAGE` 5, `DOMINATING` 7, `UNSTOPPABLE` 10, `GODLIKE` 15, `SLAYER OF HELL` 20 |
| Single kill | `FIRST BLOOD`, `SHUTDOWN` (ended an enemy streak of 5 or more), `GLORY KILL` (knife), `PAYBACK` (killed whoever killed you last), `LONG SHOT` (1800+ units), `HEADSHOT`, `BLOWN APART` (explosive), `POINT BLANK`, `BACK FROM HELL` (a kill after 4+ deaths in a row) |
| Death | red screen flash, `STREAK LOST` after a streak of 3 or more |
| Match flow | `FIGHT` with the map and mode, `YOU TAKE THE LEAD`, `LEAD LOST`, `MATCH POINT` with the real score limit when a team is three kills from it, `ONE MINUTE REMAINING`, `30 SECONDS REMAINING`, a big 10-to-1 countdown |
| Widgets | a `STREAK` chip above the cards from 2 kills, with a bar filling toward the next milestone, and a faint pulsing red tint from 5 |

Extras per banner, set in the theme: screen flash, camera shake (`earthquake`) and a sound. Each has its own switch.

## Switches and sizing

Set in `server.cfg` or live over rcon. All default to on.

| Dvar | Effect |
| --- | --- |
| `sc_hud` | master switch for every overlay |
| `sc_hud_kills`, `sc_hud_streaks`, `sc_hud_flow`, `sc_hud_death`, `sc_hud_widgets` | one group each |
| `sc_hud_sound`, `sc_hud_shake` | the sound and camera-shake extras |
| `sc_hud_scale` | size multiplier, 0.5 to 2 |
| `sc_vote`, `sc_vote_choices`, `sc_vote_seconds`, `sc_vote_delay`, `sc_vote_pool`, `sc_vote_sens`, `sc_vote_font` | the map vote, below |

## Previewing

`rcon set sc_hud_preview <name>` plays a style on every human so it can be judged without playing for it. Names are any banner id (`ripandtear`, `godlike`, `shutdown`, `fight`, `matchpoint`, ...), plus `all` (every banner in turn), `kills` (a six-kill sequence through the real combo logic), `streak`, `edge`, `countdown` and `vote`.

## Restyling

Everything about how a banner looks is in `gsc/maps/mp/shotcaller/_hud_theme.gsc`: one `case` per id with the words, colors, icon, hold time, weight, sound, shake and flash. Adding a banner is a new case plus an id in `allIds()`. Placement, sizing and animation are in `_hud.gsc`: `ensure` builds the column, `fillCard` sizes a card to its text and weight, `animateCard` brings it in, `fadeCard` slides and dims it. Keep titles short: a card is about a fifth of the screen wide and the title shrinks to fit. Fonts that read well here: `hudbig` for titles, `objective` for subtitles and labels, `bigfixed` for numbers. Shaders known to exist in-game and take a tint: `white`, `gradient_fadein`, `line_horizontal`, `killiconheadshot`, `killiconmelee`, `killiconsuicide`, `waypoint_kill`.

## End-of-match map vote

When the match ends, every human gets a full-screen grid of every map on the server (never the one just played), in alphabetical columns. Move the mouse to move the cursor, and **click** a map to vote for it; click it again to withdraw. The map under the cursor lights up and its name is shown large with its vote count, your vote is marked green, the game master's pick is underlined and named, and a line shows the maps in the lead.

- Use (or Melee) also votes for the map under the cursor.
- The most votes wins; ties are broken at random. With no votes, the game master's pick wins if the sidecar made one, otherwise the normal rotation continues.
- The result is written to `sv_mapRotationCurrent`, so the engine loads it next, and a `vote` event is logged. The winner is held on screen for about 1.6 s.
- The vote starts `sc_vote_delay` (2 s) after the match ends and runs `sc_vote_seconds` (12 s). The mod sets `level.postRoundTime` at the start of every match so the server stays on the map for the vote and its result (about `sc_vote_delay + sc_vote_seconds + 4` seconds).
- `sc_vote_pool` is the list of candidate map ids, space separated. The ops installer writes it from the rotation. Without it the pool is every map the server has seen in `sv_mapRotation` since it started, which fills up as the rotation advances because the engine drains that dvar as it plays.
- `sc_vote_sens` (default 6) is how far the cursor moves per degree of mouse turn; raise it for a slower mouse. `sc_vote_font` (0.9) scales the map names; the grid has seven columns of up to eight maps so it fits a 4:3 screen too.

How it works: a click needs a pointer and the game has no menu cursor for scripts, so the mouse is read as view angle. During the vote each player is put back in the `playing` state, where the view turns freely and the end-of-match scoreboard is not drawn (it is drawn over everything in the `intermission` and `spectator` states), their weapon is disabled so a click does not fire it, and their angles are set back to the centre every frame; the turn since the last frame is the mouse motion. A player may own only about 31 HUD elements and the shared pool is as small, so each grid column is one multi-line text element and a single bar is moved under the cursor, instead of a tile per map.

Map previews as images are not possible: the thumbnail materials live in the front-end fast files and are not loaded in a match. The vote uses typography instead. Display names are in `_mapnames.gsc`; an unknown map falls back to its id tidied up.

## Notes for contributors

- A GSC compile error (even `bad syntax` with no line number) stops the server from loading the map. Always start a scratch server after editing, and read the log for `script compile error`.
- Reserved words bite: assigning a struct field called `size` is a syntax error (`.size` is the array property). `notifyOnPlayerCommand` does not exist in IW4; poll `attackButtonPressed()`, `adsButtonPressed()` and `useButtonPressed()` instead. `println` does not reach `-stdout`; use `printconsole`.
- GSC arrays are passed by value, so a helper cannot grow the caller's array.
- A real client can be driven headlessly: run a second client under Xvfb, join it from a dev script (`menuresponse` team and class), set `sc_hud_preview`, and capture the display with `import -display :81 -window root shot.png`. Mouse motion and clicks can be injected with python-xlib's XTEST once the game window has X input focus (`set_input_focus` on the `IW4x: Multiplayer` window, otherwise motion is ignored), which is how the vote was verified. Setting `scr_war_scorelimit 1` over rcon ends a dev match within seconds.
