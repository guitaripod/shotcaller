from __future__ import annotations

import importlib.util
import re
import subprocess
from pathlib import Path

import pytest

OPS = Path(__file__).resolve().parent.parent / "ops"
SCRIPTS = sorted(OPS.rglob("*.sh"))


def load_setup():
    spec = importlib.util.spec_from_file_location("iw4madmin_setup", OPS / "iw4madmin" / "setup.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def answer_all(setup, screen: str) -> list[str]:
    """Feeds a transcript to the matcher the way the wizard loop does and returns the replies it gave."""
    pending = [(p, r.format(host="h", port=1, password="p"), req) for p, r, req in setup.WIZARD]
    replies = []
    while found := setup.next_answer(screen, pending):
        index, reply, end = found
        replies.append(reply)
        screen = screen[end:]
        pending.pop(index)
    return replies


@pytest.mark.parametrize("script", SCRIPTS, ids=lambda p: str(p.relative_to(OPS)))
def test_every_shell_script_parses(script):
    assert subprocess.run(["bash", "-n", str(script)], capture_output=True).returncode == 0


@pytest.mark.parametrize("script", SCRIPTS, ids=lambda p: str(p.relative_to(OPS)))
def test_shell_scripts_carry_no_inline_comments(script):
    inline = [line for line in script.read_text().splitlines()[1:] if re.match(r"^\s+#", line)]
    assert inline == []


def test_the_first_run_questions_are_answered_in_screen_order():
    setup = load_setup()
    first_run = (
        "Enable webfront? [y/n]: Enable multiple owners? [y/n]: Enable server-side anti-cheat (IW4 only)? [y/n]: "
        "Enable profanity deterring? [y/n]: Please enter a selection [default 0]: "
    )
    assert answer_all(setup, first_run) == ["y", "n", "y", "y", "19"]


def test_later_runs_skip_the_opening_questions():
    setup = load_setup()
    assert answer_all(setup, "Please enter a selection [default 0]: Would you like IW4MAdmin to try to automatically determine your server IP? [y/n]: ") == ["19", "n"]


def test_only_the_opening_questions_are_optional():
    setup = load_setup()
    optional = [pattern for pattern, _, required in setup.WIZARD if not required]
    assert optional == [r"Enable webfront\?", r"Enable multiple owners\?", "server-side anti-cheat", "profanity deterring"]


def test_the_wizard_password_comes_from_secrets_and_is_not_in_the_prompt_table(tmp_path):
    setup = load_setup()
    secrets = tmp_path / "secrets.cfg"
    secrets.write_text('set rcon_password "abc123"\n')
    assert setup.rcon_password(secrets) == "abc123"
    assert "abc123" not in repr(setup.WIZARD)


def test_patch_turns_on_the_whitelist_the_anti_cheat_and_ignores_bots(tmp_path):
    import json

    setup = load_setup()
    config = tmp_path / "Configuration"
    config.mkdir()
    (config / "IW4MAdminSettings.json").write_text(json.dumps({"Webfront": {}, "Servers": [{}]}))
    (config / "StatsPluginSettings.json").write_text(json.dumps({"EnableAntiCheat": False}))
    setup.patch(tmp_path, tmp_path / "games_mp.log", ["127.0.0.1", "::1", "100.64.0.9"])
    settings = json.loads((config / "IW4MAdminSettings.json").read_text())
    assert settings["IgnoreBots"] is True
    assert settings["Webfront"]["EnableConnectionWhitelist"] is True
    assert "::ffff:100.64.0.9" in settings["Webfront"]["ConnectionWhitelist"]
    assert "::ffff:::1" not in settings["Webfront"]["ConnectionWhitelist"]
    assert settings["Servers"][0]["ManualLogPath"].endswith("games_mp.log")
    assert json.loads((config / "StatsPluginSettings.json").read_text())["EnableAntiCheat"] is True


def test_the_units_restart_and_start_after_what_they_depend_on():
    admin = (OPS / "systemd" / "iw4madmin.service.in").read_text()
    assert "Restart=always" in admin and "After=network-online.target iw4x-server.service" in admin
    assert "Restart=always" in (OPS / "systemd" / "shotcaller-watchdog.service").read_text()
    assert "@BASE@/run.sh" in (OPS / "systemd" / "iw4x-server.service.in").read_text()


def test_the_update_never_touches_the_servers_own_files():
    script = (OPS / "iw4x-server" / "update.sh").read_text()
    for kept in ("/userraw/server.cfg", "/userraw/secrets.cfg", "/userraw/scriptdata/", "/userraw/scripts/_customcallbacks.gsc", "/players/"):
        assert f"--exclude={kept}" in script


def test_the_game_server_unit_is_sandboxed():
    unit = (OPS / "systemd" / "iw4x-server.service.in").read_text()
    for line in ("NoNewPrivileges=yes", "ProtectSystem=strict", "ProtectHome=tmpfs", "PrivateTmp=yes", "BindPaths=@BASE@", "RestrictNamespaces=yes"):
        assert line in unit
    hidden = next(l for l in unit.splitlines() if l.startswith("TemporaryFileSystem="))
    assert "/run/user" in hidden and "/mnt" in hidden
    assert "Environment=HOME=@BASE@/home" in unit


def test_bot_names_are_valid_and_untagged_by_default():
    lines = [line.strip() for line in (OPS / "iw4x-server" / "bots.txt").read_text().splitlines() if line.strip()]
    names = [line.split(",")[0] for line in lines]
    tags = [line.split(",")[1] for line in lines if "," in line]
    assert len(names) >= 60 and len({n.lower() for n in names}) == len(names)
    assert all(1 <= len(n) <= 15 and not set(n) & set("^\\;\"") for n in names)
    assert all(1 <= len(t) <= 4 for t in tags) and "BOT" not in tags
    assert len(tags) < len(names) / 4


def test_the_server_config_keeps_both_teams_full_and_leaves_room_to_join():
    template = (OPS / "iw4x-server" / "server.cfg.template").read_text()
    values = dict(re.findall(r'set (\w+) "([^"]*)"', template))
    team = int(values["bots_team_amount"])
    assert values["bots_team"] == "custom" and values["bots_team_mode"] == "0"
    assert int(values["bots_manage_fill"]) == 2 * team and values["bots_manage_fill_mode"] == "0"
    assert int(values["sv_maxclients"]) > int(values["bots_manage_fill"])
    assert values["sv_randomBotNames"] == "1"
