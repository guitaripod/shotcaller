"""Configures a fresh IW4MAdmin for one IW4x server without the interactive wizard.

Runs the wizard with scripted answers, then patches the settings it wrote: webfront on and
whitelisted, bots ignored, the server's game log, and the server-side anti-cheat.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import select
import subprocess
import time
from pathlib import Path

WIZARD = [
    (r"Enable webfront\?", "y", False),
    (r"Enable multiple owners\?", "n", False),
    (r"server-side anti-cheat", "y", False),
    (r"profanity deterring", "y", False),
    (r"Please enter a selection", "19", True),
    (r"automatically determine your server IP", "n", True),
    (r"Enter server IP Address/Hostname", "{host}", True),
    (r"Enter server port", "{port}", True),
    (r"automatically determine your RCon password", "n", True),
    (r"Enter server RCon password", "{password}", True),
    (r"add another\?", "n", True),
]


def rcon_password(secrets: Path) -> str:
    """Reads the rcon password from the server's secrets.cfg; it is never printed."""
    return re.search(r'rcon_password "([^"]+)"', secrets.read_text()).group(1)


def next_answer(seen: str, pending: list[tuple[str, str, bool]]) -> tuple[int, str, int] | None:
    """The earliest prompt visible in the output as (index into pending, reply, end offset), or None.

    A first run asks four extra questions that later runs skip, so prompts are matched in the order
    they appear on screen and not in a fixed order.
    """
    best = None
    for index, (pattern, reply, _) in enumerate(pending):
        match = re.search(pattern, seen)
        if match and (best is None or match.start() < best[2].start()):
            best = (index, reply, match)
    return None if best is None else (best[0], best[1], best[2].end())


def run_wizard(app: Path, dotnet: Path, answers: list[tuple[str, str, bool]], timeout_s: float) -> None:
    """Feeds the wizard its answers as the prompts appear, then stops IW4MAdmin once it has saved the server."""
    env = dict(os.environ, DOTNET_ROOT=str(dotnet), DOTNET_CLI_TELEMETRY_OPTOUT="1")
    process = subprocess.Popen(
        [str(dotnet / "dotnet"), "Lib/IW4MAdmin.dll"],
        cwd=app,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        env=env,
    )
    pending, seen, deadline = list(answers), "", time.time() + timeout_s
    while time.time() < deadline:
        ready, _, _ = select.select([process.stdout], [], [], 0.5)
        if ready:
            chunk = os.read(process.stdout.fileno(), 65536).decode("utf-8", "replace")
            if not chunk:
                break
            seen += chunk
        while pending and (found := next_answer(seen, pending)):
            index, reply, end = found
            process.stdin.write((reply + "\n").encode())
            process.stdin.flush()
            seen = seen[end:]
            pending.pop(index)
        if not any(required for _, _, required in pending) and server_saved(app):
            break
    process.terminate()
    try:
        process.wait(10)
    except subprocess.TimeoutExpired:
        process.kill()
    missed = [pattern for pattern, _, required in pending if required]
    if missed:
        raise SystemExit(f"wizard stopped at: {missed[0]}")


def server_saved(app: Path) -> bool:
    """Whether the wizard has written the server it was asked about into the settings."""
    try:
        return bool(json.loads((app / "Configuration" / "IW4MAdminSettings.json").read_text()).get("Servers"))
    except (OSError, json.JSONDecodeError):
        return False


def patch(app: Path, log_path: Path, whitelist: list[str]) -> None:
    """Applies the settings the wizard has no prompt for."""
    settings_path = app / "Configuration" / "IW4MAdminSettings.json"
    settings = json.loads(settings_path.read_text())
    settings["Webfront"]["Enabled"] = True
    settings["Webfront"]["BindUrl"] = "http://127.0.0.1:1624"
    settings["Webfront"]["EnableConnectionWhitelist"] = True
    settings["Webfront"]["ConnectionWhitelist"] = whitelist + [f"::ffff:{host}" for host in whitelist if ":" not in host]
    settings["IgnoreBots"] = True
    settings["Servers"][0]["ManualLogPath"] = str(log_path)
    settings_path.write_text(json.dumps(settings, indent=2))
    stats_path = app / "Configuration" / "StatsPluginSettings.json"
    stats = json.loads(stats_path.read_text())
    stats["EnableAntiCheat"] = True
    stats_path.write_text(json.dumps(stats, indent=2))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--dotnet", type=Path, required=True)
    parser.add_argument("--game-dir", type=Path, required=True)
    parser.add_argument("--port", type=int, default=28961)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--allow", action="append", default=["127.0.0.1", "::1"], help="address allowed to open the webfront")
    args = parser.parse_args()
    password = rcon_password(args.game_dir / "userraw" / "secrets.cfg")
    answers = [
        (pattern, reply.format(host=args.host, port=args.port, password=password), required)
        for pattern, reply, required in WIZARD
    ]
    run_wizard(args.app, args.dotnet, answers, timeout_s=120)
    patch(args.app, args.game_dir / "userraw" / "games_mp.log", args.allow)
    print("IW4MAdmin configured for", f"{args.host}:{args.port}")


if __name__ == "__main__":
    main()
