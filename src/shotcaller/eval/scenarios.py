"""Synthetic matches with a property each director answer must satisfy. The eval's ground truth."""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from typing import Any

from ..director.base import Tier
from ..orders import ChatLine, MatchOrder, Squad
from ..state import Anchor, Kill, MatchState, Player

Check = Callable[[Any, MatchState], tuple[bool, str]]


@dataclass(frozen=True, slots=True)
class Scenario:
    """One situation, the tier that answers it and the property its answer must have."""

    id: str
    tier: Tier
    build: Callable[[], MatchState]
    check: Check
    trigger: Callable[[MatchState], dict] | None = None
    repeats: bool = False


def build_state(human_kills: int, human_deaths: int, axis_skill: int = 3, allies_skill: int = 3, deaths_at: list[str] | None = None) -> MatchState:
    """A TDM state: one human on allies, four axis bots, three allied bots, optional human death anchors."""
    state = MatchState(map="mp_rust", gametype="war", slots=12, now_ms=300_000)
    state.scores.update(allies=human_kills * 100, axis=human_deaths * 100)
    state.players[0] = Player(0, "marcus", "allies", False, human_kills, human_deaths, human_kills * 100)
    for slot in range(1, 5):
        state.players[slot] = Player(slot, f"axis{slot}", "axis", True, 2, 3, 200, True, axis_skill)
    for slot in range(5, 8):
        state.players[slot] = Player(slot, f"ally{slot}", "allies", True, 3, 2, 300, True, allies_skill)
    for index, anchor_id in enumerate(deaths_at or []):
        state.anchors[anchor_id] = Anchor(anchor_id, "death", 700 + index * 40, 250, 0, 250_000 + index * 5000)
    state.feed.append(Kill(290_000, 0, "marcus", False, "allies", 2, "axis2", True, "m4a1_mp", "MOD_RIFLE_BULLET"))
    return state


def _axis_mean(squad: Squad, state: MatchState) -> float:
    ordered = {order.slot: order.skill for order in squad.bots if order.skill is not None}
    axis = [b for b in state.bots if b.team == "axis"]
    return sum(ordered.get(b.slot, b.skill or 0) for b in axis) / len(axis)


def _current_axis_mean(state: MatchState) -> float:
    axis = [b for b in state.bots if b.team == "axis"]
    return sum(b.skill or 0 for b in axis) / len(axis)


def _raises_skill(value: Any, state: MatchState) -> tuple[bool, str]:
    delta = _axis_mean(value, state) - _current_axis_mean(state)
    return delta >= 1, f"axis mean skill moved {delta:+.2f}"


def _lowers_skill(value: Any, state: MatchState) -> tuple[bool, str]:
    delta = _axis_mean(value, state) - _current_axis_mean(state)
    return delta <= -1, f"axis mean skill moved {delta:+.2f}"


def _stays_calm(value: Any, state: MatchState) -> tuple[bool, str]:
    delta = _axis_mean(value, state) - _current_axis_mean(state)
    return abs(delta) <= 1, f"axis mean skill moved {delta:+.2f}"


def _contests_deaths(value: Any, state: MatchState) -> tuple[bool, str]:
    cluster = {a.id for a in state.anchors.values() if a.kind == "death"}
    goals = [order.goal.anchor for order in value.bots if order.goal]
    ok = bool(set(goals) & cluster) and len(set(goals)) > 1 and len(goals) <= 2
    return ok, f"goals {goals} vs death sites {sorted(cluster)}"


def _raises_window(value: Any, _state: MatchState) -> tuple[bool, str]:
    ok = isinstance(value, MatchOrder) and ((value.skill_min or 0) >= 3 or (value.skill_max or 0) >= 6)
    return ok, f"match order {value}"


def _clean_match(value: Any, _state: MatchState) -> tuple[bool, str]:
    return isinstance(value, MatchOrder), "match order accepted"


def _bot_replies(value: Any, _state: MatchState) -> tuple[bool, str]:
    lines: list[ChatLine] = value
    ok = 1 <= len(lines) <= 2 and any(line.slot in (2, 5, 6, 7) for line in lines)
    return ok, f"{len(lines)} lines from {[line.slot for line in lines]}"


def _stays_quiet(value: Any, _state: MatchState) -> tuple[bool, str]:
    return len(value) <= 1, f"{len(value)} lines"


def _human_death_trigger(state: MatchState) -> dict:
    return {"type": "human_killed", "victim": "marcus", "attacker_slot": 2, "attacker": "axis2", "weapon": "m4a1_mp", "personas": {"2": "cocky veteran", "5": "cheerful rookie"}}


def _bot_duel_trigger(state: MatchState) -> dict:
    return {"type": "bot_killed_bot", "victim_slot": 3, "attacker_slot": 6, "weapon": "ak47_mp", "personas": {"3": "dry deadpan sniper", "6": "trash-talking showboat"}}


SCENARIOS: tuple[Scenario, ...] = (
    Scenario("human_dominating", Tier.SQUAD, lambda: build_state(18, 4), _raises_skill),
    Scenario("human_struggling", Tier.SQUAD, lambda: build_state(3, 14), _lowers_skill),
    Scenario("human_balanced", Tier.SQUAD, lambda: build_state(11, 10), _stays_calm),
    Scenario("human_camps_one_spot", Tier.SQUAD, lambda: build_state(12, 6, deaths_at=["w50", "w51", "w52"]), _contests_deaths, repeats=True),
    Scenario("match_too_easy", Tier.MATCH, lambda: build_state(24, 3), _raises_window),
    Scenario("match_steady", Tier.MATCH, lambda: build_state(10, 10), _clean_match),
    Scenario("chat_human_killed", Tier.CHAT, lambda: build_state(5, 6), _bot_replies, _human_death_trigger),
    Scenario("chat_bot_duel", Tier.CHAT, lambda: build_state(5, 6), _stays_quiet, _bot_duel_trigger),
)
