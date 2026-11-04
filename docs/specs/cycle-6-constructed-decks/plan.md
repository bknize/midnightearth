---
type: plan
tags: [plan, cycle-6-constructed-decks, engine, board, ui]
status: approved
related: ["[[specs/cycle-6-constructed-decks/spec]]", "[[specs/cycle-6-constructed-decks/tasks]]", "[[specs/cycle-5-walk-cursor/plan]]", "[[specs/cycle-4-card-effects/plan]]", "[[planning/phase-1-tech-stack]]"]
created: 2026-11-04
updated: 2026-11-04
uid: fed830cd-fc7e-4843-be80-a86d6fefb0d0
linear:
supersedes:
---

# Plan: Cycle 6 — constructed decks

Implements [[specs/cycle-6-constructed-decks/spec|spec]]. The engine half turns the card
file into a pool plus a deck list, resolves every instance through its origin deck,
re-does the pulse math in hundredths, adds destroyed piles, a set-valued choice, two
triggers and eighteen verbs, and retires one. The board half follows the new events and
adds the picker, the multi-select prompt and the recover strip. Log format goes to 3,
rules version to 4.

## Stack mapping

| Area | Involved | Approach and tooling |
|---|---|---|
| Engine (godot/engine + tests) | yes | Typed `RefCounted` modules, one seeded stream, replayable log (D4); new and amended suites; `implementer-engine` for everything under `godot/engine/` |
| Godot scenes/UI | yes | New `godot/picker/` scene (Control, plain Theme, D7); `board/*` follows the events; Card3D layouts for the recover strip (D1); verified through the Godot MCP |
| Shaders/cards | no | Faces stay Label3D text; glows and dimmer are the DC-04 materials |
| Input | no | Pointer shim unchanged; new prompt taps route through `PromptRules` |
| Tooling/scripts | minimal | `scripts/check.sh` boot grep unchanged (`Main ready` prints after the picker); the golden literal re-pinned at verification |
| Vault/docs | yes | This set, the specs MOC row, the cycles row and Phase 3 amendments at `/cycle test` |
| Linear | yes | Project "Cycle 6 — constructed decks", milestone `DC-07 constructed-decks`, labels `area/engine`, `area/cards`, `area/ui`, `type/feature`, `spec/cycle-6-constructed-decks` (filled by `/exercise`) |

## Module layout

| File (under `godot/`) | class_name | Responsibility | Suite |
|---|---|---|---|
| `engine/data/cards.json` | – | Format 3 pool: the Ruin and Drift tables below | `test_card_db.gd`, `test_decks.gd` |
| `engine/data/decks.json` | – | The deck list: `ruin`, `drift` | `test_deck_list.gd` |
| `tests/fixtures/dc05_cards.json`, `tests/fixtures/dc05_decks.json` | – | The 20 DC-05 cards in format 3 (P1) and a one-deck list `fixture`; loaded only by suites | the suites that use them |
| `engine/card_def.gd` | `CardDef` | adds `bonus_kind: BonusKind`, `bonus: int` (P1) | `test_card_db.gd` |
| `engine/card_effect.gd` | `CardEffect` | triggers + `ON_OPPONENT_SCORE`, `ON_MOVED`; verbs per P8; `SWITCH_STATS` removed | `test_card_db.gd` |
| `engine/card_db.gd` | `CardDb` | Format 3 parse and the R3 pool checks; no count or cost-mix check | `test_card_db.gd` |
| `engine/deck_list.gd` (new) | `DeckList` | Loads `decks.json`, validates against a `CardDb`, `seeded_pick()` (P2) | `test_deck_list.gd` |
| `engine/match_cards.gd` (new) | `MatchCards` | The 40 definitions of one match indexed by instance id (P3); replaces `CardDb` in every engine call that took it | `test_match_cards.gd` |
| `engine/match_rules.gd` | `MatchRules` | `RULES_VERSION 4`, `LOG_FORMAT 3`, `MULT_ONE 100`, `TIMES_VALUES`, `PLUS_VALUES`, `MAX_FLAT_OVER_COST 4`, `BURST_FLAT 5` | – |
| `engine/card_state.gd` | `CardState` | `has_base`/`base_flat`/`base_kind`/`base_bonus` (the copy), `flat_delta`, `no_bonus`, `temp_plus`, `return_marked`, `destroyed` (P5) | `test_score_walk.gd` |
| `engine/match_state.gd` | `MatchState` | `deck_ids`, `SeatPiles.destroyed` + `destroyed_known`, `prompt.multi`, `controller_of()` (P3, P6, P7) | `test_turn.gd` |
| `engine/score_walk.gd` | `ScoreWalk` | `Effective` triple, hundredths pulse (P4), on-opponent-score hook (P10), temp_plus clear at walk end | `test_score_walk.gd` |
| `engine/effect_resolver.gd` | `EffectResolver` | The destroy pipeline (P9), moves (P11), the new verbs, recovery, the multi answer | `test_effects.gd`, `test_effects_ruin.gd`, `test_effects_drift.gd` |
| `engine/choice.gd` | `Choice` | zones + `BOTH_DESTROYED`; eligibility per P12; set validation | `test_choices.gd` |
| `engine/engine_action.gd` | `EngineAction` | `CHOOSE_SET` with `indices` (P7) | `test_engine_action.gd`, `test_action_log.gd` |
| `engine/engine_error.gd` | `EngineError` | appends `BAD_SET`, `DECK_UNKNOWN` | `test_turn.gd` |
| `engine/action_log.gd` | `ActionLog` | Format 3 header with `decks` (P2) | `test_action_log.gd` |
| `engine/match_engine.gd` | `MatchEngine` | `create(seed, cards, decks, deck_ids)`, deck resolution, round-end pile flush, the set choice path, previews | `test_turn.gd`, `test_round_match_end.gd`, `test_destroyed.gd` |
| `engine/preview_policy.gd` | `PreviewPolicy` | a nested multi prompt declines (empty set); random destroys pick the lowest flat as today | `test_greedy_bot.gd` |
| `engine/seat_view.gd` | `SeatView` | `deck_ids`, `own_destroyed`, `opponent_destroyed` (hidden entries), hundredths `mults`, row stats as `{flat, times, plus}` | `test_seat_view.gd` |
| `engine/match_event.gd` | `MatchEvent` | kinds below; redaction of `CARD_RECOVERED` and the destroyed piles | `test_seat_view.gd` |
| `engine/bot/greedy_bot.gd` | `GreedyBot` | ordering per P13, the k-lowest-flat set answer, `MatchCards` | `test_greedy_bot.gd` |
| `tests/test_full_match.gd` | – | Golden under the seed-1 pairing (skip until pinned), 50-seed sweep under seeded pairings, leak scan incl. piles, replay | itself |
| `picker/deck_picker.tscn`, `deck_picker.gd` (new) | `DeckPicker` | Two columns of tiles, Start, `picked(deck_ids)` signal (P15) | `test_deck_picker.gd` (pure pick state) |
| `main.gd`, `main.tscn` | – | Args, smoke under the seeded pairing, picker-or-board, `Main ready` | boot log |
| `board/match_driver.gd` | `MatchDriver` | `create(seed, cards, decks, deck_ids, autoplay)`, result line with decks | `test_match_driver.gd` |
| `board/board.gd`, `board_card.gd`, `board_hud.gd`, `board_steps.gd`, `board_step.gd`, `effect_player.gd`, `score_chips.gd`, `row_tally.gd`, `prompt_rules.gd`, `prompt_host.gd`, `lift_rules.gd` + scenes | – | Faces, chips, tally, pile counts, new steps, multi-select, recover strip, Decks buttons (P16) | `test_board_steps.gd`, `test_prompt_rules.gd`, `test_lift_rules.gd`, `test_score_chips.gd`, MCP |
| `board/deck_strip.gd` (new) | `DeckStrip` | A temporary Card3D line above the rows for off-screen collections (P16) | MCP |

## Design choices

| # | Choice | Why |
|---|---|---|
| P1 | **Pool format 3.** `{"version": 3, "cards": [{"id", "name", "cost", "flat", "bonus": null \| {"x": 125} \| {"plus": 1}, "effect": null \| {"trigger", "verb", "amount", "text"}}]}`. `CardDef.bonus_kind` ∈ {NONE, TIMES, PLUS}; `bonus` is hundredths for TIMES (125, 150, 200) and whole for PLUS (1, 2). The loader checks: unique ids, cost 1..7, flat 0..cost+4, bonus in `TIMES_VALUES`/`PLUS_VALUES`, known trigger and verb; no count, no cost mix. The DC-05 fixture is the same 20 cards converted (bonus 1 → ×1.25, bonus 2 → ×1.5, c13 vanilla flat 5, c15's verb renamed `opponent_next_no_bonus`) | R1, R3, R4, C5, C6, C13, C20 |
| P2 | **Deck list.** `decks.json`: `{"version": 1, "decks": [{"id": "ruin", "name": "Ruin", "theme": "…", "cards": [20 ids]}, …]}`. `DeckList.load_default()`, `validate(cards: CardDb)` (20, distinct, present), `deck(id)`, `ids()`, `seeded_pick(seed, seat) -> String` = `MatchRng.new(MatchRng.derive_seed(seed, [DECK_TAG, seat])).pick_index(size)` with `DECK_TAG = 0x646B`. The log header gains `"decks": ["ruin", "drift"]`; replay passes them to `create()`; a header without `decks` is a format mismatch | R2, R5–R7, C3, C15 |
| P3 | **Instances and origin.** Instance id stays `origin * 20 + index`, index into the origin's deck list. `MatchCards.build(cards, decks, deck_ids)` resolves 40 `CardDef`s once per match; `def_of(id)` is an array read. Every engine function that took `CardDb` takes `MatchCards`. The controller is implicit: `MatchState.controller_of(id)` finds which seat's piles hold it. Round start already rebuilds each deck from its 20 ids, so a stolen card returns to its origin for free | R8, R9, C12 |
| P4 | **Hundredths mult.** `WalkState.mult: Array[int]` starts at `MULT_ONE` (100). `ScoreWalk.effective(card) -> Effective {flat, times, plus}` (times a hundredths product, plus whole units). Pulse: `mult = (mult * times + 50) / 100` (integer, rounds to nearest), `mult += plus * 100`, `added = flat * mult / 100` (floor), `score += added`. `CARD_SCORED` carries `flat`, `times`, `plus`, `mult`, `added`, `score`, `again`. Integer only, so macOS and iOS agree | R10–R12, C2 |
| P5 | **Effective stats.** Base = printed, or `base_*` after a copy. `flat = base_flat + flat_delta`. `times = base times (100 when the base is not TIMES) × 125 per adjacent revealed live Lodestone × 150 when this card carries Herald's edge effect and sits at slot 0`, each step `(a * b + 50) / 100`. `plus = base plus (0 when not PLUS) + temp_plus`. If `no_bonus`: `times = 100`, `plus = 0`. `temp_plus` is cleared for every card when the walk ends; `no_bonus` and `flat_delta` live until the card leaves the board or is un-revealed (P9) | R13, R14, R33, R34 |
| P6 | **Destroyed piles.** `SeatPiles.destroyed: Array[int]` and `destroyed_known: Dictionary[int, bool]` (public identity). `clear_destroyed` appends to the owner's pile (`DESTROYED_CLEARED` gains `pile: true`). `_end_round` moves each pile into `burned` before the clear. `SeatView.own_destroyed` lists ids; `opponent_destroyed` lists ids where `destroyed_known`, else `HIDDEN_CARD`, in pile order | R16–R18 |
| P7 | **Set choice.** `EngineAction.Kind.CHOOSE_SET {seat, zone, indices}`; dict `{"k": "choose_set", "s": 0, "z": 1, "i": [0, 2]}`. `MatchState.prompt.multi: bool`; `CHOICE_REQUESTED` carries `multi`. `_check_set`: a multi prompt open (`NO_PROMPT`), the prompted seat (`WRONG_SEAT`), every index offered and no repeat (`BAD_SET`). `CHOICE_MADE` carries `indices` for a set. Phase stays `AWAIT_CHOICE`. A single-target prompt rejects `CHOOSE_SET` and a multi prompt rejects `CHOOSE` (`NOT_ELIGIBLE`) | R22–R25, C8 |
| P8 | **Triggers and verbs.** Triggers add `ON_OPPONENT_SCORE`, `ON_MOVED`. Verbs: Ruin `discard_own` (amount), `destroy_leftmost_own`, `destroy_own_then_draw` (amount), `destroy_own_then_flat_up`, `sacrifice_destroy` (multi), `burst` (on_opponent_score), `unreveal_instead` (ongoing), `recover_destroyed`, `draw` (on_opponent_reveal, existing verb), `destroy_random_opponent` (existing). Drift `move_self_left`, `move_self_right`, `copy_stats`, `neighbour_times` (ongoing, amount 125), `edge_left_times` (ongoing, amount 150), `move_opponent_left`, `shift_own_left`, `reverse_opponent_row`, `swap_opponent_right`, `plus_on_moved` (on_moved, amount 2), `swap_places` (existing). Removed: `switch_stats`. Kept for the fixture: `draw_then_discard`, `free_first_next_turn`, `opponent_next_no_bonus`, `return_at_turn_end`, `flat_up`, `carry_energy` | R26–R28, C7, C10, C11, C20 |
| P9 | **One destroy pipeline.** `EffectResolver.destroy(state, cards, card, outcome) -> bool`: if the card is revealed, live and carries `unreveal_instead`, it un-reveals (`revealed.erase`, `clear_card_state`, `CARD_UNREVEALED {seat, card, slot}`, the card stays in its slot); else it is marked destroyed in place (DC-06 R12) with `CARD_DESTROYED`. Returns true in both cases, so a sacrifice counts it. Every destroy this cycle, random or chosen, own or opponent, goes through it | R30–R32, C9, C18 |
| P10 | **Burst.** After every `CARD_SCORED`, for each revealed live card of the other seat carrying `burst` (snapshot in row order, resumable like the watchers): `flat_delta += 1`, `STATS_CHANGED cause "opponent_score"`, then `_check_burst`. `_check_burst(card)` also runs after any other stat change on a revealed burst card (a copy); when `effective(card).flat >= BURST_FLAT` it destroys the card through P9 and then a random live opponent card through P9 | R26, R27, C10 |
| P11 | **Moves.** One `_place(state, seat, card, to_slot)` and one `_rewrite_row(state, seat, new_order)`; each emits a `CARD_MOVED {seat, card, from_slot, to_slot}` per card whose slot changed, then fires `ON_MOVED` once per moved card that is revealed and live (snapshot after the rewrite). The slot cursor of DC-06 does the rest. Reverse: `row.reverse()`; shift: rotate left by one over the other cards (the source keeps its slot); move_opponent_left: remove and insert at 0; swap_opponent_right: swap i and i+1; self moves: to 0 or to size-1. `plus_on_moved` adds `temp_plus += amount` | R28, R29, R33, C11 |
| P12 | **Eligibility.** `discard_own`: OWN_HAND, all. `destroy_own_then_*`: OWN_BOARD, live, source excluded. `sacrifice_destroy`: OWN_BOARD, live, source excluded, multi. `copy_stats`: OPPONENT_BOARD, revealed and live. `move_opponent_left`: OPPONENT_BOARD, all but slot 0 (face-down included, by position). `swap_opponent_right`: OPPONENT_BOARD, all but the rightmost. `recover_destroyed`: BOTH_DESTROYED (own pile in order, then the opponent's), all. `swap_places` as DC-06 R16. Zero eligible fizzles (multi too); one eligible auto-chooses except multi (R25) | R19, R22, R25, R27, R28 |
| P13 | **Bot.** `_bonus_before`: plus desc, times desc, flat desc, id asc; `_flat_before` unchanged. Multi answer: for k in 0..n, the k eligible cards with the lowest effective flat (ties by position) → `preview_set(seat, indices)`; best own-minus-opponent, ties by seed. `preview_set` mirrors `preview_choice`. No new order, no width change | R36–R38, C14 |
| P14 | **Seeded pairing and flags.** `main.gd` parses `--seed=`, `--autoplay`, `--deck=`, `--bot-deck=`; an empty deck id resolves to `DeckList.seeded_pick`. The smoke runs seed 1 under its pairing and prints `Engine smoke: seed=1 decks=<a>/<b> winner=…`. The `Board: match ended …` line gains `decks=<a>/<b>` after `seed=`. An unknown id: `push_error` and no board (`Main ready` not printed, so the gate fails loudly) | R6, R42, R53, C15 |
| P15 | **Picker.** `DeckPicker` (Control, plain Theme): `setup(decks: DeckList, preselected: Array[String])`, two `VBoxContainer` columns of tile `Button`s (name + theme), Start enabled when both picked, signal `picked(deck_ids: Array[String])`. `main.gd` shows it when no deck flag and no autoplay; on `picked` it frees the picker, instances the board and calls `board.start_match(seed, deck_ids)`. The board's `decks_requested` signal (pause and result "Decks" buttons) tears the board down and shows the picker again with the current picks preselected; Rematch keeps `deck_ids`. Pure pick state lives in `DeckPickState` (RefCounted) so a suite covers "Start only when both picked" | R39–R43, C16 |
| P16 | **Board.** Faces: `BonusLabel` text `"×1.25"` / `"+1"` from `{times, plus}`; chips `"×%.2f"`; tally `"×%.2f"`; HUD `set_destroyed(counts)`. Steps: `UNREVEAL` (flip down, 0.35), `MOVE` extended to many cards (one re-layout, 0.3), `RECOVER` (strip card flies to a hand, 0.3), `STRIP_SHOW` / `STRIP_HIDE` (0.25), `CLEAR_DESTROYED` then a pile-count update. `DeckStrip`: a Card3D line collection above the rows, built from the prompt's zone (own pile face up, opponent's hidden entries as backs), eligible glows, DC-06 reader with `"Recover"`. Multi-select: `PromptHost.selected: Array[int]`; `PromptRules.on_tap` adds `TOGGLE_SELECT`; a selected card is raised 0.03 and uses the brighter glow; `BoardHud.show_confirm("Destroy %d")` → `submit_set`. `LiftRules.step_touches` covers the new kinds. Autoplay divides every new duration | R44–R52, C19 |

## Interfaces and contracts

```gdscript
# DeckList
static func load_default() -> DeckList
func validate(cards: CardDb) -> String                       # "" when valid
func ids() -> Array[String]
func deck(id: String) -> Dictionary                          # {id, name, theme, cards}
func seeded_pick(match_seed: int, seat: int) -> String

# MatchCards
static func build(cards: CardDb, decks: DeckList, deck_ids: Array[String]) -> MatchCards
func def_of(instance: int) -> CardDef                        # null when out of range

# MatchEngine
static func create(match_seed: int, cards: CardDb, decks: DeckList, deck_ids: Array[String]) -> MatchEngine
func deck_ids() -> Array[String]
func preview_set(seat: int, indices: Array[int]) -> Array[int]

# EngineAction
enum Kind { COMMIT, CONCEDE, CHOOSE, CHOOSE_SET }
static func choose_set(seat: int, zone: int, indices: Array[int]) -> EngineAction
# dict: {"k":"choose_set","s":0,"z":1,"i":[0,2]}

# ScoreWalk
class Effective: var flat: int; var times: int; var plus: int
static func effective(card: int, state: MatchState, cards: MatchCards) -> Effective

# EffectResolver
static func destroy(state: MatchState, cards: MatchCards, card: int, outcome: Outcome) -> bool

# Choice
enum Zone { OWN_HAND, OWN_BOARD, OPPONENT_HAND, OPPONENT_BOARD, BOTH_BOARDS, BOTH_DESTROYED }

# GreedyBot
func _init(bot_seed: int, cards: MatchCards)

# MatchDriver
static func create(p_seed: int, cards: CardDb, decks: DeckList, deck_ids: Array[String], p_autoplay: bool) -> MatchDriver
func submit_set(zone: int, indices: Array[int]) -> ApplyResult

# DeckPicker (scene)
signal picked(deck_ids: Array[String])
func setup(decks: DeckList, preselected: Array[String]) -> void

# Board
signal decks_requested
func start_match(new_seed: int, deck_ids: Array[String]) -> void
```

### Events (new or changed; redaction in brackets)

| Kind | Payload |
|---|---|
| `MATCH_STARTED` (new) | `seed`, `decks: [a, b]` |
| `CARD_SCORED` | `seat`, `card`, `slot`, `flat`, `times`, `plus`, `mult` (hundredths), `added`, `score`, `again` |
| `CHOICE_REQUESTED` | + `multi: bool`; zone may be `both_destroyed` |
| `CHOICE_MADE` | + `indices: Array[int]` when `multi` (`index` is -1 then) |
| `CARD_UNREVEALED` (new) | `seat`, `card`, `slot` (public: the card was revealed) |
| `CARD_RECOVERED` (new) | `seat` (new controller), `card` [hidden from the other seat unless `destroyed_known`], `from_seat`, `position` |
| `CARD_MOVED` | unchanged, one per card whose slot changed |
| `DESTROYED_CLEARED` | + `pile: true` |
| `STATS_CHANGED` | `cause` adds `opponent_score`, `copy`, `temp_plus`, `unreveal` |
| `EFFECT_FIRED` | `trigger` adds `on_opponent_score`, `on_moved` |

### Error codes (appended)

`BAD_SET` (repeat or non-offered index in a set, or a set for a single prompt),
`DECK_UNKNOWN` (`create()` with an id not in the list; `start()` fails with it).

## Data model

### Ruin (`ruin`, "Burn your own cards for bodies above the curve and random enemy destroys.")

| id | name | cost | flat | bonus | effect (trigger: verb, amount) | text |
|---|---|---|---|---|---|---|
| r01 | Scrap | 1 | 2 | – | – | |
| r02 | Tinder | 1 | 1 | ×1.25 | – | |
| r03 | Ember | 1 | 4 | – | on_reveal: discard_own, 1 | Discard a card from your hand. |
| r04 | Shard | 1 | 0 | ×1.5 | – | |
| r05 | Tallow | 1 | 5 | – | on_reveal: destroy_leftmost_own | Destroy your leftmost other card. |
| r06 | Fuse | 2 | 1 | – | on_opponent_score: burst | Whenever an enemy card scores, +1 flat. At 5 flat, destroy this and a random enemy card. |
| r07 | Rat | 2 | 1 | – | on_opponent_reveal: draw, 1 | Whenever an enemy card reveals, draw a card. |
| r08 | Grave Robber | 2 | 2 | – | on_reveal: recover_destroyed | Put a destroyed card into your hand. |
| r09 | Wick | 2 | 3 | ×1.25 | – | |
| r10 | Butcher | 3 | 3 | – | on_reveal: destroy_own_then_draw, 2 | Destroy another card of yours: draw 2. |
| r11 | Cinder | 3 | 7 | – | on_reveal: discard_own, 1 | Discard a card from your hand. |
| r12 | Pyre | 3 | 2 | ×1.5 | – | |
| r13 | Phoenix | 4 | 3 | ×1.25 | ongoing: unreveal_instead | If this card would be destroyed, un-reveal it instead. |
| r14 | Glutton | 4 | 2 | – | on_reveal: destroy_own_then_flat_up | Destroy another card of yours: gain its flat. |
| r15 | Wreck | 4 | 5 | ×1.25 | – | |
| r16 | Immolator | 5 | 4 | – | on_reveal: sacrifice_destroy | Destroy any number of your cards: destroy that many enemy cards at random. |
| r17 | Bonfire | 5 | 5 | ×1.5 | – | |
| r18 | Reaper | 6 | 6 | – | on_reveal: destroy_random_opponent | Destroy a random enemy card. |
| r19 | Ashen King | 6 | 4 | +1 | – | |
| r20 | Cataclysm | 7 | 11 | – | on_reveal: destroy_leftmost_own | Destroy your leftmost other card. |

Curve 5-4-3-3-2-2-1; 12 effect cards, 8 vanilla; ×1.25 on four, ×1.5 on three, +1 on one.
Ruin leans flat by design: its mult comes from sacrificing fodder for over-curve bodies.

### Drift (`drift`, "Positional bonuses and moving cards on both rows.")

| id | name | cost | flat | bonus | effect (trigger: verb, amount) | text |
|---|---|---|---|---|---|---|
| d01 | Gust | 1 | 2 | – | – | |
| d02 | Sprite | 1 | 1 | ×1.25 | – | |
| d03 | Scout | 1 | 1 | ×1.25 | on_reveal: move_self_left | Move to the far left of your row. |
| d04 | Pebble | 1 | 3 | – | – | |
| d05 | Eddy | 2 | 1 | – | on_moved: plus_on_moved, 2 | When this card is moved, +2 until the walk ends. |
| d06 | Courier | 2 | 2 | ×1.25 | on_reveal: move_self_right | Move to the far right of your row. |
| d07 | Mirror | 2 | 0 | – | on_reveal: copy_stats | Copy an enemy card's current flat and bonus. |
| d08 | Tide | 2 | 3 | ×1.25 | – | |
| d09 | Shepherd | 3 | 3 | – | on_reveal: swap_places | Swap places with a card on your row. |
| d10 | Lodestone | 3 | 2 | – | ongoing: neighbour_times, 125 | The cards on either side of this one get ×1.25. |
| d11 | Current | 3 | 4 | ×1.25 | – | |
| d12 | Herald | 4 | 3 | – | ongoing: edge_left_times, 150 | While this card is on the far left of your row, it has ×1.5. |
| d13 | Hook | 4 | 4 | – | on_reveal: move_opponent_left | Move an enemy card to the far left of its row. |
| d14 | Keel | 4 | 5 | ×1.25 | – | |
| d15 | Undertow | 5 | 4 | – | on_reveal: shift_own_left | Move each of your other cards one slot left; the leftmost goes to the far right. |
| d16 | Beacon | 5 | 5 | ×1.5 | – | |
| d17 | Tempest | 6 | 5 | – | on_reveal: reverse_opponent_row | Reverse the order of the enemy row. |
| d18 | Vane | 6 | 3 | +1 | – | |
| d19 | Maelstrom | 7 | 6 | – | on_reveal: swap_opponent_right | Swap an enemy card with the card to its right. |
| d20 | Horizon | 7 | 7 | ×2 | – | |

Curve 4-4-3-3-2-2-2; 11 effect cards, 9 vanilla; ×1.25 on six, ×1.5 on one, ×2 on one,
+1 on one.

### `MatchState` additions (all in `to_dict()`)

| Field | Type | Notes |
|---|---|---|
| `deck_ids` | `Array[String]` | per seat |
| `seats[s].destroyed` | `Array[int]` | the pile, in arrival order |
| `seats[s].destroyed_known` | `Dictionary[int, bool]` | identity public |
| `walk.mult` | `Array[int]` | hundredths, 100 at walk start |
| `prompt.multi` | `bool` | set prompt |
| `card_states[id]` | `CardState` | P5 fields |

### Action log, format 3

```json
{"format": 3, "rules": 4, "seed": "1", "decks": ["ruin", "drift"],
 "actions": [{"k":"commit","s":0,"c":[3,7],"p":[0,1]}, {"k":"choose","s":0,"z":1,"i":2},
             {"k":"choose_set","s":1,"z":1,"i":[0,2]}, {"k":"concede","s":1}]}
```

## Constitution Check

| Rule | Verdict | Note |
|---|---|---|
| All project GDScript is fully typed (`parse` promotes warnings to errors) | PASS | Typed-strict checklist in every brief; `Effective` is a class, not a Dictionary |
| Engine is deterministic: seeded RNG, no wall-clock, no node access, serializable action log (D4) | PASS | Integer hundredths (P4); deck pairing from `derive_seed` (P2); every random pick via `pick_index`; previews never touch the stream; decks in the log header |
| `make check` gate contract | PASS | Boot still prints `Engine smoke:` and `Main ready` (the picker is in the tree); golden re-pinned at verification; new suites per module |
| Implementers never run Godot or `make check` | PASS | Golden left as a skip with the literals to pin |
| P5 frontmatter and vault-root links | PASS | Three notes, fresh uids |
| Do-not-touch list | PASS | No addon change; the strip uses Card3D's line layout as the rows do |
| Secrets only in `.env` | PASS | None involved |
| One branch per cycle (`cycle-6-constructed-decks`), one commit per task, `--no-ff` into `master` (ADR 0002) | PASS | See tasks |
| D2 Compatibility-clean visuals | PASS | Label3D text and DC-04 materials only |
| D7 plain Theme for UI | PASS | The picker is Control nodes with `board_theme.tres` |

**Result:** PASS.

## Risks and mitigations

- **The `CardDb` → `MatchCards` rename touches every engine module** → T02 does only that
  plus the deck plumbing, before any rule changes, so the diff is mechanical and the
  suites pin behaviour unchanged.
- **Rounding drift between live and preview** → both use `ScoreWalk` with the same
  integer formulas; a suite case runs the same state through both and asserts equality
  (as DC-05 did).
- **Un-reveal mid-walk interacting with the cursor** → P9 keeps the slot; DC-06 R5–R8
  decide reveal-again; `test_effects_ruin` covers un-reveal ahead of and behind the cursor
  and during the pulse of its own slot (it reveals in full again when reached).
- **Burst firing inside another card's score stage** → the hook runs after `CARD_SCORED`
  and before the next pulse, resumable like the watchers, so a prompt cannot sit inside
  it (burst prompts nothing).
- **The sacrifice destroying the burst card or Phoenix** → all through P9; cases for each.
- **Stolen cards and hidden information** → `CARD_RECOVERED` redaction (events table);
  the leak scan in the sweep covers piles and recoveries; a recovered unrevealed card's
  identity reaches only its new controller.
- **Bot time with multi previews** → at most n+1 previews per sacrifice prompt (n ≤ 7);
  measured per pairing at verification; NSC-74 stays open.
- **`board.gd` touched by three tasks** → waves keep one writer at a time.
- **Picker in the boot path** → `Main ready` prints once the picker (or the board, under
  flags) is in the tree; the headless autoplay run passes `--autoplay` and never sees
  the picker.
- **Table balance is untested design** → Ben reviews the tables at sign-off (C7); numbers
  are data, so a rebalance after the sweep is a JSON edit and a golden re-pin.

## Open questions

- None. Cycle 7 (ramp, bounce, Crew, the board-wide un-reveal one-shot, the cost
  reduction) and cycle 8 (bot tuning) are recorded in the spec's open items.
