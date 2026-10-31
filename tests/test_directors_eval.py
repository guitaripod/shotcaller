from __future__ import annotations

import json
import urllib.error

from shotcaller import gating, schema
from shotcaller.config import Gating
from shotcaller.director import LlmConfig, LlmDirector, StaticDirector, Tier
from shotcaller.eval import run_eval
from shotcaller.eval.scenarios import SCENARIOS, build_state
from shotcaller.fairness import FairnessPolicy, fair_view
from shotcaller.validate import Limits

POLICY = FairnessPolicy()
LIMITS = Limits(maps=("mp_rust", "mp_terminal"))


def reply(content: str) -> dict:
    return {"choices": [{"message": {"content": content}}]}


def test_llm_director_sends_a_strict_json_schema_request():
    seen = {}

    def transport(url, headers, body, timeout_s):
        seen.update(url=url, body=body, timeout=timeout_s)
        return reply('{"rationale": "x", "teams": [], "bots": []}')

    director = LlmDirector(LlmConfig(base_url="http://h/v1/", model="m"), transport)
    proposal = director.decide(Tier.SQUAD, fair_view(build_state(5, 5), POLICY))
    assert proposal.data == {"rationale": "x", "teams": [], "bots": []}
    assert seen["url"] == "http://h/v1/chat/completions"
    assert seen["body"]["response_format"]["json_schema"]["strict"] is True
    assert seen["timeout"] == 25.0


def test_llm_director_retries_once_on_unparseable_output():
    answers = iter(["I think we should push.", '{"rationale": "ok", "teams": [], "bots": []}'])
    director = LlmDirector(LlmConfig(model="m"), lambda *_: reply(next(answers)))
    proposal = director.decide(Tier.SQUAD, {})
    assert proposal.data is not None and proposal.error is None


def test_llm_director_reports_transport_errors_without_raising():
    def transport(*_):
        raise urllib.error.URLError("connection refused")

    proposal = LlmDirector(LlmConfig(model="m"), transport).decide(Tier.CHAT, {})
    assert proposal.data is None and "URLError" in proposal.error


def test_static_director_raises_skill_when_the_human_dominates_and_lowers_it_when_struggling():
    director = StaticDirector()
    up = director.decide(Tier.SQUAD, fair_view(build_state(18, 4), POLICY)).data
    down = director.decide(Tier.SQUAD, fair_view(build_state(3, 14), POLICY)).data
    calm = director.decide(Tier.SQUAD, fair_view(build_state(11, 10), POLICY)).data
    assert {b["slot"] for b in up["bots"]} == {1, 2, 3, 4} and all(b["skill"] == 5 for b in up["bots"])
    assert all(b["skill"] == 1 for b in down["bots"])
    assert calm["bots"] == []


def test_eval_scores_the_static_baseline_per_tier():
    report = run_eval(StaticDirector(), POLICY, LIMITS)
    assert set(report["tiers"]) == {"match", "squad", "chat"}
    by_id = {s["id"]: s for s in report["scenarios"]}
    assert by_id["human_dominating"]["passed"] and by_id["human_struggling"]["passed"] and by_id["human_balanced"]["passed"]
    assert not by_id["human_camps_one_spot"]["passed"]
    assert not by_id["chat_human_killed"]["passed"]


def test_eval_scores_an_oracle_model_at_the_top():
    def transport(url, headers, body, timeout_s):
        system = body["messages"][0]["content"]
        view = json.loads(body["messages"][1]["content"])["view"]
        if "adjust the bots now" in system:
            return reply(json.dumps(squad_answer(view)))
        if "server-wide knobs" in system:
            return reply('{"rationale": "easy", "skill_min": 4, "skill_max": 7}')
        return reply('{"lines": [{"slot": 2, "scope": "all", "text": "Better luck next time."}]}')

    report = run_eval(LlmDirector(LlmConfig(model="oracle"), transport), POLICY, LIMITS)
    failed = [s["id"] for s in report["scenarios"] if not s["passed"]]
    assert failed == []


def squad_answer(view: dict) -> dict:
    humans = view["humans"]
    kd = sum(h["kills"] for h in humans) / max(1, sum(h["deaths"] for h in humans))
    shift = 2 if kd >= 3 else 1 if kd >= 1.8 else -1 if kd <= 0.7 else 0
    axis = [b for b in view["bots"] if b["side"] == "opponent"]
    bots = {b["slot"]: {"slot": b["slot"], "skill": b["skill"] + shift} for b in axis} if shift else {}
    sites = [site["id"] for site in view["death_sites"]]
    if len(sites) >= 2:
        repeated = bool(view["standing_orders"]["bots"])
        picks = [sites[-1], sites[1]] if repeated else [sites[0], sites[1]]
        for slot, site in zip((1, 2), picks):
            bots.setdefault(slot, {"slot": slot})["goal"] = {"anchor": site}
    return {"rationale": "oracle", "bots": list(bots.values())}


def test_gating_enables_tiers_from_the_stored_report(tmp_path):
    config = Gating(reports_dir=tmp_path, thresholds={"match": 0.6, "squad": 0.7, "chat": 0.6})
    assert not any(gating.enabled_tiers(config, "model-a").values())
    assert all(gating.enabled_tiers(Gating(reports_dir=tmp_path, trust_unvalidated=True), "model-a").values())
    report = {"schema": schema.VERSION, "model": "model-a", "tiers": {"match": {"score": 0.9}, "squad": {"score": 0.5}, "chat": {"score": 0.7}}}
    gating.save_report(tmp_path, report)
    assert gating.enabled_tiers(config, "model-a") == {Tier.MATCH: True, Tier.SQUAD: False, Tier.CHAT: True}


def test_every_scenario_has_a_unique_id_and_a_buildable_state():
    ids = [s.id for s in SCENARIOS]
    assert len(ids) == len(set(ids))
    for scenario in SCENARIOS:
        assert scenario.build().bots
