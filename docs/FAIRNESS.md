# Fairness

shotcaller exists to make a server more fun to play against bots, not to make bots cheat. The rules are enforced in code, not only in prompts.

## What a director is never allowed to do

- Aim, move, shoot or pick a target for a bot. The GSC mod does not call Bot Warfare's `SetScriptEnemy` or any aim or movement builtin.
- See where a living player is. `fairness.fair_view` is the only data a director receives, and a test asserts it contains no coordinates at all.
- Send a bot anywhere except an anchor in the legal set.

## What a director sees

Scores, the roster with kills, deaths and (for bots) current skill and behavior values, the last dozen kills with weapons, the standing orders it gave last time, and the legal anchors with their distance to each team's home. That is what a human commander watching the scoreboard and the kill feed could know.

## Legal anchors

| Kind | Source | Legal when |
| --- | --- | --- |
| `camp` | Bot Warfare's curated camp waypoints | always |
| `home` | the waypoint nearest each team's average spawn | always |
| `death` | the waypoint nearest where a human died | at least `death_delay_ms` (6 s) and at most `death_max_age_ms` (5 min) after |

Bots then walk to those places the normal way, with Bot Warfare's own pathing and perception. A death site tells the bots where a kill cam would have shown the human.

## Operator limits

Whatever a model asks for is clamped by `[limits]`: skill moves at most `max_skill_step` (2) per decision, bot count is capped, chat is short and bots-only, the next map must be on your rotation list. Orders expire if the sidecar stops.

## Chat

Chat lines come from bots only, never imitate a human, lose color codes and wire-reserved characters, and are rate limited. The prompt asks for playful, never cruel. Pick a model whose guardrails suit your community; shotcaller does not ship a profanity filter.
