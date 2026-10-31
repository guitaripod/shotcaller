from __future__ import annotations

import json

from shotcaller.events import parse_line
from shotcaller.fairness import FairnessPolicy, fair_view, legal_anchors
from shotcaller.validate import Limits, extract_json, validate_match, validate_squad

POLICY = FairnessPolicy()
LIMITS = Limits(maps=("mp_rust", "mp_terminal"))


def test_extract_json_handles_fences_and_think_tags():
    assert extract_json('<think>hmm {not json}</think>\n```json\n{"a": 1}\n```') == {"a": 1}
    assert extract_json('Sure! {"a": {"b": 2}} done') == {"a": {"b": 2}}
    assert extract_json("no json here") is None
    assert extract_json("[1, 2]") is None


def test_squad_drops_unknown_slots_and_illegal_anchors(match_state):
    legal = legal_anchors(match_state, POLICY)
    proposal = {
        "bots": [
            {"slot": 1, "goal": {"anchor": "w41", "radius": 5000}},
            {"slot": 2, "goal": {"anchor": "w9999"}},
            {"slot": 0, "skill": 7},
            {"slot": 99, "skill": 7},
        ],
    }
    result = validate_squad(proposal, match_state, legal, LIMITS).value
    assert [b.slot for b in result.bots] == [1]
    assert (result.bots[0].goal.anchor, result.bots[0].goal.radius, result.bots[0].goal.seconds) == ("w41", 1000, 15)


def test_squad_caps_how_many_bots_may_be_on_a_mission(match_state):
    match_state.apply(parse_line("9000|join|pn=3|p=bot3|pt=axis|pb=1"))
    legal = legal_anchors(match_state, POLICY)
    goal = {"goal": {"anchor": "w41"}}
    result = validate_squad({"bots": [{"slot": 1, **goal}, {"slot": 2, **goal}, {"slot": 3, **goal}]}, match_state, legal, LIMITS)
    assert [b.slot for b in result.value.bots] == [1, 2]
    assert any("mission cap" in issue for issue in result.issues)


def test_squad_limits_skill_step(match_state):
    legal = legal_anchors(match_state, POLICY)
    result = validate_squad({"bots": [{"slot": 1, "skill": 7}, {"slot": 2, "skill": 1}]}, match_state, legal, LIMITS)
    skills = {b.slot: b.skill for b in result.value.bots}
    assert skills == {1: 5, 2: 1}
    assert result.issues


def test_only_death_sites_are_goals_and_camp_or_home_anchors_are_not(match_state):
    match_state.apply(parse_line("200|anchor|id=w5|kind=camp|x=1|y=1|z=0"))
    match_state.apply(parse_line("200|anchor|id=w6|kind=home|x=1|y=1|z=0"))
    assert set(legal_anchors(match_state, POLICY)) == {"w41"}


def test_death_anchor_is_illegal_until_the_delay_passes(match_state):
    match_state.apply(parse_line("8000|anchor|id=w77|kind=death|x=5|y=5|z=0"))
    match_state.now_ms = 8000 + POLICY.death_delay_ms - 1
    assert "w77" not in legal_anchors(match_state, POLICY)
    match_state.now_ms = 8000 + POLICY.death_delay_ms
    assert "w77" in legal_anchors(match_state, POLICY)
    match_state.now_ms = 8000 + POLICY.death_max_age_ms + 1
    assert "w77" not in legal_anchors(match_state, POLICY)


def test_fair_view_never_contains_a_live_position(match_state):
    view = fair_view(match_state, POLICY)
    text = json.dumps(view)
    for forbidden in ('"x"', '"y"', '"z"', "origin", "position"):
        assert forbidden not in text
    assert [site["id"] for site in view["death_sites"]] == ["w41"]


def test_match_order_clamps_and_checks_the_map(match_state):
    result = validate_match({"skill_min": 0, "skill_max": 9, "bot_count": 50, "next_map": "mp_nowhere"}, match_state, LIMITS)
    order = result.value
    assert (order.skill_min, order.skill_max, order.bot_count, order.next_map) == (1, 7, 11, None)
    ok = validate_match({"next_map": "mp_terminal"}, match_state, LIMITS).value
    assert ok.next_map == "mp_terminal"


def test_match_order_drops_an_inverted_window(match_state):
    result = validate_match({"skill_min": 6, "skill_max": 2}, match_state, LIMITS)
    assert result.value.skill_min is None and result.issues
