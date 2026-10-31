"""The event line format the GSC mod writes, and its parser."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class Event:
    """One telemetry line: game time in milliseconds, a type and its string fields."""

    t: int
    type: str
    fields: dict[str, str]

    def get_int(self, key: str, default: int = 0) -> int:
        """The field as an integer, or the default when absent or malformed."""
        try:
            return int(self.fields[key])
        except (KeyError, ValueError):
            return default

    def get_str(self, key: str, default: str = "") -> str:
        """The field as text, or the default when absent."""
        return self.fields.get(key, default)


def parse_line(line: str) -> Event | None:
    """Parses `ms|type|key=value|...`; returns None for blank or malformed lines."""
    parts = line.rstrip("\r\n").split("|")
    if len(parts) < 2 or not parts[0].lstrip("-").isdigit():
        return None
    fields: dict[str, str] = {}
    for part in parts[2:]:
        key, sep, value = part.partition("=")
        if sep:
            fields[key] = value
    return Event(t=int(parts[0]), type=parts[1], fields=fields)
