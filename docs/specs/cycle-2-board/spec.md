---
type: spec
tags: [spec, cycle-2-board, board]
status: approved
related: ["[[specs/cycle-2-board/plan]]", "[[specs/cycle-2-board/tasks]]", "[[specs/cycle-1-match-engine/spec]]", "[[planning/phase-3-game-loop]]", "[[planning/phase-1-tech-stack]]"]
created: 2026-11-03
updated: 2026-11-03
uid: 423d9379-b409-4570-b445-db2ed4a39bfb
linear: https://linear.app/night-science-llc/project/cycle-2-board-b50bca125334
supersedes:
---

# Spec: Cycle 2 — the board

**Slug:** `cycle-2-board`  ·  **Change type:** scene  ·  **Status:** approved (Ben, 2026-11-03, three rounds; signed off 2026-11-03)  ·  **Runs as:** milestone `DC-03 board` (DC-02 was hardening)

Cycle 2 puts the cycle-1 engine on screen: a 3D table where Ben plays a full match
against the greedy bot on desktop by dragging cards from his hand onto the shared board.
Input goes through an in-house pointer shim so the same drag works with a mouse now and
with touch at the iOS milestone that follows (D8).

## Intent

After cycle 2, launching the game opens a match against the greedy bot on a 3D table:
Ben drags cards from his hand onto his row of the shared board within the turn's energy,
commits, watches every engine event play as a tween, and plays on to a match-end panel
with a Rematch button; a `--autoplay` run plays the same table bot-vs-bot and prints a
result line that matches the engine's.

## Non-goals

- No iOS or Simulator build, export preset work or signing (C1; the next milestone cycle).
- No card art, foil or shader work; placeholder faces only (C3).
- No tap action: a tap is recognised and ignored, reserved for a later use (C7).
- No title screen or menus other than pause and match end (C8).
- No skip or speed control for animations, other than `--autoplay`'s fixed 4× (C4, C11).
- No engine rule changes; the engine is consumed as cycle 1 and DC-02 left it.
- No sound, no settings, no save or resume, no turn timer.
- No pointer addon: the shim is project code, liftable later (C5).
- No screenshot beyond the two in C11, no recording in automated tests.

## Actors

- **Ben (player)**: always seat 0; drags, commits, pauses, concedes, rematches.
- **Greedy bot**: plays seat 1, and seat 0 too under autoplay; reads only its own seat's
  redacted view.
- **Engine**: the cycle-1 `MatchEngine`, the single source of truth for rules.
- **Board**: the scene that draws the table from seat 0's view and events, runs the
  animation queue and turns drags into commits.
- **Pointer shim**: turns mouse and touch into one press, drag, release and cancel
  stream with camera hit tests.
- **Orchestrator**: runs `make check` and drives the Godot MCP at verification.

## Requirements (EARS)

### Start, seats and seeds

- R1. When the main scene starts, it shall print the `Engine smoke:` line, then open the
  board with a new match, then print `Main ready`.
- R2. The board shall seat the player at seat 0 and drive seat 1 with the greedy bot.
- R3. The board shall take the match seed from a `--seed=N` user argument when one is
  given, and otherwise from the clock.
- R4. Where autoplay is on (the `--autoplay` user argument or the autoplay verification
  scene), the board shall let the greedy bot play seat 0 as well and shall run every
  animation at 4× speed.
- R5. When a match ends, the board shall print one line
  `Board: match ended seed=<n> winner=<0|1> wins=<a>-<b> rounds=<n> end=<reason> actions=<n>`,
  with the same fields and values the engine smoke line uses for that seed.

### Hidden information

- R6. The board shall draw the table only from seat 0's redacted view and seat 0's
  redacted events; only the seat-1 bot (and the seat-0 bot under autoplay) shall read
  any other view.

### Table (R8 of Phase 3)

- R7. The board shall show the player's hand as a face-up fan at the bottom, the
  opponent's hand as a face-down fan at the top, and one shared board with the
  opponent's row above the player's row.
- R8. The board shall show no deck or discard pile: drawn and dealt cards shall enter
  from off-screen on one side, and cleared or burned cards shall leave off-screen on the
  opposite side.
- R9. Each card face shall show the card's placeholder name, cost and power as text, and
  every card back shall show one shared plain design.
- R10. The HUD shall show both board scores, four round-win pips per seat, the round and
  turn, the energy left this turn, a Commit button and a pause button.

### Staging and commit (C2, C9, C10)

- R11. While the player is awaited and no animation is playing, the board shall let the
  player drag a hand card onto the player's board row to stage it, and drag a staged card
  back to the hand to unstage it.
- R12. When a card is dropped on the player's row, the board shall insert it at the
  release position; the row's left-to-right order shall be the commit and reveal order.
- R13. While the player is awaited, the board shall let the player drag a staged card
  along the row to reorder it.
- R14. If a card dropped on the player's row costs more than the energy left, then the
  board shall refuse the drop, return the card to the hand and flash the energy readout.
- R15. While cards are staged, the energy readout shall show the turn's energy minus the
  staged cards' total cost.
- R16. When the player presses Commit, the board shall submit one commit of the staged
  cards in row order; while nothing is staged the button shall read Pass and submit an
  empty commit.
- R17. If the engine rejects a commit the board submitted, then the board shall report an
  error and return the staged cards to the hand.
- R18. While the player is not awaited or an animation is playing, the board shall
  ignore drags on the player's cards and shall disable Commit.
- R19. The board shall let the player reorder the hand fan by drag, with no effect on the
  engine.
- R20. When the player taps a card (releases before the drag threshold), the board shall
  leave the table unchanged.

### Pointer shim (C2, C5)

- R21. The pointer shim shall turn mouse events (real on desktop, emulated from the first
  touch on iOS) into one stream of press, drag start, drag move, release, tap and cancel,
  each with a viewport position and the object under the camera ray.
- R22. The pointer shim shall track whether a press is held itself and shall not rely on
  an event's button mask.
- R23. The pointer shim shall act once per physical touch, ignoring the raw touch event
  that duplicates an emulated mouse event.
- R24. The pointer shim shall start a drag only after the pointer moves more than the
  drag threshold, measured in points and converted to viewport units by the screen scale.
- R25. If a second touch begins, a release arrives at (-1, -1), or the application loses
  focus while a press is held, then the pointer shim shall emit cancel instead of
  release.
- R26. When a drag is cancelled, the board shall return the card to the collection it
  came from and stage nothing.
- R27. Where a drag comes from touch, the board shall hold the dragged card above the
  touch point by a lift offset in points.
- R28. Where the pointer is a real mouse, the board shall show the hover pop on the hand
  card under it; where the pointer is emulated from touch, the board shall show no hover.

### Card3D (C6)

- R29. The patched Card3D DragController shall take its input only from the pointer shim
  and shall not depend on physics picking or `mouse_entered` / `mouse_exited`.
- R30. The Card3D patch shall be recorded line by line in
  `godot/addons/THIRD_PARTY_LICENSES.md`.

### Animation (C4)

- R31. The board shall play seat 0's events in engine order, each as a tween, starting
  the next only when the previous one finishes.
- R32. When a card is dealt or drawn, the board shall sweep it in from the entry side
  into that seat's hand fan, face up for the player and face down for the opponent.
- R33. When a card is burned, the board shall sweep it in from the entry side and
  straight off the exit side.
- R34. When the opponent commits, the board shall slide that many face-down cards from
  the opponent's fan onto the opponent's row, so the player sees the count before
  committing.
- R35. When a card is revealed, the board shall flip that card face up on its row in the
  engine's reveal order and add its power to that side's displayed score.
- R36. When a turn ends, the displayed scores shall equal the turn-end event's scores.
- R37. When a round ends, the board shall light the winner's next round-win pip; when the
  next round starts, it shall sweep both rows and both hands off the exit side before the
  deal.
- R38. When the bot is about to commit, the board shall wait 0.6 s (scaled by the
  animation speed) before animating it.
- R39. While the animation queue holds steps, the board shall lock player input.

### Pause, match end, rematch (C8)

- R40. When the player presses the pause button (or Escape on desktop), the board shall
  open a pause menu with Resume and Concede.
- R41. When the player chooses Concede, the board shall submit a concede for seat 0 and
  play the match end.
- R42. When the match ends, the board shall keep the final table on screen (cycle-1 C15)
  and show a result panel with the winner, both round-win counts, the end reason and a
  Rematch button.
- R43. When the player presses Rematch, the board shall clear the table and start a new
  match.

### Gate

- R44. If the board cannot load the card data or the engine rejects a bot action, then
  the board shall push an error so the boot stage of `make check` fails.
- R45. When the boot stage runs the main scene headless, the board shall load and start
  its match without printing an error line.

## Clarifications (Ben, 2026-11-03)

| # | Question | Decision |
|---|---|---|
| C1 | Cycle finish line | 1a: a full match against the greedy bot on desktop, start to match end, Ben always seat 0; iOS is the next milestone cycle (D8) |
| C2 | How the player commits | 2b, "with full investigation in best practices": drag from hand to board. Research (2026-11-03, against Godot 4.6 source): touch arrives twice (emulated mouse first, then raw touch); Card3D's hover and drop-zone detection only fire on mouse events; iOS cancels arrive as a release at (-1, -1) with no cancel flag, which unpatched Card3D would treat as a drop; Godot's MCP synthesizes motion with no button mask; GDTIM is stale and blind to 3D collisions. Best practice: one in-house shim reading the mouse stream, its own synchronous raycast, raw touch only for cancels, thresholds and lift in points |
| C3 | Card look | 3a: placeholder faces (name, cost, power as text) and one plain back; no art, no foil |
| C4 | Animation | 4a: every event is a short sequenced tween; input locked while the queue plays; no skip |
| C5 | Is the touch shim an addon? (Ben's question) | 1a: project code in `godot/input/`, typed and gated with its own suite, no board dependency, liftable into an addon later. An addon under `godot/addons/` would escape lint and the typed-strict parse and would need a constitution change |
| C6 | Card3D's DragController | 2b: patch it to take shim events, recorded in `THIRD_PARTY_LICENSES.md`, rather than replace it |
| C7 | What a tap does | 3b: nothing for now. Ben: "Tap will have a use later" |
| C8 | Start and end | 4a: the board is what the main scene opens; seed from the clock or `--seed=N`; result panel with Rematch; concede in a pause menu; smoke and `Main ready` lines kept |
| C9 | Unaffordable drop | 1a: refused; the card springs back and the energy readout flashes; unaffordable cards stay draggable |
| C10 | Staged order | 2a: left to right on the row is commit and reveal order; reorder by drag within the row; a drop inserts at the release point |
| C11 | Proof of a full match | 3a: `--autoplay` (bot plays seat 0, 4× speed) prints a `Board: match ended …` line that must match the engine's result for the seed; two screenshots in all (a mid-turn drag with cards staged, and the match-end panel); gdUnit4 covers the shim and the event-to-step logic headless |
| C12 | Defaults (stated round 3, no objection) | Fixed landscape camera; Theme-based HUD (D7); hover pop only for a real mouse; 0.6 s bot think delay; hand fan reorderable (cosmetic); Ben always seat 0 |

## Scenarios

- **Given** `make check`, **when** the boot stage runs, **then** the log holds the
  `Engine smoke:` line, then `Main ready`, and no error line.
- **Given** seed 1 under autoplay, **when** the match ends, **then** the runtime log
  holds `Board: match ended seed=1 winner=0 wins=4-0 rounds=4 end=wins actions=56`,
  matching the pinned engine smoke result.
- **Given** turn 3 with the player awaited and nothing staged, **when** the player drags
  a cost-2 card onto the row, **then** the card sits on the row, the energy readout
  shows 1 and the button reads Commit.
- **Given** 1 energy left, **when** the player drops a cost-2 card on the row, **then**
  the card returns to the hand, the energy readout flashes and still shows 1.
- **Given** two staged cards A then B, **when** the player drags B to the left of A and
  commits, **then** the commit names B then A, and the player's reveals run B before A.
- **Given** the opponent commits first with two cards, **when** its commit animates,
  **then** two face-down cards sit on the opponent's row and the opponent's fan holds two
  fewer cards.
- **Given** a drag in progress, **when** a second touch begins (or the app loses focus),
  **then** the card returns to where it came from and nothing is staged.
- **Given** a press on a hand card, **when** it is released before moving past the drag
  threshold, **then** the table is unchanged.
- **Given** a reveal sequence, **when** each card flips, **then** its side's displayed
  score rises by its power, and after the last flip both scores equal the turn-end
  event's scores.
- **Given** any point in a match, **when** the player concedes from the pause menu,
  **then** the result panel shows the bot as winner with reason concede over the
  unchanged final table.
- **Given** the result panel, **when** the player presses Rematch, **then** the table
  clears and a new round 1 deals.

## Data touched

- New: `godot/input/` (pointer shim), `godot/board/` (board scene, card scene, HUD,
  theme, pure helpers, verification scenes), new suites under `godot/tests/`, this spec
  set.
- Changed: `godot/main.gd`, `godot/main.tscn`, `godot/addons/card_3d/scripts/drag_controller.gd`
  (recorded patch, C6), `godot/addons/THIRD_PARTY_LICENSES.md`, `scripts/check.sh`
  (boot passes a fixed seed), `docs/specs/specs-moc.md`, `docs/planning/cycles.md`.
- Read only: `godot/engine/*`, `docs/planning/*`, `CLAUDE.md`.
- Never: the rest of `godot/addons/*`, `docs/.obsidian/`, `.env`, `godot/.godot/`,
  `godot/reports/`, the archive.

## Definition of done

- [ ] Every requirement R1–R45 is covered by a named gdUnit4 case, the boot log, the
      autoplay result line or a step of the MCP verification.
- [ ] `make check` is green with the new suites passing.
- [ ] The seed-1 autoplay run prints the golden `Board: match ended …` line.
- [ ] Two Godot MCP screenshots: a mid-turn drag with cards staged, and the match-end
      panel (C11).
- [ ] The Card3D patch is recorded in `THIRD_PARTY_LICENSES.md`.
- [ ] Constitution Check passes (see plan).
- [ ] Spec, plan and tasks signed off by Ben (2026-11-03) and committed before implementation begins.
