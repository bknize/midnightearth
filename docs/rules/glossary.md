---
type: reference
tags: [reference, rules-v2, glossary]
status: built
related: ["[[specs/ruleset-v2/spec]]", "[[rules/rules-moc]]", "[[systems/game-loop]]", "[[systems/cards-crew-decks]]", "[[cards/Cards]]"]
created: 2026-11-06
updated: 2026-11-06
uid: 50ec83af-22d5-4bb1-9262-1e94e9a6cfac
linear: https://linear.app/night-science-llc/issue/NSC-137/t01-glossary
supersedes:
---

# Glossary (ruleset v2)

The rules in this note are built since DC-14 (rules version 7); the DC-13 and DC-14 rows of
[[planning/cycles]] record how and the readings made on the way. It fixes the one meaning of
each word the rest of the canon uses. The game as built is described in
[[systems/game-loop]] and [[systems/cards-crew-decks]]; "today's name" below is the name
under rules version 6, which those guides list in their "Changed from v6" tables. The requirements come from [[specs/ruleset-v2/spec]] and the scratch sheet
[[cards/Cards]]. Every other canon note ([[rules/rules-v2]], [[rules/resolution]],
[[rules/crew-v2]], [[rules/cards-v2]], [[rules/test-decks]]) is written against this one and
is read from [[rules/rules-moc]].

A rules sentence anywhere in the canon may name a game concept only with a word defined
here (spec R3). Where a term is a number, the number itself lives in [[rules/rules-v2]];
this note says what the term means. Multipliers are written with the sign ×.

## 1. Structure of play

| Term | Meaning | Moment or zone | Today's name |
|---|---|---|---|
| Match | The whole game, won by the first seat to four Round wins. | Match start to Match end | Match (same) |
| Round | Seven Turns; the seat that wins more of them takes the Round, and a tied Round awards no win. | Round start to Round end | Round (same) |
| Turn | One cycle of draw, Commit, Walk and turn end. | Turn start to turn end | Turn (same) |
| Walk | The scoring pass: a cursor steps along both rows, revealing and Scoring cards. | Between the second Commit and turn end | Walk (same) |
| Commit | Placing cards face down from a hand into slots on a row, paying their Cost. | The two commit phases of a Turn | Commit (same) |
| Pass | A Commit of zero cards; it is still an accepted Commit. | A commit phase | Pass, "committed nothing" |
| Score | As a noun, a seat's Walk Score (the rounded walking total after its last Scoring card); as a verb, a card adding its Power to its Controller's walking total, then multiplying that total by its Bonus value. | The Walk | Score (same) |
| Match start | The moment the Match begins: Decks are shuffled once and each seat is dealt its opening hand. | Once per Match | Match setup |
| Match end | The moment a seat has four Round wins, or has more Round wins after Round 7 with no sudden-death Round left. | Once per Match | Match over |
| Round start | The moment a Round begins; Turn 1 follows. Nothing is refilled or reshuffled. | Once per Round | Round setup |
| Round end | The moment after Turn 7: every card on both rows is Discarded to its Owner's Pile, then the Round is awarded. | Once per Round | Round end (same) |
| Turn start | The first phase of a Turn: each seat draws one card, then On start triggers fire. | Once per Turn | Turn start (same) |
| Turn end | The last phase of a Turn: the At turn end triggers before the exit pass, the exit pass, the At turn end triggers after it, turn-scoped statuses end, Energy settles, the Turn's winner is recorded. Also a trigger moment (section 10). | Once per Turn | Turn end (same) |
| Turn win | The Turn's result for the seat with the higher Score; a tied Turn is no win and keeps the commit order. | Recorded at turn end | Turn win (same) |
| Round win | The Round's result for the seat with more Turn wins; a tied Round awards none. | Awarded at Round end | Round win (same) |
| Opening hand | The four cards each seat is dealt once, at Match start. | Match start | Hand dealt 3 each Round |
| Coin flip | The seeded random choice of which seat commits first on the first Turn of a Match. | Match start | Coin flip (same) |
| First seat, second seat | The seat that commits first this Turn, and the other; the first seat's cards come first in every order the canon defines. | One Turn | First committer |

Note on winning: a Turn's winner is the seat with the higher Score from that Turn's Walk. A
Round's winner is decided by Turn wins, as today (spec R5). After Round 7 the seat with more
Round wins takes the Match, with sudden-death Rounds while they are level.

## 2. Zones, cards and ownership

| Term | Meaning | Moment or zone | Today's name |
|---|---|---|---|
| Deck | A seat's face-down draw stack, exactly 40 cards with at most four copies of a card. | Shuffled once at Match start; never refilled at Round start | Deck, 20 cards today, refilled and reshuffled at Round start |
| Pile | A seat's single face-up public zone that receives every card leaving a hand or a row, except a card going to its Owner's hand (Fleeting), moving to a row or flipping face down; it lasts the whole Match. | Public to both seats | Destroyed pile plus burn pile |
| Leaving a Pile | A card leaves a Pile by being shuffled into a Deck (Exhume, Reset, the Pile-shuffling Crew) or put on a row (Revive). It is not a Discard, and its Memory goes with it. | A Pile | New in v2 |
| Discard | A card entering a Pile from a hand (a chosen discard or the discard-down) or from a row (a Condemned card leaving at turn end, a card cleared at Round end). | The moment of entering a Pile; fires On discard | Discard from hand, destroyed card moving to the destroyed pile |
| Hand size | The number of cards a seat may hold after its own Commit. The base is four. Where abilities change it, every "your Hand size is N" (a set) applies first, the highest set winning, then every "+N" (an addition): Quartermaster's 7 with Pantry's +2 is 9. | Checked once per Commit, never at any other time | Hand cap of 7, a card drawn at the cap is burned |
| Owner | The seat whose Deck the card came from; for a created card, the seat it is created for. | Fixed for the card's life in the Match | Origin (the "origin's deck") |
| Controller | The seat whose row the card is on; for an ability, the seat it acts for (see "you, your"). | Changes only while the card is on a row it does not Own | Controller (same) |

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
| Power | The points a card adds to its Controller's walking total when it Scores; it may be negative. | Read at Score | Flat |
| Bonus | A modifier of a card's Bonus value, either a Mult or an Add. A card has at most one printed Bonus and may be granted more; all of them apply when it Scores. | The score stage of the card's pulse | Bonus (the x-part and the plus-part) |
| Mult | A Bonus that multiplies the card's Bonus value; printed ×1.25, ×1.5 or ×2. | As Bonus | The times-bonus, "x bonus" |
| Add | A Bonus that adds to the card's Bonus value; printed +0.25, +0.5 or +1. | As Bonus | The plus-bonus, "+ bonus", "+N mult" in Cards.md |
| Bonus value | The number a card multiplies its seat's walking total by when it Scores: it starts at 1, gains every Add, is then multiplied by every Mult, and is never below 0. A card with no Bonus has a Bonus value of 1. | One Score of one card | Running multiplier (retired) |
| Walking total | A seat's points during one Walk. It starts at 0 each Walk; each Score adds the card's Power, then multiplies the total by the card's Bonus value. | One Walk, per seat | Running multiplier and Score (retired) |
| Scoring card | A card that Scores in the Walk: revealed in its pulse and not Squelched or Silenced. | The score stage | Scoring card (same) |
| Grant | An ability giving a card a change: "gets Power +N", "gets Add +N", "gets Mult ×N". It is a Board change unless the text says "for the match" or "permanently", and it ends as its text says. | Until its stated end | Flat or bonus gain |
| Memory | Changes that follow the card everywhere because the ability said "for the match" or "permanently". | Survives leaving the row, a Round end and un-reveal | Card memory (same) |
| Board change | A stat change that ends when the card leaves its row or the Round ends. | While on a row | Board changes (same) |
| Rules text | The abilities printed on a card or Crew; a card with none is a plain body. | Always | Text |

**Score maths (spec R28, C21).** When a card Scores, for its Controller's seat, in this order:
(1) the seat's walking total gains the card's Power; (2) the card's Bonus value starts at 1,
gains every Add it carries, then is multiplied by every Mult it carries; (3) the walking
total is multiplied by the Bonus value. A card Scores for its Controller's seat, whoever
Owns it. The seat's Score for the Walk is its walking total after its last Scoring card,
rounded to a whole number once, at the end of the Walk, half rounding up; nothing is rounded
in between. A negative Power subtracts before the multiply. A Mult below 1 simply
multiplies, and a negative walking total is multiplied like any other (a Mult above 1 makes
it more negative). Order of cards therefore matters: Power added early is multiplied by
every later Bonus, and a Bonus on the far right of a row multiplies the whole total.

A Bonus grows by an ability that states how much (spec R27): an Add gains +N, a Mult gains
+N or is multiplied by ×N. Growth applies as the base value, then the additive steps, then
the multiplicative steps, rounded to hundredths. When a card carries several Bonuses, all
Adds apply, then all Mults.

## 5. The Walk

| Term | Meaning | Moment or zone | Today's name |
|---|---|---|---|
| Reveal | A face-down card flips face up as the cursor reaches it. | Reveal stage of a pulse; fires On reveal | Reveal (same) |
| Un-reveal | A revealed card flips face down in its slot; it loses its Board changes and keeps its Memory. | Fade at turn end, or an effect | Un-reveal (same) |
| Cursor | The marker that steps along the slots of both rows during the Walk, first seat's row first at each slot. | The Walk | Cursor (same) |
| Pulse | One step of the Walk's cursor on one slot: a reveal stage, a drain, a score stage, a drain. | The Walk | Pulse (same) |
| Stage | One part of a pulse: the reveal stage (the card flips and On reveal wakes) or the score stage (the card Scores and On score wakes). | A pulse | Stage (same) |
| Drain | The queue emptying fully, with prompts and the Budget (trigger) applied; the points where it happens are named D1 to D12 in [[rules/resolution]]. | After a stage or phase | New in v2 |
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

### Verbs on cards and rows

| Verb | Meaning |
|---|---|
| choose | The ability's Controller picks, unless the text names the chooser ("each seat chooses"). A chosen card may be face down; the chooser sees its slot only. With no eligible choice the effect fizzles ("no target"). |
| chosen card | The card a "choose" picked. The choice is kept as long as the text says; it ends when the chosen card or the card that chose it leaves its row or is Un-revealed. |
| random | Picked with the Match's seeded RNG, by slot, with no identity shown. |
| shuffle (into) | Put a card from a Pile or hand into a Deck at a random position, using the seeded RNG. |
| create | Make a new card that is in no Deck, in the place the text names. Its Owner is the seat it is created for; it has base values and no Memory. It is not part of the 40-card Deck. |
| copy | As "create a copy": a new card with the same base values and no Memory. As "copies its Power and Bonus": takes the current values until the stated end. |
| look at | Show the identity of a card to the looking seat only; nothing is made public. |
| shift | Move a card one slot in a direction; other cards slide past Anchored cards. |
| swap | Two cards trade slots; with an Anchored card among them it fizzles. |
| reverse | The row's order is flipped; Anchored cards stay in their slots and the rest are permuted around them. |
| reorder | The row's cards are permuted at random; Anchored cards stay in their slots. |
| "cannot be X" | While it applies, status X (or the event X) cannot be applied to the card: an effect that would apply X to it does not apply X. If the effect applies several things (Silence is a Mute and a Squelch), only the blocked part is dropped: a card that "cannot be Muted" which is Silenced becomes Squelched only (spec C24). It does not end an X already in place. |
| "instead" | A replacement effect: when the stated event would happen, the replacement happens instead and the stated event does not, so its triggers do not fire (Wraith, Fence). Where two replacements meet on one event, the one that acts first in the order of rule Q3 applies and the event is replaced once. |

## 7. Supporting terms

These are not in the spec's term list but the entries above need them. Each has one meaning.

| Term | Meaning |
|---|---|
| Seat | One of the two sides of a Match, numbered 0 and 1; owns a hand, a Deck, a Pile, a row and Crew. |
| Walk end | The moment after the last Scoring card of a Walk and before its walking totals are rounded; an Ongoing that names it applies there once. |
| Reveal-stage hook | The point in a pulse after the reveal-stage drain (D7) and before the score stage; a text that says "after its On reveal resolves and before it Scores" acts here ([[rules/resolution]] step 10). |
| Dross | A created card (Litter makes it): Cost 1, Power 0, no Bonus; Ongoing (while in your hand): at Walk end your walking total is multiplied by ×0.75 for each Dross in your hand. Owned by the seat whose hand it was created in ([[rules/cards-v2]]). |
| Opponent, opposing | The opponent is the other seat than "you"; opposing means on the opponent's row (or, for a hand or a Pile, the opponent's). |
| you, your | In card and Crew text, the ability's Controller: for a card on a row, its Controller; for a hand card, the holding seat; for a Crew, the Crew's seat. |
| Hand | The cards a seat holds, private to that seat. |
| Row | A seat's line of slots on the board; the Walk reads it left to right. A row has no size cap: Placement and effects may take it past seven cards. |
| Slot | One position on a row, counted from 0 on the left. |
| Leftmost, rightmost | The slot with the lowest, or the highest, number on a row that holds a card. |
| Ring | The row seen as a loop for stepwise moves: the leftmost slot is next to the rightmost. The Walk does not use it. |
| Face down, face up | A face-down card shows only its slot to the other seat; a face-up (revealed) card shows its identity to both. |
| Badge | The word shown on a card for each status it holds (section 9). |
| Draw | Take the top card of the Deck into the hand; if the Deck is empty, draw nothing and fire On empty draw. |
| Crew | A non-card helper a seat brings to the Match; never on a row, never a target, never moved or copied. Three per Deck. |
| Crew slot | A Crew's position in its deck list; it sets the order among a seat's Crew. |
| Discard-down | After a seat's Commit is accepted, choosing exactly the excess cards over its Hand size and Discarding them. |
| Exit mark | One of Condemned, Fleeting, Fade; a card holds at most one and a newer mark replaces the older. |
| Exit pass | The one pass at turn end in which exit marks resolve. |
| Cessation | The stated end of a status: "until end of turn" (the default), "permanently" (it is Memory), or a named end condition. |
| Move | A change of slot made by an effect; on a ring, so the leftmost slot is next to the rightmost for stepwise moves. |
| Placement | Putting a card into a slot (by Commit or by an effect); not a Move. |
| Ability | One effect of a card or Crew with one trigger moment. |
| Trigger | A moment (section 10) at which an ability may act; also the ability's pending instance in the queue. |
| Effect | What an ability does when it resolves. |
| Target | A card an effect acts on; Crew are never Targets. |
| Eligible | A Target that fits the text and may legally be acted on: not Anchored for a Move, swap or reorder, revealed where the text says so, and never a Crew. |
| Resolution | One trigger taken off the queue and carried out; it counts one against the Budget (trigger). |
| Uses | How often an ability may act: "unlimited" means every time its moment occurs; "once per Turn" or "once per Walk" caps it. |
| Retrigger | An extra resolution of the same ability immediately after each resolution it applies to, with choices made again. |
| Queue | The one first-in, first-out line of Batches per Walk; it drains fully before the pulse moves to its next stage. |
| Prompt | A pause for a choice by a seat, wherever the queue is draining; with no eligible target the effect fizzles, with one it is chosen automatically, except for optional counts and Crew (see Q9). |
| Fizzle | An effect that does nothing, with a stated reason ("no target", "exhausted"). |
| Strategy | One of Greed, Combo, Disruption, Graveyard, Control, Ramp, or evergreen; a tag on every card and Crew. |

## 8. Retired words

None of these appear in a rules sentence of the canon. The table below is the only place in
rules sentences they are used, to say what replaced them (spec R2, R38, R64).

| Retired word | Replaced by | Why |
|---|---|---|
| flat | Power | One name for the points a card adds when it Scores |
| destroy, destroyed | Condemn, Condemned | Condemn removes a card at turn end, so its current Score survives and the Walk's slots stay stable (Cards.md note) |
| destroyed pile | Pile | One public Pile per seat holds every card that leaves play |
| burn, burned, burn pile | Pile (nothing is burned) | Piles last the whole Match; there is no hand-cap burn |
| bonus (as a number) | Mult or Add; Bonus value for the number | "Bonus" now names the slot on the card, never the number inside it |
| return, returns | Fleeting | A card that goes to its Owner's hand at turn end holds Fleeting |
| running multiplier | Walking total and Bonus value | A seat's points are a walking total that each Score adds to and multiplies (spec C21) |

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

**How Silenced forms and splits (spec C5, R33, C22, C24).**

- Forms: if a card is both Muted and Squelched, it becomes Silenced and the two are replaced
  by the one status.
- Splits: when an effect removes Muted from a Silenced card, it becomes Squelched; when an
  effect removes Squelched from a Silenced card, it becomes Muted.
- Each half keeps its own end condition. When one half ends by its own cessation, the card
  is left with the other half; when both have ended, the card is clear.
- Silencing a card directly with an effect gives both halves with that effect's cessation.
- A "cannot be X" protection blocks only its half: Ward ("cannot be Muted") on a card that
  would be Silenced leaves it Squelched only. Stasis (a Squelch lasts until it leaves your
  row) protects the Squelch half the same way: that half lasts until Stasis leaves your row.

**Exit marks (spec R35).** A card holds at most one of Condemned, Fleeting, Fade. A newer
mark replaces an older one. At turn end the marks resolve in one pass, the first seat's
row first, then the second's, in slot order.

**Scope (spec R37).** Every board-scoped status ends when the card leaves its row or is
Un-revealed; a "permanent" status is Memory and survives both.

## 10. Trigger moments

Every ability has exactly one trigger moment (spec R50). There are ten.

| Moment | Fires when | Who it fires for |
|---|---|---|
| On reveal | The card flips face up in the Walk. | That card |
| On score | The card adds to the Score. | That card, and abilities that react to a Score |
| On commit | Its Controller's Commit is accepted, before that seat's discard-down. | Revealed row cards, and hand cards whose text says "while in your hand"; never cards committed face down this Turn |
| On start | Turn start, after the draws. | Revealed cards only |
| On discard | A card enters a Pile (see Discard, section 2). | Abilities that react to a Discard |
| On squelch | The card becomes Squelched alone (a Silenced card fires no triggers). | That card |
| On empty draw | A seat would draw from an empty Deck. Every On empty draw trigger fires, with no re-check that the Deck is still empty. | That seat's abilities and Crew, such as Void and the Pile-shuffling Crew |
| On moved | The card changes slot by a Move (not by Placement). | That card, and Crew that react to a Move |
| At turn end | Turn end has two points: before the exit pass, and after it. A text says which. | The ability's Controller's cards and Crew |
| Ongoing | Never fires; the engine reads it when the value is needed. | Everything it applies to |

**Notation: two kinds of bracket.**

- A watcher bracket names whose event the ability watches: "On reveal (another card of
  yours)" fires when another card of yours is revealed. Without a bracket, an ability
  watches the card itself.
- A zone bracket names where the card must be for the ability to act: "(while in your
  hand)" makes the ability active from the hand, and "Ongoing (while in your hand)" is
  read while the card is in a hand. Without a zone bracket, the card must be on a row.

Crew fire only after the effect that caused them has fully resolved, as a Batch of their own
(spec R51).

## Coverage check

All of spec R1's terms have an entry above: Match, Round, Turn, Walk, Commit, Score,
Condemn, Squelch, Mute, Silence, Fleeting, Fade, Discard, Pile, Deck, Anchored, Power, Cost,
Bonus, Mult, Add, Energy, Budget, Hand size, Owner, Controller, Reveal, Un-reveal, Memory,
Board change, Pulse, Batch, Budget (trigger), and the ten trigger moments. R2's six
retired words are in section 8, with "running multiplier" added by spec C21.
