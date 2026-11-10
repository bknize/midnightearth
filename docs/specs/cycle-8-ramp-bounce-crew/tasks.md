---
type: tasks
tags: [tasks, cycle-8-ramp-bounce-crew, engine, board, cards]
status: approved
related: ["[[specs/cycle-8-ramp-bounce-crew/spec]]", "[[specs/cycle-8-ramp-bounce-crew/plan]]", "[[specs/cycle-7-bot-players/tasks]]", "[[decisions/0002-one-branch-per-cycle]]", "[[planning/phase-1-tech-stack]]", "[[planning/cycles]]"]
created: 2026-11-04
updated: 2026-11-09
uid: 74041068-ca8e-4595-97eb-c4819afd258a
supersedes:
---

# Tasks: Cycle 8 — ramp, bounce, Crew

Derived from [[specs/cycle-8-ramp-bounce-crew/plan|plan]]. Numbered, dependency-ordered,
independently reviewable. Everything under `godot/engine/` goes to `implementer-engine`;
board and `main.gd` work goes to `implementer`; `reviewer` reads diffs; `orchestrator` runs
`make check` and `make bot-eval`, re-pins the golden, drives the Godot MCP and handles
Linear. Implementers write suites but never run them; "passes" is confirmed at T07 and T14.
Every brief carries the typed-strict checklist from the DC-01 lessons and the plan's event
and interface tables, so board tasks can start from the contract before the engine lands.

**Precondition (C2), met 2026-11-04:** cycle 7 milestone A (`cycle-7-bot-players`, DC-08)
merged into `master` as fbb0d38 and `cycle-8-ramp-bounce-crew` was re-based onto it;
milestone A runs before cycle 7 milestone B, so `make bot-train` is not available to it
(plan P18). Reconciled with DC-08 as shipped: spec C12.

## Milestone A: Bloom, Echo and card memory

| # | Task | Area | Depends on | Acceptance check | Who | Status |
|---|---|---|---|---|---|---|
| 1 | Card memory and effective cost: `CardMemory` (P2), `MatchState.memory` (kept across `_begin_round`, in `to_dict`/`duplicate`), `ScoreWalk.effective()` with memory and `effective_cost()` (P3), `LegalPlays` cost-array variants (P3; the printed-cost functions stay for the frozen `GreedyV1Bot`, which is not edited) with the engine, `GreedyBot.candidates_for`, `CandidateGen.all`'s trailing `costs` parameter and `Evaluator.features_of` on them, `SeatView.own_hand_row`/`own_hand_costs` and `cost`/`grown`/`uses_left` on row entries, pool format 4 with `uses` and the R11 loader checks (P1), `CardEffect.ON_ALLY_REVEAL` and the new verb names known to the loader, `MatchRules` constants, `RULES_VERSION` 5 with `test_action_log.gd`'s literal pin moved to 5; the DC-05 fixture bumped to format 4 (its frozen-fixture stamp literal in `test_bot_stamp.gd` is re-pinned by the orchestrator at T07). No rule change: every existing suite passes with empty memory | engine | – | `test_card_memory.gd`: round-trip and `is_empty`. `test_greedy_v1_bot.gd` and `test_candidate_gen.gd` pass unchanged. `test_evaluator.gd`: `energy_left` uses the effective cost. `test_score_walk_memory.gd`: a printed ×1.25 with `times` +50 reads 175; a no-bonus mark shows 100/0 and the memory survives it; `effective_cost` of cost 3 with reduction 4 is 0; memory survives `_begin_round` and a `duplicate()`. `test_legal_plays.gd`: a budget-2 commit of a cost-3 card passes with reduction 1 and fails with 0. `test_card_db.gd`: `uses` 1.5 fails; `grow_self_times` amount 30 fails, 25 passes; `unreveal_at_turn_end` on `on_reveal` fails; format 3 fails with the version error. `test_action_log.gd`: a rules-4 log fails replay. `test_seat_view.gd`: `own_hand_row` carries `cost`; the opponent's view holds no entry for a hand card's memory | implementer-engine | done |
| 2 | Bloom: `BloomEffects.grow` and the nine grow verbs (P4), the uses countdown (P7) with `EFFECT_FIRED.uses_left` and `EFFECT_FIZZLED.reason`, eligibility per P8 for `grow_other_flat` and `grow_hand_one_times`, `STATS_CHANGED` with `cost`/`permanent`/causes, private for hand cards | engine | 1 | `test_effects_bloom.gd`: Sapling scores thrice → 125, 150, 175 and the mult follows; Seed's flat grows per score and is kept through a round start and a redraw; Rain grows every hand card and emits one private `STATS_CHANGED` each (hidden for the other seat); Vine prompts over the hand and auto-chooses with one card; Orchard fizzles alone on the row; Oak fires once then `EFFECT_FIZZLED reason spent` and `uses_left` 0 persists across rounds; a grown card recovered by the other seat scores with its growth for the recoverer; preview equals live with memory | implementer-engine | done |
| 3 | Echo: `EchoEffects` (P6): the three return verbs through `return_marked`, `unreveal_at_turn_end` and `flip_echoes` in `_end_turn`, `cost_down_right`/`cost_down_self`, `draw_once`, `ally_reveal_flat`; the `ALLY_WATCHERS` stage with pause/resume (P5); eligibility per P8 | engine | 2 | `test_effects_echo.gd`: Flicker returns at turn end with memory kept and board changes gone; Recall marks another own card, Banish a revealed enemy card which goes to its controller's hand (a recovered card goes to the recoverer); Echo flips face down after the clear and reveals in full next walk, its on-reveal firing again; Tinker reduces slot+1's cost and fizzles at the row's end; Messenger draws 2 once per match; Refrain gains +1 per other own reveal and resets at round start; Relay draws per ally reveal; a prompt opened by an ally watcher pauses and resumes in order; `ALLY_WATCHERS` is skipped when no definition has the trigger (a stub counts) | implementer-engine | done |
| 4 | Tables and bot: Bloom and Echo in `cards.json` and `decks.json` exactly as the plan's tables; the hand-growth rule in `GreedyBot.ranked_option` (P15); `test_full_match.gd`: `GOLDEN_TUNED` emptied so the golden case skips until the orchestrator pins the four-deck seed-1 line at T07, the sweep under seeded pairings over four decks keeping its `p99_us < 10000` assertion and `stamp=` print, the leak scan covering memory; `main.gd` smoke unchanged in shape | engine | 3 | `test_decks.gd`: both decks load, 20 distinct ids each, curves 4-4-3-3-2-2-2, every verb one the resolver handles. `test_tuned_bot.gd`: with a cost-3 card reduced to 2 on a budget of 2 the bot's candidates include it and the engine accepts the action; the hand-growth prompt is answered by the highest-flat rule without a preview; 50 seeds over four decks end with no rejected action. `test_candidate_gen.gd`: `all()` with costs equals the old enumeration when costs are printed | implementer-engine | done |
| 5 | Board A (P16): `BoardCard.show_entry` with `CostLabel` effective cost and `GrownMark`, hand faces from `own_hand_row` at turn start, draws and hand restats, the hand `STATS` step (`in_hand`), `Staging`/`board._cost_of` on `own_hand_costs`, `LiftRules` for the hand restat, the strip dressing with memory | board | 1 (contract from the plan's event and view tables) | `test_board_steps.gd`: a private `STATS_CHANGED` on a viewer's hand card yields a `STATS` step with `in_hand`; one on an opponent's hidden card yields none. `test_staging.gd`: a card with printed cost 3 and effective cost 2 stages on budget 2. `test_lift_rules.gd`: the hand restat touches the held card. By node query: a grown hand card shows the mark and "×1.75"; a reduced card's cost label reads the effective cost; the mark is absent on a printed card | implementer | done |
| 6 | Review of T01–T05 against the spec and the Constitution Check, with attention to hidden information (R8: memory on hand cards, the opponent's view, the leak scan), the replay contract (memory and uses in `to_dict`, R29), rows never shrinking mid-walk (R19), the ally-watcher pause/resume (R15) and cost reads (no `CardDef.cost` left outside the loader and `effective_cost`) | all | 1–5 | Ranked findings; blockers fixed before T07 (commits `dc-NN: T06 review fixes`) | reviewer | done |
| 7 | Verification A (below) | all | 1–6 | All boxes checked | orchestrator | done |

**Waves (A).** Engine tasks are serial (each edits `score_walk.gd`, `effect_resolver.gd` or
`match_engine.gd`): T01 → T02 → T03 → T04. T05 starts from the contract in wave 1 beside
T01 and is re-run against T04's engine. Then T06 and T07.

## Milestone B: Crew

| # | Task | Area | Depends on | Acceptance check | Who | Status |
|---|---|---|---|---|---|---|
| 8 | Crew data: `crew.json` with the eight Crew (P12), `CrewDef`, `CrewPool`, `decks.json` v2 with `crew` lists and `DeckList.validate(cards, crew)`, `MatchEngine.create(…, crew)`, `MatchCards.crew_for`, `MatchState.crew_uses` with per-scope reset, `MATCH_STARTED.crew`, `SeatView.crew`/`crew_uses`; the fixture deck lists three Crew; `MatchDriver.create` and `main.gd` pass the pool | engine | 7 | `test_crew_pool.gd`: the shipped file loads with eight Crew; an unknown trigger, a non-bool `optional` or a bad scope fails. `test_deck_list.gd`: two Crew, a repeated Crew or an unknown id fails `validate`. `test_turn.gd`: `MATCH_STARTED` names both seats' Crew; `crew_uses` resets a per-round use at round start and keeps a per-match one; the view carries both seats' Crew | implementer-engine | done |
| 9 | Optional prompts and the decline (P9–P11): `prompt.optional`/`resume`/`crew`, `EngineAction.DECLINE` with dict and log, `LOG_FORMAT` 4 and `RULES_VERSION` 6, `_check_decline` with `NOT_OPTIONAL`, `EffectResolver.decline` and `CHOICE_DECLINED`, the turn-start pause and `_resume_turn_start`, `preview_decline`, `CHOICE_REQUESTED` payload | engine | 8 | `test_engine_action.gd`: `decline` round-trips. `test_action_log.gd`: a format-3 log fails with the format mismatch; a log with a decline replays. `test_choices.gd`: a decline with no prompt, from the wrong seat or on a non-optional prompt is rejected with the codes and nothing changes; on an optional prompt it closes the prompt without the effect and the walk resumes. `test_crew_flow.gd` (stub Crew): a turn-start prompt leaves phase `AWAIT_CHOICE` with the walk inactive, commits are rejected meanwhile, and after a choice or decline the phase is `AWAIT_FIRST` with the right first seat; `preview_decline` changes no state and returns two scores | implementer-engine | done |
| 10 | Crew triggers and abilities (P13, P14): the trigger queue appended by `destroy`, `rewrite_row`, `resolve_returns`, every un-reveal; drained after each firing, at turn end and at round end; `CrewEffects.fire` for the eight Crew; Tallyman in `effective()`; `salvaged` in `clear_destroyed` with `DESTROYED_CLEARED {pile: false, salvaged}`; `CREW_FIRED` | engine | 9 | `test_crew_effects.gd`: Quartermaster draws 2 extra on turn 1 only, burning at the cap; Tallyman gives ×1.25 to an even-flat card (0 included) and nothing to an odd one, only for its seat; Shade prompts on turn 4 with the revealed cards, a choice flips one and Lookout draws, a decline changes nothing; Salvager prompts after Immolator's sacrifice resolves (the opponent already lost that many), a discard sends the destroyed card to hand at turn end with memory kept and the pile count unchanged, once per round then silent, and does not fire with an empty hand; Veil prompts over the destroyed card, accept un-destroys it and flips the whole row face down, the use is spent for the match, a decline keeps it; Navigator gives +1 flat on each own move; Gardener grows every row card at round end and the growth is in the next round's hand; a Crew with no eligible target does not fire or count; `full_state()` with a queued Crew replays | implementer-engine | done |
| 11 | Bot B and stamp (P15): `TunedBot.answer_prompt` answers optional walk prompts by preview plus the decline, the Shade rule, decline for any other turn-start prompt; `BotStamp.current` gains `crew_path` (default `CrewPool.DEFAULT_PATH`) and `scripts/bot/records.py current_stamp()` hashes the three files the same way; a `tests/fixtures/dc05_crew.json` fixture for the frozen-fixture pin (re-pinned by the orchestrator at T14); sweep leak scan covers Crew prompts; `GOLDEN_TUNED` emptied again; `test_action_log.gd`'s pin moved to 6 | engine | 10 | `test_tuned_bot.gd`: on an optional prompt the bot previews n + 1 candidates and may return `decline`; on Shade's prompt it picks the highest-flat own card with an on-reveal effect or declines; 50 seeds over four decks and their Crew end with no rejected action with `p99_us` under 10 ms. `test_bot_stamp.gd`: the stamp changes when `crew.json` changes and the fixture digest matches `records.py` on the three fixtures; `test_greedy_v1_bot.gd` unchanged | implementer-engine | done |
| 12 | Board B (P17): `CrewLine` per side from `MATCH_STARTED.crew`, badges from `crew_uses`, `CREW_FIRE` step and pulse, lift-to-read and no drag for Crew, `BoardHud.show_skip` and `skip_pressed` → `MatchDriver.submit_decline`, Crew banner text, the turn-start prompt before staging (Commit disabled, hand locked, staging restored on close), `CHOICE_DECLINED` step, salvaged `DESTROYED_CLEARED` as a `RETURN` | board, ui | 9 (contract) | `test_board_steps.gd`: `CREW_FIRED` yields a `CREW_FIRE` step; `CHOICE_DECLINED` clears the prompt; `DESTROYED_CLEARED {pile: false}` yields a `RETURN`. `test_prompt_rules.gd`: an optional prompt wants the Skip button, a plain one does not. `test_crew_line_text.gd`: badge text for 2, 1, 0 and -1. By node query: three Crew per side with names; a "1 left" badge becomes "spent" and the Crew dims; Skip is visible on an optional prompt and submits a decline; on turn 4 with Shade the prompt shows before Commit enables | implementer | done |
| 13 | Review of T08–T12 against the spec and the Constitution Check, with attention to the queue (Crew never fires inside an effect, R46), the turn-start pause (R54), the decline contract (R52, R53, format 4), Crew visibility (public, never a target, R42) and the stamp (R58) | all | 8–12 | Ranked findings; blockers fixed before T14 | reviewer | done |
| 14 | Verification B (below) | all | 8–13 | All boxes checked | orchestrator | done |

**Waves (B).** T08 → T09 → T10 → T11 serial; T12 from the contract in wave 2 beside T09,
re-run against T11's engine. Then T13 and T14. Milestone B runs as its own cycle on
`cycle-8b-ramp-bounce-crew` cut from `master` after A merges.

## Verification task A (7)

Owned by the orchestrator, on `cycle-8-ramp-bounce-crew`, editor opened on the cycle
worktree. Two screenshots.

- [x] `make check` exits 0; gdUnit run time under 30 s (cycle 7 C15, spec C12); record the
      case count and the time in the cycles row.
- [x] Re-pin the seed-1 golden under the four-deck seeded pairing in `GOLDEN_TUNED`
      (`test_full_match.gd`, DC-08's mechanism): smoke, `Board: match ended …` and the
      `test_match_driver` pin agree across headless `--fixed-fps 60 --autoplay` and an editor
      run; record the line in [[planning/cycles]].
- [x] Re-pin the frozen-fixture stamp digest in `test_bot_stamp.gd` (and its Python twin)
      for the format-4 fixture (`shasum -a 256` over the fixture files, cards then decks).
- [x] 50-seed sweep over four decks: every log replays, the leak scan is clean (memory on
      hidden cards included), `p99_us` under 10 ms with the slowest printed; record pairing
      counts and the longest match.
- [x] Cycle 7 rerun provision as restated (R32, plan P18): the sweep line reads
      `stamp=MISMATCH`; run `make bot-eval` (expected PASS with identical default choices);
      edit the `stamp` field of `godot/engine/bot/data/tuned_weights.json` to the new
      `BotStamp.current()` value, re-run `make check` for `stamp=match`; add a ledger row
      "re-stamped without training: default weights" with the eval line, and paste both
      into the cycles row. No `make bot-train` (it lands with cycle 7 milestone B).
- [x] **Memory.** On a seed where Sapling scores twice (scripted through the probe scene if
      none does): its face reads "×1.50" with the grown mark; after the round, the same card
      in hand still reads "×1.50"; Tinker reduces a neighbour and the hand face shows the
      lower cost; staging that card on the reduced budget is accepted. **Screenshot 1:**
      `godot/reports/DC-09/grown-hand-face.png`.
- [x] **Bounce.** Echo flips face down at turn end in its slot and reveals again next walk
      with its on-reveal; Flicker returns to the hand; Banish returns an enemy card to the
      opponent's fan. **Screenshot 2:** `godot/reports/DC-09/echo-face-down.png`.
- [x] Ben has reviewed the Bloom and Echo tables and any row change is in `cards.json`, the
      plan and the golden before the re-pin.
- [x] No GDScript warning in the editor run; `obsidian-cli vault=docs unresolved` and
      `orphans` report nothing new; the Phase 3 amendment (C3) is appended to the planning
      notes; the cycles row records the gdUnit time against the 30 s budget.

Outcome (2026-11-05): all boxes checked; the gate, golden, sweep, bot rerun and MCP results are in the DC-09 row of [[planning/cycles]]. Ben's table review: the tables stand as signed off at `/spec` (no rows struck). Staging a reduced card was proven by `test_staging_memory`, not driven on the board.

## Verification task B (14)

Owned by the orchestrator, on `cycle-8b-ramp-bounce-crew`. Two screenshots.

- [x] `make check` exits 0 with gdUnit under 30 s; a format-3 log fails replay; the golden
      re-pinned in `GOLDEN_TUNED` if the Crew changed it; the sweep clean with `p99_us` under
      10 ms; the frozen-fixture stamp digest re-pinned over the three fixtures (cards, decks,
      crew); the rerun provision as in A (plan P18: `make bot-eval`, hand re-stamp, ledger
      row), or `make bot-train` if cycle 7 milestone B has merged by then (R58).
- [x] **Crew line.** Both sides show three Crew with names; on a Ruin seat Salvager reads
      "1 left", then "spent" after a use; Veil's badge persists across rounds. **Screenshot
      3:** `godot/reports/DC-11/crew-line.png`.
- [x] **Decline.** On a Salvager prompt the eligible hand cards glow, the reader shows
      "Discard" and a Skip button is visible; Skip closes the prompt with no discard and the
      log carries `decline`; on a Veil prompt accepting flips the row face down and none is
      destroyed. **Screenshot 4:** `godot/reports/DC-11/optional-prompt-skip.png`.
- [x] **Turn start.** With Echo (Shade) on turn 4 the prompt opens before staging, Commit is
      disabled, a choice flips the card and Lookout draws; after the prompt the hand drags
      again.
- [x] Bot vs bot on every deck pairing and Crew ends with no rejected action (the sweep).
- [x] `obsidian-cli vault=docs unresolved` and `orphans` report nothing new.

## Commit plan

Milestone A is one changeset on `cycle-8-ramp-bounce-crew` (`CLAUDE.md`, Git;
[[decisions/0002-one-branch-per-cycle]]), cut from `master` at `/spec` and re-based onto
`master` once cycle 7 milestone A merges (C2). It carries the spec
(`spec: cycle-8-ramp-bounce-crew`), the Linear write-back
(`exercise: cycle-8-ramp-bounce-crew`), one commit per task (`dc-NN: T<nn> <task title>`),
review fixes and the verification outcome including the golden re-pin and any re-stamped
weights, each message ending with the Co-Authored-By line the session provides; `/cycle
test` merges it into `master` with `git merge --no-ff`. Milestone B is a second cycle with
no spec of its own: it cuts `cycle-8b-ramp-bounce-crew` from `master` at its `/cycle plan`,
carries T08–T14 the same way and merges at its `/cycle test`. Nothing is committed directly
on `master`. Never push without Ben.
