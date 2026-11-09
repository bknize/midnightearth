---
type: spec
tags: [spec, cycle-13-bot-trainer-b, engine, tooling, bot, training, learner]
status: approved
related: ["[[specs/cycle-13-bot-trainer-b/plan]]", "[[specs/cycle-13-bot-trainer-b/tasks]]", "[[specs/cycle-11-bot-trainer/spec]]", "[[planning/bot-trainer-architecture]]", "[[planning/bot-ladder]]", "[[specs/cycle-7-bot-players/spec]]", "[[planning/cycles]]", "[[planning/phase-1-tech-stack]]"]
created: 2026-11-07
updated: 2026-11-09
uid: 3c3e6b99-3719-4405-b164-29c44ff6db23
linear: https://linear.app/night-science-llc/project/cycle-13-bot-trainer-cycle-b-the-learner-the-linear-bot-rung-1-64d41cbb8498
supersedes:
---

# Spec: Cycle 13 — bot trainer, cycle B (the learner, the `linear` bot, rung 1)

**Slug:** `cycle-13-bot-trainer-b`  ·  **Change type:** engine + tooling  ·  **Status:** approved (Ben, 2026-11-07, two rounds, signed off "Good" 2026-11-07; see Clarifications)

This is cycle B of the bot trainer designed in [[planning/bot-trainer-architecture]] and
built as far as labelled datasets by cycle A ([[specs/cycle-11-bot-trainer/spec]], DC-16 and
DC-17). Ben's decisions T1 to T8 stand and are not reopened: native Windows on the PC (T1),
code by `git bundle` over MCP (T2), the LLM only from cycle C (T3), `linear` as the first
shipped policy form (T4), play-outs to the end of the match (T5), the trainer in `trainer/`
(T6), SSH as `trainer` for maintenance (T7), fixed MCP verbs for runs (T8). Cycle A's facts
stand as facts: the PC labels about 660 positions an hour at `k` 8 × 16 determinizations with
random rollouts (23.7 rollouts a second on 8 workers); the Mac does 9.6 rollouts a second per
worker; `random` is rung 0 at stamp `r7-857b165d5a5d755e`; many random-vs-random positions
are already decided (every candidate −1030), and the rest carry weak signal.

Ben's request, in his words: "After T14 lands, run Cycle B", then "Yes, spec cycle B", after
asking whether bot training would be operational after T14 and being told that cycle A only
produces labelled data and cycle B turns it into a better bot.

## Intent

After cycle B, the game has a `linear` bot that scores a candidate commit from its own view
and the candidate alone, by integer weights that were fitted from play-out labels: the
play-out worker writes each candidate's feature vector into the label, the trainer fits
integer linear weights on the PC and exports a weights file the Mac fetches, measures against
the yardstick and sweeps; the fitted policy then plays the rollouts and the self-play of the
next run, and after two or three such iterations the best policy is rung 1 of the ladder.

## Non-goals

- **No LLM** (T3), **no plan language**, **no plan-aware rollout policy**, **no trees** (T4
  stages b and c are cycles C and D).
- **No card-pair features** (round 1, 2a: the architecture's superset waits for more data).
- **No change to the default bot**: `random` stays `BotRegistry.default_name()`, so the golden
  match, the smoke line and the sweep's coverage counters do not move (round 2, 1a). The board
  reaches `linear` by name only.
- **No `eval` verb on the PC**; every SPRT runs on the Mac (round 2, 3a).
- **No automatic chaining** of run → fit → next run inside the trainer; the orchestrator
  drives each step by its verb (round 2, 4a).
- **No prompt labels** (cycle 11 C6): the `linear` bot answers prompts as `random` does.
- **No edit** to `docs/systems/bot-training.md` (NSC-204 stays blocked on Ben's uncommitted
  edit in the main checkout); the architecture note and the ladder are the records this
  cycle appends to.
- **NSC-231** (PC throughput) and **NSC-233** (deeper trainer cleanups) stay in Backlog;
  **NSC-232** (fold `inspect` into `label`) is done here, since the label reply changes anyway
  (interrogator default, round 2 preamble, not vetoed).
- No board, picker or scene change; no iOS build (D8); no push; nothing on `master`; no token
  anywhere but `.env` and the PC's token file (P6).

## Actors

- **Ben**: decides, keeps the PC on through the training nights, signs off.
- **The orchestrator**: runs the gate, drives the Mac side (`make bot-eval`, `make sweep`),
  the PC over MCP (`sync_code`, `start_run`, `fit`, `get_artifact`) and SSH, commits the
  weights file, writes the ledger and cycle rows, posts to Linear.
- **The engine** (`godot/engine/`): gains the feature function, the weights file reader and
  the `linear` bot.
- **The play-out worker** and **the match worker** (`godot/tools/`): learn the features and
  a named weights file.
- **The driver** (`scripts/bot/driver.py`, `make bot-eval`) and **the sweep**
  (`make sweep BOT=linear`).
- **The trainer service** (PC): gains the learner (`fit`) and `get_artifact`.
- **Implementer-engine, implementer, reviewer**: the roles of `CLAUDE.md`.

## Requirements (EARS)

"The engine" is `godot/engine/`. "A position", "a label", "the seat's view" and "the
stamp" are as cycle 11 defines them. "A candidate" is a legal commit action of the seat at
the position. "A feature vector" is an ordered list of integers computed from the seat's view
and one candidate. "A weights file" is the JSON file of section B. "A fit" is one learner job
over one or more finished runs. "The yardstick" is the ladder's: today `random`, rung 0.

### A. Features (engine)

- R1. The engine shall compute, for a seat's view and a candidate commit, a feature vector of
  whole numbers in a fixed order under a named **feature set**, from the view and the
  candidate only: no play-out, no hidden information, no clock, no generator.
- R2. The feature set shall hold a compact part (the candidate's committed Power, Bonus and
  cost, Budget left, cards committed and kept, the end chosen, both row lengths after the
  commit, both Scores and totals, round wins and wins still needed, Round and Turn, the
  opponent's hand and pending counts, both Deck counts and both Pile sizes, the free first
  card, a pass mark) and one indicator per card id of the card pool counting how many copies
  of that card the candidate commits (round 1, 2a).
- R3. The same view and candidate shall give the same feature vector on every machine, and a
  suite shall pin one vector at the seed-1 position cycle 11 pinned (seat 1's first Round 3
  commit).
- R4. The feature set shall carry a version string; every label, every weights file and the
  bot shall name it, and a weights file whose feature set is not the engine's shall be
  treated as broken (R9).

### B. The `linear` bot and its weights file (engine)

- R5. The registry shall know a bot named `linear` that, at a commit decision, scores each
  candidate by the integer sum of its features times the weights (in hundredths) and commits
  the highest-scoring candidate, ties broken uniformly by its per-decision seed; it shall
  satisfy cycle 7 R2 and R3 (own view and seed only; never an action the engine rejects).
- R6. While the candidates of a hand number more than the weights file's `k`, the `linear`
  bot shall score `k` of them drawn uniformly by its per-decision seed, and a hand too large
  to enumerate shall be sampled as `random` samples it.
- R7. When a prompt is open for its seat, the `linear` bot shall answer as `random` would with
  the same seed.
- R8. The weights file shall be a JSON object carrying a format version, the bot name, the
  stamp, the feature-set version, `k`, the fit that produced it (its id, the run ids and the
  dataset digest) and the weights by feature name as whole numbers in hundredths; the
  engine shall read it from the committed path under `godot/engine/bot/data/` by default
  and from any given path when a caller names one.
- R9. If the weights file is missing, malformed, of another format version or feature set,
  names an unknown feature or holds a weight that is not whole or out of range, then the
  `linear` bot shall use its built-in default weights (committed Power counted once,
  everything else 0) and the launcher shall print one `Bot weights:` line naming the fault;
  the engine itself shall print nothing (cycle 7 R11).
- R10. The `linear` bot built on the committed weights file shall pass the quiet 50-seed
  sweep (`make sweep BOT=linear`) with a p99 decision under 10 ms on the Mac, and the sweep
  shall print `stamp=match` or `stamp=MISMATCH` for the weights file it swept.
- R11. The sweep shall accept a weights file path (`make sweep BOT=linear WEIGHTS=<path>`)
  and build the bot on it, so a candidate file is swept before it is committed.
- R12. `random` shall stay the default bot, and the seed-1 golden
  (`seed=1 decks=combo/graveyard bot=random winner=1 wins=3-4 rounds=7 end=wins
  actions=265`) and the `random` sweep shall be unchanged (round 2, 1a).

### C. The workers (tooling under `godot/`)

- R13. The play-out worker's `label` reply shall carry, per candidate, its feature vector,
  and shall carry the feature-set version, the position's Round and Turn and the seat's hand
  as card ids and names; the `inspect` request shall be removed (NSC-232).
- R14. The play-out worker's `label` and `play` requests shall accept an optional weights
  file path for the rollout bot and for the generator bot, used when the named bot is
  `linear`; without one the committed file is used.
- R15. The match worker shall accept an optional weights file path per side and build a
  `linear` side on it; its end record shall say whether every weights file used carries the
  current stamp.
- R16. Two runs of the same requests, on one worker or spread over eight, shall give the same
  label digest (cycle 11 R31 kept; the digest changes once with the new reply shape, and
  cycle A's digests are not comparable with cycle B's).

### D. The driver and `make bot-eval` (tooling under `scripts/`)

- R17. The driver shall accept a weights file path per side (`--weights-a`, `--weights-b`),
  pass each to the match worker, and print `stamp=match` when every weights file used
  carries the current stamp and `stamp=MISMATCH` otherwise, in the summary line of cycle 11
  R11; `bot-eval.sh` and `make bot-eval` shall pass a `WEIGHTS` path through to side `a`.
- R18. `make bot-eval BOT=linear REF=random` with `--gainer` on the committed weights file
  shall be the ladder's rung-1 measurement (R4 of [[planning/bot-ladder]]); every SPRT of this
  cycle runs on the Mac (round 2, 3a).
- R19. The driver shall run unchanged on macOS and native Windows (cycle 11 R12 kept).

### E. Labels with features, the run config (trainer)

- R20. Every label the trainer stores and every shard line shall carry the candidate's
  feature vector and the run's feature-set version; every position shall carry Round, Turn
  and the hand (from the `label` reply, R13).
- R21. The run config shall gain `rollout_weights` and `generator_weights`, each the id of a
  fit whose weights file the trainer holds (or empty for none), and the trainer shall give
  the workers that file's path for the `linear` bot; a config naming an unknown fit shall be
  returned as an error, not started.
- R22. A run shall record the stamp, the commit and the feature-set version it was labelled
  under, and `get_report` and `list_runs` shall show them.

### F. The learner: `fit` (trainer)

- R23. The trainer shall expose a `fit` verb taking a typed config (the run ids to learn
  from, an L2 strength, an iteration count, a holdout fraction, a fit seed, `k` for the
  weights file) with defaults, shall validate it and return a fit id; a run that is not
  `done` or `stopped`, or that is under another stamp or feature set than the others, shall
  be refused by name.
- R24. The fit shall learn a pairwise ranking: within each position, every pair of candidates
  whose mean values differ is one example ordered by the higher mean; positions whose
  candidates all share one value contribute nothing (the decided positions of random play
  drop out by themselves).
- R25. The fit shall hold out a fraction of positions chosen by the fit seed, fit on the rest,
  and report the pair count, the share of pairs ordered correctly on the fitted and the
  held-out positions, the same share after the weights are made whole numbers, and the ten
  weights largest in magnitude with their names.
- R26. The fit shall write a weights file of section B (R8) under the trainer's data folder,
  named by the fit id, carrying the stamp, the feature-set version, the run ids and the
  dataset digest of the runs it learned from.
- R27. The same fit config over the same runs shall give the same weights file on the same
  machine.
- R28. A fit shall run as a job: `run_status`, `list_runs` and `get_report` shall answer for a
  fit id as they do for a run id; one fit at a time; a fit may run while a labelling run is
  active, since it reads only finished runs.
- R29. The trainer shall run with the Python standard library, the `mcp` package and
  **numpy** (round 1, 4b; cycle 11 R39 amended); `make trainer-test` shall skip the learner
  tests on a machine without numpy and run everything else.

### G. `get_artifact` (trainer)

- R30. The server shall expose `get_artifact(fit_id, name)` returning the fit's weights file
  or its report inline (base64) with its byte length and SHA-256; an unknown fit or name
  shall be an error. The server's tool set shall then be exactly the nine of cycle 11 R43
  plus `fit` and `get_artifact`, and still no tool that runs a shell or an arbitrary command.
- R31. Dataset shards shall stay reachable over SSH (`scp`) only; `get_artifact` serves fits.

### H. Iteration and promotion (the orchestrator's loop; round 1, 3a; round 2, 2a, 4a)

- R32. The cycle shall run at least two and at most three iterations: iteration 0 labels
  4,000 positions with `random` as rollout and generator; each later iteration labels 2,000
  positions with the previous iteration's weights as rollout and generator; every run keeps
  `k` 8, 16 determinizations and the 8 h cap (`stop_run`/`resume_run` across a night if the
  cap ends a run early).
- R33. When a fit's weights file is fetched, the orchestrator shall sweep it (R11) and run the
  gainer SPRT against the yardstick on the Mac (R18); from iteration 1 on it shall also run
  the gainer SPRT of the new weights against the previous iteration's weights, and the
  **best** weights are the last that beat their predecessor (iteration 0's if none did).
- R34. When the best weights pass the gainer SPRT against the yardstick and the quiet sweep,
  the orchestrator shall commit them as the committed weights file, add the rung-1 row to
  [[planning/bot-ladder]] (bot, stamp, fit id, the `bot-eval` line, the sweep line) and the
  `linear` bot becomes the yardstick; if no iteration passes, then nothing is promoted, the
  committed file stays the best fit so far marked unproven in the ladder's note, and the
  cycle still closes with every measurement in its row (round 1, 1a).
- R35. Every iteration's run id, fit id, agreement figures, `bot-eval` line and sweep line
  shall be written in the cycle's row of [[planning/cycles]].

### I. The gate and verification

- R36. `make check` shall be green at the end of every task, gdUnit under the 30 s budget,
  with the new engine modules and both workers typed-strict under `parse` and lint.
- R37. `make trainer-test` shall be green on the Mac and on the PC (numpy present on the PC;
  skips reported on a machine without it).
- R38. The cycle shall be proven by text lines, not screenshots (engine and tooling): the
  pinned feature vector, the `linear` suite, the sweep lines, the `bot-eval` lines, the fit
  reports, the label digest equal on 1 and 8 workers, and the ledger row.

## Clarifications (Ben, 2026-11-07; C9 2026-11-08)

| # | Question | Answer |
|---|---|---|
| C1 | Round 1 Q1, what "a better bot" means: (a) rung 1 under R4 (gainer PASS against `random` plus the quiet sweep p99 under 10 ms), a PASS is the bar, no win-rate target, and the cycle closes with the loop built even if nothing passes; (b) PASS plus win rate ≥ 0.60; (c) the pipeline is the deliverable, promotion a bonus | 1a |
| C2 | Round 1 Q2, what the bot scores: (a) about 20–30 compact position-and-candidate features plus one indicator per card id (91), computed by the worker into every label so the bot and the dataset agree by construction; (b) the compact set only; (c) (a) plus card-pair co-occurrence (+1 task M) | 2a |
| C3 | Round 1 Q3, bootstrapping: (a) expert iteration in the cycle, the fitted weights become the rollout and generator policy of the next run, two or three iterations, the best by gainer SPRT to the ladder; (b) one pass only; (c) (a) plus an epsilon of random moves in the generator | 3a |
| C4 | Round 1 Q4, where the fit runs: (a) PC, pure stdlib `fit` verb; (b) PC with numpy in the venv, R39 amended; (c) Mac | 4b |
| C5 | Round 2 Q1, shipping: (a) `linear` in the registry over one committed weights file, reachable by name, default bot stays `random`; (b) default becomes `linear` once promoted (+1 task M) | 1a |
| C6 | Round 2 Q2, run sizes: (a) 4,000 random-rollout positions, then 2,000 per iteration with the fitted policy, three nights; (b) half; (c) 8 determinizations, twice the positions | 2a |
| C7 | Round 2 Q3, measurement: (a) Mac only, `bot-eval` gains `--weights`, no `eval` verb on the PC; (b) plus an `eval` verb (+1 task M) | 3a |
| C8 | Round 2 Q4, closing: (a) the iterations are the verification, the branch lives for the nights, `/cycle test` after the last; (b) close after iteration 0, iterate after the merge | 4a |
| C9 | DC-18 T09, 2026-11-08: iteration 0's gainer against `random` stopped (exit 3) on two `greed` mirrors that hit the 2,000-action cap. In sudden death the F0 bot held its last card and passed every turn, the other seat had no cards, every Round tied 0-0, and `MatchEngine._stalled()` (cycle 9 C12) fires only with both hands empty. Q1 the rule: (a) a sudden-death Round in which neither seat commits a card ends the Match as a stalemate (higher Match total Score wins, equal totals draw), `RULES_VERSION` 7 to 8, night 1 rerun under the new stamp; (b) the same rule with no version bump; (c) leave the rules, `bot-eval` scores a capped game as a draw. Q2 timing: (a) fix first, gainer reruns clean, then night 2; (b) night 2 now, fix in parallel | Ben: "1a 2a". New stamp `r8-857b165d5a5d755e`; night 1 (run c61172712da8, fit 91579a1f5ef6) is superseded and rerun as iteration 0 under r8 |

Defaults stated by the interrogator and not vetoed (round 2 preamble and this spec): NSC-232
folded in, NSC-231 and NSC-233 left in Backlog; a fit reads the runs named in its config, the
latest iteration's run by default, never a mix of rollout policies by accident (R23 refuses
mixed stamps or feature sets, and the orchestrator names one run per fit); the built-in
default weights count committed Power once (R9); ties in the `linear` bot are broken by its
decision seed (R5); `k` for the `linear` bot defaults to 64 candidates; the run config's
`hours` stays 8; from iteration 1 the new weights are also measured against the previous
iteration's (R33); the committed weights file lives at `godot/engine/bot/data/linear_weights.json`;
cycle A's label digests are not comparable with cycle B's (R16).

## Scenarios

- **Given** seed 1 replayed to seat 1's first Round 3 commit and the candidate cycle 11
  pinned, **when** the engine computes the feature vector, **then** it equals the pinned
  vector on the Mac and on the PC, its compact part names Round 3 and the right Turn, and its
  card indicators sum to the candidate's card count (R1 to R3).
- **Given** a weights file with `committed_power` 100 and everything else 0, **when** the
  `linear` bot chooses at a position with an affordable high-Power card, **then** it commits
  the candidate with the highest committed Power, the same one on every run (R5).
- **Given** a weights file with one unknown feature name, **when** `godot --headless --bot=linear`
  runs the smoke, **then** the launcher prints one `Bot weights:` line, the bot plays with the
  defaults and the match finishes (R9).
- **Given** `make sweep BOT=linear WEIGHTS=/tmp/f0.json`, **when** it runs, **then** the sweep
  line ends `bot=linear p95_us=.. p99_us=.. stamp=match` with `p99_us` under 10000 (R10, R11).
- **Given** a 12-position run on the PC, **when** the shards are read, **then** every label
  line holds a `features` list of the feature set's length and the feature-set version, and
  every position holds Round, Turn and the hand (R13, R20).
- **Given** two finished runs under one stamp, **when** `fit` names both with the defaults,
  **then** `run_status` shows the fit running then done, `get_report` shows pair count, fitted
  and held-out agreement, agreement after quantization and the top ten weights, and
  `get_artifact(fit, "weights")` returns a file whose `fit.runs` lists both run ids (R23 to
  R26, R30).
- **Given** that fit run twice with the same config, **when** both weights files are compared,
  **then** they are byte-equal (R27).
- **Given** a run config with `rollout_weights` set to a fit id, **when** the run labels a
  position, **then** the rollouts are played by `linear` on that fit's file, and the same
  position labelled by the Mac's worker with the same file gives the same values (R14, R21).
- **Given** iteration 1's weights, **when** `make bot-eval BOT=linear WEIGHTS=<f1> REF=random
  --gainer` runs and then the same against iteration 0's file, **then** two `bot-eval:` lines
  are kept and the best weights follow R33.
- **Given** the best weights pass both gates, **when** the orchestrator commits them, **then**
  `godot/engine/bot/data/linear_weights.json` carries the stamp `r7-…`, the ladder has a
  rung-1 row and `make check` and `make sweep` (random) are unchanged (R12, R34).

## Data touched

- New: `docs/specs/cycle-13-bot-trainer-b/{spec,plan,tasks}.md`; by its tasks: the engine's
  feature module, weights reader and `linear` bot with their suites; the committed weights
  file `godot/engine/bot/data/linear_weights.json`; `trainer/fit.py` and its tests; the
  `fits` table and `fits/<id>/` folder in the trainer's data store.
- Changed: `godot/engine/bot/bot_registry.gd` (the `linear` name, a weights path), the
  launcher's one warning line (`godot/main.gd`, `godot/board/match_driver.gd`),
  `godot/tools/playout_protocol.gd`, `playout_handler.gd`, `match_worker.gd` and its records,
  `godot/tests/sweep/test_sweep.gd` (`SWEEP_WEIGHTS`, the stamp field), `scripts/bot/driver.py`,
  `records.py`, their tests, `scripts/bot-eval.sh`, the Makefile (`WEIGHTS`), `trainer/config.py`,
  `run.py`, `store.py`, `server.py`, `farm.py`, `trainer/tests/*`, `trainer/windows/SETUP.md`
  (numpy in the venv), [[planning/bot-ladder]] (rung 1 or the unproven note),
  [[planning/cycles]] (the cycle row), one row in [[specs/specs-moc]] (added by the
  orchestrator).
- Read only: the rest of `godot/engine/`; `docs/rules/*`; `docs/planning/*` except the two
  notes above; the archive.
- Never: `docs/.obsidian/`; `godot/addons/*`; `.env`; `godot/.godot/`; `godot/reports/`; the
  archive; `docs/systems/bot-training.md` (NSC-204 waits for Ben); the token.

## Definition of done

- [ ] `make check` green, gdUnit under 30 s; golden unchanged; `make sweep` (random)
      unchanged (R12, R36). (superseded: gdUnit ran 30.8 s, waived by Ben 2a, NSC-251, DC-20 T19)
- [x] Feature suite: the pinned seed-1 vector, the card indicators, every feature a whole
      number from the view and the candidate only (R1 to R4).
- [x] `linear` suite: highest score wins, ties by seed, `k` sampling, prompts as `random`,
      the broken-file fallback and the one `Bot weights:` line (R5 to R9).
- [x] `make sweep BOT=linear [WEIGHTS=…]` p99 under 10 ms with `stamp=` printed (R10, R11).
- [x] The label reply and shards carry features, Round, Turn and hand; `inspect` is gone; the
      digest is equal on 1 and 8 workers (R13, R16, R20).
- [x] `make bot-eval BOT=linear WEIGHTS=… REF=random` runs on the Mac with `stamp=` right
      (R17, R18); `make bot-selftest` green.
- [x] `make trainer-test` green on the Mac (learner tests skipped without numpy) and on the PC
      (R29, R37); `fit`, `get_artifact`, the extended `run_status`/`list_runs`/`get_report`
      and the two new config fields proven over MCP (R21 to R30).
- [ ] Iterations run per R32 and R33, each line and figure in the cycle row (R35). (iterations 1 and 2 moved to NSC-243, DC-20 T19)
- [x] Rung 1 promoted per R34, or nothing promoted and the measurements recorded (C1).
- [x] No screenshot: proof by text lines (R38).
- [x] Constitution Check passes (see plan); spec, plan and tasks signed off by Ben and
      committed before implementation begins.
