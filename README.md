# shotcaller

An LLM game master for [Bot Warfare](https://github.com/ineedbots/iw4x_bot_warfare) bots on [IW4x](https://iw4x.io) (Call of Duty: Modern Warfare 2) servers.

The LLM never aims, moves or shoots. Bot Warfare keeps all of that, including how bots roam the map. shotcaller changes only the things a model can actually improve: how sharp each bot is, a short mission to where you keep dying, and the server's bot settings. It is built so that a better model, dropped in behind one alias, does the job better without changing any code.

```
 IW4x server (Wine)                         shotcaller sidecar (Python, stdlib only)
┌──────────────────────────┐   events.log   ┌──────────────────────────────────────┐
│ Bot Warfare              │ ─────────────▶ │ tail ─▶ MatchState ─▶ fair view      │
│ shotcaller GSC mod       │                │                         │            │
│  telemetry, anchors,     │   orders.txt   │            Director (LLM │ static)   │
│  order enforcement       │ ◀───────────── │                         │            │
└──────────────────────────┘                │ validate ─▶ fairness ─▶ actuate      │
        ▲   rcon (match knobs)              │ journal ─▶ eval / replay ─▶ gating   │
        └────────────────────────────────── └──────────────────────────────────────┘
```

## What the LLM decides, by speed

| Tier | Cadence | Decides |
| --- | --- | --- |
| `match` | per map, then every ~2 min | bot skill window, bot count, next map |
| `squad` | every ~15 s | per-bot skill (opponents harder or easier to keep the match close), and at most two timed missions to where the human keeps dying |
| everything else | never | aim, movement, firing, camping, sprinting, spawn behavior: Bot Warfare only |

The surface is small on purpose. There is no chat either: model-written banter without real context read as noise, so it was removed. An earlier version also let the model set camp/sprint/follow percentages and park bots at fixed spots; the result was bots standing around. The model has no information that beats Bot Warfare's tuning there, so those levers are gone. A mission sends a bot to a death site, holds about 15 seconds, then releases it back to stock play.

## Fair by construction

The director sees what a human commander could know: scores, the roster, the kill feed and map anchors. It is never given a living player's position, and it can only send bots to places a human recently died, after a delay. See [docs/FAIRNESS.md](docs/FAIRNESS.md).

## Gets better as models get better

Every decision is journaled with the exact view the model saw. `shotcaller eval` scores a model on a scenario suite and `shotcaller replay` re-asks a new model every decision from real matches. A model only runs a tier once its eval score clears a threshold, so you can point the config at a new model, run the eval, and promote it with evidence. See [docs/EVAL.md](docs/EVAL.md).

## Quick start

Requirements: an IW4x dedicated server with Bot Warfare installed (`userraw/z_svr_bots.iwd`), Python 3.11+, and any OpenAI-compatible endpoint (llama-swap, llama.cpp, vLLM, ...).

```sh
scripts/install-gsc.sh /path/to/iw4x/game          # copy the GSC mod into userraw
uv tool install --editable .                       # or: pip install -e .
cp examples/shotcaller.toml ~/.config/shotcaller/  # edit game_dir, rcon port, model
```

Server config (`userraw/server.cfg`) needs `set bots_skill "0"` so Bot Warfare leaves per-bot skill to shotcaller, plus your usual `rcon_password` in `userraw/secrets.cfg` (`set rcon_password "..."`).

```sh
shotcaller eval          # score the configured model, store its report
shotcaller doctor        # check files, rcon and the report
shotcaller run           # run the director (see systemd/shotcaller.service)
```

## Docs

- [Architecture](docs/ARCHITECTURE.md)
- [Wire protocol](docs/PROTOCOL.md)
- [Fairness](docs/FAIRNESS.md)
- [Eval, replay and gating](docs/EVAL.md)
- [Contributing](CONTRIBUTING.md)

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
