# Eval, replay and gating

The point of shotcaller is that a better model, behind the same config key, does the job better. This is how you know.

## Scenario eval

`shotcaller eval` asks the configured model (or `--model`, or `--baseline` for the rule-based director) to answer synthetic matches, three times each (`--runs`) because models are stochastic, runs each answer through the production validator and checks a property of the result.

| Scenario | Tier | Property |
| --- | --- | --- |
| `human_dominating` | squad | opposing bots get at least one skill level tougher on average |
| `human_struggling` | squad | opposing bots get at least one level easier |
| `human_balanced` | squad | opposing bots move by at most one level (no thrashing) |
| `human_camps_one_spot` | squad | one or two bots (not more) are sent to different places the human keeps dying, hottest site included, and re-asking with the first answer shown does not return identical orders |
| `no_hot_site` | squad | a single stray death is not a reason to send anyone: no missions |
| `match_too_easy` | match | the skill window rises |
| `match_steady` | match | the answer is accepted |

Per tier: `score = 0.3 * valid + 0.5 * passed + 0.2 * latency_ok`, where `valid` is the share of answers that parsed and validated, `passed` the share that satisfied their property, and `latency_ok` the share within the tier's time budget (`[llm.timeouts_s]`). Reports are written to `[gating] reports_dir` as `<model>.json` with the schema version, the per-tier numbers and every scenario's detail.

## Gating

At start the service reads the model's report. A tier runs on the model only if its score meets `[gating.thresholds]` (defaults: match 0.9, squad 0.92). The defaults sit above the static baseline's score on purpose: a model has to beat doing nothing clever before it is trusted with a tier. Otherwise squad uses the static baseline and match and chat stay off. A report written under an older `schema.VERSION` is ignored, so changing the shape of orders forces a re-eval. `trust_unvalidated = true` skips the check.

Promote a model: edit `[llm] model`, `shotcaller eval`, `shotcaller doctor`, restart the service.

## Replay

Every decision is journaled with the exact view and trigger. `shotcaller replay journal.jsonl --model <id>` re-asks a model every recorded decision and reports its valid rate, latency and how often it reproduces the squad orders that were actually used. Use it to compare a new model on states from your own matches before it ever plays one.

Each match end also journals an `outcome` entry (final scores and the human's K/D), so you can measure what a configuration did to match closeness over time. The journal is also the dataset for fine-tuning a small model on the decisions of a large one.

## Results

Measured 2026-11-01 on a local llama-swap with `enable_thinking = false`, second run of each so the model is already loaded. Replace these with your own numbers; they show the spread between weight classes, not a ranking.

| Model | match | squad | squad p95 |
| --- | --- | --- | --- |
| Nemotron 3.5 Bolt 74B-A9B abliterated (Q4, local) | 1.00 | 0.97 | 1.3 s |
| Nemotron 3.5 Bolt E4B (Q4, local) | 1.00 | 0.86 | 5.7 s |
| Qwen3 4B Instruct (Q4, local) | 0.83 | 0.87 | 0.5 s |
| static baseline (no model) | 0.75 | 0.90 | 0.0 s |

Each number is three runs per scenario. `human_camps_one_spot` is still the hardest scenario (Bolt 74B and E4B pass 2 of 3, Qwen3 4B 0 of 3): choosing two different death sites and then varying the orders when asked again is what separates the weight classes. `no_hot_site` catches the opposite failure: the E4B model passes 1 of 3 because it sends bots to a single stray death. The static baseline now scores 0.90 on squad because it handles the skill scenarios and the quiet one, so the default squad threshold is 0.92: a model has to beat it, not tie it.

The suite has seven scenarios. It is a floor to clear, not a ranking; add scenarios as you find failures.

## Thinking models

Reasoning models spend the token budget on hidden reasoning and return empty content. Turn thinking off per request with `[llm.extra_body.chat_template_kwargs] enable_thinking = false` (llama.cpp, vLLM), or `reasoning_effort = "none"` where supported, or raise `max_tokens`.
