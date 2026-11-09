---
type: reference
tags: [reference, rules-v2, rules]
status: built
related: ["[[specs/ruleset-v2/spec]]", "[[rules/rules-moc]]", "[[rules/glossary]]", "[[rules/resolution]]", "[[rules/crew-v2]]", "[[systems/game-loop]]", "[[systems/cards-crew-decks]]", "[[cards/Cards]]"]
created: 2026-11-06
updated: 2026-11-09
uid: effd8870-94a5-4b01-9b84-254a2da735eb
linear: https://linear.app/night-science-llc/issue/NSC-138/t02-rules-v2
supersedes:
---

# Rules v2

The rules in this note are built since DC-14 (rules version 7); the DC-13 and DC-14 rows of
[[planning/cycles]] record how and the readings made on the way. The game as built is
described in [[systems/game-loop]] and [[systems/cards-crew-decks]]; each section below
states the v2 rule, and the table at the end sets it beside the rules of version 6 ("today"
in that table means version 6). The requirements come
from [[specs/ruleset-v2/spec]] (cited inline as R-numbers) and the scratch sheet
[[cards/Cards]]. Every capitalised word is defined in [[rules/glossary]]. The order in which
triggers resolve belongs to [[rules/resolution]], and the ten Crew to [[rules/crew-v2]]; this
note does not repeat them.

## 1. Match, Round, Turn

**Match.** A Match is won by the first seat to four Round wins. A Round is seven Turns. A
tied Round awards no win. After Round 7 the seat with more Round wins takes the Match, and
Rounds continue as sudden death while the seats are level (R5). The third sudden-death Round
in a row to tie ends the Match in a Stalemate, so a Match is over after Round 10 at the latest:
the seat with the higher total of its Walk Scores over the Match wins, and equal totals draw
(cycle 14 C15). A Turn is one cycle of draw,
Commit, Walk and turn end; the Walk is the scoring pass and Score is its total (R4).

**Round end.** When a Round ends, every card on both rows goes to its Owner's Pile. Each
seat keeps its hand, its Deck and its Pile as they are (R6).

**Who commits first.** The seat that won the previous Turn commits first. On Turn 1 of a
Round, the seat that lost the previous Round commits first. After a tied Round there is no
loser, so the alternation of first committer simply continues from the last Turn of the
Round into Turn 1 of the next: the seat that did not commit first on that last Turn commits
first (C25). The first Turn of a Match is decided by a seeded coin flip. A tied Turn keeps
the order (R7).

**Turn phases, in order (R8).**

1. Turn start: each seat draws one card, then On start triggers fire.
2. First Commit, by the seat that commits first.
3. That seat's discard-down (section 3).
4. Second Commit.
5. That seat's discard-down.
6. The Walk.
7. Turn end.

**Turn end steps, in order (R9, C18).**

1. At turn end triggers that fire before the exit pass (Veil).
2. The exit pass: exit marks resolve (section 6, R35).
3. At turn end triggers that fire after the exit pass (Shade).
4. Statuses that end at turn end end.
5. Energy settles (section 2).
6. The Turn's winner is recorded.

## 2. Energy and Cost

- A seat's Budget on Turn N is N Energy: 1 on Turn 1, 7 on Turn 7. Unspent Energy is lost at
  turn end unless an ability says otherwise (R10).
- An ability that grants Energy ("+1 Energy this turn", or Engineer's +1 each Turn from Turn 3)
  adds it to that Turn's Budget on top of the N (R11).
- A card's Cost is the Energy paid to Commit it. Abilities may reduce a Cost, but never below
  0. A printed Cost above 7 is allowed only on a card whose text makes it reachable, such as
  a card that costs 7 on Turn 7 (R12).

## 3. Hand

- Each seat is dealt an opening hand of four cards once, at Match start (R13).
- The base Hand size is four. Ongoing abilities and Crew change it; the Quartermaster sets it
  to seven, and "your Hand size is +2" adds two (R14). Sets apply first (the highest set
  wins), then additions: Quartermaster's 7 with Pantry's +2 is 9.
- During a Turn a hand may hold more cards than its Hand size. A draw always succeeds unless
  the Deck is empty (R15).
- **Discard-down.** When a seat's Commit is accepted, if its hand holds more cards than its
  Hand size, that seat must choose exactly the excess from its hand. The chosen cards go to
  its Pile as Discards. This happens before the other seat commits or the Walk starts (R16).
- No other check of Hand size exists: not at turn end, not at Round start, not on a draw
  (R17).

## 4. Deck and Pile

- A Deck is exactly 40 cards, with at most four copies of any one card, drawn from the whole
  pool with no restriction by strategy (R18).
- Each Deck is shuffled once, at Match start. It is not refilled or reshuffled at Round
  start (R19).
- When a seat would draw from an empty Deck, it draws nothing and all of its On empty draw triggers
  fire, with no re-check that the Deck is still empty (the Pile-shuffling Crew, Void) (R20, C29).
- Each seat has one Pile, face up and public to both seats. It receives every card that
  leaves a hand or a row for any reason other than going to a hand (Fleeting), moving to a
  row or flipping face down (R21).
- A Discard is a card entering a Pile from a hand (a chosen discard or the discard-down) or
  from a row (a Condemned card leaving at turn end, a card cleared at Round end). On discard
  triggers fire for all of them (R22).
- Each Pile lasts the whole Match. No card leaves play except to a Pile (R23).
- When a card enters a Pile, its identity becomes known to both seats (R24).

## 5. Card anatomy, Bonus growth and Score maths

**Anatomy (R25).** Every card has a Cost, a Power (the points it adds when it Scores), at
most one printed Bonus, a strategy tag or "evergreen", and rules text. A card may have no
Bonus and no rules text. Abilities may grant a card further Bonuses.

**Bonus (R26, C20).** A Bonus is either a Mult or an Add.

- A Mult multiplies the card's Bonus value. It is printed ×1.25, ×1.5 or ×2.
- An Add adds to the card's Bonus value. It is printed +0.25, +0.5 or +1 (+1 only on
  expensive cards).
- A card carries its printed Bonus plus any granted ones (Void, Tallyman, Idler). When it
  Scores, all Adds apply, then all Mults.

**Growth (R27, C19).** An ability that grows a Bonus states how much: an Add gains +N, a Mult
gains +N or is multiplied by ×N. Growth applies as the base value, then the additive steps,
then the multiplicative steps, and the result is rounded to hundredths. Example: a printed
×1.5 Mult that gains +0.25 and is multiplied by ×1.2 once is (1.5 + 0.25) × 1.2 = ×2.10.

**Score maths (R28, C21; reading 9a, open to Ben's veto).** Each seat has a walking total that
starts at 0 each Walk. When a card Scores, for its Controller's seat:

1. The walking total gains the card's Power.
2. The card's Bonus value starts at 1, gains every Add, then is multiplied by every Mult.
3. The walking total is multiplied by the Bonus value. A card with no Bonus multiplies by 1.

The seat's Score for the Walk is its walking total after its last Scoring card, rounded to a
whole number once, at the end of the Walk (half rounds up). Nothing is rounded in between. A
negative Power subtracts before the multiply, so a Score may be negative. A Mult below 1
simply multiplies, and a negative walking total is multiplied like any other, so a Mult
above 1 makes a negative total more negative. The Bonus value is never below 0.

Order matters: Power added early is multiplied by every later Bonus, so a Bonus on the far
right of a row multiplies the whole walking total and is the strongest.

**Worked row.** One seat's row, left to right, walking total starting at 0:

| Slot | Card | Power | Bonus | Walking total after Power | Bonus value | Walking total after |
|---|---|---|---|---|---|---|
| 0 | A | 2 | Mult ×1.5 | 0 + 2 = 2 | 1 × 1.5 = 1.5 | 2 × 1.5 = 3 |
| 1 | B | 3 | Add +1 | 3 + 3 = 6 | 1 + 1 = 2 | 6 × 2 = 12 |
| 2 | C | 4 | none | 12 + 4 = 16 | 1 | 16 × 1 = 16 |

The seat's Score for the Walk is 16.

**Same cards, different order.** The same three cards as C, A, B:

| Slot | Card | Power | Bonus | Walking total after Power | Bonus value | Walking total after |
|---|---|---|---|---|---|---|
| 0 | C | 4 | none | 0 + 4 = 4 | 1 | 4 |
| 1 | A | 2 | Mult ×1.5 | 4 + 2 = 6 | 1.5 | 6 × 1.5 = 9 |
| 2 | B | 3 | Add +1 | 9 + 3 = 12 | 2 | 12 × 2 = 24 |

The Score is 24 from the same three cards. (B, A, C also gives 16, which is a coincidence of
these numbers: (3 × 2 + 2) × 1.5 + 4 = 16.)

**Memory and Board changes (R29).** A change to a card's stats is a Board change. It ends
when the card leaves its row or the Round ends. If the ability says "for the match" or
"permanently", the change is Memory and follows the card everywhere.

**Owner and Controller (R30).** The Owner is the seat whose Deck the card came from. The
Controller is the seat whose row it is on. Whenever a card leaves a row it does not Own, it
goes to its Owner's Pile or hand.

## 6. Statuses

There are exactly seven statuses: Muted, Squelched, Silenced, Condemned, Fleeting, Fade and
Anchored (R31). The glossary's status table is the one-line reference; the rules are these.

- **Muted.** The card's triggered abilities do not fire. It still Scores and its Ongoing
  abilities still apply. **Squelched.** The card does not Score and its Ongoing abilities
  stop. Its triggered abilities still fire (R32).
- **Silenced.** If a card is both Muted and Squelched, both are replaced by Silenced: no
  triggers, no Score, no Ongoing. When an effect removes Muted from a Silenced card, it
  becomes Squelched. When an effect removes Squelched from a Silenced card, it becomes Muted
  (R33). Each half keeps its own end condition; when one half ends the card is left with the
  other (C22). A "cannot be Muted" card (Ward) that would be Silenced is Squelched only, and
  Stasis protects the Squelch half of a Silence the same way (C24).
- **Cessation.** Every ability that gives a status states when it ends: "until end of turn"
  (the default), "permanently" (the status is Memory and follows the card), or a named end
  condition. A status with no stated cessation ends at turn end (R34).
- **Exit marks.** Condemned, Fleeting and Fade are exit marks. A card holds at most one, and
  a newer mark replaces an older one. At turn end the marks resolve in one pass, the row of
  the seat that committed first before the other row, each in slot order (R35):
  - Condemned: the card goes to its Owner's Pile as a Discard.
  - Fleeting: the card goes to its Owner's hand.
  - Fade: the card flips face down in place, keeping its Memory and losing its Board changes.
- **Anchored.** The card cannot be moved by any effect. A shift slides other cards past an
  Anchored card. A swap, reverse or reorder leaves Anchored cards in their slots and
  permutes the rest (R36).
- **Scope.** A status that is a Board change ends when the card leaves its row or is
  Un-revealed. A "permanently" status is Memory and survives both (R37).
- **No removal during the Turn.** No card or Crew removes a card from a row before turn end.
  Condemn is the only way a card leaves a row to a Pile, and it happens at turn end (R38).

A Condemned card still Scores this Walk, because it stays in its slot until turn end.

## 7. Movement

- A Move is a change of slot made by an effect. For stepwise moves the row is a ring: moving
  left from the leftmost slot lands on the rightmost, and the reverse. The Walk still reads
  the row left to right (R39).
- Committing a card into a slot is Placement, not a Move. It may change other cards' slot
  numbers without firing On moved or breaking an Anchored card (R40).
- The cursor rules of [[specs/cycle-5-walk-cursor/spec]] stay. A pulse belongs to its slot.
  A card moved ahead of the cursor is reached later this Walk. A card moved behind the cursor
  waits for the next Walk. A card landing on the pulsed slot Scores now (R41).

Example (row A B C, B Anchored): "your other cards each move one slot left" slides C past B
to slot 0 and wraps A to slot 2. B stays in slot 1 (R36, R39).

## 8. Hidden information

- A seat sees its own hand, both rows' revealed cards, face-down cards as slots only, the
  other seat's hand count and Deck count, both Piles in full, both seats' Crew, and the count
  and slots of a face-down Commit (R53).
- While a card is in a hand or face down, its effects, stats and Memory are private to its
  Owner. They become public when the card is revealed or enters a Pile (R54).
- A card in a hand that triggers ("while in your hand") is shown to both seats as it fires:
  the card and its ability become public knowledge, then it stays in the hand. The telegraph
  is deliberate and is part of the card's power budget (Ben, DC-13, cycle 9 spec C14).

## 9. Changed from today

| Topic | Today (rules version 6) | Rules v2 | Requirement |
|---|---|---|---|
| Energy | Budget is the turn number plus Energy a carry card saved; unspent Energy is lost unless a revealed carry card is on the row | Budget on Turn N is N plus granted Energy; unspent Energy is lost at turn end unless an ability says otherwise | R10, R11 |
| Cost | Effective cost can fall to 0 through Memory | Cost can fall to 0 through any ability; printed Costs above 7 only where the text makes them reachable | R12 |
| Hand | Dealt 3 each Round; at most 7; a card drawn at the cap is burned | Opening hand of 4 dealt once at Match start; base Hand size 4; a hand may exceed it during a Turn; one discard-down after the seat's own Commit | R13–R17 |
| Deck | 20 cards; refilled and reshuffled at Round start | 40 cards, at most four copies; shuffled once at Match start; never refilled | R18, R19 |
| Empty Deck | Not reached in a 20-card Round | Draw nothing and fire On empty draw; the tenth Crew shuffles the Pile in | R20 |
| Pile | A destroyed pile per seat, emptied into a burn pile at Round end; burn pile private | One Pile per seat, public, kept for the Match; rows clear into it at Round end; nothing is burned | R6, R21, R23, R24 |
| Discard | Discard from a hand only | A card entering a Pile from a hand or a row; On discard fires for all | R22 |
| Destroy | Marks a card in place; it leaves at turn end for the destroyed pile; random destroy exists | Retired: Condemn is the only removal, resolved at turn end with the Walk's slots stable | R35, R38 |
| Return | A return mark sends a card to its owner's hand, or burns it at the cap | Fleeting sends it to its Owner's hand, with no cap to burn at | R35 |
| Flip at turn end | Echo cards flip face down in place | Fade flips face down in place, keeping Memory | R35 |
| Statuses | None beyond the destroyed and return marks | Seven statuses: Muted, Squelched, Silenced, Condemned, Fleeting, Fade, Anchored, each with a cessation | R31–R34, R37 |
| Exit marks | Several marks may sit on a card | One mark per card; the newer replaces the older; one turn-end pass | R35 |
| Anchored | None | Immovable by any effect | R36 |
| Movement | Moves go to the far left or right, or shift by one; no ring | Stepwise moves wrap on a ring; Placement is not a Move | R39, R40 |
| Card stats | Flat, plus a ×-part and a +-part | Power, plus at most one printed Bonus (a Mult or an Add) and any granted ones, with defined growth | R25–R27 |
| Score maths | A running multiplier from ×1.00; each card's Bonus adjusts it, then the card adds floor(flat × multiplier). The same row of flat 2 with ×1.5, flat 3 with +1 and flat 4 with no bonus scores 20 | A walking total from 0: each Scoring card adds its Power, builds its Bonus value, and multiplies the total by it; the same row scores 16 (24 in the order C, A, B); rounded once at the end of the Walk | R28 |
| Turn end | Returns, clear destroyed, flips, Crew queue, energy | At turn end triggers before the exit pass, exit marks, At turn end triggers after it, statuses end, energy settles, winner recorded | R9 |
| Hidden information | Burn piles private; destroyed pile private if never revealed | Piles public; hand and face-down effects private to the Owner | R24, R53, R54 |

## 10. Trace table

| Requirement | Where it is stated |
|---|---|
| R5, R6, R7 | Section 1: Match, Round end, Who commits first |
| R8, R9 | Section 1: Turn phases, Turn end steps |
| R10, R11, R12 | Section 2 |
| R13–R17 | Section 3 |
| R18–R24 | Section 4 |
| R25–R30 | Section 5, with the worked row |
| R31–R38 | Section 6 |
| R39–R41 | Section 7 |
| R53, R54 | Section 8 |
| All of the above | Section 9, the changed-from-today table |
