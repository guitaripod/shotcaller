from __future__ import annotations

import json

from shotcaller import journal
from shotcaller.director import Tier
from shotcaller.events import parse_line
from shotcaller.fairness import FairnessPolicy, fair_view
from shotcaller.journal import Journal
from shotcaller.watchdog import Watchdog, WatchdogConfig

from conftest import MATCH_LINES, lines_to_state
from test_service import SQUAD_ANSWER, ScriptedDirector, build


def watchdog(rcon_ok: list[bool], log_age: list[float | None], restarts: list[str]) -> Watchdog:
    config = WatchdogConfig(failures=3, stale_s=90, grace_s=120, cooldown_s=300)
    return Watchdog(config, lambda: rcon_ok.pop(0) if len(rcon_ok) > 1 else rcon_ok[0], lambda: log_age[0], restarts.append)


def test_watchdog_restarts_after_consecutive_failures_then_stays_quiet():
    restarts: list[str] = []
    dog = watchdog([False], [None], restarts)
    assert [dog.check(t) for t in (0, 20, 40)] == ["suspect", "suspect", "restarted"]
    assert restarts == ["iw4x-server"]
    assert dog.check(60) == "quiet" and dog.check(150) == "quiet"
    assert restarts == ["iw4x-server"]


def test_watchdog_never_restarts_a_server_that_answers_or_is_loading_a_map():
    restarts: list[str] = []
    answering = watchdog([True], [None], restarts)
    assert [answering.check(t) for t in range(0, 400, 20)] == ["ok"] * 20
    loading = watchdog([False], [30.0], restarts)
    assert [loading.check(t) for t in range(0, 400, 20)] == ["ok"] * 20
    assert restarts == []


def test_watchdog_one_good_check_resets_the_count_and_the_cooldown_limits_restarts():
    restarts: list[str] = []
    dog = watchdog([False, False, True, False, False, False, False, False, False, False, False], [None], restarts)
    assert [dog.check(t) for t in (0, 20, 40)] == ["suspect", "suspect", "ok"]
    assert [dog.check(t) for t in (60, 80, 100)] == ["suspect", "suspect", "restarted"]
    assert [dog.check(t) for t in (130, 200)] == ["quiet", "quiet"]
    assert [dog.check(t) for t in (250, 270, 290)] == ["suspect", "suspect", "suspect"]
    assert len(restarts) == 1


def test_journal_rotates_and_keeps_a_fixed_number_of_backups(tmp_path):
    path = tmp_path / "journal.jsonl"
    log = Journal(path, max_bytes=200, backups=2)
    for index in range(40):
        log.record("decision", n=index, filler="x" * 30)
    names = sorted(p.name for p in tmp_path.iterdir())
    assert names == ["journal.jsonl", "journal.jsonl.1", "journal.jsonl.2"]
    newest = [e["n"] for e in journal.read(path)]
    assert newest and newest[-1] == 39
    assert all(json.loads(line) for line in path.with_name("journal.jsonl.1").read_text().splitlines())


def test_death_sites_count_repeat_deaths_and_rank_hottest_first(match_state):
    for t in (200, 300, 400):
        match_state.apply(parse_line(f"{t}|anchor|id=w5|kind=death|x=1|y=1|z=0"))
    match_state.apply(parse_line("250|anchor|id=w6|kind=death|x=2|y=2|z=0"))
    view = fair_view(match_state, FairnessPolicy())
    assert [(s["id"], s["deaths_here"]) for s in view["death_sites"]][:2] == [("w5", 3), ("w6", 1)]


def test_a_site_stays_legal_while_it_keeps_getting_deaths(match_state):
    policy = FairnessPolicy(death_delay_ms=6000, death_max_age_ms=60_000)
    match_state.apply(parse_line("100|anchor|id=w5|kind=death|x=1|y=1|z=0"))
    match_state.apply(parse_line("65000|anchor|id=w5|kind=death|x=1|y=1|z=0"))
    match_state.now_ms = 70_000
    assert "w5" in {s["id"] for s in fair_view(match_state, policy)["death_sites"]}


def test_humans_on_both_teams_hold_the_director_and_release_the_bots(tmp_path):
    director = ScriptedDirector({Tier.SQUAD: SQUAD_ANSWER})
    service, events, orders, _ = build(tmp_path, director, {Tier.SQUAD: True, Tier.MATCH: False})
    service.step(0.0)
    service.step(0.5)
    assert "bot|1|skill=4" in orders.read_text()
    calls = len(director.calls)
    with events.open("a") as handle:
        handle.write("11000|join|pn=3|p=second|pt=axis|pb=0\n11000|p|pn=3|p=second|pt=axis|pb=0|k=0|d=0|s=0|alive=1\n")
    service.step(20.0)
    service.step(40.0)
    assert "bot|" not in orders.read_text()
    assert len(director.calls) == calls


def test_a_single_team_of_humans_is_not_held(tmp_path):
    state = lines_to_state(MATCH_LINES + ["11000|join|pn=3|p=second|pt=allies|pb=0"])
    assert state.human_teams() == {"allies"}


def test_the_vote_result_is_journaled(tmp_path):
    service, events, _, _ = build(tmp_path, ScriptedDirector({}))
    with events.open("a") as handle:
        handle.write("99000|vote|winner=mp_terminal|choices=mp_rust,mp_terminal,mp_afghan|counts=0,2,1\n")
    service.step(0.0)
    votes = [e for e in journal.read(tmp_path / "journal.jsonl") if e["kind"] == "vote"]
    assert votes == [{**votes[0], "winner": "mp_terminal", "choices": ["mp_rust", "mp_terminal", "mp_afghan"], "counts": ["0", "2", "1"]}]


STATUS = """print
map: mp_rust
num score ping guid                             name            lastmsg address               qport rate
--- ----- ---- -------------------------------- --------------- ------- --------------------- ----- -----
  0   200  999                            bot16 RektInator^7        71300 00000000.000000000000:4096 99999
  1     0   14 1a7f51a364dfd6c8               TestA^7               900 192.168.1.197:28990  1234 99999
  2     0   31 9c0e1d2b3a4f5e6d     /dev/console^7               700 192.168.1.58:28960  4321 99999
"""


def test_human_count_ignores_bots():
    from shotcaller.rcon import count_humans

    assert count_humans(STATUS) == 2
    assert count_humans("map: mp_rust\n") == 0
    assert count_humans("") == 0


def test_a_player_with_a_negative_qport_is_still_counted():
    from shotcaller.rcon import count_humans

    status = (
        "map: mp_afghan\n"
        "num score ping guid                             name            lastmsg address               qport rate\n"
        "--- ----- ---- -------------------------------- --------------- ------- --------------------- ----- -----\n"
        "  0   800  999                             bot0 ChunkyMonkey^7     272100 00000000.000000000000:0    1 99999\n"
        " 12     0  102                 1a7f51a364dfd6c8 TestA^7               200 127.0.0.1:49994       -11514 99999\n"
    )
    assert count_humans(status) == 1
