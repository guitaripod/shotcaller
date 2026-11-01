"""Restarts the game server when it has stopped answering, so a hang costs a minute and not a night."""

from __future__ import annotations

import logging
import subprocess
import time
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

from .rcon import Rcon

log = logging.getLogger("shotcaller.watchdog")


@dataclass(frozen=True, slots=True)
class WatchdogConfig:
    """What to watch and how patient to be."""

    unit: str = "iw4x-server"
    interval_s: float = 20.0
    failures: int = 3
    stale_s: float = 90.0
    grace_s: float = 120.0
    cooldown_s: float = 300.0


class Watchdog:
    """Counts consecutive bad checks and restarts the unit once, then leaves it alone while it comes back."""

    def __init__(
        self,
        config: WatchdogConfig,
        rcon_answers: Callable[[], bool],
        log_age_s: Callable[[], float | None],
        restart: Callable[[str], None],
    ) -> None:
        self.config = config
        self._rcon_answers = rcon_answers
        self._log_age_s = log_age_s
        self._restart = restart
        self._bad = 0
        self._quiet_until = float("-inf")
        self._last_restart = float("-inf")

    def check(self, now: float) -> str:
        """One pass. Returns `ok`, `quiet` (still inside a grace period), `suspect` or `restarted`."""
        if now < self._quiet_until:
            return "quiet"
        if self._healthy():
            self._bad = 0
            return "ok"
        self._bad += 1
        if self._bad < self.config.failures:
            return "suspect"
        if now - self._last_restart < self.config.cooldown_s:
            return "suspect"
        log.warning("%s unresponsive for %d checks; restarting", self.config.unit, self._bad)
        self._restart(self.config.unit)
        self._bad = 0
        self._last_restart = now
        self._quiet_until = now + self.config.grace_s
        return "restarted"

    def _healthy(self) -> bool:
        """Healthy when rcon answers, or the mod wrote to the event log recently (a map is loading)."""
        if self._rcon_answers():
            return True
        age = self._log_age_s()
        return age is not None and age < self.config.stale_s

    def run(self) -> None:
        """Checks forever on the configured interval."""
        while True:
            self.check(time.monotonic())
            time.sleep(self.config.interval_s)


def restart_user_unit(unit: str) -> None:
    """Restarts a systemd user unit."""
    subprocess.run(["systemctl", "--user", "restart", unit], check=False)


def file_age_s(path: Path) -> float | None:
    """Seconds since a file was last written, or None when it does not exist."""
    try:
        return time.time() - path.stat().st_mtime
    except FileNotFoundError:
        return None


def build(config: WatchdogConfig, rcon: Rcon, events_log: Path) -> Watchdog:
    """The production watchdog: rcon status, the event log's age, and `systemctl --user restart`."""
    return Watchdog(config, rcon.alive, lambda: file_age_s(events_log), restart_user_unit)
