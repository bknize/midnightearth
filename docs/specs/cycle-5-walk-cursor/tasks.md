---
type: tasks
tags: [tasks, cycle-5-walk-cursor, engine, board]
status: approved
related: ["[[specs/cycle-5-walk-cursor/spec]]", "[[specs/cycle-5-walk-cursor/plan]]", "[[decisions/0002-one-branch-per-cycle]]", "[[planning/phase-1-tech-stack]]", "[[planning/cycles]]"]
created: 2026-11-04
updated: 2026-11-04
uid: 1be9b5c2-635a-4d40-871c-af1d0f2e7ea2
supersedes:
---

# Tasks: Cycle 5 — the walk cursor

Derived from [[specs/cycle-5-walk-cursor/plan|plan]]. Numbered, dependency-ordered,
independently reviewable. Everything under `godot/engine/` goes to `implementer-engine`;
board work goes to `implementer`; `reviewer` reads diffs; `orchestrator` runs `make check`,
re-pins the golden line, drives the Godot MCP and handles Linear. Implementers write suites
but never run them; "passes" is confirmed at T09. Every brief carries the typed-strict
checklist from the DC-01 lessons and the plan's event table, so board tasks can start from
the contract before the engine lands.

| # | Task | Area | Depends on | Acceptance check | Who | Status |
|---|---|---|---|---|---|---|
| 1 | The slot cursor: `WalkState.cursor` and `scored` replace `pulsed` (P1, P3); `ScoreWalk.next_slot`, the pulse owns its card (P2), `CARD_SCORED.again`; `RULES_VERSION` 3 (P15); `to_dict()` and `duplicate()` updated | engine | – | `test_score_walk.gd`: the DC-05 14-vs-10 and 3-vs-1 cases still pass; a walk emits exactly n + m pulses; a scripted swap of the pulsing card behind the cursor scores it once and never scores the card that landed on the passed slot; a scripted swap forward scores it twice with `again` on the second; an on-score card scored twice shows base + 2; a face-down card swapped behind stays unrevealed and reveals in the next walk. `test_action_log.gd`: a rules-2 log fails replay with the version mismatch | implementer-engine | done |
| 2 | Destroyed as a state: `CardState.destroyed`, `MatchState.is_destroyed`; `_destroy_random` marks in place and picks among live cards (P4, P5); destroyed pulses (flip only, no hooks); watchers and the energy carrier skip destroyed cards; `Choice` eligibility per P5; `clear_destroyed` and the turn-end order (P6); `DESTROYED_CLEARED` and `CARD_REVEALED.destroyed` with redaction; `SeatView` row `destroyed` flag | engine | 1 | `test_effects.gd`: a destroy leaves the row size unchanged and marks the card; a destroyed card's flip emits `CARD_REVEALED` with `destroyed` and no effect, no bonus-0 spend (the mark survives to the next live reveal), no score; a destroyed c05 carries nothing; destroy with only destroyed cards opposite fizzles with the stream untouched; turn end clears destroyed cards to the burn pile after returns and before energy, a return-marked destroyed card is discarded. `test_choices.gd`: the swap lists a destroyed card, switch and return do not. `test_seat_view.gd`: a destroyed face-down card's `CARD_DESTROYED`, `DESTROYED_CLEARED` and row entry hide its id from the opponent and show its slot | implementer-engine | done |
| 3 | Preview and sweep: `_hide_opponent` marks inert instead of erasing (P7); `PreviewPolicy.destroy_slot` on live cards; `test_full_match.gd` golden left as a skip with the five literals to pin (pinned at T09), sweep records the longest walk and the slowest decision, leak scan covers destroyed face-down cards; `main.gd` smoke unchanged in shape | engine | 2 | `test_greedy_bot.gd`: preview-vs-live equality on a state with a forward swap and a destroy; a preview mid-walk with a face-down opponent card keeps the live slot order; preview changes nothing. Sweep suite compiles against the new API | implementer-engine | done |
| 4 | Board steps and tracker: `PULSE.destroyed` and `PULSE.again`, `DESTROY` as the in-place mark, `CLEAR_DESTROYED`, `TURN_END` duration (P9, P10); `ScoreTracker` with `tally`, `tally_mults`, `held` (P11); `LiftRules.step_touches` for the new kinds (P14) | board | 1 (contract from the plan's event table) | `test_board_steps.gd`: a destroyed reveal yields a flip-only pulse with no score; a second `CARD_SCORED` for a card yields a 0.12 s pulse with `again`; `DESTROYED_CLEARED` yields `CLEAR_DESTROYED` 0.45 s; `DESTROY` no longer removes. `test_score_tracker.gd`: `held` never changes during a walk, the tally follows pulses, `TURN_END` moves the total into `held` and clears the tally. `test_lift_rules.gd`: each new kind that touches the held card | implementer | done |
| 5 | The destroyed look: `BoardCard.set_destroyed` with dim, tilt and the `Crack` overlay behind one exported texture path (P8); `EffectPlayer.destroy` marks in place, `clear_destroyed` flies out at turn end, `pulse` handles `destroyed` and `again`; a face-down destroyed card shows the treatment on its back | board | 4 | By node query: after a `DESTROY` step the card is still in its row collection, dimmed, tilted and carries a visible `Crack`; after `CLEAR_DESTROYED` it is gone; a flip-only pulse does not lift; the tilt is suspended while the card is held | implementer | done |
| 6 | Chips, tally and the HUD: `ScoreChips` (P12), `RowTally` with the fly-in (P13), `BoardHud.set_scores(held)`, `count_to`, `score_anchor`; `×mult` leaves the HUD; `board.gd` wires the steps; autoplay speed divides every new duration (R36) | board, ui | 4, 5 | By node query and log: a scoring bonus card spawns "×M" then "+N" above it; a bonus-0 card only "+N"; a destroyed pulse spawns nothing; the row tally equals the last `CARD_SCORED.score` and `mult` of its side; the HUD label equals the previous `TURN_ENDED` total throughout the walk and the new total after the count; the tally is hidden outside a walk; during a prompt pause nothing changes | implementer | done |
| 7 | The prompt reader: `PromptRules.on_tap` with `LIFT_ELIGIBLE`, `SWAP_LIFT`, `PUT_DOWN` and `action_label` (P16); `PromptHost.lifted_option`; `CardLift` shows an own face-down card's face and flips it back on put-down, an opponent's stays a back; `BoardHud.show_action` / `hide_action` / `action_pressed`; `board.gd` routes the button to `submit_choice`; Escape and table taps put down (R40–R47) | board, ui | 6 | `test_prompt_rules.gd`: a tap on an eligible card → `LIFT_ELIGIBLE` (never `CHOOSE`); on another eligible card while one is lifted → `SWAP_LIFT`; on the lifted card or the table → `PUT_DOWN`; on a non-eligible face-up card → `LIFT`; `action_label` gives `Swap`, `Discard`, `Switch`, `Return` for the four prompt verbs. By node query: the button is hidden with nothing lifted and absent outside a prompt; the lifted own face-down card is face up in the lift and face down after put-down; the opponent's lifted card stays `face_down`; pressing the button submits the lifted option | implementer | done |
| 8 | Review of T01–T07 against the spec and the Constitution Check, with attention to hidden information (R20, R21, R46), the replay contract (R22, R24), the pulse count (R4), the pulse owner (R5) and the prompt flow (R40–R43) | all | 1–7 | Ranked findings; blockers fixed before T09 (commits `dc-06: T08 review fixes`) | reviewer | done |
| 9 | Verification (below) | all | 1–8 | All boxes checked | orchestrator | done |

**Waves.** Engine tasks are serial (each edits `score_walk.gd` or `match_engine.gd`):
T01 → T02 → T03. Board tasks overlap them from the plan's contract: wave 1 T01 + T04;
wave 2 T02 + T05; wave 3 T03 + T06; wave 4 T07. Only one `board.gd` writer per wave (T06
and T07 edit it, in different waves; T04 and T05 stay in their own files). Then T08 and
T09.

## Verification task (9)

Owned by the orchestrator, on `cycle-5-walk-cursor`, editor opened on the cycle worktree
(`scripts/godot-editor.sh switch cycle-5-walk-cursor`). Three screenshots in all.

- [x] `make check` exits 0, test stage under 15 s; record the case count.
- [x] Re-pin the seed-1 golden: run the smoke, write the five literals into
      `test_full_match.gd`, update the boot expectation in `scripts/check.sh` if it checks
      the values, and record the new `Engine smoke:` / `Board: match ended …` line in
      [[planning/cycles]]. Headless `--fixed-fps 60` autoplay prints the same line.
- [x] 50-seed sweep passes with prompts and destroys; record the longest walk (pulses), the
      longest match and the slowest bot decision, and post the numbers to B-09 as a
      comment (the issue stays in Backlog).
- [x] **Cursor** (amended 2026-11-04, C23). On a scripted or seeded turn where c12 swaps
      forward: node queries show c12 flipping at its slot, the move, then the card that
      landed on c12's slot scoring there (revealing first if it was face down), and c12
      scoring once when the cursor reaches its new slot, with the HUD holding; where c12
      swaps behind: the already-scored card that landed on c12's slot scores again there
      (`again`, short pulse) and c12 does not score this walk.
- [x] **Destroyed.** After a destroy the card stays in `OpponentRow` (or `PlayerRow`)
      dimmed, tilted and cracked; when the cursor reaches it face down it flips without
      lifting and no chip appears; at `TURN_END` it flies off and the row shrinks.
      **Screenshot 1:** `godot/reports/DC-06/destroyed-card.png`, with the row tally in
      frame.
- [x] **Chips and tally.** On a pulse of a bonus card: "×M" then "+N" above the card, the
      row tally updated, the HUD unchanged. **Screenshot 2:**
      `godot/reports/DC-06/score-chips.png`. At `TURN_END`: the tally flies into the HUD
      and the HUD counts to the `TURN_ENDED` total; outside a walk the tally is hidden.
- [x] **Prompt pause.** During c12's prompt no chip shows for c12, tally and HUD hold; after
      the choice the walk resumes and the values follow (B-08 closed with this check).
- [x] **Prompt reader.** On the first seed-1 turn in which seat 0 is prompted: a tap on a
      glowing card lifts it and the button reads the verb's label ("Swap"); nothing is
      submitted; a tap on another glowing card swaps the lift; a tap on the table puts it
      down and hides the button; an own face-down eligible card lifts face up and goes back
      face down; the opponent's face-down card, where one is lifted, stays a back.
      **Screenshot 3:** `godot/reports/DC-06/prompt-reader.png`. Pressing the button
      submits the choice; banner, glows, dimmer and button clear; the walk resumes.
- [x] No GDScript warning in the editor run; `obsidian-cli vault=docs orphans` reports
      nothing new (`unresolved` if the CLI build has it).

Outcome (orchestrator, 2026-11-04):
- Gate green in 47 s (test stage 14–15 s): 465 cases, 0 skipped.
- Golden re-pinned: `seed=1 winner=0 wins=4-3 rounds=7 end=wins actions=120`. The boot smoke,
  headless `--fixed-fps 60` autoplay and the `test_match_driver` pin all agree.
- Sweep: `longest=125 seed=13 longest_walk=21 walk_seed=17 prompts=873 destroyed_hidden=11`;
  slowest decision 16.8–19.6 ms across runs (posted to B-09).
- Cursor: checked on the seed-1 event stream, not by node query. At R1 T7 c12 (card 11, slot 2)
  swaps with card 19 (slot 0, already scored); card 19 then scores again on slot 2 with
  `again`, and c12 does not score this walk. The board's flip → move → score order is covered
  by `test_board_steps_walk.gd`.
- Destroyed, chips and tally, prompt pause, prompt reader: checked by node query in the editor
  through a throwaway probe scene. Three screenshots are in `godot/reports/DC-06/`.
- Fixed during verification: the chips waited for nothing on a first reveal, and the flip
  stretched over the longer step (now `BoardStep.chip_delay`). Two editor shadowing warnings
  were fixed too.

## Commit plan

The whole cycle is one changeset on branch `cycle-5-walk-cursor`
([[decisions/0002-one-branch-per-cycle]]), cut from `master` at `/spec` (371a745). It
carries the spec (`spec: cycle-5-walk-cursor`), the Linear write-back
(`exercise: cycle-5-walk-cursor`), one commit per task (`dc-06: T<nn> <task title>`),
review fixes (`dc-06: T08 review fixes`, only if the review produced any) and the
verification outcome, including the golden re-pin. Every message ends with the
Co-Authored-By line the session provides. When T09 passes, `/cycle test` merges the branch
into `master` with `git merge --no-ff` and rewrites the GitHub links in Linear to `master`.
Never push without Ben.
