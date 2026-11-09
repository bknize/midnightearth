---
type: tasks
tags: [tasks, cycle-7-bot-players, engine, bot, tooling]
status: approved
related: ["[[specs/cycle-7-bot-players/spec]]", "[[specs/cycle-7-bot-players/plan]]", "[[decisions/0002-one-branch-per-cycle]]", "[[planning/phase-1-tech-stack]]", "[[planning/cycles]]"]
created: 2026-11-04
updated: 2026-11-09
uid: 27b7fad5-c575-47db-a846-43c4dbc1e707
linear: https://linear.app/night-science-llc/project/cycle-7-bot-players-c711d1c8bc83
supersedes:
---

# Tasks: Cycle 7 — bot players

Derived from [[specs/cycle-7-bot-players/plan|plan]]. Numbered, dependency-ordered,
independently reviewable. Everything under `godot/engine/` goes to `implementer-engine`;
`godot/tools/`, `godot/main.gd`, `godot/board/match_driver.gd`, `scripts/` and the Makefile
go to `implementer`; `reviewer` reads diffs; `orchestrator` runs `make check`, `make
bot-eval`, launches the training run, re-pins the golden, drives the Godot MCP, edits the
`/cycle test` skill and handles Linear. Implementers write suites and Python unittests but
never run Godot; "passes" is confirmed at T11 and T18. Every brief carries the typed-strict
checklist from the DC-01 lessons and the plan's interface and record tables, so the worker
and the driver can start from the contract before the bots land.

**Precondition (C4):** cycle 6 (`cycle-6-constructed-decks`) is merged into `master` and
`cycle-7-bot-players` is re-based onto it before `/cycle plan`.

## Milestone A: the tuned bot, the interface, the references, the harness

| # | Task | Area | Depends on | Acceptance check | Who |
|---|---|---|---|---|---|
| 1 | Bot interface and registry: `BotPlayer` (P1), `BotRegistry` (P2) with `seed_for` moved and forwarded, `RandomBot`, `GreedyBot extends BotPlayer` with no behaviour change; `test_full_match.gd` and `main.gd`'s smoke still build greedy bots through `GreedyBot.new` (switched at T05/T07) | engine | – | `test_bot_registry.gd`: `make("greedy", …)` chooses the same action as `GreedyBot.new` on seeds 1–5; `make("nope", …)` is null; `make("random", seed, cards, defaults, 5)` is null (no level); `seed_for` equals `GreedyBot.seed_for`. `test_random_bot.gd`: every action over 50 seeds is accepted by the engine, the same seed and view give the same action, two seeds differ on at least one view. `test_greedy_bot.gd` unchanged and passing | implementer-engine |
| 2 | Frozen reference: `reference/greedy_v1_bot.gd` (P3) and its pinned suite; the ledger's row text for it returned in the report | engine | 1 | `test_greedy_v1_bot.gd`: 12 fixture (view, seed) pairs from seeds 1–12 at round 1 turn 3 plus one set prompt give the literal actions the suite pins; `GreedyV1Bot.new` and `GreedyBot.new` agree on all 12 (true today, a guard for later) | implementer-engine |
| 3 | Candidates, bound, evaluator, weights and stamp: `CandidateGen` (P4, P14), `Evaluator` with `FEATURES` and `pushed` (P5, P6), `BotWeights` (P7), `BotStamp` (P8), `data/tuned_weights.json` with default weights and `k` 48 and the current stamp | engine | 1 | `test_candidate_gen.gd`: `all()` equals the greedy bot's `candidates()` as a set for 20 views; `bound` of [4 ×1.25, 2 +1, 3] in that order is 15 and in the order [3, 2 +1, 4 ×1.25] is 13; `top(k)` is the first k by bound then ties. `test_evaluator.gd`: default weights give `value == score_diff`; `pushed` at level 20 returns the values unchanged; at level 0 the best candidate still has the highest expected pushed value over 1,000 draws and a candidate with gap above `push_unit` never beats the best. `test_bot_weights.gd`: the shipped file loads with `load_error == ""`, `stamp == BotStamp.current()`; a missing file, a bad feature name and a non-integer weight each set `load_error` and `defaults()` has `k` 48. `test_bot_stamp.gd`: the literal for the shipped files (pinned; re-pinned when data changes) | implementer-engine |
| 4 | `TunedBot` (P9): top-K previews, evaluator, push, prompts and set prompts, `decision_rng` tags; registry `tuned` becomes `default_name()` | engine | 3 | `test_tuned_bot.gd`: with default weights and `k = 1000` the action equals `GreedyBot`'s on seeds 1–20 (R12); with `k = 48` the choice differs from the full search on at most a recorded share of 200 decisions (number logged in the report, not asserted); level 20 never differs from level 20 across two runs (R2); level 3 over seeds 1–50 picks a non-best candidate at least once and never one whose gap exceeds `push_unit`; a set prompt previews n + 1 candidates; every action over 50 seeds is accepted (R3); the bot asks only `preview`, `preview_choice`, `preview_set` (a stub engine counts calls) | implementer-engine |
| 5 | Sweep and stamp line (P15): bots by `BotRegistry.default_name()`, `PackedInt32Array` of decision times, `p95_us`, `p99_us` and `slowest_us` on the line with `p99_us < 10000` asserted (C14), `stamp=match|MISMATCH` printed, `bot=` field; golden left as a skip with the literals to pin | engine (tests) | 4 | `test_full_match.gd` compiles and the sweep passes on the tuned bot; a temporary edit of the stamp in a copied weights file in a test prints `MISMATCH` without failing; the leak scan and replay invariants unchanged | implementer-engine |
| 6 | Worker (P17): `tools/bot_worker.gd` with the CLI, pair sets with seat and deck swaps, timing, replay check, the four record kinds, exit codes; `BotWorkerRecords` (pure record builders) | tooling | 1 (contract: interfaces and record table) | `test_bot_worker_records.gd`: a decision record has every field of the plan's table; a pair record's `points_a` is 2 when `a` wins both seat games, 1 on a split, 0.5 when one is a draw and the other a loss; deck-swapped seeds produce two pair records. Orchestrator at T11: `godot --headless --path godot -s res://tools/bot_worker.gd -- --a=greedy --b=greedy --seeds=1-10 --decks=seeded --out=/tmp/x.jsonl --label=t` exits 0 and the `end` record shows 20 games, 0 rejected | implementer |
| 7 | Launcher and driver flags (P16): `--bot=`, `--bot-level=`, `MatchDriver.create(…, bot_name, level)`, `bot=` in the smoke and result lines, `Bot weights:` warning on a load error, errors with no `Main ready` on an unknown name or a level on a reference bot | board, ui | 1 (contract) | `test_match_driver.gd`: the result line carries `bot=tuned`; `create` with `"random"` and level 20 works, with `"random"` and level 5 fails. Boot log at T11: `Engine smoke: … bot=tuned`, `Main ready`; `--bot=nope` logs an error and no `Main ready`; with the weights file renamed, one `Bot weights:` line and `Main ready` | implementer |
| 8 | Driver eval (P18, P19, P22): `scripts/bot/driver.py` (`eval`, `selftest`), `sprt.py`, `records.py` (stamp in Python, aggregates of R27), `scripts/bot-eval.sh`, Makefile `bot-eval` and `bot-selftest`, the report folder layout | tooling | 6 | `scripts/bot/test_sprt.py` (run by `make bot-selftest`): a simulated 0.52 pentanomial gainer passes [0, 25] and a 0.50 one fails within the cap; the Python stamp equals the literal `test_bot_stamp.gd` pins; aggregates computed from a fixture JSONL match hand-counted values. Orchestrator at T11: `make bot-eval BOT=greedy REF=greedy_v1` is a non-regression PASS (identical bots) and `make bot-eval` (tuned vs greedy_v1) prints its line and exits 0; a planted worker exit 1 makes the driver exit 3 naming the worker | implementer |
| 9 | Ledger and process (P23, P24): `docs/planning/bot-ladder.md` with the frontmatter, the rerun checklist and the first two rows (greedy_v1 frozen, tuned v1 default weights); the `/cycle test` skill step for R36; the `cycles.md` header sentence; the specs MOC row | vault, tooling | 2 | `obsidian-cli vault=docs unresolved` and `orphans` report nothing new; the skill step reads as P24; the ledger rows cite the T02 report and T11's `bot-eval` line | orchestrator |
| 10 | Review of T01–T09 against the spec and the Constitution Check, with attention to hidden information (R2, R15, the random and tuned bots' engine calls), determinism (every draw from `decision_rng`, no clock read by a bot, R18), the frozen copy (R21, R22), the gate contract (R30, R35) and the worker's replay check (R26) | all | 1–9 | Ranked findings; blockers fixed before T11 (commits `dc-NN: T10 review fixes`) | reviewer |
| 11 | Verification A (below) | all | 1–10 | All boxes checked | orchestrator |

**Waves (A).** Engine tasks are serial where they share files: T01 → T02, T01 → T03 → T04 →
T05. Tooling and board tasks start from the plan's contracts: wave 1 T01 + T06; wave 2 T02 +
T03 + T07; wave 3 T04 + T08; wave 4 T05 + T09; then T10 and T11. One writer per file per
wave (`match_driver.gd` only in T07; `test_full_match.gd` only in T05).

## Milestone B: training, the matrix bot, calibration

| # | Task | Area | Depends on | Acceptance check | Who |
|---|---|---|---|---|---|
| 12 | Joint preview (P10): `MatchEngine.preview_pair`, hypothesis validation against the public budget and the pending count and slots, hidden-pile independence | engine | 11 | `test_preview_pair.gd`: a pair preview equals `preview()` when the hypothesis is empty; with the opponent committed first, a hypothesis of the wrong count or slots returns `[]`; two engines with the same view, one holding hypothesis card X in the opponent's hand and the other in its deck, return equal scores; the real pending cards never score (a hypothesis of weak cards against a strong real pending gives the weak result); `preview_pair` changes no state, log, event or stream (`full_state()` equal before and after) | implementer-engine |
| 13 | `HandSampler`, `RegretMatching`, `MatrixBot` (P11–P14), `data/matrix_weights.json` (defaults: `k` 6, `k_opp` 3, `samples` 2, `rm_iterations` 50 after C16 and T18; first written as 12 / 12 / 4 / 200), registry `matrix` | engine | 12 | `test_hand_sampler.gd`: `unseen` excludes every id the view shows and includes the rest of the opponent's 20; samples have `opponent_hand_count` distinct ids; the same seed gives the same samples. `test_regret_matching.gd`: matching pennies converges to within 0.05 of uniform; a dominant row gets above 0.95; `sample_index` is deterministic per seed. `test_matrix_bot.gd`: as second committer every opponent hypothesis has the observed count and slots (a stub engine records `preview_pair` arguments); the bot asks only the preview functions; every action over 50 seeds is accepted; same seed and view give the same action; previews per decision ≤ `k · k_opp` + options | implementer-engine |
| 14 | Driver train (P20, P22): `evolve.py`, `driver.py train` with checkpoints, resume, `--hours`, `--run-seed`, promotion through two `eval` runs, weights write with the stamp and a copy of the previous file, the `PROMOTED` / exit 2 lines; `scripts/bot-train.sh`, Makefile `bot-train`; the worker's `--weights-a/-b` already accept candidate files (T06) | tooling | 8 | `scripts/bot/test_evolve.py`: a generation of 16 from a run seed is reproducible; mutation stays within bounds and `k ≤ k_max`; a resumed run from `gen-3.json` continues at generation 4; promotion is refused when either `eval` is FAIL (stubbed). Orchestrator at T18: `make bot-train HOURS=0.2 LABEL=smoke` runs at least one generation, writes checkpoints and exits 0 or 2 with a summary | implementer |
| 15 | Driver calibrate (P21): `driver.py calibrate`, Makefile `bot-calibrate`, the Markdown table and tier suggestion | tooling | 8 | `test_calibrate.py`: the table is built from fixture results with intervals and the band mapping; orchestrator at T18: `make bot-calibrate` prints the table for the grid | implementer |
| 16 | (Moved to the end of DC-11, decision 1a; DC-10 verifies the loop with short runs only.) The training run: `make bot-train` overnight on the tuned bot, then on the matrix bot; promote; commit the weights (`dc-NN: T16 trained weights <stamp>`); ledger rows with the `PROMOTED` lines; if the first night promotes nothing, record the best candidate's result and run a second night with a wider σ | tooling | 13, 14 | At least one promotion per bot or a recorded reason; `make check` green with the new weights; the ledger rows cite the SPRT lines | orchestrator |
| 17 | Review of T12–T16 against the spec and the Constitution Check, with attention to hidden information through `preview_pair` (R48, R49), the sampler's exclusions (R50), float confinement in the regret solver (P13), the promotion rule (R41) and the rerun provision end to end (R36, R38) | all | 12–16 | Ranked findings; blockers fixed before T18 | reviewer |
| 18 | Verification B (below) | all | 12–17 | All boxes checked | orchestrator |

**Waves (B).** Wave 5 T12 + T14 + T15 (T14 and T15 from T08's driver, independent files);
wave 6 T13; then T16 (overnight, orchestrator and Ben), T17, T18. Milestone B runs as its
own cycle on `cycle-7b-bot-players` cut from `master` after A merges (plan, Risks).

## Verification task A (11)

Owned by the orchestrator, on `cycle-7-bot-players`, editor opened on the cycle worktree.

- [x] `make check` exits 0, test stage under 30 s of gdUnit time (C15); record the case
      count. The sweep line
      reads `bot=tuned p95_us=… p99_us=… stamp=match` with `p99_us < 10000`; record
      `slowest_us` (C14).
- [x] Re-pin the seed-1 golden under the tuned bot: smoke and `Board: match ended …` lines
      carry `bot=tuned` and agree across headless `--fixed-fps 60 --autoplay`, the
      `test_match_driver` pin and an editor run; record the line in [[planning/cycles]].
- [x] `--bot=greedy` reproduces cycle 6's golden line (R5); `--bot=nope` and
      `--bot=random --bot-level=3` log an error and print no `Main ready`; with the weights
      file renamed one `Bot weights:` line prints and `Main ready` follows.
- [x] Worker smoke (T06's check) exits 0; `make bot-selftest` passes; `make bot-eval
      BOT=greedy REF=greedy_v1` is PASS; `make bot-eval` (tuned vs greedy_v1) prints its
      summary and exits 0 in about ten minutes; paste the line into the cycles row and the
      ledger; note the first-committer win rate.
- [x] Stamp provision: with `RULES_VERSION` bumped in a scratch worktree, the sweep prints
      `stamp=MISMATCH` and the gate stays green; `make bot-eval` says so on its first line.
- [x] MCP on seed 1 against the tuned bot: seat 1's first commit lands and flips; **one
      screenshot** `godot/reports/DC-NN/tuned-bot-first-commit.png`.
- [x] `obsidian-cli vault=docs unresolved` and `orphans` report nothing new; the `/cycle
      test` skill carries the R36 step; NSC-74 closes with the sweep numbers.

## Verification task B (18)

Owned by the orchestrator, on `cycle-7b-bot-players`.

- [ ] `make check` exits 0; `make sweep` and `make sweep BOT=matrix` each print their line
      with `p99_us` under 10000 (the sweep left the gate, NSC-133, decision 2b). The
      matrix defaults are k 6, k_opp 3, samples 2, rm_iterations 50 (C16; k_opp 4 measured 10.9 ms); if the p99 still
      misses 10 ms, the orchestrator brings the next step down back to Ben. (superseded: the matrix bot and `make sweep BOT=matrix` are gone (DC-13), DC-20 T19)
- [ ] `make bot-eval` (tuned, trained weights, vs greedy_v1) PASS as a gainer; `make
      bot-eval BOT=matrix` vs greedy_v1 PASS and vs the tuned best-so-far PASS (R54); the
      three lines in the ledger and the cycles row. (superseded: the tuned, trained and matrix bots are gone (DC-13), DC-20 T19)
- [x] One match from the training run replays from its log to an equal state (the driver's
      sample check, re-run by hand on one file).
- [ ] `make bot-train HOURS=0.2 LABEL=smoke` resumes from a checkpoint after an
      interruption (the default label is `<bot>-<stamp>` and a checkpoint of another stamp
      is refused, C16); a candidate pending at the interruption is re-promoted first. (superseded: `make bot-train` was deleted in DC-16, DC-20 T19)
- [ ] The calibration table is in the ledger (R55). (superseded: calibration was deleted in DC-16, DC-20 T19)
- [x] `obsidian-cli vault=docs unresolved` and `orphans` report nothing new.

## Linear (exercised 2026-11-04)

- Project: [Cycle 7 — bot players](https://linear.app/night-science-llc/project/cycle-7-bot-players-c711d1c8bc83) (P-NSC-8, state Planned)
- Milestones: created at `/cycle plan`, one per cycle: A `DC-NN bot-players` (T01–T11), B `DC-NN bot-training` (T12–T18)
- Issue mapping: task n is issue NSC-(99 + n); all in Todo, `blockedBy` set from the Depends column

| Task | Issue | Task | Issue |
|---|---|---|---|
| T01 | NSC-100 | T10 | NSC-109 |
| T02 | NSC-101 | T11 | NSC-110 |
| T03 | NSC-102 | T12 | NSC-111 |
| T04 | NSC-103 | T13 | NSC-112 |
| T05 | NSC-104 | T14 | NSC-113 |
| T06 | NSC-105 | T15 | NSC-114 |
| T07 | NSC-106 | T16 | NSC-115 |
| T08 | NSC-107 | T17 | NSC-116 |
| T09 | NSC-108 | T18 | NSC-117 |

## Commit plan

Milestone A is one changeset on `cycle-7-bot-players` (`CLAUDE.md`, Git;
[[decisions/0002-one-branch-per-cycle]]), cut from `master` at `/spec` and re-based onto
`master` once cycle 6 merges (C4). It carries the spec (`spec: cycle-7-bot-players`), the
Linear write-back (`exercise: cycle-7-bot-players`), one commit per task
(`dc-NN: T<nn> <task title>`), review fixes and the verification outcome, each message ending
with the Co-Authored-By line the session provides; `/cycle test` merges it into `master`
with `git merge --no-ff`. Milestone B is a second cycle with no spec of its own: it cuts
`cycle-7b-bot-players` from `master` at its `/cycle plan`, carries T12–T18 the same way (the
trained weights are T16's commit) and merges at its `/cycle test`. Nothing is committed
directly on `master`.

## Review nits (deferred)

Recorded at DC-10 T17 (Ben's 3a, 2026-11-05); the orchestrator files them in Linear.

- `match_engine.gd` is about 927 lines with 19-20 public methods: past the size where a
  split would pay.
- Winner's curse: the best of a generation is picked by its noisy fitness, so its fitness
  is biased upward (the promotion eval is the real test).
- `write_json` in `evolve.py` indents with a tab by default (the checkpoints pass
  `indent=2`): one convention would be tidier.
- `--hours` is per invocation, not cumulative across resumes.
