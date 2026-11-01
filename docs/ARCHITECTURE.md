# Architecture

shotcaller has two halves that share nothing but two plain text files.

```
 IW4x server process                                 shotcaller sidecar
┌─────────────────────────────────┐                ┌───────────────────────────────────────────┐
│ Bot Warfare (stock, unmodified) │                │ EventTail ─▶ MatchState ─▶ fair_view      │
│                                 │                │                              │            │
│ shotcaller GSC mod              │  events.log    │                    Director.decide(tier)   │
│  _telemetry  kills, scores ─────┼──────────────▶ │                              │            │
│  _anchors    human death sites  │                │              pipeline.resolve (validate    │
│  _orders     poll + enforce ◀───┼─ orders.txt ── │              + fairness + limits)          │
│                                 │                │                              │            │
│                                 │◀── rcon ────── │        OrderFile / MatchActuator           │
└─────────────────────────────────┘                │        Journal ─▶ eval / replay ─▶ gating  │
                                                   └───────────────────────────────────────────┘
```

## Why files, not HTTP

GSC in IW4x can read and write files (`FileRead`, `FileWrite`, `FileExists`) but cannot POST over HTTP, and rcon needs a round trip per command. Two files are simple, debuggable with `cat`, survive a restart of either side and need no extra process. The wire format is line based because GSC has no JSON parser. See [PROTOCOL.md](PROTOCOL.md).

## Game side (`gsc/`)

| File | Job |
| --- | --- |
| `scripts/mp/shotcaller.gsc` | entry point the engine loads from `userraw/scripts/mp` |
| `maps/mp/shotcaller/_main.gsc` | dvars, start-up order |
| `_log.gsc` | event log: truncates per map, `emit`, `field`, name sanitising |
| `_telemetry.gsc` | kill callback hook, joins and leaves, scoreboard snapshots, match end |
| `_anchors.gsc` | human death sites as `w<index>` anchors, and anchor id to origin |
| `_orders.gsc` | polls `orders.txt`, applies skill, runs timed missions, reverts on expiry |
| `_hud.gsc`, `_hud_theme.gsc`, `_hud_events.gsc` | overlay toolkit, banner styles, and the kill, streak and match-flow events that trigger them (see [OVERLAYS.md](OVERLAYS.md)) |
| `_mapvote.gsc`, `_mapnames.gsc` | the end-of-match vote screen and map display names |

It hooks `level.callbackplayerkilled` one frame after Bot Warfare so both stay in the chain. It sets only Bot Warfare's own per-bot skill (`pers["bots"]["skill"]["base"]`) and its `SetScriptGoal` / `ClearScriptGoal` for timed missions. It never touches behavior percentages, `SetScriptEnemy`, aim or movement builtins.

Safety on the game side:

- Orders carry a TTL. If the sidecar dies, the mod reverts every bot to its stock values when the TTL lapses.
- Orders name the map they were written for; orders for another map are ignored.
- An order set with nothing in it reverts the bots immediately.
- Values are clamped again in GSC (skill 1-7, goal radius 16-1000, mission length 3-60 s).
- A goal is a mission: applied once when it first appears, released on arrival, timeout or death, and not re-applied while the same goal string is still in the file.

## Sidecar (`src/shotcaller/`)

| Module | Job |
| --- | --- |
| `events`, `tail` | parse the event log; read only complete new lines; notice truncation |
| `state` | `MatchState`: roster, scores, kill feed, anchors, rebuilt from events |
| `fairness` | the only view a director gets; which anchors are legal goals |
| `orders`, `schema` | typed orders, wire encoding, JSON schemas per tier |
| `validate`, `pipeline` | one path from a proposal to safe orders, used live and in eval |
| `director/` | `Director` protocol; `StaticDirector` baseline; `LlmDirector` for any OpenAI-compatible endpoint; prompts |
| `service` | the loop: tail, track, schedule tiers, collect answers, write orders, journal |
| `actuator`, `rcon` | atomic order file; server-wide knobs over rcon |
| `journal` | append-only JSONL of every decision with the exact view; rotates at `[journal] max_mb` and keeps `backups` files |
| `watchdog` | `shotcaller watchdog`: restarts the game server unit after consecutive failed rcon checks or a stale `events.log` |
| `eval/`, `gating` | scenario suite, per-tier scores, replay, and which tiers a model has earned |
| `config`, `cli` | TOML config; `run`, `eval`, `replay`, `doctor` |

The service runs director calls on a small thread pool so a slow `squad` call never delays a `match` decision. A tier never has two calls in flight. Calls are made on a snapshot of the view; answers are validated against the state as it is when they return.

## Tiers and fallbacks

| Tier | Trigger | Output | If the model fails |
| --- | --- | --- | --- |
| `match` | new map, then every `match_s` | skill window via rcon, and a next-map recommendation (`sc_gm_pick`) shown first in the map vote | nothing changes |
| `squad` | every `squad_s` with a human playing | bot skill and missions in the order file | after one TTL without a valid answer the static baseline takes over |

A tier whose model has no passing eval report does not run on the model at all (squad falls back to the static baseline; match stays silent) unless `trust_unvalidated` is set.

## Extending

- **A new model:** change `[llm] model`, run `shotcaller eval`, restart. Gating turns tiers on by evidence.
- **A new director:** implement `decide(tier, view, trigger) -> Proposal`. It goes through the same validation, so it cannot break the fairness rules.
- **A new order type:** add it to `orders.py`, `schema.py`, `validate.py`, the wire format (`PROTOCOL.md`) and `_orders.gsc`, and bump `schema.VERSION` so old eval reports stop gating the new shape.
- **A new scenario:** add one to `eval/scenarios.py` with a property check.
