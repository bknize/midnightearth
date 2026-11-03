---
type: plan
tags: [plan, cycle-3-board-feedback, board]
status: approved
related: ["[[specs/cycle-3-board-feedback/spec]]", "[[specs/cycle-3-board-feedback/tasks]]", "[[specs/cycle-2-board/plan]]", "[[planning/phase-1-tech-stack]]"]
created: 2026-11-03
updated: 2026-11-03
uid: e53bb301-c199-436f-9e3f-666c08d82a57
linear:
supersedes:
---

# Plan: Cycle 3 — board feedback

Implements [[specs/cycle-3-board-feedback/spec|spec]]. Everything here is scene, input and
addon-patch work on top of the DC-03 board. Nothing touches `godot/engine/`.

## Stack mapping

| Area | Involved | Approach and tooling |
|---|---|---|
| Godot scenes/UI | yes | `board/board.gd`, `board.tscn`, `board_card.tscn` + `.gd`, `board_hud.tscn` + `.gd`; new `board/card_lift.gd` and `board/lift_rules.gd`; Theme unchanged (D7); verified through the Godot MCP on `board/verify/board_seed1.tscn` |
| Input | yes | `input/pointer_shim.gd`, `input/pointer_tracker.gd`, `tests/test_pointer_tracker.gd` (GUI-press rule, R25) |
| Addon patch | yes | `addons/card_3d/scripts/drag_controller.gd` (R28), every changed line recorded in `addons/THIRD_PARTY_LICENSES.md` |
| Engine | no | read only |
| Shaders/cards | no | rim, glow and dimmer are unshaded `StandardMaterial3D` with alpha, Compatibility-clean (D2) |
| Tests | yes | new `tests/test_lift_rules.gd`, `tests/test_result_text.gd`; extended `test_pointer_tracker.gd` |
| Vault/docs | yes | this set; the DC-04 row in [[planning/cycles]] at `/cycle test` |
| Linear | yes | new project "Cycle 3 — board feedback"; NSC-48, NSC-49 and NSC-50 move into it (C7) |

## Design choices

| # | Choice | Why |
|---|---|---|
| P1 | **Pick-up uses a stand-in** (C5). The board hides the real card in its slot (`visible = false`; it stays in its collection, so the slot stays open). A `BoardCard` stand-in under `Loose` takes the card's global transform, face and rim, then tweens to the lift pose. On put-down it tweens to the real card's *current* global transform, then it is freed and the real card is shown again | Card3D layouts re-tween cards whenever a collection changes. A card pulled out of its collection would close its gap, and the queue keeps running (C6). The user sees one card move out and back (R4) |
| P2 | **Lift pose**: the stand-in is parented to nothing that moves. Its target is `camera.global_transform * Transform3D(Basis(), Vector3(0, 0, -d))`, face towards the camera, with `d = CARD_HEIGHT / (LIFT_FILL * 2 * tan(deg_to_rad(camera.fov) / 2))`. Here `CARD_HEIGHT = 3.5` (the Card3D mesh) and `LIFT_FILL = 0.9` | Fills about 90% of the screen height at any aspect, with no hard-coded distance |
| P3 | **Dimmer**: a `MeshInstance3D` quad parented to the camera, just behind the lift pose, large enough to cover the frustum there. It is black, unshaded and transparent, with alpha tweened 0 → 0.6. The HUD's `CanvasLayer` is hidden while a card is held (a 2D layer always draws over 3D, so it cannot sit under the card) | R3. The HUD hides rather than dims because Godot draws 2D over 3D. That also makes R3's "HUD takes no input" automatic |
| P4 | **Timings**: lift 0.25 s and put-down 0.2 s, ease out cubic, not scaled by `speed` (player-driven). R9 and R10 put-downs use the same 0.2 s, or 0 for R10 | Responsive. Autoplay never lifts |
| P5 | **Tap routing**: the board connects to `PointerShim.tapped`. If no card is held and `may_lift`, it lifts the `BoardCard` that owns the hit collider. If a card is held, any tap puts it down. Escape is handled in `board._unhandled_input` before the pause check: held → put down and mark the event handled | R1, R5, C9 |
| P6 | **Drag lock while held**: the board's lock (`_is_locked`, used by `BoardDragStrategy`) also returns true while a card is held. Hover pop is suppressed by setting `hover_disabled` on the player's collections while held | R6 |
| P7 | **Queue and the held card** (C6, R9): before `_play(step)`, the runner asks `LiftRules.step_touches(step, held)`. If true, it awaits `card_lift.put_down()` and then plays the step. The await uses the node-owned wait pattern from the NSC-45 fix, so exit never leaks a coroutine | R8, R9 |
| P8 | **Rim**: a `MeshInstance3D` child `Rim` in `board_card.tscn`. It is a `PlaneMesh` 2.5 × 3.5 scaled by 1.08, just behind the card mesh, unshaded, colour `Color(0.35, 0.75, 1.0, 0.9)`, hidden by default. `BoardCard.set_unseen(on: bool)`. The board keeps it equal to "on `player_row` and not revealed" (R17–R21) by calling one `_refresh_rims()` after every staging change, commit, reveal and clear | C4, C9. One recompute point, no per-path bookkeeping |
| P9 | **Revealed set**: `_revealed_ids: Dictionary[int, bool]` on the board, filled in `_reveal` for seat 0 and cleared at round sweep and new match. Unseen = on `player_row` and not in `_revealed_ids` | R18 needs to know which committed cards have played their reveal |
| P10 | **Zone glows**: one `MeshInstance3D` `ZoneGlow` per player collection in `board.tscn` (`PlayerRow/ZoneGlow`, `PlayerHand/ZoneGlow`), a flat quad sized to that collection's drop-zone shape, unshaded, transparent. Three looks: idle glow (alpha 0.18, pale gold), hover (alpha 0.35), refuse (red, alpha 0.35). `board._on_drag_started` shows both; `mouse_enter_drop_zone` / `mouse_exit_drop_zone` on both collections set hover; `_on_drag_stopped` and `_clear_table_now` hide both | R12–R16 |
| P11 | **Refuse state**: shown on the row panel while `_drag_from_hand and not _card_affordable(card)`, in place of glow and hover | R14 |
| P12 | **GUI presses** (R25, NSC-50.2, suspected cause of NSC-49): on a press, `PointerShim` asks `get_viewport().gui_get_hovered_control()`. If that control's `mouse_filter` is not `MOUSE_FILTER_IGNORE`, it calls `tracker.feed(event, true)` (`gui_blocked`). The tracker then swallows that gesture until the press ends. The tracker owns the rule, so the suite tests it headless; the shim only supplies the flag. The HUD's full-screen containers already use `mouse_filter = 2` (ignore), so only buttons and panels block | One check at the press. Motion and release keep flowing (a drag that crosses the HUD still works), and the tracker stays testable without a viewport |
| P13 | **`may_act` cache** (NSC-50.1): `_awaited: bool` is set in `_advance()` / `_on_turn_started` from `driver.view().is_awaited()` once per step, and `may_act` reads it | R26 |
| P14 | **Drag reset** (NSC-50.3): `_clear_table_now` calls `pointer.cancel()` before clearing collections. The DragController handles the cancel and drops its drag state. If any state remains (checked in review), add a `reset()` to the patch | R27 with no addon change if possible |
| P15 | **Stray drag start** (NSC-50.4): in `drag_controller.gd` `_on_pointer_drag_started`, when nothing is selected, call `pointer.cancel()` so the tracker leaves drag mode. Recorded in `THIRD_PARTY_LICENSES.md` | R28 |
| P16 | **Layout** (NSC-48): the HUD's round, turn and energy panel (`Root/TopInfo`) moves from top centre to the top-left corner, clear of the opponent fan. Both rows get a `LineCardLayout` sub-resource with `max_width = 26` (8 × 2.5 + 7 × 0.5 = 23.5 fits; the default 20 overlaps). `NameLabel` uses `autowrap_mode = 2` (word) and a font size picked so the longest name in `engine/data/cards.json` wraps only at spaces | R22, R23 |
| P17 | **Result phrases** (NSC-48): a static `BoardHud.reason_text(reason: String, winner: int, rounds: int) -> String` | R24 |

### Phrase table (R24)

| Reason | Phrase |
|---|---|
| `wins` | `First to 4 round wins` |
| `rounds` | `Most round wins after <rounds> rounds` |
| `sudden_death` | `Won in sudden death` |
| `concede` | `You conceded` when winner is 1, `Opponent conceded` when winner is 0 |
| anything else | the raw reason (with a `push_warning`) |

## Interfaces and contracts

```gdscript
# board/lift_rules.gd: pure, no nodes (R9, R11)
class_name LiftRules
extends RefCounted
enum Place { HAND, ROW, OPPONENT_ROW, OPPONENT_HAND }

## R1, R2, R11: may this card be lifted, from its own state alone?
static func may_lift(place: Place, face_up: bool) -> bool
## R9: would this step move, flip or remove the held card?
## held_id: engine instance id; held_place and held_staged describe the card now.
static func step_touches(step: BoardStep, held_id: int, held_place: Place, held_staged: bool) -> bool
```

`step_touches` is true for:
- `CLEAR_TABLE` (round sweep): any held card.
- A seat-0 reveal whose `card == held_id`.
- `TURN_START` when `held_staged` (the board unstages all at a turn start).
- A seat-0 commit under autoplay that moves `held_id` from hand to row.
- `MATCH_END`: no (the table stays, cycle-2 R42).

Opponent commit and reveal never touch a held card, because a held opponent card is
already revealed. The suite builds steps from a real seed-1 match, as
`test_board_steps.gd` does.

```gdscript
# board/card_lift.gd: Node owned by the board
class_name CardLift
extends Node
signal lifted(card: BoardCard)
signal put_down_finished(card: BoardCard)
var held: BoardCard            # the real card, or null
func setup(camera: Camera3D, loose: Node3D, dimmer: MeshInstance3D, spawn: Callable) -> void
func lift(card: BoardCard) -> void
func put_down(duration: float = PUT_DOWN_TIME) -> void   # awaitable; no-op when nothing held
func drop_now() -> void                                     # R10
func is_holding() -> bool
```

```gdscript
# board_card.gd additions
func set_unseen(on: bool) -> void   # shows or hides $Rim
func is_unseen() -> bool
func copy_face_from(other: BoardCard) -> void  # face text, face-up state, rim (for the stand-in)
```

```gdscript
# pointer_tracker.gd change
func feed(event: InputEvent, gui_blocked: bool = false) -> Array[PointerEvent]
```

A press fed with `gui_blocked = true` emits nothing. The motion and release that follow
emit nothing until the next unblocked press. A touch duplicate of a blocked press is
blocked too.

Board scene additions: `Camera3D/Dimmer` (MeshInstance3D), `CardLift` (Node),
`DragController/PlayerRow/ZoneGlow`, `DragController/PlayerHand/ZoneGlow`. Signal
`PointerShim.tapped → Board._on_pointer_tapped`. Connect `PlayerHand`'s
`mouse_enter_drop_zone` and `mouse_exit_drop_zone` signals (PlayerRow's are already
connected).

## Data model

No engine state and nothing serialized. Board-side state:
- `CardLift.held: BoardCard`, plus the stand-in (private).
- `Board._revealed_ids: Dictionary[int, bool]`: seat-0 ids whose reveal has played this
  round.
- `Board._awaited: bool`: cached per step (P13).
- Zone glow look: derived from the drag state on every drag event, not stored.

## Constitution Check

| Rule | Verdict | Note |
|---|---|---|
| All project GDScript is fully typed | PASS | New files follow the typed-strict checklist from the DC-01 lessons. Suites are exempt from `return_value_discarded` only |
| Engine is deterministic (D4) | PASS | No engine change. The board stays a consumer |
| `make check` gate contract | PASS | Two new suites and one extended suite. Boot unchanged (R30) |
| Implementers never run Godot or `make check` | PASS | Briefs say so. The orchestrator verifies at T08 |
| P5 frontmatter and vault-root links | PASS | All three notes |
| Do-not-touch list | PASS | Only `drag_controller.gd` under `addons/`, through a patch recorded in `THIRD_PARTY_LICENSES.md`. Screenshots land in gitignored `godot/reports/` |
| Secrets only in `.env` | PASS | None involved |
| Branch per changeset, one commit per task, `--no-ff` into `master` | PASS | `spec-cycle-3-board-feedback` for this set; `dc-04-board-feedback` for the cycle |
| D2 Compatibility-clean visuals | PASS | Unshaded alpha materials only; no `SCREEN_TEXTURE`, no custom shader |
| D1 Card3D in-house extras | PASS | Pick-up, glows and rims are project code on top of Card3D |

**Result:** PASS.

## Risks and mitigations

- **Transparent sort order** (dimmer vs stand-in vs rim) → set `render_priority`: dimmer
  below the stand-in, rim below its card. Check in the T08 screenshot.
- **The held card's slot moves while held** (a deal re-fans the hand) → put-down reads the
  real card's transform at put-down time (P1), so it lands in the new slot.
- **A step frees the held card** → covered by R9 and `step_touches`. Every free path
  (round sweep, new match) is in the true list. A `put_down` on a freed card logs a
  warning and frees the stand-in.
- **`gui_get_hovered_control` and emulated touch** → the press comes as an emulated mouse
  event first (cycle-2 C2), so the same check applies. Proven at the iOS milestone.
- **NSC-49 might not be the pointer** → T08's 10-run scripted Pause → Concede decides it.
  If it still fails, it goes back to Backlog with the log, per C8.
- **board.gd is touched by five tasks** → waves in tasks.md keep at most one board.gd
  writer in flight at a time.

## Open questions

- None.
