---
type: tasks
tags: [tasks, cycle-4-card-effects, engine, board]
status: approved
related: ["[[specs/cycle-4-card-effects/spec]]", "[[specs/cycle-4-card-effects/plan]]", "[[decisions/0002-one-branch-per-cycle]]", "[[planning/phase-1-tech-stack]]", "[[planning/cycles]]"]
created: 2026-11-03
updated: 2026-11-03
uid: 5739f6af-c673-4cc3-b816-ec11153a84a7
linear: https://linear.app/night-science-llc/project/cycle-4-card-effects-032a703ba2d5
supersedes:
---

# Tasks: Cycle 4 — card effects

Derived from [[specs/cycle-4-card-effects/plan|plan]]. Numbered, dependency-ordered,
independently reviewable. Everything under `godot/engine/` goes to `implementer-engine`;
board work goes to `implementer`; `reviewer` reads diffs; `orchestrator` runs
`make check`, re-pins the golden line, drives the Godot MCP and handles Linear.
Implementers write suites but never run them; "passes" is confirmed at T14. Every brief
carries the typed-strict checklist from the DC-01 lessons and the plan's event table, so
board tasks can start from the contract before the engine lands.

| # | Task | Area | Depends on | Acceptance check | Who |
|---|---|---|---|---|---|
| 1 | Card data format 2: `CardEffect` (triggers, verbs, `from_dict`), `CardDef` with `flat`, `bonus`, `effect`; `CardDb` parse and R2 validation (cost table, unique ids, flat 0..cost+2, bonus 0..2, known verbs and triggers); `cards.json` as the plan's table; `MatchRules` versions 2 and `MAX_BONUS` | engine | – | `test_card_db.gd` covers the valid load, each new validation failure via in-memory JSON, a null effect for vanilla cards and every verb and trigger name round-tripping | implementer-engine |
| 2 | Positional commits and energy: `EngineAction` with `slots` and `CHOOSE` (`to_dict`/`from_dict`, format 2 keys); `EngineError` codes appended; `LegalPlays.validate` with row size, budget and the free first card; `MatchState` rows, `pending_slots`, `energy`, `revealed`; `_commit` stores slots and `_resolve` merges both commits (P1, P2); `SeatView` `opponent_pending_slots` and `budgets`; `ActionLog` format 2 and version-mismatch on format 1 | engine | 1 | `test_legal_plays.gd`: slot validation (out of range, repeated, out of order → `BAD_SLOTS`), budget with carry, free first card. `test_turn.gd`: merged row order for first-then-second commits at interleaved slots. `test_action_log.gd`: format 2 round trip, a format-1 log fails replay with `FORMAT_MISMATCH` | implementer-engine |
| 3 | `ScoreWalk` and `CardState`: resumable walk in `MatchState.walk` (P3, P5), `effective()` (P4), `WALK_STARTED`, `CARD_REVEALED` with slot and stats, `CARD_SCORED`; `_run_walk()` replaces `_reveal()`; turn end from walk totals (R17); `SeatView` rows with shown stats and `mults` | engine | 2 | `test_score_walk.gd`: the spec's 14-vs-10 example; alternation 3-vs-1 → first-0, second-0, first-1, first-2; recompute across two turns; mult resets per walk; a card pulsed at most once after a simulated swap and destroy; preview-vs-live equality on a plain state | implementer-engine |
| 4 | Effect framework and non-prompt verbs: `EffectResolver`, hooks for the four triggers (P6), `EFFECT_FIRED`, `EFFECT_FIZZLED`, `STATS_CHANGED`; verbs `DRAW`, `FREE_FIRST_NEXT_TURN`, `OPPONENT_NEXT_BONUS_ZERO`, `DESTROY_RANDOM_OPPONENT`, `FLAT_UP_ON_SCORE`, `CARRY_ENERGY`; per-seat energy at turn end (P7, P14); `ON_OPPONENT_REVEAL` exercised with an in-memory card | engine | 3 | `test_effects.gd`: one case per verb with the event list asserted; bonus-zero spent on the next reveal and not stacking; destroy fizzles on an empty row and uses the stream (two seeds differ, one seed repeats); flat_up applies after each scoring; carry only while the card is on the row at turn end; free first lost if unused; on_opponent_reveal fires once per revealed card of the other seat | implementer-engine |
| 5 | Prompts and prompt verbs: `Choice` zones, eligibility and resolution (P9, P10); `AWAIT_CHOICE`, `apply(CHOOSE)` resumes the walk (P3); auto-choose and fizzle; `CHOICE_REQUESTED` / `CHOICE_MADE` with redaction (R34); verbs `DRAW_THEN_DISCARD`, `SWAP_PLACES`, `SWITCH_STATS`, `RETURN_AT_TURN_END` (R24 burn at cap); `SeatView.prompt` | engine | 4 | `test_choices.gd`: every error code (`NO_PROMPT`, `NOT_ELIGIBLE`, `WRONG_SEAT`) leaves state and log unchanged; 0, 1 and 2+ eligible paths; each prompt verb's result; return to a full hand burns; swap then the walk pulses neither card twice. `test_seat_view.gd`: the non-choosing seat's prompt and choice events hold no hand ids | implementer-engine |
| 6 | Preview and bot: `MatchState.duplicate()`, `PreviewPolicy`, `MatchEngine.preview()` / `preview_choice()` / `open_prompt()` (P12); `GreedyBot.choose(view, engine)` searching masks × orders × ends and answering prompts (P13) | engine | 5 | `test_greedy_bot.gd`: preview changes nothing (full state and log equal before and after); the bot puts a bonus card left of a flat card when both fit; it destroys when the preview says so; it answers a prompt with the best option; same seed and view → same action; never rejected across sampled views including prompts | implementer-engine |
| 7 | Full match and smoke: `test_full_match.gd` golden left as a skip with the five literals to pin (as DC-01), 50-seed sweep asserting every match ends, no hand over 7, every commit within budget, no hidden id in any redacted view or event (prompts included), every log replays equal; `main.gd` smoke loop answers prompts through the bot; `MatchDriver` `submit_choice`, `open_prompt`, bot prompts in `play_bot()` | engine, board | 6 | Suite compiles against the new API; smoke line format unchanged; `test_match_driver.gd` covers a bot-answered prompt | implementer-engine |
| 8 | Board steps and staging: `BoardStep` kinds (plan, Board design), `BoardSteps` mapping with the two-speed `PULSE`, `PROMPT` untimed, `CHOICE_SHOW` 0.4, effect step durations (P17, P18); `Staging` with slots, budget and free first card | board | 2 (contract from the plan's event table) | `test_board_steps.gd`: each new event kind yields its step with the plan's duration; a revealed pulse is 0.12/speed and a flip pulse 0.35/speed plus the gap; PROMPT has no duration. `test_staging.gd`: slots follow row indices, free first card, budget with carry | implementer |
| 9 | Card faces and rim removal: `FlatLabel`, `BonusLabel`, `TextLabel` in `board_card.tscn` (P20); `show_def`, `show_stats` with pulse; remove `Rim`, `set_unseen`, `is_unseen`, `copy_face_from` rim handling, `_revealed_ids`, `_refresh_rims()` (P21); font size chosen against the longest text | board | 1 | Every card's text fits without a mid-word break at the lift size; `test_lift_rules.gd` loses its rim cases and still passes; no `Rim` reference remains under `board/` | implementer |
| 10 | Row and commit on the board: staging at any slot (P15), played cards not draggable (R44), `submit_player` with slots (R45), commit flip together (P16), opponent commit to slots (R47), `TURN_START` budgets and free-first readout (R49), `WALK_START` resets (R50) | board | 8, 9 | A drop between two played cards opens the gap and stages at that index; a drag on a played card never starts; Commit sends `slots` equal to row indices; after an accepted commit every staged card is face down in place; opponent backs land at the event's slots | implementer |
| 11 | The walk and effects on the board: `PULSE` lift-and-settle at two speeds with flip, HUD `score ×mult` (R51, R52), `STATS`, `DESTROY`, `MOVE`, `RETURN`, `DISCARD`, `FIZZLE`, `EFFECT`, `CHOICE_SHOW` steps (P18); `LiftRules.step_touches` for the new kinds (R54) | board | 10 | `test_lift_rules.gd` covers each new kind that touches the held card; the displayed score equals the last `CARD_SCORED.score` per side after every pulse; a destroyed card leaves the row collection | implementer |
| 12 | Prompt UI: `PromptRules` (glow set, tap routing) with suite; banner, per-card glow, dimmer, tap → `submit_choice`, lift of non-eligible cards, Escape and HUD lockout (R55–R57, C16); autoplay skips the banner | board, ui | 11 | `test_prompt_rules.gd`: glow set for each zone including the opponent's hand by fan index; tap on eligible → CHOOSE, on non-eligible face-up → LIFT, else NOTHING; the runner does not advance past a `PROMPT` until a choice is accepted | implementer |
| 13 | Review of T01–T12 against the spec and the Constitution Check, with attention to hidden information (R7, R34), the replay contract (R27, R39) and the `pulsed` rule (R16) | all | 1–12 | Ranked findings; blockers fixed before T14 (commits `dc-05: T13 review fixes`) | reviewer |
| 14 | Verification (below) | all | 1–13 | All boxes checked | orchestrator |

**Waves.** Engine tasks are serial (each edits `match_engine.gd`): T01 → T02 → T03 → T04
→ T05 → T06 → T07. Board tasks overlap them: wave 1 T01; wave 2 T02 + T09; wave 3 T03 +
T08; wave 4 T04; wave 5 T05 + T10; wave 6 T06 + T11; wave 7 T07 + T12. Only one `board.gd`
writer per wave. Then T13 and T14.

## Verification task (14)

Owned by the orchestrator, on `cycle-4-card-effects`, editor opened on the cycle worktree
(`scripts/godot-editor.sh switch cycle-4-card-effects`). Three screenshots in all (C17).

- [ ] `make check` exits 0, test stage under 15 s; record the case count.
- [ ] Re-pin the seed-1 golden: run the smoke, write the five literals into
      `test_full_match.gd`, update the boot expectation in `scripts/check.sh` if it checks
      the values, and record the new `Engine smoke:` / `Board: match ended …` line in
      [[planning/cycles]]. Headless `--fixed-fps 60` autoplay prints the same line.
- [ ] 50-seed sweep passes with prompts and random destroys; note the longest match and
      the slowest bot decision.
- [ ] **Faces.** On `board_seed1.tscn`, every hand card shows name, cost, flat, bonus (when
      non-zero) and rules text; a lifted effect card reads cleanly. **Screenshot 3:**
      `godot/reports/DC-05/lifted-effect-card.png`.
- [ ] **Slots and commit.** Stage a card between two played cards (turn 2 or later): node
      query shows it at that row index, the gap opened, and `Staging.slots` matches.
      **Screenshot 1:** `godot/reports/DC-05/staged-between.png`. Click Commit: all staged
      cards are `face_down` in place; the action log's last commit carries the slots. A
      drag on a played card does not start.
- [ ] **Walk.** At walk start both HUD scores read 0 and `×1`; pulses alternate from the
      first committer by node query on the lifted card; a revealed pulse is short and a
      flip keeps the reveal beat; after `TURN_END` the scores equal the event's.
- [ ] **Prompt.** On the first seed-1 turn in which seat 0 is prompted (note the turn):
      banner text equals the card's text, eligible cards carry a visible `Glow`, the rest
      are dimmed, Commit is disabled. **Screenshot 2:** `godot/reports/DC-05/prompt.png`.
      A tap on a non-eligible face-up card lifts it; a second tap puts it down; the prompt
      still waits. A tap on a glowing card submits the choice; banner, glows and dimmer
      clear; the walk resumes. A bot prompt shows `CHOICE_SHOW` on its pick.
- [ ] **Effects by node query** (seeded or scripted): a destroyed card leaves
      `OpponentRow`; a swap re-orders `PlayerRow`; a returned card is back in the owner's
      fan after `TURN_END`; the energy readout shows the carried budget; the free-first
      mark shows and a cost-above-budget leftmost drop is accepted.
- [ ] No GDScript warning in the editor run; `obsidian-cli vault=docs orphans` reports
      nothing new (`unresolved` if the CLI build has it).

## Linear (exercised 2026-11-03)

Project [Cycle 4 — card effects](https://linear.app/night-science-llc/project/cycle-4-card-effects-032a703ba2d5),
state Planned until `/cycle plan DC-05` puts the issues into milestone
`DC-05 card-effects`. Label `spec/cycle-4-card-effects` on all. Engine tasks carry
`area/engine`, board tasks `area/cards` (T07 both, T12 adds `area/ui`); T01–T12 are
`type/feature`, T13 and T14 `type/chore`. GitHub links point at `cycle-4-card-effects`
until `/cycle test` rewrites them to `master` (ADR 0002).

| Task | Issue | Blocked by |
|---|---|---|
| T01 | NSC-59 | – |
| T02 | NSC-60 | NSC-59 |
| T03 | NSC-61 | NSC-60 |
| T04 | NSC-62 | NSC-61 |
| T05 | NSC-63 | NSC-62 |
| T06 | NSC-64 | NSC-63 |
| T07 | NSC-65 | NSC-64 |
| T08 | NSC-66 | NSC-60 |
| T09 | NSC-67 | NSC-59 |
| T10 | NSC-68 | NSC-66, NSC-67 |
| T11 | NSC-69 | NSC-68 |
| T12 | NSC-70 | NSC-69 |
| T13 | NSC-71 | NSC-59 … NSC-70 |
| T14 | NSC-72 | NSC-59 … NSC-71 |

All fourteen are in Todo.

## Commit plan

The whole cycle is one changeset on branch `cycle-4-card-effects`
([[decisions/0002-one-branch-per-cycle]]), cut from `master` at `/spec`. It carries the
spec (`spec: cycle-4-card-effects`), the Linear write-back
(`exercise: cycle-4-card-effects`), one commit per task (`dc-05: T<nn> <task title>`),
review fixes (`dc-05: T13 review fixes`, only if the review produced any) and the
verification outcome, including the golden re-pin. Every message ends with the
Co-Authored-By line the session provides. When T14 passes, `/cycle test` merges the
branch into `master` with `git merge --no-ff` and rewrites the GitHub links in Linear to
`master`. Never push without Ben.
