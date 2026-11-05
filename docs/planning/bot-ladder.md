---
type: planning
tags: [planning, bot, ledger]
status: growing
related: ["[[specs/cycle-7-bot-players/spec]]", "[[specs/cycle-7-bot-players/plan]]", "[[planning/cycles]]", "[[planning/planning-moc]]"]
created: 2026-11-04
updated: 2026-11-04
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

## Rerun after an engine change

Any cycle that changes `MatchRules.RULES_VERSION`, the card pool JSON or the deck list
JSON (anything that moves the stamp) does this before its `/cycle test` merge (R36):

1. `make check`. The sweep line prints `stamp=MISMATCH` when the shipped weights were
   measured under another stamp; the gate stays green either way.
2. `make bot-eval` (the shipped bot against `greedy_v1`, non-regression, about ten minutes
   on all cores). Its first line says when a stamp does not match.
3. On FAIL or `stamp=MISMATCH`: `make bot-train` (overnight by default; `HOURS=` to bound
   it), then commit the promoted weights on the cycle branch. A run that promotes nothing
   leaves the old weights and records the best candidate's result here.
4. If an engine API change forced an edit to `greedy_v1`, list the edit in its row's note.
5. Add a row here and put the `bot-eval` line in the cycle's row of [[planning/cycles]].

Milestone B (`make bot-train`, `make bot-calibrate`, the matrix bot) lands as DC-10, after cycle 8
milestone A as DC-09 (Ben, [[specs/cycle-8-ramp-bounce-crew/spec]] C12); until then step 3 cannot run, and a FAIL is recorded as a follow-up issue instead.

## Related

- [[specs/cycle-7-bot-players/spec]] (R21–R23, R33–R38)
- [[planning/cycles]]
