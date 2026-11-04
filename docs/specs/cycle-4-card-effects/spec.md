---
type: spec
tags: [spec, cycle-4-card-effects, engine, board]
status: approved
related: ["[[specs/cycle-4-card-effects/plan]]", "[[specs/cycle-4-card-effects/tasks]]", "[[specs/cycle-1-match-engine/spec]]", "[[specs/cycle-2-board/spec]]", "[[specs/cycle-3-board-feedback/spec]]", "[[planning/phase-3-game-loop]]", "[[planning/phase-1-tech-stack]]", "[[planning/cycles]]"]
created: 2026-11-03
updated: 2026-11-03
uid: 11960434-be6a-4a44-9a97-15de617a8612
linear:
supersedes:
---

# Spec: Cycle 4 — card effects

**Slug:** `cycle-4-card-effects`  ·  **Change type:** engine + scene  ·  **Status:** approved (Ben, 2026-11-03, five rounds; signed off 2026-11-03)  ·  **Runs as:** milestone `DC-05 card-effects`

Cycle 4 changes how a turn scores and gives cards effects. Each row is an ordered line
that persists through the round; new cards are staged at any slot between played cards.
When both seats have committed, a cursor walks the two rows left to right, alternating
seats card by card: its pulse flips an unrevealed card and scores every card it touches.
Cards carry a **flat** value and a **bonus**: bonus raises a running multiplier before the
card's flat is multiplied in, so order is the game. Ten of the twenty cards carry an
effect, four of which prompt the player to choose a target.

## Intent

After cycle 4, Ben plays a match whose rows are ordered lines, stages cards between his
played cards, watches his commit flip face down as one, sees the cursor walk both rows
and the scores climb pulse by pulse, answers targeting prompts by tapping glowing cards,
and reads each card's flat, bonus and rules text on its face; the greedy bot does the
same through a pure preview, and every match, prompts and random destroys included,
replays from its log.

## Non-goals

- No "on opponent reveal" card. The trigger exists in the framework and has a test, but
  no card in the deck uses it (C13).
- No card art, foil, sound or iOS build (D8). Faces stay text.
- No deck builder, no second deck, no change to the mirror match or the 20-card cost
  table (C14).
- No cursor ring or separate cursor object on the table: the pulsed card lifts and
  settles (C9).
- No cancel on a prompt, no targeting arrow, no target chosen at staging time (C10).
- No animation skip or speed control beyond autoplay's 4×.
- No rearranging of played cards by drag; only an effect moves a played card (Ben).
- No change to rounds, round wins, sudden death, concede, hand cap, deal or draw rules
  except where an effect says so.

## Actors

- **Ben (seat 0)**: stages, commits, answers prompts, picks cards up to read them.
- **The greedy bot (seat 1, and seat 0 under autoplay)**: chooses commits and prompt
  answers from its redacted view through the engine's preview.
- **The engine**: owns rows, the walk, effects, prompts, randomness and the log.
- **The board**: plays engine events as tweens and owns staging, the commit flip, the
  walk's pulses and the prompt UI.
- **The orchestrator**: runs `make check`, re-pins the golden line and drives the Godot
  MCP at verification.

## Requirements (EARS)

### Cards (C14)

- R1. The engine shall load each card with an id, a name, a cost, a flat value, a bonus
  and at most one effect, the effect carrying a trigger, a verb, its parameters and its
  rules text.
- R2. If the card data does not hold exactly 20 cards with the Phase 3 cost table
  (4×1, 4×2, 3×3, 3×4, 2×5, 2×6, 2×7), unique ids, flat within 0..cost+2, bonus within
  0..2 and only known effect verbs and triggers, then the engine shall report a load
  failure and refuse to start a match.
- R3. The card data shall be the table in the plan: ten vanilla cards and ten effect
  cards (C14).

### Rows and positional commits (Ben, C1)

- R4. The engine shall keep each seat's board as an ordered row that persists until the
  round ends; a card's slot shall change only through an effect.
- R5. The engine shall accept a commit naming zero or more cards from the acting seat's
  hand, each with the slot it will occupy in that seat's row once all the committed cards
  are in place, slots strictly increasing left to right.
- R6. If a commit names a slot outside the row that results, repeats a slot, or lists
  slots out of order, then the engine shall reject it with a failure code, leaving the
  state and the log unchanged.
- R7. While the second committer is awaited, that seat's view shall show the first
  committer's face-down count and the slots those cards will occupy, and shall not show
  their identities.
- R8. When the second committer commits, the engine shall place both commits into their
  rows at their slots before anything scores.

### Energy

- R9. While a turn is in progress, each seat's energy budget shall equal the turn number
  plus any energy an effect carried into this turn for that seat.
- R10. If a seat's commit costs more than that seat's budget, with the leftmost new card
  costing 0 when an effect granted it, then the engine shall reject the commit as over
  budget.

### The walk (C2, C3, C4)

- R11. When both seats have committed, the engine shall start a walk: both board scores
  reset to 0 and each seat's multiplier to 1.
- R12. During a walk, the cursor shall pulse the turn's first committer's leftmost
  unpulsed card, then the second committer's, alternating card by card from left to
  right; when one row has no unpulsed card left, the other row's remaining cards shall be
  pulsed in order.
- R13. When the cursor pulses an unrevealed card, the engine shall reveal it and fire its
  on-reveal effect before scoring it.
- R14. When the cursor pulses a card, the engine shall add the card's effective bonus to
  its seat's multiplier, then add the card's effective flat times that multiplier to the
  seat's score, and shall emit the amounts and the new score.
- R15. When a card has been scored, the engine shall fire its on-score effect.
- R16. The engine shall pulse each card at most once per walk, whatever moves or
  destroys cards during it.
- R17. When the walk ends, the engine shall set each seat's board score to its walk total
  and shall record the turn winner from those totals, as cycle 1 R16 did from power.
- R18. While an ongoing effect's card is revealed on a row, the effect shall apply from
  that card's reveal onward within the walk and in every later walk of the round.

### Effects (C11, C12, C13)

- R19. The engine shall support four triggers: on reveal, on opponent reveal, on score
  and ongoing; the deck shall use the first, third and fourth.
- R20. The engine shall implement these ten effects, each on one card of the plan's
  table:
  - draw 1 card;
  - draw 2 cards, then prompt the owner to discard 1 from hand;
  - the first card the owner plays next turn costs 0;
  - swap places with a card on the owner's board (prompt);
  - switch a chosen card's flat and bonus (prompt, any revealed card on either board,
    this card included);
  - the opponent's next revealed card has bonus 0;
  - return a chosen card to its owner's hand at the end of this turn (prompt, any other
    revealed card on either board);
  - destroy a random card on the opponent's board;
  - on score: this card's flat rises by 1 after each time it scores;
  - ongoing: the owner's unspent energy at turn end carries into the owner's next turn.
- R21. Every stat change made by an effect (flat, bonus, the switch, bonus set to 0)
  shall attach to that card instance and shall last until the round clears the boards or
  the card leaves the board.
- R22. When the opponent's bonus-0 mark is set, it shall apply to the first card that
  opponent reveals afterwards, in this walk or a later one, and shall then be spent;
  setting it again before it is spent shall not stack.
- R23. When a card is destroyed, it shall leave its row at once and shall not be pulsed
  later in that walk.
- R24. When a turn ends, every card marked for return shall leave the board for its
  owner's hand; if that hand holds 7 cards, then the card shall be burned instead.
- R25. When a card is drawn or returned to a hand at the cap, the engine shall burn it
  and emit a burn event, as cycle 1 R12 does.
- R26. When an effect's target set is empty, the effect shall do nothing and the engine
  shall emit that it fizzled.
- R27. The random card in "destroy a random card" shall be drawn from the engine's
  seeded stream, so a replay destroys the same card.

### Prompts (C7, C10)

- R28. When an effect needs a choice and two or more targets are eligible, the engine
  shall pause the walk, emit a prompt naming the choosing seat, the effect's card, its
  rules text, the zone and the eligible targets, and shall await a choice action from
  that seat.
- R29. When exactly one target is eligible, the engine shall choose it without a prompt
  and emit the choice.
- R30. A target shall be named by zone (own hand, own board, opponent hand, opponent
  board) and position in that zone, so a face-down card can be chosen without its
  identity.
- R31. If a choice comes from a seat that is not the prompted one, names a zone or
  position that is not eligible, or arrives when no prompt is open, then the engine shall
  reject it with a failure code, leaving the state and the log unchanged.
- R32. When a choice is accepted, the engine shall log it, apply the effect, and resume
  the walk where it paused.
- R33. The engine shall impose no time limit on a prompt (cycle 1 R6).
- R34. The prompt and the choice events, as the non-choosing seat sees them, shall not
  reveal the identity of any card in a hand.

### Bot (C8)

- R35. The engine shall offer a pure preview that scores a hypothetical commit for a
  seat as the walk would, without changing state, consuming randomness, or logging; in a
  preview, the opponent's face-down cards count as absent, a nested prompt takes its
  first eligible target, and a random pick takes the opponent's lowest-flat card.
- R36. The bot shall choose its commit by previewing every legal card set in two orders
  (bonus first, flat first) at the row's left end and at its right end, keeping the
  highest own-minus-opponent score, ties broken by its seed.
- R37. The bot shall answer a prompt by previewing each eligible target and choosing the
  best own-minus-opponent score, ties broken by its seed.
- R38. The bot shall never return an action the engine rejects, and its choice shall
  depend only on its seed and its view.

### Log and replay

- R39. The action log shall carry a new format and rules version, record commits with
  their slots and every accepted choice, and replay to an equal full state.
- R40. If a log of the previous format or rules version is replayed, then the replay
  shall fail with a version mismatch, as cycle 1 R34 requires.

### Board: faces and staging (C9, Ben)

- R41. Each card face shall show its name, cost, flat, bonus and rules text, readable
  when the card is picked up (DC-04 lift).
- R42. When an effect changes a card's shown flat or bonus, the board shall update the
  number and pulse it.
- R43. While the player is awaited, the board shall let the player stage a hand card at
  any slot of the player's row: before, between or after played cards, opening a gap at
  the pointer.
- R44. The board shall not let the player drag a played card.
- R45. When the player presses Commit, the board shall submit the staged cards with the
  slots they occupy on the row.
- R46. When the player's commit is accepted, the board shall flip the staged cards face
  down together, leaving them in their slots.
- R47. When the opponent commits, the board shall slide that many face-down cards from
  the opponent's fan into the slots the engine named.
- R48. The DC-04 rim shall be retired; a face-down card is a committed card.
- R49. The energy readout shall show the seat's budget for the turn, including carried
  energy, and shall mark when the first card is free.

### Board: the walk (C9, C15)

- R50. When a walk starts, the board shall set both displayed scores to 0 and show each
  side's multiplier at 1.
- R51. When the cursor pulses a card, the board shall lift and settle that card; a card
  already revealed shall pulse in about 0.12 s, and a first-time flip shall keep the
  0.35 s reveal beat and its gap.
- R52. When a card is scored, the displayed score and multiplier of its side shall change
  to the engine's values for that pulse.
- R53. When an effect destroys, moves, returns or discards a card, the board shall play
  it: the card sweeps off, slides to its new slot, flies to its owner's hand (face up for
  the player, face down for the opponent), or leaves the hand off the exit side.
- R54. If the next step would move, flip, remove or restat the held card, then the board
  shall put it down first (DC-04 R9 extended).

### Board: prompts (C10, C16)

- R55. When the player is prompted, the board shall pause the walk on screen, show a
  banner with the effect's rules text, glow every eligible card (face-down eligible cards
  glow as backs) and dim the rest.
- R56. While a prompt is open, a tap on a glowing card shall submit that choice; a tap on
  a non-eligible face-up card shall pick it up to read, and the next tap shall put it
  down; drags, Escape and the HUD buttons other than Pause shall do nothing.
- R57. When a choice is accepted, the board shall clear the banner, glows and dimmer and
  let the walk continue.
- R58. When the bot's choice plays, the board shall glow the chosen card for a beat
  before the effect's step.

### Unchanged and gate

- R59. The boot log shall still carry `Engine smoke:` then `Main ready`, and the autoplay
  board shall print `Board: match ended …` with the fields of cycle 2 R5; the seed-1
  values are re-pinned by the orchestrator at verification.
- R60. Every cycle-1, cycle-2 and cycle-3 requirement stays in force except: cycle-1 R5
  (action kinds), R13 (energy), R15–R16 (reveal and scoring), R28 (view fields), R31
  (log), cycle-2 R12–R13 (row order and reorder), R16 (commit shape), R35 (reveal and
  score), and cycle-3 R17–R21 (the rim), which this spec replaces.

## Clarifications (Ben, 2026-11-03)

| # | Question | Decision |
|---|---|---|
| C1 | Round 1: effect kinds, deck, board features, bot | Ben, in his own words: "Let's board features first. After a player commits their board, the staged (but not visible) cards should flip over all at once. Then, they are revealed in order. This avoids the weird lack of distinction between staged and revealing. Next, order matters. Score is calculated from left to right. When the turn starts, a 'cursor' will start on the leftmost card showing a kind of 'pulse' animation, then the opponent's cursor goes, then yours again. When a cursor 'pulses' an unrevealed card, it is revealed. The cursor's pulse is what scores the card. Scoring a card adds its score to your totals. Players can stage cards before, between, or after already-played cards. Players cannot rearrange played cards (without the benefit of a card effect of some kind). Some basis for triggers: on reveal, on opponent reveal, on score, ongoing. Additionally, we want to add 'bonus' as a property to cards. Like in Balatro, cards have flat and multiplicative values, these cards will, too. This allows us to make score order way more important: it's better to get bonus value as high as possible as early as possible. Bonus is always added before flat score." Round 1's Q1, Q2 and Q4 were superseded by rounds 2–5 |
| C2 | Bonus and flat math | 1a: a running multiplier per seat, 1 at the start of each walk; a pulse adds the card's bonus to the multiplier, then its flat × multiplier to the score |
| C3 | Recompute or accumulate | 2a: each walk starts both scores at 0 and pulses every card on both rows; the round is decided by turn 7's walk; "on score" fires on every pulse |
| C4 | Walk order | 3a: the first committer pulses first; cursors alternate card by card, each row left to right; when one row runs out the other finishes; a pulse flips an unrevealed card and scores it in the same beat |
| C5 | Finish line | 4a: everything this cycle under `cycle-4-card-effects` (scoring model, board, framework, effects, deck). Ben: "and more after this" |
| C6 | Card stats and deck | 1a, "but defer until we have a list of effects to implement"; settled by C14 |
| C7 | Effect targets | 2c, Ben: "we need a UI for selecting cards when prompted; your hand, enemy hand, your board, enemy board, and possibly more in the future. Take inspiration from SNAP and suggest one" |
| C8 | Bot | 3a: pure engine preview; subsets × two orders × two ends; ties by seed |
| C9 | Board look | 4b: no cursor ring; the pulsed card lifts and settles; faces show flat, bonus and rules text; commit flips the staged cards together |
| C10 | Prompt UI | 1a: the walk pauses; a banner reads the effect text; eligible cards glow (DC-04 drop-zone look), the rest dim (DC-04 dimmer); face-down eligible cards glow as backs and are chosen by position; one tap decides; no cancel; exactly one eligible is auto-chosen; none fizzles; the bot's pick glows for a beat |
| C11 | Effect list | 2a: all ten Ben listed, with the readings in R20–R22 |
| C12 | "Return at end of round" vs Phase 3 R3 | 3a, Ben: "correct. it should be at the end of the turn, not round" |
| C13 | Unused triggers | 4b: ship only the triggers the list uses; "on opponent reveal" stays in the framework with no card |
| C14 | The 20-card table | 1a: the plan's table; loader checks the cost table, unique ids, flat 0..cost+2, bonus 0..2, known effects; golden line re-pinned at verification |
| C15 | Walk pace | 2a: two speeds, about 0.12 s for an already-revealed pulse and the 0.35 s reveal beat for a first flip |
| C16 | Pick-up during a prompt | 3a: a tap on a glowing card chooses; a tap on a non-eligible face-up card lifts it; the prompt waits |
| C17 | Proof | 4a: three screenshots (a staged card between played cards with faces showing flat, bonus and text; a prompt mid-walk; a lifted effect card), `make check`, the re-pinned golden line, node queries for the flip, the pulse order and an answered prompt, and a 50-seed sweep replaying logs with prompts and random destroys |
| C18 | Defaults stated in rounds 2–5, no objection | The opponent sees where face-down cards sit; nothing scores until both have committed; an ongoing effect counts from its card's reveal onward within a walk; the rim retires; swap and the free card act on the owner's board or next commit; switch and the bounce pick any revealed card on either board; random destroy hits the opponent's board; discard picks from the owner's hand and goes to the burn pile |

## Scenarios

- **Given** two cards [flat 3, bonus 1] and [flat 4, bonus 0] on a row, **when** the
  bonus card is left of the other, **then** the walk scores 14; reversed, 10 (C2).
- **Given** turn 3 with two played cards on the player's row, **when** Ben drops a hand
  card between them and commits, **then** the commit names slot 1, the three cards flip
  face down together, and the walk pulses them in row order.
- **Given** the first committer's row holds 3 cards and the second's 1, **when** the walk
  runs, **then** the pulse order is first-0, second-0, first-1, first-2.
- **Given** the opponent revealed the bonus-0 card last turn, **when** Ben's first new
  card flips this turn, **then** its bonus is 0 for the rest of the round and the mark is
  spent.
- **Given** the swap card flips with three other cards on its row, **then** a prompt
  names the three; **when** Ben taps one, **then** the two cards exchange slots, the walk
  resumes, and neither is pulsed twice.
- **Given** the swap card flips with no other card on its row, **then** no prompt opens
  and the effect fizzles.
- **Given** the destroy card flips with the opponent's row empty, **then** it fizzles;
  with two cards there, **then** the seeded stream picks one and it sweeps off.
- **Given** the return card picks a card, **when** the turn ends, **then** that card flies
  to its owner's hand (burned if the hand holds 7), and next turn's budget is unchanged.
- **Given** the energy card is on Ben's row and he spends 2 of 4, **when** turn 5 starts,
  **then** his budget reads 7.
- **Given** the free-card card flipped last turn, **when** Ben stages a cost-3 card
  leftmost with 2 energy, **then** the drop is accepted and the commit passes.
- **Given** the on-score card has been pulsed three times, **then** its shown flat is base
  + 3.
- **Given** the bot is prompted, **then** its choice glows for a beat before the effect
  plays, and the log holds the choice.
- **Given** a prompt is open, **when** Ben taps a face-up opponent card that is not
  eligible, **then** it lifts; **when** he taps again, **then** it goes back and the prompt
  still waits.
- **Given** 50 seeds, **when** each plays bot vs bot, **then** every match ends, no view
  or prompt leaks a hidden id, and every log replays to an equal state.
- **Given** a cycle-1 log (format 1), **when** replayed, **then** the replay fails with a
  version mismatch.

## Data touched

- New: engine modules for effects, the walk, choices and the preview under
  `godot/engine/`; new suites under `godot/tests/`; board prompt UI and prompt rules
  under `godot/board/`; this spec set.
- Changed: `godot/engine/data/cards.json`, `card_def.gd`, `card_db.gd`, `match_engine.gd`,
  `match_state.gd`, `seat_view.gd`, `match_event.gd`, `engine_action.gd`,
  `engine_error.gd`, `legal_plays.gd`, `match_rules.gd`, `action_log.gd`,
  `bot/greedy_bot.gd`; `godot/board/board.gd`, `board.tscn`, `board_card.gd`,
  `board_card.tscn`, `board_hud.gd`, `board_hud.tscn`, `board_step.gd`, `board_steps.gd`,
  `staging.gd`, `lift_rules.gd`, `board_drag_strategy.gd`; `godot/main.gd` (smoke line
  unchanged in shape); `godot/tests/test_full_match.gd` (golden re-pin);
  `docs/specs/specs-moc.md`; `docs/planning/cycles.md` at `/cycle test`.
- Read only: `godot/input/*`, `scripts/*`, `docs/planning/*`.
- Never: `godot/addons/*` (no patch expected this cycle), `docs/.obsidian/`, `.env`,
  `godot/.godot/`, `godot/reports/`, the archive.

## Planning amendments

This cycle amends two Phase 3 decisions, by Ben's rounds 1–2: R2's "round score = sum of
power on your side" becomes the ordered walk with bonus (R11–R17), and R5's "unspent
energy is lost" gains the energy-carry effect as its one exception (R20). The
orchestrator may append both to [[planning/phase-3-game-loop]] at `/cycle test`.

## Definition of done

- [ ] Every requirement R1–R60 is covered by a named gdUnit4 case, the boot log, the
      autoplay line or a step of the MCP verification.
- [ ] `make check` is green; the test stage stays under 15 s.
- [ ] The seed-1 golden line is re-pinned in `test_full_match.gd`, `scripts/check.sh`'s
      boot expectations and the cycles log, and the autoplay board prints the same line.
- [ ] The 50-seed sweep replays every log, prompts and random destroys included.
- [ ] Three screenshots (C17).
- [ ] Constitution Check passes (see plan).
- [x] Spec, plan and tasks signed off by Ben (2026-11-03); committed before implementation begins.
