---
type: tasks
tags: [tasks, cycle-13-bot-trainer-b, engine, tooling, bot, training, learner]
status: approved
related: ["[[specs/cycle-13-bot-trainer-b/spec]]", "[[specs/cycle-13-bot-trainer-b/plan]]", "[[specs/cycle-11-bot-trainer/tasks]]", "[[planning/bot-ladder]]", "[[planning/cycles]]", "[[planning/phase-1-tech-stack]]"]
created: 2026-11-07
updated: 2026-11-09
uid: 0ff43372-b685-419c-a103-2573766111cd
supersedes:
---

# Tasks: Cycle 13 — bot trainer, cycle B

Derived from [[specs/cycle-13-bot-trainer-b/plan|plan]]. Numbered, dependency-ordered,
independently reviewable. Each task names its area, its acceptance check and who does it.
`implementer` edits code in a worktree; `implementer-engine` takes anything under
`godot/engine/`; `reviewer` reads a diff and returns findings; `orchestrator` runs
`make check`, drives the workers, the PC and Linear. Sizes: S under half a day of agent
work, M about a day, L more. One milestone, one branch (`cycle-13-bot-trainer-b`); T09 to
T11 span the training nights (spec C8).

| # | Task | Area | Depends on | Acceptance check | Who | Status |
|---|---|---|---|---|---|---|
| T01 | **Features.** `godot/engine/bot/bot_features.gd` (plan P1): `SET_VERSION`, `names()`, `of()`, the 33 compact features and the `card:<id>` indicators in `CardDb` order. Suite `test_bot_features.gd`: every feature from hand-built views (a pass, a right-end commit, the free first card, grown cards, a sudden-death round); the card indicators sum to the committed count; the pinned vector at the seed-1 position cycle 11 pinned (seat 1's first Round 3 commit, same candidate). (M) | engine, tests | – | Suite passes; `make check` green; the pin's values quoted in the task's commit message for the verification (spec R3). | implementer-engine | done |
| T02 | **Weights file, the `linear` bot, the registry.** `bot_weights.gd` (plan P2, from `2ef6664^` cut to R8: version 2, `features`, `k`, `fit`, `cached()`, `stamp_matches()`, `vector()`), `linear_bot.gd` (plan P3: scoring, `k` sampling, ties by seed, prompts through a `RandomBot`), `bot_registry.gd` (`NAMES`, `make_with()`, `weights_error()`; `default_name()` stays `random`), the one `Bot weights:` line in `godot/main.gd` and `godot/board/match_driver.gd` (plan P4), `Rollout.play()`/`label()` taking `weights_path`, and the committed defaults file `godot/engine/bot/data/linear_weights.json` (plan P15, stamped `r7-857b165d5a5d755e`). Suites `test_bot_weights.gd` (round trip, every fault of R9 gives the defaults with `load_error`, `stamp_matches`) and `test_linear_bot.gd` (highest score wins on a hand-built view, ties by seed are deterministic, `k` sampling keeps `k`, a hand over `ENUMERATE_MAX` is sampled, a prompt answer equals `random`'s with the same seed, cycle 7 R3 on 50 seeds of decisions through the harness). (L) | engine, tests, data | T01 | Suites pass; `make check` green; golden and `make sweep` (random) unchanged; `grep -rn "linear" godot/main.gd` shows only the warning path. | implementer-engine | done |
| T03 | **Workers and the sweep.** Protocol v2 in `playout_protocol.gd` and `playout_handler.gd` (plan P5: `features`, `feature_set`, `round`, `turn`, `hand` in the `label` reply, `rollout_weights`/`generator_weights`, `inspect` removed, `hello` with `feature_set`); `match_worker.gd` and `match_worker_records.gd` with `--weights-a=`/`--weights-b=` and `weights_stamp` (plan P6); `godot/tests/sweep/test_sweep.gd` reading `SWEEP_WEIGHTS` and printing `stamp=` (plan P6). Suite `test_playout_protocol.gd` updated (an `inspect` line is now an error reply; a label reply builder carries the features list in order). (M) | tooling (godot/tools, tests/sweep) | T02 | Suites pass; `make check` green; the 20-position request file gives one digest on 1 and 8 workers (T08). | implementer | done |
| T04 | **Driver, `bot-eval.sh`, Makefile.** `driver.py eval --weights-a/--weights-b` forwarded to the worker, `stamp=match|MISMATCH` from the end records' `weights_stamp` (plan P7), `records.py` reading the new field, `test_records.py`/`test_sprt.py` updated; `bot-eval.sh --weights`; Makefile `WEIGHTS` for `bot-eval` (and `sweep`, already forwarded). Windows-safe (R19). (S) | tooling (scripts, Makefile) | T03 | `make bot-selftest` green; `python3 -I scripts/bot/driver.py eval --help` shows both flags; a dry `make bot-eval BOT=linear REF=random SEEDS=1-4` ends `exit=0` with `stamp=match` (T08). | implementer | done |
| T05 | **Trainer: features in the store, weights in the config.** `config.py` (`rollout_weights`, `generator_weights`), `store.py` (`labels.features`, `runs.feature_set`, table `fits`, migration of a cycle A database, shard lines with `features`; plan P9), `run.py` (the `label` reply's `features`, `round`, `turn`, `hand` into the store, no `inspect`, weights paths into requests; plan P8), `server.py` (`start_run` resolving fit ids to paths and refusing unknown ones, `health` with numpy's version or `none`), `trainer/tests/stub_worker.py` speaking v2, tests for each. (M) | trainer | T03 | `make trainer-test` green; a stub-worker run's shard lines carry `features` lists and `feature_set`; a cycle A `trainer.db` fixture opens and migrates. | implementer | done |
| T06 | **The learner, `fit` and `get_artifact`.** `trainer/fit.py` (plan P10: pairs, scaling, logistic L2 by full-batch gradient descent, holdout, agreement before and after quantization, export of the weights file and `report.json`), `FitConfig` and the `fit` job in `server.py` (plan P11), `get_artifact` (plan P12), fits answered by `run_status`/`list_runs`/`get_report`; `windows/SETUP.md` Part 1 with numpy (plan P13); tests per plan P14 (`test_fit.py` skipped without numpy). (L) | trainer | T05 | `make trainer-test` green (learner tests run where numpy is present); the synthetic recovery test passes with held-out agreement above 0.95; two fits of one config give byte-equal files; the tool list is the eleven of spec R30. | implementer | done |
| T07 | **Review.** Read T01 to T06 against the spec: features from the view and the candidate only (R1), determinism and integer arithmetic (R3, R5), the fallback and the single warning line (R9), the default bot untouched (R12), protocol v2 and the digest (R13, R16), Windows-safety (R19), the fit's determinism and refusals (R23, R27), no shell tool (R30). Findings only. | review | T01–T06 | Findings posted; blockers and should-fixes dispatched and merged before T08. | reviewer | done |
| T08 | **Verification on the Mac and the PC smoke.** Mac: `make check` (gdUnit under 30 s); golden unchanged; `make sweep` (random) unchanged; `make sweep BOT=linear` on the defaults file with p99 under 10 ms and `stamp=match`; the pinned feature vector printed; `make bot-selftest`; `make bot-eval BOT=linear REF=random SEEDS=1-20` (defaults file, line kept); the play-out worker's 20-position digest equal on 1 and 8 workers (new digest recorded); `make trainer-test` on the Mac (skips noted) and, over SSH as `trainer`, numpy installed in the venv and `make trainer-test`'s command green on the PC. PC over MCP: `sync_code` of the branch head; `health` shows numpy; a 12-position run with `k` 8 × 16 determinizations whose shards carry features; `fit` on it, `run_status`/`get_report` for the fit, `get_artifact` for weights and report with sha256 checked; one position of that run labelled again by the Mac's worker with the fetched file as `rollout_weights`, values equal; a `start_run` naming an unknown fit refused. Cycle row started. No screenshot (R38). | verification | T07 | Every Mac and PC smoke box of the spec's definition of done ticked except the iteration and promotion boxes. | orchestrator | done |
| T09 | **Iteration 0.** Per plan P16: `start_run` 4,000 positions, `random` rollout and generator, 8 workers, `run_seed` 1300; `resume_run` across the 8 h cap if needed; `fit` on the run; `get_artifact`; `make sweep BOT=linear WEIGHTS=<F0>`; `make bot-eval BOT=linear WEIGHTS=<F0> REF=random --gainer`; run id, fit id, pairs, agreements and both lines in the cycle row. | verification (PC night 1) | T08 | The row holds iteration 0's figures and lines (spec R35). | orchestrator | done |
| T10 | **Iterations 1 and 2.** Per plan P16: 2,000 positions each with the previous fit as `rollout_weights` and `generator_weights` (`run_seed` 1301, 1302); fit, fetch, sweep, gainer against `random` and gainer against the previous iteration's file; the best weights per spec R33; iteration 2 skipped only when spec R32's two-iteration case applies. Figures and lines in the cycle row. | verification (PC nights 2–3) | T09 | The row holds every iteration's figures; the best weights named. | orchestrator | todo |
| T11 | **Promotion and close.** If the best weights pass both gates: commit them as `godot/engine/bot/data/linear_weights.json` (`dc-NN: T11 linear weights r7-… (fit <id>)`), `make check` and `make sweep` (random) unchanged, `make sweep BOT=linear` and `make bot-eval BOT=linear REF=random --gainer` on the committed file (lines kept), rung-1 row in [[planning/bot-ladder]] and `linear` named the yardstick; else commit the best fit's file, mark `linear` unproven in the ladder note and record why (spec R34). Cycle row completed; specs MOC row checked; link audit (`obsidian-cli vault=docs unresolved` and `orphans`). No screenshot (R38). | verification | T10 | Every box of the spec's definition of done ticked. | orchestrator | todo |

## Verification task (always last)

Tasks T08 to T11, owned by the orchestrator:

- [x] `make check` exits 0 after every task; `make trainer-test` exits 0 on both machines.
- [ ] End-to-end proof by lines: the pinned feature vector; `Sweep:` lines for `random`
      (unchanged) and `linear` (p99 under 10 ms, `stamp=match`); `bot-eval:` lines for every
      iteration against `random` and against the previous iteration; fit reports with pairs
      and agreements; the label digest equal on 1 and 8 workers; the Mac re-label equal to
      the PC's values under the fitted rollout. (iterations 1 and 2 moved to cycle-13 T10, DC-20 T19)
- [ ] Rung 1 in [[planning/bot-ladder]] (or the unproven note) and the cycle row in
      [[planning/cycles]] with every iteration. (promotion moved to cycle-13 T11, DC-20 T19)
- [x] No screenshot: engine and tooling cycle (spec R38), proof by text lines.
- [x] `obsidian-cli vault=docs unresolved` reports nothing new.

## Waves (a proposal for `/cycle plan`)

(1) T01; (2) T02; (3) T03; (4) T04, T05; (5) T06; (6) T07; (7) T08; (8) T09 (night 1);
(9) T10 (nights 2 and 3); (10) T11.

## Commit plan

The whole cycle is one changeset on one branch named for the spec slug
(`cycle-13-bot-trainer-b`; `CLAUDE.md`, Git), cut from `master` (086a9bf) at `/spec` before
the first note. It carries the spec (`spec: cycle-13-bot-trainer-b`), the Linear write-back
(`exercise: cycle-13-bot-trainer-b`), one commit per task (`dc-NN: T<nn> <task title>`),
review fixes, the weights file commit of T11 and the verification outcome, each message
ending with the Co-Authored-By line the session provides. The branch lives through the
training nights (spec C8). When T11 passes, `/cycle test` merges the branch into `master`
with a merge commit (`git merge --no-ff`) so the cycle stays visible in history. Nothing is
committed directly on `master`. Never push.
