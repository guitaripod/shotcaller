"""Turns a director's raw answer into safe orders: closed sets, clamped values, legal anchors only."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field

from .orders import DEFAULT_RADIUS, RADIUS_RANGE, SKILL_RANGE, BotOrder, ChatLine, Goal, MatchOrder, Squad
from .state import Anchor, MatchState

_THINK = re.compile(r"<think>.*?</think>", re.DOTALL)
_FENCE = re.compile(r"```(?:json)?\s*(.*?)```", re.DOTALL)
_COLOR = re.compile(r"\^[0-9:;]")
_CONTROL = re.compile(r"[\x00-\x1f\x7f|]")


@dataclass(frozen=True, slots=True)
class Limits:
    """Hard bounds the operator sets, enforced no matter what a model says."""

    max_skill_step: int = 2
    max_goal_bots: int = 2
    goal_seconds: int = 15
    max_bots: int = 17
    chat_max_len: int = 80
    chat_max_lines: int = 2
    maps: tuple[str, ...] = ()


@dataclass(slots=True)
class Validated:
    """A checked proposal and the problems found while checking it."""

    value: object
    issues: list[str] = field(default_factory=list)


def extract_json(text: str) -> dict | None:
    """Pulls the first JSON object out of a model reply, ignoring think tags and code fences."""
    text = _THINK.sub("", text)
    fenced = _FENCE.search(text)
    if fenced:
        text = fenced.group(1)
    start, end = text.find("{"), text.rfind("}")
    if start < 0 or end <= start:
        return None
    try:
        parsed = json.loads(text[start : end + 1])
    except json.JSONDecodeError:
        return None
    return parsed if isinstance(parsed, dict) else None


def validate_squad(proposal: dict, state: MatchState, legal: dict[str, Anchor], limits: Limits) -> Validated:
    """Checks bot orders against the roster, the legal anchors, the skill step limit and the mission cap."""
    issues: list[str] = []
    squad = Squad()
    bots = {p.slot: p for p in state.bots}
    seen_slots: set[int] = set()
    missions = 0
    for raw in _list(proposal.get("bots")):
        slot = raw.get("slot") if isinstance(raw, dict) else None
        if not isinstance(slot, int) or slot not in bots or slot in seen_slots:
            issues.append(f"bot order dropped: slot {slot!r}")
            continue
        seen_slots.add(slot)
        order = BotOrder(slot, _skill(raw.get("skill"), bots[slot].skill, limits, issues))
        if missions < limits.max_goal_bots:
            _goal(raw.get("goal"), order, legal, limits, issues)
            missions += order.goal is not None
        elif raw.get("goal") is not None:
            issues.append("goal dropped: mission cap reached")
        if not order.is_empty():
            squad.bots.append(order)
    return Validated(squad, issues)


def validate_match(proposal: dict, state: MatchState, limits: Limits) -> Validated:
    """Checks the skill window, bot head count and next map."""
    issues: list[str] = []
    low, high = _int(proposal.get("skill_min")), _int(proposal.get("skill_max"))
    low = _clamp(low, *SKILL_RANGE) if low is not None else None
    high = _clamp(high, *SKILL_RANGE) if high is not None else None
    if low is not None and high is not None and low > high:
        issues.append("skill window inverted; dropped")
        low = high = None
    count = _int(proposal.get("bot_count"))
    if count is not None:
        count = _clamp(count, 0, min(limits.max_bots, max(0, state.slots - 1)))
    next_map = proposal.get("next_map")
    if next_map is not None and next_map not in limits.maps:
        issues.append(f"next_map dropped: {next_map!r}")
        next_map = None
    return Validated(MatchOrder(low, high, count, next_map), issues)


def validate_chat(proposal: dict, state: MatchState, limits: Limits) -> Validated:
    """Checks chat lines: only bots speak, text is plain, short and unique."""
    issues: list[str] = []
    bots = {p.slot for p in state.bots}
    lines: list[ChatLine] = []
    for raw in _list(proposal.get("lines"))[: limits.chat_max_lines]:
        if not isinstance(raw, dict) or raw.get("slot") not in bots or raw.get("scope") not in ("all", "team"):
            issues.append("chat line dropped: bad speaker or scope")
            continue
        text = clean_chat(str(raw.get("text", "")), limits.chat_max_len)
        if not text or any(line.text == text for line in lines):
            issues.append("chat line dropped: empty or duplicate")
            continue
        lines.append(ChatLine(raw["slot"], raw["scope"], text))
    return Validated(lines, issues)


def clean_chat(text: str, max_len: int) -> str:
    """Strips color codes and wire-reserved characters and cuts to the length limit."""
    text = _CONTROL.sub(" ", _COLOR.sub("", text))
    return " ".join(text.split())[:max_len].strip()


def _list(value: object) -> list:
    return value if isinstance(value, list) else []


def _int(value: object) -> int | None:
    return value if isinstance(value, int) and not isinstance(value, bool) else None


def _clamp(value: int, low: int, high: int) -> int:
    return max(low, min(high, value))


def _skill(raw: object, current: int | None, limits: Limits, issues: list[str]) -> int | None:
    number = _int(raw)
    if number is None:
        return None
    number = _clamp(number, *SKILL_RANGE)
    if current is not None and abs(number - current) > limits.max_skill_step:
        issues.append(f"skill step limited from {current} toward {number}")
        number = current + limits.max_skill_step * (1 if number > current else -1)
    return number


def _goal(raw: object, order: BotOrder, legal: dict[str, Anchor], limits: Limits, issues: list[str]) -> None:
    if raw is None:
        return
    if not isinstance(raw, dict) or raw.get("anchor") not in legal:
        issues.append(f"goal dropped: anchor {raw.get('anchor') if isinstance(raw, dict) else raw!r} is not legal")
        return
    radius = _int(raw.get("radius"))
    order.goal = Goal(raw["anchor"], _clamp(radius, *RADIUS_RANGE) if radius is not None else DEFAULT_RADIUS, limits.goal_seconds)
