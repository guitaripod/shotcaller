# Fairness

shotcaller exists to make a server more fun to play against bots, not to make bots cheat. The rules are enforced in code, not only in prompts.

## What a director is never allowed to do

- Aim, move, shoot or pick a target for a bot. The GSC mod does not call Bot Warfare's `SetScriptEnemy` or any aim or movement builtin.
- See where a living player is. `fairness.fair_view` is the only data a director receives, and a test asserts it contains no coordinates at all.
- Send a bot anywhere except an anchor in the legal set.

## What a director sees

Scores, a summary of how the human is doing, the roster with kills, deaths and (for bots) current skill and side, the last dozen kills with weapons, the standing orders it gave last time, and the death sites it may send bots to. That is what a human commander watching the scoreboard and the kill feed could know.

## Legal goals

Only death sites: the waypoint nearest where a human died, legal from `death_delay_ms` (6 s) to `death_max_age_ms` (5 min) after. Camp spots and spawn areas are not offered, because sending a bot to a fixed spot just parks it. A bot sent to a death site walks there the normal way, with Bot Warfare's own pathing and perception, holds about 15 seconds and is released. At most two bots are on a mission at once. A death site tells the bots where a kill cam would have shown the human.

## Operator limits

Whatever a model asks for is clamped by `[limits]`: skill moves at most `max_skill_step` (2) per decision, `max_goal_bots` (2) bots on a mission for `goal_seconds` (15), bot count is capped, the next map must be on your rotation list. Orders expire if the sidecar stops.

