"""JSON schemas for what a director may answer, one per tier. Bump VERSION when a shape changes."""

from __future__ import annotations

from .orders import BEHAVIORS, RADIUS_RANGE, SKILL_RANGE

VERSION = 1

_PERCENT = {"type": "integer", "minimum": 0, "maximum": 100}
_BEHAVIORS = {
    "type": "object",
    "properties": {name: _PERCENT for name in BEHAVIORS},
    "additionalProperties": False,
}
_SKILL = {"type": "integer", "minimum": SKILL_RANGE[0], "maximum": SKILL_RANGE[1]}

SQUAD = {
    "type": "object",
    "properties": {
        "rationale": {"type": "string", "maxLength": 240},
        "teams": {
            "type": "array",
            "maxItems": 2,
            "items": {
                "type": "object",
                "properties": {"team": {"enum": ["allies", "axis"]}, "behaviors": _BEHAVIORS},
                "required": ["team", "behaviors"],
                "additionalProperties": False,
            },
        },
        "bots": {
            "type": "array",
            "maxItems": 18,
            "items": {
                "type": "object",
                "properties": {
                    "slot": {"type": "integer", "minimum": 0, "maximum": 17},
                    "skill": _SKILL,
                    "behaviors": _BEHAVIORS,
                    "goal": {
                        "type": ["object", "null"],
                        "properties": {
                            "anchor": {"type": "string", "maxLength": 8},
                            "radius": {"type": "integer", "minimum": RADIUS_RANGE[0], "maximum": RADIUS_RANGE[1]},
                        },
                        "required": ["anchor"],
                        "additionalProperties": False,
                    },
                },
                "required": ["slot"],
                "additionalProperties": False,
            },
        },
    },
    "required": ["rationale", "teams", "bots"],
    "additionalProperties": False,
}

MATCH = {
    "type": "object",
    "properties": {
        "rationale": {"type": "string", "maxLength": 240},
        "skill_min": _SKILL,
        "skill_max": _SKILL,
        "bot_count": {"type": "integer", "minimum": 0, "maximum": 17},
        "next_map": {"type": ["string", "null"], "maxLength": 32},
    },
    "required": ["rationale"],
    "additionalProperties": False,
}

CHAT = {
    "type": "object",
    "properties": {
        "lines": {
            "type": "array",
            "maxItems": 2,
            "items": {
                "type": "object",
                "properties": {
                    "slot": {"type": "integer", "minimum": 0, "maximum": 17},
                    "scope": {"enum": ["all", "team"]},
                    "text": {"type": "string", "maxLength": 80},
                },
                "required": ["slot", "scope", "text"],
                "additionalProperties": False,
            },
        }
    },
    "required": ["lines"],
    "additionalProperties": False,
}

BY_TIER = {"squad": SQUAD, "match": MATCH, "chat": CHAT}
