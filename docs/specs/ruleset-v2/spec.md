---
type: spec
tags: [spec, ruleset-v2, rules, vault, design]
status: approved
related: ["[[specs/ruleset-v2/plan]]", "[[specs/ruleset-v2/tasks]]", "[[cards/Cards]]", "[[systems/game-loop]]", "[[systems/cards-crew-decks]]", "[[planning/phase-3-game-loop]]", "[[specs/cycle-5-walk-cursor/spec]]", "[[specs/cycle-8-ramp-bounce-crew/spec]]", "[[planning/phase-1-tech-stack]]"]
created: 2026-11-06
updated: 2026-11-06
uid: bb79af3f-db95-4aa5-998a-cccaeb6fe93c
linear: https://linear.app/night-science-llc/project/ruleset-v2-hardened-vocabulary-resolution-chart-new-card-set-7f65436c0b01
supersedes:
---

# Spec: Ruleset v2 — hardened vocabulary, resolution chart, new card set

**Slug:** `ruleset-v2`  ·  **Change type:** vault (design only)  ·  **Status:** approved (Ben, 2026-11-06, four rounds, 26 clarifications incl. the T07 review decisions C18 to C26; signed off 2026-11-06)

This set changes no code. It produces the design canon the next implementation cycles are
specced from: a hardened glossary, a step-by-step resolution chart, the v2 rules, a 90-card
pool, ten Crew and six test decks, all as notes under `docs/rules/`. The scratch sheet it
grows from is [[cards/Cards]]. The rules as built today (rules version 6) are described in
[[systems/game-loop]] and [[systems/cards-crew-decks]]; those notes keep describing the code
and are not edited here.

## Intent

After this set, a designer or an implementer can open `docs/rules/` and find one answer to
"what does this word mean", "what happens next" and "what is in the game", written in a
closed vocabulary, with no sentence that depends on the old engine's names.

## Non-goals

- No engine, scene, data (`cards.json`, `crew.json`, `decks.json`) or bot change. Rules
  version stays 6 until an implementation cycle raises it.
- No edit to `docs/systems/*` (they describe the code as built), to `docs/cards/Cards.md`
  (Ben's scratch sheet, linked as the source) or to the archive.
- No art, no deck builder, no Linear project beyond what `/exercise` creates for this set.
- No final balance pass. Numbers in `cards-v2` are first-draft values with the guideline
  they were set by; tuning happens when the cards are played.
- No implementation sequencing beyond one paragraph in the plan.

## Actors

- **Ben**: decides, reads every note, signs each off.
- **Implementers** (vault): write the six notes from this spec.
- **Reviewer**: checks every rules sentence against the glossary.
- **Orchestrator**: dispatches, runs the link audit, commits.
- **Later readers**: the interrogator of each implementation cycle, and the implementer
  who turns a note into engine behaviour.

## Requirements (EARS)

"The canon" below means the set of notes under `docs/rules/`. "A rules sentence" is any
sentence in the canon that states how the game behaves, including card and Crew text.

### A. Vocabulary

- R1. The canon shall define each of these terms in the glossary with one meaning each:
  Match, Round, Turn, Walk, Commit, Score, Condemn, Squelch, Mute, Silence, Fleeting, Fade,
  Discard, Pile, Deck, Anchored, Power, Cost, Bonus, Mult, Add, Energy, Budget, Hand size,
  Owner, Controller, Reveal, Un-reveal, Memory, Board change, Pulse, Batch, Budget (trigger),
  and the trigger moments On reveal, On score, On commit, On start, On discard, On squelch,
  On empty draw, On moved, Ongoing.
- R2. The glossary shall list each retired word (flat, destroy, destroyed pile, burn,
  bonus-as-number, return) with the word that replaces it.
- R3. Every rules sentence in the canon shall use only glossary terms for the game concepts
  it names, so that a reader can resolve each noun and verb to one glossary entry.
- R4. The canon shall use Match for first to four Round wins, Round for seven Turns, Turn
  for one draw-commit-walk cycle, Walk for the scoring pass, Commit for the face-down
  placement, and Score as the noun for a seat's Walk total and the verb for a card adding
  points.

### B. Match, Round, Turn

- R5. The canon shall keep the match structure of today: a Match is won by the first seat to
  four Round wins, a Round is seven Turns, a tied Round awards no win, and after Round 7 the
  seat with more Round wins takes the Match, with sudden-death Rounds while they are level.
- R6. When a Round ends, the canon shall send every card on both rows to its owner's Pile and
  shall keep each seat's hand, deck and Pile as they are.
- R7. The canon shall keep today's commit order: the seat that won the previous Turn commits
  first; on Turn 1 of a Round the loser of the previous Round commits first; the first Turn
  of a Match is a seeded coin flip; a tied Turn keeps the order. After a tied Round there is
  no loser, so the alternation of first committer simply continues from the Round's last
  Turn into Turn 1 of the next Round (C25).
- R8. The canon shall define a Turn as these phases in order: turn start (each seat draws
  one card, then On start triggers), first commit, that seat's discard-down, second commit,
  that seat's discard-down, the Walk, turn end.
- R9. The canon shall define turn end as these steps in order: the At turn end triggers
  that fire before the exit pass, exit marks resolve (R35), the At turn end triggers that
  fire after the exit pass, turn-scoped statuses end, energy settles, the Turn's winner is
  recorded (C18).

### C. Energy

- R10. The canon shall give each seat a Budget on Turn N equal to N Energy, 1 on Turn 1 and 7
  on Turn 7, with unspent Energy lost at turn end unless an ability says otherwise.
- R11. Where an ability grants Energy ("+1 Energy this turn", Engineer's +1 each Turn from
  Turn 3), the canon shall add it to that Turn's Budget on top of R10.
- R12. The canon shall define a card's Cost as the Energy paid to commit it, reducible by
  abilities to no less than 0, and shall allow printed Costs above 7 only on cards whose text
  makes them reachable (the "costs 7 on Turn 7" card).

### D. Hand

- R13. The canon shall set the opening hand to four cards dealt once, at Match start.
- R14. The canon shall set the base Hand size to four, modified by Ongoing abilities and
  Crew (Quartermaster's seven, "your Hand size is +2").
- R15. The canon shall let a hand exceed its Hand size during a Turn: a draw always succeeds
  unless the deck is empty.
- R16. When a seat's commit is accepted, if that seat's hand holds more cards than its Hand
  size, the canon shall require the seat to choose exactly the excess from its hand, and
  shall send the chosen cards to its Pile as Discards, before the other seat commits or the
  Walk starts.
- R17. The canon shall perform no other hand-size check: not at turn end, not at round
  start, not on a draw.

### E. Deck and Pile

- R18. The canon shall set the Deck to exactly 40 cards with at most four copies of any one
  card, drawn from the whole pool with no strategy restriction.
- R19. The canon shall shuffle each Deck once, at Match start, and shall not refill or
  reshuffle it at Round start.
- R20. When a seat would draw from an empty Deck, the canon shall draw nothing and fire that
  seat's On empty draw triggers (Void, the pile-shuffling Crew).
- R21. The canon shall give each seat one Pile, face up and public to both seats, that
  receives every card that leaves a hand or a row for any reason other than returning to a
  hand, moving to a row or flipping face down.
- R22. The canon shall define Discard as a card entering a Pile from a hand (a chosen
  discard or the discard-down) or from a row (a Condemned card leaving at turn end, a card
  cleared at Round end), so On discard fires for all of them (Ben, Round 3: "a condemned
  card leaving to the pile IS a discard").
- R23. The canon shall keep each Pile for the whole Match; nothing is burned.
- R24. When a card enters a Pile, the canon shall reveal its identity to both seats.

### F. Card anatomy and scoring

- R25. The canon shall give every card a Cost, a Power (the points it adds when it Scores,
  today's "flat"), at most one printed Bonus, a strategy tag or "evergreen", and rules text;
  a card may have no Bonus and no rules text. Abilities may grant further Bonuses (R26).
- R26. The canon shall define a Bonus as either a Mult (multiplies the card's Bonus value,
  printed ×1.25, ×1.5 or ×2) or an Add (adds to the card's Bonus value, printed +0.25, +0.5
  or +1). A card may carry its printed Bonus plus any granted ones; when it Scores, all Adds
  apply, then all Mults (C20).
- R27. The canon shall let abilities grow a Bonus (Ben: "just like Balatro"): an ability
  states how much, an Add gaining +N, a Mult gaining +N or being multiplied by ×N (C19).
  Growth applies as base, then additive steps, then multiplicative steps, rounded to
  hundredths.
- R28. The canon shall define Score maths with a walking total (C21, reading 9a, open to
  Ben's veto). Each seat has a walking total that starts at 0 each Walk. When a card Scores,
  for its Controller's seat: (1) the walking total gains the card's Power; (2) the card's
  Bonus value starts at 1, then gains every Add, then is multiplied by every Mult; (3) the
  walking total is multiplied by the Bonus value (a card with no Bonus multiplies by 1). The
  seat's Walk Score is the walking total after its last Scoring card, rounded to a whole
  number once, at the end of the Walk (half rounds up). A negative Power still subtracts
  before the multiply.
- R29. The canon shall keep the memory rule: stat changes are board changes and end when the
  card leaves its row or the Round ends, unless the ability says "for the match" or
  "permanently", in which case they are Memory and follow the card everywhere.
- R30. The canon shall define Owner (the seat whose Deck the card came from) and Controller
  (the seat whose row it is on), and shall send a card to its Owner's Pile or hand whenever
  it leaves a row it does not Own.

### G. Statuses

- R31. The canon shall define exactly these statuses: Muted, Squelched, Silenced, Condemned,
  Fleeting, Fade, Anchored.
- R32. The canon shall define Muted as "the card's triggered abilities do not fire; it still
  Scores and its Ongoing abilities still apply", and Squelched as "the card does not Score
  and its Ongoing abilities stop; its triggered abilities still fire".
- R33. If a card is both Muted and Squelched, then the canon shall replace both with
  Silenced (no triggers, no Score, no Ongoing); when an effect removes Muted from a Silenced
  card it becomes Squelched, and when an effect removes Squelched from a Silenced card it
  becomes Muted (Ben, Round 2).
- R34. The canon shall require every status-granting ability to state its cessation: "until
  end of turn" by default, or "permanently" (Memory, follows the card), or a named end
  condition; a status with no stated cessation ends at turn end.
- R35. The canon shall define Condemned, Fleeting and Fade as exit marks: a card holds at
  most one, a newer mark replaces an older one, and at turn end the marks resolve in one
  pass (first committer's row first, slot order): Condemned goes to its Owner's Pile as a
  Discard, Fleeting goes to its Owner's hand, Fade flips face down in place keeping its
  Memory and losing its board changes.
- R36. The canon shall define Anchored as "cannot be moved by any effect"; a shift slides
  other cards past an Anchored card, and a swap, reverse or reorder leaves Anchored cards
  in their slots and permutes the rest.
- R37. The canon shall end every board-scoped status when the card leaves its row or is
  un-revealed; a "permanent" status is Memory and survives both.
- R38. The canon shall retire destroy: no card or Crew removes a card from a row before turn
  end, and every salvaged card that destroyed now Condemns.

### H. Movement

- R39. The canon shall define a move as a change of slot by an effect, and the row as a
  ring for stepwise moves: "move left" from the leftmost slot lands on the rightmost, and
  the reverse, while the Walk still reads left to right.
- R40. The canon shall define committing a card into a slot as placement, not a move: it
  may change other cards' indices without firing On moved or breaking an anchor.
- R41. The canon shall keep the cursor rules of [[specs/cycle-5-walk-cursor/spec]]: a pulse
  belongs to its slot, a card moved ahead of the cursor is reached later this Walk, a card
  moved behind it waits for the next Walk, and a card landing on the pulsed slot Scores now.

### I. Triggers and resolution

- R42. The canon shall contain a resolution chart that a reader can follow step by step from
  turn start to turn end, including every drain point of the trigger queue.
- R43. The canon shall resolve triggers breadth-first through one queue per Walk: a
  resolving effect never resolves the triggers it wakes inline; they are appended as a Batch
  and the queue drains fully before the pulse moves to its next stage (reveal stage, drain,
  score stage, drain).
- R44. When a Batch is created, the canon shall snapshot which cards and Crew are in it, so
  an effect that moves, un-reveals or Condemns a card cannot make it fire twice or skip it
  within that Batch.
- R45. Within one Batch, the canon shall order cards before Crew; among cards, this Turn's
  first committer's cards first then the second committer's, each seat by slot left to
  right; among one seat's Crew, slot order.
- R46. The canon shall give each pulse a budget of 50 trigger resolutions; when it is spent,
  every trigger still queued for that pulse fizzles with the reason "exhausted", visibly,
  and the Walk continues.
- R47. The canon shall read every variable amount (a Power, a Cost, cards in a Pile) at the
  moment the ability resolves, not when it was queued.
- R48. The canon shall define a retrigger ("trigger your other On reveals twice this turn")
  as one extra resolution of the same ability immediately after each resolution it applies
  to, with choices made again; retriggers stack by one resolution each and never apply to
  themselves.
- R49. The canon shall define "each card Scores twice this turn" as running the score stage
  of every pulse twice, each scoring running the three Score steps of R28 and firing On score.
- R50. The canon shall define the trigger moments: On reveal (the card flips face up in the
  Walk), On score (the card adds to the Score), On commit (its Controller's commit is
  accepted, before that seat's discard-down; fires for revealed row cards and for hand cards
  whose text says "while in your hand"; never for cards committed face down this Turn), On
  start (turn start after the draws, revealed cards only), On discard (a card enters a Pile,
  R22), On squelch (the card becomes Squelched alone; a Silenced card fires no triggers),
  On empty draw (R20), On moved (R39), At turn end (two points: before the exit pass and
  after it, each with its own drain, C18), Ongoing (never fires; read when needed).
- R51. The canon shall keep Crew firing only after the effect that caused them has fully
  resolved, as a Batch of their own (cycle 8 R46), and shall keep Crew as non-cards: never
  on a row, never a target, never Condemned, moved or copied.
- R52. The canon shall keep today's prompt rules: no eligible target fizzles, one eligible
  target is chosen automatically, two or more pause the Walk for a choice; Crew prompts are
  optional and may be skipped; the discard-down is a multi-select of exactly the excess.

### J. Hidden information

- R53. The canon shall keep today's information model: a seat sees its own hand, both rows'
  revealed cards, face-down cards as slots only, the other seat's hand and Deck counts, both
  Piles in full (R21), both seats' Crew, and the count and slots of a face-down commit.
- R54. While a card is in a hand or face down, the canon shall keep its effects, stats and
  Memory private to its Owner, and shall make them public when it is revealed or enters a
  Pile.

### K. Crew

- R55. The canon shall define exactly ten Crew: Tallyman, Shade, Veil, Navigator, Void,
  Engineer, Quartermaster, Salvager, Captain, and a tenth who, when its seat would draw from
  an empty Deck, shuffles that seat's Pile into its Deck first (working name Dredger).
- R56. The canon shall write each Crew's text in glossary terms with its trigger moment, its
  cessation where it grants a status, its uses and scope, and whether it prompts; Tallyman's
  "every 4 score triggers, +5 mult" is Mult ×2 on the seat's 5th, 10th, 15th ... Scoring
  card of a Walk (C23), Captain's "first card" is the leftmost slot, Void's "10 +2x1.5" is
  stated as Power 10 with Add +2 and Mult ×1.5 on its next Scoring card, or as Ben corrects.
- R57. The canon shall tag each Crew as evergreen or as serving one of the six strategies.
- R58. The canon shall keep three Crew per deck, chosen in the deck list, with sharing
  allowed.

### L. Card pool and decks

- R59. The canon shall list 90 cards: 10 for each of the six strategies (Greed, Combo,
  Disruption, Graveyard, Control, Ramp) and 30 evergreen cards, each with Cost, Power,
  Bonus, tag and rules text in glossary terms.
- R60. The canon shall seed the pool from the salvage table and the card ideas in
  [[cards/Cards]], rewriting every one into glossary terms (destroy to Condemn, flat to
  Power, "+N mult" to Add, "x1.25 Bonus" to Mult), and shall name the source line for each.
- R61. The canon shall follow this Power guideline and mark each exception with the reason:
  Power from Cost to Cost + 2 with no drawback, up to Cost + 4 with a drawback; Costs 1 to 7,
  with named exceptions (R12).
- R62. The canon shall give each strategy a one-paragraph plan: what it wants to do by Round
  2, by Round 5, and in the last two Rounds when Decks run dry (40 cards less the opening
  hand at one draw a Turn empties around Round 6 Turn 1 before effect draws).
- R63. The canon shall list six test decks, one per strategy, each exactly 40 cards (four
  copies of its strategy's ten) and three Crew, and shall state that they are fixtures for
  testing and bot training, not canon.
- R64. The canon shall retire Bloom, Ruin, Drift and Echo as deck fixtures; their names may
  survive only as flavour on individual cards whose design they inspired (Ben, Round 4:
  "loosely correlated to the card choices, but they are not 4 finite fixtures of the game").
- R65. The canon shall flag every card whose text creates a loop, a retrigger, an
  information leak from a face-down card, or a Controller change, with a one-line note on
  how the resolution chart handles it.

### M. The notes themselves

- R66. The canon shall live in `docs/rules/` as six notes of type `reference` (`glossary`,
  `resolution`, `rules-v2`, `cards-v2`, `crew-v2`, `test-decks`) plus a `rules-moc`, each
  with P5 frontmatter and a fresh uid, linked from [[home]].
- R67. Each canon note shall link to this spec, to [[cards/Cards]] where it draws on it, and
  to the as-built guide it will one day replace, and shall state in its first paragraph that
  it is design, not yet built.
- R68. When `obsidian-cli vault=docs unresolved` and `orphans` run after the notes are
  written, they shall report nothing new for `docs/rules/` or `docs/specs/ruleset-v2/`.
- R69. If a rules sentence in a canon note uses a word the glossary does not define for that
  concept, then the reviewer shall report it and the note shall not be accepted until it is
  fixed or the glossary gains the term.

## Clarifications (Ben, 2026-11-06)

| # | Question | Answer |
|---|---|---|
| C1 | Round 1 Q1: "+1 energy per turn, not +N" | 1a: Budget on Turn N is N, 28 a Round, unspent lost; Engineer is +1 on top (R10, R11) |
| C2 | Round 1 Q2: the Pile and the deck | 2a with amendments, Ben: "but if round 4 is when cards run dry, let's up the deck size to 40 and add a crew member who shuffles your pile when you draw on an empty deck". Deck and Pile persist for the Match, rows clear into the Pile at Round end, Deck 40, tenth Crew (R6, R18–R23, R55) |
| C3 | Round 1 Q3: card anatomy | 3a, Ben: "Bonuses can be increased by additive or multiplicative just like Balatro". Power replaces flat; one Bonus, Mult or Add; growth +0.25 or ×1.2 on a Mult, +1 on an Add (R25–R28) |
| C4 | Round 1 Q4: does destroy survive | 4a: retired; Condemn is the only removal; salvaged destroyers Condemn (R38) |
| C5 | Round 2 Q1: Muted and Squelched | 1b, Ben: "let's created a status called Silenced, which completely turns a card off. If a card is both Squelched and Muted, it instead becomes Silenced. Effects that remove muted turn silenced into squelched and vice versa. Additionally, these effects should come with a cessation clause. Mostly it'll be 'until end of turn', but some effects persist indefinitely or with a separate end condition." (R32–R34) |
| C6 | Round 2 Q2: stacked exit marks | 2a: one mark, latest wins; one turn-end pass in committer then slot order (R35) |
| C7 | Round 2 Q3: hand size 4 | 3a: no hard cap, one discard-down after the seat's own commit, discards go to the Pile and count as Discards, opening hand 4 (R13–R17) |
| C8 | Round 2 Q4: Anchored and the edge | 4a: ring movement, Anchored immovable, placement is not a move (R36, R39, R40) |
| C9 | Round 3 Q1: resolution model | 1a: one breadth-first queue per Walk, snapshot per Batch (R43, R44) |
| C10 | Round 3 Q2: order and loops | 2a: cards before Crew, first committer first, slot order; 50 resolutions per pulse then "exhausted" (R45, R46) |
| C11 | Round 3 Q3: twice and N | 3a: retriggers add one resolution each with fresh choices, N read at resolution, "Scores twice" runs the score stage twice (R47–R49) |
| C12 | Round 3 Q4: new trigger moments | 4a, Ben: "a condemned card leaving to the pile IS a discard" (R22, R50) |
| C13 | Round 4 Q1: pool size | 1d, Ben: "90 cards, 10 per strategy plus 30 evergreen/generically useful cards" (R59) |
| C14 | Round 4 Q2: Crew count and the tenth | 2a: ten Crew, three per deck, Dredger as the working name (R55–R58) |
| C15 | Round 4 Q3: constructed decks | 3a, Ben: "bloom, drift, ruin, and echo remain as loosely correlated to the card choices, but they are not 4 finite fixtures of the game" (R63, R64) |
| C16 | Round 4 Q4: where the canon lives | 4a: `docs/rules/`, six `reference` notes plus a MOC, implementers write, reviewer audits the vocabulary, Ben's read accepts (R66–R69) |
| C17 | Round 4 preamble, no objection | Match / Round / Turn / Walk / Commit / Score keep today's meanings (R4) |
| C18 | T07 review 1a: new trigger moment | A tenth moment, **At turn end**, with two points: one before the exit pass (Veil: swap a card's Condemned for Fleeting) and one after it (Shade: Un-reveal one of three random revealed cards of yours). Each point has its own drain in the resolution walkthrough (R9, R50) |
| C19 | T07 review 2a: widen growth | An ability states how much a Bonus grows: Add +N, Mult +N or ×N. Eddy, Scrap and Idler are legal as written (R27) |
| C20 | T07 review 3a: granted Bonuses stack | A card may carry its printed Bonus plus any granted ones (Void, Tallyman, Idler ...); when it Scores all Adds apply, then all Mults. "At most one Bonus" is amended to "at most one printed Bonus" (R25, R26) |
| C21 | T07 review 9a (reading 9a, open to Ben's veto): Score rule | Ben: "A card's power adds to the walking total, then a card's flat bonus adds to its bonus, then its mult bonus multiplies the bonus, then the bonus is applied to the walking total. That's what happens when a card scores." and "We want the order of cards to be very important in maximizing your score". Each seat has a walking total starting at 0 each Walk; a Scoring card adds its Power, builds its Bonus value (1, plus Adds, times Mults) and multiplies the walking total by it. Replaces the running multiplier (R28). Consequence: the printed Bonuses of `cards-v2` are re-tuned (Adds in +0.25 / +0.5 steps, Mults ×1.25 to ×2) and a Bonus on the far right of a row is the strongest |
| C22 | T07 review 4a: Silenced halves | Each half keeps its own end condition; when one half ends the card is left with the other (R33) |
| C23 | T07 review 5a: Tallyman | Ben: "The math should work out that every 5th score is doubled, like tally marks." Tallyman: your 5th, 10th, 15th ... Scoring card in a Walk gets Mult ×2 for that Score; a card that Scores twice counts twice; no longer +5 Add (R56) |
| C24 | T07 review 6a: "cannot be X" vs Silence | Ward ("cannot be Muted") blocks the Mute half of a Silence, so the card ends up Squelched only; the same pattern holds for any "cannot be X". Stasis protects the Squelch half of a Silence the same way: that half lasts until Stasis leaves your row |
| C25 | T07 review 7a: tied Round | After a tied Round, alternation of first committer simply continues from the last Turn into Turn 1 of the next Round (R7) |
| C26 | T07 review 8a: scratch sheet | Ben's scratch sheet `docs/cards/Cards.md` is committed on the branch; `[[cards/Cards]]` resolves |
| C27 | T08 read-through, Saboteur | Ben asked about Power -3 with ×0.5; at ×0.5 on the far right it halves the opponent's Walk Score for Cost 3, so the orchestrator offered tunings and Ben chose (a): "Go with a". Saboteur is Cost 4, Power -3, Mult ×0.75; landing last on the opposing row it takes about a quarter of that Walk Score |

Defaults stated by the interrogator and open to Ben's veto at sign-off (none changes a
decision above): the Pile is public and face up (R21, R24); opening hand dealt once at
Match start (R13); a card that leaves a row it does not Own goes to its Owner (R30); a
seat's Walk Score may go negative; a Mult below 1 simply multiplies, a negative walking
total is multiplied like any other, and a Bonus value never falls below 0 (R28, choices
of the T07 fix, flagged); board-scoped statuses also end on un-reveal
(R37); growth applies base, additive, then multiplicative (R27); Void's text reading
(R56).

## Scenarios

- **Given** Turn 3, seat 0 committed first with a revealed card reading "On commit: select
  one card on the board and Squelch it until end of turn", **when** seat 0's commit is
  accepted, **then** the prompt opens for seat 0 before seat 1 commits, the chosen card is
  Squelched, seat 1 sees the Squelch badge, and the status ends at turn end (R16 order,
  R34, R50).
- **Given** a card with Power 4 holding Fleeting, **when** an enemy effect Condemns it,
  **then** it holds only Condemned, still Scores this Walk, and goes to its Owner's Pile at
  turn end as a Discard, firing On discard watchers on both rows (R22, R35).
- **Given** a Muted card on a row, **when** an effect Squelches it, **then** it is Silenced;
  **when** a later effect ends the Mute, **then** it is Squelched and its triggers fire
  again (R33).
- **Given** "On reveal: trigger your other On reveals twice this turn" revealed at slot 0,
  **when** a card at slot 2 reading "On reveal: discard a card in your hand, +N Add where N
  is read from its Cost" reveals, **then** it resolves, then resolves again with a new discard choice
  and N re-read from the second card (R47, R48).
- **Given** two cards that each say "On score: Condemn a random enemy card, then this card
  Scores again", **when** they feed each other within one pulse, **then** after 50
  resolutions the rest fizzle as "exhausted" and the Walk moves on (R46).
- **Given** Round 6 Turn 1 with an empty Deck and Dredger, **when** the seat draws,
  **then** its Pile is shuffled into its Deck and the draw succeeds; **given** Void instead,
  **then** nothing is drawn and Void's grant applies to the seat's next Scoring card (R20,
  R55).
- **Given** seat 1 holds six cards after drawing, with Hand size 4, **when** seat 1's commit
  of one card is accepted, **then** seat 1 must choose exactly one card to Discard before
  the Walk starts (R16).
- **Given** a row A B C with B Anchored, **when** "your other cards each move one slot left"
  resolves, **then** C slides past B to slot 0 and A wraps to the far right, B stays in slot
  1 (R36, R39).
- **Given** the six canon notes written, **when** the reviewer reads `cards-v2`, **then**
  every card's text resolves to glossary terms or the note is sent back (R69).

## Data touched

- New: `docs/specs/ruleset-v2/{spec,plan,tasks}.md` (this set); by its tasks,
  `docs/rules/{rules-moc,glossary,resolution,rules-v2,cards-v2,crew-v2,test-decks}.md`; one
  row in [[specs/specs-moc]]; one line in [[home]].
- Read only: [[cards/Cards]], `docs/systems/*`, `docs/planning/*`, the cycle specs,
  `godot/engine/*` (to know what today's rules are), the archive's `Game/Systems/*`.
- Never: `godot/`, `scripts/`, `.claude/`, `docs/.obsidian/`, the archive, Ben's
  uncommitted edits to `docs/systems/bot-training.md` and `cards-crew-decks.md`.

## Definition of done

- [ ] The seven notes exist under `docs/rules/` with P5 frontmatter and fresh uids, linked
      from [[home]] (R66).
- [ ] Every one of R1's terms has a glossary entry and R2's retired words are listed.
- [ ] The resolution chart walks a turn end to end with every drain point and the budget
      (R42–R46), and each scenario above can be traced through it.
- [ ] `cards-v2` lists 90 cards (6 × 10 tagged plus 30 evergreen), every salvaged card and
      idea from [[cards/Cards]] accounted for (used, merged or dropped with a reason).
- [ ] `crew-v2` lists ten Crew; `test-decks` lists six 40-card decks with three Crew each
      and the fixture disclaimer.
- [ ] The reviewer's vocabulary audit reports no unresolved word (R69).
- [ ] `obsidian-cli vault=docs unresolved` and `orphans` report nothing new (R68).
- [ ] `make check` is green (no code is touched; this confirms nothing slipped in).
- [ ] No screenshot: a vault-only set (P7 applies to visible features).
- [ ] Ben has read each note and signed it off.
- [ ] Spec, plan and tasks signed off by Ben and committed before the notes are written.
