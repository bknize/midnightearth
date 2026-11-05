---
type: planning
tags: [planning, bot, ledger]
status: growing
related: ["[[specs/cycle-7-bot-players/spec]]", "[[specs/cycle-7-bot-players/plan]]", "[[planning/cycles]]", "[[planning/planning-moc]]"]
created: 2026-11-04
updated: 2026-11-05
uid: ef993f98-4b7e-47a9-9dc2-6884a4a06820
linear: https://linear.app/night-science-llc/project/cycle-7-bot-players-c711d1c8bc83
supersedes:
---

# Bot ladder

> The ledger of every bot the game ships or measures against: one row per accepted bot,
> reference change or retrain, with the stamp it was measured under
> ([[specs/cycle-7-bot-players/spec]] R37).

Strength is measured by `make bot-eval` (pentanomial SPRT on paired, seat- and
deck-swapped seeds, α = β = 0.05; gainer bounds [0, +25] Elo, non-regression [−25, 0]).
The stamp is `r<RULES_VERSION>-<first 16 hex of SHA-256 over the card pool then the deck
list>`; a weights file and a report are valid only under the stamp they carry. "Best so
far" is the weights file committed in the repository (R23); nothing else counts.

## Ledger

| Date | Bot | Stamp | Tested against | Result (bound, pairs, games, win rate ± ci) | p95 / slowest µs | Commit | Note |
|---|---|---|---|---|---|---|---|
| 2026-11-04 | greedy_v1 | r4-8054169094898cc2 | – | reference | – | 52f2ef5 | Frozen copy of GreedyBot at cycle 6's merge (R21). API-forced edits: extends BotPlayer. Choices pinned on 12 seeds at round 1 turn 3 and one set prompt (`test_greedy_v1_bot.gd`, 703c449). |
| 2026-11-04 | random | r4-8054169094898cc2 | – | reference (floor) | – | 5895167 | Uniform over legal commits and prompt answers, per-decision seed (R20). |
| 2026-11-04 | tuned v1 (default weights: score_diff 100, k 48) | r4-8054169094898cc2 | greedy_v1 | not run: superseded by k 24 before verification | – | 7425df9 | Same choices as the greedy bot under the full search (R12); the top-48 prune changed 0 of 200 test decisions. Sweep slowest 46 ms (k 48 previews nearly every candidate). |
| 2026-11-04 | tuned v1 (k 24, shipped) | r4-8054169094898cc2 | greedy_v1 | non-regression PASS (H1), 100 pairs, 200 games, 0.500 ± 0.000 (identical choices); first committer won 0.50 | sweep p95 4475, p99 6795, slowest 25020; eval (8 workers, loaded) p95 8789, slowest 132623, overruns 389 / 424 (greedy_v1) | e9e18fe | Spec C14 (Ben): k 24 and a p99 sweep assertion. The top-24 prune changed 0 of 200 test decisions. Quiet-run p99 7.0 ms, max about 11 ms. Check at DC-08 T11: `greedy` against `greedy_v1` is PASS (H1), 100 pairs, 0.500. Full line: `bot-eval: a=tuned b=greedy_v1 result=PASS bound=H1 pairs=100 games=200 winrate=0.500±0.000 first_committer=0.50 p95_us=8789 slowest_us=132623 overruns_a=389 overruns_b=424 stamp=match exit=0`. |
| 2026-11-05 | tuned v1 (k 24, default weights, re-stamped without training) | r5-f898a1b1ce5bee0f | greedy_v1 | non-regression PASS (H1), 64 pairs, 128 games, 0.508 ± 0.015; first committer won 0.49 | sweep p95 5104, p99 7191, slowest 11383; eval p95 8502, slowest 67444, overruns 241 / 293 (greedy_v1) | (DC-09 T07) | Cycle 8 milestone A (Bloom, Echo, card memory, rules 5). `make bot-train` lands with DC-10, so the `stamp` field was edited by hand (plan P18); `make check` then reads `stamp=match`. The two bots no longer choose identically: the shipped bot reads effective costs, `greedy_v1` printed ones (unedited, R21). Full line: `bot-eval: a=tuned b=greedy_v1 result=PASS bound=H1 pairs=64 games=128 winrate=0.508±0.015 first_committer=0.49 p95_us=8502 slowest_us=67444 overruns_a=241 overruns_b=293 stamp=MISMATCH exit=0` (run before the re-stamp). |

## Calibration

<!-- calibration:begin -->

Latest run, 2026-11-05. Stamp: r5-f898a1b1ce5bee0f. Bot: `tuned` at each level against `greedy_v1` at full strength; 200 paired seeds per cell.

| level | pairing | winrate ± ci | pairs |
|---|---|---|---|
| 0 | bloom/bloom | 0.350 ± 0.037 | 200 |
| 0 | bloom/echo | 0.497 ± 0.003 | 400 |
| 0 | drift/drift | 0.170 ± 0.034 | 200 |
| 0 | echo/echo | 0.205 ± 0.036 | 200 |
| 0 | ruin/drift | 0.144 ± 0.022 | 400 |
| 0 | ruin/ruin | 0.140 ± 0.033 | 200 |
| 4 | bloom/bloom | 0.362 ± 0.035 | 200 |
| 4 | bloom/echo | 0.496 ± 0.004 | 400 |
| 4 | drift/drift | 0.210 ± 0.036 | 200 |
| 4 | echo/echo | 0.205 ± 0.036 | 200 |
| 4 | ruin/drift | 0.174 ± 0.024 | 400 |
| 4 | ruin/ruin | 0.170 ± 0.034 | 200 |
| 8 | bloom/bloom | 0.407 ± 0.033 | 200 |
| 8 | bloom/echo | 0.497 ± 0.003 | 400 |
| 8 | drift/drift | 0.237 ± 0.037 | 200 |
| 8 | echo/echo | 0.265 ± 0.037 | 200 |
| 8 | ruin/drift | 0.231 ± 0.026 | 400 |
| 8 | ruin/ruin | 0.220 ± 0.040 | 200 |
| 12 | bloom/bloom | 0.425 ± 0.033 | 200 |
| 12 | bloom/echo | 0.500 ± 0.000 | 400 |
| 12 | drift/drift | 0.295 ± 0.039 | 200 |
| 12 | echo/echo | 0.300 ± 0.038 | 200 |
| 12 | ruin/drift | 0.292 ± 0.028 | 400 |
| 12 | ruin/ruin | 0.275 ± 0.044 | 200 |
| 16 | bloom/bloom | 0.450 ± 0.033 | 200 |
| 16 | bloom/echo | 0.499 ± 0.002 | 400 |
| 16 | drift/drift | 0.335 ± 0.034 | 200 |
| 16 | echo/echo | 0.372 ± 0.038 | 200 |
| 16 | ruin/drift | 0.338 ± 0.029 | 400 |
| 16 | ruin/ruin | 0.325 ± 0.044 | 200 |
| 20 | bloom/bloom | 0.482 ± 0.018 | 200 |
| 20 | bloom/echo | 0.499 ± 0.002 | 400 |
| 20 | drift/drift | 0.500 ± 0.000 | 200 |
| 20 | echo/echo | 0.580 ± 0.028 | 200 |
| 20 | ruin/drift | 0.500 ± 0.003 | 400 |
| 20 | ruin/ruin | 0.500 ± 0.000 | 200 |

Mean over pairings, `tuned` at the level vs `greedy_v1`:

| level | winrate |
|---|---|
| 0 | 0.251 |
| 4 | 0.270 |
| 8 | 0.310 |
| 12 | 0.348 |
| 16 | 0.386 |
| 20 | 0.510 |

Tier suggestion (easy ≈ 0.35, normal ≈ 0.50, hard = the max):

- easy: level 12 (winrate 0.348)
- normal: level 20 (winrate 0.510)
- hard: level 20 (winrate 0.510)

Stamp: r5-f898a1b1ce5bee0f

<!-- calibration:end -->

## Rerun after an engine change

Any cycle that changes `MatchRules.RULES_VERSION`, the card pool JSON or the deck list
JSON (anything that moves the stamp) does this before its `/cycle test` merge (R36):

1. `make sweep` and `make sweep BOT=matrix` (the 50-seed sweep, outside the gate since
   NSC-133). The sweep line prints `stamp=MISMATCH` when the shipped weights were measured
   under another stamp; the sweep stays green either way, and `p99_us` must stay under
   10000 (the latency budget, for both bots).
2. `make bot-eval` and `make bot-eval BOT=matrix` (each shipped bot against `greedy_v1`,
   non-regression, about ten minutes on all cores). The first line says when a stamp does
   not match.
3. On FAIL or `stamp=MISMATCH`: `make bot-train` and `make bot-train BOT=matrix` for the
   bot concerned (overnight by default; `HOURS=` to bound it), then commit the promoted
   weights on the cycle branch. The default run label is `<bot>-<stamp>`; a checkpoint of
   another stamp is refused (pass a new `LABEL=`). The final line repeats a stamp
   mismatch. A candidate is promoted only if it passes the gainer test against `greedy_v1`
   and the best-so-far with no rejected action and no replay mismatch, and a quiet
   50-seed sweep with the candidate's weights (`make sweep BOT=<bot> WEIGHTS=<path>`, run by
   the trainer after both passes) has a p99 decision under 10 ms (R41, C16). A run that promotes nothing leaves the old weights and records
   the best candidate's result here.
4. If an engine API change forced an edit to `greedy_v1`, list the edit in its row's note.
5. Add a row here and put the `bot-eval` line in the cycle's row of [[planning/cycles]].

Milestone B (`make bot-train`, `make bot-calibrate`, the matrix bot) lands as DC-10, after cycle 8
milestone A as DC-09 (Ben, [[specs/cycle-8-ramp-bounce-crew/spec]] C12); until then step 3 cannot run, and a FAIL is recorded as a follow-up issue instead.

After a retrain or a large change to the bots, `make bot-calibrate` refreshes the
[Calibration](#calibration) table.

## Related

- [[specs/cycle-7-bot-players/spec]] (R21–R23, R33–R38)
- [[planning/cycles]]
