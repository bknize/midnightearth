---
type: spec
tags: [spec, cycle-1, match-engine]
status: approved
related: ["[[specs/cycle-1-match-engine/plan]]", "[[specs/cycle-1-match-engine/tasks]]", "[[planning/phase-3-game-loop]]", "[[planning/phase-1-tech-stack]]", "[[specs/cycle-0-scaffolding/spec]]"]
created: 2026-11-02
updated: 2026-11-02
uid: 1c160661-e877-403f-9e89-d295daee6d13
linear:
supersedes:
---

# Spec: Cycle 1 — match engine

**Slug:** `cycle-1-match-engine`  ·  **Change type:** engine  ·  **Status:** approved (Ben, 2026-11-02, four rounds; signed off 2026-11-02)

Cycle 1 builds the pure match engine that cycle 2's board scene will call. It encodes
the MVP rules R1–R9 from [[planning/phase-3-game-loop]] and the greedy bot, under
`godot/engine/`, with gdUnit4 suites under `godot/tests/`. Nothing is drawn on screen.

## Intent

After cycle 1, a caller can start a seeded match, apply commit and concede actions for
either seat, read an ordered event list and a per-seat redacted view after every action,
ask the greedy bot for a move, and replay the action log to the identical state, all
proven by gdUnit4 suites and a bot-vs-bot match that runs at boot.

## Non-goals

- No scenes, cards on screen, UI, HUD, animation or art. `main.tscn` is unchanged; only
  `main.gd` gains a smoke run that prints one line.
- No save or resume (C13). The log format makes it possible later; nothing writes to disk.
- No configurable rules (C10). Round count, turn count, hand sizes and the card list are
  constants.
- No turn timer or match clock (C10, C13).
- No lookahead bot, deck builder, card effects or mulligan (post-MVP, Phase 3).
- No screenshot and no screen recording in automated tests (C12).
- No network, backend or multiplayer transport (D4).

## Actors

- **Caller**: a gdUnit4 suite, the main scene's smoke run, and (cycle 2) the board
  scene. It constructs the match and submits actions for both seats.
- **Seat 0 and seat 1**: the two players. The engine does not know which is human.
- **Greedy bot**: a pure decision function that reads one seat's redacted view.
- **Engine**: owns match state, randomness, rules, events and the action log.
- **Orchestrator**: runs `make check` and reads the boot log at verification.

## Requirements (EARS)

### Determinism and surface

- R1. The engine shall derive every random outcome (per-round shuffles and coin flips)
  from the match seed supplied at construction.
- R2. The engine shall not use the global random generator, wall-clock time, the
  filesystem other than its own card data file, or any scene-tree node.
- R3. The engine shall expose one entry point that applies an action and returns a
  result carrying success or a failure code, plus the ordered list of events the action
  caused (C1).
- R4. When an action is accepted, the engine shall advance the match to the next point
  that needs a seat's decision before returning, and shall include every event on the
  way (draws, burns, reveals, turn end, round end, round start, match end) in order.
- R5. The engine shall accept exactly two action kinds: a commit naming zero or more
  cards from the acting seat's hand in the order given, and a concede.
- R6. The engine shall impose no time limit; a match shall wait for a seat's action
  indefinitely (C10).

### Cards and deck

- R7. The engine shall load the 20-card list from one JSON data file (C7) holding, per
  card, an id, a placeholder name, a cost and a power.
- R8. If the card data does not hold exactly 20 cards with costs 4×1, 4×2, 3×3, 3×4,
  2×5, 2×6, 2×7, unique ids, and each power within cost to cost+2, then the engine shall
  report a load failure and shall refuse to start a match.
- R9. The engine shall give each seat its own copy of the 20 cards, each card instance
  with an id unique across both seats (C5).
- R10. The card powers shall be the table in the plan (C6).

### Rounds and turns (R1–R9 of Phase 3)

- R11. When a round starts, the engine shall shuffle each seat's 20 cards, deal each seat
  3, and clear both boards.
- R12. When a turn starts, the engine shall draw 1 card for each seat; if that seat
  already holds 7 cards, then the engine shall burn the drawn card instead and emit a
  burn event.
- R13. While a turn is in progress, the energy available to each seat shall equal the
  turn number (1–7), and unspent energy shall be lost at turn end.
- R14. When the first committer of a turn commits, the engine shall hold the cards face
  down and shall then await the second committer.
- R15. When the second committer commits, the engine shall reveal the cards alternating
  between the two commits, starting with the first committer's first card; when one
  commit runs out, the remainder of the other shall reveal in order.
- R16. When the reveal finishes, the engine shall set each seat's board score to the sum
  of power on its side and shall record the turn winner as the seat with the higher
  board score, or no winner on equal scores.
- R17. When turns 2 to 7 start, the engine shall make the previous turn's winner the
  first committer, and if the previous turn had no winner, then the previous first
  committer commits first again.
- R18. When turn 1 of a round starts, the engine shall make the most recent round
  winner of the match the second committer, looking past tied rounds and including
  sudden-death rounds; if no round has been won yet in the match, then the engine shall
  pick the first committer by a seeded coin flip (C9).
- R19. When turn 7 ends, the engine shall end the round: the seat with the higher board
  score wins it, and equal scores award no win.

### Match end

- R20. When a seat reaches 4 round wins, the engine shall end the match with that seat
  as winner and reason "wins".
- R21. When round 7 ends with neither seat at 4 wins, the engine shall end the match if
  one seat has more round wins (reason "rounds"), and otherwise shall start a
  sudden-death round.
- R22. When a sudden-death round is won, the engine shall end the match with that seat
  as winner and reason "sudden death"; when a sudden-death round ties, the engine shall
  start another.
- R23. When a seat concedes while the match is in progress, the engine shall end the
  match at once with the other seat as winner and reason "concede", whether or not it
  is the conceding seat's turn.
- R24. When a round ends, the engine shall emit a round-end event with the round number,
  both board scores, the winner or a tie, and both seats' round wins.
- R25. When the match ends, the engine shall emit a match-end event with the winner,
  the reason, both seats' round wins and the number of rounds played.

### Illegal actions (C2)

- R26. If an action comes from a seat that is not the one awaited, names a card not in
  that seat's hand, names a card twice, exceeds the turn's energy, is malformed, or
  arrives after the match ended, then the engine shall return a failure with a code
  from a fixed list, shall leave the state unchanged, and shall not log the action.
- R27. The engine shall not print, assert or push an error for an illegal action.

### Hidden information (C4)

- R28. The engine shall provide, for each seat, a redacted view holding that seat's own
  hand and face-down commit, both boards' revealed cards, the opponent's hand count and
  face-down commit count, both deck counts, both board scores, both round-win counts,
  the round, the turn, the energy, the phase and the awaited seat.
- R29. The redacted view and the per-seat event list shall not contain the identity of
  any card in the opponent's hand, deck, face-down commit or burn, nor the match seed or
  deck order.
- R30. The engine shall provide a full-state read, for tests and replay, that includes
  everything the redacted views omit.

### Action log and replay (C3)

- R31. The engine shall keep an action log holding a format version, a rules version,
  the match seed and every accepted action in order, and nothing derived.
- R32. The action log shall round-trip through JSON text without loss, including seeds
  larger than 2^53.
- R33. When a log is replayed from a fresh match, the engine shall reach a full state
  equal to the original's after the same number of actions, without running the bot.
- R34. If a replayed log holds an action the engine rejects, or names a different format
  or rules version, then the replay shall fail and report the index of the first bad
  action or the version mismatch.

### Bot (R7 of Phase 3, C8)

- R35. The bot shall read only a seat's redacted view plus its own seed, and shall
  return a commit action for that seat.
- R36. The bot shall choose, among the legal card sets for the turn's energy, one with
  the highest total power, breaking ties by its seeded randomness.
- R37. The bot's choice shall depend only on its seed and the view, so the same view
  and seed always give the same action.
- R38. The bot shall never return an action the engine rejects.

### Smoke run (C12)

- R39. When the main scene starts, it shall play one fixed-seed bot-vs-bot match through
  the engine and print one line starting `Engine smoke:` with the seed, the winner, the
  round wins, the rounds played and the end reason, before it prints `Main ready`.
- R40. If the smoke run cannot load the card data or a bot action is rejected, then the
  main scene shall report an error so the boot stage of `make check` fails.

## Clarifications (Ben, 2026-11-02)

| # | Question | Decision |
|---|---|---|
| C1 | How does a caller drive the engine? | 1a: one match object; apply an action, get a result with an ordered event list; read a snapshot any time |
| C2 | Illegal actions | 2a: failure result with a code from a fixed list, state unchanged, not logged, nothing printed |
| C3 | Randomness and the log | 3a: one match seed; an engine stream for shuffles and coin flips, the bot separate; the log holds seed and accepted actions only; replay never runs the bot; JSON round trip |
| C4 | Hidden information | 4a: a redacted view per seat; the bot reads only that view; a full-state read for tests |
| C5 | One deck or two copies | 1a: each seat has its own copy of the 20 cards, shuffled separately each round, with unique instance ids |
| C6 | Power table | 2a: the proposed table (bonuses +0/+1/+1/+2 for costs 1–2, +0/+1/+2 for 3–4, +0/+2 for 5–6, +0/+2 for 7) |
| C7 | Card data format | 3a: one JSON file under the engine, validated on load |
| C8 | Bot location and interface | 4a: under `godot/engine/bot/`, pure, takes a view and its seed, returns a commit; a shared legal-plays function |
| C9 | Turn 1 after a tied round | Ben (round 3, corrected round 4): "whoever won a round most recently goes second", looking past ties, sudden death included. Coin flip only when no round has been won yet. This replaces two Phase 3 defaults: "the loser of the previous round commits first" (same outcome when the last round was won) and "sudden-death turn 1 is a coin flip" |
| C10 | Configurable match length | Ben: "no". Rules are constants. The takeaway from "in PvE a human can put this game down and pick it up" is that there is no time limit |
| C11 | Test depth | 3a: suite per module, a fixed-seed bot-vs-bot match plus replay, a 50-seed invariant sweep, under 10 s |
| C12 | Screenshot for an engine-only cycle | Ben: worried about screenshot token spend; "we shouldn't do any screen recordings in automated tests". Round 4: 3a. P7's screenshot is waived for this cycle; the proof is `make check` plus the `Engine smoke:` boot line. P7 stays as written for visible cycles |
| C13 | Save and resume | Ben: "Nothing" in scope this cycle; "THEORETICALLY in pve a human can save and resume" |

## Scenarios

- **Given** a valid card file and seed 1, **when** a match starts, **then** each seat
  holds 4 cards (3 dealt, 1 drawn), the round is 1, the turn is 1, the energy is 1, and a
  seeded coin flip has picked the awaited seat.
- **Given** seat 0 awaited on turn 3, **when** seat 0 commits two cards costing 1 and 2,
  **then** the result is a success, seat 1's view shows a face-down count of 2 and no
  card identities, and seat 1 is awaited.
- **Given** seat 0 awaited on turn 3, **when** seat 0 commits cards costing 2 and 2,
  **then** the result is an over-budget failure, the full state is unchanged and the log
  length is unchanged.
- **Given** seat 1 awaited, **when** seat 0 commits, **then** the result is a wrong-seat
  failure.
- **Given** the first committer placed three cards and the second placed one, **when**
  the turn resolves, **then** the reveal events run first-1, second-1, first-2, first-3.
- **Given** seat 1 won round 2 and round 3 tied, **when** round 4 starts, **then** seat 0
  commits first on turn 1.
- **Given** a seat holding 7 cards, **when** a turn starts, **then** it still holds 7 and
  a burn event names that seat.
- **Given** wins 3–3 after round 7, **when** the next round starts, **then** it is a
  sudden-death round, and the first seat to win a round wins the match with reason
  "sudden death".
- **Given** any match in progress, **when** the non-awaited seat concedes, **then** the
  match ends with the other seat as winner and reason "concede", and further actions
  fail with the match-over code.
- **Given** a finished bot-vs-bot match from a fixed seed, **when** its log is written to
  JSON, read back and replayed, **then** the replayed full state equals the original.
- **Given** 50 seeds, **when** each plays a bot-vs-bot match, **then** every match ends,
  no hand exceeds 7, no commit exceeds the turn's energy, no view leaks a hidden card,
  and every log replays to an equal state.
- **Given** `make check`, **when** the boot stage runs, **then** the log holds an
  `Engine smoke:` line before `Main ready` and no error line.

## Data touched

- New: `godot/engine/` (modules, the card JSON, `bot/`), new suites under `godot/tests/`,
  this spec set.
- Changed: `godot/main.gd` (smoke run only), `docs/specs/specs-moc.md`.
- Read only: `docs/planning/*`, `CLAUDE.md`, `scripts/check.sh`.
- Never: `godot/addons/*`, `docs/.obsidian/`, `.env`, `godot/.godot/`, `godot/reports/`,
  the archive.

## Definition of done

- [ ] Every requirement R1–R40 is covered by a named gdUnit4 case or the smoke line.
- [ ] `make check` is green, with every engine suite passing and the test stage under 10 s.
- [ ] The boot log carries the `Engine smoke:` line before `Main ready`.
- [ ] The fixed-seed match result is pinned as a golden assertion.
- [ ] No screenshot and no recording for this cycle (C12); the Linear status update is text.
- [ ] Constitution Check passes (see plan).
- [x] Spec, plan and tasks signed off by Ben (2026-11-02) and committed before implementation begins.
