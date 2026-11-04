---
type: plan
tags: [plan, cycle-4-card-effects, engine, board]
status: approved
related: ["[[specs/cycle-4-card-effects/spec]]", "[[specs/cycle-4-card-effects/tasks]]", "[[specs/cycle-1-match-engine/plan]]", "[[specs/cycle-3-board-feedback/plan]]", "[[planning/phase-1-tech-stack]]"]
created: 2026-11-03
updated: 2026-11-03
uid: baf3efcd-e891-4436-93b4-b54f789cf07e
linear:
supersedes:
---

# Plan: Cycle 4 — card effects

Implements [[specs/cycle-4-card-effects/spec|spec]]. The engine half rewrites turn
resolution around an ordered, resumable walk and adds effects, prompts and a preview; the
board half follows the new events. Rules version and log format both go to 2.

## Stack mapping

| Area | Involved | Approach and tooling |
|---|---|---|
| Engine (godot/engine + tests) | yes | Typed `RefCounted` modules, one seeded stream, replayable log (D4); new suites per module; `implementer-engine` |
| Godot scenes/UI | yes | `board/*` follows the new events; plain Theme (D7); Card3D layouts and tweens (D1); verified on `board/verify/board_seed1.tscn` through the Godot MCP |
| Shaders/cards | no | Glows and dimmer are the DC-04 unshaded materials; faces are Label3D text |
| Input | no | The pointer shim is unchanged; prompts route through the existing `tapped` signal |
| Tooling/scripts | minimal | `scripts/check.sh` keeps its boot grep; the golden line it expects is re-pinned at T14 |
| Vault/docs | yes | This set, the specs MOC row, the DC-05 row in [[planning/cycles]] at `/cycle test` |
| Linear | yes | Project "Cycle 4 — card effects", milestone `DC-05 card-effects`, labels `area/engine`, `area/cards`, `area/ui`, `type/feature`, `spec/cycle-4-card-effects` (filled by `/exercise`) |

## Module layout

| File (under `godot/`) | class_name | Responsibility | Suite |
|---|---|---|---|
| `engine/data/cards.json` | – | Format 2: the table below | `test_card_db.gd` |
| `engine/card_def.gd` | `CardDef` | `id`, `name`, `cost`, `flat`, `bonus`, `effect: CardEffect` (null for vanilla) | `test_card_db.gd` |
| `engine/card_effect.gd` | `CardEffect` | `trigger` (ON_REVEAL, ON_OPPONENT_REVEAL, ON_SCORE, ONGOING), `verb` (enum below), `amount: int`, `text: String`; `from_dict` | `test_card_db.gd` |
| `engine/card_db.gd` | `CardDb` | Format 2 parse and R2 validation | `test_card_db.gd` |
| `engine/card_state.gd` | `CardState` | Per-instance modifiers (data model) | `test_score_walk.gd` |
| `engine/match_rules.gd` | `MatchRules` | `RULES_VERSION := 2`, `LOG_FORMAT := 2`, `MAX_BONUS := 2` | – |
| `engine/engine_action.gd` | `EngineAction` | `COMMIT` with `slots`, `CONCEDE`, new `CHOOSE` (`zone`, `index`) | `test_action_log.gd` |
| `engine/engine_error.gd` | `EngineError` | Appends `BAD_SLOTS`, `NO_PROMPT`, `NOT_ELIGIBLE` | `test_turn.gd` |
| `engine/legal_plays.gd` | `LegalPlays` | `validate(proposal, slots, hand, row_size, budget, free_first, cards)`; enumeration unchanged | `test_legal_plays.gd` |
| `engine/match_state.gd` | `MatchState` | Rows, per-seat energy state, walk progress, open prompt | `test_turn.gd` |
| `engine/score_walk.gd` | `ScoreWalk` | The pure, resumable walk over a `MatchState`: next pulse, scoring math, cursor rules (R11–R18). Used live and by the preview | `test_score_walk.gd` |
| `engine/effect_resolver.gd` | `EffectResolver` | Applies one verb to a state, returns the events it caused or the prompt it needs (R19–R27) | `test_effects.gd` |
| `engine/choice.gd` | `Choice` | Zones, eligibility lists, target resolution (R28–R34) | `test_choices.gd` |
| `engine/match_engine.gd` | `MatchEngine` | Entry point; orchestrates commit → walk → prompts → turn end; `preview()` | `test_turn.gd`, `test_round_match_end.gd` |
| `engine/seat_view.gd` | `SeatView` | Adds rows with per-card shown stats, pending slots, per-seat budgets, open prompt | `test_seat_view.gd` |
| `engine/match_event.gd` | `MatchEvent` | New kinds below; redaction of prompt and choice payloads | `test_seat_view.gd` |
| `engine/action_log.gd` | `ActionLog` | Format 2; replay with choices | `test_action_log.gd` |
| `engine/bot/greedy_bot.gd` | `GreedyBot` | Preview-driven commit and choice (R36–R38) | `test_greedy_bot.gd` |
| `tests/test_full_match.gd` | – | Golden (re-pinned at T14), 50-seed sweep with prompts, leak and replay checks | itself |
| `board/board_step.gd`, `board_steps.gd` | `BoardStep`, `BoardSteps` | New step kinds and the two-speed pulse | `test_board_steps.gd` |
| `board/staging.gd` | `Staging` | Staged ids with row slots; budget and free card | `test_staging.gd` |
| `board/prompt_rules.gd` | `PromptRules` | Pure: which cards glow, which taps choose or lift (R55–R56) | `test_prompt_rules.gd` |
| `board/lift_rules.gd` | `LiftRules` | `step_touches` extended to the new kinds (R54) | `test_lift_rules.gd` |
| `board/board.gd`, `board_card.gd`, `board_hud.gd` + scenes | – | Faces, slots, commit flip, walk, prompt UI | MCP at T14 |

## Design choices

| # | Choice | Why |
|---|---|---|
| P1 | **Slots in the commit are final-row indices.** `EngineAction.commit(seat, cards, slots)`; `slots[i]` is where `cards[i]` sits once every committed card is in place; strictly increasing; all within `0 .. row_size + cards.size() - 1`. The engine merges by walking 0..n and taking the committed card whose slot matches, else the next played card | One number per card, trivially validated (R5, R6), and the board already knows each staged card's row index (R45) |
| P2 | **Pending cards are placed at resolution.** `pending` keeps `cards` and `slots`; the second committer's view shows `opponent_pending_slots` (R7). At `_resolve()` both commits merge (first committer first), then the walk starts | Keeps R14's "face down until the second commits" and lets the board slide opponent backs into named slots (R47) |
| P3 | **The walk is resumable state, not a loop.** `MatchState.walk = {active: bool, next_seat: int, pulsed: Dictionary[int, bool], mult: [int, int]}`; `ScoreWalk.step(state, cards, sink)` performs one pulse and returns whether a prompt opened. `MatchEngine._run_walk()` loops `step` until the walk ends or a prompt pauses it; `apply(CHOOSE)` applies the choice then calls `_run_walk()` again | A prompt is just another decision point in R4's "advance to the next point that needs a seat's decision"; replay needs no special casing |
| P4 | **Pulse math** (R14): `mult[seat] += eff_bonus(card)`; `added = eff_flat(card) * mult[seat]`; `scores[seat] += added`; emit `CARD_SCORED`. Effective stats: `CardState` applies `switched` (swap flat and bonus), `flat_delta`, `bonus_zero`, then ongoing modifiers from revealed cards (none in this deck, hook kept) | One function `ScoreWalk.effective(card, state, cards) -> Vector2i` used by live, preview and `SeatView` |
| P5 | **Cursor rule** (R12, R16): the next pulse is the leftmost card of `walk.next_seat`'s row not in `pulsed`; if none, the other seat's; if neither, the walk ends. After each pulse `next_seat` flips. Destroyed and moved cards are handled by the `pulsed` set, not by indices | Swaps and destroys cannot double-pulse or skip |
| P6 | **Effect hooks.** `ON_REVEAL` fires in the pulse before scoring; `ON_SCORE` after `CARD_SCORED`; `ON_OPPONENT_REVEAL` fires for every revealed card of the other seat when a card is revealed (framework and a test with an in-memory card; no deck card); `ONGOING` is read by `effective()` and by turn end (energy carry) | R13, R15, R18, R19 |
| P7 | **Per-seat energy.** `MatchState.energy = {carry: [int, int], free_first: [bool, bool], spent: [int, int]}`; budget = `turn + carry[seat]`; `free_first[seat]` is consumed at that seat's next commit (unused is lost); at turn end, if the energy-carry card is revealed on the seat's row, `carry[seat] = budget - spent[seat]`, else 0 | R9, R10, R20 |
| P8 | **Verbs** (`CardEffect.Verb`): `DRAW` (amount), `DRAW_THEN_DISCARD` (amount, prompt own hand), `FREE_FIRST_NEXT_TURN`, `SWAP_PLACES` (prompt own board, others), `SWITCH_STATS` (prompt any revealed card, self included), `OPPONENT_NEXT_BONUS_ZERO`, `RETURN_AT_TURN_END` (prompt any other revealed card), `DESTROY_RANDOM_OPPONENT`, `FLAT_UP_ON_SCORE` (amount), `CARRY_ENERGY` | R20; each verb is one branch of `EffectResolver.apply()` with its own test |
| P9 | **Prompts.** `MatchState.prompt = {seat, card, verb, zone, options: Array[int]}` (positions in the zone). `Choice.eligible(state, seat, verb)` builds `zone` and `options`. 0 options → `EFFECT_FIZZLED`; 1 → auto `CHOICE_MADE`; 2+ → `CHOICE_REQUESTED`, `phase = AWAIT_CHOICE`, `awaited_seat()` returns the prompted seat | R26, R28, R29 |
| P10 | **Zones**: `OWN_HAND`, `OWN_BOARD`, `OPPONENT_HAND`, `OPPONENT_BOARD`, relative to the prompted seat; `index` is the position in that zone's list at the time of the choice. The engine resolves index → instance id; `CHOICE_MADE` carries `card` as a private field when the zone is a hand (R34) | A face-down card is chosen without its identity (R30) |
| P11 | **Randomness order.** The engine stream is consumed by: round-start shuffles and coin (as before), then `DESTROY_RANDOM_OPPONENT` picks via `pick_index` at the moment the effect fires. Preview never touches the stream | R27, R35; replay reproduces because the walk order is deterministic given the log |
| P12 | **Preview** (R35): `MatchEngine.preview(seat, action) -> Array[int]` (scores pair) clones `MatchState` (`duplicate()` added), merges the commit into the clone's row with the opponent's pending treated as absent, runs `ScoreWalk` to the end with a `PreviewPolicy` (prompt → first option; random → opponent's lowest-flat card; no events, no RNG), and returns the clone's scores. `preview_choice(seat, index)` does the same from an open prompt | The bot gets truthful order and effect values without touching state |
| P13 | **Bot search** (R36): for each legal mask, two orders (bonus desc then flat desc; flat desc then bonus desc; both tie-broken by instance id) × two placements (slots `0..k-1`, or `row_size..row_size+k-1`) → ≤ 512 previews per decision, ≤ 128 when the row is empty (dedupe identical slot lists). Score = `own - opponent`; ties → `pick_index` from the per-decision seed. Prompts (R37): preview each option, same tie-break | Under 10 ms per decision in the 50-seed sweep is the T14 budget |
| P14 | **Turn end.** After the walk: `RETURN_AT_TURN_END` marks resolve (to hand or burn), energy carry computed, `TURN_ENDED {round, turn, scores, winner}`; then `_begin_turn()` emits `TURN_STARTED {round, turn, budgets: [a, b], free_first: [bool, bool], first_seat}` | R17, R24, R9 |
| P15 | **Board slots.** `Staging` keeps `(id, slot)` pairs where `slot` is the card's index in `player_row.cards`; `_normalize_row()` no longer forces staged cards after played ones; `BoardDragStrategy.can_drag()` is false for played (revealed or committed) cards (R44); a drop inserts at the release index as Card3D already does, which opens the gap (R43) | R43–R45 with no addon change |
| P16 | **Commit flip** (R46): `PLAYER_COMMIT` step gains `duration = 0.30`; the board flips every staged card `face_down = true` together with one tween each | The commit is readable as one gesture |
| P17 | **Walk steps.** `WALK_START` (scores and mults to 0 and 1), `PULSE` with `revealed: bool` (duration 0.12 when already revealed, else 0.35 with the 0.15 gap, and the flip) carrying `flat`, `bonus`, `mult`, `added`, `score`; the HUD shows `score ×mult` per side during a walk and plain score after `TURN_END` | R50–R52, C15 |
| P18 | **Effect steps.** `EFFECT` (0.25 s, the source card lifts briefly), `STATS` (number update and pulse, 0.2), `DESTROY` (fly out, 0.45), `MOVE` (row re-layout, 0.3), `RETURN` (to hand, 0.3), `DISCARD` (hand to exit, 0.45), `FIZZLE` (0.15, text "no target" fades on the card), `CHOICE_SHOW` (bot's pick glows 0.4) | R42, R53, R58 |
| P19 | **Prompt UI** (R55–R57): `PROMPT` step is not timed; the runner stops advancing until `Board.submit_player(choose)` is accepted. `PromptRules.glow_set(prompt, view)` maps `zone` + `options` to `BoardCard`s (the opponent's hand by fan index); eligible cards reuse the DC-04 `ZoneGlow` material on a per-card `Glow` child; the DC-04 dimmer dims the rest; the banner is a `PanelContainer` under `TopInfo`. `PromptRules.on_tap(hit, prompt) -> {CHOOSE, LIFT, NOTHING}` keeps C16 testable | Builds on DC-04's glow, dimmer and lift without new materials |
| P20 | **Faces** (R41): `board_card.tscn` gains `BonusLabel` (top right, "+N" in gold, hidden when 0), `FlatLabel` replaces `PowerLabel` (bottom right), `TextLabel` (rules text, word wrap, under the name, size 20). `BoardCard.show_stats(flat, bonus)` pulses the changed label (R42) | Readable at the DC-04 lift size |
| P21 | **Rim retired** (R48): `Rim` node, `set_unseen`, `_revealed_ids` bookkeeping and `_refresh_rims()` are removed; `test_lift_rules` loses the rim cases | Face-down now carries the meaning |

## Interfaces and contracts

```gdscript
# EngineAction
enum Kind { COMMIT, CONCEDE, CHOOSE }
static func commit(seat: int, cards: Array[int], slots: Array[int]) -> EngineAction
static func choose(seat: int, zone: int, index: int) -> EngineAction
# dict forms: {"k":"commit","s":0,"c":[3,7],"p":[0,2]}  {"k":"choose","s":1,"z":1,"i":0}

# MatchEngine (additions)
func budget_for(seat: int) -> int                       # turn + carry
func preview(seat: int, action: EngineAction) -> Array[int]        # [score0, score1]
func preview_choice(seat: int, index: int) -> Array[int]
func open_prompt() -> Dictionary                         # {} when none

# ScoreWalk (pure)
static func begin(state: MatchState) -> void
static func next_card(state: MatchState) -> int          # instance id or -1
static func effective(card: int, state: MatchState, cards: CardDb) -> Vector2i  # (flat, bonus)
static func step(state: MatchState, cards: CardDb, rng: MatchRng, sink: Callable, policy: PreviewPolicy) -> bool  # true when paused on a prompt

# Choice
enum Zone { OWN_HAND, OWN_BOARD, OPPONENT_HAND, OPPONENT_BOARD }
static func eligible(state: MatchState, seat: int, verb: int, source: int) -> Dictionary  # {zone, options}
static func resolve(state: MatchState, seat: int, zone: int, index: int) -> int           # instance id or -1

# GreedyBot
func choose(view: SeatView, engine: MatchEngine) -> EngineAction   # commit or choose, by phase
```

`choose()` now takes the engine for `preview()`; the bot still reads only its own view and
calls preview for its own seat, so hidden information stays hidden (the preview treats
the opponent's pending as absent and the engine never returns it).

### Events (new or changed; redaction in brackets)

| Kind | Payload |
|---|---|
| `TURN_STARTED` | `round`, `turn`, `budgets: [int, int]`, `free_first: [bool, bool]`, `first_seat` |
| `COMMITTED` | `seat`, `count`, `cards` [hidden], `slots` |
| `WALK_STARTED` | `round`, `turn`, `first_seat` |
| `CARD_REVEALED` | `seat`, `card`, `def_id`, `slot`, `flat`, `bonus` |
| `CARD_SCORED` | `seat`, `card`, `slot`, `flat`, `bonus`, `mult`, `added`, `score` |
| `EFFECT_FIRED` | `seat`, `card`, `verb`, `trigger` |
| `EFFECT_FIZZLED` | `seat`, `card`, `verb` |
| `CHOICE_REQUESTED` | `seat`, `card`, `verb`, `text`, `zone`, `options: Array[int]` |
| `CHOICE_MADE` | `seat`, `card`, `zone`, `index`, `target` [hidden when the zone is a hand], `auto: bool` |
| `STATS_CHANGED` | `seat`, `card`, `flat`, `bonus`, `cause` (`switch`, `flat_up`, `bonus_zero`) |
| `CARD_DESTROYED` | `seat`, `card`, `slot` |
| `CARD_MOVED` | `seat`, `card`, `from_slot`, `to_slot` (two per swap) |
| `CARD_RETURNED` | `seat`, `card`, `slot` (public; the card was revealed) |
| `CARD_DISCARDED` | `seat`, `card` [hidden] |
| `BONUS_ZERO_SET` | `seat` (the opponent who will suffer it) |
| `ENERGY_CARRIED` | `seat`, `amount` |
| `FREE_FIRST_SET` | `seat` |
| `TURN_ENDED` | unchanged |

`CARD_DEALT`, `CARD_DRAWN`, `CARD_BURNED`, `ROUND_*`, `CONCEDED`, `MATCH_ENDED` are
unchanged.

### Error codes (appended)

`BAD_SLOTS` (R6), `NO_PROMPT` (a choose with no prompt open), `NOT_ELIGIBLE` (R31).
`WRONG_SEAT` covers a choose from the wrong seat. `OVER_BUDGET` now checks the seat's
budget with the free first card (R10).

## Data model

### Card table (C14), `engine/data/cards.json` format 2

| id | cost | flat | bonus | effect (trigger: verb, amount) | text |
|---|---|---|---|---|---|
| c01 | 1 | 1 | 0 | on_reveal: draw, 1 | Draw a card. |
| c02 | 1 | 2 | 0 | – | |
| c03 | 1 | 1 | 1 | – | |
| c04 | 1 | 3 | 0 | – | |
| c05 | 2 | 1 | 0 | ongoing: carry_energy | Your unspent energy carries to your next turn. |
| c06 | 2 | 1 | 0 | on_score: flat_up, 1 | Each time this scores, it gains +1 flat. |
| c07 | 2 | 2 | 1 | – | |
| c08 | 2 | 4 | 0 | – | |
| c09 | 3 | 3 | 0 | on_reveal: draw_then_discard, 2 | Draw 2 cards, then discard 1. |
| c10 | 3 | 3 | 0 | on_reveal: free_first_next_turn | The first card you play next turn costs 0. |
| c11 | 3 | 3 | 1 | – | |
| c12 | 4 | 4 | 0 | on_reveal: swap_places | Swap places with a card on your board. |
| c13 | 4 | 2 | 2 | on_reveal: switch_stats | Switch a card's flat and bonus. |
| c14 | 4 | 6 | 0 | – | |
| c15 | 5 | 5 | 0 | on_reveal: opponent_next_bonus_zero | Your opponent's next revealed card has 0 bonus. |
| c16 | 5 | 5 | 1 | – | |
| c17 | 6 | 6 | 0 | on_reveal: return_at_turn_end | Return another card to its owner's hand at the end of this turn. |
| c18 | 6 | 8 | 0 | – | |
| c19 | 7 | 7 | 0 | on_reveal: destroy_random_opponent | Destroy a random card on your opponent's board. |
| c20 | 7 | 7 | 2 | – | |

Names stay `Placeholder NN`. Entry shape:
`{"id","name","cost","flat","bonus","effect": {"trigger","verb","amount","text"} | null}`;
`"version": 2`. Instance ids stay `seat * 20 + index`.

### `MatchState` additions (all in `to_dict()`)

| Field | Type | Notes |
|---|---|---|
| `seats[s].board` | `Array[int]` | now the ordered row (slot = index) |
| `seats[s].revealed` | `Dictionary[int, bool]` | cards on the row that have been revealed |
| `pending_slots` | `Array[int]` | with `pending` |
| `card_states` | `Dictionary[int, CardState]` | `flat_delta`, `switched`, `bonus_zero`, `return_marked`; cleared at round start and when the card leaves the board |
| `bonus_zero_pending` | `[bool, bool]` | per seat that will suffer it (R22) |
| `energy` | `{carry, free_first, spent}` | P7 |
| `walk` | `{active, next_seat, pulsed, mult}` | P3 |
| `prompt` | Dictionary | P9; empty when none |
| `phase` | enum | adds `AWAIT_CHOICE` |

`SeatView` adds: `own_row`, `opponent_row` (ordered, with `revealed` flags and shown
flat and bonus per card from `effective()`), `opponent_pending_slots`, `budgets`,
`free_first` (own only), `prompt` (zone and options when this seat is prompted; the
opponent sees only that a prompt is open), `mults`.

### Action log, format 2

```json
{"format": 2, "rules": 2, "seed": "1",
 "actions": [{"k":"commit","s":0,"c":[3,7],"p":[0,1]}, {"k":"choose","s":0,"z":1,"i":2}, {"k":"concede","s":1}]}
```

## Board design

- Faces per P20; `show_def` sets name, cost, flat, bonus, text; `show_stats` updates and
  pulses; the back is unchanged.
- Step kinds added to `BoardStep.Kind`: `WALK_START`, `PULSE`, `EFFECT`, `FIZZLE`,
  `PROMPT`, `CHOICE_SHOW`, `STATS`, `DESTROY`, `MOVE`, `RETURN`, `DISCARD`. `REVEAL` is
  folded into `PULSE` (`revealed = false` means flip first). `OPPONENT_COMMIT` and
  `PLAYER_COMMIT` carry `slots`.
- `MatchDriver` gains `submit_choice(zone, index)` and `open_prompt()`; `play_bot()`
  answers prompts as well as commits.
- The runner (`_advance`) stops on a `PROMPT` step for seat 0 and resumes when the choice
  is accepted (the accepted result's events enqueue after it). `may_act()` is false
  during a prompt except for the tap paths `PromptRules` allows.
- Under autoplay the seat-0 bot answers prompts; the `PROMPT` step is skipped (no banner)
  and `CHOICE_SHOW` still glows.
- HUD: `set_scores(scores, mults, walking)`, `set_budget(left, total, free_first)`,
  `show_prompt(text)` / `hide_prompt()`.
- Verification scene `board/verify/board_seed1.tscn` is unchanged; the orchestrator picks
  the first seed-1 turn in which a prompt opens for the screenshot (T14 notes the turn).

## Constitution Check

| Rule | Verdict | Note |
|---|---|---|
| All project GDScript is fully typed (`parse` promotes warnings to errors) | PASS | Typed-strict checklist in every brief; dictionaries typed where keys are fixed |
| Engine is deterministic: seeded RNG, no wall-clock, no node access, serializable action log (D4) | PASS | One stream; random destroy via `pick_index`; preview never touches the stream; walk and prompt live in `MatchState` and `to_dict()`; choices logged |
| `make check` gate contract | PASS | New suites; boot grep unchanged; golden re-pinned at T14 by the orchestrator |
| Implementers never run Godot or `make check` | PASS | Golden left as a skip until T14, as DC-01 did |
| P5 frontmatter and vault-root links | PASS | Three notes, fresh uids |
| Do-not-touch list | PASS | No addon change planned; if `drag_controller.gd` needs one for R44, it goes through a recorded patch |
| Secrets only in `.env` | PASS | None involved |
| One branch per cycle (`cycle-4-card-effects`), one commit per task, `--no-ff` into `master` (ADR 0002) | PASS | See tasks |
| D2 Compatibility-clean visuals | PASS | DC-04 unshaded materials and Label3D only |
| D1 Card3D in-house extras | PASS | Slots, flip, pulses and prompts are project code |

**Result:** PASS.

## Risks and mitigations

- **`match_engine.gd` grows past readability** → the walk, effects, choices and preview
  are their own modules (layout table); the engine keeps flow only.
- **Effects that change the row mid-walk** (swap, destroy) → the `pulsed` set (P5) and
  `test_score_walk` cases for swap-ahead, swap-behind and destroy-ahead.
- **Preview drifts from the live walk** → both run `ScoreWalk.step` with a policy; a
  suite case runs preview and live on the same state with no prompt or random and
  asserts equal scores.
- **Bot decision time** (≤ 512 previews × a walk of ≤ 16 cards) → measured in the 50-seed
  sweep; if the test stage passes 15 s, drop the flat-first order (P13) and note it.
- **Golden line and boot grep both change** → T14 re-pins `test_full_match.gd`, the
  `scripts/check.sh` expectation and the cycles log in one commit.
- **Hidden-information leaks through prompts** (options in a hand zone, `target` in
  `CHOICE_MADE`) → `test_seat_view` scans every redacted prompt and choice event in the
  sweep.
- **Energy carry with a destroyed or returned carry card** → carry is computed at turn
  end from the row as it stands then (P7); a case covers each.
- **`board.gd` touched by four tasks** → waves keep one writer at a time (tasks).
- **Face text size at the DC-04 lift** → T09 picks the size against the longest text
  ("Return another card to its owner's hand at the end of this turn."); checked in
  screenshot 3.

## Open questions

- None. Ben's "and more after this" (C5) is expected as a later spec, not this cycle.
