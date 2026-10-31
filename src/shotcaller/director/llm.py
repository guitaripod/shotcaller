"""A director backed by any OpenAI-compatible chat endpoint, such as llama-swap, llama.cpp or vLLM."""

from __future__ import annotations

import json
import time
import urllib.error
import urllib.request
from collections.abc import Callable
from dataclasses import dataclass, field

from .. import schema
from ..validate import extract_json
from . import prompts
from .base import Proposal, Tier

Transport = Callable[[str, dict, dict, float], dict]


@dataclass(frozen=True, slots=True)
class LlmConfig:
    """How to reach the model and how long to wait for each tier."""

    base_url: str = "http://127.0.0.1:8081/v1"
    model: str = ""
    api_key: str = ""
    timeouts_s: dict[str, float] = field(default_factory=lambda: {"match": 30.0, "squad": 25.0})
    max_tokens: dict[str, int] = field(default_factory=lambda: {"match": 400, "squad": 900})
    temperature: float = 0.7
    structured_output: bool = True
    extra_body: dict = field(default_factory=dict)
    maps: tuple[str, ...] = ()


def http_transport(url: str, headers: dict, body: dict, timeout_s: float) -> dict:
    """POSTs JSON and returns the decoded JSON reply."""
    request = urllib.request.Request(url, json.dumps(body).encode(), {"Content-Type": "application/json", **headers})
    with urllib.request.urlopen(request, timeout=timeout_s) as response:
        return json.load(response)


class LlmDirector:
    """Asks a language model for a tier's JSON answer, with one repair attempt for unparseable output."""

    def __init__(self, config: LlmConfig, transport: Transport = http_transport) -> None:
        self.config = config
        self.name = config.model
        self._transport = transport

    def decide(self, tier: Tier, view: dict) -> Proposal:
        """Calls the model for one tier and returns its parsed answer or the error."""
        messages = self._messages(tier, view)
        started = time.monotonic()
        try:
            text = self._complete(tier, messages)
            data = extract_json(text)
            if data is None:
                text = self._complete(tier, [*messages, {"role": "assistant", "content": text}, {"role": "user", "content": "That was not valid JSON. Answer again with only the JSON object."}])
                data = extract_json(text)
        except (urllib.error.URLError, TimeoutError, OSError, KeyError, ValueError) as error:
            return Proposal(data=None, model=self.name, latency_ms=_elapsed_ms(started), error=f"{type(error).__name__}: {error}")
        error = None if data is not None else "unparseable"
        return Proposal(data=data, raw=text, model=self.name, latency_ms=_elapsed_ms(started), error=error)

    def _messages(self, tier: Tier, view: dict) -> list[dict]:
        content: dict[str, object] = {"view": view}
        if tier is Tier.MATCH:
            content["maps"] = list(self.config.maps)
        return [
            {"role": "system", "content": prompts.BY_TIER[tier.value]},
            {"role": "user", "content": json.dumps(content, separators=(",", ":"))},
        ]

    def _complete(self, tier: Tier, messages: list[dict]) -> str:
        body = {
            "model": self.config.model,
            "messages": messages,
            "temperature": self.config.temperature,
            "max_tokens": self.config.max_tokens[tier.value],
            **self.config.extra_body,
        }
        if self.config.structured_output:
            body["response_format"] = {
                "type": "json_schema",
                "json_schema": {"name": f"shotcaller_{tier.value}_v{schema.VERSION}", "strict": True, "schema": schema.BY_TIER[tier.value]},
            }
        headers = {"Authorization": f"Bearer {self.config.api_key}"} if self.config.api_key else {}
        reply = self._transport(f"{self.config.base_url.rstrip('/')}/chat/completions", headers, body, self.config.timeouts_s[tier.value])
        return reply["choices"][0]["message"]["content"] or ""


def _elapsed_ms(started: float) -> int:
    return int((time.monotonic() - started) * 1000)
