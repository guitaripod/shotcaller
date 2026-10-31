"""Incremental reader for the event log, which the game truncates at every map start."""

from __future__ import annotations

from pathlib import Path

from .events import Event, parse_line


class EventTail:
    """Reads only complete new lines from a file and notices when the game truncated it."""

    def __init__(self, path: Path) -> None:
        self.path = path
        self._offset = 0

    def poll(self) -> tuple[list[Event], bool]:
        """Returns the new events and whether the file restarted since the last poll."""
        try:
            size = self.path.stat().st_size
        except FileNotFoundError:
            return [], False
        restarted = size < self._offset
        if restarted:
            self._offset = 0
        if size == self._offset:
            return [], restarted
        with self.path.open("rb") as handle:
            handle.seek(self._offset)
            chunk = handle.read()
        end = chunk.rfind(b"\n")
        if end < 0:
            return [], restarted
        self._offset += end + 1
        lines = chunk[: end + 1].decode("utf-8", errors="replace").splitlines()
        return [event for event in map(parse_line, lines) if event], restarted
