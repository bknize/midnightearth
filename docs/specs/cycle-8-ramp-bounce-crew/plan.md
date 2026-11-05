---
type: plan
tags: [plan, cycle-8-ramp-bounce-crew, engine, board, cards]
status: approved
related: ["[[specs/cycle-8-ramp-bounce-crew/spec]]", "[[specs/cycle-8-ramp-bounce-crew/tasks]]", "[[specs/cycle-6-constructed-decks/plan]]", "[[specs/cycle-7-bot-players/plan]]", "[[specs/cycle-5-walk-cursor/plan]]", "[[planning/phase-1-tech-stack]]", "[[decisions/0002-one-branch-per-cycle]]"]
created: 2026-11-04
updated: 2026-11-04
uid: 92033b9a-898a-4fe2-b919-576ee5dddb85
linear:
supersedes:
---

# Plan: Cycle 8 — ramp, bounce, Crew

Implements [[specs/cycle-8-ramp-bounce-crew/spec|spec]]. The spec is clarified (C1–C11, no
open markers). Everything builds on cycle 6's engine and on cycle 7 milestone A's bot
([[specs/cycle-7-bot-players/plan]]: `BotRegistry`, `TunedBot`, `CandidateGen`, `BotStamp`,
the rerun provision). **Precondition (C2):** `/cycle plan` for milestone A waits until
`cycle-7-bot-players` (DC-08) has merged into `master`, and milestone A runs before cycle 7
milestone B; the orchestrator re-bases `cycle-8-ramp-bounce-crew` (three notes only) onto
`master` first. Milestone B is a second cycle on `cycle-8b-ramp-bounce-crew`, cut from
`master` after A merges (as cycle 7 does).

## Stack mapping

| Area | Involved | Approach and tooling |
|---|---|---|
| Engine (godot/engine + tests) | yes | Typed `RefCounted` modules, one seeded stream, replayable log (D4); `CardMemory`, two effect modules, Crew modules, the decline action, the turn-start pause; gdUnit4 suite per module; `implementer-engine` for everything under `godot/engine/` |
| Godot scenes/UI | yes | `board/*`: hand faces with effective cost and a grown mark, hand restat steps, Crew line (Card3D line collection, D1), Skip button and Crew badges as plain Theme (D7); no picker change (C4); verified through the Godot MCP |
| Shaders/cards | no | Faces stay Label3D text; the grown mark is a Label3D glyph with a Theme colour; glows and dimmer are the DC-04 materials |
| Input | no | Pointer shim unchanged; Crew taps route through `PromptRules`/`LiftRules` |
| Tooling/scripts | minimal | `scripts/check.sh` unchanged; `BotStamp` (cycle 7) hashes `crew.json` too in B; the orchestrator runs `make bot-eval` per cycle 7 R36 |
| Vault/docs | yes | This set, the specs MOC row, cycles rows and the 20 s budget note at `/cycle test`, the Phase 3 amendment (C3) |
| Linear | yes | One project "Cycle 8 — ramp, bounce, Crew", two milestones (A, B; the next two free `DC-NN`), labels `area/engine`, `area/cards`, `area/ui`, `type/feature`, `spec/cycle-8-ramp-bounce-crew` (filled by `/exercise`) |

## Module layout

| File (under `godot/`) | class_name | Responsibility | Suite |
|---|---|---|---|
| `engine/data/cards.json` | – | Format 4: 80 cards, `effect.uses` optional (P1) | `test_card_db.gd`, `test_decks.gd` |
| `engine/data/decks.json` | – | v2: `bloom`, `echo`; `crew: [3 ids]` per deck (B) | `test_deck_list.gd` |
| `engine/data/crew.json` (B) | – | The eight Crew (P12) | `test_crew_pool.gd` |
| `tests/fixtures/dc05_cards.json`, `dc05_decks.json` | – | Fixture converted to format 4 / v2 (a fixture deck lists three Crew in B) | fixture users |
| `engine/card_effect.gd` | `CardEffect` | `uses: int`; trigger `ON_ALLY_REVEAL`; verbs per P4, P6 | `test_card_db.gd` |
| `engine/card_db.gd` | `CardDb` | Format 4 parse; R11 checks (`uses` whole, grow amounts in `GROW_STEPS`, verb/trigger pairs per `ALLOWED_TRIGGERS`) | `test_card_db.gd` |
| `engine/card_memory.gd` (new) | `CardMemory` | `flat`, `times`, `plus`, `cost`, `uses_left`, `is_empty()`, `copy()`, `to_dict()` (P2) | `test_card_memory.gd` |
| `engine/match_state.gd` | `MatchState` | `memory: Dictionary[int, CardMemory]` (never cleared at round start), `prompt.optional`, `prompt.resume`, `prompt.crew`; `crew_uses` (B) (P2, P9, P13) | `test_turn.gd` |
| `engine/match_rules.gd` | `MatchRules` | `RULES_VERSION` 5 (A) then 6 (B), `LOG_FORMAT` 4 (B), `GROW_STEPS`, `MIN_COST 0`, `SHADE_TURN 4` | – |
| `engine/score_walk.gd` | `ScoreWalk` | `effective()` adds memory (P3) and Tallyman (B, P14); `effective_cost()`; ally-reveal watcher stage (P5); Crew queue drain after each firing (B, P13) | `test_score_walk.gd`, `test_score_walk_memory.gd` |
| `engine/legal_plays.gd` | `LegalPlays` | Every cost read through `costs: Array[int]` parallel to the hand (P3); `commit_cost(proposal, free_first, cost_of: Callable)` | `test_legal_plays.gd` |
| `engine/effect_resolver.gd` | `EffectResolver` | Dispatch to `BloomEffects`, `EchoEffects`; `uses` countdown (P7); turn-end flip (P6); decline (B, P10); Crew hooks (B, P13) | `test_effects.gd` |
| `engine/bloom_effects.gd` (new) | `BloomEffects` | The grow family (P4) | `test_effects_bloom.gd` |
| `engine/echo_effects.gd` (new) | `EchoEffects` | Returns, flip, cost reductions, ally-reveal verbs (P6) | `test_effects_echo.gd` |
| `engine/choice.gd` | `Choice` | Zones per P8; `optional` on prompts; `GROW_HAND_ONE` on OWN_HAND | `test_choices.gd` |
| `engine/engine_action.gd` | `EngineAction` | `DECLINE` kind, dict `{"k":"decline","s":0}` (B, P10) | `test_engine_action.gd` |
| `engine/engine_error.gd` | `EngineError` | `NOT_OPTIONAL` (B) | `test_turn.gd` |
| `engine/action_log.gd` | `ActionLog` | Format 4 (B): the decline entry; format-3 logs fail replay | `test_action_log.gd` |
| `engine/match_engine.gd` | `MatchEngine` | `create(seed, cards, decks, deck_ids, crew: CrewPool)` (B); the turn-start pause (P11); `preview_decline(seat)` (B); round-end Crew (B) | `test_turn.gd`, `test_crew_flow.gd` |
| `engine/seat_view.gd` | `SeatView` | `own_hand_row` entries, `cost` and `grown` on row entries, `own_hand_costs`; `crew`, `crew_uses` (B); prompt `optional`, `crew` | `test_seat_view.gd` |
| `engine/match_event.gd` | `MatchEvent` | Kinds below | `test_seat_view.gd` |
| `engine/crew_def.gd`, `crew_pool.gd` (new, B) | `CrewDef`, `CrewPool` | Load `crew.json`, validate, `crew_of(id)` (P12) | `test_crew_pool.gd` |
| `engine/crew_effects.gd` (new, B) | `CrewEffects` | The eight abilities, the trigger queue (P13, P14) | `test_crew_effects.gd` |
| `engine/deck_list.gd` | `DeckList` | v2 parse; `crew_ids(deck_id)`; `validate(cards, crew)` (B) | `test_deck_list.gd` |
| `engine/match_cards.gd` | `MatchCards` | `has_trigger(ON_ALLY_REVEAL)`; `crew_for(seat)` (B) | `test_match_cards.gd` |
| `engine/bot/candidate_gen.gd`, `tuned_bot.gd`, `greedy_bot.gd` (cycle 7) | – | `costs` from the view (P3); hand-growth rule; optional prompts and turn-start rule (B, P15) | `test_candidate_gen.gd`, `test_tuned_bot.gd`, `test_greedy_bot.gd` |
| `engine/bot/bot_stamp.gd` (cycle 7, B) | `BotStamp` | Hash covers `crew.json` | `test_bot_stamp.gd` |
| `tests/test_full_match.gd` | – | Golden under the four-deck pairing (skip until pinned), sweep leak scan covers memory and Crew prompts | itself |
| `board/board_card.gd`, `board_card.tscn` | `BoardCard` | `CostLabel` effective cost, `GrownMark` glyph (P16) | node query |
| `board/board.gd`, `board_steps.gd`, `board_step.gd`, `effect_player.gd`, `lift_rules.gd`, `staging.gd`, `prompt_host.gd`, `prompt_rules.gd`, `board_hud.gd`, `match_driver.gd` | – | Hand restat, staging by effective cost, Skip button, Crew prompt before staging, `submit_decline` (P16, P17) | `test_board_steps.gd`, `test_prompt_rules.gd`, `test_lift_rules.gd`, `test_staging.gd`, MCP |
| `board/crew_line.gd` (new, B) | `CrewLine` | Three Crew per side as Card3D line, badges, fire pulse, lift-to-read (P17) | MCP, `test_crew_line_text.gd` (badge text, pure) |

## Design choices

| # | Choice | Why |
|---|---|---|
| P1 | **Pool format 4.** `cards.json` `"version": 4`; an effect may carry `"uses": n` (absent or 0 is unlimited). `CardDb` checks: `uses` a non-negative whole; a grow verb's amount in `MatchRules.GROW_STEPS` (`flat` {1, 2}, `times` {25, 50}, `plus` {1}, `cost` {1, 2}); each verb only on the triggers `CardEffect.ALLOWED_TRIGGERS[verb]` lists (for example `grow_self_times` on `on_score` or `on_reveal`, `unreveal_at_turn_end` on `ongoing` only, `ally_reveal_flat` and `draw` on `on_ally_reveal`). The DC-05 fixture is the same cards with the version bumped | R9, R11 |
| P2 | **CardMemory.** `MatchState.memory: Dictionary[int, CardMemory]` by instance id; `CardMemory {flat: int, times: int (hundredths delta), plus: int, cost: int (reduction ≥ 0), uses_left: int (-1 until first read, then the effect's `uses`)}`. `memory_for(card)` creates at defaults; `is_empty()` drops nothing (an entry with `uses_left` set is not empty). `_begin_round` does not touch it; `create()` starts it empty. `to_dict()` serialises `"memory": {id: {...}}`; `duplicate()` deep-copies. A recovery, return, un-reveal or round start never reads it; only `effective()`, `effective_cost()` and the uses check do | R2, R6, R8, R14 |
| P3 | **Effective stats and cost.** In `ScoreWalk.effective()`: after the base (printed or copied) add `memory.flat`, `memory.times` and `memory.plus`, then positional parts, `flat_delta`, `temp_plus`, then `no_bonus` (×1.00, +0; memory untouched). `ScoreWalk.effective_cost(card, state, cards) = max(def.cost - memory.cost, MatchRules.MIN_COST)`. `LegalPlays` no longer reads `CardDef.cost` directly: `enumerate_masks(hand, costs, energy)`, `validate(proposal, slots, hand, costs, row_size, budget, free_first)`, `commit_cost(proposal, proposal_costs, free_first)`; `MatchEngine` builds `costs` from `effective_cost` and `SeatView.own_hand_costs` carries them, so the bots (`CandidateGen.all(hand, costs, …)`, `GreedyBot.candidates`) and the board's staging read one number. `preview()` clones carry memory, so previews see the same costs and stats | R3, R4, R21, R24 |
| P4 | **The grow family (Bloom).** Verbs `grow_self_flat`, `grow_self_times`, `grow_self_plus`, `grow_self_times_once` (uses 1), `grow_other_flat` (prompt OWN_BOARD), `grow_hand_flat` (all hand), `grow_hand_one_times` (prompt OWN_HAND), `grow_row_flat`, `grow_row_times` (all other row cards). One `BloomEffects.grow(state, cards, seat, targets: Array[int], stat, amount, outcome)`: `memory_for(t).<stat> += amount`, then `STATS_CHANGED {seat, card, flat, times, plus, cost, cause: "grow", permanent: true}` per target, public for a row card, private to the holder for a hand card (redaction hides `card`). Empty target set → `EFFECT_FIZZLED`. Growth on a hand card changes no board state, so the walk's cursor is untouched | R12, R13, R26 |
| P5 | **ON_ALLY_REVEAL.** `CardEffect.Trigger.ON_ALLY_REVEAL`; in `Pulse.run` a new stage `ALLY_WATCHERS` between `WATCHERS` and `SCORE`: snapshot the revealing seat's other revealed live cards with the trigger, in row order, fire each (skipping any no longer revealed), pause/resume exactly like `_watchers` (the snapshot and index stored in `walk.paused_watchers` / `paused_watcher_at`, the stage in `paused_stage`). Skipped outright when `MatchCards.has_trigger(ON_ALLY_REVEAL)` is false | R15 |
| P6 | **Echo verbs.** `return_self_at_turn_end` (on_reveal: `return_marked` on the source), `return_own_at_turn_end` (prompt OWN_BOARD, live, source excluded → `return_marked`), `return_opponent_at_turn_end` (prompt OPPONENT_BOARD, revealed live → `return_marked`; `resolve_returns` already sends a card to its row's seat, the controller), `unreveal_at_turn_end` (ongoing marker; `EffectResolver.flip_echoes(state, cards)` runs in `_end_turn` after `clear_destroyed` and before `settle_energy`: for each seat, each revealed live card carrying it goes through `_unreveal` + `CARD_UNREVEALED`, in slot order), `cost_down_right` (on_reveal: the card at `slot + 1` of the source's row, any state; `memory.cost += amount`, `STATS_CHANGED cause "cost"`; none → fizzle), `cost_down_self`, `draw_once` (on_reveal, uses 1: `_draw(amount)`), `ally_reveal_flat` (on_ally_reveal: `flat_delta += amount`, cause `ally_reveal`), `draw` on `on_ally_reveal` (existing verb), `free_first_next_turn` (existing), `grow_self_flat` on `on_reveal` (P4) | R16–R18 |
| P7 | **Uses countdown.** Before `apply()` dispatches a verb whose effect has `uses > 0`: `memory_for(card).uses_left` is initialised to `uses` when -1; if 0 the firing emits `EFFECT_FIZZLED {…, reason: "spent"}` and nothing else; else it decrements and the verb runs; `STATS_CHANGED` is not emitted for a uses change, the `EFFECT_FIRED` payload carries `uses_left`. `SeatView` hand and row entries carry `uses_left` (-1 for unlimited) | R6, R12, R16 |
| P8 | **Eligibility.** `grow_other_flat`: OWN_BOARD, live, source excluded. `grow_hand_one_times`: OWN_HAND, every position (one eligible auto-chooses as any single prompt). `return_own_at_turn_end`: OWN_BOARD, live, not already return-marked, source excluded. `return_opponent_at_turn_end`: OPPONENT_BOARD, revealed, live, not return-marked. `Choice.needs_choice` and `zone_for` extended; `Choice.is_optional_prompt(prompt)` reads `optional` | R20 |
| P9 | **Prompt dictionary.** Gains `optional: bool` (always present, false for every card prompt in A), `resume: "walk" | "turn_start"` (A: always `"walk"`), and in B `crew: String` (the Crew id, `""` for a card prompt) with `card` -1 then. `CHOICE_REQUESTED` carries `optional` and `crew` | R49, R52, R54 |
| P10 | **Decline (B).** `EngineAction.Kind.DECLINE {seat}`, dict `{"k":"decline","s":0}`; `_check_decline`: a prompt open (`NO_PROMPT`), the prompted seat (`WRONG_SEAT`), `optional` true (`NOT_OPTIONAL`, new code). `_decline()`: `EffectResolver.decline(state)` clears the prompt, emits `CHOICE_DECLINED {seat, card, crew}` (public), no uses counted, then resumes per `prompt.resume`: `_run_walk()` or `_resume_turn_start()`. A `CHOOSE` on an optional prompt applies as today and counts the use. `LOG_FORMAT` 4; `ActionLog.from_dict` parses the kind; a format-3 log fails `FORMAT_MISMATCH` | R52, R53, R55 |
| P11 | **Turn-start pause (B).** `_begin_turn()` ends with `CrewEffects.turn_start(state, cards, crew, rng, outcome)` for each seat in first-committer order; a Crew prompt sets `state.prompt` with `resume: "turn_start"` and phase `AWAIT_CHOICE` (the walk inactive, `awaited_seat()` the prompted seat; `_check_commit` already rejects commits in `AWAIT_CHOICE`). `_choose`/`_decline` then call `_resume_turn_start()`, which runs the remaining turn-start Crew of that seat and the other seat, and finally sets `AWAIT_FIRST`. The view's `phase` and `prompt` tell the board | R54, R64 |
| P12 | **Crew data (B).** `crew.json`: `{"version": 1, "crew": [{"id": "shade", "name": "Shade", "trigger": "turn_start", "verb": "unreveal_own_one", "amount": 4, "optional": true, "uses": 0, "scope": "none", "text": "…"}, …]}`; `CrewDef` mirrors it; `CrewPool.load_default()`, `validate()`, `crew_of(id)`. `decks.json` `"version": 2`, each deck `"crew": ["salvager", "veil", "quartermaster"]`; `DeckList.validate(cards, crew)` checks three distinct known ids. `MatchEngine.create(seed, cards, decks, deck_ids, crew)`; `MatchCards.crew_for(seat) -> Array[CrewDef]`; `MATCH_STARTED` gains `crew`, two lists of three ids (seat 0's, seat 1's). The log header is unchanged (Crew derive from the deck ids) | R39–R42 |
| P13 | **Crew triggers (B).** `CrewDef.Trigger {TURN_START, ROUND_END, OWN_DESTROYED, OWN_MOVED, OWN_RETURNED, ONGOING}`. `MatchState.crew_uses: Array[Array[int]]` per seat per slot (-1 unlimited), reset per scope at `_begin_round`. A **queue**: `EffectResolver.destroy()`, `DriftEffects.rewrite_row()`, `resolve_returns()` and every un-reveal append `{trigger, seat, card}` to `state.crew_queue`; `ScoreWalk.Pulse` drains the queue after each `_fire` outcome resolves (and after an `answer`/`answer_set` resolves), firing matching Crew of the card's controller in slot order through `CrewEffects.fire()`; a Crew prompt pauses with `resume: "walk"` and the stage the pulse was at, the queue kept in state (`walk.crew_queue` is serialised). Turn-end hooks drain after `resolve_returns` and `flip_echoes`; round end fires `ROUND_END` Crew before `_leader()`. Events: `CREW_FIRED {seat, slot, crew, verb, trigger, uses_left}` (public), `CREW_SKIPPED` is `CHOICE_DECLINED`. A Crew with no eligible target is not fired and emits nothing | R45–R49 |
| P14 | **The eight Crew (B).** Quartermaster `turn_start` amount 1 (turn == amount): `_draw(2)`. Tallyman `ongoing`: in `effective()`, when the card's row seat holds Tallyman and `flat % 2 == 0`, `times = times_hundredths(times, 125)` after the positional parts (skipped when neither seat has it). Shade `turn_start` amount 4, optional, verb `unreveal_own_one` (prompt OWN_BOARD revealed live): `_unreveal` + `CARD_UNREVEALED`, queues `OWN_RETURNED`. Salvager `own_destroyed`, optional, scope round: prompt OWN_HAND (every position; empty hand → not fired); accept: `_discard(chosen)`, `card_state_for(destroyed).salvaged = true`; `clear_destroyed()` sends a salvaged card to its controller's hand (burn at cap) with `DESTROYED_CLEARED {…, pile: false, salvaged: true}` and queues `OWN_RETURNED`. Veil `own_destroyed`, optional, scope match: prompt over the destroyed card only (one option, still prompted, R49); accept: clear `destroyed` on it, then `_unreveal` every revealed card of that row (it included) in slot order, one `CARD_UNREVEALED` each, queue `OWN_RETURNED` per card. Navigator `own_moved`: `flat_delta += 1`, `STATS_CHANGED cause "crew"`. Gardener `round_end`: `grow(row cards, flat, 1)` for its seat. Lookout `own_returned`: `_draw(1)` | R47, R50, R51 |
| P15 | **Bot (A and B).** `CandidateGen.all(hand, costs, budget, row_size, free_first, seat, cards)`; `TunedBot` and `GreedyBot` pass `view.own_hand_costs`; `bound()` unchanged (stats from `effective` via the view's entries, not `CardDef`: `stats_of` reads `own_hand_row`). Prompt rules: `grow_hand_one_times` → the hand card with the highest effective flat (ties by position), no preview (the hand never scores in a preview); every other new single prompt by preview. B: an optional walk prompt → preview each option (`preview_choice`) and the decline (`preview_decline(seat)`: clone, `EffectResolver.decline`, `_hide_opponent`, finish the walk), best value, ties by the prompt rng; a turn-start prompt (`view.prompt.resume == "turn_start"`) → `shade` rule (R57), any other → decline. `BotStamp.current()` hashes `cards.json`, `decks.json`, `crew.json` (and `records.py` the same) | R21–R23, R56–R58 |
| P16 | **Board A.** `BoardCard`: `CostLabel` text from the view entry's `cost`; `GrownMark` (a Label3D "◆" in a Theme colour, visible when `grown`); `show_entry(entry)` used for hand and row faces alike. `SeatView.own_hand_row` drives hand faces at `TURN_START`, after a `STATS` step on a hand card (new: `BoardSteps` maps a private `STATS_CHANGED` whose card is in the viewer's hand to a `STATS` step with `in_hand: true`; `EffectPlayer.restat_hand`), and after draws. `Staging` cost checks read `view.own_hand_costs` (`board._cost_of`). `LiftRules.step_touches` covers the hand restat. Turn-end `CARD_UNREVEALED` and `CARD_RETURNED` already have steps; the strip's `_dress` uses `show_entry` with memory | R24–R28 |
| P17 | **Board B.** `CrewLine` (RefCounted, like `DeckStrip`): a Card3D line of three `BoardCard`s per side at `CREW_ORIGIN_OWN` (left of the player's hand) and `CREW_ORIGIN_OPP` (left of the opponent's hand), built from `MATCH_STARTED.crew` with name and text, `badge: Label3D` ("2 left" / "spent", dimmed at 0; hidden for unlimited), `pulse(slot)` on a `CREW_FIRE` step (`BoardSteps` maps `CREW_FIRED`, 0.25 s), badge update from `uses_left`. `LiftRules`: a Crew lifts to read, never drags (`BoardDragStrategy` refuses). Prompt: `PromptHost.open` shows `hud.show_skip()` when `prompt.optional` (a plain Theme Button at the confirm's anchor, text "Skip"); `skip_pressed` → `driver.submit_decline()` → `EngineAction.decline(0)`. Banner text for a Crew prompt: `"<Crew name>: <text>"`. Turn-start prompt: the `PROMPT` step arrives before `TURN_START`'s staging unlock; `board.may_act()` is false while a prompt is open (already), Commit disabled, `_refresh_staging_ui` after the prompt closes. `CHOICE_DECLINED` → a `FIZZLE`-like 0.15 s step clearing the prompt. Salvaged `DESTROYED_CLEARED {pile: false}` → `RETURN` step instead of the fly-off; pile counts read `pile` | R59–R66 |

## Interfaces and contracts

```gdscript
# CardMemory
var flat: int; var times: int; var plus: int; var cost: int; var uses_left: int = -1
func is_empty() -> bool; func copy() -> CardMemory; func to_dict() -> Dictionary

# MatchState
var memory: Dictionary[int, CardMemory]
func memory_for(card: int) -> CardMemory            # creates at defaults
func memory_of(card: int) -> CardMemory             # null when none
var crew_uses: Array[Array]                         # B, per seat: [uses_left ×3], -1 unlimited
var crew_queue: Array[Dictionary]                   # B, {trigger, seat, card}

# ScoreWalk
static func effective(card, state, cards) -> Effective        # memory, then board changes
static func effective_cost(card: int, state: MatchState, cards: MatchCards) -> int
enum Stage { REVEAL_EFFECT, WATCHERS, ALLY_WATCHERS, SCORE, DONE }

# LegalPlays (every cost from the caller)
static func enumerate_masks(hand: Array[int], costs: Array[int], energy: int) -> Array[int]
static func validate(proposal, slots, hand, costs, row_size, budget, free_first) -> int
static func commit_cost(proposal: Array[int], proposal_costs: Array[int], free_first: bool) -> int

# SeatView
var own_hand_row: Array[Dictionary]     # {card, cost, flat, times, plus, grown, uses_left}
var own_hand_costs: Array[int]          # parallel to own_hand
# own_row / opponent_row entries gain: cost, grown, uses_left (hidden entries: 0, false, -1)
var crew: Array[Array]                  # B, per seat: three Crew ids (public)
var crew_uses: Array[Array]             # B
# prompt gains: optional: bool, resume: String, crew: String

# EngineAction (B)
enum Kind { COMMIT, CONCEDE, CHOOSE, CHOOSE_SET, DECLINE }
static func decline(p_seat: int) -> EngineAction     # {"k":"decline","s":0}

# MatchEngine
static func create(match_seed, cards: CardDb, decks: DeckList, deck_ids: Array[String], crew: CrewPool) -> MatchEngine   # B adds crew
func preview_decline(seat: int) -> Array[int]        # B; [] unless an optional walk prompt is open for seat

# CrewPool / CrewDef (B)
static func load_default() -> CrewPool
func validate() -> String; func crew_of(id: String) -> CrewDef
class CrewDef: id, name, trigger: Trigger, verb: Verb, amount: int, optional: bool, uses: int, scope: Scope, text

# CandidateGen (cycle 7, amended)
static func all(hand: Array[int], costs: Array[int], budget: int, row_size: int, free_first: bool, seat: int, cards: MatchCards) -> Array[EngineAction]

# MatchDriver (B)
func submit_decline() -> ApplyResult

# BoardHud (B)
signal skip_pressed
func show_skip() -> void; func hide_skip() -> void; func skip_visible() -> bool

# CrewLine (B)
func build(parent: Node3D, side: int, crew: Array[CrewDef], make_card: Callable) -> void
func set_uses(slot: int, uses_left: int) -> void
func pulse(slot: int, seconds: float) -> void
func has_card(card: Card3D) -> bool
```

### Events (new or changed; redaction in brackets)

| Kind | Payload |
|---|---|
| `STATS_CHANGED` | + `cost`, `permanent: bool`; `cause` adds `grow`, `cost`, `ally_reveal`, `crew`; private to the holder when the card is in a hand [card hidden] |
| `EFFECT_FIRED` | + `uses_left` (-1 unlimited) |
| `EFFECT_FIZZLED` | + `reason` (`"no_target"`, `"spent"`) |
| `CARD_UNREVEALED` | unchanged; now also at turn end (the echo flip), from Shade and Veil |
| `CHOICE_REQUESTED` | + `optional`, `resume`, `crew` (B) |
| `CHOICE_DECLINED` (new, B) | `seat`, `card`, `crew`; public |
| `MATCH_STARTED` | + `crew`: two lists of three Crew ids, seat 0's then seat 1's (B) |
| `CREW_FIRED` (new, B) | `seat`, `slot`, `crew`, `verb`, `trigger`, `uses_left`; public |
| `DESTROYED_CLEARED` | + `salvaged: bool`; `pile` false for a salvaged card (B) |
| `TURN_STARTED` | unchanged; a Crew prompt may follow it before any `COMMITTED` (B) |

### Error codes (appended)

`NOT_OPTIONAL` (B: a decline on a prompt that is not optional). `CARD_DATA_INVALID` now also
covers a bad `uses`, a grow amount outside `GROW_STEPS`, a verb on a trigger it may not use,
and (B) a bad Crew pool or a deck with other than three distinct known Crew.

## Data model

### Bloom (`bloom`, "Grow your cards for good: bonuses that stay for the match.")

| id | name | cost | flat | bonus | effect (trigger: verb, amount[, uses]) | text |
|---|---|---|---|---|---|---|
| b01 | Seed | 1 | 1 | – | on_score: grow_self_flat, 1 | Whenever this scores, +1 flat for the match. |
| b02 | Sprout | 1 | 2 | – | – | |
| b03 | Acorn | 1 | 1 | ×1.25 | – | |
| b04 | Moss | 1 | 3 | – | – | |
| b05 | Sapling | 2 | 1 | – | on_score: grow_self_times, 25 | Whenever this scores, ×+0.25 for the match. |
| b06 | Tiller | 2 | 2 | – | on_reveal: grow_other_flat, 1 | Another card of yours gets +1 flat for the match. |
| b07 | Bramble | 2 | 3 | ×1.25 | – | |
| b08 | Rain | 2 | 1 | – | on_reveal: grow_hand_flat, 1 | Each card in your hand gets +1 flat for the match. |
| b09 | Vine | 3 | 2 | – | on_reveal: grow_hand_one_times, 25 | A card in your hand gets ×+0.25 for the match. |
| b10 | Trunk | 3 | 4 | ×1.25 | – | |
| b11 | Orchard | 3 | 2 | – | on_reveal: grow_row_flat, 1 | Each other card on your row gets +1 flat for the match. |
| b12 | Grove | 4 | 3 | – | on_score: grow_self_plus, 1 | Whenever this scores, its +bonus grows by 1 for the match. |
| b13 | Elder | 4 | 3 | ×1.5 | – | |
| b14 | Harvest | 4 | 5 | – | on_reveal: draw, 1 | Draw a card. |
| b15 | Oak | 5 | 4 | – | on_score: grow_self_times_once, 50, uses 1 | Once per match, when this scores: ×+0.5 for the match. |
| b16 | Canopy | 5 | 5 | ×1.25 | – | |
| b17 | Redwood | 6 | 6 | – | on_reveal: grow_hand_flat, 2 | Each card in your hand gets +2 flat for the match. |
| b18 | Bloom | 6 | 4 | +1 | – | |
| b19 | Ancient | 7 | 7 | ×1.5 | – | |
| b20 | World Tree | 7 | 5 | – | on_reveal: grow_row_times, 25 | Each other card on your row gets ×+0.25 for the match. |

Curve 4-4-3-3-2-2-2; 11 effect cards, 9 vanilla; ×1.25 on four, ×1.5 on two, +1 on one.
Bloom's bodies start under the curve and grow past it by round 3.

### Echo (`echo`, "Replay your reveals: returns, flips and cards that remember.")

| id | name | cost | flat | bonus | effect (trigger: verb, amount[, uses]) | text |
|---|---|---|---|---|---|---|
| e01 | Whisper | 1 | 1 | – | on_reveal: grow_self_flat, 1 | Whenever this reveals, +1 flat for the match. |
| e02 | Spark | 1 | 2 | – | – | |
| e03 | Flicker | 1 | 1 | ×1.25 | on_reveal: return_self_at_turn_end | Returns to your hand at the end of the turn. |
| e04 | Glint | 1 | 3 | – | – | |
| e05 | Echo | 2 | 2 | – | ongoing: unreveal_at_turn_end | At the end of the turn, this card flips face down. |
| e06 | Refrain | 2 | 1 | – | on_ally_reveal: ally_reveal_flat, 1 | Whenever another card of yours reveals, +1 flat this round. |
| e07 | Ripple | 2 | 3 | ×1.25 | – | |
| e08 | Messenger | 2 | 2 | – | on_reveal: draw_once, 2, uses 1 | The first time this reveals each match, draw 2. |
| e09 | Tinker | 3 | 3 | – | on_reveal: cost_down_right, 1 | The card to the right of this one costs 1 less for the match. |
| e10 | Recall | 3 | 2 | – | on_reveal: return_own_at_turn_end | Another card of yours returns to your hand at the end of the turn. |
| e11 | Chime | 3 | 4 | ×1.25 | – | |
| e12 | Banish | 4 | 3 | – | on_reveal: return_opponent_at_turn_end | An enemy card returns to its owner's hand at the end of the turn. |
| e13 | Lantern | 4 | 4 | – | on_reveal: free_first_next_turn | Next turn, your first card is free. |
| e14 | Mirage | 4 | 5 | ×1.25 | – | |
| e15 | Relay | 5 | 3 | – | on_ally_reveal: draw, 1 | Whenever another card of yours reveals, draw a card. |
| e16 | Signal | 5 | 5 | ×1.5 | – | |
| e17 | Reverb | 6 | 5 | – | on_reveal: cost_down_self, 2 | This card costs 2 less for the match. |
| e18 | Resonance | 6 | 3 | +1 | – | |
| e19 | Encore | 7 | 10 | – | on_reveal: return_self_at_turn_end | Returns to your hand at the end of the turn. |
| e20 | Eternity | 7 | 7 | ×2 | – | |

Curve 4-4-3-3-2-2-2; 12 effect cards, 8 vanilla; ×1.25 on four, ×1.5 on one, ×2 on one, +1
on one. Encore's flat 10 is within cost+4 (cycle 6 C13) and is paid for by scoring once per
play.

### Crew (`crew.json`, milestone B)

| id | name | trigger | optional | uses / scope | ability | decks |
|---|---|---|---|---|---|---|
| quartermaster | Quartermaster | turn_start (turn 1) | no | – | Draw 2 extra cards on the first turn of each round. | ruin, bloom, echo |
| tallyman | Tallyman | ongoing | no | – | Your cards with an even flat (0 counts) get ×1.25 when they score. | drift, bloom |
| shade | Shade | turn_start (turn 4) | yes | – | You may flip one revealed card of yours face down. | echo |
| salvager | Salvager | own_destroyed | yes | 1 / round | You may discard a card: the destroyed card returns to your hand at the end of the turn instead of going to your pile. | ruin |
| veil | Veil | own_destroyed | yes | 1 / match | You may flip every revealed card you control face down instead; none of them is destroyed. | ruin, drift |
| navigator | Navigator | own_moved | no | – | Whenever a card of yours is moved, it gets +1 flat this round. | drift |
| gardener | Gardener | round_end | no | – | When a round ends, each card on your row gets +1 flat for the match. | bloom |
| lookout | Lookout | own_returned | no | – | Whenever a card of yours returns to your hand or flips face down, draw a card. | echo |

Deck Crew: ruin `[salvager, veil, quartermaster]`, drift `[navigator, veil, tallyman]`,
bloom `[gardener, tallyman, quartermaster]`, echo `[shade, lookout, quartermaster]`.

### `MatchState` additions (all in `to_dict()`)

| Field | Type | Notes |
|---|---|---|
| `memory` | `Dictionary[int, CardMemory]` | per instance; never cleared at round start (P2) |
| `prompt.optional`, `prompt.resume`, `prompt.crew` | `bool`, `String`, `String` | P9 |
| `card_states[id].salvaged` | `bool` | B, P14 |
| `crew_uses` | `Array[Array]` | B, per seat per slot (P13) |
| `crew_queue` | `Array[Dictionary]` | B, pending Crew triggers (P13) |

### Action log

Milestone A: format 3, rules 5 (no structural change). Milestone B: format 4, rules 6:

```json
{"format": 4, "rules": 6, "seed": "1", "decks": ["bloom", "echo"],
 "actions": [{"k":"commit","s":0,"c":[3,7],"p":[0,1]}, {"k":"choose","s":0,"z":0,"i":2},
             {"k":"decline","s":1}, {"k":"concede","s":1}]}
```

## Constitution Check

| Rule | Verdict | Note |
|---|---|---|
| All project GDScript is fully typed (`parse` promotes warnings to errors) | PASS | `CardMemory`, `CrewDef` are classes; costs are `Array[int]`; the typed-strict checklist in every brief |
| Engine is deterministic: seeded RNG, no wall-clock, no node access, serializable action log (D4) | PASS | No new random pick (R72); memory, uses, crew uses and the queue are in `to_dict()`; the decline is a logged action; previews clone memory and never touch the stream |
| `make check` gate contract | PASS | Boot prints `Engine smoke:` and `Main ready`; golden re-pinned at verification; the 20 s gdUnit budget (C8) is a DoD item, not a gate change |
| Implementers never run Godot or `make check` | PASS | Golden left as a skip with literals to pin |
| P5 frontmatter and vault-root links | PASS | Three notes, fresh uids |
| Do-not-touch list | PASS | No addon change; the Crew line uses Card3D's line layout as the strip does |
| Secrets only in `.env` | PASS | None involved |
| One branch per cycle, one commit per task, `--no-ff` into `master` (ADR 0002) | PASS | A on `cycle-8-ramp-bounce-crew` (re-based onto `master` after DC-08 merges, C2); B on `cycle-8b-ramp-bounce-crew` cut from `master` after A merges |
| D2 Compatibility-clean visuals | PASS | Label3D text and DC-04 materials only |
| D7 plain Theme for UI | PASS | Skip button and badges are plain Theme controls and Label3D |
| Cycle 7 rerun provision (R36 there) | PASS | R32, R58: `make bot-eval` at each `/cycle test`; `BotStamp` covers `crew.json` in B |

**Result:** PASS.

## Risks and mitigations

- **Costs leave `CardDef`** → T01 changes `LegalPlays` to take costs and every caller in one
  mechanical pass before any rule changes; the suites pin behaviour unchanged with zero
  reductions; cycle 7's `CandidateGen` is amended in the same task so the bot never reads a
  printed cost.
- **Memory on a hidden card leaking** → `STATS_CHANGED` for a hand card is private; the sweep's
  leak scan compares every view and event against the full state's hidden ids (R8, R73); a
  suite asserts the opponent's view never carries a hand card's memory.
- **Mid-walk row changes** → none: every return is a turn-end mark, the flip keeps the slot,
  Veil and Shade un-reveal in place (R19).
- **The ally-watcher stage interleaving with the opponent watchers** → a fixed order
  (REVEAL_EFFECT → WATCHERS → ALLY_WATCHERS → SCORE) and pause/resume through the same
  `paused_*` fields; `test_effects_echo` covers a prompt inside each stage.
- **Crew firing inside another effect** → the queue drains only after a firing resolves (P13),
  so counts are settled; a Crew prompt pauses like a watcher's. A suite runs Immolator with
  Salvager and Veil through every answer.
- **Turn-start pause breaking the board's turn flow** → the board already disables input while
  a prompt is open; `may_act()` reads the view's phase; T12 adds the case "prompt before the
  first commit" to `test_board_steps` and the MCP run.
- **Twelve-plus new verbs in one task** → split by deck (T02 Bloom, T03 Echo), each with its
  own suite and module (`BloomEffects`, `EchoEffects`), the resolver only dispatching.
- **Tallyman in `effective()` costs time in the sweep** → skipped unless a seat holds it
  (`MatchCards.has_crew`), as the positional parts are.
- **Stamp mismatch after the pool change** → expected; R32 and cycle 7 R36 say what to run.
  With default weights (before cycle 7 B) `make bot-eval` is a draw check and `bot-train` is
  not expected to be needed; if it is, it is the overnight run the orchestrator already owns.
- **The 20 s budget** → measured at each verification; if B lands over it, the speed skips of
  cycle 6 T12 are the first lever and the cycles row records the number.
- **Table balance is untested design** → Ben reviews both tables at sign-off (cycle 6 C7);
  numbers are data, so a rebalance after the sweep is a JSON edit and a golden re-pin.

## Open questions

- None. Numbers in the tables are Ben's to strike or change at sign-off.
