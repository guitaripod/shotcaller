"""Configuration loaded from a TOML file, with defaults for a stock local setup."""

from __future__ import annotations

import re
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

from .director.llm import LlmConfig
from .fairness import FairnessPolicy
from .validate import Limits

_PASSWORD = re.compile(r'rcon_password\s+"([^"]+)"')


@dataclass(frozen=True, slots=True)
class ServerConfig:
    """Where the game server lives and how to reach it."""

    game_dir: Path
    rcon_host: str = "127.0.0.1"
    rcon_port: int = 28961
    rcon_password_file: Path | None = None

    @property
    def scriptdata(self) -> Path:
        """The directory the GSC mod reads and writes."""
        return self.game_dir / "userraw" / "scriptdata" / "shotcaller"

    def rcon_password(self) -> str:
        """The rcon password, read from the server's secrets.cfg and never logged."""
        path = self.rcon_password_file or self.game_dir / "userraw" / "secrets.cfg"
        match = _PASSWORD.search(path.read_text(encoding="utf-8"))
        if not match:
            raise ValueError(f"no rcon_password found in {path}")
        return match.group(1)


@dataclass(frozen=True, slots=True)
class Cadence:
    """How often each tier runs, in seconds."""

    squad_s: float = 15.0
    match_s: float = 120.0
    chat_gap_s: float = 20.0
    orders_ttl_s: float = 45.0
    poll_s: float = 0.5


@dataclass(frozen=True, slots=True)
class Gating:
    """Minimum eval score a model needs before it may run a tier."""

    reports_dir: Path = Path("~/.local/share/shotcaller/reports")
    thresholds: dict[str, float] = field(default_factory=lambda: {"match": 0.9, "squad": 0.95, "chat": 0.9})
    trust_unvalidated: bool = False


DEFAULT_PERSONAS = (
    "cocky veteran who has seen it all",
    "cheerful rookie who is thrilled to be here",
    "dry deadpan sniper",
    "trash-talking showboat",
)


@dataclass(frozen=True, slots=True)
class Config:
    """Everything the service needs."""

    server: ServerConfig
    llm: LlmConfig = field(default_factory=LlmConfig)
    limits: Limits = field(default_factory=Limits)
    fairness: FairnessPolicy = field(default_factory=FairnessPolicy)
    cadence: Cadence = field(default_factory=Cadence)
    gating: Gating = field(default_factory=Gating)
    journal_path: Path = Path("~/.local/share/shotcaller/journal.jsonl")
    personas: tuple[str, ...] = DEFAULT_PERSONAS


def load(path: Path) -> Config:
    """Reads a TOML file into a Config; unknown keys are ignored, missing ones default."""
    raw = tomllib.loads(path.read_text(encoding="utf-8"))
    server = raw["server"]
    maps = tuple(raw.get("maps", {}).get("rotation", ()))
    llm = _llm_values(raw.get("llm", {}), maps)
    return Config(
        server=ServerConfig(
            game_dir=Path(server["game_dir"]).expanduser(),
            rcon_host=server.get("rcon_host", "127.0.0.1"),
            rcon_port=server.get("rcon_port", 28961),
            rcon_password_file=Path(server["rcon_password_file"]).expanduser() if "rcon_password_file" in server else None,
        ),
        llm=_build(LlmConfig, llm),
        limits=_build(Limits, {**raw.get("limits", {}), "maps": maps}),
        fairness=_build(FairnessPolicy, raw.get("fairness", {})),
        cadence=_build(Cadence, raw.get("cadence", {})),
        gating=_gating(raw.get("gating", {})),
        journal_path=Path(raw.get("journal", {}).get("path", "~/.local/share/shotcaller/journal.jsonl")).expanduser(),
        personas=tuple(raw.get("chat", {}).get("personas", DEFAULT_PERSONAS)),
    )


def _build(cls, values: dict):
    names = set(cls.__dataclass_fields__)
    return cls(**{key: value for key, value in values.items() if key in names})


def _llm_values(values: dict, maps: tuple[str, ...]) -> dict:
    defaults = LlmConfig()
    return {
        **values,
        "maps": maps,
        "timeouts_s": {**defaults.timeouts_s, **values.get("timeouts_s", {})},
        "max_tokens": {**defaults.max_tokens, **values.get("max_tokens", {})},
    }


def _gating(values: dict) -> Gating:
    gating = _build(Gating, values)
    thresholds = {**Gating().thresholds, **gating.thresholds}
    return Gating(Path(gating.reports_dir).expanduser(), thresholds, gating.trust_unvalidated)
