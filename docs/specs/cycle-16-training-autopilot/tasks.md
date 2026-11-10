---
type: tasks
tags: [tasks, cycle-16-training-autopilot, tooling, bot, training, llm, autopilot]
status: approved
related: ["[[specs/cycle-16-training-autopilot/spec]]", "[[specs/cycle-16-training-autopilot/plan]]", "[[planning/phase-1-tech-stack]]"]
created: 2026-11-09
updated: 2026-11-09
uid: 8669afa9-0889-4a0a-8f5a-92ea900d6c4e
supersedes:
---

# Tasks: training autopilot

Derived from [[specs/cycle-16-training-autopilot/plan|plan]]. Numbered, dependency-ordered,
independently reviewable. No task touches `godot/engine/`, so every code task is `implementer`.
Implementers test with stubs only (a stub farm, a stub eval driver, a stub HTTP server, a fake
clock); they never run Godot, the LLM or the PC.

| # | Task | Area | Depends on | Acceptance check | Who | Status |
|---|---|---|---|---|---|---|
| 1 | Close DC-21's hand-run rounds (P21): judge the round in flight once, record it in the DC-21 row on `cycle-15-training`, mark DC-21 paused, note the two candidate fit ids | vault | – | The DC-21 row names the last hand-run round, the pause and the candidates | orchestrator | done |
| 2 | Knobs: the table, bounds, hard limits, `validate` with one trial value and refusals (P9; R18, R23, R24, R27, R28) | tooling | – | `trainer/tests/test_knobs.py`: in bounds, out of bounds, past the hard limit, unknown knob, two out-of-bounds values | implementer | done |
| 3 | Findings log: entry schema, append with fsync, read after a block number (P12; R13 to R16) | tooling | – | `test_findings.py`: append-only, a torn last line is reported and skipped, `after` filter | implementer | done |
| 4 | Judge and champion: run the eval driver twice, parse the lines, champion file, feature-set check (P5, P6; R7 to R10, R39) | tooling | – | `test_judge.py` with a stub driver: pass/pass, fail, cap, error, no champion, changed feature set | implementer | done |
| 5 | Advisor: LLM server start and stop, prompt, reply schema, retry, timeout, the fallback rule, the request record (P7, P8, P11; R17, R19 to R22) | tooling | 2, 3 | `test_advisor.py` with a stub HTTP server: valid reply, invalid then valid, timeout to fallback, server left stopped, record written | implementer | done |
| 6 | The loop: blocks, iterations, deadline and grace, trial blocks, plateau, faults, stop, state file and resume, seed judging (P1 to P4, P10, P14, P16; R1 to R6, R11, R12, R24 to R26, R33 to R37) | tooling | 2, 3, 4, 5 | `test_autopilot.py` with a fake clock and stub farm: three blocks, a deadline mid-run above and below `min_positions`, a trial pass and fail, plateau at 6, three failures stop, stop at each safe point, resume from each stage | implementer | done |
| 7 | Steering: validate, apply, archive, refuse (P13; R29 to R31) | tooling | 2, 6 | `test_steering.py`: narrow, widen inside the hard limit, pin, avoid, notes reach the prompt, invalid file refused and the old steering kept | implementer | done |
| 8 | Service wiring: the four tools, `sync_code` refusal, resume at service start (P15; R37, R38) | tooling | 6 | `test_server.py` additions: start, status, stop, `get_findings`, `sync_code` refused while running, restart resumes | implementer | done |
| 9 | Mac pull and figures: `trainer/digest.py`, `scripts/training-pull.sh`, `make training-digest` (P17; R40, R41, R43) | tooling | 3 | `test_digest.py` on a fixture log across three days: every figure of R41; a bad line exits 1 naming it; the script makes one SSH connection | implementer | done |
| 10 | Windows files and setup: `autopilot-stop.cmd`, the example config, the SETUP.md section, the night jobs retired (P20) | tooling | 8 | SETUP.md walks first start, stop and logs; the stop file path matches P14 | implementer | done |
| 11 | The `/training` skill and the digest note's first version (P18, P19; R32, R42, R43) | tooling, vault | 8, 9 | The skill lists the five verbs, the approval rule and the no-contact rule; the note has P5 frontmatter | implementer | done |
| 12 | Docs: `CLAUDE.md` (layout rows, the skill verbs), `docs/systems/bot-training.md`, architecture decisions T8 onward from this spec's Clarifications | vault | 6 to 11 | Link audit clean; the architecture table carries the 13 answers | implementer | done |
| 13 | Review of the cycle's diff | tooling | 2 to 12 | Findings ranked; blockers fixed | reviewer | done |

Waves: tasks 1 to 4 together; then 5; then 6 and 9; then 7 and 8; then 10 and 11; then 12, 13.

## Verification task (always last)

Task 14, owned by the orchestrator:

- [x] `make check` exits 0 and `make trainer-test` is green on the Mac.
- [x] `sync_code` the branch to the PC; trainer tests green on the PC.
- [x] Short-block proof on the PC: `autopilot_start` with `block_hours` 0.25 and the two
      candidates of task 1. One read of the log afterwards shows a `seed` entry naming a
      champion, three `full` entries, one with `plan_source` `advisor`, one `fallback` (forced
      by a wrong LLM server path in `config.json` for one boundary), one `trial` entry (forced by
      a steering file that narrows `positions` below the advisor's last value), one
      `interrupted` entry from a stop, and a block resumed after a service restart ending at its
      original deadline.
- [x] `sync_code` refused while it ran, accepted after the stop.
- [x] `/training digest` on the Mac: one SSH connection, `figures.md` written, the digest note
      rewritten.
- [x] No screenshot (no visible feature); the proof is the findings lines, quoted in the cycle
      row of `docs/planning/cycles.md`.
- [x] `obsidian-cli vault=docs unresolved` reports nothing new.

Outcome (2026-11-10): every box holds; the findings lines are quoted in the DC-22 row of
[[planning/cycles]]. Four defects found on the PC were fixed on the branch first (judge without
Godot, seeded champion without a stamp, advisor thinking past its context, a fallback starting a
trial), and two test and digest faults.

## Commit plan

The whole cycle is one changeset on `cycle-16-training-autopilot`, cut from `master` at `/spec`
before the first note. It carries the spec (`spec: cycle-16-training-autopilot`), the Linear
write-back (`exercise: cycle-16-training-autopilot`), one commit per task
(`dc-NN: T<nn> <task title>`), review fixes and the verification outcome, each message ending
with the Co-Authored-By line the session provides. Task 1 is committed on `cycle-15-training`,
DC-21's branch. When the verification task passes, `/cycle test` merges the branch into `master`
with `git merge --no-ff`. Nothing is committed directly on `master`.
