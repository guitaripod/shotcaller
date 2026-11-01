"""The match as the sidecar knows it, rebuilt from the event stream."""

from __future__ import annotations

from collections import deque
from dataclasses import dataclass, field

from .events import Event

TEAMS = ("allies", "axis")


@dataclass(slots=True)
class Player:
    """One connected player, bot or human, as of the last scoreboard snapshot."""

    slot: int
    name: str
    team: str = "none"
    bot: bool = False
    kills: int = 0
    deaths: int = 0
    score: int = 0
    alive: bool = True
    skill: int | None = None


@dataclass(frozen=True, slots=True)
class Anchor:
    """A waypoint the game offered as a goal: where a human died."""

    id: str
    kind: str
    x: int
    y: int
    z: int
    born_ms: int
    count: int = 1
    last_ms: int = 0


@dataclass(frozen=True, slots=True)
class Kill:
    """One entry of the kill feed."""

    t: int
    victim: int
    victim_name: str
    victim_bot: bool
    victim_team: str
    attacker: int | None
    attacker_name: str
    attacker_bot: bool
    weapon: str
    means: str


@dataclass(slots=True)
class MatchState:
    """Scores, roster, kill feed and anchors for the current map."""

    map: str = ""
    gametype: str = ""
    slots: int = 0
    now_ms: int = 0
    scores: dict[str, int] = field(default_factory=lambda: dict.fromkeys(TEAMS, 0))
    players: dict[int, Player] = field(default_factory=dict)
    anchors: dict[str, Anchor] = field(default_factory=dict)
    feed: deque[Kill] = field(default_factory=lambda: deque(maxlen=40))
    last_ack: int = -1
    ended: bool = False

    def apply(self, event: Event) -> None:
        """Folds one event into the state."""
        self.now_ms = max(self.now_ms, event.t)
        handler = getattr(self, f"_on_{event.type}", None)
        if handler:
            handler(event)

    @property
    def humans(self) -> list[Player]:
        """Human players who are on a playing team; spectators and players still joining do not count."""
        return [p for p in self.players.values() if not p.bot and p.team in TEAMS]

    @property
    def bots(self) -> list[Player]:
        """Connected bots."""
        return [p for p in self.players.values() if p.bot]

    def human_kd(self) -> float | None:
        """Combined kill/death ratio of all humans, or None before any human has played."""
        humans = self.humans
        if not humans:
            return None
        return sum(p.kills for p in humans) / max(1, sum(p.deaths for p in humans))

    def human_teams(self) -> set[str]:
        """Teams that have at least one playing human on them."""
        return {p.team for p in self.humans}

    def side_of(self, bot: Player) -> str | None:
        """Whether a bot is a teammate or an opponent of the humans: None without humans, mixed when both teams have one."""
        teams = self.human_teams()
        if not teams:
            return None
        if len(teams) == len(TEAMS):
            return "mixed"
        return "teammate" if bot.team in teams else "opponent"

    def recent_human_deaths(self, window_ms: int) -> list[Kill]:
        """Kill feed entries where a human died within the window."""
        return [k for k in self.feed if not k.victim_bot and self.now_ms - k.t <= window_ms]

    def _clear(self) -> None:
        """Drops everything learned about the previous map."""
        self.scores = dict.fromkeys(TEAMS, 0)
        self.players = {}
        self.anchors = {}
        self.feed.clear()
        self.last_ack = -1
        self.ended = False

    def _on_hello(self, event: Event) -> None:
        self._clear()
        self.map = event.get_str("map")
        self.gametype = event.get_str("gametype")
        self.slots = event.get_int("slots")
        self.now_ms = event.t

    def _on_join(self, event: Event) -> None:
        slot = event.get_int("pn", -1)
        if slot >= 0:
            self.players[slot] = Player(slot, event.get_str("p"), event.get_str("pt", "none"), event.get_str("pb") == "1")

    def _on_leave(self, event: Event) -> None:
        self.players.pop(event.get_int("pn", -1), None)

    def _on_snap(self, event: Event) -> None:
        for team in TEAMS:
            self.scores[team] = event.get_int(team)

    def _on_p(self, event: Event) -> None:
        slot = event.get_int("pn", -1)
        if slot < 0:
            return
        player = self.players.get(slot) or Player(slot, event.get_str("p"))
        player.name = event.get_str("p", player.name)
        player.team = event.get_str("pt", player.team)
        player.bot = event.get_str("pb") == "1"
        player.kills = event.get_int("k")
        player.deaths = event.get_int("d")
        player.score = event.get_int("s")
        player.alive = event.get_str("alive") == "1"
        player.skill = event.get_int("skill", -1) if "skill" in event.fields else None
        self.players[slot] = player

    def _on_kill(self, event: Event) -> None:
        attacker = event.get_int("an", -1) if "an" in event.fields else None
        self.feed.append(
            Kill(
                t=event.t,
                victim=event.get_int("vn", -1),
                victim_name=event.get_str("v"),
                victim_bot=event.get_str("vb") == "1",
                victim_team=event.get_str("vt", "none"),
                attacker=attacker,
                attacker_name=event.get_str("a"),
                attacker_bot=event.get_str("ab") == "1",
                weapon=event.get_str("w"),
                means=event.get_str("mod"),
            )
        )

    def _on_anchor(self, event: Event) -> None:
        anchor_id = event.get_str("id")
        if anchor_id:
            earlier = self.anchors.get(anchor_id)
            self.anchors[anchor_id] = Anchor(
                id=anchor_id,
                kind=event.get_str("kind"),
                x=event.get_int("x"),
                y=event.get_int("y"),
                z=event.get_int("z"),
                born_ms=earlier.born_ms if earlier else event.t,
                count=earlier.count + 1 if earlier else 1,
                last_ms=event.t,
            )

    def _on_ack(self, event: Event) -> None:
        self.last_ack = event.get_int("seq", -1)

    def _on_end(self, event: Event) -> None:
        self.ended = True
        for team in TEAMS:
            self.scores[team] = event.get_int(team)
