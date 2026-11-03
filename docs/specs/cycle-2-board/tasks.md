---
type: tasks
tags: [tasks, cycle-2-board, board]
status: approved
related: ["[[specs/cycle-2-board/spec]]", "[[specs/cycle-2-board/plan]]", "[[planning/phase-1-tech-stack]]", "[[planning/cycles]]"]
created: 2026-11-03
updated: 2026-11-03
uid: ab3133b4-d3cd-4414-aa3f-67f548d02303
linear:
supersedes:
---

# Tasks: Cycle 2 — the board

Derived from [[specs/cycle-2-board/plan|plan]]. Numbered, dependency-ordered,
independently reviewable. Nothing in this cycle is under `godot/engine/`, so every code
task goes to `implementer`; `reviewer` reads diffs; `orchestrator` runs `make check`,
drives the Godot MCP and handles Linear. Implementers write suites but never run them;
"passes" below is confirmed by the orchestrator at T11. Every brief carries the
typed-strict checklist from the DC-01 lessons.

| # | Task | Area | Depends on | Acceptance check | Who |
|---|---|---|---|---|---|
| 1 | Pointer shim: `input/pointer_event.gd`, `input/pointer_tracker.gd`, `input/pointer_shim.gd`; `test_pointer_tracker.gd` | input | – | Suite covers R21–R25 and the hover rule of R28 per the plan's tracker rules, with synthesized mouse, emulated-mouse and screen-touch events; `godot/input/` references nothing under `godot/board/` | implementer |
| 2 | Card3D DragController patch to take `PointerShim` input (plan steps 1–7); record every changed line in `addons/THIRD_PARTY_LICENSES.md` | addon | 1 | Only `drag_controller.gd` and the licence note change under `addons/`; no `_unhandled_input`, `mouse_entered` or `input_event` left in the drag path; the licence row lists each change | implementer |
| 3 | `board/match_driver.gd`; `test_match_driver.gd` | board | – | Suite covers R2, R5, R6: seed-1 autoplay through the driver yields `Board: match ended seed=1 winner=0 wins=4-0 rounds=4 end=wins actions=56`; returned events never hold an opponent hand id; concede gives reason `concede` | implementer |
| 4 | `board/staging.gd`; `test_staging.gd` | board | – | Suite covers R12–R16: insert at index, move, remove, over-budget refusal leaves state unchanged, energy left, empty commit is a pass, action order equals row order | implementer |
| 5 | `board/board_step.gd`, `board/board_steps.gd`; `test_board_steps.gd` | board | – | Suite covers R31–R38 per the plan's step table, built from events of a real seed-1 match: order, reveal order and power, score equals `TURN_ENDED`, burn entry-to-exit, round sweep before deal, bot wait, speed scaling | implementer |
| 6 | Card and HUD scenes: `board/board_card.tscn` + `.gd` (inherits Card3D's scene, face labels, back, picking off), `board/board_theme.tres`, `board/board_hud.tscn` + `.gd` (scores, pips, round and turn, energy with flash, Commit or Pass, pause menu, result panel with Rematch) | board | – | Typed and lint-clean; HUD exposes setters and signals only (`commit_pressed`, `pause_pressed`, `concede_pressed`, `resume_pressed`, `rematch_pressed`); no engine calls inside the HUD | implementer |
| 7 | Board scene, autoplay path: `board/board.tscn` + `board.gd` with camera, light, four collections under the patched `DragController`, entry and exit markers, `PointerShim`, HUD; step queue runner; bot pacing; seeds and args; `Board:` line; `board/verify/board_autoplay.tscn` | board | 2, 3, 5, 6 | Running the autoplay scene plays a whole match with no player input and prints the `Board:` line; R1-free (main is T09); input lock flag set while steps remain (R39) | implementer |
| 8 | Board scene, player path: `board/board_drag_strategy.gd`; drag staging, refusal with energy flash, row reorder, Commit or Pass, tap ignored, cancel return, hover rule; pause, concede, result panel, rematch; `board/verify/board_seed1.tscn` | board | 4, 7 | Covers R11–R20, R26–R28, R40–R43 in code; `Staging` stays in step with `PlayerRow` through `card_moved`; nothing reaches the engine except `submit_player` | implementer |
| 9 | Main wiring: `main.gd` instances the board after the smoke run and prints `Main ready` once it is in the tree; `main.tscn` drops its camera, light and title; `scripts/check.sh` boot passes `-- --seed=1` | scene, tooling | 8 | Smoke line unchanged; `Main ready` still last of the two; the `check.sh` diff is the one boot line | implementer |
| 10 | Review of T01–T09 against the spec and the Constitution Check, reading the Card3D patch in full | all | 1–9 | Ranked findings; each blocker fixed by `implementer` before T11 (fixes commit as `dc-03: T10 review fixes`) | reviewer |
| 11 | Verification (below) | all | 1–10 | All boxes checked | orchestrator |

T01, T03, T04, T05 and T06 can run in parallel. T02 needs T01's signals; T07 needs the
patch, the driver, the steps and the scenes.

## Verification task (11)

- [ ] `make check` exits 0; the test stage lists `test_pointer_tracker`, `test_staging`,
      `test_board_steps` and `test_match_driver`, all passing.
- [ ] The boot log holds `Engine smoke: seed=1 …` then `Main ready`, and no error line.
- [ ] MCP `run_scene` on `board/verify/board_autoplay.tscn`; `get_runtime_log` holds
      `Board: match ended seed=1 winner=0 wins=4-0 rounds=4 end=wins actions=56` and no
      error line.
- [ ] MCP `run_scene` on `board/verify/board_seed1.tscn`; read seat 0's hand through
      `query_runtime_node`; with `send_input` mouse press, motion and release: drag an
      affordable card onto `PlayerRow` (staged, energy readout drops), drag a card that
      costs more than the energy left (refused, back in hand), press and release without
      moving (table unchanged).
- [ ] **Screenshot 1:** mid-turn with a card staged on `PlayerRow`.
- [ ] Click Commit; the runtime log or a node query shows the turn resolved.
- [ ] Click the pause button, then Concede; the result panel shows the bot winning by
      concede over the final table.
- [ ] **Screenshot 2:** the match-end result panel.
- [ ] Click Rematch; a node query shows round 1 dealt again.
- [ ] Two screenshots in all (C11); the Linear status update carries both, the
      `Board:` line and the suite counts.
- [ ] `obsidian-cli vault=docs unresolved` and `… orphans` report nothing new.

## Linear

Filled by `/exercise cycle-2-board`. Empty until then.

- Project:
- Milestone: `DC-03 board`
- Issue mapping:

## Commit plan

One commit per task on branch `dc-03-board`. Messages: `dc-03: T<nn> <task title>`,
ending with the Co-Authored-By line the session provides. T10 commits only if the review
produced fixes. When T11 passes, the branch merges into `master` with a merge commit
(`git merge --no-ff`). The spec set itself is its own changeset: committed as
`spec: cycle-2-board` on branch `spec-cycle-2-board` when Ben says to, and merged into
`master` with `--no-ff` before `/exercise`. Never push without Ben.
