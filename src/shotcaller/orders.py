"""What a director may ask of the bots, and the wire format the GSC mod reads."""

from __future__ import annotations

from dataclasses import dataclass, field

SKILL_RANGE = (1, 7)
DEFAULT_RADIUS = 150
RADIUS_RANGE = (16, 1000)
DEFAULT_MISSION_SECONDS = 15


@dataclass(frozen=True, slots=True)
class Goal:
    """A timed mission: walk to an anchor, hold within a radius, then go back to playing as usual."""

    anchor: str
    radius: int = DEFAULT_RADIUS
    seconds: int = DEFAULT_MISSION_SECONDS


@dataclass(slots=True)
class BotOrder:
    """A skill level and an optional timed mission for one bot."""

    slot: int
    skill: int | None = None
    goal: Goal | None = None

    def is_empty(self) -> bool:
        """True when the order changes nothing."""
        return self.skill is None and self.goal is None


@dataclass(slots=True)
class Squad:
    """The standing bot orders, replaced on every decision and dropped when they expire."""

    bots: list[BotOrder] = field(default_factory=list)

    def is_empty(self) -> bool:
        """True when nothing is ordered."""
        return not any(not bot.is_empty() for bot in self.bots)


@dataclass(frozen=True, slots=True)
class MatchOrder:
    """Server-wide knobs applied over rcon: the bot skill window and a recommended next map."""

    skill_min: int | None = None
    skill_max: int | None = None
    next_map: str | None = None

    def is_empty(self) -> bool:
        """True when nothing is ordered."""
        return self.skill_min is None and self.skill_max is None and self.next_map is None


def encode(seq: int, map_name: str, ttl_ms: int, squad: Squad) -> str:
    """Renders the order file: header lines, then one line per ordered bot."""
    lines = [f"seq|{seq}", f"map|{map_name}", f"ttl|{ttl_ms}"]
    for bot in squad.bots:
        if not bot.is_empty():
            lines.append("|".join(["bot", str(bot.slot), *_bot_pairs(bot)]))
    return "\n".join(lines) + "\n"


def _bot_pairs(bot: BotOrder) -> list[str]:
    pairs = []
    if bot.skill is not None:
        pairs.append(f"skill={bot.skill}")
    if bot.goal is not None:
        pairs.append(f"goal={bot.goal.anchor}:{bot.goal.radius}:{bot.goal.seconds}")
    return pairs


def squad_to_dict(squad: Squad) -> dict:
    """A JSON-ready summary of standing orders, shown back to the director so it can vary them."""
    return {
        "bots": [
            {
                "slot": b.slot,
                **({"skill": b.skill} if b.skill is not None else {}),
                **({"goal": {"anchor": b.goal.anchor, "radius": b.goal.radius}} if b.goal else {}),
            }
            for b in squad.bots
            if not b.is_empty()
        ],
    }
