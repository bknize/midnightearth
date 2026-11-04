---
type: plan
tags: [plan, cycle-5-walk-cursor, engine, board]
status: approved
related: ["[[specs/cycle-5-walk-cursor/spec]]", "[[specs/cycle-5-walk-cursor/tasks]]", "[[specs/cycle-4-card-effects/plan]]", "[[planning/phase-1-tech-stack]]"]
created: 2026-11-04
updated: 2026-11-04
uid: 22f3d35a-fbfd-44ef-9184-5bb6cf88239c
linear: https://linear.app/night-science-llc/project/cycle-5-the-walk-cursor-a06cd75587c4
supersedes:
---

# Plan: Cycle 5 — the walk cursor

Implements [[specs/cycle-5-walk-cursor/spec|spec]]. The engine half replaces the `pulsed`
set with a slot cursor per row and turns destroy into a card state; the board half follows
the new pulses, draws the destroyed look and replaces the live HUD number with chips, a row
tally and a turn-end count, and puts the reader view with an action button between a
prompt's tap and its choice. Rules version goes to 3; the log format stays 2. Everything
builds on the DC-05 modules ([[specs/cycle-4-card-effects/plan]]); no new engine module.

## Stack mapping

| Area | Involved | Approach and tooling |
|---|---|---|
| Engine (godot/engine + tests) | yes | Typed `RefCounted` modules, one seeded stream, replayable log (D4); the DC-05 suites gain cases; `implementer-engine` |
| Godot scenes/UI | yes | `board/*` follows the new events; plain Theme (D7); Card3D layouts and tweens (D1); chips and tally are `Label3D` nodes; verified on `board/verify/board_seed1.tscn` through the Godot MCP |
| Shaders/cards | minimal | The crack placeholder is an unshaded `StandardMaterial3D` on a quad with a generated line texture, or `ImmediateMesh` lines; no `SCREEN_TEXTURE`, mediump-safe (D2). No shader file unless the implementer finds the quad unreadable, then one Compatibility-clean spatial shader |
| Input | minimal | The prompt reader reuses the existing `tapped` signal and Escape path; played cards stay undraggable |
| Tooling/scripts | minimal | `scripts/check.sh` keeps its boot grep; the golden it expects is re-pinned at T09 |
| Vault/docs | yes | This set, the specs MOC row, the DC-06 row in [[planning/cycles]] at `/cycle test` |
| Linear | yes | Project "Cycle 5 — the walk cursor", milestone `DC-06 walk-cursor`, labels `area/engine`, `area/cards`, `area/ui`, `type/feature`, `spec/cycle-5-walk-cursor` (filled by `/exercise`); NSC-73 closes at `/cycle test`, NSC-74 gets the new measurement as a comment |

## Module layout (changed files)

| File (under `godot/`) | Change | Suite |
|---|---|---|
| `engine/match_rules.gd` | `RULES_VERSION := 3` | `test_action_log.gd` |
| `engine/match_state.gd` | `WalkState.cursor: Array[int]` replaces `pulsed`; `is_destroyed()`, `destroyed_ids()`; `take_from_row` unchanged for returns and the turn-end clear | `test_score_walk.gd` |
| `engine/card_state.gd` | `destroyed: bool` (in `is_default`, `copy`, `to_dict`) | `test_score_walk.gd` |
| `engine/score_walk.gd` | Cursor rules P1–P3; destroyed pulses P4; the pulse owner P2 | `test_score_walk.gd` |
| `engine/effect_resolver.gd` | `_destroy_random` marks instead of removing (P4, P5); `clear_destroyed()` at turn end (P6); watchers skip destroyed; `_carrier` skips destroyed | `test_effects.gd` |
| `engine/choice.gd` | Eligibility per P5: swap keeps destroyed cards, switch and return skip them | `test_choices.gd` |
| `engine/match_engine.gd` | `_end_turn` order P6; `_hide_opponent` marks inert instead of erasing (P7) | `test_turn.gd`, `test_greedy_bot.gd` |
| `engine/preview_policy.gd` | `destroy_slot` picks among live cards | `test_greedy_bot.gd` |
| `engine/seat_view.gd` | Row entries gain `destroyed: bool` (public); hidden ids unchanged | `test_seat_view.gd` |
| `engine/match_event.gd` | New kind `DESTROYED_CLEARED`; `CARD_REVEALED` gains `destroyed`; redaction as today | `test_seat_view.gd` |
| `tests/test_full_match.gd` | Golden left as a skip until T09; sweep records longest walk and slowest decision; leak scan covers destroyed face-down cards | itself |
| `board/board_step.gd`, `board_steps.gd` | `PULSE` gains `destroyed` and `again`; `DESTROY` becomes the in-place mark; new `CLEAR_DESTROYED` (fly-out at turn end); `TURN_END` carries the tally hand-off (P9, P10) | `test_board_steps.gd` |
| `board/score_tracker.gd` | Tracks `tally` (walk score and mult per side) and `held` (HUD total per side) separately (P11) | `test_score_tracker.gd` |
| `board/board_card.gd`, `board_card.tscn` | `set_destroyed(bool)`: dim, tilt, crack overlay node `Crack` with one texture slot (P8) | MCP at T09 |
| `board/effect_player.gd` | `destroy` marks in place; `clear_destroyed` flies out; `pulse` handles `destroyed` (flip only) and `again` (short pulse) | MCP at T09 |
| `board/score_chips.gd` + scene | `Label3D` chips "×M" then "+N" rising and fading above a card (P12) | `test_board_steps.gd` durations |
| `board/row_tally.gd` + scene | Per side: "score ×mult" `Label3D` beside the row; `fly_to(hud_anchor)` at turn end (P13) | MCP at T09 |
| `board/board_hud.gd`, `board_hud.tscn` | `set_scores` loses `mults`/`walking`; `count_to(seat, total, seconds)` (P13); `score_anchor(seat)` for the fly-in | MCP at T09 |
| `board/lift_rules.gd` | `step_touches` adds `DESTROY` (mark), `CLEAR_DESTROYED`, a re-pulse | `test_lift_rules.gd` |
| `board/prompt_rules.gd` | `on_tap` gains `LIFT_ELIGIBLE` and `SWAP_LIFT`; `action_label(verb)` (P16) | `test_prompt_rules.gd` |
| `board/prompt_host.gd`, `prompt_tap.gd`, `card_lift.gd` | The lifted eligible card, its put-down paths, own face-down cards shown face up in the lift, opponent's kept as backs (P16) | `test_prompt_rules.gd` for the pure parts; MCP at T09 |
| `board/board_hud.gd`, `board_hud.tscn` (also) | `show_action(text)` / `hide_action()`, signal `action_pressed`; a Theme button under the lifted card (P16) | MCP at T09 |
| `board/board.gd` | Dispatches the new steps; `_refresh_scores` reads the tracker's `held`; routes `action_pressed` to `submit_choice` | MCP at T09 |

## Design choices

| # | Choice | Why |
|---|---|---|
| P1 | **The cursor is a slot index per row.** `WalkState.cursor = [int, int]`, both 0 at `begin()`; `next_slot(state)` returns `(seat, slot)`: `next_seat`'s row if `cursor[next_seat] < row.size()`, else the other's, else the walk ends. A pulse at `(seat, slot)` first sets `cursor[seat] = slot + 1`, then flips `next_seat`, then runs the pulse on the card at that slot. `pulsed` is removed from `WalkState` and `to_dict()` | R1–R4: the slot is passed before any effect resolves (R2), and the pulse count is fixed at walk start since row sizes do not change during a walk (destroy marks, returns and the clear are at turn end) |
| P2 | **The score stage belongs to the slot** (amended 2026-11-04, C23). `Pulse.run` reveals the card on the slot (REVEAL_EFFECT, WATCHERS stages as before), then at SCORE takes whatever card holds that slot now. If it is a different card: unrevealed → it gets its own full reveal first (CARD_REVEALED, bonus-0 spend, its ON_REVEAL, the opponent's watchers, each of which may pause on a prompt) and then scores; revealed → it scores (with `again` if already in `scored`); destroyed → flip only. The paused-prompt state records the pulse's seat and slot (`walk.paused_slot`) alongside the card, so a resume scores the slot's occupant, not the card that opened the prompt. The moved card is reached later by the cursor only if its new slot is unpassed | R5, R10, R11, C23–C25: the card that landed on the pulsed slot scores now; the moved card scores later or not this walk |
| P3 | **Re-scoring is a consequence, not a mechanism.** A later pulse at a slot finds whatever card is there; a revealed card starts at the SCORE stage and runs R14's math and the on-score hook again (R9). No per-card counter is needed for correctness; `CARD_SCORED` gains `again: bool` (true when the card already scored this walk) for the board's short pulse, tracked in a per-walk `scored` set in `WalkState` (serialized, cleared at `begin()`) | R6, R9, R30; the `again` flag keeps the board's two speeds decidable from one event |
| P4 | **Destroy is a `CardState` flag.** `_destroy_random` sets `card_state_for(target).destroyed = true` and emits `CARD_DESTROYED {seat, card, slot}` with today's privacy (private to the owner while face down). `MatchState.is_destroyed(card)`. In a pulse, a destroyed card: unrevealed → `CARD_REVEALED {…, destroyed: true}` and the pulse ends (no bonus-0 spend, no REVEAL_EFFECT, no WATCHERS, no SCORE); revealed → the pulse ends at once with no event. `_fire` returns false for a destroyed source; `_watcher_snapshot` and `_carrier` skip destroyed cards | R12–R15, C6, C8; one flag read by the walk, the resolver, the choice and the view |
| P5 | **Targets.** `Choice._is_eligible`: `SWAP_PLACES` → `card != source` (destroyed allowed); `SWITCH_STATS` and `RETURN_AT_TURN_END` → also `not destroyed`; `_destroy_random` builds the live list (`not destroyed`) and fizzles when it is empty, drawing nothing; `pick_index` runs on the live list's size and the slot reported is the row slot of the picked card; `PreviewPolicy.destroy_slot` filters the same way | R16, R17, C9; the stream is consumed only when a pick exists (R27 of DC-05 holds) |
| P6 | **Turn end order.** `_end_turn`: `resolve_returns` (skips destroyed cards, R19) → `clear_destroyed` (each destroyed card in row order per seat: `take_from_row`, `burned.append`, `DESTROYED_CLEARED {seat, card, slot}`, private to the owner when the card was never revealed) → `settle_energy` → `TURN_ENDED`. Rows shrink only here | R18, R19, R21, C10, C12 |
| P7 | **Preview hiding.** `_hide_opponent` no longer erases the opponent's unrevealed row cards; it sets `destroyed = true` on the clone's copies (inert slots, unscored, still occupying their slot) and clears `pending` as before. The clone's `cursor` is untouched, so slot positions and alternation match the live walk | R23, C18; the preview's walk is the live walk on a copy |
| P8 | **The destroyed look.** `BoardCard.set_destroyed(true)`: the card's own `Dimmer`-style darkening (modulate on the face and back materials to the DC-04 dimmer level), a fixed tilt (`rotation.z` about 9°, `rotation.x` about 4°, deterministic per slot parity so neighbours do not match) applied on top of the layout's transform each frame the layout settles, and a `Crack` quad child at `NOTE_Z` with an unshaded transparent material whose `albedo_texture` is the placeholder (a generated `ImageTexture` of jagged white lines on alpha, built once in code) and is read from `godot/art/` through one exported path when present. `set_destroyed(false)` on `clear_def` | R26, R27, C11, C13; no addon change; the texture slot is the art hand-off (ADR 0003 manifest when the image lands) |
| P9 | **Steps.** `DESTROY` (0.35 s: dim, tilt and crack fade in; the card does not leave); `PULSE` gains `destroyed: bool` (flip only, `REVEAL_TIME`, no lift, no chips) and `again: bool` (0.12 s like a revealed pulse; the chips show); `CLEAR_DESTROYED` (0.45 s fly-out, today's destroy animation) from `DESTROYED_CLEARED`; `TURN_END` keeps `scores` and gains the duration the fly-in and count need (0.6 s) | R28–R30, R34 |
| P10 | **Pulse folding** (`BoardSteps._scored_after`) stays keyed on the card id; a destroyed reveal has no score and folds nothing; a re-score with no reveal yields its own `PULSE` from `CARD_SCORED` with `again` | Today's folding already matches by id, so the destroyed and second-score cases fall out |
| P11 | **Two numbers in the tracker.** `ScoreTracker.tally: [score, score]`, `tally_mults`, `held: [int, int]`. `WALK_START` zeroes the tally and the mults, leaves `held`; `PULSE` with a score updates the tally; `TURN_END` sets `held = scores` and clears the tally; `CLEAR_TABLE` resets all. The HUD shows `held` (R33); `walking` is dropped from the HUD contract | R32–R35, C17; the half-walk number (NSC-73) cannot appear because nothing feeds `held` during a walk |
| P12 | **Chips.** `ScoreChips` spawns `Label3D` chips above the pulsed card: when `bonus != 0`, "×M" (gold, 0.25 s rise and fade) then "+N" (seat colour, 0.25 s), else "+N" alone; both inside the pulse's duration budget, so the pulse step's duration becomes `max(PULSE_TIME, chips)`; `added == 0` still shows "+0". Nothing for a destroyed pulse | R31, R28, C14 |
| P13 | **Tally and count.** `RowTally` is a `Label3D` per side anchored at the row's right end, text `score ×mult`, visible from `WALK_START` to `TURN_END`. At `TURN_END` it tweens to `BoardHud.score_anchor(seat)` (unprojected to the table plane) over 0.3 s, then `BoardHud.count_to(seat, total, 0.3)` steps the label from `held` to the new total and the tally hides. Durations divide by the autoplay speed (R36) | R32, R34, R36, C15 |
| P14 | **Lift rules.** `LiftRules.step_touches` adds `DESTROY` (mark), `CLEAR_DESTROYED` and any `PULSE` of the held card (already there); a destroyed face-up card can still be lifted to read (DC-04) and its tilt is suspended while held | R37 |
| P16 | **The prompt reader.** `PromptRules.on_tap(hit, prompt, lifted) -> {LIFT_ELIGIBLE, SWAP_LIFT, LIFT, PUT_DOWN, NOTHING}`: a tap on an eligible card lifts it (or replaces the lifted one), on a non-eligible face-up card lifts it with no button, on the lifted card, the table or Escape puts it down. `PromptHost` keeps `lifted_option` (zone index); `BoardHud.show_action(PromptRules.action_label(verb))` with labels `Swap`, `Discard`, `Switch`, `Return` (`CardEffect.verb_name` → label table); `action_pressed` → `Board.submit_player(choose(zone, lifted_option))` then put-down and the DC-05 R57 clearing. The lift of an own face-down card shows the face (the `SeatView.own_row` stats are known; `CardLift` flips the lifted copy face up and back on put-down); an opponent's face-down card lifts as a back. The button is a Theme `Button` in the HUD anchored under the lift position (D7); hidden whenever `lifted_option` is empty; absent outside a prompt. Autoplay and the bot's `CHOICE_SHOW` are untouched | R40–R47, C19–C22; builds on DC-04's lift and DC-05's `PromptRules` tap routing, which stays a pure, tested function |
| P15 | **Rules version 3.** `MatchRules.RULES_VERSION := 3`; `LOG_FORMAT` stays 2; `ActionLog` replay compares both as cycle 1 R34 requires, so a DC-05 log fails with `RULES_MISMATCH` (or the existing mismatch code) | R24 |

## Interfaces and contracts

```gdscript
# MatchState.WalkState (replaces pulsed)
var cursor: Array[int] = [0, 0]       # slots passed per row
var scored: Dictionary[int, bool] = {} # cards scored at least once this walk (for `again`)

# MatchState
func is_destroyed(card: int) -> bool

# ScoreWalk (pure)
static func next_slot(state: MatchState) -> Vector2i   # (seat, slot) or (-1, -1)
static func step(state, cards, rng, sink, policy) -> bool   # unchanged signature

# EffectResolver
static func clear_destroyed(state: MatchState) -> Array[MatchEvent]   # turn end, P6

# ScoreTracker
var tally: Array[int]; var tally_mults: Array[int]; var held: Array[int]

# BoardHud
func set_scores(scores: Array[int]) -> void               # the held totals
func count_to(seat: int, total: int, seconds: float) -> void
func score_anchor(seat: int) -> Vector2                   # screen position of the label

# BoardCard
func set_destroyed(on: bool) -> void

# PromptRules (pure)
enum Tap { CHOOSE, LIFT, NOTHING, LIFT_ELIGIBLE, SWAP_LIFT, PUT_DOWN }   # CHOOSE kept for the button path
static func on_tap(hit: Dictionary, prompt: Dictionary, lifted_option: int) -> int
static func action_label(verb: String) -> String   # "Swap" | "Discard" | "Switch" | "Return"

# BoardHud
signal action_pressed
func show_action(text: String) -> void
func hide_action() -> void
```

### Events (new or changed; redaction in brackets)

| Kind | Payload |
|---|---|
| `CARD_REVEALED` | `seat`, `card`, `def_id`, `slot`, `flat`, `bonus`, `order`, **`destroyed: bool`** |
| `CARD_SCORED` | `seat`, `card`, `slot`, `flat`, `bonus`, `mult`, `added`, `score`, **`again: bool`** (may now appear twice per card per walk) |
| `CARD_DESTROYED` | `seat`, `card` [hidden while face down], `slot` (unchanged shape; the card stays on the row) |
| **`DESTROYED_CLEARED`** | `seat`, `card` [hidden when never revealed], `slot` (turn end) |
| `TURN_ENDED` | unchanged |

`CARD_MOVED`, `CHOICE_*`, `STATS_CHANGED`, `CARD_RETURNED`, `TURN_STARTED` are unchanged.
`SeatView` row entries: `{card, flat, bonus, revealed, destroyed}`.

## Data model

`MatchState.to_dict()` changes: `walk.pulsed` → `walk.cursor` and `walk.scored`;
`card_states[id].destroyed`. Everything else as DC-05. Instance ids, slots and the action
log's dict forms are unchanged. The destroyed flag ends with `take_from_row` (turn end),
the return path never sees it (P6), and round start clears it with the rest.

## Board design

- A destroyed card is marked by `EffectPlayer.destroy(step)` in place; the fly-out moves to
  `clear_destroyed(step)` at turn end; `_sweep_off_row` and `fly_out` are reused.
- `pulse(step)`: `destroyed` → flip only; `again` → short pulse with chips; a first reveal
  keeps the reveal beat and shows chips once the score arrives (the folded step).
- `ScoreChips` and `RowTally` are children of the board, positioned from the pulsed card's
  global transform and the rows' end markers.
- The HUD's score labels show `held`; `×mult` text leaves `score_text`.
- The prompt reader (P16) sits on the DC-05 prompt flow: the banner and glows open as
  before; the lift and the action button are the only additions; `may_act()` stays false
  during a prompt except for the tap paths `PromptRules` allows and the button.
- Verification scene `board/verify/board_seed1.tscn` is unchanged; the orchestrator picks
  the first seed-1 turn with a destroy, the first with a bonus card scoring and the first
  seat-0 prompt (R1 T4's swap in DC-05) for the three screenshots, or a scripted state if
  seed 1 lacks one.

## Constitution Check

| Rule | Verdict | Note |
|---|---|---|
| All project GDScript is fully typed (`parse` promotes warnings to errors) | PASS | Typed-strict checklist in every brief; `Vector2i` for `(seat, slot)` |
| Engine is deterministic: seeded RNG, no wall-clock, no node access, serializable action log (D4) | PASS | Cursor and destroyed flag in `to_dict()`; the stream is drawn only when a live target exists (P5); preview never touches the stream |
| `make check` gate contract | PASS | Suites extended; boot grep unchanged; golden re-pinned at T09 by the orchestrator |
| Implementers never run Godot or `make check` | PASS | Golden left as a skip until T09, as DC-05 did |
| P5 frontmatter and vault-root links | PASS | Three notes, fresh uids |
| Do-not-touch list | PASS | No addon change; the crack placeholder is project code; no write to `godot/art/` this cycle |
| Secrets only in `.env` | PASS | None involved |
| One branch per cycle (`cycle-5-walk-cursor`), one commit per task, `--no-ff` into `master` (ADR 0002) | PASS | See tasks |
| D2 Compatibility-clean visuals | PASS | Unshaded materials and `Label3D`; a generated line texture, no screen reads |
| D3 art only through `/art` | PASS | The overlay is a placeholder with one texture slot; the image comes later |
| D1 Card3D in-house extras | PASS | Tilt, chips and tally are project code on top of the layout |

**Result:** PASS.

## Risks and mitigations

- **A card scored twice drifts the preview from the live walk** → both run `ScoreWalk.step`;
  the DC-05 preview-vs-live case is extended with a scripted forward swap and a destroy.
- **The tilt fights the Card3D layout tween** → apply the tilt as an offset after the layout
  settles (`CardCollection3D` signal or a per-frame add on the card), suspended while held
  (P14); checked by node query at T09.
- **Golden and boot grep both change** → T09 re-pins `test_full_match.gd`, the check script's
  expectation and the cycles log in one commit.
- **Hidden information for a destroyed face-down card** (`CARD_DESTROYED`,
  `DESTROYED_CLEARED`, the view's `destroyed` flag next to a hidden id) → the T03 leak scan
  covers both events and the row entries in every redacted view of the sweep.
- **Bot time** → unchanged search; walks have one pulse per slot; T09 records the slowest
  decision and the longest walk for NSC-74.
- **`board.gd` touched by two tasks (T06, T07)** → they run in different waves.
- **Chip legibility at the DC-04 lift size and over a dimmed card** → T06 picks the font size
  and the rise height; screenshot 2 checks it.
- **The lifted copy of an own face-down card leaks nothing** → it is the player's own card
  and the view already carries its stats; an opponent's card lifts as a back (P16), checked
  by node query at T09.
- **The action button overlaps the banner or the lifted card** → the button anchors under
  the lift position with the Theme's spacing; screenshot 3 checks it.

## Open questions

- None. The crack image is a later `/art` run (C13), not part of this cycle.
