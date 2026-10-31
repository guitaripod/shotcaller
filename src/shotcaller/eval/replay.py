"""Re-asks a director every decision a journal recorded, to compare models on real matches."""

from __future__ import annotations

import statistics
from pathlib import Path

from .. import journal
from ..director.base import Director, Tier
from ..fairness import FairnessPolicy
from ..orders import Squad, squad_to_dict
from ..pipeline import resolve
from ..state import Anchor, MatchState, Player
from ..validate import Limits


def replay(director: Director, path: Path, policy: FairnessPolicy, limits: Limits) -> dict:
    """Runs the director on each recorded view and reports validity, latency and agreement with what was done."""
    state = MatchState()
    latencies: list[int] = []
    valid = total = agree = comparable = 0
    for entry in journal.read(path):
        if entry.get("kind") != "decision" or not entry.get("view"):
            continue
        tier = Tier(entry["tier"])
        proposal = director.decide(tier, entry["view"], entry.get("trigger"))
        total += 1
        latencies.append(proposal.latency_ms)
        _hydrate(state, entry["view"])
        resolved = resolve(tier, proposal, state, policy, limits)
        valid += resolved.valid
        if resolved.valid and tier is Tier.SQUAD and isinstance(resolved.value, Squad) and entry.get("orders") is not None:
            comparable += 1
            agree += squad_to_dict(resolved.value) == entry["orders"]
    return {
        "model": director.name,
        "decisions": total,
        "valid_rate": round(valid / total, 3) if total else None,
        "identical_to_recorded_squad_orders": round(agree / comparable, 3) if comparable else None,
        "p50_ms": int(statistics.median(latencies)) if latencies else None,
        "max_ms": max(latencies) if latencies else None,
    }


def _hydrate(state: MatchState, view: dict) -> None:
    """Rebuilds just enough roster from a recorded view for the validator to check slots."""
    state.map, state.gametype = view["map"], view["gametype"]
    state.now_ms = view["elapsed_s"] * 1000
    state.players = {
        b["slot"]: Player(b["slot"], f"bot{b['slot']}", b["team"], True, b["kills"], b["deaths"], 0, b["alive"], b["skill"], b["camp"], b["sprint"])
        for b in view["bots"]
    }
    state.anchors = {
        a["id"]: Anchor(a["id"], a["kind"], a["team"], 0, 0, 0, state.now_ms - a.get("human_died_here_s_ago", 600) * 1000) for a in view["anchors"]
    }
