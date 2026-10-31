"""Carries orders into the game: an atomic order file for the GSC mod and rcon for server-wide knobs."""

from __future__ import annotations

import os
from pathlib import Path

from .orders import MatchOrder, Squad, encode
from .rcon import Rcon


class OrderFile:
    """Writes the order file the GSC mod polls, replacing it atomically so a read never sees half of it."""

    def __init__(self, path: Path) -> None:
        self.path = path
        self._seq = 0

    @property
    def seq(self) -> int:
        """The sequence number of the last write."""
        return self._seq

    def write(self, map_name: str, ttl_ms: int, squad: Squad) -> int:
        """Writes a new order file with the next sequence number and returns it."""
        self._seq += 1
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.path.with_name(self.path.name + ".tmp")
        temporary.write_text(encode(self._seq, map_name, ttl_ms, squad), encoding="utf-8")
        os.replace(temporary, self.path)
        return self._seq

    def clear(self) -> None:
        """Removes the order file so the mod finds nothing to apply."""
        self.path.unlink(missing_ok=True)


class MatchActuator:
    """Applies the server-wide order through rcon."""

    def __init__(self, rcon: Rcon, gametype_prefix: str = "gametype war") -> None:
        self._rcon = rcon
        self._gametype_prefix = gametype_prefix

    def apply(self, order: MatchOrder) -> list[str]:
        """Sends one rcon command per set field and returns the commands sent."""
        sent = []
        if order.skill_min is not None:
            sent.append(f"set bots_skill_min {order.skill_min}")
        if order.skill_max is not None:
            sent.append(f"set bots_skill_max {order.skill_max}")
        if order.bot_count is not None:
            sent.append(f"set bots_manage_fill {order.bot_count}")
        if order.next_map is not None:
            sent.append(f'set sv_mapRotationCurrent "{self._gametype_prefix} map {order.next_map}"')
        for command in sent:
            self._rcon.send(command)
        return sent
