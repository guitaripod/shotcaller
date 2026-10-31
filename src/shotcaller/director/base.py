"""The contract every director implements, and what it hands back."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum
from typing import Protocol


class Tier(StrEnum):
    """The three decision speeds, from slowest to fastest."""

    MATCH = "match"
    SQUAD = "squad"
    CHAT = "chat"


@dataclass(slots=True)
class Proposal:
    """A director's answer before validation: a JSON-shaped dict plus how it was produced."""

    data: dict | None
    raw: str = ""
    model: str = ""
    latency_ms: int = 0
    error: str | None = None
    meta: dict = field(default_factory=dict)


class Director(Protocol):
    """Decides what the bots should try to do. Implementations never touch aim or movement."""

    name: str

    def decide(self, tier: Tier, view: dict, trigger: dict | None = None) -> Proposal:
        """Answers for one tier given the fair view and, for chat, the event that triggered it."""
        ...
