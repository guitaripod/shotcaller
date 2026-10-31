"""The rule-based baseline: adaptive difficulty and nothing else. Also the fallback and the eval floor."""

from __future__ import annotations

from .base import Proposal, Tier

DOMINATING_KD = 1.8
CRUSHING_KD = 3.0
STRUGGLING_KD = 0.7
HOPELESS_KD = 0.4


class StaticDirector:
    """Nudges the bots opposing the humans toward a close match using only the humans' kill/death ratio."""

    name = "static"

    def decide(self, tier: Tier, view: dict) -> Proposal:
        """Answers the squad tier; the match tier gets an empty proposal."""
        if tier is Tier.SQUAD:
            return Proposal(data=self._squad(view), model=self.name)
        return Proposal(data={"rationale": "static baseline holds the match settings"}, model=self.name)

    def _squad(self, view: dict) -> dict:
        shift = self._skill_shift(view)
        opposing = self._opposing(view)
        bots = []
        if shift:
            for bot in opposing:
                if bot["skill"] is not None:
                    bots.append({"slot": bot["slot"], "skill": max(1, min(7, bot["skill"] + shift))})
        return {"rationale": f"human K/D adjust {shift:+d}", "bots": bots}

    def _skill_shift(self, view: dict) -> int:
        deaths = sum(h["deaths"] for h in view["humans"])
        if not view["humans"]:
            return 0
        kd = sum(h["kills"] for h in view["humans"]) / max(1, deaths)
        if kd >= CRUSHING_KD:
            return 2
        if kd >= DOMINATING_KD:
            return 1
        if kd <= HOPELESS_KD:
            return -2
        if kd <= STRUGGLING_KD:
            return -1
        return 0

    def _opposing(self, view: dict) -> list[dict]:
        opposing = [b for b in view["bots"] if b["side"] == "opponent"]
        return opposing or view["bots"]
