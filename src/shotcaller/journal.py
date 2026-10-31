"""An append-only record of every decision, the raw material for replay and later fine-tuning."""

from __future__ import annotations

import json
import time
from collections.abc import Iterator
from pathlib import Path


class Journal:
    """Writes one JSON object per line."""

    def __init__(self, path: Path) -> None:
        self.path = path
        path.parent.mkdir(parents=True, exist_ok=True)

    def record(self, kind: str, **data: object) -> None:
        """Appends one entry stamped with wall-clock time."""
        entry = {"ts": round(time.time(), 3), "kind": kind, **data}
        with self.path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(entry, separators=(",", ":"), default=str) + "\n")


def read(path: Path) -> Iterator[dict]:
    """Yields the entries of a journal, skipping lines that are not valid JSON."""
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                continue
