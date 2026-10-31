"""Decides which tiers a model has earned, from the reports the eval wrote."""

from __future__ import annotations

import json
import re
from pathlib import Path

from . import schema
from .config import Gating
from .director.base import Tier


def report_path(reports_dir: Path, model: str) -> Path:
    """Where the eval report for a model lives."""
    return reports_dir / (re.sub(r"[^A-Za-z0-9._-]+", "_", model) + ".json")


def save_report(reports_dir: Path, report: dict) -> Path:
    """Writes a report under its model's name and returns the path."""
    path = report_path(reports_dir, report["model"])
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return path


def load_report(reports_dir: Path, model: str) -> dict | None:
    """The stored report for a model, or None when it was never evaluated or the schema moved on."""
    path = report_path(reports_dir, model)
    if not path.exists():
        return None
    report = json.loads(path.read_text(encoding="utf-8"))
    return report if report.get("schema") == schema.VERSION else None


def enabled_tiers(gating: Gating, model: str) -> dict[Tier, bool]:
    """Which tiers the model may run: those whose eval score meets the threshold."""
    report = load_report(gating.reports_dir, model)
    if report is None:
        return dict.fromkeys(Tier, gating.trust_unvalidated)
    return {tier: bool(report["tiers"].get(tier.value, {}).get("score", 0.0) >= gating.thresholds[tier.value]) for tier in Tier}
