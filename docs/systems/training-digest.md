---
type: system
tags: [system, bot, training]
status: seedling
related: ["[[specs/cycle-16-training-autopilot/spec]]", "[[systems/bot-training]]", "[[planning/bot-ladder]]", "[[systems/systems-moc]]"]
created: 2026-11-09
updated: 2026-11-10
uid: 0a750fb8-9d41-4cbf-aeb4-3cafbec46399
supersedes:
---

# Training digest

> The orchestrator's reading of the bot autopilot's findings. `/training digest` rewrites this
> note whole; raw figures live under `godot/reports/bot/autopilot/` (generated, untracked).

Digest of 2026-11-10 00:30: blocks 1 to 10, all from the cycle 16 short-block proof (T14 of
[[specs/cycle-16-training-autopilot/tasks]]): 15-minute blocks, `judge_cap` 40, 6 minutes reserved
for fit and judge, `min_positions` 30. They prove the loop, not the bot: no figure here is a
training result.

## Figures by day

| Day | Blocks | Kinds | Statuses | Hours | Labels | Labels/h | Fitted mean / last | Held-out mean / last | Vs random | Vs champion | Champion changes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-11-10 | 10 | full 7, seed 1, trial 2 | done 8, interrupted 2 | 1.81 | 8,670 | 6,155 | 0.659 / 0.691 | 0.558 / 0.529 | PASS 4, CAP 3, not run 4 | FAIL 2, CAP 1, not run 8 | 1 |

Five full blocks fitted 200 to 325 positions each (1,002 to 1,708 labels); held-out agreement
0.517 to 0.637, against 0.538 for F0 and 0.581 for F2 on 2,000 to 4,000 positions.

## Champion history

| Block | Fit | From | To | Note |
|---|---|---|---|---|
| 1 (seed) | `05182ca9d62f` (F0) | none | F0 | F0 PASS against `random`; F2 `47b40a1e748a` PASS against `random`, FAIL against F0 |

No block fit beat F0: four hit the judge cap of 40 pairs (champion kept), two lost to it.

## What the advisor tried and what worked

| Source | Blocks |
|---|---|
| advisor | 3, 7, 9, 10 |
| fallback | 4, 5, 6 |
| default | 1, 2, 8 (first block after each start) |

- Block 3: `l2` 0.005 and `fit_iterations` 1000, to curb overfitting; held-out 0.560, judge capped.
- Block 4: fallback forced by a wrong `server_path` (the proof's step).
- Block 5: the advisor returned nothing twice. Qwen3.5 thought for 8,396 tokens and filled its
  10,240-token slot. Since `2aaeb3a` the request turns thinking off (decision T21 in
  [[planning/bot-trainer-architecture]]); block 9's reply then took 109 s with the server start.
- Trials: `positions` 1000 (block 5, 94 labels/min against a floor of 40.6, pass; started by a
  fallback, which `2aaeb3a` now forbids) and `positions` 800 (block 9, proposed by the advisor,
  100 labels/min against 40.8, pass). Both values are now allowed extras.

## Plateaus and faults

None. Blocks 7 and 10 were stopped on purpose (`interrupted`). Block 6 was resumed after the
service was killed mid-block and closed at 05:46:09Z, 3 minutes past its original deadline,
inside the 5-minute grace.

## Steering in force

Steering 2 (the proof's, sent 2026-11-09): `positions` bounds 200 to 400, a note asking for 800.
Steering 1 (`positions` 200 to 600) came before it. Allowed extras: `positions` 1000 and 800.

## Reading and proposals

The figures say only that the machinery works on the PC: seed, advisor, fallback, trial, stop,
resume and the digest. Fifteen-minute blocks label too few positions (200 to 325) for a fit to
beat F0, and a 40-pair judge mostly caps. They say nothing yet about what the advisor can do over
3-hour blocks. Before the first real night, the proof's steering should be replaced: its 200 to
400 bounds would hold every block far below the 1,000 to 4,000 positions a fit needs. That needs
a steering file Ben approves (`/training steer`). The start config should be the example's
(`block_hours` 3, `judge_cap` 200, default reserve and `min_positions`).

## Related

- [[systems/bot-training]]
- [[specs/cycle-16-training-autopilot/spec]]
