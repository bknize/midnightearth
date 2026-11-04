---
type: tasks
tags: [tasks, cycle-6-constructed-decks, engine, board, ui]
status: approved
related: ["[[specs/cycle-6-constructed-decks/spec]]", "[[specs/cycle-6-constructed-decks/plan]]", "[[decisions/0002-one-branch-per-cycle]]", "[[planning/phase-1-tech-stack]]", "[[planning/cycles]]"]
created: 2026-11-04
updated: 2026-11-04
uid: b8da4ab5-4538-4f5a-b66a-ebc1a2b5e526
linear:
supersedes:
---

# Tasks: Cycle 6 — constructed decks

Derived from [[specs/cycle-6-constructed-decks/plan|plan]]. Numbered, dependency-ordered,
independently reviewable. Everything under `godot/engine/` goes to `implementer-engine`;
board, picker and `main.gd` work goes to `implementer`; `reviewer` reads diffs;
`orchestrator` runs `make check`, re-pins the golden, drives the Godot MCP and handles
Linear. Implementers write suites but never run them; "passes" is confirmed at T13. Every
brief carries the typed-strict checklist from the DC-01 lessons and the plan's event and
interface tables, so board tasks can start from the contract before the engine lands.

| # | Task | Area | Depends on | Acceptance check | Who |
|---|---|---|---|---|---|
| 1 | Pool format 3 and the deck list: `CardDef.bonus_kind`/`bonus`, `CardEffect` triggers and verbs per P8 (`switch_stats` removed, `opponent_next_no_bonus` renamed), `CardDb` format-3 parse and R3 checks (no count, no cost mix, flat ≤ cost+4), `DeckList` (P2) with `seeded_pick`, `MatchCards` (P3); the DC-05 fixture files under `tests/fixtures/` (P1); `MatchRules` constants | engine | – | `test_card_db.gd`: a format-2 file fails with the version error; a bonus `{"x": 130}` or `{"plus": 3}` fails; flat cost+5 fails, cost+4 passes; an unknown verb fails; the fixture loads with 20 cards and c13 vanilla. `test_deck_list.gd`: 19 or 21 cards, a repeated id or an unknown id fails `validate`; `seeded_pick(1, 0)` and `(1, 1)` are stable across calls and differ from seed 2's for at least one seat over seeds 1..10. `test_match_cards.gd`: `def_of(25)` is seat 1's deck's index 5; two seats on the same deck resolve to equal definitions | implementer-engine |
| 2 | Decks in the match: `MatchEngine.create(seed, cards, decks, deck_ids)` with `DECK_UNKNOWN`, `MatchState.deck_ids`, `MATCH_STARTED`, `MatchCards` replacing `CardDb` in `ScoreWalk`, `EffectResolver`, `Choice`, `LegalPlays`, `SeatView`, `GreedyBot`, `MatchDriver`; `ActionLog` format 3 with `decks` and `RULES_VERSION 4`; replay rebuilds the decks; `SeatView.deck_ids`. No rule change: every existing suite passes on the fixture deck for both seats | engine | 1 | `test_turn.gd`: `create` with an unknown id → `start()` fails `DECK_UNKNOWN`; `test_action_log.gd`: the header carries `decks`, a format-2 or rules-3 log fails replay with the mismatch, a header without `decks` is a format mismatch; a fixture-vs-fixture match replays to an equal state. `test_full_match.gd` compiles against the new API with the golden as a skip | implementer-engine |
| 3 | The hundredths mult: `WalkState.mult` at 100, `ScoreWalk.Effective` and `effective()` (P5 without the ongoing Drift parts), the pulse math (P4), `CARD_SCORED` payload, `CardState` reshaped (`base_kind`, `no_bonus`, `temp_plus`, switch fields gone), `temp_plus` cleared at walk end, `SeatView.mults` and row stats as `{flat, times, plus}` | engine | 2 | `test_score_walk.gd`: the spec's [4 ×1.25, 2 +1, 3] row scores 5 → 9 → 15 with mults 125 → 225 → 225; ×1.25 twice gives 156 (not 157); a no-bonus mark zeroes both parts; `temp_plus` is gone after the walk; preview equals live on a row with both bonus kinds. `test_seat_view.gd`: row entries carry `times` and `plus` | implementer-engine |
| 4 | Destroyed piles and recovery: `SeatPiles.destroyed`/`destroyed_known`, `clear_destroyed` to the pile with `pile: true`, the round-end flush to `burned`, `BOTH_DESTROYED` zone, `recover_destroyed` verb (P12), `CARD_RECOVERED` with redaction, `MatchState.controller_of`, `SeatView.own_destroyed`/`opponent_destroyed` | engine | 3 | `test_destroyed.gd`: a destroyed card is in its owner's pile after turn end and in `burned` after round end; a card destroyed this turn is not offered; the prompt offers own then opponent positions; recovering an opponent card puts it in the chooser's hand with printed stats, it commits and scores for the chooser, and round start returns it to its origin deck; recovering at hand cap burns it. `test_seat_view.gd`: the opponent's unrevealed-destroyed entry is `HIDDEN_CARD` and `CARD_RECOVERED` hides it from the other seat; a known one is public | implementer-engine |
| 5 | The set choice: `EngineAction.CHOOSE_SET` (P7) with dict form and log, `prompt.multi`, `_check_set` with `BAD_SET`, `CHOICE_REQUESTED.multi`, `CHOICE_MADE.indices`, `preview_set`, `PreviewPolicy` declines a nested multi prompt; the `sacrifice_destroy` verb through a provisional destroy (marks in place; P9 lands in T06) | engine | 4 | `test_engine_action.gd`: round-trip of `choose_set`. `test_choices.gd`: a repeat, a non-offered index, a `CHOOSE` on a multi prompt and a `CHOOSE_SET` on a single prompt are rejected with the codes; an empty set is accepted and fizzles; one eligible still prompts; zero eligible fizzles. `test_effects_ruin.gd`: choosing 2 of 4 destroys those two and two random live opponent cards; with one live opponent card only one; the log replays the set | implementer-engine |
| 6 | The destroy pipeline and the Ruin verbs: `EffectResolver.destroy` (P9) used by every destroy incl. T05's and DC-05's random one; `CARD_UNREVEALED`; `discard_own`, `destroy_leftmost_own`, `destroy_own_then_draw`, `destroy_own_then_flat_up`, `unreveal_instead`, `burst` with `ON_OPPONENT_SCORE` (P10), `draw` on `on_opponent_reveal`; eligibility per P12 | engine | 5 | `test_effects_ruin.gd`: Phoenix un-reveals in its slot with printed stats when chosen for a sacrifice and the opponent still loses that many; a face-down Phoenix (unrevealed) is destroyed normally; un-revealed ahead of the cursor it reveals in full again when reached, behind it stays down until the next walk; Fuse gains +1 per opponent score and at 5 destroys itself and one random live opponent card, a copy to 5 fires it too; a discard with an empty hand fizzles and the card scores; Tallow with no other card fizzles; Glutton gains the target's effective flat; Rat draws on each opponent reveal and burns at the cap. `test_choices.gd`: sources are excluded, destroyed cards are not offered | implementer-engine |
| 7 | The Drift verbs and `ON_MOVED`: `_place`/`_rewrite_row` with one `CARD_MOVED` per changed slot (P11), `move_self_left/right`, `move_opponent_left`, `shift_own_left`, `reverse_opponent_row`, `swap_opponent_right`, `copy_stats` (base per P5), `neighbour_times` and `edge_left_times` in `effective()`, `plus_on_moved` → `temp_plus`; `_check_burst` after a copy | engine | 6 | `test_effects_drift.gd`: the spec's reverse scenario ([A, B, C] with cursor 2 → C and B skipped, A scores again); shift keeps the source's slot and wraps the leftmost; Hook moves a face-down card by position; Maelstrom excludes the rightmost; Mirror copies effective stats and does not follow later changes; Lodestone gives ×1.25 to both neighbours only while revealed and live; Herald has ×1.5 only at slot 0; Eddy swapped forward scores with +2 and has none next turn; `ON_MOVED` fires once per moved revealed live card. `test_score_walk.gd`: preview equals live on a row with a neighbour and an edge | implementer-engine |
| 8 | The tables and the bot: Ruin and Drift in `cards.json` and `decks.json` exactly as the plan's tables; `GreedyBot` ordering (P13) and the k-lowest-flat set answer; `test_full_match.gd` golden under the seed-1 pairing (skip with the literals to pin), 50-seed sweep under seeded pairings with the leak scan covering piles and recoveries, slowest decision per pairing; `main.gd` smoke line with `decks=` | engine | 7 | `test_decks.gd`: both decks load, 20 distinct ids each, cost curves 5-4-3-3-2-2-1 and 4-4-3-3-2-2-2, every effect verb in the pool is one the resolver handles (a parse of the table in the plan is not required: assert ids, costs, bonus kinds and verbs by list). `test_greedy_bot.gd`: a +1 card orders before a ×2 card before a flat 7; the set answer previews n+1 candidates and never a non-offered index; a Ruin bot vs a Drift bot plays seed 1 to the end with no rejected action | implementer-engine |
| 9 | Board faces, chips, tally, piles and steps: `BonusLabel` "×1.25"/"+1", chips and tally to two decimals (`times`, `plus`, `mult` hundredths), `BoardHud.set_destroyed`, steps `UNREVEAL`, many-card `MOVE`, `RECOVER`, `STRIP_SHOW`/`STRIP_HIDE`, `CLEAR_DESTROYED` → pile count; `LiftRules.step_touches` for the new kinds; `EffectPlayer.unreveal` and the grouped move | board | 3 (contract from the plan's event table) | `test_board_steps.gd`: `CARD_SCORED {times 125, plus 0, mult 125}` yields a "×1.25" chip then "+N"; `{times 100, plus 0}` only "+N"; a run of `CARD_MOVED` from one effect becomes one `MOVE` step with every card; `CARD_UNREVEALED` yields `UNREVEAL` 0.35 s; `CARD_RECOVERED` yields `RECOVER`. `test_score_chips.gd`: the chip text for 156 is "×1.56". `test_lift_rules.gd`: each new kind that touches the held card. By node query: a face shows "+1" for a plus card and nothing for a vanilla one; the HUD pile counts follow `DESTROYED_CLEARED` and reset at `ROUND_STARTED` | implementer |
| 10 | The multi-select prompt and the recover strip: `PromptHost.selected`, `PromptRules.on_tap` with `TOGGLE_SELECT`, "Select"/"Deselect" and the other new labels (R49), the raised brighter-glow selected look, `BoardHud.show_confirm("Destroy %d")` → `MatchDriver.submit_set`; `DeckStrip` (P16) built from a `both_destroyed` prompt, backs for hidden entries, "Recover" button, cleared on the choice; `board.gd` routes both | board, ui | 5, 9 | `test_prompt_rules.gd`: a tap on an eligible card during a multi prompt → `LIFT_ELIGIBLE`; the button toggles membership; `action_label` gives "Select"/"Deselect"/"Discard"/"Destroy"/"Copy"/"Move"/"Swap"/"Recover" by verb and state; confirm text "Destroy 0" with an empty set. By node query: two selected cards are raised and brighter; the confirm button reads "Destroy 2" and submits `choose_set` with their positions; a recover prompt shows a strip above the rows with the opponent's hidden entry as a back; the strip is gone after the choice | implementer |
| 11 | The picker and the launch path: `DeckPicker` scene + `DeckPickState` (P15), `main.gd` args (`--seed=`, `--autoplay`, `--deck=`, `--bot-deck=`; unknown id → `push_error`, no `Main ready`), picker-or-board, `Main ready` after whichever is in the tree, `MatchDriver.create` with decks, `Board.start_match(seed, deck_ids)`, result line `decks=a/b`, Rematch keeps the ids, "Decks" buttons in pause and result → `decks_requested` → picker with the current picks preselected | ui, board | 2 (contract) | `test_deck_pick_state.gd`: Start is enabled only with both picks; preselection from a pair; a pick replaces the column's previous pick. `test_match_driver.gd`: the result line carries `decks=`. By node query: with no flags the picker is shown with two columns of two tiles and Start enabled (preselected); with `--deck=drift --bot-deck=ruin` the board starts at once; `--autoplay` skips the picker; the pause menu's "Decks" ends the match and shows the picker with the last picks | implementer |
| 12 | Review of T01–T11 against the spec and the Constitution Check, with attention to hidden information (R18, R19, `CARD_RECOVERED`, the strip's backs), the replay contract (R7, R12, R24, R35), the destroy pipeline (every destroy through P9), the cursor rules under the new moves (R29) and the integer rounding (P4) | all | 1–11 | Ranked findings; blockers fixed before T13 (commits `dc-07: T12 review fixes`) | reviewer |
| 13 | Verification (below) | all | 1–12 | All boxes checked | orchestrator |

**Waves.** Engine tasks are serial (each edits `effect_resolver.gd`, `score_walk.gd` or
`match_engine.gd`): T01 → T02 → T03 → T04 → T05 → T06 → T07 → T08. Board and UI tasks
overlap them from the plan's contract: wave 1 T01 + T09 (faces and steps, from the event
table); wave 2 T02 + T11 (picker and launch path, from the `MatchDriver`/`Board`
contract); wave 3 T03; wave 4 T04; wave 5 T05 + T10 (multi-select and strip, from the
prompt contract); wave 6 T06; wave 7 T07; wave 8 T08. One `board.gd` writer per wave:
T09 (wave 1), T11 (wave 2), T10 (wave 5). Then T12 and T13. The engine chain is long; the
orchestrator may merge T09–T11 as soon as their wave's engine task is green, and should
expect the board suites that read engine payloads to be re-run after T08.

## Verification task (13)

Owned by the orchestrator, on `cycle-6-constructed-decks`, editor opened on the cycle
worktree (`scripts/godot-editor.sh switch cycle-6-constructed-decks`). Three screenshots.

- [ ] `make check` exits 0, test stage under 15 s; record the case count.
- [ ] Re-pin the seed-1 golden under its seeded pairing: run the smoke, write the
      literals (decks included) into `test_full_match.gd`, update the boot expectation in
      `scripts/check.sh` if it checks values, and record the new `Engine smoke:` /
      `Board: match ended …` line in [[planning/cycles]]. Headless `--fixed-fps 60
      --autoplay` prints the same line.
- [ ] 50-seed sweep passes under seeded pairings, every log replays with its decks, the
      leak scan is clean for piles and recoveries; record the longest match, the pairing
      counts and the slowest decision per pairing; post to NSC-74 (stays in Backlog).
- [ ] **Picker.** With no flags: two columns, two tiles each, preselected with the seed's
      pairing, Start enabled; pick Ruin / Drift, Start → the board begins with those decks
      (the result line later shows `decks=ruin/drift`). **Screenshot 1:**
      `godot/reports/DC-07/deck-picker.png`. `--deck=drift --bot-deck=ruin` and
      `--autoplay` both skip the picker; an unknown id logs an error and no `Main ready`.
      Pause → "Decks" returns to the picker with the picks kept; Rematch keeps them.
- [ ] **Mult.** On a seed where a ×-card scores: the face reads "×1.25", the chip "×1.25"
      then "+N", the row tally the mult to two decimals; a +1 card's chip reads the new
      mult; the HUD holds until `TURN_END`. **Screenshot 2:**
      `godot/reports/DC-07/mult-face-tally.png`, a face reading "×1.25" with a tally such
      as "×1.56" in frame.
- [ ] **Sacrifice.** On a turn where Immolator flips for seat 0 (scripted through the
      probe scene if seed 1 has none): eligible cards glow; two taps and two "Select"
      presses raise two cards; the confirm reads "Destroy 2"; **Screenshot 3:**
      `godot/reports/DC-07/multi-select.png`; pressing it marks both destroyed and two
      opponent cards with them; "Destroy 0" on a fresh prompt fizzles.
- [ ] **Un-reveal, recover, moves.** By node query or the event stream: a Phoenix chosen
      for a sacrifice flips face down in its slot with printed stats; at turn end the
      destroyed cards fly off and both HUD pile counts rise; Grave Robber's prompt shows a
      strip with the opponent's hidden entry as a back and a "Recover" button, the chosen
      card flies to the hand and the strip clears; Tempest re-lays the opponent's row in
      one slide and the cursor rule (DC-06 R5–R7) shows on the following pulses.
- [ ] Ben has reviewed the Ruin and Drift tables (C7) and any row change is reflected in
      `cards.json`, the plan and the golden before the re-pin.
- [ ] No GDScript warning in the editor run; `obsidian-cli vault=docs orphans` reports
      nothing new (`unresolved` if the CLI build has it).

## Linear

Filled by `/exercise cycle-6-constructed-decks`. Empty until then.

- Project: (URL)
- Milestone: `DC-07 constructed-decks`
- Issue mapping: task n is issue NSC-m (T01 = … T13 = …)

## Commit plan

The whole cycle is one changeset on branch `cycle-6-constructed-decks`
([[decisions/0002-one-branch-per-cycle]]), cut from `master` at `/spec` before the first
note. It carries the spec (`spec: cycle-6-constructed-decks`), the Linear write-back
(`exercise: cycle-6-constructed-decks`), one commit per task (`dc-07: T<nn> <task
title>`), review fixes (`dc-07: T12 review fixes`, only if the review produced any) and
the verification outcome, including the golden re-pin. Every message ends with the
Co-Authored-By line the session provides. When T13 passes, `/cycle test` merges the
branch into `master` with `git merge --no-ff` and rewrites the GitHub links in Linear to
`master`. Never push without Ben.
