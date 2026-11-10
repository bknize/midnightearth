---
type: tasks
tags: [tasks, cycle-3-board-feedback, board]
status: approved
related: ["[[decisions/0002-one-branch-per-cycle]]", "[[specs/cycle-3-board-feedback/spec]]", "[[specs/cycle-3-board-feedback/plan]]", "[[planning/phase-1-tech-stack]]", "[[planning/cycles]]"]
created: 2026-11-03
updated: 2026-11-03
uid: ad542daf-f955-4038-8e64-d121a9df705c
supersedes:
---

# Tasks: Cycle 3 — board feedback

Derived from [[specs/cycle-3-board-feedback/plan|plan]]. Nothing is under `godot/engine/`,
so every code task goes to `implementer`. `reviewer` reads diffs, and `orchestrator` runs
`make check`, drives the Godot MCP and handles Linear. Implementers write suites but never
run them; "passes" is confirmed at T08. Every brief carries the typed-strict checklist
from the DC-01 lessons.

T01 and T02 are the existing Backlog issues cycle-3 T01 and cycle-3 T02, moved into this project
(C7). B-05 has no code of its own: its suspected fix is in T01, and T08's 10-run check
closes it.

| # | Task | Area | Depends on | Acceptance check | Who | Status |
|---|---|---|---|---|---|---|
| 1 | **cycle-3 T01** pointer and drag hygiene: `pointer_tracker.feed(event, gui_blocked)` plus the shim's `gui_get_hovered_control` check (P12); `_awaited` cache (P13); `pointer.cancel()` in `_clear_table_now` (P14); `drag_controller.gd` cancels a stray drag start (P15), recorded line by line in `addons/THIRD_PARTY_LICENSES.md` | input, board, addon | – | `test_pointer_tracker.gd` gains cases: a blocked press emits nothing through motion and release; the next unblocked press works; a blocked press's touch duplicate is blocked too. `may_act` no longer calls `driver.view()`. Under `addons/`, only `drag_controller.gd` and the licence note change | implementer | done |
| 2 | **cycle-3 T02** layout: `Root/TopInfo` to the top-left corner; `LineCardLayout` with `max_width = 26` on both rows; `NameLabel` word wrap and font size (P16); `BoardHud.reason_text` and the phrase table (P17); new `test_result_text.gd` | board, ui | – | Suite covers all four reasons, both concede seats and the unknown-reason fallback. No `board.gd` change beyond passing the round count to `show_result` | implementer | done |
| 3 | `board/lift_rules.gd` (`may_lift`, `step_touches`) and `test_lift_rules.gd` | board | – | Suite covers R2 and R11 for every `Place` × face-up combination, and every true and false case of `step_touches` in the plan, using steps from a real seed-1 match | implementer | done |
| 4 | Unseen rim: `Rim` in `board_card.tscn`, `set_unseen` / `is_unseen` / `copy_face_from` in `board_card.gd`; `_revealed_ids` and `_refresh_rims()` in `board.gd` (P8, P9) | board | 1, 2 | Code covers R17–R21. `_refresh_rims()` runs after staging changes, player commit, reveal, unstage-all, clear and new match. Only cards on `player_row` that are not in `_revealed_ids` are unseen | implementer | done |
| 5 | Drop-zone glows: `ZoneGlow` on `PlayerRow` and `PlayerHand` in `board.tscn`; idle, hover and refuse looks; wiring on drag start, zone enter and exit, drag stop and table clear (P10, P11) | board | 4 | Code covers R12–R16. `PlayerHand`'s zone signals are connected. Both glows are hidden after a drop, a refusal, a cancel and `_clear_table_now`. The opponent's collections get no glow | implementer | done |
| 6 | Card pick-up: `board/card_lift.gd`; `Camera3D/Dimmer`; HUD hidden while held; tap routing and Escape (P5); drag and hover lock (P6); runner put-down before touching steps (P7); `drop_now` on a new match (P1–P4, P7) | board | 3, 5 | Code covers R1–R11. The real card stays in its collection and is hidden while held. The stand-in copies its face and rim. Put-down targets the real card's transform at put-down time. Every await in the runner uses the node-owned wait pattern | implementer | done |
| 7 | Review of T01–T06 against the spec and the Constitution Check, reading the `drag_controller.gd` patch in full | all | 1–6 | Ranked findings. Each blocker is fixed by `implementer` before T08 (fixes commit as `dc-04: T07 review fixes`) | reviewer | done |
| 8 | Verification (below), which also closes B-05 | all | 1–7 | All boxes checked | orchestrator | done |

**Waves.** Wave 1 runs T01, T02 and T03 in parallel (disjoint files). Wave 2 is T04,
wave 3 is T05 and wave 4 is T06, because each of them edits `board.gd`. Then T07 and T08.

## Verification task (8)

Run 2026-11-03 on `cycle-3-board-feedback` with the editor opened on the cycle worktree
(`scripts/godot-editor.sh switch cycle-3-board-feedback`). Two screenshots in all.

- [x] `make check` exits 0 (24 s, 258 cases: 237 from DC-03, plus `test_result_text` 6,
      `test_lift_rules` 10 and `test_pointer_tracker` 5 new).
- [x] Boot log and seed-1 autoplay unchanged (R30). Headless `--fixed-fps 60` autoplay
      prints `Board: match ended seed=1 winner=0 wins=4-0 rounds=4 end=wins actions=56`.
      The editor run of the main scene showed one GDScript warning: `pointer_shim.gd:88`, a
      local `hovered` shadowing the shim's signal. Fixed as `dc-04: T08 verification fix`;
      after that, 0 errors and 0 warnings.
- [x] **Pick-up** on `board_seed1.tscn`, turn 1. A tap on hand card id 8 lifted it:
      `CardLift.held` was the card, the card was hidden and still in `PlayerHand`, the
      stand-in sat at the lift pose, the dimmer alpha was 0.6 and the HUD was hidden (R1,
      R3, R4). **Screenshot 1:** `godot/reports/DC-04/card-held.png`. The card faces the
      camera, fills about 90% of the height, and the table is dimmed with no table text
      showing through. A tap elsewhere put it down: the card was visible in its slot, the
      stand-in freed, the dimmer off, the HUD back, and pause did not open (R5). Escape
      while holding put the card down without opening pause; Escape with nothing held
      opened pause (C9). While paused, a tap did not lift (R7).
- [x] A tap on a face-down opponent hand card was ignored. A tap on a revealed opponent
      row card (id 23) lifted it (R2).
- [x] A real click on Commit, then a tap on the committed card, lifted it during the
      animations. The queue played on underneath, and the card was put down before its
      own reveal (R8, R9). Conceding while holding put the card down and showed the
      result panel, reading "You conceded" (review fix 2, R24). `start_match` while
      holding dropped the card in the same frame: stand-in freed, dimmer off, HUD on,
      `Loose` empty (R10).
- [x] **Zones.** An unaffordable drag (id 6, cost 2, energy 1) showed the row in the refuse
      look (red, 0.35) and the hand idle (gold, 0.18). On release the card was refused
      and both glows were hidden. An affordable drag showed the row in the hover look
      (gold, 0.35); after the drop, both glows were hidden (R12–R15).
- [x] **Rims.** A staged card has a rim. Dragging it along the row keeps the rim (R20).
      A committed card keeps its rim until its reveal, then loses it. An unstaged card has
      none (R17–R19, R21). **Screenshot 2:**
      `godot/reports/DC-04/drag-zones-rims.png`, a staged card mid-drag along the row, rim
      visible, row glow in the hover look, hand glow idle. It was retaken once: in the
      first take, Card3D's drag tilt turned the card edge-on after a 90 px synthesized
      jump.
- [x] **cycle-3 T02.** In both screenshots the opponent fan sits clear of `TopInfo`, now top
      left. Eight cards need 23.5 units under a 26-unit `max_width`, so each card takes
      its full 3.0 step with no overlap. Names wrap only at spaces ("Placeholder 20" on one
      line at size 28). All four reason phrases are checked by `test_result_text`
      (R22–R24).
- [x] **cycle-3 T01 / B-05.** A gitignored harness, deleted after the run, made 10 scripted
      Pause → Concede runs through `Input.parse_input_event`. Each run had two cards on the
      row and a card under the Concede button. Result: `DC04 concede runs: 10/10`, each
      followed by Rematch, with 0 errors (R25, R29).
- [x] `obsidian-cli vault=docs orphans` reports nothing new (`unresolved` is not available
      in this CLI build).

## Commit plan

The whole cycle is one changeset on branch `cycle-3-board-feedback`
([[decisions/0002-one-branch-per-cycle]]), cut from `master` at `/spec`. It carries the
spec (`spec: cycle-3-board-feedback`), the Linear write-back
(`exercise: cycle-3-board-feedback`), one commit per task (`dc-04: T<nn> <task title>`),
review fixes (`dc-04: T07 review fixes`, only if the review produced any) and the
verification outcome. Every message ends with the Co-Authored-By line the session
provides. When T08 passes, `/cycle test` merges the branch into `master` with
`git merge --no-ff` and rewrites the GitHub links in Linear to `master`. Never push
without Ben.
