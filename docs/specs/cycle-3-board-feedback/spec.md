---
type: spec
tags: [spec, cycle-3-board-feedback, board]
status: approved
related: ["[[specs/cycle-3-board-feedback/plan]]", "[[specs/cycle-3-board-feedback/tasks]]", "[[specs/cycle-2-board/spec]]", "[[planning/cycles]]", "[[planning/phase-1-tech-stack]]"]
created: 2026-11-03
updated: 2026-11-03
uid: a8896f79-3a81-48ed-bbe0-f88ee3bd9c44
linear:
supersedes:
---

# Spec: Cycle 3 — board feedback

**Slug:** `cycle-3-board-feedback`  ·  **Change type:** scene  ·  **Status:** approved (Ben, 2026-11-03, two rounds; signed off 2026-11-03)  ·  **Runs as:** milestone `DC-04 board-feedback`

Cycle 3 answers Ben's first hands-on test of the cycle-2 board with three changes. Tapping a
card picks it up to examine it. Drop zones glow while a drag is in progress. Cards the
opponent has not seen yet get a rim. The cycle also takes in the three issues left in
Backlog after DC-03: NSC-48 (layout), NSC-49 (the concede-click flake) and NSC-50 (four
review nits).

## Intent

After cycle 3, Ben can tap any face-up card to lift it to fill the screen over a dimmed
table and tap again to put it back. While he drags, the zones that will take the card
glow, the one under the pointer brightens, and the row turns red when it would refuse the
card. His staged and committed cards carry a rim until they are revealed. The opponent's
fan, crowded rows and the result reason read cleanly, and a click on a HUD button never
reaches the table.

## Non-goals

- No card art, rules text or foil. The held card shows the same placeholder face (cycle-2
  C3); the pick-up is built so art and text can fill it later.
- No reading of face-down cards ("forbidden" cards). A later feature may allow it in
  other circumstances (C2).
- No shader work. The rim, glows and dimmer are plain unshaded materials.
- No engine rule changes. The engine is consumed as DC-03 left it.
- No iOS build (D8). Touch follows from the pointer shim but is only proven at the next
  milestone.
- No pinch, rotate or tilt of the held card. Pick up and put down only.
- No sound, settings or animation speed control.

## Actors

- **Ben (seat 0)**: taps, drags and commits on desktop with a mouse.
- **The board**: plays engine events as tweens and owns the pick-up, glows and rims.
- **The pointer shim**: turns mouse and touch into press, drag, tap and cancel.
- **The greedy bot (seat 1, and seat 0 under autoplay)**: unchanged.
- **The orchestrator**: verifies through `make check` and the Godot MCP.

## Requirements (EARS)

### Picking up a card (C1, C2, C5, C6)

- R1. When the player taps a card whose face the player can see (a card in the player's
  hand, a card on the player's row, or a revealed card on the opponent's row), the board
  shall pick it up. The card lifts out of its slot and turns face-on to the camera, and it
  grows until it fills most of the screen height.
- R2. When the player taps a face-down card, the board shall leave the table unchanged.
- R3. While a card is held, the board shall dim the table and the HUD behind it, and the
  HUD shall take no input.
- R4. While a card is held, its slot shall stay open, and only one copy of the card shall
  be visible.
- R5. When the player taps anywhere or presses Escape while a card is held, the board
  shall put the card down. It flies back into its slot (wherever that slot now is) and the
  dimmer lifts. That tap or key press shall do nothing else.
- R6. While a card is held, the board shall start no drag and show no hover pop.
- R7. While a drag is in progress or the pause menu is open, a tap shall not pick up a
  card.
- R8. While a card is held, the animation queue shall keep playing underneath (C6).
- R9. If the next animation step would move, flip or remove the held card, then the board
  shall put the card down first and play that step once the card is back in its slot.
- R10. When a new match starts (Rematch, or a fresh start), the board shall drop any held
  card at once, with no tween.
- R11. The board shall decide whether a card may be picked up from that card's state
  alone, so a later feature can widen the rule (C2).

### Drop zones (C3)

- R12. When a drag of one of the player's cards starts, the board shall show a glowing
  panel on each zone that accepts the drag: the player's row and the player's hand.
- R13. While a drag is in progress, the panel of the zone under the pointer shall be
  brighter than the other panel.
- R14. While the dragged card comes from the hand and costs more than the energy left, the
  row's panel shall show a red refusal state instead of its glow.
- R15. When a drag ends (drop, refusal or cancel), the board shall hide every zone panel.
- R16. The board shall never show a panel on the opponent's row or hand.

### Cards the opponent has not seen (C4, C9)

- R17. While one of seat 0's cards is on the player's row and has not been revealed, the
  board shall draw a tinted rim around it. This covers staged cards and committed cards
  waiting for their reveal.
- R18. When a seat-0 card's reveal plays, the board shall remove that card's rim.
- R19. When a staged card goes back to the hand (unstaged, a refused commit, or a turn
  start), the board shall remove its rim.
- R20. The rim shall stay on a card while it is being dragged along the row or held.
- R21. Cards in the hand and the opponent's cards shall have no rim.

### Layout (NSC-48)

- R22. At 1280 × 720, the opponent's face-down fan shall be fully visible, with no HUD
  panel covering it.
- R23. With eight cards on a row, no card shall cover another card's name, cost or power,
  and no card name shall break mid-word.
- R24. The result panel shall give the end reason as a phrase, one per reason: `wins`,
  `rounds`, `sudden_death` and `concede` (plan, phrase table).

### Pointer and drag hygiene (NSC-50, NSC-49)

- R25. When a press lands on a HUD control that takes mouse input, the pointer shim shall
  ignore that press and the rest of its gesture, so the table sees no press, drag or tap.
- R26. The board shall work out whether the player is awaited once per animation step,
  not on every hover and select.
- R27. When the table is cleared for a new match, the board shall end any drag in
  progress, leaving the drag controller with no dragged card.
- R28. If a drag starts with no card selected, then the drag controller shall end the
  gesture, so the pointer leaves drag mode at once.
- R29. When the player presses Pause and then Concede, the board shall concede, whatever
  cards lie under the menu (NSC-49).

### Unchanged

- R30. The boot log, the `Engine smoke:` line, `Main ready` and the seed-1 autoplay
  `Board: match ended seed=1 winner=0 wins=4-0 rounds=4 end=wins actions=56` line shall
  stay as DC-03 left them.
- R31. Every cycle-2 requirement stays in force except cycle-2 R20 ("a tap leaves the
  table unchanged"). R1 and R2 of this spec replace it (C7 of cycle 2 reserved the tap for
  this).

## Clarifications (Ben, 2026-11-03)

| # | Question | Decision |
|---|---|---|
| C1 | How the zoomed card appears | Ben: "the card should zoom in to fill the screen, over a dimmer table. Like 1a, but I don't want a 'copy' of the card, I want it to feel like the user is picking up and examining the card." Resolved by C5 |
| C2 | Which cards can be zoomed | 2a: any card whose face the player can see; tapping a face-down card does nothing. Ben: "there may be features later which allow a user to read a 'forbidden' card in other circumstances, but not right now" (R11) |
| C3 | Drop-zone look | 3a: a translucent glowing panel on each zone that accepts the drag (player's row and hand); the zone under the pointer brightens; the row turns red when it would refuse an unaffordable card |
| C4 | Marker for cards the opponent hasn't seen | 4b: a tinted rim around the card (no badge) |
| C5 | How the pick-up works | 5a: the card lifts out of its slot to fill the screen and flies back into the same slot; the slot stays open while it is held; you only ever see one card. A stand-in may carry it for the trip so the card layouts never fight the tween |
| C6 | Pick-up during animations | 6b: allowed, and the animation queue keeps playing underneath. Edge-case rule (orchestrator, stated with round 2's answers): a step that would move, flip or remove the held card puts it down first (R9) |
| C7 | Backlog issues in Linear | 7a: move NSC-48, NSC-49 and NSC-50 into the Cycle 3 project under DC-04, add `spec/cycle-3-board-feedback`, keep their Cycle 2 spec links; `/exercise` does not duplicate them |
| C8 | Proof at `/cycle test` | 8a: two screenshots (a card held; a drag in progress with zones glowing and staged cards rimmed), node queries for each state, and a scripted Pause → Concede run repeated 10 times with cards on the row under the menu |
| C9 | Defaults (stated in round 2, no objection) | Static cool-blue rim drawn as a slightly larger card-shaped plane behind the card, no shader; the rim stays on during a drag; no pick-up mid-drag; Escape puts a held card down before it can open pause; mouse hover pop unchanged |

## Scenarios

- **Given** the player is awaited with four cards in hand, **when** Ben taps the second
  card, **then** it lifts to fill most of the screen face-on over a dimmed table and HUD,
  and its slot in the fan stays open.
- **Given** a card is held, **when** Ben taps anywhere, **then** it flies back into its
  slot, the dimmer lifts, and nothing else on the table changes.
- **Given** the opponent's row holds two face-down cards and one revealed card, **when**
  Ben taps a face-down card, **then** nothing happens; **when** he taps the revealed one,
  **then** it is picked up.
- **Given** Ben holds a staged card while the bot's commit animates, **when** the next
  turn starts and would send staged cards back to the hand, **then** the held card is put
  down first, and only then does it fly back to the hand.
- **Given** a card is held during a round, **when** the round ends, **then** the card is
  put down before the sweep clears the table.
- **Given** Ben starts dragging an affordable hand card, **then** panels glow on his row
  and his hand; **when** the pointer is over the row, **then** the row's panel brightens;
  **when** he drops it, **then** both panels disappear.
- **Given** Ben drags a card costing more than the energy left, **when** the pointer is
  over the row, **then** the row's panel shows red; **when** he releases, **then** the
  card returns, the energy flashes, and every panel is hidden.
- **Given** Ben stages two cards, **then** both have a rim; **when** he commits, **then**
  they keep it; **when** each one's reveal plays, **then** its rim goes.
- **Given** Ben unstages a card by dragging it back to the hand, **then** its rim goes.
- **Given** the pause menu is open over a row of cards, **when** Ben clicks Concede (10
  scripted runs), **then** each run concedes and shows the result panel.
- **Given** a hand card lies under the Commit button, **when** Ben clicks Commit, **then**
  the commit goes through and the card is neither pressed nor picked up.
- **Given** a match ends by each reason, **then** the result panel reads that reason's
  phrase.
- **Given** `make check`, **then** it is green, and the seed-1 autoplay line is unchanged.

## Data touched

- New: the pick-up logic and its rules under `godot/board/`, a rules suite under
  `godot/tests/`, the rim on the card scene, a glow panel per player zone on the board
  scene, the dimmer.
- Changed: `godot/board/board.gd`, `board.tscn`, `board_card.tscn` (+ `.gd`),
  `board_hud.tscn` (+ `.gd`), `godot/input/pointer_shim.gd` and `pointer_tracker.gd`
  (+ suite), `godot/addons/card_3d/scripts/drag_controller.gd` through a recorded patch.
- Read only: `godot/engine/` (all of it), `engine/data/cards.json`.
- Never: `docs/.obsidian/`, `.env`, `godot/.godot/`, `godot/reports/` (screenshots land
  there, gitignored, and are never committed), the archive.

## Definition of done

- [ ] Tapping a face-up card picks it up as R1–R11 describe, confirmed by node queries
      on `board/verify/board_seed1.tscn`
- [ ] The zone panels behave as R12–R16, confirmed mid-drag by node queries
- [ ] Rims follow R17–R21 across stage, commit, reveal and unstage
- [ ] NSC-48's three acceptance boxes are checked (R22–R24)
- [ ] NSC-50's four items are fixed (R25–R28), and the Pause → Concede run passes 10
      times out of 10 (R29, closing NSC-49)
- [ ] `make check` is green and the seed-1 autoplay line is unchanged (R30)
- [ ] Two screenshots: a card held, and a drag with glowing zones and rimmed staged cards
      (C8)
- [ ] Constitution Check passes (see plan)
- [ ] Spec, plan and tasks signed off by Ben and committed before implementation begins
