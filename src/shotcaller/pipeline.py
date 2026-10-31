"""The single path from a director's proposal to safe orders, shared by the live service and the eval."""

from __future__ import annotations

from dataclasses import dataclass, field

from .director.base import Proposal, Tier
from .fairness import FairnessPolicy, legal_anchors
from .orders import MatchOrder, Squad
from .state import MatchState
from .validate import Limits, validate_match, validate_squad


@dataclass(slots=True)
class Resolved:
    """A proposal after validation: the safe orders, the problems found and whether it was usable at all."""

    value: Squad | MatchOrder | None
    issues: list[str] = field(default_factory=list)
    valid: bool = False


def resolve(tier: Tier, proposal: Proposal, state: MatchState, policy: FairnessPolicy, limits: Limits) -> Resolved:
    """Validates a proposal for its tier against the match state, the fairness policy and the operator limits."""
    if proposal.data is None:
        return Resolved(None, [proposal.error or "no answer"], False)
    if tier is Tier.SQUAD:
        checked = validate_squad(proposal.data, state, legal_anchors(state, policy), limits)
    else:
        checked = validate_match(proposal.data, state, limits)
    return Resolved(checked.value, checked.issues, True)
