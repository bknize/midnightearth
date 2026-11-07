---
type: spec
tags: [spec, cycle-9-rules-v2, engine, rules-v2, cards, board]
status: approved
related: ["[[specs/cycle-9-rules-v2/plan]]", "[[specs/cycle-9-rules-v2/tasks]]", "[[specs/ruleset-v2/spec]]", "[[rules/rules-moc]]", "[[rules/glossary]]", "[[rules/rules-v2]]", "[[rules/resolution]]", "[[rules/cards-v2]]", "[[rules/crew-v2]]", "[[rules/test-decks]]", "[[systems/game-loop]]", "[[systems/cards-crew-decks]]", "[[planning/cycles]]", "[[planning/bot-ladder]]", "[[planning/phase-1-tech-stack]]"]
created: 2026-11-06
updated: 2026-11-06
uid: 8bcbf874-aa7e-4696-9bb8-acb7bbe843e0
linear: https://linear.app/night-science-llc/project/cycle-9-rules-v2-in-the-engine-60e0297b48b8
supersedes:
---

# Spec: Cycle 9 — rules v2 in the engine

**Slug:** `cycle-9-rules-v2`  ·  **Change type:** engine  ·  **Status:** approved (Ben, 2026-11-06, three rounds and one mid-interview direction, signed off 2026-11-06; see Clarifications)

This cycle builds the ruleset-v2 canon under `docs/rules/` into the engine, the data files
and the board, replacing rules version 6. The canon is the design: [[rules/glossary]],
[[rules/rules-v2]], [[rules/resolution]], [[rules/cards-v2]], [[rules/crew-v2]] and
[[rules/test-decks]], with Ben's rulings C1 to C32 in [[specs/ruleset-v2/spec]]. None of
those rulings is reopened here; where this spec cites "canon Rn" it means a requirement of
that spec, and "Qn" or "Dn" a rule or drain point of [[rules/resolution]]. The spec here says
what the engine, the data and the board must do; the canon says what the game is.

Two milestones, one spec (Ben, round 1, 1a):

- **Milestone A** (DC-13, this branch `cycle-9-rules-v2`): all rules machinery, the 30
  evergreen cards, Greed and Ramp with their two decks and the six Crew those decks list, the
  bot strip, a minimum playable board.
- **Milestone B** (DC-14, `cycle-9b-rules-v2`): Combo, Disruption, Graveyard and Control with
  their decks, the other four Crew, the board work their cards need, and the rewrite of the
  two system guides.

## Intent

After milestone A a match plays end to end under rules version 7: seven-turn Rounds with
Energy equal to the Turn number, an opening hand of four and a discard-down after each
Commit, a 40-card Deck shuffled once and a public Pile, Power and Bonus cards scored by a
walking total, seven statuses with exit marks, ring movement, a breadth-first trigger queue
with a budget of 50 per pulse, fifty cards and six Crew from the canon, a random opponent,
and a board a human can play it on. After milestone B the whole 90-card pool, six decks and
ten Crew are in, and the vault's system guides describe the game as built.

## Non-goals

- **No bot work beyond the strip.** No training, re-stamp, evaluation, yardstick change,
  evaluator feature, calibration or ladder row. Ben: "defer all bot changes for a separate
  spec+interrogation" (round 1) and "Strip it all away and go back to the singular random
  bot. I will investigate another bot strategy on another session" (mid-interview). The
  bot stack except the random bot is removed (R70 to R75); `scripts/bot/` and the
  `make bot-*` targets stay untouched for that later session (round 3, 1b).
- No balance pass. Numbers are the canon's first-draft values; a card is changed only by
  editing [[rules/cards-v2]] first.
- No deck builder, no art, no iOS build (D8: desktop every cycle).
- No board polish beyond the minimum playable seat (round 1, 2a): no new layouts, themes or
  animations past the ones named in section J.
- No edit to `docs/systems/game-loop.md` or `docs/systems/cards-crew-decks.md` until the
  end of milestone B (round 2, 3a), and never to the uncommitted edits those two files carry
  in the main checkout, whose author is unconfirmed.
- No edit to the canon notes except to set their `status` when the rules are built (B).
- v6 data is not kept as fixtures (round 2, 3a): git history holds it.

## Actors

- **Ben**: decides, plays the human seat, signs off.
- **A player**: the human seat on the board; commits, answers prompts, does the discard-down.
- **The random bot**: the only opponent this cycle and the sweep's player.
- **The engine**: applies actions, runs the Walk and the queue, writes the log.
- **The board**: shows the human seat what the engine says.
- **Implementer-engine, implementer, reviewer, orchestrator**: the roles of `CLAUDE.md`.
- **A later bot session**: reads the engine's view and legal-play helpers; nothing here is
  shaped for it beyond keeping those public.

## Requirements (EARS)

"The engine" is `godot/engine/`. "A log" is the serialized action log (D4). "The board" is
the human seat's scene. Numbers in canon units: Bonus values in hundredths (×1.25 is 125,
+0.5 is 50); the walking total in ten-thousandths (R28 to R31).

### A. Match, Round, Turn (canon R5 to R9)

- R1. The engine shall keep the match structure of today: a Match ends at four Round wins, a
  Round is seven Turns, a tied Round awards no win, and after Round 7 the seat with more
  Round wins takes the Match with sudden-death Rounds while level (canon R5).
- R2. When a Round ends, the engine shall send every card on both rows to its Owner's Pile as
  a Discard, keep every hand, Deck and Pile as they are, and drain On discard once (D12).
- R3. The engine shall decide the first committer as today (previous Turn's winner; on Turn 1
  the previous Round's loser; a seeded coin flip on the first Turn of a Match; a tied Turn
  keeps the order), and after a tied Round shall continue the alternation from the Round's
  last Turn (canon R7, C25).
- R4. The engine shall run each Turn as: turn start (each seat draws one card, first seat
  first, then On start), first Commit, that seat's On commit and discard-down, second Commit,
  that seat's On commit and discard-down, the Walk, turn end (canon R8; resolution steps 1
  to 16).
- R5. When a Turn ends, the engine shall run, in order: At turn end before the exit pass
  (D9), the exit pass (R41) and its On discard drain (D10), At turn end after the exit pass
  (D11), turn-scoped statuses ending, Energy settling, the Turn's winner recorded (canon R9).

### B. Energy and Cost (canon R10 to R12)

- R6. The engine shall give each seat a Budget of N Energy on Turn N plus every grant made for
  that Turn, and shall carry no Energy between Turns.
- R7. When an ability grants Energy for the current Turn (Dynamo) or for every Turn from a
  given one (Engineer, from Turn 3), the engine shall add it to that Turn's Budget.
- R8. The engine shall read a card's Cost at Commit as its printed Cost less every reduction
  that applies (Memory and Ongoing), never below 0; the loader shall accept a printed Cost
  above 7 only on a card whose text names the Turn it becomes reachable (Colossus).
- R9. If a Commit's total Cost exceeds the seat's Budget, then the engine shall reject the
  action, leave the state unchanged and not log it.

### C. Hand (canon R13 to R17)

- R10. When a Match starts, the engine shall shuffle each Deck once with the seeded RNG and
  deal each seat four cards; the engine shall not deal again at Round start.
- R11. The engine shall compute a seat's Hand size as the highest "your Hand size is N" set
  that applies (base 4), plus every "+N" that applies (Pantry), read at that seat's Commit.
- R12. While a Turn is in progress, the engine shall let a hand hold any number of cards; a
  draw shall succeed whenever the Deck is not empty.
- R13. When a seat's Commit is accepted and its On commit drain (D3 or D5) has finished, if
  that seat's hand holds more cards than its Hand size, the engine shall open a multi-select
  prompt for that seat over its hand that accepts exactly the excess, and shall send the
  chosen cards to its Pile as Discards before the other seat may commit or the Walk starts.
- R14. If a discard-down answer names fewer or more cards than the excess, or a card not in
  that hand, then the engine shall reject it and keep the prompt open.
- R15. The engine shall perform no other Hand size check: not at turn end, not at Round
  start, not on a draw.

### D. Deck and Pile (canon R18 to R24)

- R16. The engine's deck loader shall accept a deck only when it lists exactly 40 cards with
  at most four copies of any one card, from any tag, and exactly three different Crew.
- R17. The engine shall not refill or reshuffle a Deck at Round start.
- R18. When a seat would draw from an empty Deck, the engine shall draw nothing, wake that
  seat's On empty draw triggers as one Batch and drain it; every trigger in the Batch fires
  with no re-check that the Deck is still empty (C29); immediately after the drain, if the
  Deck is no longer empty, the engine shall make the denied draw once (Q11).
- R19. The engine shall give each seat one Pile, in Pile order, whose every entry is public
  to both seats from the moment the card enters it (canon R21, R24); the destroyed and burn
  piles of rules version 6 shall not exist.
- R20. The engine shall treat every card entering a Pile from a hand (a chosen discard, the
  discard-down) or from a row (a Condemned card in the exit pass, a Round-end clear) as a
  Discard that wakes On discard (canon R22).
- R21. The engine shall keep each Pile for the whole Match; no card shall leave play except
  to a Pile, and a card shall leave a Pile only by being shuffled into a Deck or placed on a
  row (glossary, Leaving a Pile).

### E. Card anatomy and the walking total (canon R25 to R30, C19 to C21)

- R22. The engine's card loader shall accept a card with an id, a name, a tag (one of the six
  strategies or `evergreen`), a Cost, a Power (which may be negative), at most one printed
  Bonus (a Mult of 125, 150 or 200, or an Add of 25, 50 or 100 hundredths), zero or more
  abilities each with exactly one trigger moment, and rules text; a card may have no Bonus
  and no abilities.
- R23. The engine shall let a card carry its printed Bonus plus any granted Bonuses, and
  when it Scores shall apply all Adds, then all Mults (C20).
- R24. When an ability grows a Bonus, the engine shall apply the growth as base, then
  additive steps, then multiplicative steps, rounded to the nearest hundredth, and shall stop
  at the cap the ability names (Sapling ×2, Graft ×2.5).
- R25. The engine shall keep one walking total per seat that starts at 0 at each Walk start.
- R26. When a card Scores, the engine shall, for its Controller's seat and in this order:
  add the card's Power to the walking total; build the card's Bonus value as 1 plus every
  Add, then times every Mult, never below 0; multiply the walking total by the Bonus value
  (a card with no Bonus multiplies by 1) (canon R28).
- R27. When a Walk ends, the engine shall set each seat's Score to its walking total after
  its last Scoring card, rounded once to a whole number with half rounding up; a Score may
  be negative, a Mult below 1 simply multiplies and a negative total is multiplied like any
  other.
- R28. The engine shall hold the walking total and the Bonus value as integers in
  ten-thousandths, rounding to the nearest ten-thousandth after each multiply (Ben, round 1,
  3a; the engine's reading of C21), so that two replays of one log produce identical totals.
- R29. The engine shall report every Score step in a public event that carries the card, the
  Power added, the Bonus value and the walking total after, all in canon units, so the board
  can show the total as the canon describes it.
- R30. The engine shall keep the memory rule: a stat change is a Board change that ends when
  the card leaves its row or the Round ends, unless the ability says "for the match" or
  "permanently", in which case it is Memory that follows the card through every zone, the
  Pile and a Deck included (canon R29).
- R31. The engine shall record each card's Owner (the seat whose Deck it came from; for a
  created card, the seat it was created for) and Controller (the seat whose row it is on),
  and whenever a card leaves a row it does not Own shall send it to its Owner's Pile or hand
  (canon R30).

### F. Statuses and exit marks (canon R31 to R38, C5, C6, C22, C24)

- R32. The engine shall know exactly seven statuses: Muted, Squelched, Silenced, Condemned,
  Fleeting, Fade and Anchored, each held per card with its cessation (until end of turn,
  permanently, or a named condition).
- R33. While a card is Muted, the engine shall not fire its triggered abilities and shall
  still Score it and read its Ongoing abilities; while a card is Squelched, the engine shall
  not Score it and shall not read its Ongoing abilities, and shall still fire its triggers.
- R34. If a card is both Muted and Squelched, then the engine shall hold it as Silenced (no
  triggers, no Score, no Ongoing), keep each half's own cessation, and when one half ends
  or is removed shall leave the card with the other half (R33, C22); a card becoming
  Squelched alone shall wake On squelch, a card becoming Silenced shall not.
- R35. When an ability applies a status with no stated cessation, the engine shall end it at
  turn end; a "permanently" status shall be Memory; a named condition shall end it when the
  condition is met.
- R36. The engine shall end every board-scoped status when the card leaves its row or is
  Un-revealed, and shall keep a permanent one through both (canon R37).
- R37. While a protection "cannot be X" applies to a card (Ward: Muted; Bastion: Condemned),
  the engine shall drop only the blocked part of any effect that would apply X to it, so a
  Silence against a card that cannot be Muted leaves it Squelched only (C24), and shall not
  end an X already in place.
- R38. The engine shall hold at most one exit mark per card (Condemned, Fleeting or Fade);
  when a newer mark is applied, it shall replace the older.
- R39. While a card holds an exit mark, the engine shall still Score it and fire its
  triggers; no card or Crew shall remove a card from a row before turn end (canon R38).
- R40. The engine shall let an Anchored card be moved by no effect: a shift slides other
  cards past it, a swap naming it fizzles, a reverse or reorder leaves it in its slot and
  permutes the rest (canon R36, Q3 order for the Batch the move wakes).
- R41. When the exit pass runs, the engine shall resolve the marks in one pass, the first
  seat's row before the second's and each in slot order: Condemned to its Owner's Pile as a
  Discard, Fleeting to its Owner's hand, Fade face down in place keeping Memory and losing
  Board changes; an Ongoing that changes exit marks shall be read once at the start of the
  pass; the On discard Batches shall wake after the pass with a snapshot taken then (D10).

### G. Movement (canon R39 to R41)

- R42. When an effect moves a card stepwise, the engine shall treat the row as a ring: left
  from the leftmost slot lands on the rightmost and the reverse; the Walk shall still read
  the row left to right.
- R43. The engine shall treat committing or placing a card into a slot as Placement, not a
  Move: it changes other cards' slot numbers without waking On moved or breaking an Anchor.
- R44. The engine shall keep the cursor rules of [[specs/cycle-5-walk-cursor/spec]]: a pulse
  belongs to its slot, a card moved ahead of the cursor is reached later this Walk, a card
  moved behind it waits for the next Walk, a card landing on the pulsed slot Scores now.

### H. Triggers and the queue (canon R42 to R52, Q1 to Q11)

- R45. The engine shall resolve triggers through one first-in, first-out queue of Batches: a
  resolving effect shall never resolve the triggers it wakes inline; it appends them as one
  Batch and finishes, and the queue drains fully before play moves to the next step (Q1).
  Outside the Walk (a draw, a Commit, a Discard, turn end, Round end) the same rules apply
  with a fresh queue that drains at once.
- R46. When a Batch is created, the engine shall snapshot the cards and Crew in it; a later
  move, Un-reveal or exit mark shall not make one fire twice or skip it; whether a Muted or
  Silenced card may fire shall be read when its trigger comes up (Q2).
- R47. Within one Batch the engine shall order cards before Crew; among cards the first
  seat's then the second's, each by slot left to right; among one seat's Crew, Crew slot
  order (Q3).
- R48. The engine shall give each pulse a budget of 50 trigger resolutions across both of
  its drains; each trigger taken off the queue counts one, whether it acts or fizzles, and
  so does each retrigger resolution; when the 50 are spent, every trigger still queued for
  that pulse fizzles with the reason `exhausted` in a public event and the Walk continues;
  the count restarts at 0 for the next pulse (Q4).
- R49. The engine shall read every variable amount (a Power, a Cost, cards in a Pile, an N)
  at the moment the ability resolves (Q5).
- R50. When a retrigger applies to an ability, the engine shall add one extra resolution of
  it immediately after each resolution, before the next trigger in the queue, with choices
  made again and amounts read again; retriggers stack by one each and never apply to
  themselves; triggers woken by the extra resolution form their own Batch (Q6).
- R51. While "Scores twice" applies, the engine shall run the score stage of every later
  pulse twice, each run doing the three Score steps of R26 and waking On score, both Batches
  queued before the score stage's drain; a card that Scores twice counts twice for any count
  of Scores (Q7).
- R52. The engine shall fire a Crew only after the effect that woke it has fully resolved, as
  the Crew part of its Batch, and shall treat Crew as non-cards: never on a row, never a
  target, never Condemned, moved or copied (Q8).
- R53. When an effect resolves, the engine shall fizzle it with reason `no target` when no
  target is eligible, choose automatically with exactly one eligible target, and open a
  prompt for the choosing seat with two or more, pausing wherever the queue is draining and
  resuming at the same place; a Crew prompt shall be optional and shall open even for one
  eligible target; an ability with an optional count shall always prompt and may take none
  (Q9).
- R54. The engine shall implement the ten trigger moments as the glossary defines them: On
  reveal, On score, On commit (revealed row cards and hand cards whose text says "while in
  your hand"; never a card committed face down this Turn), On start (revealed cards only,
  after the draws), On discard, On squelch, On empty draw, On moved, At turn end (two
  points), Ongoing (read when needed), with the watcher bracket and the zone bracket.
- R55. The engine shall drain the queue at exactly the twelve points of [[rules/resolution]]
  (D1 to D12); D7 and D8 are the only drains inside the Walk.
- R56. When a draw, a Commit, a Discard or turn end wakes a prompt, the engine shall pause
  in that step with the phase reporting an open prompt, reject every other action meanwhile,
  and resume the same step after the answer (as cycle 8's turn-start pause).

### I. Hidden information (canon R53, R54)

- R57. The engine's view for a seat shall hold its own hand, both rows' revealed cards,
  face-down cards as slots only, the other seat's hand and Deck counts, both Piles in full,
  both seats' Crew, the count and slots of a face-down Commit, both walking totals and both
  Scores, and the identity of each opposing face-down card it has looked at (Lookout); it
  shall never hold the seed, a Deck order or the id of a card in the other seat's hand, Deck
  or face-down Commit that it has not looked at.
- R58. While a card is in a hand or face down, the engine shall keep its stats, Memory and
  effects private to its Owner (a private event carries the owning seat and is redacted for
  the other), and shall make them public when it is revealed or enters a Pile.
- R59. The engine shall log every look-at (Delve's three cards, Lookout's card) as private to
  the looking seat, and the sweep's leak scan shall treat a looked-at identity in the other
  seat's view as a leak.

### J. Content and data (canon R55 to R64)

- R60. Milestone A's card pool shall be exactly the 30 evergreen cards, the ten Greed cards
  and the ten Ramp cards of [[rules/cards-v2]], each with the Cost, Power, Bonus, tag and
  rules text printed there, and every one of their abilities shall behave as that text and
  its Flags column describe; milestone B shall add the other forty.
- R61. Milestone A's deck list shall be exactly the Greed and Ramp decks of
  [[rules/test-decks]] (four copies of each of the strategy's ten cards; Crew Tallyman,
  Void, Engineer and Navigator, Captain, Dredger); milestone B shall add the other four.
- R62. Milestone A's Crew pool shall be Tallyman, Void, Engineer, Navigator, Captain and
  Dredger with the moment, text, end condition, uses and prompting of [[rules/crew-v2]];
  the tenth Crew ships as Dredger with id `dredger` (round 2, 2a); milestone B shall add
  Shade, Veil, Quartermaster and Salvager.
- R63. The rules version 6 content (Ruin, Drift, Bloom, Echo and their cards and Crew), the
  four v6 effect families and every verb only they used shall be removed with their suites
  (round 2, 3a); git history keeps them.
- R64. If a pool, deck or Crew file fails any loader check, then the engine shall report the
  first failure by name and `main.gd` shall print an error and show no board.

### K. Rules version, log and replay (D4)

- R65. The engine shall report rules version 7 and a new log format; a log of an earlier
  format shall fail replay with a format mismatch and no state change.
- R66. The engine shall derive every random outcome (the coin flip, shuffles, random choices,
  shuffle-into) from the match seed, read no clock and touch no node.
- R67. When a log is replayed against the same pools, the engine shall reproduce the same
  full state, Scores and events as the original run, prompts and fizzles included.
- R68. The engine shall keep the action kinds of today (commit with slots, choose, choose set,
  decline, concede); the discard-down shall be answered with a set choice over the hand.
- R69. The engine's instance ids shall have room for created cards (milestone B's Dross and
  Twin copies) without colliding with Deck cards.

### L. The bot strip (Ben, mid-interview; round 3, 1b and 2a)

- R70. The engine shall ship exactly one bot, `random`: uniform over legal commits within the
  Budget and over legal prompt answers (a set of exactly the excess for the discard-down,
  the decline included for an optional prompt), seeded per decision as today.
- R71. The engine shall contain no greedy, greedy_v1, tuned or matrix bot, no evaluator,
  candidate generator, hand sampler, regret matching, weights file, bot stamp or bot worker,
  and no suite or fixture that exists only for them.
- R72. The engine shall have no preview mode: no `preview`, `preview_choice`, `preview_set`,
  `preview_decline`, pair preview or preview policy, and no effect code path that exists
  only to keep a preview equal to live play (round 3, 2a).
- R73. The bot name flag shall accept `random` only; a bot level flag shall not exist; the
  board's and the smoke's opponent shall be `random`; `make sweep` shall play `random`.
- R74. `scripts/bot/`, `scripts/bot-eval.sh`, `scripts/bot-train.sh` and the `make bot-*`
  targets shall not be edited this cycle (round 3, 1b); that they no longer run is accepted
  until the bot session rebuilds what they drive.
- R75. The cycle shall not run `make bot-eval`, `make bot-train`, a re-stamp or a ladder
  measurement; the rerun provision of [[planning/bot-ladder]] is suspended, and the ladder
  note gains one closing line saying so at verification.

### M. Board, milestone A (minimum playable seat; round 1, 2a; round 3, 3a)

- R76. The board shall show on every face its Power and its printed Bonus as "×1.25" or
  "+0.50", with a granted change pulsing as today's stat change does.
- R77. While a Walk runs, the board's chips and row tally shall show the Controller's
  walking total after each Score to two decimals while it has a fraction and as a whole
  number when it has none; the HUD shall show the rounded Score at Walk end and in the
  totals.
- R78. The board shall show both Piles in place of the destroyed strip: a count per seat on
  the HUD and, on a tap or when a prompt targets a Pile, a strip of that Pile's cards face
  up in Pile order, the opponent's included.
- R79. While a card holds a status, the board shall show its badge word (Muted, Squelched,
  Silenced, Condemned, Fleeting, Fade, Anchored), one word per status it holds.
- R80. When the engine opens a discard-down prompt for the human seat, the board shall open
  a multi-select over the hand whose confirm button enables only when exactly the excess is
  selected, and shall disable Commit until it closes.
- R81. When the exit pass resolves, the board shall move a Condemned card to its Owner's
  Pile, a Fleeting card to its Owner's fan, and flip a Fade card face down in its slot.
- R82. The board shall show the Energy Budget as N on Turn N plus grants, an empty draw as a
  note on the deck, and a Pile shuffled into a Deck as the Pile emptying.
- R83. The board shall show a fizzle with reason `exhausted` as a note on the pulsed card,
  as it shows `no target` today.

### N. The gate and verification

- R84. `make check` shall be green at the end of every task, with gdUnit under the 30 s
  budget of cycle 7 C15.
- R85. `make sweep` under `random` over the shipped deck pairings shall end every match,
  replay every log, find no leak (Pile entries public, hands and looked-at cards private),
  and print the longest match and the slowest decision; the latency assertion stays and is
  expected to be trivially met.
- R86. The seed-1 smoke line (`Engine smoke: seed=1 decks=… bot=random …`) shall be pinned
  as the golden by the orchestrator at verification and agree across the engine smoke, the
  board autoplay and the driver pin.

## Clarifications (Ben, 2026-11-06)

Rounds 1 and 2 were asked by an earlier interrogator whose transcript was lost after round
2; its rounds and Ben's answers are recorded verbatim from the orchestrator's relay. Ben's
request in his own words, mid-interview: "We need to update the cards and decks as well".

| # | Question | Answer |
|---|---|---|
| C1 | Round 1 Q1, scope and cycles: whole canon in one spec with two milestones (A: rules machinery, 30 evergreen, Greed and Ramp, two decks, six Crew, DC-13; B: the other four strategies, decks and Crew, DC-14) vs one cycle vs A only | 1a |
| C2 | Round 1 Q2, board: minimum playable human seat (faces read Power and Bonus, walking total on HUD and chips, the strip becomes the two Piles, badge words, discard-down multi-select, exit pass animations), one board task per milestone, no polish | 2a |
| C3 | Round 1 Q3, walking-total arithmetic: integer fixed point at ten-thousandths, rounding to the nearest ten-thousandth after each multiply, Bonus values in hundredths, recorded as the engine's reading of C21 | 3a |
| C4 | Round 1 Q4, bot provision (bot-eval + re-stamp + ladder row, train in cycle, or a new yardstick) | Ben: "4 -- defer all bot changes for a separate spec+interrogation". No bot provision in this spec |
| C5 | Round 2 Q1, where "defer all bot changes" stops: (a) minimal edits so every bot compiles against v2, or (b) nothing under `godot/engine/bot/` edited except the random bot, bot suites skipped, the board's opponent `random` | 1b, then superseded by C7 |
| C6 | Round 2 Q2, the tenth Crew's name | 2a: ships as Dredger, id `dredger` |
| C7 | Round 2 Q3, v6 content: replaced outright (data files become v2 content, the four v6 verb families and suites deleted, git keeps v6; system guides rewritten once at the end of B; the uncommitted edits to the two system notes left alone) vs frozen fixtures vs guides rewritten in A | 3a |
| C8 | Mid-interview direction, after the orchestrator raised that skipped bot suites would still have to parse | Ben: "Strip it all away and go back to the singular random bot. I will investigate another bot strategy on another session". Supersedes C5: every bot but `random` is removed (R70 to R75) |
| C9 | Round 3 Q1, how far the strip goes: (a) everything bot except `random` including `scripts/bot/`, `bot-eval.sh`, `bot-train.sh` and the `make bot-*` targets, or (b) the same but `scripts/bot/` and the `make bot-*` targets kept for the later bot session | 1b: the Godot-side bot code, its suites, weights, stamp and fixtures go; `scripts/bot/`, the two shell scripts and the Makefile targets are not edited (R74) |
| C10 | Round 3 Q2, the engine's preview mode: removed with the bots (tests use a plain state copy; no "preview equals live" acceptance) vs kept as a general facility | 2a: removed (R72) |
| C11 | Round 3 Q3, what the human seat sees of a fractional walking total: two decimals while fractional and the rounded Score at Walk end, vs whole numbers everywhere | 3a (R77) |
| C12 | DC-13 run, after T03 (2026-11-06): a 200-seed random-vs-random probe on the shipped decks found 7 matches that never end (both Decks and hands empty from about Round 6, every sudden-death Round tied 0-0); how does a Match end when it can no longer progress? (a) a draw, (b) the higher Match total Score, draw only if level, (c) cap sudden death | Ben: "Total Score (1b)". A tied sudden-death Round with both Decks and both hands empty ends the Match, reason `stalemate`: the seat with the higher sum of its Walk Scores over the whole Match wins; equal sums draw (winner -1). Built as 348dd5c (`MatchState.match_scores`, `MatchEngine._stalled`) |
| C13 | DC-13 run, after T03 (2026-11-06): the code awarded a Round to the higher Turn-7 Score (today's rule, kept under R1) while the glossary says the seat with more Turn wins; who takes a Round? (a) more Turn wins, (b) the higher Turn-7 Score | Ben: "More Turn wins (2a)". A Round goes to the seat that won more of its Turns; equal Turn wins award no Round win. Built as `MatchState.turn_wins` (reset each Round, in `to_dict`), counted in `TurnFlow.settle_turn`, read by `award_round`; ROUND_ENDED gains `turn_wins` |
| C14 | DC-13 T10 review (2026-11-06): a triggered ability of a card in hand (Layaway, On commit while in your hand) sent the other seat a redacted TRIGGER_FIRED that kept its unique verb, so the opponent learned the card and the count of copies; blank the verb, drop the event, or…? | Ben: "When a card triggers in-hand, we show an animation to make it public knowledge that a card-in-hand is activating. We'll build the intentional telegraph into the card's power budget." A hand trigger is public: its TRIGGER_FIRED / TRIGGER_FIZZLED name the card for both seats and the board shows the card face to both seats as it fires; the card stays in the hand. Canon amended: [[rules/rules-v2]] section 8 |

Defaults stated by the interrogator, open to Ben's veto at sign-off (none changes a decision
above): `godot/tools/bot_worker.gd` and its records helper go with the bots they drive, so
`scripts/bot/driver.py` is inert until the bot session rebuilds a worker (C9 reading); the
`--bot=` flag stays with `random` as its only value; the frozen DC-05 fixtures go with the
stamp test they served; the v6 suites that test rewritten modules are rewritten or deleted
by the task that rewrites the module; Ward's "your cards cannot be Muted" is a seat-scoped
protection over that seat's row cards until turn end; a looked-at card stays known to the
looking seat until it is revealed or leaves the row; the sweep's coverage counters are reset
for the random bot's play.

## Scenarios

Each is traceable through [[rules/resolution]]; the nine canon scenarios there hold too.

- **Given** Turn 3 and seat 0 holding six cards after its draw with Hand size 4, **when**
  seat 0's Commit of one card is accepted and D3 drains, **then** a multi-select prompt opens
  for seat 0 over its five cards accepting exactly one, a two-card answer is rejected, the
  one-card answer sends that card to seat 0's Pile as a Discard, both seats' views list it,
  and only then is seat 1's Commit accepted (R13, R14, R19, R20).
- **Given** a row A (Power 2, Mult ×1.5), B (Power 3, Add +1), C (Power 4), **when** the Walk
  Scores them in that order, **then** the walking total reads 3, 12, 16 after each Score
  and the Score is 16; in the order C, A, B it reads 4, 9, 24 (R26, R27; canon's worked row).
- **Given** a walking total of 25000 (2.5) and a Scoring card of Power 1 with Mult ×1.25,
  **when** it Scores, **then** the total is 43750 (4.375) and the board's chip reads
  "4.38" while the HUD still shows the previous Score (R28, R77).
- **Given** Round 6 Turn 2 with an empty Deck and Dredger, **when** the seat draws at turn
  start, **then** D1 shuffles its Pile into its Deck with the seeded RNG, the resumed draw
  succeeds and the view's Pile for that seat is empty; with Void instead, nothing is drawn and
  the next Scoring card of that seat gets Power +10, Add +0.5 and Mult ×1.25 for that Score;
  with both, both fire in either Crew slot order (R18, R62, C29).
- **Given** Flare revealed at slot 1, **when** its On reveal resolves, **then** Flare holds
  Condemned, Scores this Walk, and in the exit pass goes to its Owner's Pile as a Discard,
  the board flying it to the Pile (R38, R39, R41, R81).
- **Given** a stub card Muted until end of turn, **when** a stub effect Squelches it, **then**
  the card is Silenced; **when** the Mute's turn ends first, **then** it is left Squelched
  and fires its triggers again (R34, R35).
- **Given** a row A B C with B Anchored by Brace, **when** a stub "your other cards each move
  one slot left" resolves, **then** the row reads C B A, B never moved, and On moved wakes
  for A and C as one Batch after the effect (R40, R42, R45, R47).
- **Given** two stub cards that each Condemn a random enemy card and Score again on every
  Score, **when** they feed each other in one pulse, **then** the 50th resolution is the
  last, every queued trigger fizzles `exhausted` in public events, the board notes it on the
  pulsed card, and the next pulse starts at 0 (R48, R83).
- **Given** Lookout revealed by seat 0, **when** seat 0 chooses a face-down opposing card,
  **then** seat 0's view names that card at its slot, seat 1's view and the public event do
  not, and the sweep's leak scan passes (R57, R59).
- **Given** Sapling with Memory ×1.75 in seat 1's Pile, **when** Dredger shuffles the Pile
  into the Deck and Sapling is drawn and later revealed, **then** its face reads ×1.75 with
  the grown mark (R30, R76).
- **Given** a rules-6, format-4 log, **when** it is replayed, **then** replay fails with the
  format mismatch and nothing changes; **given** a format-5 log of a 50-seed sweep match,
  **then** replay reproduces its full state (R65, R67).
- **Given** `--bot=tuned` on the command line, **when** `main.gd` starts, **then** it prints
  an error naming `random` as the only known bot and shows no board (R73).

## Data touched

- New: `docs/specs/cycle-9-rules-v2/{spec,plan,tasks}.md`; one row in [[specs/specs-moc]];
  by its tasks, new engine modules named in the plan and new gdUnit suites.
- Rewritten: `godot/engine/data/{cards,decks,crew}.json` (v2 content), most of
  `godot/engine/`, the random bot, `godot/main.gd`, the board scripts the plan names, the
  engine and board suites, the sweep.
- Deleted: `godot/engine/bot/` except `bot_player.gd`, `bot_registry.gd` and
  `random_bot.gd`; `godot/engine/bot/data/`; `godot/tools/bot_worker*.gd`;
  `godot/engine/{bloom,drift,echo,ruin}_effects.gd`, `pair_preview.gd`,
  `preview_policy.gd`; their suites; `godot/tests/fixtures/dc05_*.json`.
- Read only: `docs/rules/*` (the design), `docs/specs/ruleset-v2/*`, `docs/systems/*`,
  `docs/planning/*`, `scripts/*`.
- Appended at verification by the orchestrator: a DC-13 row in [[planning/cycles]], one
  closing line in [[planning/bot-ladder]].
- Never: `scripts/bot/`, `scripts/bot-eval.sh`, `scripts/bot-train.sh`, the `Makefile`'s
  `bot-*` targets (R74); `docs/.obsidian/`; `godot/addons/*`; `.env`; `godot/.godot/`;
  `godot/reports/`; the archive; the uncommitted edits to `docs/systems/bot-training.md`
  and `docs/systems/cards-crew-decks.md` in the main checkout.

## Definition of done

Milestone A (DC-13):

- [ ] `make check` is green with gdUnit under 30 s; a format-4 log fails replay (R65, R84).
- [ ] The three data files hold exactly the 50 cards, two decks and six Crew of the canon,
      and a diff of the card table against [[rules/cards-v2]] shows no difference in Cost,
      Power, Bonus, tag or text (R60 to R62).
- [ ] Every requirement of sections A to I has a gdUnit case, stub abilities standing in
      where milestone A's content has no card for it (statuses, Fleeting, Fade, retriggers,
      Scores twice, the budget).
- [ ] `make sweep` under `random` is clean (R85) and the golden is pinned (R86).
- [ ] `godot/engine/bot/` holds the random bot only; `grep -rl preview godot/engine` is empty
      (R71, R72); `scripts/bot/` and the Makefile are unchanged (`git diff --stat` on them is
      empty) (R74).
- [ ] Three Godot MCP screenshots (P7): a v2 face with a two-decimal chip and tally, the
      discard-down multi-select with Commit disabled, the Pile strip after a Condemned exit.
- [ ] Constitution Check passes (see plan).
- [ ] Spec, plan and tasks signed off by Ben and committed before implementation begins.

Milestone B (DC-14):

- [ ] The 90 cards, six decks and ten Crew are in and every Flags note in [[rules/cards-v2]]
      has a test; `make sweep` over six decks is clean; the golden is re-pinned.
- [ ] [[systems/game-loop]] and [[systems/cards-crew-decks]] describe rules version 7 and
      the canon notes' `status` says built.
- [ ] Two screenshots: a Silenced badge on a card the opponent Eclipsed, and Dross in hand
      with the Walk-end multiply shown in the tally.
