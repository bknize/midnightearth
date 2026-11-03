---
type: tasks
tags: [tasks, cycle-3-board-feedback, board]
status: approved
related: ["[[decisions/0002-one-branch-per-cycle]]", "[[specs/cycle-3-board-feedback/spec]]", "[[specs/cycle-3-board-feedback/plan]]", "[[planning/phase-1-tech-stack]]", "[[planning/cycles]]"]
created: 2026-11-03
updated: 2026-11-03
uid: ad542daf-f955-4038-8e64-d121a9df705c
linear:
supersedes:
---

# Tasks: Cycle 3 — board feedback

Derived from [[specs/cycle-3-board-feedback/plan|plan]]. Nothing is under `godot/engine/`,
so every code task goes to `implementer`. `reviewer` reads diffs, and `orchestrator` runs
`make check`, drives the Godot MCP and handles Linear. Implementers write suites but never
run them; "passes" is confirmed at T08. Every brief carries the typed-strict checklist
from the DC-01 lessons.

T01 and T02 are the existing Backlog issues NSC-50 and NSC-48, moved into this project
(C7). NSC-49 has no code of its own: its suspected fix is in T01, and T08's 10-run check
closes it.

| # | Task | Area | Depends on | Acceptance check | Who |
|---|---|---|---|---|---|
| 1 | **NSC-50** pointer and drag hygiene: `pointer_tracker.feed(event, gui_blocked)` plus the shim's `gui_get_hovered_control` check (P12); `_awaited` cache (P13); `pointer.cancel()` in `_clear_table_now` (P14); `drag_controller.gd` cancels a stray drag start (P15), recorded line by line in `addons/THIRD_PARTY_LICENSES.md` | input, board, addon | – | `test_pointer_tracker.gd` gains cases: a blocked press emits nothing through motion and release; the next unblocked press works; a blocked press's touch duplicate is blocked too. `may_act` no longer calls `driver.view()`. Under `addons/`, only `drag_controller.gd` and the licence note change | implementer |
| 2 | **NSC-48** layout: `Root/TopInfo` to the top-left corner; `LineCardLayout` with `max_width = 26` on both rows; `NameLabel` word wrap and font size (P16); `BoardHud.reason_text` and the phrase table (P17); new `test_result_text.gd` | board, ui | – | Suite covers all four reasons, both concede seats and the unknown-reason fallback. No `board.gd` change beyond passing the round count to `show_result` | implementer |
| 3 | `board/lift_rules.gd` (`may_lift`, `step_touches`) and `test_lift_rules.gd` | board | – | Suite covers R2 and R11 for every `Place` × face-up combination, and every true and false case of `step_touches` in the plan, using steps from a real seed-1 match | implementer |
| 4 | Unseen rim: `Rim` in `board_card.tscn`, `set_unseen` / `is_unseen` / `copy_face_from` in `board_card.gd`; `_revealed_ids` and `_refresh_rims()` in `board.gd` (P8, P9) | board | 1, 2 | Code covers R17–R21. `_refresh_rims()` runs after staging changes, player commit, reveal, unstage-all, clear and new match. Only cards on `player_row` that are not in `_revealed_ids` are unseen | implementer |
| 5 | Drop-zone glows: `ZoneGlow` on `PlayerRow` and `PlayerHand` in `board.tscn`; idle, hover and refuse looks; wiring on drag start, zone enter and exit, drag stop and table clear (P10, P11) | board | 4 | Code covers R12–R16. `PlayerHand`'s zone signals are connected. Both glows are hidden after a drop, a refusal, a cancel and `_clear_table_now`. The opponent's collections get no glow | implementer |
| 6 | Card pick-up: `board/card_lift.gd`; `Camera3D/Dimmer`; HUD hidden while held; tap routing and Escape (P5); drag and hover lock (P6); runner put-down before touching steps (P7); `drop_now` on a new match (P1–P4, P7) | board | 3, 5 | Code covers R1–R11. The real card stays in its collection and is hidden while held. The stand-in copies its face and rim. Put-down targets the real card's transform at put-down time. Every await in the runner uses the node-owned wait pattern | implementer |
| 7 | Review of T01–T06 against the spec and the Constitution Check, reading the `drag_controller.gd` patch in full | all | 1–6 | Ranked findings. Each blocker is fixed by `implementer` before T08 (fixes commit as `dc-04: T07 review fixes`) | reviewer |
| 8 | Verification (below), which also closes NSC-49 | all | 1–7 | All boxes checked | orchestrator |

**Waves.** Wave 1 runs T01, T02 and T03 in parallel (disjoint files). Wave 2 is T04,
wave 3 is T05 and wave 4 is T06, because each of them edits `board.gd`. Then T07 and T08.

## Verification task (8)

Run on `cycle-3-board-feedback` with the editor opened on the cycle worktree
(`scripts/godot-editor.sh switch`). No screenshots beyond the two below (screenshot
token rule).

- [ ] `make check` exits 0. `test_lift_rules`, `test_result_text` and the extended
      `test_pointer_tracker` pass.
- [ ] The boot log and the seed-1 autoplay `Board: match ended seed=1 winner=0 wins=4-0
      rounds=4 end=wins actions=56` line are unchanged (R30).
- [ ] **Pick-up** on `board/verify/board_seed1.tscn`. Tap a hand card, then check by node
      query: `CardLift.held` is that card, it is hidden and still in `PlayerHand`, the
      stand-in sits at the lift pose, the dimmer alpha is 0.6, and the HUD is hidden.
      **Screenshot 1:** `godot/reports/DC-04/card-held.png`. Tap again: the card is
      visible in its slot, the stand-in is freed, the dimmer is clear and the HUD is back
      (R1–R6). Escape while holding: the card is put down and pause does not open.
- [ ] Tapping a face-down opponent card leaves the table unchanged (R2). After a reveal,
      tapping the revealed opponent card lifts it.
- [ ] Lift a staged card, then press Commit by calling the handler directly. The queue
      keeps playing (R8). At the next turn start the card is put down before it returns
      to the hand (R9). Lift a card before a round sweep: it is put down first. Rematch
      while holding: dropped at once (R10).
- [ ] **Zones**: mid-drag of an affordable hand card, both `ZoneGlow` are visible and the
      row is in its hover look over the row. Mid-drag of an unaffordable card over the
      row, the row is in its refuse look. After release and after a cancel, both are
      hidden (R12–R16).
- [ ] **Rims**: two staged cards are unseen; after Commit they are still unseen; after
      each one's reveal it is not; an unstaged card is not (R17–R21).
      **Screenshot 2:** `godot/reports/DC-04/drag-zones-rims.png`, mid-drag with both
      zones glowing and the staged cards rimmed.
- [ ] **NSC-48**: at 1280 × 720 the opponent fan's projected bounds do not overlap
      `TopInfo`'s rect. A row of eight cards has no overlap between neighbours' face
      rects. Names wrap only at spaces. Each reason phrase is checked by the suite (R22–R24).
- [ ] **NSC-50 / NSC-49**: a click on Commit over a hand card commits, and the card gets
      no press and is not lifted (R25). A scripted Pause → Concede run with cards on the row
      under the menu concedes 10 times out of 10, each followed by Rematch (R29).
- [ ] `obsidian-cli vault=docs unresolved` and `… orphans` report nothing new.

## Linear

Filled by `/exercise cycle-3-board-feedback`. Plan for it (C7): create the project
"Cycle 3 — board feedback". Create issues for T03–T08 only. Move NSC-50 (T01) and NSC-48
(T02) into the project and give them the `spec/cycle-3-board-feedback` label, keeping
their Cycle 2 spec links and adding this spec's. Move NSC-49 in as well, with a
`blockedBy` on T01 and a note that T08 closes it. `/cycle plan DC-04` puts all of them in
milestone `DC-04 board-feedback`.

- Project: (empty until `/exercise`)
- Milestone: DC-04 board-feedback
- Issue mapping: T01 = NSC-50, T02 = NSC-48, T03 … T08 = new; NSC-49 closes with T08

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
