# Contributing

Issues and pull requests are welcome. By contributing you agree your work is released under GPL-3.0-or-later.

## Setup

```sh
uv venv && uv pip install -e '.[dev]'
python -m pytest -q
```

The tests need no game, no model and no network: the sidecar is exercised through a scripted director, an inline executor and temp files, and the GSC is linted (balanced brackets, no inline comments, a `///` doc comment above every function).

## Testing against a real server

1. Install the GSC into a scratch copy of your server: `scripts/install-gsc.sh <game dir>`.
2. Start the server on a spare port with `set bots_skill "0"`, spawn bots (`rcon spawnBot 8`) and join with a client.
3. Point a dev config at it and run `shotcaller run`. Watch `userraw/scriptdata/shotcaller/events.log` for `ack` lines and the journal for decisions.

GSC compile errors show in the server console at start-up; a script that fails to compile disables itself, so always check for `Script scripts/mp/shotcaller.gsc loaded successfully`.

## Style

- No inline comments. If something needs explaining, extract a well-named function with a doc comment (`///` in GSC, a docstring in Python).
- Keep the sidecar standard-library only.
- Anything a director can ask for goes through `validate.py` and, if it involves information or places, `fairness.py`. Do not add a path around them.
- A change to a model-facing shape bumps `schema.VERSION` and extends the eval scenarios.

## Ideas that would help

- Map knowledge for the director (lane and sightline summaries per map) so squad goals are smarter than "go to this camp spot".
- Gametypes beyond team deathmatch (objective anchors for domination, search and destroy).
- A scenario that scores a director on real recorded outcomes instead of properties.
- Other engines: the sidecar only needs an event log and a way to apply orders.
