"""The information barrier: what a director may see and where it may send a bot.

A director sees what a human commander on the server could know: scores, the roster,
the kill feed and where humans recently died. It is never given a living player's position,
and it may only send bots to death sites the game published, a few seconds after the fact.
"""

from __future__ import annotations

from dataclasses import dataclass

from .state import Anchor, MatchState


@dataclass(frozen=True, slots=True)
class FairnessPolicy:
    """Timing rules for which anchors are legal goals."""

    death_delay_ms: int = 6000
    death_max_age_ms: int = 300_000
    feed_entries: int = 12


def legal_anchors(state: MatchState, policy: FairnessPolicy) -> dict[str, Anchor]:
    """Death sites a director may name in a goal right now: old enough to be public, recent enough to matter."""
    return {
        anchor.id: anchor
        for anchor in state.anchors.values()
        if anchor.kind == "death"
        and state.now_ms - anchor.born_ms >= policy.death_delay_ms
        and state.now_ms - (anchor.last_ms or anchor.born_ms) <= policy.death_max_age_ms
    }


def fair_view(state: MatchState, policy: FairnessPolicy, standing: dict | None = None) -> dict:
    """The only picture of the match a director is given, as plain JSON-ready data."""
    legal = legal_anchors(state, policy)
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
        "death_sites": [_death_site(a, state.now_ms) for a in sorted(legal.values(), key=lambda a: (-a.count, -(a.last_ms or a.born_ms)))],
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


def _death_site(anchor: Anchor, now_ms: int) -> dict:
    return {"id": anchor.id, "deaths_here": anchor.count, "last_death_s_ago": (now_ms - (anchor.last_ms or anchor.born_ms)) // 1000}
