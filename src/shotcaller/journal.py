"""An append-only record of every decision, the raw material for replay and later fine-tuning."""

from __future__ import annotations

import json
import time
from collections.abc import Iterator
from pathlib import Path


class Journal:
    """Writes one JSON object per line and rotates the file once it passes a size limit."""

    def __init__(self, path: Path, max_bytes: int = 64 * 1024 * 1024, backups: int = 3) -> None:
        self.path = path
        self.max_bytes = max_bytes
        self.backups = backups
        path.parent.mkdir(parents=True, exist_ok=True)

    def record(self, kind: str, **data: object) -> None:
        """Appends one entry stamped with wall-clock time."""
        entry = {"ts": round(time.time(), 3), "kind": kind, **data}
        self._rotate_if_full()
        with self.path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(entry, separators=(",", ":"), default=str) + "\n")

    def _rotate_if_full(self) -> None:
        """Shifts journal.jsonl to .1, .1 to .2 and so on, dropping the oldest backup."""
        if not self.path.exists() or self.path.stat().st_size < self.max_bytes:
            return
        oldest = self.path.with_name(f"{self.path.name}.{self.backups}")
        oldest.unlink(missing_ok=True)
        for index in range(self.backups - 1, 0, -1):
            source = self.path.with_name(f"{self.path.name}.{index}")
            if source.exists():
                source.rename(self.path.with_name(f"{self.path.name}.{index + 1}"))
        self.path.rename(self.path.with_name(f"{self.path.name}.1"))


def read(path: Path) -> Iterator[dict]:
    """Yields the entries of a journal, skipping lines that are not valid JSON."""
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                continue
