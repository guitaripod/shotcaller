"""What a director may ask of the bots, and the wire format the GSC mod reads."""

from __future__ import annotations

from dataclasses import dataclass, field

BEHAVIORS = ("strafe", "nade", "sprint", "camp", "follow", "crouch", "jump")
SKILL_RANGE = (1, 7)
DEFAULT_RADIUS = 150
RADIUS_RANGE = (16, 1000)


@dataclass(frozen=True, slots=True)
class Goal:
    """Walk to an anchor and stay within a radius of it."""

    anchor: str
    radius: int = DEFAULT_RADIUS


@dataclass(slots=True)
class TeamOrder:
    """Behavior percentages applied to every bot on a team."""

    team: str
    behaviors: dict[str, int] = field(default_factory=dict)


@dataclass(slots=True)
class BotOrder:
    """Skill, behavior percentages and an optional goal for one bot."""

    slot: int
    skill: int | None = None
    behaviors: dict[str, int] = field(default_factory=dict)
    goal: Goal | None = None
    clear_goal: bool = False

    def is_empty(self) -> bool:
        """True when the order changes nothing."""
        return self.skill is None and not self.behaviors and self.goal is None and not self.clear_goal


@dataclass(slots=True)
class Squad:
    """The standing team and bot orders that persist until replaced or expired."""

    teams: list[TeamOrder] = field(default_factory=list)
    bots: list[BotOrder] = field(default_factory=list)

    def is_empty(self) -> bool:
        """True when nothing is ordered."""
        return not self.teams and not self.bots


@dataclass(frozen=True, slots=True)
class ChatLine:
    """One thing a bot says in chat."""

    slot: int
    scope: str
    text: str


@dataclass(frozen=True, slots=True)
class MatchOrder:
    """Server-wide knobs applied over rcon: the bot skill window, head count and next map."""

    skill_min: int | None = None
    skill_max: int | None = None
    bot_count: int | None = None
    next_map: str | None = None

    def is_empty(self) -> bool:
        """True when nothing is ordered."""
        return self.skill_min is None and self.skill_max is None and self.bot_count is None and self.next_map is None


def encode(seq: int, map_name: str, ttl_ms: int, squad: Squad, chat: list[ChatLine]) -> str:
    """Renders the order file: header lines, then team, bot and chat lines."""
    lines = [f"seq|{seq}", f"map|{map_name}", f"ttl|{ttl_ms}"]
    for team in squad.teams:
        lines.append("|".join(["team", team.team, *_pairs(team.behaviors)]))
    for bot in squad.bots:
        if not bot.is_empty():
            lines.append("|".join(["bot", str(bot.slot), *_bot_pairs(bot)]))
    for line in chat:
        lines.append(f"chat|{line.slot}|{line.scope}|{line.text}")
    return "\n".join(lines) + "\n"


def _pairs(values: dict[str, int]) -> list[str]:
    return [f"{key}={value}" for key, value in values.items()]


def _bot_pairs(bot: BotOrder) -> list[str]:
    pairs = []
    if bot.skill is not None:
        pairs.append(f"skill={bot.skill}")
    pairs.extend(_pairs(bot.behaviors))
    if bot.clear_goal:
        pairs.append("goal=clear")
    elif bot.goal is not None:
        pairs.append(f"goal={bot.goal.anchor}:{bot.goal.radius}")
    return pairs


def squad_to_dict(squad: Squad) -> dict:
    """A JSON-ready summary of standing orders, shown back to the director so it can vary them."""
    return {
        "teams": [{"team": t.team, "behaviors": t.behaviors} for t in squad.teams],
        "bots": [
            {
                "slot": b.slot,
                **({"skill": b.skill} if b.skill is not None else {}),
                **({"behaviors": b.behaviors} if b.behaviors else {}),
                **({"goal": {"anchor": b.goal.anchor, "radius": b.goal.radius}} if b.goal else {}),
            }
            for b in squad.bots
            if not b.is_empty()
        ],
    }
