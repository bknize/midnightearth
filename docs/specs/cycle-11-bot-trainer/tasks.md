---
type: tasks
tags: [tasks, cycle-11-bot-trainer, engine, tooling, bot, training, windows, mcp]
status: approved
related: ["[[specs/cycle-11-bot-trainer/spec]]", "[[specs/cycle-11-bot-trainer/plan]]", "[[planning/bot-trainer-architecture]]", "[[planning/bot-ladder]]", "[[planning/cycles]]", "[[planning/phase-1-tech-stack]]"]
created: 2026-11-07
updated: 2026-11-07
uid: 091e8cb1-63a1-43fe-9c19-8554d6a5fc73
linear:
supersedes:
---

# Tasks: Cycle 11 — bot trainer, cycle A

Derived from [[specs/cycle-11-bot-trainer/plan|plan]]. Numbered, dependency-ordered,
independently reviewable. Each task names its area, its acceptance check and who does it.
`implementer` edits code in a worktree; `implementer-engine` takes anything under
`godot/engine/`; `reviewer` reads a diff and returns findings; `orchestrator` runs
`make check`, drives the workers, the PC and Linear.

Two milestones (spec C1): **A1** is T01 to T07 on `cycle-11-bot-trainer`; **A2** is T08 to
T14 on `cycle-11b-bot-trainer`, cut from `master` after A1 merges. Sizes: S under half a
day of agent work, M about a day, L more.

## Milestone A1: the Mac side

| # | Task | Area | Depends on | Acceptance check | Who |
|---|---|---|---|---|---|
| T01 | **The stamp.** Restore `godot/engine/bot/bot_stamp.gd` over the three data files (plan P1); suite `test_bot_stamp.gd`: the string shape `r7-<16 hex>`, a changed Crew byte changes it, a missing file gives `""`. Make `records.py`'s `rules_version()` and `current_stamp()` path-safe and pin the engine's value in `test_records.py` from a fixture of the three files. (S) | engine, tooling | – | Suite passes; `python3 -I scripts/bot/driver.py selftest` passes; the two stamps are equal when the orchestrator prints both (T07). | implementer-engine |
| T02 | **The match worker.** `godot/tools/match_worker.gd` and `match_worker_records.gd` with the cycle 7 contract minus levels and weights (plan P2): seed pairs with deck swaps, timed decisions, replay of every game, exit codes 0/1/2/3, end record with the stamp. Suite `test_match_worker_records.gd` for the record builders. (M) | tooling (godot/tools), tests | T01 | Suite passes; `make check` green with the worker typed-strict; a 4-seed worker run writes `d`, `g`, `p`, `end` lines the driver aggregates (T07). | implementer |
| T03 | **The driver on both platforms, the old tooling gone.** `driver.py` keeps `eval` and `selftest` (`--batch`, no weights, `os.path`/`pathlib`, no shell, `GODOT_BIN` `.exe`-safe), `records.py` loses weights helpers; delete `evolve.py`, `calibrate.py`, `test_evolve.py`, `test_calibrate.py`, `fixtures/matrix_weights.json`, `scripts/bot-train.sh`, the `bot-train` and `bot-calibrate` Makefile targets; `bot-eval.sh` and the Makefile default to `random` vs `random`; `bot-selftest` stays. (M) | tooling (scripts, Makefile) | T02 | `make bot-selftest` green; `git ls-files scripts/bot` shows only `driver.py`, `records.py`, `sprt.py`, their three tests and `fixtures/{a,b}.jsonl`; `make bot-eval` ends `exit=0` near 0.500 (T07). | implementer |
| T04 | **The rollout entry and determinization.** `MatchEngine.from_state()` (training-only), `godot/engine/rollout.gd` with `hidden_sets`, `determinize`, `play`, `label` (plan P5 to P8, P10). Suite `test_rollout.gd`: hidden sets per owner on hand-built states (a face-down Fade card, a looked-at card, `deck_top`, a created Dross in the other hand); the seat's view of the copy equals the original's `to_dict()`; the real match's `full_state()` is unchanged after 16 rollouts; same seeds same values; the value formula; `capped` and `rejected`; the seed-1 pin (value and action count of one rollout at seat 1's first Round 3 commit under `random`). No bot or scene references `Rollout`. (L) | engine, tests | – | Suite passes within budget; `make check` green; `grep -rn Rollout godot/engine/bot godot/board godot/main.gd` is empty. | implementer-engine |
| T05 | **The play-out worker.** `godot/tools/playout_protocol.gd` (request parsing, reply building, field order, the digest's excluded fields) and `godot/tools/playout_worker.gd` (`hello`, `play`, `label`, error replies, `quit`, flush per line; plan P9 to P11). Suite `test_playout_protocol.gd` for parsing and building, including a prefix that fails to replay giving an error reply object. (M) | tooling (godot/tools), tests | T04 | Suite passes; `make check` green; the orchestrator's 20-position request file gives one digest on 1 and on 8 workers (T07). | implementer |
| T06 | **Review A1.** Read the diffs of T01 to T05 against the spec's A to D: determinism (R18, R19, R23), the hidden-set rule (R17), the worker contracts, Windows-safety of the Python (R12), nothing reachable from live play (R24). Findings only. | review | T01–T05 | Findings posted; blockers and should-fixes dispatched and merged before T07. | reviewer |
| T07 | **Verification A1.** `make check` (gdUnit under 30 s); `make sweep` clean and the golden unchanged (R59); engine and driver stamps printed and equal (R1); `make bot-selftest`; `make bot-eval` `random` vs `random` (R13, line kept for the ledger); a 4-seed match-worker run inspected; the play-out worker smoke: `hello`, `play` seed 1, `label` the seed-1 position with `k` 8 and 16 determinizations, an error, `quit`; the 20-position digest on 1 and 8 workers (R31); rollouts per second per worker recorded; ladder note rewritten (`## Rungs` with `random` at rung 0 and the stamp, the rules of R4 and R5, no Calibration block); specs MOC row; DC row in [[planning/cycles]]; link audit. No screenshot (engine and tooling, spec R60). | verification | T06 | Every box of the spec's A1 definition of done ticked. | orchestrator |

## Milestone A2: the PC side (`cycle-11b-bot-trainer`)

| # | Task | Area | Depends on | Acceptance check | Who |
|---|---|---|---|---|---|
| T08 | **Trainer package skeleton, seeds, store, config.** `trainer/__init__.py`, `__main__.py` (`serve`, `run`, `selftest` stubs), `seeds.py` (splitmix64 `derive` pinned against three engine values), `config.py` (dataclass, defaults, validation errors), `store.py` (sqlite3 tables, batch commit with the JSONL shard in one transaction, digest, resume point, `interrupted` on startup), `trainer/tests/` for each, `make trainer-test`, `.env.example` and `.mcp.json` entries (plan P12, P16, P19). (M) | trainer, tooling | A1 merged | `make trainer-test` green; `python3 -I -m trainer selftest` exits 0; `.mcp.json` has `${BOT_TRAINER_URL}` and `${BOT_TRAINER_TOKEN}` only, no literal. | implementer |
| T09 | **Farm and run loop.** `farm.py` (worker pool over pipes, reply threads, restart and re-queue, timeout) and `run.py` (generate, pick, label, batches, stop at a boundary, resume from the store; plan P13, P14); `python -I -m trainer run --config` for a local run; tests with a Python stub worker speaking the protocol: ordering, batch atomicity, resume equals uninterrupted (digest), restart counting. (L) | trainer | T08 | `make trainer-test` green; a stub-worker run of 100 positions stopped at 40 and resumed gives the uninterrupted digest. | implementer |
| T10 | **MCP server, verbs, token.** `server.py`: `MCPServer`, streamable HTTP, bearer check (plan P15), the nine tools of R43 with the shapes of R44 to R50, errors as `{"error"}`; `report.json` at run end; tests: 401 without or with a wrong token, every tool's happy path against a store fixture, `start_run` refusal while active, config errors. (M) | trainer | T09 | `make trainer-test` green; `python3 -I -m trainer serve` refuses to start without a token file (exit 2, one line). | implementer |
| T11 | **`sync_code` and the Windows scripts.** `sync.py` (inline or inbox bundle, verify, fetch, detached checkout, import with the gate's grep, refusal while active, copy of `runner.ps1` to the stable path; plan P17) with tests over a fake `git`; `trainer/windows/runner.ps1`, `grant-batch-logon.ps1`, `start-mcp.cmd`, `SETUP.md` (plan P18). (M) | trainer, windows | T08 | `make trainer-test` green; `SETUP.md` lists every admin step with the exact commands and no secret. | implementer |
| T12 | **Review A2.** Read T08 to T11 against E to H: the token path (R40 to R42), no shell tool (R43), atomic batches and resume (R35, R36), Windows-safety (R55), `sync_code` refusals (R52). Findings only. | review | T08–T11 | Findings posted; blockers and should-fixes merged before T14. | reviewer |
| T13 | **The bots guide and the layout row.** Rewrite `docs/systems/bot-training.md` from the code and the spec (R56): rung 0 and the stamp, `make bot-eval`, the play-out worker and its requests, the run store, the verbs, the PC setup; add the `trainer/` row to `CLAUDE.md` (R57). **Blocked** until Ben has committed or discarded his working-copy edits to the guide in the main checkout; the orchestrator asks him before dispatching. (S) | vault | T12 | Guide and `CLAUDE.md` updated on the cycle branch; `obsidian-cli vault=docs unresolved` reports nothing new. | implementer |
| T14 | **Verification A2.** On the Mac: `make check`, `make trainer-test`. On the PC over SSH as `trainer`: `make trainer-test`'s command, `SETUP.md` steps confirmed with Ben (task re-pointed, token file in place), `start-mcp.cmd` dropped in the queue. From the Mac over MCP: a request without the token is 401 (`curl`); `health`; `sync_code` of the A2 branch head (inbox bundle); `start_run` of 200 positions, `k` 8, 16 determinizations, 16 workers; `run_status` to done; a second run stopped at about position 90 and resumed, its digest equal to the first's (R36); `get_report`; `sample_positions` with `n` 3 shown to Ben; one sampled position labelled again by the Mac's play-out worker, values equal (R23); a service restart through the queue with a run running shows `interrupted` and `resume_run` finishes it (R37, R54). Record rollouts per second per worker on the PC, the DC row, the ledger rung-0 row's PC confirmation; link audit. No screenshot (R60). | verification | T13 | Every box of the spec's A2 definition of done ticked. | orchestrator |

## Verification task (always last)

Task T07 (A1) and task T14 (A2), owned by the orchestrator:

- [ ] `make check` exits 0 (both milestones); `make trainer-test` exits 0 on both machines (A2).
- [ ] End-to-end proof by lines: `bot-eval:` summary near 0.500 with `stamp=r7-…`; the
      seed-1 rollout pin; the 20-position worker digest equal on 1 and 8 workers (A1); the
      MCP run, stop and resume with equal digests, the 401, the Mac re-label equal to the
      PC's values (A2).
- [ ] No screenshot: engine and tooling cycle (spec R60), proof by text lines.
- [ ] `obsidian-cli vault=docs unresolved` reports nothing new.

## Waves (a proposal for `/cycle plan`)

A1: (1) T01, T04; (2) T02; (3) T03, T05; (4) T06; (5) T07.
A2: (1) T08; (2) T09, T11; (3) T10; (4) T12; (5) T13 (when unblocked), T14.

## Linear

Filled by `/exercise <slug>`. Empty until then.

- Project: <URL>
- Milestones: DC-15 (A1), DC-16 (A2), numbers confirmed at `/cycle plan`
- Issue mapping: task n is issue <KEY-m> (T01 = <KEY-…> … T14 = <KEY-…>)

## Commit plan

The whole cycle is one changeset per milestone on one branch named for the spec slug
(`cycle-11-bot-trainer` for A1, `cycle-11b-bot-trainer` for A2; `CLAUDE.md`, Git), cut from
`master` at `/spec` (A1) and at `/cycle plan` (A2) before the first note or edit. Each
carries the spec (`spec: cycle-11-bot-trainer`), the Linear write-back
(`exercise: cycle-11-bot-trainer`), one commit per task (`dc-NN: T<nn> <task title>`), review
fixes and the verification outcome, each message ending with the Co-Authored-By line the
session provides. When the verification task passes, `/cycle test` merges the branch into
`master` with a merge commit (`git merge --no-ff`) so the cycle stays visible in history.
Nothing is committed directly on `master`. Never push.
