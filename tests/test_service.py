from __future__ import annotations

import json
from pathlib import Path

from shotcaller import gating, journal
from shotcaller.actuator import MatchActuator, OrderFile
from shotcaller.config import Config, ServerConfig
from shotcaller.director import StaticDirector, Tier
from shotcaller.director.base import Proposal
from shotcaller.journal import Journal
from shotcaller.service import Service
from shotcaller.tail import EventTail
from shotcaller.validate import Limits

from conftest import MATCH_LINES, InlineExecutor
from test_orders_actuator import FakeRcon


class ScriptedDirector:
    def __init__(self, answers: dict[Tier, dict | None], name: str = "scripted") -> None:
        self.name = name
        self.answers = answers
        self.calls: list[tuple[Tier, dict | None]] = []

    def decide(self, tier, view, trigger=None):
        self.calls.append((tier, trigger))
        data = self.answers.get(tier)
        return Proposal(data=data, raw=json.dumps(data), model=self.name, latency_ms=12, error=None if data is not None else "boom")


SQUAD_ANSWER = {"rationale": "go", "bots": [{"slot": 1, "skill": 4, "goal": {"anchor": "w41", "radius": 200}}]}
CHAT_ANSWER = {"lines": [{"slot": 1, "scope": "all", "text": "Gotcha."}]}
MATCH_ANSWER = {"rationale": "ease", "skill_min": 2}


def build(tmp_path: Path, director, enabled=None, lines=MATCH_LINES):
    scriptdata = tmp_path / "userraw" / "scriptdata" / "shotcaller"
    scriptdata.mkdir(parents=True)
    events = scriptdata / "events.log"
    events.write_text("\n".join(lines) + "\n")
    config = Config(server=ServerConfig(game_dir=tmp_path), limits=Limits(maps=("mp_rust",)))
    rcon = FakeRcon()
    service = Service(
        config,
        director,
        StaticDirector(),
        enabled or dict.fromkeys(Tier, True),
        EventTail(events),
        OrderFile(scriptdata / "orders.txt"),
        MatchActuator(rcon),
        Journal(tmp_path / "journal.jsonl"),
        InlineExecutor(),
    )
    return service, events, scriptdata / "orders.txt", rcon


def append(events: Path, *lines: str) -> None:
    with events.open("a") as handle:
        handle.write("\n".join(lines) + "\n")


def test_squad_orders_reach_the_order_file(tmp_path):
    service, _, orders, rcon = build(tmp_path, ScriptedDirector({Tier.SQUAD: SQUAD_ANSWER, Tier.MATCH: MATCH_ANSWER}))
    service.step(0.0)
    service.step(0.5)
    text = orders.read_text()
    assert "map|mp_rust" in text and "bot|1|skill=4|goal=w41:200:15" in text
    assert rcon.sent == ["set bots_skill_min 2"]


def test_squad_runs_on_its_interval_only(tmp_path):
    director = ScriptedDirector({Tier.SQUAD: SQUAD_ANSWER, Tier.MATCH: MATCH_ANSWER})
    service, *_ = build(tmp_path, director)
    for now in (0.0, 0.5, 5.0, 10.0, 14.9):
        service.step(now)
    assert [t for t, _ in director.calls].count(Tier.SQUAD) == 1
    service.step(15.1)
    assert [t for t, _ in director.calls].count(Tier.SQUAD) == 2


def test_orders_are_refreshed_by_the_heartbeat_so_they_do_not_expire(tmp_path):
    service, _, orders, _ = build(tmp_path, ScriptedDirector({Tier.SQUAD: SQUAD_ANSWER}), {Tier.SQUAD: True, Tier.MATCH: False, Tier.CHAT: False})
    service.step(0.0)
    service.step(0.5)
    first = orders.read_text().splitlines()[0]
    service.step(9.0)
    assert orders.read_text().splitlines()[0] != first


def test_a_human_death_triggers_one_chat_line_then_it_is_not_repeated(tmp_path):
    director = ScriptedDirector({Tier.SQUAD: SQUAD_ANSWER, Tier.CHAT: CHAT_ANSWER})
    service, events, orders, _ = build(tmp_path, director, {Tier.SQUAD: True, Tier.MATCH: False, Tier.CHAT: True})
    service.step(0.0)
    service.step(0.5)
    append(events, "6000|kill|vn=0|v=marcus|vt=allies|vb=0|w=m4a1_mp|mod=MOD_RIFLE_BULLET|x=1|y=2|z=3|an=1|a=bot1|at=axis|ab=1")
    service.step(1.0)
    service.step(1.5)
    chat_calls = [trigger for tier, trigger in director.calls if tier is Tier.CHAT]
    assert len(chat_calls) == 1 and chat_calls[0]["type"] == "human_killed" and chat_calls[0]["personas"]
    service.step(9.0)
    assert "chat|" not in orders.read_text()


def test_chat_is_rate_limited(tmp_path):
    director = ScriptedDirector({Tier.CHAT: CHAT_ANSWER})
    service, events, *_ = build(tmp_path, director, {Tier.SQUAD: False, Tier.MATCH: False, Tier.CHAT: True})
    kill = "6000|kill|vn=0|v=marcus|vt=allies|vb=0|w=m4a1_mp|mod=MOD_RIFLE_BULLET|x=1|y=2|z=3|an=1|a=bot1|at=axis|ab=1"
    for now in (0.0, 1.0, 2.0):
        append(events, kill)
        service.step(now)
    assert [t for t, _ in director.calls].count(Tier.CHAT) == 1


def test_a_new_map_clears_the_orders_and_names_the_new_map(tmp_path):
    service, events, orders, _ = build(tmp_path, ScriptedDirector({Tier.SQUAD: SQUAD_ANSWER}), {Tier.SQUAD: True, Tier.MATCH: False, Tier.CHAT: False})
    service.step(0.0)
    service.step(0.5)
    append(events, "0|hello|v=0.1.0|map=mp_terminal|gametype=war|slots=12")
    service.step(1.0)
    text = orders.read_text()
    assert "map|mp_terminal" in text and "bot|" not in text


def test_a_failing_model_falls_back_to_the_static_director_and_the_journal_records_it(tmp_path):
    service, _, orders, _ = build(tmp_path, ScriptedDirector({Tier.SQUAD: None}), {Tier.SQUAD: False, Tier.MATCH: False, Tier.CHAT: False})
    service.step(0.0)
    service.step(0.5)
    entries = [e for e in journal.read(tmp_path / "journal.jsonl") if e["kind"] == "decision"]
    assert entries and entries[0]["fallback"] is True and entries[0]["valid"] is True
    assert "seq|" in orders.read_text() or not orders.exists()


def test_a_failing_model_is_journaled_and_the_static_baseline_takes_over(tmp_path):
    service, _, orders, _ = build(tmp_path, ScriptedDirector({Tier.SQUAD: None}))
    service.step(0.0)
    service.step(0.5)
    entries = [e for e in journal.read(tmp_path / "journal.jsonl") if e["kind"] == "decision" and e["tier"] == "squad"]
    assert [(e["fallback"], e["valid"]) for e in entries] == [(False, False), (True, True)]
    assert entries[0]["orders"] is None
    assert "bot|1|skill=5" in orders.read_text()


def test_a_model_that_recovers_replaces_the_baseline(tmp_path):
    director = ScriptedDirector({Tier.SQUAD: None})
    service, _, orders, _ = build(tmp_path, director, {Tier.SQUAD: True, Tier.MATCH: False, Tier.CHAT: False})
    service.step(0.0)
    service.step(0.5)
    director.answers[Tier.SQUAD] = SQUAD_ANSWER
    service.step(16.0)
    service.step(16.5)
    assert "bot|1|skill=4|goal=w41:200:15" in orders.read_text()


def test_spectating_humans_do_not_wake_the_director(tmp_path):
    spectating = [line.replace("pt=allies|pb=0", "pt=spectator|pb=0") for line in MATCH_LINES]
    director = ScriptedDirector({Tier.SQUAD: SQUAD_ANSWER})
    service, *_ = build(tmp_path, director, lines=spectating)
    service.step(0.0)
    service.step(0.5)
    assert director.calls == []


def test_no_humans_means_no_director_calls(tmp_path):
    bots_only = [line for line in MATCH_LINES if "pb=0" not in line]
    director = ScriptedDirector({Tier.SQUAD: SQUAD_ANSWER})
    service, *_ = build(tmp_path, director, lines=bots_only)
    service.step(0.0)
    service.step(0.5)
    assert director.calls == []


def test_release_writes_an_empty_short_lived_order_set(tmp_path):
    service, _, orders, _ = build(tmp_path, ScriptedDirector({Tier.SQUAD: SQUAD_ANSWER}))
    service.step(0.0)
    service.step(0.5)
    service.release()
    text = orders.read_text()
    assert "ttl|1000" in text and "bot|" not in text


def test_end_event_journals_the_outcome(tmp_path):
    service, events, *_ = build(tmp_path, ScriptedDirector({}))
    append(events, "99000|end|allies=7500|axis=4100")
    service.step(0.0)
    outcomes = [e for e in journal.read(tmp_path / "journal.jsonl") if e["kind"] == "outcome"]
    assert outcomes and outcomes[0]["scores"] == {"allies": 7500, "axis": 4100}
