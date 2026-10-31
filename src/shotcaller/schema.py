"""JSON schemas for what a director may answer, one per tier. Bump VERSION when a shape changes."""

from __future__ import annotations

from .orders import RADIUS_RANGE, SKILL_RANGE

VERSION = 3

_SKILL = {"type": "integer", "minimum": SKILL_RANGE[0], "maximum": SKILL_RANGE[1]}

SQUAD = {
    "type": "object",
    "properties": {
        "rationale": {"type": "string", "maxLength": 240},
        "bots": {
            "type": "array",
            "maxItems": 18,
            "items": {
                "type": "object",
                "properties": {
                    "slot": {"type": "integer", "minimum": 0, "maximum": 17},
                    "skill": _SKILL,
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
    "required": ["rationale", "bots"],
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

BY_TIER = {"squad": SQUAD, "match": MATCH}
