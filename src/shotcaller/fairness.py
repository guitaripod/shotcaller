"""The information barrier: what a director may see and where it may send a bot.

A director sees what a human commander on the server could know: scores, the roster,
the kill feed and map anchors. It is never given a living player's position, and it may
only send bots to anchors the game itself published, with human death sites delayed.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

from .state import TEAMS, Anchor, MatchState


@dataclass(frozen=True, slots=True)
class FairnessPolicy:
    """Timing rules for which anchors are legal goals."""

    death_delay_ms: int = 6000
    death_max_age_ms: int = 300_000
    feed_entries: int = 12


def legal_anchors(state: MatchState, policy: FairnessPolicy) -> dict[str, Anchor]:
    """Anchors a director may name in a goal right now."""
    legal: dict[str, Anchor] = {}
    for anchor in state.anchors.values():
        age = state.now_ms - anchor.born_ms
        if anchor.kind == "death" and not policy.death_delay_ms <= age <= policy.death_max_age_ms:
            continue
        legal[anchor.id] = anchor
    return legal


def fair_view(state: MatchState, policy: FairnessPolicy, standing: dict | None = None) -> dict:
    """The only picture of the match a director is given, as plain JSON-ready data."""
    legal = legal_anchors(state, policy)
    homes = {a.team: a for a in legal.values() if a.kind == "home"}
    return {
        "standing_orders": standing or {"teams": [], "bots": []},
        "map": state.map,
        "gametype": state.gametype,
        "elapsed_s": state.now_ms // 1000,
        "scores": dict(state.scores),
        "summary": _summary(state),
        "humans": [_human(p) for p in state.humans],
        "bots": [_bot(p, state.side_of(p)) for p in sorted(state.bots, key=lambda p: p.slot)],
        "kill_feed": [_kill(k, state.now_ms) for k in list(state.feed)[-policy.feed_entries :]],
        "anchors": [_anchor(a, homes, state.now_ms) for a in legal.values()],
    }


def _summary(state: MatchState) -> dict:
    kd = state.human_kd()
    allies, axis = state.scores["allies"], state.scores["axis"]
    return {
        "human_kd": round(kd, 2) if kd is not None else None,
        "human_state": _human_state(kd),
        "leading_team": "allies" if allies > axis else "axis" if axis > allies else "tied",
        "score_gap": abs(allies - axis),
    }


def _human_state(kd: float | None) -> str:
    if kd is None:
        return "no humans"
    if kd >= 1.8:
        return "dominating: make the opposing bots tougher"
    if kd <= 0.7:
        return "struggling: make the opposing bots easier"
    return "balanced: leave things mostly alone"


def _human(player) -> dict:
    return {"name": player.name, "team": player.team, "kills": player.kills, "deaths": player.deaths}


def _bot(player, side: str | None) -> dict:
    return {
        "slot": player.slot,
        "team": player.team,
        "side": side,
        "kills": player.kills,
        "deaths": player.deaths,
        "alive": player.alive,
        "skill": player.skill,
        "camp": player.camp,
        "sprint": player.sprint,
    }


def _kill(kill, now_ms: int) -> dict:
    return {
        "age_s": max(0, (now_ms - kill.t) // 1000),
        "victim": kill.victim_name,
        "victim_slot": kill.victim,
        "victim_is_bot": kill.victim_bot,
        "attacker": kill.attacker_name or None,
        "attacker_slot": kill.attacker,
        "attacker_is_bot": kill.attacker_bot if kill.attacker is not None else None,
        "weapon": kill.weapon,
    }


def _anchor(anchor: Anchor, homes: dict[str, Anchor], now_ms: int) -> dict:
    view = {"id": anchor.id, "kind": anchor.kind, "team": anchor.team}
    for team in TEAMS:
        if team in homes:
            view[f"distance_to_{team}_home"] = _distance(anchor, homes[team])
    if anchor.kind == "death":
        view["human_died_here_s_ago"] = (now_ms - anchor.born_ms) // 1000
    return view


def _distance(a: Anchor, b: Anchor) -> int:
    return int(math.hypot(a.x - b.x, a.y - b.y))
