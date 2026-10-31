"""The live loop: tail events, track the match, ask the director on each tier's schedule, send safe orders."""

from __future__ import annotations

import logging
import time
from concurrent.futures import Executor, Future, ThreadPoolExecutor
from dataclasses import dataclass, field, replace

from .actuator import MatchActuator, OrderFile
from .config import Config
from .director.base import Director, Proposal, Tier
from .events import Event
from .fairness import fair_view
from .journal import Journal
from .orders import ChatLine, MatchOrder, Squad, squad_to_dict
from .pipeline import Resolved, resolve
from .state import MatchState
from .tail import EventTail

log = logging.getLogger("shotcaller")


@dataclass(slots=True)
class _Flight:
    """A director call in progress."""

    future: Future
    view: dict
    trigger: dict | None
    started: float
    fallback: bool = False


@dataclass(slots=True)
class _Schedule:
    """When each tier last ran and what is waiting to be said."""

    last: dict[Tier, float] = field(default_factory=dict)
    chat_triggers: list[dict] = field(default_factory=list)
    last_write: float = 0.0
    match_due: bool = True


class Service:
    """Wires the pieces together. `step` does one pass and is driven by `run` or, in tests, by hand."""

    def __init__(
        self,
        config: Config,
        director: Director,
        fallback: Director,
        enabled: dict[Tier, bool],
        tail: EventTail,
        orders: OrderFile,
        match: MatchActuator | None,
        journal: Journal,
        executor: Executor | None = None,
    ) -> None:
        self.config = config
        self.director = director
        self.fallback = fallback
        self.enabled = enabled
        self.tail = tail
        self.orders = orders
        self.match = match
        self.journal = journal
        self.state = MatchState()
        self.squad = Squad()
        self.chat: list[ChatLine] = []
        self._executor = executor or ThreadPoolExecutor(max_workers=3, thread_name_prefix="shotcaller")
        self._flights: dict[Tier, _Flight] = {}
        self._schedule = _Schedule()
        self._squad_ok_at = float("-inf")

    def run(self) -> None:
        """Steps until interrupted, then releases the bots back to stock behavior."""
        log.info("shotcaller running; tiers enabled: %s", {t.value: on for t, on in self.enabled.items()})
        try:
            while True:
                self.step(time.monotonic())
                time.sleep(self.config.cadence.poll_s)
        finally:
            self.release()

    def release(self) -> None:
        """Writes an empty order set so the bots drop back to their stock behavior."""
        self.squad = Squad()
        self.chat = []
        self.orders.write(self.state.map, 1000, self.squad, [])

    def step(self, now: float) -> None:
        """One pass: ingest events, collect finished answers, start due ones, refresh the order file."""
        events, _ = self.tail.poll()
        for event in events:
            self._ingest(event, now)
        self._collect(now)
        self._start_due(now)
        self._heartbeat(now)

    def _ingest(self, event: Event, now: float) -> None:
        self.state.apply(event)
        if event.type == "hello":
            self._on_new_map(now)
        elif event.type == "kill":
            self._on_kill(event)
        elif event.type == "end":
            self.journal.record("outcome", map=self.state.map, scores=self.state.scores, human_kd=self.state.human_kd())

    def _on_new_map(self, now: float) -> None:
        self.squad = Squad()
        self.chat = []
        self._schedule.chat_triggers.clear()
        self._schedule.match_due = True
        self.orders.write(self.state.map, 1000, self.squad, [])
        self._schedule.last_write = now

    def _on_kill(self, event: Event) -> None:
        victim_human = event.get_str("vb") != "1"
        attacker_bot = event.get_str("ab") == "1"
        if victim_human and attacker_bot:
            kind = "human_killed"
        elif not victim_human and event.get_str("ab") == "0":
            kind = "bot_killed_by_human"
        else:
            return
        self._schedule.chat_triggers.append(
            {
                "type": kind,
                "victim": event.get_str("v"),
                "victim_slot": event.get_int("vn", -1),
                "attacker": event.get_str("a"),
                "attacker_slot": event.get_int("an", -1),
                "weapon": event.get_str("w"),
                "t": event.t,
            }
        )

    def _collect(self, now: float) -> None:
        for tier, flight in list(self._flights.items()):
            if not flight.future.done():
                continue
            del self._flights[tier]
            proposal = _result(flight.future)
            resolved = resolve(tier, proposal, self.state, self.config.fairness, self.config.limits)
            self._journal_decision(tier, flight, proposal, resolved, now)
            if resolved.valid:
                self._adopt(tier, resolved, now)
                if tier is Tier.SQUAD:
                    self._squad_ok_at = now
            elif tier is Tier.SQUAD and now - self._squad_ok_at > self.config.cadence.orders_ttl_s:
                self._fall_back(flight, now)

    def _fall_back(self, flight: _Flight, now: float) -> None:
        """Replaces stale squad orders with the static baseline after the model has failed for a whole TTL."""
        proposal = self.fallback.decide(Tier.SQUAD, flight.view)
        resolved = resolve(Tier.SQUAD, proposal, self.state, self.config.fairness, self.config.limits)
        self._journal_decision(Tier.SQUAD, replace(flight, fallback=True), proposal, resolved, now)
        if resolved.valid:
            self._adopt(Tier.SQUAD, resolved, now)

    def _adopt(self, tier: Tier, resolved: Resolved, now: float) -> None:
        if tier is Tier.SQUAD and isinstance(resolved.value, Squad):
            self.squad = resolved.value
            self._write(now)
        elif tier is Tier.CHAT and isinstance(resolved.value, list) and resolved.value:
            self.chat = resolved.value
            self._write(now)
            self.chat = []
        elif tier is Tier.MATCH and isinstance(resolved.value, MatchOrder) and self.match and not resolved.value.is_empty():
            log.info("match order: %s", self.match.apply(resolved.value))

    def _journal_decision(self, tier: Tier, flight: _Flight, proposal: Proposal, resolved: Resolved, now: float) -> None:
        orders = None if not resolved.valid else _plain(resolved.value)
        self.journal.record(
            "decision",
            tier=tier.value,
            model=proposal.model,
            fallback=flight.fallback,
            latency_ms=proposal.latency_ms,
            valid=resolved.valid,
            issues=resolved.issues,
            view=flight.view,
            trigger=flight.trigger,
            raw=proposal.raw,
            orders=orders,
        )
        log.info("%s %s %dms issues=%d model=%s", tier.value, "ok" if resolved.valid else "FAILED", proposal.latency_ms, len(resolved.issues), proposal.model)

    def _start_due(self, now: float) -> None:
        state, cadence = self.state, self.config.cadence
        if state.ended or not state.humans:
            return
        if self._due(Tier.SQUAD, now, cadence.squad_s) and state.bots:
            self._submit(Tier.SQUAD, now)
        if self._schedule.match_due or self._due(Tier.MATCH, now, cadence.match_s):
            if state.bots and self.enabled[Tier.MATCH]:
                self._submit(Tier.MATCH, now)
            self._schedule.match_due = False
        if self._schedule.chat_triggers and self.enabled[Tier.CHAT] and self._due(Tier.CHAT, now, cadence.chat_gap_s):
            trigger = self._schedule.chat_triggers[-1]
            self._schedule.chat_triggers.clear()
            self._submit(Tier.CHAT, now, trigger)

    def _due(self, tier: Tier, now: float, interval_s: float) -> bool:
        return tier not in self._flights and now - self._schedule.last.get(tier, -interval_s) >= interval_s

    def _submit(self, tier: Tier, now: float, trigger: dict | None = None) -> None:
        director, fallback = self._director_for(tier)
        view = fair_view(self.state, self.config.fairness, squad_to_dict(self.squad))
        if trigger is not None:
            trigger = {**trigger, "personas": self._personas(trigger)}
        self._schedule.last[tier] = now
        future = self._executor.submit(director.decide, tier, view, trigger)
        self._flights[tier] = _Flight(future, view, trigger, now, fallback)

    def _director_for(self, tier: Tier) -> tuple[Director, bool]:
        if self.enabled[tier]:
            return self.director, False
        return self.fallback, True

    def _personas(self, trigger: dict) -> dict[str, str]:
        involved = {trigger.get("victim_slot"), trigger.get("attacker_slot")}
        bots = [b.slot for b in self.state.bots if b.slot in involved] or [b.slot for b in self.state.bots][:3]
        personas = self.config.personas
        return {str(slot): personas[slot % len(personas)] for slot in bots}

    def _heartbeat(self, now: float) -> None:
        interval = self.config.cadence.squad_s / 2
        if not self.squad.is_empty() and now - self._schedule.last_write >= interval:
            self._write(now)

    def _write(self, now: float) -> None:
        ttl_ms = int(self.config.cadence.orders_ttl_s * 1000)
        self.orders.write(self.state.map, ttl_ms, self.squad, self.chat)
        self._schedule.last_write = now


def _result(future: Future) -> Proposal:
    try:
        return future.result()
    except Exception as error:
        return Proposal(data=None, error=f"{type(error).__name__}: {error}")


def _plain(value: object) -> object:
    if isinstance(value, Squad):
        return squad_to_dict(value)
    if isinstance(value, MatchOrder):
        return {"skill_min": value.skill_min, "skill_max": value.skill_max, "bot_count": value.bot_count, "next_map": value.next_map}
    if isinstance(value, list):
        return [{"slot": line.slot, "scope": line.scope, "text": line.text} for line in value]
    return None
