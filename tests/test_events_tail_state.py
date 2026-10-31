from __future__ import annotations

from shotcaller.events import parse_line
from shotcaller.tail import EventTail

from conftest import MATCH_LINES, lines_to_state


def test_parse_line_reads_type_and_fields():
    event = parse_line("1500|kill|v=a|vb=1|w=ak47_mp\n")
    assert event is not None
    assert (event.t, event.type) == (1500, "kill")
    assert event.get_str("w") == "ak47_mp"
    assert event.get_int("missing", 7) == 7


def test_parse_line_rejects_garbage():
    assert parse_line("") is None
    assert parse_line("not|an|event") is None
    assert parse_line("12") is None


def test_tail_reads_only_complete_lines(tmp_path):
    path = tmp_path / "events.log"
    tail = EventTail(path)
    assert tail.poll() == ([], False)
    path.write_text("1|hello|map=mp_rust\n2|snap|allies=1")
    events, restarted = tail.poll()
    assert [e.type for e in events] == ["hello"] and not restarted
    with path.open("a") as handle:
        handle.write("|axis=2\n")
    events, _ = tail.poll()
    assert [e.type for e in events] == ["snap"]
    assert events[0].get_int("axis") == 2


def test_tail_detects_truncation(tmp_path):
    path = tmp_path / "events.log"
    path.write_text("1|hello|map=a\n2|snap|allies=1\n")
    tail = EventTail(path)
    tail.poll()
    path.write_text("0|hello|map=b\n")
    events, restarted = tail.poll()
    assert restarted
    assert events[0].get_str("map") == "b"


def test_state_tracks_roster_scores_and_anchors():
    state = lines_to_state(MATCH_LINES)
    assert state.map == "mp_rust" and state.slots == 12
    assert [p.name for p in state.humans] == ["marcus"]
    assert sorted(p.slot for p in state.bots) == [1, 2]
    assert state.scores == {"allies": 300, "axis": 200}
    assert state.human_kd() == 4.5
    assert state.anchors["w41"].kind == "death"
    assert state.players[1].skill == 3


def test_state_resets_on_new_map():
    state = lines_to_state(MATCH_LINES)
    state.apply(parse_line("9000|hello|map=mp_terminal|gametype=war|slots=12"))
    assert state.map == "mp_terminal"
    assert not state.players and not state.anchors


def test_state_records_kill_feed():
    state = lines_to_state(MATCH_LINES)
    state.apply(parse_line("6000|kill|vn=0|v=marcus|vt=allies|vb=0|w=m4a1_mp|mod=MOD_RIFLE_BULLET|x=1|y=2|z=3|an=1|a=bot1|at=axis|ab=1"))
    kill = state.feed[-1]
    assert (kill.victim_name, kill.attacker_name, kill.attacker_bot) == ("marcus", "bot1", True)
    assert state.recent_human_deaths(5000)
