"""Command line: run the service, evaluate a model, replay a journal, check the setup."""

from __future__ import annotations

import argparse
import json
import logging
import signal
import sys
from dataclasses import replace
from pathlib import Path

from . import __version__, gating
from .actuator import MatchActuator, OrderFile
from .config import Config, load
from .director import LlmDirector, StaticDirector
from .director.base import Tier
from .eval import run_eval
from .eval.replay import replay
from .journal import Journal
from .rcon import Rcon
from .service import Service
from .tail import EventTail
from .watchdog import build as build_watchdog

DEFAULT_CONFIG = Path("~/.config/shotcaller/shotcaller.toml").expanduser()


def main(argv: list[str] | None = None) -> int:
    """Entry point for the `shotcaller` command."""
    parser = argparse.ArgumentParser(prog="shotcaller", description="An LLM game master for Bot Warfare bots on IW4x servers.")
    parser.add_argument("--version", action="version", version=f"shotcaller {__version__}")
    parser.add_argument("-c", "--config", type=Path, default=DEFAULT_CONFIG, help="path to shotcaller.toml")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("run", help="run the director service")
    evaluate = commands.add_parser("eval", help="score the configured model on the scenario suite and store its report")
    evaluate.add_argument("--model", help="override the configured model id")
    evaluate.add_argument("--baseline", action="store_true", help="score the static baseline instead of a model")
    evaluate.add_argument("--runs", type=int, default=3, help="times to run each scenario, since models are stochastic (default 3)")
    replay_parser = commands.add_parser("replay", help="re-run a model on the states recorded in a journal")
    replay_parser.add_argument("journal", type=Path)
    replay_parser.add_argument("--model", help="override the configured model id")
    commands.add_parser("players", help="print how many human players are connected")
    commands.add_parser("watchdog", help="restart the game server unit when it stops answering")
    commands.add_parser("doctor", help="check the install, the game files and the connections")
    args = parser.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    config = load(args.config.expanduser())
    return {"run": _run, "eval": _eval, "replay": _replay, "watchdog": _watchdog, "players": _players, "doctor": _doctor}[args.command](config, args)


def _director(config: Config, model: str | None) -> LlmDirector:
    return LlmDirector(replace(config.llm, model=model) if model else config.llm)


def _run(config: Config, args: argparse.Namespace) -> int:
    director = _director(config, None)
    enabled = gating.enabled_tiers(config.gating, director.name)
    rcon = Rcon(config.server.rcon_host, config.server.rcon_port, config.server.rcon_password())
    service = Service(
        config,
        director,
        StaticDirector(),
        enabled,
        EventTail(config.server.scriptdata / "events.log"),
        OrderFile(config.server.scriptdata / "orders.txt"),
        MatchActuator(rcon),
        Journal(config.journal_path, config.journal_max_mb * 1024 * 1024, config.journal_backups),
    )
    signal.signal(signal.SIGTERM, _stop)
    try:
        service.run()
    except KeyboardInterrupt:
        return 0
    return 0


def _stop(signum: int, frame: object) -> None:
    """Turns SIGTERM into a normal interrupt so the service releases the bots before it exits."""
    raise KeyboardInterrupt


def _eval(config: Config, args: argparse.Namespace) -> int:
    director = StaticDirector() if args.baseline else _director(config, args.model)
    report = run_eval(director, config.fairness, config.limits, config.llm.timeouts_s, runs=args.runs)
    path = gating.save_report(config.gating.reports_dir, report)
    for tier, score in report["tiers"].items():
        print(f"{tier:6} score={score['score']:.3f} valid={score['valid']:.2f} passed={score['passed']:.2f} p95={score['p95_ms']}ms")
    for scenario_id, outcomes in _by_scenario(report["scenarios"]).items():
        print(f"  {sum(outcomes)}/{len(outcomes)} {scenario_id}")
    print(f"report: {path}")
    return 0


def _by_scenario(results: list[dict]) -> dict[str, list[bool]]:
    grouped: dict[str, list[bool]] = {}
    for result in results:
        grouped.setdefault(result["id"], []).append(result["passed"])
    return grouped


def _replay(config: Config, args: argparse.Namespace) -> int:
    summary = replay(_director(config, args.model), args.journal, config.fairness, config.limits)
    print(json.dumps(summary, indent=2))
    return 0


def _players(config: Config, args: argparse.Namespace) -> int:
    server = config.server
    print(Rcon(server.rcon_host, server.rcon_port, server.rcon_password()).human_count())
    return 0


def _watchdog(config: Config, args: argparse.Namespace) -> int:
    server = config.server
    rcon = Rcon(server.rcon_host, server.rcon_port, server.rcon_password())
    try:
        build_watchdog(config.watchdog, rcon, server.scriptdata / "events.log").run()
    except KeyboardInterrupt:
        return 0
    return 0


def _doctor(config: Config, args: argparse.Namespace) -> int:
    checks = []
    server = config.server
    checks.append(("game dir", server.game_dir.is_dir()))
    checks.append(("GSC installed", (server.game_dir / "userraw/scripts/mp/shotcaller.gsc").exists()))
    checks.append(("Bot Warfare installed", (server.game_dir / "userraw/z_svr_bots.iwd").exists()))
    events = server.scriptdata / "events.log"
    checks.append(("events.log present", events.exists()))
    try:
        checks.append(("rcon answers", Rcon(server.rcon_host, server.rcon_port, server.rcon_password()).alive()))
    except (OSError, ValueError):
        checks.append(("rcon answers", False))
    report = gating.load_report(config.gating.reports_dir, config.llm.model)
    checks.append((f"eval report for {config.llm.model or '(no model set)'}", report is not None))
    for name, ok in checks:
        print(f"{'ok  ' if ok else 'FAIL'} {name}")
    return 0 if all(ok for _, ok in checks) else 1


if __name__ == "__main__":
    sys.exit(main())
