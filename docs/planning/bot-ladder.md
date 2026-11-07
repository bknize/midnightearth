---
type: planning
tags: [planning, bot, ledger]
status: growing
related: ["[[specs/cycle-11-bot-trainer/spec]]", "[[planning/bot-trainer-architecture]]", "[[specs/cycle-7-bot-players/spec]]", "[[specs/cycle-7-bot-players/plan]]", "[[planning/cycles]]", "[[planning/planning-moc]]"]
created: 2026-11-04
updated: 2026-11-07
uid: ef993f98-4b7e-47a9-9dc2-6884a4a06820
linear: https://linear.app/night-science-llc/project/cycle-7-bot-players-c711d1c8bc83
supersedes:
---

# Bot ladder

> The ladder of every bot the game measures: one **rung** per measured bot at one stamp,
> and the **yardstick**, the highest rung at the current stamp
> ([[specs/cycle-11-bot-trainer/spec]] R3–R5; first written by cycle 7 R37).

Strength is measured by `make bot-eval` (pentanomial SPRT on paired, seat- and
deck-swapped seeds, α = β = 0.05; gainer bounds [0, +25] Elo, non-regression [−25, 0]),
driving `godot/tools/match_worker.gd`. The stamp is `r<RULES_VERSION>-<first 16 hex of
SHA-256 over the card pool, the deck list and the Crew pool files>` (cycle 11 R1), computed
the same way by `BotStamp.current()` and `scripts/bot/records.py`; a rung is valid only
under the stamp it carries.

## Rungs

| Rung | Bot | Stamp | Measured against | Result | Commit | Note |
|---|---|---|---|---|---|---|
| 0 | random | r7-857b165d5a5d755e | random (selftest) | non-regression PASS (H1), 101 pairs, 202 games, 0.500 ± 0.000; first committer won 0.49 | (DC-16 T07) | Uniform over legal commits and prompt answers. Mirror match: each seat swap returns the same result, so the win rate is exactly 0.500. Sweep p95 130 µs, p99 400 µs, slowest 2131 µs. Full line: `bot-eval: a=random b=random result=PASS bound=H1 pairs=101 games=202 winrate=0.500±0.000 first_committer=0.49 p95_us=192 p99_us=630 slowest_us=9165 overruns_a=0 overruns_b=0 stamp=match exit=0`. |

**The yardstick** is the highest rung at the current stamp: today `random`, rung 0.

**Promotion (R4).** A policy becomes the next rung only after a gainer SPRT PASS against
the yardstick (`scripts/bot-eval.sh --a <policy> --b <yardstick> --gainer`) and a quiet 50-seed `make sweep BOT=<policy>` with a p99 decision under 10 ms on
the Mac. It then becomes the yardstick. Cycle 11 promotes nothing; the first learned policy
is cycle B's ([[planning/bot-trainer-architecture]]).

## History: the ledger of rules 4 to 6

The bots below were removed by DC-13 (rules 7); their rows are kept as history and measure
nothing at the current stamp.

| Date | Bot | Stamp | Tested against | Result (bound, pairs, games, win rate ± ci) | p95 / slowest µs | Commit | Note |
|---|---|---|---|---|---|---|---|
| 2026-11-04 | greedy_v1 | r4-8054169094898cc2 | – | reference | – | 52f2ef5 | Frozen copy of GreedyBot at cycle 6's merge (R21). API-forced edits: extends BotPlayer. Choices pinned on 12 seeds at round 1 turn 3 and one set prompt (`test_greedy_v1_bot.gd`, 703c449). |
| 2026-11-04 | random | r4-8054169094898cc2 | – | reference (floor) | – | 5895167 | Uniform over legal commits and prompt answers, per-decision seed (R20). |
| 2026-11-04 | tuned v1 (default weights: score_diff 100, k 48) | r4-8054169094898cc2 | greedy_v1 | not run: superseded by k 24 before verification | – | 7425df9 | Same choices as the greedy bot under the full search (R12); the top-48 prune changed 0 of 200 test decisions. Sweep slowest 46 ms (k 48 previews nearly every candidate). |
| 2026-11-04 | tuned v1 (k 24, shipped) | r4-8054169094898cc2 | greedy_v1 | non-regression PASS (H1), 100 pairs, 200 games, 0.500 ± 0.000 (identical choices); first committer won 0.50 | sweep p95 4475, p99 6795, slowest 25020; eval (8 workers, loaded) p95 8789, slowest 132623, overruns 389 / 424 (greedy_v1) | e9e18fe | Spec C14 (Ben): k 24 and a p99 sweep assertion. The top-24 prune changed 0 of 200 test decisions. Quiet-run p99 7.0 ms, max about 11 ms. Check at DC-08 T11: `greedy` against `greedy_v1` is PASS (H1), 100 pairs, 0.500. Full line: `bot-eval: a=tuned b=greedy_v1 result=PASS bound=H1 pairs=100 games=200 winrate=0.500±0.000 first_committer=0.50 p95_us=8789 slowest_us=132623 overruns_a=389 overruns_b=424 stamp=match exit=0`. |
| 2026-11-05 | tuned v1 (k 24, default weights, re-stamped without training) | r5-f898a1b1ce5bee0f | greedy_v1 | non-regression PASS (H1), 64 pairs, 128 games, 0.508 ± 0.015; first committer won 0.49 | sweep p95 5104, p99 7191, slowest 11383; eval p95 8502, slowest 67444, overruns 241 / 293 (greedy_v1) | (DC-09 T07) | Cycle 8 milestone A (Bloom, Echo, card memory, rules 5). `make bot-train` lands with DC-10, so the `stamp` field was edited by hand (plan P18); `make check` then reads `stamp=match`. The two bots no longer choose identically: the shipped bot reads effective costs, `greedy_v1` printed ones (unedited, R21). Full line: `bot-eval: a=tuned b=greedy_v1 result=PASS bound=H1 pairs=64 games=128 winrate=0.508±0.015 first_committer=0.49 p95_us=8502 slowest_us=67444 overruns_a=241 overruns_b=293 stamp=MISMATCH exit=0` (run before the re-stamp). |
| 2026-11-05 | tuned v1 (k 24, default weights, re-stamped without training); matrix (6/3/2/50, re-stamped) | r6-c4cbd3190e297787 | greedy_v1 | non-regression PASS (H1), 48 pairs, 96 games, 0.510 ± 0.036; first committer won 0.49 | sweep p95 7223, p99 9793, slowest 21526 (406 Crew prompts, 160 declines); eval p95 15412, p99 21106, slowest 200041, overruns 641 / 755 (greedy_v1) | (DC-11 T14) | Cycle 8 milestone B (Crew, optional prompts and the decline, rules 6, log format 4; the stamp hashes cards, decks and Crew, R58). Cycle 7 milestone B has merged, so R58 points at `make bot-train`, but the overnight run is Ben's (cycle 7 T16, NSC-115), so both weights files were re-stamped by hand (plan P18) and the matrix bot is exempt from R17 until T16 (cycle 8 C13, cycle 7 C17: its Crew sweep p99 was 10.43 and 10.46 ms). Full line: `bot-eval: a=tuned b=greedy_v1 result=PASS bound=H1 pairs=48 games=96 winrate=0.510±0.036 first_committer=0.49 p95_us=15412 p99_us=21106 slowest_us=200041 overruns_a=641 overruns_b=755 stamp=MISMATCH exit=0` (run before the re-stamp). |

## After an engine change (R5)

Any cycle that changes `MatchRules.RULES_VERSION`, the card pool JSON, the deck list JSON
or the Crew JSON (anything that moves the stamp) does this before its `/cycle test` merge:

1. `make sweep` (the 50-seed sweep, outside the gate) with `p99_us` under 10000.
2. `make bot-eval` (`random` against `random`, non-regression): the rung-0 check at the new
   stamp. No re-stamp is needed, `random` has no weights.
3. Add a rung-0 row at the new stamp, and mark every higher rung **unproven** in its Note
   until it is re-measured against the yardstick (a gainer PASS at the new stamp).
4. Put the `bot-eval` line in the cycle's row of [[planning/cycles]].

This replaces the DC-13 line "rerun provision suspended" (cycle 11 R5). The genetic
trainer (`make bot-train`) and the level calibration (`make bot-calibrate`) were deleted in
DC-16 with the levels they measured (cycle 11 R6, C3).

## Related

- [[specs/cycle-11-bot-trainer/spec]] (R1–R6)
- [[planning/bot-trainer-architecture]]
- [[specs/cycle-7-bot-players/spec]] (R21–R23, R33–R38)
- [[planning/cycles]]
