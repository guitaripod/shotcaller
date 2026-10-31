"""Runs a director over the scenarios and scores it per tier."""

from __future__ import annotations

import statistics
from dataclasses import asdict, dataclass, field
from datetime import UTC, datetime

from .. import schema
from ..director.base import Director, Tier
from ..fairness import FairnessPolicy, fair_view
from ..orders import Squad, squad_to_dict
from ..pipeline import resolve
from ..validate import Limits
from .scenarios import SCENARIOS, Scenario

WEIGHTS = {"valid": 0.3, "passed": 0.5, "latency": 0.2}
DEFAULT_BUDGETS_S = {"match": 30.0, "squad": 25.0, "chat": 8.0}


@dataclass(slots=True)
class ScenarioResult:
    """The outcome of one scenario."""

    id: str
    tier: str
    valid: bool
    passed: bool
    detail: str
    latency_ms: int
    issues: list[str] = field(default_factory=list)
    similarity: float | None = None


@dataclass(slots=True)
class TierScore:
    """Aggregates for one tier."""

    n: int
    valid: float
    passed: float
    latency_ok: float
    p50_ms: int
    p95_ms: int
    score: float


def run_scenario(director: Director, scenario: Scenario, policy: FairnessPolicy, limits: Limits) -> ScenarioResult:
    """Asks the director, validates through the production pipeline and checks the scenario's property."""
    state = scenario.build()
    trigger = scenario.trigger(state) if scenario.trigger else None
    view = fair_view(state, policy)
    proposal = director.decide(scenario.tier, view, trigger)
    resolved = resolve(scenario.tier, proposal, state, policy, limits)
    result = ScenarioResult(scenario.id, scenario.tier.value, resolved.valid, False, "", proposal.latency_ms, resolved.issues)
    if resolved.valid:
        result.passed, result.detail = scenario.check(resolved.value, state)
        if scenario.repeats and isinstance(resolved.value, Squad):
            result.similarity = _repeat_similarity(director, scenario, state, resolved.value, policy, limits)
            result.passed = result.passed and result.similarity < 1.0
    else:
        result.detail = "; ".join(resolved.issues)
    return result


def _repeat_similarity(director: Director, scenario: Scenario, state, first: Squad, policy: FairnessPolicy, limits: Limits) -> float:
    view = fair_view(state, policy, squad_to_dict(first))
    second = resolve(scenario.tier, director.decide(scenario.tier, view), state, policy, limits)
    if not second.valid or not isinstance(second.value, Squad) or second.value.is_empty():
        return 0.0
    before, after = _signature(first), _signature(second.value)
    return len(before & after) / max(1, len(before | after))


def _signature(squad: Squad) -> set[tuple]:
    return {(b.slot, b.skill, b.goal.anchor if b.goal else None) for b in squad.bots}


def score_tier(results: list[ScenarioResult], budget_s: float) -> TierScore:
    """Combines validity, property pass rate and latency into one number between 0 and 1."""
    count = len(results)
    valid = sum(r.valid for r in results) / count
    passed = sum(r.passed for r in results) / count
    latency_ok = sum(r.latency_ms <= budget_s * 1000 for r in results) / count
    latencies = sorted(r.latency_ms for r in results)
    p95 = latencies[min(count - 1, int(0.95 * count))]
    score = WEIGHTS["valid"] * valid + WEIGHTS["passed"] * passed + WEIGHTS["latency"] * latency_ok
    return TierScore(count, valid, passed, latency_ok, int(statistics.median(latencies)), p95, round(score, 3))


def run_eval(director: Director, policy: FairnessPolicy, limits: Limits, budgets_s: dict[str, float] | None = None, scenarios: tuple[Scenario, ...] = SCENARIOS) -> dict:
    """Runs every scenario and returns a JSON-ready report with per-tier scores."""
    budgets = {**DEFAULT_BUDGETS_S, **(budgets_s or {})}
    results = [run_scenario(director, s, policy, limits) for s in scenarios]
    tiers = {}
    for tier in Tier:
        subset = [r for r in results if r.tier == tier.value]
        if subset:
            tiers[tier.value] = asdict(score_tier(subset, budgets[tier.value]))
    return {
        "schema": schema.VERSION,
        "model": director.name,
        "created": datetime.now(UTC).isoformat(timespec="seconds"),
        "tiers": tiers,
        "scenarios": [asdict(r) for r in results],
    }
