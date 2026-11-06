---
type: reference
tags: [reference, rules-v2, glossary]
status: seedling
related: ["[[specs/ruleset-v2/spec]]", "[[rules/rules-moc]]", "[[rules/glossary]]", "[[systems/game-loop]]", "[[systems/cards-crew-decks]]", "[[cards/Cards]]"]
created: 2026-11-06
updated: 2026-11-06
uid: 50ec83af-22d5-4bb1-9262-1e94e9a6cfac
linear: https://linear.app/night-science-llc/issue/NSC-137/t01-glossary
supersedes:
---

# Glossary (ruleset v2)

This note is design for ruleset v2, not yet built. It fixes the one meaning of each word the
rest of the canon uses. The game as it runs today (rules version 6) is described in
[[systems/game-loop]] and [[systems/cards-crew-decks]]; "today's name" below always points
there. The requirements come from [[specs/ruleset-v2/spec]] and the scratch sheet
[[cards/Cards]]. Every other canon note ([[rules/rules-v2]], [[rules/resolution]],
[[rules/crew-v2]], [[rules/cards-v2]], [[rules/test-decks]]) is written against this one and
is read from [[rules/rules-moc]].

A rules sentence anywhere in the canon may name a game concept only with a word defined
here (spec R3). Where a term is a number, the number itself lives in [[rules/rules-v2]];
this note says what the term means.

## 1. Structure of play

| Term | Meaning | Moment or zone | Today's name |
|---|---|---|---|
| Match | The whole game, won by the first seat to four Round wins. | Match start to Match end | Match (same) |
| Round | Seven Turns; the seat that wins more of them takes the Round, and a tied Round awards no win. | Round start to Round end; cards on both rows go to their Owners' Piles at the end | Round (same) |
| Turn | One cycle of draw, Commit, Walk and turn end. | Turn start to turn end | Turn (same) |
| Walk | The scoring pass: a cursor steps along both rows, revealing and Scoring cards. | Between the second Commit and turn end | Walk (same) |
| Commit | Placing cards face down from a hand into slots on a row, paying their Cost. | The two commit phases of a Turn | Commit (same) |
| Score | As a noun, a seat's total from one Walk; as a verb, a card adding its points to that total. | The Walk | Score (same) |

Note on winning: a Turn's winner is the seat with the higher Score from that Turn's Walk. A
Round's winner is decided by Turn wins, as today (spec R5). After Round 7 the seat with more
Round wins takes the Match, with sudden-death Rounds while they are level.

## 2. Zones, cards and ownership

| Term | Meaning | Moment or zone | Today's name |
|---|---|---|---|
| Deck | A seat's face-down draw stack, exactly 40 cards with at most four copies of a card. | Shuffled once at Match start; never refilled at Round start | Deck, 20 cards today, refilled and reshuffled at Round start |
| Pile | A seat's single face-up public zone that receives every card leaving a hand or a row, except by return to hand, move to a row or flip face down; it lasts the whole Match. | Public to both seats | Destroyed pile plus burn pile |
| Discard | A card entering a Pile from a hand (a chosen discard or the discard-down) or from a row (a Condemned card leaving at turn end, a card cleared at Round end). | The moment of entering a Pile; fires On discard | Discard from hand, destroyed card moving to the destroyed pile |
| Hand size | The number of cards a seat may hold after its own Commit; the base is four, changed by Ongoing abilities and Crew. | Checked once per Commit, never at any other time | Hand cap of 7, a card drawn at the cap is burned |
| Owner | The seat whose Deck the card came from. | Fixed for the card's life in the Match | Origin (the "origin's deck") |
| Controller | The seat whose row the card is on. | Changes only while the card is on a row it does not Own | Controller (same) |

A card that leaves a row it does not Own goes to its Owner's Pile or hand (spec R30).

## 3. Energy

| Term | Meaning | Moment or zone | Today's name |
|---|---|---|---|
| Energy | The resource a seat spends to Commit cards. | Spent at Commit; unspent Energy is lost at turn end unless an ability says otherwise | Energy (same); today unspent energy can carry |
| Budget | The Energy a seat has to spend on a Turn: N on Turn N, plus any Energy an ability grants that Turn. | One Turn | Budget (today it is the turn number plus carried energy) |
| Cost | The Energy a card takes to Commit, reducible by abilities to no less than 0. | Read at Commit | Cost (same), also "effective cost" |

## 4. Card anatomy and Score maths

| Term | Meaning | Moment or zone | Today's name |
|---|---|---|---|
| Power | The points a card adds when it Scores; it may be negative. | Read at Score | Flat |
| Bonus | A card's single modifier of the running multiplier, either a Mult or an Add, applied before the card Scores. | Applied in the score stage of the card's pulse | Bonus (the x-part and the plus-part) |
| Mult | A Bonus that multiplies the seat's running multiplier; printed x1.25, x1.5 or x2. | As Bonus | The times-bonus, "x bonus" |
| Add | A Bonus that adds whole units to the seat's running multiplier; printed +1 or +2. | As Bonus | The plus-bonus, "+ bonus", "+N mult" in Cards.md |
| Memory | Changes that follow the card everywhere because the ability said "for the match" or "permanently". | Survives leaving the row, a Round end and un-reveal | Card memory (same) |
| Board change | A stat change that ends when the card leaves its row or the Round ends. | While on a row | Board changes (same) |

The running multiplier is a seat's multiplier during one Walk: it starts at x1.00, each
card's Bonus adjusts it, and the card then adds floor(Power times running multiplier) to
the seat's Score (spec R28).

A Bonus grows additively or multiplicatively (spec R27): a Mult may gain +0.25 or be
multiplied by x1.2, an Add may gain +1; growth applies as base, then additive steps, then
multiplicative steps, rounded to hundredths.

## 5. The Walk

| Term | Meaning | Moment or zone | Today's name |
|---|---|---|---|
| Reveal | A face-down card flips face up as the cursor reaches it. | Reveal stage of a pulse; fires On reveal | Reveal (same) |
| Un-reveal | A revealed card flips face down in its slot; it loses its Board changes and keeps its Memory. | Fade at turn end, or an effect | Un-reveal (same) |
| Pulse | One step of the Walk's cursor on one slot: a reveal stage, a drain, a score stage, a drain. | The Walk | Pulse (same) |
| Batch | The set of triggers woken by one resolution, appended to the queue together; its cards and Crew are snapshotted when it is created. | The Walk | Watcher list (snapshotted) |
| Budget (trigger) | The limit of 50 trigger resolutions per pulse; when spent, every queued trigger of that pulse fizzles with the reason "exhausted". | One pulse | New in v2 |

## 6. Statuses and actions on cards

| Term | Meaning | Moment or zone | Today's name |
|---|---|---|---|
| Condemn | Mark a card to be Discarded at turn end; it still Scores this Walk. | Applied now, resolved at turn end | Destroy (retired) |
| Squelch | Make a card stop Scoring and stop its Ongoing abilities, while its triggered abilities still fire. | Until its cessation | New in v2 |
| Mute | Make a card's triggered abilities not fire, while it still Scores and its Ongoing abilities apply. | Until its cessation | New in v2 |
| Silence | Make a card entirely inert: no triggers, no Score, no Ongoing; formed when a card is both Muted and Squelched. | Until its cessation | New in v2 |
| Fleeting | An exit mark: the card goes to its Owner's hand at turn end. | Resolved at turn end | Return, "returns to your hand at the end of the turn" |
| Fade | An exit mark: the card Un-reveals in place at turn end, keeping Memory and losing Board changes. | Resolved at turn end | Echo's turn-end flip, "unreveal" |
| Anchored | A status: the card cannot be moved by any effect. | Until its cessation | New in v2 |

Condemn, Squelch, Mute, Silence are verbs for applying the status of the same name. Fleeting,
Fade and Anchored are given to a card ("target card gets Fleeting"); the game also says
Condemn for the verb that gives the Condemned status.

## 7. Supporting terms

These are not in the spec's term list but the entries above need them. Each has one meaning.

| Term | Meaning |
|---|---|
| Seat | One of the two sides of a Match, numbered 0 and 1; owns a hand, a Deck, a Pile, a row and Crew. |
| Hand | The cards a seat holds, private to that seat. |
| Row | A seat's line of slots on the board; the Walk reads it left to right. |
| Slot | One position on a row, counted from 0 on the left. |
| Face down, face up | A face-down card shows only its slot to the other seat; a face-up (revealed) card shows its identity to both. |
| Draw | Take the top card of the Deck into the hand; if the Deck is empty, draw nothing and fire On empty draw. |
| Crew | A non-card helper a seat brings to the Match; never on a row, never a target, never moved or copied. Three per Deck. |
| Discard-down | After a seat's Commit is accepted, choosing exactly the excess cards over its Hand size and Discarding them. |
| Exit mark | One of Condemned, Fleeting, Fade; a card holds at most one and a newer mark replaces the older. |
| Cessation | The stated end of a status: "until end of turn" (the default), "permanently" (it is Memory), or a named end condition. |
| Move | A change of slot made by an effect; on a ring, so the leftmost slot is next to the rightmost for stepwise moves. |
| Placement | Committing a card into a slot; not a Move. |
| Retrigger | An extra resolution of the same ability immediately after each resolution it applies to, with choices made again. |
| Queue | The one first-in, first-out line of Batches per Walk; it drains fully before the pulse moves to its next stage. |
| Prompt | A pause in the Walk for a choice by a seat; with no eligible target the effect fizzles, with one it is chosen automatically. |
| Fizzle | An effect that does nothing, with a stated reason ("no target", "exhausted"). |
| Turn end | The last phase of a Turn: exit marks resolve, Turn-scoped statuses end, Energy settles, the Turn's winner is recorded. |
| Strategy | One of Greed, Combo, Disruption, Graveyard, Control, Ramp, or evergreen; a tag on every card and Crew. |

## 8. Retired words

None of these appear in a rules sentence of the canon. The table below is the only place
they are used (spec R2, R38, R64).

| Retired word | Replaced by | Why |
|---|---|---|
| flat | Power | One name for the points a card adds when it Scores |
| destroy, destroyed | Condemn, Condemned | Condemn removes a card at turn end, so its current Score survives and the Walk's slots stay stable (Cards.md note) |
| destroyed pile | Pile | One public Pile per seat holds every card that leaves play |
| burn, burned, burn pile | Pile (nothing is burned) | Piles last the whole Match; there is no hand-cap burn |
| bonus (as a number) | Mult or Add | "Bonus" now names the slot on the card, never the number inside it |
| return, returns | Fleeting | A card that goes to its Owner's hand at turn end holds Fleeting |

Names kept as flavour only: Bloom, Ruin, Drift and Echo (spec R64). They are no longer
deck fixtures.

## 9. Status table

Statuses are exactly these seven (spec R31). Every status-granting ability states its
cessation (R34); a status with no stated cessation ends at turn end.

| Status | What it stops | Default end | Badge word |
|---|---|---|---|
| Muted | The card's triggered abilities do not fire; it still Scores and its Ongoing abilities still apply. | Turn end | Muted |
| Squelched | The card does not Score and its Ongoing abilities stop; its triggered abilities still fire. | Turn end | Squelched |
| Silenced | Everything: no triggers, no Score, no Ongoing. | Per half, see below | Silenced |
| Condemned | Nothing now. At turn end the card is Discarded to its Owner's Pile. | Resolved at turn end | Condemned |
| Fleeting | Nothing now. At turn end the card goes to its Owner's hand. | Resolved at turn end | Fleeting |
| Fade | Nothing now. At turn end the card Un-reveals in place, keeping Memory and losing Board changes. | Resolved at turn end | Fade |
| Anchored | The card cannot be moved by any effect: a shift slides other cards past it, a swap, reverse or reorder leaves it in its slot and permutes the rest. | Turn end, unless the ability names another | Anchored |

**How Silenced forms and splits (spec C5, R33).**

- Forms: if a card is both Muted and Squelched, it becomes Silenced and the two are replaced
  by the one status.
- Splits: when an effect removes Muted from a Silenced card, it becomes Squelched; when an
  effect removes Squelched from a Silenced card, it becomes Muted.
- Each half keeps the cessation of the application that made it. When a half ends by its own
  cessation, the card becomes the other status; when both have ended, the card is clear.
  (This last sentence is my reading of C5's "cessation clause" and is flagged for Ben.)
- Silencing a card directly with an effect gives both halves with that effect's cessation.

**Exit marks (spec R35).** A card holds at most one of Condemned, Fleeting, Fade. A newer
mark replaces an older one. At turn end the marks resolve in one pass, the first committer's
row first, then the second's, in slot order.

**Scope (spec R37).** Every board-scoped status ends when the card leaves its row or is
Un-revealed; a "permanent" status is Memory and survives both.

## 10. Trigger moments

Every ability has exactly one trigger moment (spec R50).

| Moment | Fires when | Who it fires for |
|---|---|---|
| On reveal | The card flips face up in the Walk. | That card |
| On score | The card adds to the Score. | That card, and abilities that react to a Score |
| On commit | Its Controller's Commit is accepted, before that seat's discard-down. | Revealed row cards, and hand cards whose text says "while in your hand"; never cards committed face down this Turn |
| On start | Turn start, after the draws. | Revealed cards only |
| On discard | A card enters a Pile (see Discard, section 2). | Abilities that react to a Discard |
| On squelch | The card becomes Squelched or Silenced, once per application. | That card |
| On empty draw | A seat would draw from an empty Deck. | That seat's abilities and Crew, such as Void and the Pile-shuffling Crew |
| On moved | The card changes slot by a Move (not by Placement). | That card, and Crew that react to a Move |
| Ongoing | Never fires; the engine reads it when the value is needed. | Everything it applies to |

Crew fire only after the effect that caused them has fully resolved, as a Batch of their own
(spec R51).

## Coverage check

All of spec R1's terms have an entry above: Match, Round, Turn, Walk, Commit, Score,
Condemn, Squelch, Mute, Silence, Fleeting, Fade, Discard, Pile, Deck, Anchored, Power, Cost,
Bonus, Mult, Add, Energy, Budget, Hand size, Owner, Controller, Reveal, Un-reveal, Memory,
Board change, Pulse, Batch, Budget (trigger), and the nine trigger moments. R2's six
retired words are in section 8.
