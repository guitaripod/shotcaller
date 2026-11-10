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
    assert "TemporaryFileSystem=@HIDDEN@" in unit
    installer = (OPS / "iw4x-server" / "install.sh").read_text()
    candidates = re.search(r"for d in ([^;]+);", installer).group(1).split()
    assert {"/mnt", "/media", "/run/media", "/srv", "/run/user"} <= set(candidates)
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
    fill = int(values["bots_manage_fill"])
    slots = int(values["sv_maxclients"])
    assert values["bots_team"] == "custom" and values["bots_team_mode"] == "0"
    assert fill == 2 * team and values["bots_manage_fill_mode"] == "0"
    assert slots - fill == 2
    assert values["sv_randomBotNames"] == "1"


def vm_args(mode):
    out = subprocess.run([str(OPS / "vm" / "vm.sh"), "args", mode], capture_output=True, text=True, env={"VM_DIR": "/vm", "PATH": "/usr/bin:/bin"})
    assert out.returncode == 0, out.stderr
    return out.stdout.splitlines()


def netdev(lines):
    return next(line for line in lines if line.startswith("user,"))


def test_the_production_guest_is_cut_off_except_for_named_forwards():
    net = netdev(vm_args("run"))
    options = net.split(",")
    assert "restrict=on" in options and "restrict=off" not in options
    forwards = [o for o in options if o.startswith(("hostfwd=", "guestfwd="))]
    assert sorted(forwards) == sorted([
        "hostfwd=tcp:127.0.0.1:2222-:22",
        "hostfwd=tcp:127.0.0.1:28962-:28962",
        "hostfwd=tcp:127.0.0.1:1624-:1624",
        "guestfwd=tcp:10.0.2.100:8081-cmd:socat - TCP:127.0.0.1:8081",
    ])


def test_qemu_exposes_nothing_beyond_host_loopback():
    net = netdev(vm_args("run"))
    exposed = [(proto, bind) for proto, bind in re.findall(r"hostfwd=(\w+):([^-]*)-", net) if not bind.startswith("127.0.0.1")]
    assert exposed == []


def test_the_open_network_is_only_for_provisioning_and_exposes_nothing():
    net = netdev(vm_args("open"))
    assert "restrict" not in net and "udp" not in net
    assert re.findall(r"hostfwd=(\w+):([^-]*)-", net) == [("tcp", "127.0.0.1:2222")]


def test_the_vm_unit_hides_the_host_from_qemu():
    unit = (OPS / "systemd" / "iw4x-vm.service.in").read_text()
    for line in ("NoNewPrivileges=yes", "ProtectHome=tmpfs", "ProtectSystem=strict", "BindPaths=@DIR@", "BindReadOnlyPaths=@REPO@"):
        assert line in unit
    assert "TemporaryFileSystem=@HIDDEN@" in unit


def load_tunnel():
    spec = importlib.util.spec_from_file_location("udp_tunnel", OPS / "vm" / "udp_tunnel.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_the_udp_tunnel_carries_datagrams_both_ways_and_keeps_senders_apart():
    import asyncio
    import socket

    tunnel = load_tunnel()

    class Echo(asyncio.DatagramProtocol):
        def connection_made(self, transport):
            self.transport = transport

        def datagram_received(self, data, addr):
            self.transport.sendto(b"echo:" + data + b":" + str(addr[1]).encode(), addr)

    async def scenario():
        loop = asyncio.get_running_loop()
        probe = socket.socket(); probe.bind(("127.0.0.1", 0)); tunnel_port = probe.getsockname()[1]; probe.close()
        echo_transport, _ = await loop.create_datagram_endpoint(Echo, local_addr=("127.0.0.1", 0))
        game = echo_transport.get_extra_info("sockname")
        server = await asyncio.start_server(tunnel.GuestSide(game).handle, "127.0.0.1", tunnel_port)
        host = tunnel.HostSide(("127.0.0.1", tunnel_port))
        host_transport, _ = await loop.create_datagram_endpoint(lambda: host, local_addr=("127.0.0.1", 0))
        public = host_transport.get_extra_info("sockname")
        task = asyncio.create_task(host.run_tunnel())
        for _ in range(50):
            if host.writer is not None:
                break
            await asyncio.sleep(0.05)

        async def ask(payload):
            client = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            client.setblocking(False)
            client.sendto(payload, public)
            for _ in range(100):
                try:
                    return (await loop.run_in_executor(None, lambda: client.recvfrom(4096)))[0]
                except BlockingIOError:
                    await asyncio.sleep(0.02)
            raise AssertionError("no reply")

        first, second = await asyncio.gather(ask(b"one"), ask(b"two"))
        again = await ask(b"three")
        task.cancel(); server.close(); echo_transport.close(); host_transport.close()
        return first, second, again

    first, second, again = asyncio.run(scenario())
    assert first.startswith(b"echo:one:") and second.startswith(b"echo:two:") and again.startswith(b"echo:three:")
    assert first.rsplit(b":", 1)[1] != second.rsplit(b":", 1)[1]


def test_the_host_side_never_sends_to_an_address_it_has_not_heard_from():
    tunnel = load_tunnel()
    side = tunnel.HostSide(("127.0.0.1", 1))
    sent = []

    class Spy:
        def sendto(self, payload, addr):
            sent.append((payload, addr))

    side.transport = Spy()
    side.reply(999, b"forged")
    side.datagram_received(b"hello", ("203.0.113.9", 4000))
    side.reply(1, b"ok")
    assert sent == [(b"ok", ("203.0.113.9", 4000))]


def test_the_tap_network_gives_the_guest_its_own_address():
    net = next(line for line in vm_args("tap") if line.startswith("tap,"))
    options = net.split(",")
    assert "ifname=iw4x0" in options and "script=no" in options
    assert not any(o.startswith(("hostfwd=", "guestfwd=")) for o in options)


def test_the_guest_guard_keeps_the_vm_off_this_machine():
    out = subprocess.run([str(OPS / "vm" / "net.sh"), "plan"], capture_output=True, text=True, env={"PATH": "/usr/bin:/bin"})
    assert out.returncode == 0, out.stderr
    rules = out.stdout
    assert "table inet iw4x" in rules
    assert "ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16, 100.64.0.0/10 } drop" in rules
    assert "udp dport 28961 dnat ip to 10.44.0.2:28961" in rules
    assert "tcp dport 8081 accept" in rules
    assert "policy accept" in rules and "hook input" in rules and "hook forward" in rules
