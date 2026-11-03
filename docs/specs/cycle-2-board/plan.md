---
type: plan
tags: [plan, cycle-2-board, board]
status: approved
related: ["[[specs/cycle-2-board/spec]]", "[[specs/cycle-2-board/tasks]]", "[[specs/cycle-1-match-engine/plan]]", "[[planning/phase-1-tech-stack]]", "[[planning/phase-3-game-loop]]"]
created: 2026-11-03
updated: 2026-11-03
uid: c41f4b46-2293-4478-ac4e-31074a9d655f
linear:
supersedes:
---

# Plan: Cycle 2 — the board

Implements [[specs/cycle-2-board/spec|spec]] (approved 2026-11-03). This is the HOW.
Nothing here changes a requirement; where a requirement left a choice, the choice is
recorded here so [[specs/cycle-2-board/tasks|tasks]] can point at it.

## Stack mapping

| Area | Involved | Approach and tooling |
|---|---|---|
| Godot scenes/UI | yes | New `godot/board/` scene tree on Card3D collections and layouts (D1); HUD, pause menu and result panel as Controls under a `CanvasLayer` styled by one `Theme` resource (D7); verified through the Godot MCP (D6) |
| Input | yes | New `godot/input/` pointer shim (C5): a pure, testable state machine plus a thin node that raycasts the camera |
| Engine (godot/engine + tests) | read only | Consumed through `MatchEngine`, `SeatView`, `ApplyResult.events_for(0)`, `GreedyBot`, `CardDb`; no engine edits |
| Vendored addon | yes, patch | `addons/card_3d/scripts/drag_controller.gd` patched to take shim input (C6), recorded in `THIRD_PARTY_LICENSES.md` |
| Shaders/cards | no | Placeholder faces use `Label3D` and plain `StandardMaterial3D`; no shader (C3) |
| Tooling/scripts | one line | `scripts/check.sh` boot stage passes `-- --seed=1` so boot is reproducible |
| Vault/docs | yes | This set, the specs MOC row, the DC-03 row in the cycles log |
| Linear | yes | Filled by `/exercise`: project per spec, milestone `DC-03 board`, labels `area/scene`, `area/input`, `area/tooling`, `type/feature`, `type/chore`, `spec/cycle-2-board` |

## Module layout

Paths relative to `godot/`. Pure helpers extend `RefCounted` and have a suite; node
scripts stay thin and are proven at verification.

| File | class_name | Responsibility | Suite |
|---|---|---|---|
| `input/pointer_event.gd` | `PointerEvent` | `kind` (PRESS, DRAG_START, DRAG_MOVE, RELEASE, TAP, CANCEL, HOVER), `position: Vector2`, `from_touch: bool` | `test_pointer_tracker.gd` |
| `input/pointer_tracker.gd` | `PointerTracker` | Pure state machine: `feed(event: InputEvent) -> Array[PointerEvent]`, `focus_lost() -> Array[PointerEvent]`; R21–R25 | `test_pointer_tracker.gd` |
| `input/pointer_shim.gd` | `PointerShim` | `Node`: feeds `_input` to the tracker, handles `NOTIFICATION_APPLICATION_FOCUS_OUT`, raycasts, emits signals; computes `units_per_point` | verification |
| `board/match_driver.gd` | `MatchDriver` | Owns `CardDb`, `MatchEngine`, the bots and the action count; returns seat-0 events; builds the `Board:` line | `test_match_driver.gd` |
| `board/staging.gd` | `Staging` | Staged ids in row order, energy, insert, remove, move, `can_afford`, `energy_left`, `to_action` | `test_staging.gd` |
| `board/board_step.gd` | `BoardStep` | One animation step: `kind`, `seat`, `card`, `def_index`, `power`, `scores`, `duration` | `test_board_steps.gd` |
| `board/board_steps.gd` | `BoardSteps` | Pure: `from_events(events: Array[MatchEvent], speed: float) -> Array[BoardStep]` | `test_board_steps.gd` |
| `board/board_card.tscn`, `board_card.gd` | `BoardCard` | Inherits `addons/card_3d/scenes/card_3d.tscn` (no addon edit); `instance_id`, `show_def(def)`, face `Label3D`s, back material; `input_ray_pickable = false` on its body | verification |
| `board/board_theme.tres` | – | The one Theme (D7): fonts sizes, button and panel styles | – |
| `board/board_hud.tscn`, `board_hud.gd` | `BoardHud` | Scores, pips, round and turn, energy with flash, Commit or Pass, pause button, pause menu, result panel | verification |
| `board/board.tscn`, `board.gd` | `Board` | Camera, light, `DragController` (patched) with four collections, entry and exit markers, `PointerShim`, `BoardHud`; runs the step queue; wires drags to `Staging` | verification |
| `board/verify/board_autoplay.tscn` | – | `board.tscn` instance with `autoplay = true`, `fixed_seed = 1` | verification |
| `board/verify/board_seed1.tscn` | – | `board.tscn` instance with `fixed_seed = 1` for the MCP drag run | verification |

`run_scene` in the Godot MCP cannot pass command-line arguments, so the two `verify/`
scenes carry the seed and autoplay as exported values; `--seed=N` and `--autoplay` are for
command-line launches, and the exported values win when set.

## Interfaces and contracts

```gdscript
# PointerTracker (pure)
var units_per_point: float = 1.0          # set by the shim
var drag_threshold_points: float = 8.0
func feed(event: InputEvent) -> Array[PointerEvent]
func focus_lost() -> Array[PointerEvent]
func is_held() -> bool

# PointerShim (Node)
signal pressed(position: Vector2, hit: Object)
signal drag_started(position: Vector2, from_touch: bool)
signal drag_moved(position: Vector2, hit: Object)
signal released(position: Vector2, hit: Object)
signal tapped(position: Vector2, hit: Object)
signal cancelled()
signal hovered(hit: Object)               # real mouse only (R28)
@export var camera: Camera3D
@export_flags_3d_physics var card_mask: int = 1
@export_flags_3d_physics var drop_zone_mask: int = 2
func ray_hit(position: Vector2, mask: int) -> Object

# MatchDriver (pure)
static func create(seed: int, cards: CardDb, autoplay: bool) -> MatchDriver
func start() -> Array[MatchEvent]                      # seat-0 redacted events
func submit_player(action: EngineAction) -> ApplyResult
func bot_turn_due() -> bool                            # awaited seat is bot-driven
func play_bot() -> ApplyResult                         # one bot action
func view() -> SeatView                                # seat 0
func is_over() -> bool
func result_line() -> String                           # R5, empty until over

# Staging (pure)
func reset(energy: int) -> void
func can_afford(cost: int) -> bool
func insert(card: int, cost: int, index: int) -> bool  # false when over budget (R14)
func remove(card: int) -> void
func move(card: int, index: int) -> void
func energy_left() -> int
func cards() -> Array[int]
func to_action(seat: int) -> EngineAction

# BoardSteps (pure)
static func from_events(events: Array[MatchEvent], speed: float) -> Array[BoardStep]
```

### Pointer tracker rules (R21–R25, research C2)

- **Source stream.** Mouse button 1 and mouse motion only. A mouse event with
  `device == InputEvent.DEVICE_ID_EMULATION` is touch (`from_touch = true`); otherwise
  it is a real mouse.
- **Raw touch.** `InputEventScreenTouch` and `InputEventScreenDrag` never move the
  pointer (R23); they are read only to cancel: a touch press with `index != 0` while
  held, or a release at `(-1, -1)`, or `canceled == true`.
- **Held state.** Tracked by the tracker from press and release, never from
  `button_mask` (R22), so MCP motion with mask 0 still drags.
- **Drag threshold.** 8 points × `units_per_point`. The shim sets `units_per_point` to
  `DisplayServer.screen_get_scale() × viewport height ÷ window height`, so the threshold
  is the same physical size on a Retina Mac and an iPhone.
- **Tap.** Release before the threshold emits `TAP` (and the board ignores it, R20).
- **Hover.** Unheld motion from a real mouse emits `HOVER`; touch never does (R28).

### Card3D DragController patch (C6, R29, R30)

Only `addons/card_3d/scripts/drag_controller.gd` changes; `card_3d.gd` and
`card_collection_3d.gd` keep their upstream wiring. The patch:

1. Adds `@export var pointer: PointerShim` and connects its signals in `_ready()`;
   removes `_unhandled_input`.
2. On `pressed` with a hit whose owner is a `Card3D` in a known collection, emits that
   card's `card_3d_mouse_down`, which drives the existing `_on_card_pressed` →
   `card_selected` → `_on_collection_card_selected` path.
3. On `drag_started`, calls the existing `_drag_card_start()` (Card3D's own
   `card_drag_threshold` stays 0; the shim owns the threshold).
4. On `drag_moved`, raycasts `drop_zone_mask` to find the hovered collection's
   `DropZone` body and calls the existing enter and exit handlers when it changes (in
   place of `mouse_entered`/`mouse_exited`), then `_handle_drag_event()`. Where the drag
   is from touch, the projected position is offset upward by a lift of 48 points ×
   `units_per_point` (R27).
5. On `released`, emits the pressed card's `card_3d_mouse_up` and calls
   `_on_collection_card_deselected()`.
6. On `cancelled`, clears the hovered collection and returns the card with
   `_return_card_to_collection()` (R26), then resets drag state.
7. On `hovered`, emits `card_3d_mouse_over` / `card_3d_mouse_exit` on the cards entering
   and leaving the ray.

The board turns off physics picking on its own instances (`input_ray_pickable = false`
on card bodies and drop zones) so no duplicate path remains. Each changed line goes in the
`card_3d/` row of `THIRD_PARTY_LICENSES.md`, after the existing `is_running()` fix.

### Collections and drop rules (R11–R19)

| Collection | Layout | `DragStrategy` rules |
|---|---|---|
| `PlayerHand` | fan, bottom | select and remove only while the player may act (R18); reorder always on (R19) |
| `PlayerRow` | line, lower board | insert only while the player may act and `Staging.can_afford` (R14); reorder on (R13); remove back to `PlayerHand` only |
| `OpponentRow` | line, upper board | nothing selectable |
| `OpponentHand` | fan, top, face down | nothing selectable |

The board subclasses `DragStrategy` in typed project code (`board/board_drag_strategy.gd`)
rather than editing the addon. A refused drop (R14) is detected on `drag_stopped` when the
card was over `PlayerRow`, and triggers the energy flash. `card_moved` keeps `Staging`
in step with `PlayerRow`'s order.

### Table geometry

Card3D lays cards in a collection's XY plane, and its drag plane is `z = 1.5`. The table
keeps that convention: the board faces a fixed camera on +Z with a slight downward tilt,
in landscape at the project's 1280 × 720 base with `expand` aspect. Entry marker off the
left edge, exit marker off the right.

### Step queue (R31–R39)

`BoardSteps.from_events` maps seat-0 events to steps; `Board` runs them one at a time
and locks input while any remain.

| Event | Step | Duration at 1× |
|---|---|---|
| `ROUND_STARTED` (after round 1) | sweep both rows and both hands to the exit, free the cards | 0.40 s |
| `CARD_DEALT`, `CARD_DRAWN` | spawn at entry, sweep to the seat's fan (opponent face down) | 0.30 s, deals staggered 0.12 s |
| `CARD_BURNED` | spawn at entry, sweep to exit | 0.45 s |
| `TURN_STARTED` | HUD round, turn, energy; `Staging.reset(energy)` | instant |
| `COMMITTED` (opponent) | bot think wait, then `count` face-down cards fan to `OpponentRow` | 0.6 s + 0.25 s per card |
| `COMMITTED` (player) | none: the cards are already on `PlayerRow` | instant |
| `CARD_REVEALED` | flip the card face up (opponent cards take the revealed `def_id`), score += power | 0.35 s + 0.15 s gap |
| `TURN_ENDED` | set both scores from the payload (R36) | instant |
| `ROUND_ENDED` | light the winner's pip | 0.30 s |
| `MATCH_ENDED` | print the `Board:` line, show the result panel | instant |

Speed is 1 normally and 4 under autoplay; every duration divides by it. The opponent's
face-down cards on `OpponentRow` are matched to reveals in order, since the redacted
commit carries no ids.

### Seeds and rematch (R3, R43)

- First match: exported `fixed_seed` if non-zero, else `--seed=N`, else
  `Time.get_ticks_usec()` mixed with `Time.get_unix_time_from_system()`. The clock is
  read in the scene, never in the engine.
- Rematch: a fresh clock seed, or `seed + 1` when the first seed was fixed, so a fixed
  run stays repeatable.
- Bots use `GreedyBot.seed_for(seed, seat)`, exactly as `main.gd`'s smoke run, so the
  seed-1 autoplay match equals the smoke match (R5).

### Main scene (R1, R44, R45)

`main.gd` keeps the smoke run, then instances `board/board.tscn` as a child and prints
`Main ready` once it is in the tree. `main.tscn` loses its `Camera3D`,
`DirectionalLight3D` and `Title` (the board brings its own camera and light).
`scripts/check.sh`'s boot command gains `-- --seed=1`.

## Data model

No new serialized data. The board holds:

| Owner | State | Notes |
|---|---|---|
| `MatchDriver` | `CardDb`, `MatchEngine`, `Array[GreedyBot]` (seat 1, plus seat 0 under autoplay), `seed`, `actions` | The engine stays the only rules state |
| `Staging` | `Array[int]` staged ids, `Dictionary` id → cost, `energy` | Reset at each `TURN_STARTED` |
| `Board` | `Dictionary` instance id → `BoardCard`, `Array[BoardStep]` queue, `speed`, `input_locked` | Opponent cards keyed by a local counter until revealed |

## Tests

| Suite | Covers |
|---|---|
| `test_pointer_tracker.gd` | R21–R25: press → drag past threshold → move → release; release under threshold is a tap; mask-0 motion still drags; an emulated mouse press followed by its raw touch duplicate yields one press; second-finger press, (-1, -1) release, `canceled` and `focus_lost()` each yield cancel; hover only for non-emulated motion; threshold scales with `units_per_point` |
| `test_staging.gd` | R12–R16: insert at index, move, remove, over-budget refusal leaves state unchanged, `energy_left`, empty commit is a pass, `to_action` order |
| `test_board_steps.gd` | R31–R38: step order equals event order; reveal steps carry engine order and power; score after the last reveal equals `TURN_ENDED`; burns go entry to exit; round sweep precedes the deal; opponent commit yields the bot wait; durations divide by speed |
| `test_match_driver.gd` | R2, R5, R6: seed-1 autoplay played through the driver ends with `Board: match ended seed=1 winner=0 wins=4-0 rounds=4 end=wins actions=56`; the driver returns only seat-0 redacted events (no opponent hand id); a concede yields reason `concede` |

## Constitution Check

| Rule | Verdict | Note |
|---|---|---|
| All project GDScript is fully typed | PASS | `godot/input/` and `godot/board/` are under the gate; `BoardCard` and `BoardDragStrategy` subclass untyped addon classes with typed members |
| Engine is deterministic: seeded RNG, no wall-clock, no node access, serializable action log (D4) | PASS | Engine untouched; the clock seed is read in the scene and handed to the engine; replay unaffected |
| `make check` gate contract | PASS | Boot keeps both lines and gains a fixed seed; board failures `push_error`, which the grep catches |
| Implementers never run Godot or `make check` | PASS | Node scripts are proven by the orchestrator through the MCP at T11; pure helpers by suites the orchestrator runs |
| Notes carry P5 frontmatter and vault-root links | PASS | Three notes, fresh uids |
| No edits under the do-not-touch list | PASS with a recorded patch | Only `addons/card_3d/scripts/drag_controller.gd`, recorded in `THIRD_PARTY_LICENSES.md` as CLAUDE.md allows (C6) |
| Secrets only in `.env` | PASS | None involved |
| Small reversible commits on `dc-03-board`, merged with `--no-ff` | PASS | See tasks |
| UI uses plain Godot Theme resources (D7) | PASS | One `board_theme.tres`; no addon |
| Compatibility-clean rendering (D2) | PASS | No shaders; `StandardMaterial3D` and `Label3D` only |
| P7: one screenshot per visible feature | PASS | Two screenshots (C11): drag staging and match end |

**Result:** PASS.

## Risks and mitigations

- The patched DragController is outside the typed gate (`addons/` is skipped) →
  keep the patch small and listed line by line; T10's review reads it in full; the MCP
  drag run exercises every path except touch.
- Touch paths (duplicate events, (-1, -1) cancel, lift) cannot be exercised on desktop
  → `test_pointer_tracker.gd` feeds synthesized `InputEventScreenTouch` and emulated
  `InputEventMouseButton` events; device proof waits for the iOS milestone.
- Godot 4.6.3 lacks the 4.7 fix for a 3D picking crash when a picked object leaves the
  tree (PR #117776) → physics picking is off on board objects, so the crash path is not
  reached.
- Card3D reparents cards between collections mid-drag, and the board also moves cards
  during steps → input stays locked while steps run (R39), so the two never overlap.
- The step queue could drift from engine state (a dropped or doubled step) → scores
  are reset from `TURN_ENDED` every turn (R36), and the autoplay line is checked against
  the engine's own result.
- A long autoplay match at 4× takes roughly 30 s → the MCP verification waits on the
  runtime log line rather than sleeping a fixed time.

## Open questions

- None.
