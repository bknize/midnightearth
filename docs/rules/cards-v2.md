---
type: reference
tags: [reference, rules-v2, cards-v2]
status: seedling
related: ["[[specs/ruleset-v2/spec]]", "[[rules/rules-moc]]", "[[rules/glossary]]", "[[systems/cards-crew-decks]]", "[[cards/Cards]]", "[[rules/rules-v2]]", "[[rules/resolution]]", "[[rules/crew-v2]]"]
created: 2026-11-06
updated: 2026-11-06
uid: bb2db17d-f279-4b43-9970-86c6c690632c
linear: https://linear.app/night-science-llc/issue/NSC-141/t05-cards-v2
supersedes:
---

# Cards (ruleset v2)

This note is design for ruleset v2, not yet built. It lists the 90-card pool: ten cards for
each of six strategies and thirty evergreen cards. The cards that run today (rules version 6)
are described in [[systems/cards-crew-decks]]. The pool is seeded from the salvage table and
the card ideas in Ben's scratch sheet [[cards/Cards]], under R59 to R62 and R65 of
[[specs/ruleset-v2/spec]]. Every capitalised word is defined in [[rules/glossary]]; the
rules a card relies on are in [[rules/rules-v2]], the order things resolve in is
[[rules/resolution]] (cited below as Q1 to Q11 and D1 to D12), and the Crew each strategy
pairs with are in [[rules/crew-v2]]. All numbers are first-draft values, set by the guideline
in section 3 and tuned when the cards are played.

| Section | Cards | Cost curve |
|---|---|---|
| Greed | 10 | 1, 1, 2, 2, 3, 3, 4, 5, 6, 7 |
| Combo | 10 | 1, 2, 2, 3, 3, 3, 4, 5, 6, 7 |
| Disruption | 10 | 1, 2, 3, 3, 4, 4, 4, 4, 5, 6 |
| Graveyard | 10 | 2, 2, 3, 3, 3, 4, 4, 4, 5, 6 |
| Control | 10 | 2, 2, 3, 3, 3, 4, 4, 5, 6, 7 |
| Ramp | 10 | 1, 2, 2, 2, 3, 3, 4, 4, 5, 12 (7 on Turn 7) |
| Evergreen | 30 | 1 to 7, see section 2 |
| **Total** | **90** | |

## 1. Reading the tables

**Columns.** ID, Name, Tag (the card's strategy, or evergreen, R59), Cost, Power, Bonus (the
printed Mult or Add, or a dash), rules text, Source (a line of [[cards/Cards]], written L68,
or "new"), and Flags. Costs are 1 to 7; the one
named exception is Colossus at Cost 12 (R12). A dash in the Bonus column means no Bonus, which counts as a Bonus value of 1: the card does not change the walking total beyond its Power.
A card with no text is a plain body.

**Text style (binding).** The moment comes first, one sentence, glossary verbs. Every
status names its end: "until end of turn" is written out each time, "permanently" and "for
the match" mean Memory, and a Board change ends when the card leaves its row or the Round
ends (R29, R34). A bracket after a moment, such as "On reveal (another card of yours)", says
whose event the ability watches; without a bracket it watches the card itself.

**Verbs.** Every verb and notation below is defined in [[rules/glossary]]: choose, chosen
card, random, shuffle (into), create, copy, look at, shift, swap, reverse, reorder,
"cannot be X", "instead", you and your, opposing, leftmost and rightmost, Grant ("gets Power
+N", "gets Add +N", "gets Mult ×N"), Pass, and the two brackets (a watcher bracket such as
"On reveal (another card of yours)" and a zone bracket such as "(while in your hand)").
Bonuses on a card stack: all Adds apply, then all Mults (spec C20), and under the walking
total a Bonus on the far right of a row multiplies the most (C21).

**Flag codes.** Only R65 categories are flagged.

| Code | Meaning | Handled by |
|---|---|---|
| LOOP | The text can feed itself, within a Walk or across Turns | The Budget (trigger) of 50 per pulse (Q4); across Turns, a Cost or a Turn each time |
| RETRIG | The text adds extra resolutions of an ability | Q6 |
| TWICE | The text makes Scoring happen twice | Q7 |
| LEAK | The text shows a face-down or hidden card's identity to one seat | R54: private to the looking seat, nothing logged publicly |
| CTRL | The text changes a card's Controller | R30: the card goes to its Owner at turn end or Round end; Owner never changes |
| CREATE | The text makes cards that are in no Deck | Outside the 40-card Deck rules of R18; see the Dross rule below |

**Dross.** Created by Litter. Cost 1, Power 0, no Bonus, Ongoing (while in your hand): at the
end of the Walk, before rounding, your walking total is multiplied by ×0.75 for each Dross
in your hand. Ben's sketch (L25) was a ×.75 Bonus while in hand; under the walking total a
Mult on a card in hand has nothing to multiply, so the intent, a tax on the holder's Score,
is kept as a Walk-end multiply (flagged for Ben). Dross is a created card Owned by the seat
whose hand it was put in; when that seat Discards it, it goes to that seat's Pile as a
Discard (R22), and a Pile-shuffling Crew (Dredger) can shuffle it into that seat's Deck again.
Twin's copies are created the same way. Dross and copies are not part of the 90.

## 2. The cards

### 2.1 Greed

*Raw numbers early. Cheap, efficient bodies for the first Rounds, a few cards that pay a
Discard or a card for Power, and one finisher.*

**Plan (R62).** *Round 2:* the Greed seat leads on the board and on Round wins. Turns 1 to 3
are Pip, Ember, Flare and Skim, so by Turn 4 five or more cards have Scored and Tallyman's
fifth-Score Mult ×2 lands; a strong Power card ahead of the fifth slot is doubled too. It expects to hold at least two Round wins, because its late game
is thin. *Round 5:* the hand is nearly empty (Ember, Cinder and Jackpot all Discard), the row
is wide, and Banner makes plain bodies huge; it is cashing a lead into the fourth Round win
before a Ramp or Graveyard seat outgrows it. Gilt wants the far right of the row, where its
Mult ×1.5 multiplies everything scored before it. If the Match is level, Gilt and Jackpot
decide Turn 7. *Dry Deck (Rounds 6 and 7):* Courier drains the Deck faster, so the Greed
seat runs dry first, on purpose: with Void each empty draw becomes Power +10, Add +2 and
Mult ×1.5 on its next Scoring card. Without Void it is out of cards and relies on the cards
already on the row. *Crew:* Tallyman, Void; Engineer is the evergreen pick. Void's grant is strongest on the
last Scoring card of the row. *Beats* slow
Ramp and Combo in Rounds 1 and 2. *Loses to* Disruption (one Squelch or Mute on a spike
card) and Control (Cull and Fence punish a wide row).

| ID | Name | Tag | Cost | Power | Bonus | Text | Source | Flags |
|---|---|---|---|---|---|---|---|---|
| GR01 | Ember | Greed | 1 | 4 | — | On reveal: Discard a card from your hand. | L68 | Discard fires On discard (its own Batch after the effect, Q1). Empty hand: fizzles "no target" |
| GR02 | Pip | Greed | 1 | 3 | — | — | new | |
| GR03 | Flare | Greed | 2 | 5 | — | On reveal: Condemn this card. | new | Condemned, it still Scores this Walk (Q10) and leaves to the Pile at turn end (D10) |
| GR04 | Skim | Greed | 2 | 2 | Mult ×1.25 | — | new | |
| GR05 | Cinder | Greed | 3 | 7 | — | On reveal: Discard a card from your hand. | L71 | As Ember |
| GR06 | Courier | Greed | 3 | 3 | — | On score: draw a card. | L41 | Empty Deck: fires On empty draw (D8 drain) |
| GR07 | Banner | Greed | 4 | 3 | — | Ongoing: each of your cards that has no rules text has Power +4. | L52 | Read when the card Scores (Q5). The idea's "or squelched" half is dropped (see L52) |
| GR08 | Bounty | Greed | 5 | 7 | — | On score: your opponent draws a card. | new | The opponent's Deck can run dry sooner, which feeds their Dredger or Void |
| GR09 | Gilt | Greed | 6 | 4 | Mult ×1.5 | — | new | A late Mult multiplies the whole walking total, so Gilt wants the far right |
| GR10 | Jackpot | Greed | 7 | 10 | — | On reveal: Discard your hand. | new | Each Discard wakes On discard as its own Batch (Q1, D7) |

### 2.2 Combo

*Reveals and other triggers, set up cheaply and paid off late. Wants cards to reveal more
than once.*

**Plan (R62).** *Round 2:* the Combo seat is slightly behind on the board. Wick, Refrain,
Swell and Reprieve are low Power but they set the engine: Swell gives Fade so On reveal
cards fire again, and Shade un-reveals one more at turn end. It accepts one narrow Round
loss. *Round 5:* the payoffs are on the table. Encore doubles the On reveals, Reprise makes
every card Score twice, Finale scales with the number of reveals, and Reverb replays every
Turn at a lower Cost; the Mult cards and Finale belong on the right of the row. This is the Round the Combo seat takes by a wide margin. *Dry Deck
(Rounds 6 and 7):* Twin creates cards that are in no Deck, Wick and Reverb send themselves
back to hand with Fleeting, and Shade keeps re-revealing, so the seat still has plays when
the Deck is empty. *Crew:* Shade; Quartermaster (a larger hand holds the combo pieces) and
Engineer. *Beats* Control and Graveyard, which are slow to punish a quiet row. *Loses to*
Disruption (Mute stops triggers, Quorum mutes the row) and to early Greed.

| ID | Name | Tag | Cost | Power | Bonus | Text | Source | Flags |
|---|---|---|---|---|---|---|---|---|
| CB01 | Wick | Combo | 1 | 2 | — | On score: draw a card, then this card gets Power -1; then, if its Power is 0 or less, it gets Fleeting. | L61 | LOOP across Turns: Fleeting sends it to your hand at turn end (Q10, D10), its Board changes end, and it can be played again for Cost 1 |
| CB02 | Refrain | Combo | 2 | 1 | — | On reveal (another card of yours): this card gets Power +1 until it leaves your row. | L82 | A watcher; Encore doubles it (RETRIG, Q6) |
| CB03 | Swell | Combo | 2 | 2 | — | On reveal: another card of yours gets Fade. | new | Fade replaces an older exit mark, so it also saves a Condemned card (Q10) |
| CB04 | Reprieve | Combo | 3 | 3 | — | On reveal: choose a card on either row; it gets Fleeting. | L57 | On an opposing card it goes to its Owner's hand at turn end after it Scores this Walk; no Controller change |
| CB05 | Scrap | Combo | 3 | 2 | — | On reveal: Discard a card from your hand; this card gets Add +N until end of turn, where N is 0.25 for each point of that card's Cost, at most 1. | L45 | RETRIG target (scenario 4): under Encore each resolution asks again and reads N again (Q5, Q6, Q9). The 0.25 step and the cap of 1 are design additions (C21); the granted Add stacks with any printed Bonus (C20) |
| CB06 | Twin | Combo | 3 | 1 | — | On reveal: create a copy of this card in your hand. | L32 | LOOP across Turns and CREATE: each reveal makes one more copy; a copy has base values and no Memory. Hand growth is checked only by the discard-down (R16) |
| CB07 | Reprise | Combo | 4 | 3 | — | On commit: every card on both rows Scores twice this Turn. | L39 | TWICE (Q7); covers both rows. Fires only for a Reprise revealed on an earlier Turn (never the Turn it is committed) |
| CB08 | Encore | Combo | 5 | 4 | — | On reveal: until end of turn, each of your other On reveal abilities resolves twice. | L38 | RETRIG (Q6): one extra resolution after each, never itself, choices and amounts read again. Slot order matters: it only covers cards revealed after it |
| CB09 | Reverb | Combo | 6 | 5 | — | On reveal: this card gets Fleeting and costs 2 less for the match. | L85 | The Cost reduction is Memory and clamps at 0; each replay of the card is cheaper |
| CB10 | Finale | Combo | 7 | 4 | — | On reveal: this card gets Power +2 for each of your other cards revealed this Turn, until end of turn. | new | N is read when it resolves (Q5), so cards to its left count and cards to its right do not |

### 2.3 Disruption

*Stop the other seat's win condition with Squelch and Mute; a few cards pay for it with
slow, certain damage.*

**Plan (R62).** *Round 2:* Hush and Muzzle are cheap and answer the first big
card; the seat accepts a low Score and aims at the far right of the opposing row, where
Bonuses multiply the most. Muzzle and Eclipse choose by slot, so the seat is guessing against
face-down commits. *Round 5:*
Stasis makes every Squelch last, Hex and Jam keep Muting, Gag removes the one card the
opponent built a Round around, and Quorum cuts a wide row to two cards. *Dry Deck (Rounds 6
and 7):* Litter has filled the opponent's hand with Dross, so with an empty Deck they cannot
draw out of it, and Eclipse and Saboteur close the last Turns. *Crew:* none is tagged
Disruption in [[rules/crew-v2]] (a gap); the evergreen Engineer helps pay Eclipse, and
Salvager smooths the hand. *Beats* Combo (Mute stops triggers) and Greed (Squelch one spike).
*Loses to* Ramp and Control: Ramp grows beyond the reach of one Mute a Turn, and Control's
Shake and Tempest reorder the opposing row, which ruins a slot guess against face-down cards.

| ID | Name | Tag | Cost | Power | Bonus | Text | Source | Flags |
|---|---|---|---|---|---|---|---|---|
| DI01 | Hush | Disruption | 1 | 1 | — | On reveal: Mute an opposing card until end of turn. | new | |
| DI02 | Muzzle | Disruption | 2 | 2 | — | On reveal: Squelch an opposing card until end of turn. | new | |
| DI03 | Litter | Disruption | 3 | 2 | — | On reveal: create three Dross in your opponent's hand. | L25 | CREATE: Dross is defined in section 1. A card created is Owned by the seat it is put in |
| DI04 | Saboteur | Disruption | 4 | -3 | Mult ×0.75 | On reveal: move this card to the rightmost slot of your opponent's row. | L40 | CTRL: it is on the opposing row at the end of the Walk and goes to its Owner's Pile at Round end (R30, D12). Moved ahead of the cursor, it is reached later this Walk (R41) and Scores for the opposing seat, subtracting 3 from its walking total and then multiplying that total by ×0.75 (C21). Landing last, it takes about a quarter of the opponent's Walk Score; Ben chose ×0.75 at Cost 4 over ×0.5 (C27) |
| DI05 | Hex | Disruption | 3 | 3 | — | On reveal: choose a card on either row. On start: Mute the chosen card until end of turn. | L42 | The choice (the chosen card, glossary) is kept until Hex or the chosen card leaves its row or is Un-revealed. Prompt at reveal (Q9); the On start Mute fires each Turn Hex is revealed and not Muted |
| DI06 | Jam | Disruption | 4 | 3 | — | On score: Mute N random opposing cards until end of turn, where N is this card's Power. | L43 | N is read when it resolves (Q5); fewer cards than N, all of them |
| DI07 | Stasis | Disruption | 4 | 3 | — | Ongoing: each Squelch applied by your effects lasts until this card leaves your row instead of until end of turn. | L44 | Ends with Stasis; a Squelched card that leaves its row loses the Squelch anyway (R37). It protects the Squelch half of your Silences the same way (C24). If Stasis is itself Squelched, the Ongoing stops and new Squelches use the default end |
| DI08 | Gag | Disruption | 4 | 2 | — | On commit: Squelch an opposing card permanently, then Condemn this card. | L34 | The Squelch is Memory and follows the card into its Pile and any later Deck. Fires only for a Gag revealed on an earlier Turn, at step 5 (D3, Q9) |
| DI09 | Quorum | Disruption | 5 | 4 | — | On start: each seat chooses two of its revealed cards; every other revealed card on both rows is Muted until end of turn. | L56 | Prompts both seats at turn start (Q9, D2); a seat with two or fewer revealed cards is unaffected. It hits your own cards too |
| DI10 | Eclipse | Disruption | 6 | 5 | — | On reveal: Silence an opposing card until end of turn. | new | Silenced: no triggers, no Score, no Ongoing (R33). Against a card that cannot be Muted (Ward) it Squelches only (C24) |

### 2.4 Graveyard

*Condemnation and Discard, with tools to cushion the losses and bring cards back.*

**Plan (R62).** *Round 2:* Fuse, Tithe and Reliquary start the engine while the Piles are
small; Ember or Salvager feed Discards and Tithe turns each Condemned card into Energy.
The seat is not ahead on board, but it is stocking its Pile. *Round 5:* Boneyard counts
the Piles, Glutton and Immolator Condemn their own cards for Power and for random
opposing Condemns, Wraith keeps cards on the row, and Revive puts a body back. *Dry Deck
(Rounds 6 and 7):* this is the strategy's Round. Exhume and Reset refill the Deck, Dredger
shuffles the Pile in on an empty draw, and Veil turns Condemned cards back into hand. The
others are out of cards while it is full. *Crew:* Veil, Salvager, Dredger. *Beats* Control
and Ramp, which cannot keep up in the long game; Boneyard grows with every card either seat
loses. *Loses to* Greed (it falls behind early) and Disruption (Mute stops its triggers;
Wraith and Tithe are Ongoing and On discard, so Squelch and Mute each hit one half).

| ID | Name | Tag | Cost | Power | Bonus | Text | Source | Flags |
|---|---|---|---|---|---|---|---|---|
| GY01 | Fuse | Graveyard | 2 | 1 | — | On score (an opposing card): this card gets Power +1 until it leaves your row; then, if its Power is 5 or more, Condemn this card and one random opposing card. | L69, L70 | The two rows of the scratch sheet are the same card. The random Condemn is chosen with the seeded RNG (Q9) and resolves at turn end |
| GY02 | Tithe | Graveyard | 2 | 2 | — | On discard (a Condemned card of yours Discarded at turn end): you have +1 Energy next Turn for each such card, at most +3 per turn end. | L53 | Watches the exit pass (D10). A Round end clearing the row is not a Condemned Discard. On Turn 7 there is no next Turn in the Round, so the Energy is lost. The cap of 3 is a design addition |
| GY03 | Reliquary | Graveyard | 3 | 2 | Mult ×1.25 | On discard (a card of yours entering your Pile from your hand): this card's Mult is multiplied by ×1.2 for the match, at most once per Turn, to a maximum of ×2. | L48 | Memory. The once per Turn cap, "from your hand" and the maximum are design additions; the idea counted every Discard |
| GY04 | Boneyard | Graveyard | 3 | 2 | — | Ongoing: this card has Power +1 for each four cards in both Piles, rounded down. | L29 | Read at Score (Q5). The idea was one per card; divided by four to keep it below the Power guideline |
| GY05 | Wraith | Graveyard | 3 | 3 | — | Ongoing: your Condemned cards have Fade instead of Condemned when exit marks resolve. | L49 | An "instead" effect, read once at the start of the exit pass (resolution step 12), so a Condemned Wraith still applies to your other cards. Fade keeps Memory and loses Board changes (R35). Veil changes the card to Fleeting first and so wins |
| GY06 | Glutton | Graveyard | 4 | 2 | — | On reveal: Condemn one of your other cards; this card gets Power +N until it leaves your row, where N is that card's Power. | L72 | The Condemned card still Scores this Walk (Q10); Prompt with two or more choices (Q9) |
| GY07 | Revive | Graveyard | 4 | 3 | — | On reveal: choose a card in your Pile; put it face down on your row in the slot to the right of this card, then Condemn this card. | L58 | LOOP: a Revive revived by Revive chains one card per resolution, bounded by the Pile and by the Budget (Q4). Placement from a Pile is not a Move (R40); the card is ahead of the cursor, so it is reached this Walk (R41) |
| GY08 | Exhume | Graveyard | 4 | 4 | — | On reveal: choose up to two cards in either Pile; shuffle each into its Owner's Deck. | L55 | Piles are public (R21). Choosing the opposing Pile refills the opposing Deck. An optional count: it always Prompts, even with one eligible card, and may choose none (Q9) |
| GY09 | Immolator | Graveyard | 5 | 4 | — | On reveal: Condemn any number of your other cards, then Condemn that many random opposing cards. | L73 | An optional count: a multi-select Prompt even with one eligible card (Q9). Condemns are marks until turn end (Q10), so the Walk's slots do not change |
| GY10 | Reset | Graveyard | 6 | 5 | — | On reveal: shuffle both seats' Piles into their Decks, then Condemn this card. | L60 | Ends the dry Deck for both seats. Condemned, it reaches the Pile at turn end, after the shuffle, so it is not shuffled in this Turn |

### 2.5 Control

*Card movement and board manipulation: arrange your own row to feed your Mults and
pull the other one apart.*

**Plan (R62).** *Round 2:* Pin, Eddy and Shepherd set the row, aiming to hold a Mult in the
rightmost slot, where it multiplies the whole walking total (Herald). Control is thin on
Power and is content to lose or tie a Round while its engine takes shape. *Round 5:* Level,
Fence and Shake are in play. Reordering is where Control gains: Shepherd, Nudge and Shake
bring a Mult to the right of the row, Eddy grows as it is moved, and Tempest and Skip scramble
the opposing row so its Bonuses land early where they multiply little. Pin holds the slots
that must not move: a Mult in the rightmost slot, and Captain's Power +1 for the match
in the leftmost, which grows every Turn. *Dry Deck (Rounds 6 and 7):* Cull cuts a wide row to
five, Tempest breaks its order for the last Turn, and there are few new cards for the
opponent to find. *Crew:* none is tagged Control in [[rules/crew-v2]] (a gap); Captain (Ramp)
pairs with Pin, which holds the leftmost slot, and Engineer is the evergreen pick. *Beats*
Greed (Cull and Fence punish a wide row) and Combo (Tempest and Shake wreck reveal order).
*Loses to* Disruption (Hush, a Mute, stops Shake's On reveal) and Ramp (Power for the match
grows past what moving can answer).

| ID | Name | Tag | Cost | Power | Bonus | Text | Source | Flags |
|---|---|---|---|---|---|---|---|---|
| CT01 | Eddy | Control | 2 | 1 | Add +0.25 | On moved: this card's Add gets +0.25 until end of turn. | L74 | Wakes after the Move has finished (Q1). Under Shake it can be moved several times, and each Move counts once |
| CT02 | Pin | Control | 2 | 2 | — | On reveal: choose a card on either row; it gets Anchored until this card leaves its row. | new | The source of Anchored for decks that do not play Brace. An Anchored card keeps its slot through a shift, swap, reverse or reorder (R36) |
| CT03 | Shepherd | Control | 3 | 3 | — | On reveal: swap this card with another card on your row. | L76 | Both cards wake On moved as one Batch (Q1, Q3). Anchored cards are not eligible, and an Anchored Shepherd cannot swap: either fizzles "no target". Cursor rules decide who Scores now (R41) |
| CT04 | Skip | Control | 3 | 3 | — | On reveal: the next card to be revealed this Walk is moved to a different random slot of its row after its On reveal resolves and before it Scores. | L47 | Acts at the reveal-stage hook (resolution step 10): the Move happens after D7, its On moved Batch drains in D8. The pulse belongs to the slot, so the moved card does not Score there; a card landing in that slot Scores now (R41). Anchored cards do not move |
| CT05 | Fence | Control | 3 | 3 | — | Ongoing: when a card on either row would be moved left from the leftmost slot or right from the rightmost slot, Condemn it instead of moving it. | L26 | An "instead" effect: the Move does not happen, so no On moved fires. Anchored cards are never moved, so this does not apply to them. It overrides the ring (R39) |
| CT06 | Herald | Control | 4 | 3 | — | Ongoing: while this card is in the rightmost slot of your row, its Mult is ×1.5. | L77 | Read at Score (Q5). Priced as a Mult ×1.5 card in section 3. L77 had it in the leftmost slot, where a Mult multiplies only its own Power; the rightmost slot multiplies the whole walking total, and getting Herald there is Control's play (C21) |
| CT07 | Level | Control | 4 | 4 | — | Ongoing: each card's Power is the lowest Power among the revealed cards on its Controller's row, read before any Level applies. | L46 | Read at Score (Q5). A negative Power on a row (Saboteur) sets every card on it to that Power. It hits your own row too |
| CT08 | Shake | Control | 5 | 5 | — | On reveal: randomly reorder both rows; Anchored cards stay in their slots. | L31 | Every card moved wakes On moved as one large Batch, counted against the Budget (Q4). Face-down cards move by slot, identity unseen |
| CT09 | Tempest | Control | 6 | 5 | — | On reveal: reverse the order of the opposing row; Anchored cards stay in their slots. | L78 | As Shake, on one row |
| CT10 | Cull | Control | 7 | 7 | — | On reveal: each seat chooses five cards on its row; Condemn every card on both rows that was not chosen. | L33 | Prompts both seats (Q9); a seat with five or fewer cards is unaffected. Condemn is a mark until turn end (Q10) |

### 2.6 Ramp

*Persistent card improvements across the Match, so late Rounds belong to the seat that
invested.*

**Plan (R62).** *Round 2:* Whisper, Sapling and Rain grow their cards for the match, and
Dynamo and Tinker start a cheaper curve. The Ramp seat is behind on board and expects to lose
or tie. *Round 5:* the invested cards are big. Graft multiplies a Mult for the match (a Mult on the right of the row is worth most),
Layaway is cheap, Lantern gives a free first card, and Navigator and Captain add Power
each Walk. It takes two Rounds at least here. *Dry Deck (Rounds 6 and 7):* the Memory
sits on cards in the Pile; a Pile-shuffling Crew (Dredger) brings those cards back already
grown. Colossus costs 7 on Turn 7 and Scores 12. *Crew:* Navigator, Captain; Dredger
brings grown cards back from the Pile. *Beats* Disruption (it outgrows one Mute) and Graveyard.
*Loses to* Greed (it must survive the first two Rounds) and Control (Pin, Tempest and Level
undo the slot order its Mults need).

| ID | Name | Tag | Cost | Power | Bonus | Text | Source | Flags |
|---|---|---|---|---|---|---|---|---|
| RA01 | Whisper | Ramp | 1 | 1 | — | On reveal: this card gets Power +1 for the match. | L81 | Memory. Grows again with every reveal, so Fade and Shade replays count |
| RA02 | Sapling | Ramp | 2 | 1 | Mult ×1.25 | On score: this card's Mult gets +0.25 for the match, to a maximum of ×2. | L79 | Memory. Growth is additive here (R27). The maximum is a design addition (C21): a Mult multiplies the whole walking total |
| RA03 | Rain | Ramp | 2 | 1 | — | On reveal: each card in your hand gets Power +1 for the match. | L80 | Memory on cards in hand; it follows each card to the Pile and back |
| RA04 | Dynamo | Ramp | 2 | 2 | — | On start: you have +1 Energy this Turn. | L36 | Added to the Budget on top of the Turn number (R11). Fires only for a revealed card |
| RA05 | Tinker | Ramp | 3 | 3 | — | On reveal: the card to the right of this card costs 1 less for the match. | L83 | Memory. Clamps at 0 (R12) |
| RA06 | Idler | Ramp | 3 | 2 | — | On commit: if you Pass this Turn, this card gets Power +2 and Add +0.5 until end of turn. | L37 | A Pass is a Commit of zero cards, still an accepted Commit. The granted Add stacks with any printed Bonus (C20). Fires only for a revealed Idler (step 5, D3) |
| RA07 | Lantern | Ramp | 4 | 4 | — | On reveal: the first card you commit next Turn costs 0, until you commit a card or next Turn ends. | L84 | If nothing is committed next Turn the effect ends at the next turn end |
| RA08 | Graft | Ramp | 4 | 3 | — | On score: the card to the right of this card has its Mult multiplied by ×1.2 permanently, to a maximum of ×2.5. | L28 | Memory, growth ×1.2 (R27). Fizzles "no target" if that card has no Mult. The maximum is a design addition (C21) |
| RA09 | Layaway | Ramp | 5 | 6 | — | On commit (while in your hand): this card costs 1 less for the match. | L54 | Fires from the hand (R50). Clamps at 0 |
| RA10 | Colossus | Ramp | 12 | 12 | — | Ongoing (while in your hand): on Turn 7 this card's Cost is 7. | L30 | The one named Cost exception (R12). Other Cost changes apply after |

### 2.7 Evergreen

*Thirty broadly useful cards, mostly simple. Every deck can play them. They carry no
strategy tag and no plan; they fill the gaps of every curve.*

| ID | Name | Tag | Cost | Power | Bonus | Text | Source | Flags |
|---|---|---|---|---|---|---|---|---|
| EV01 | Mote | evergreen | 1 | 2 | — | — | new | |
| EV02 | Wisp | evergreen | 1 | 1 | Mult ×1.25 | — | new | |
| EV03 | Tuft | evergreen | 1 | 1 | — | On score: this card gets Power +1 until it leaves your row. | new | |
| EV04 | Pebble | evergreen | 2 | 3 | — | — | new | |
| EV05 | Scout | evergreen | 2 | 2 | — | On reveal: draw a card. | new | |
| EV06 | Delve | evergreen | 2 | 2 | — | On reveal: look at the top three cards of your Deck, draw one of them and shuffle the other two into your Deck. | L27 | LEAK (private): only you see the three cards (R54) |
| EV07 | Lookout | evergreen | 2 | 2 | — | On reveal: look at one face-down card on the opposing row. | new | LEAK by design: its identity is shown to you only, until it is revealed |
| EV08 | Scapegoat | evergreen | 2 | 3 | — | On squelch: end this card's Squelch and Condemn this card. | L50 | The idea says "instead"; this reading uses the On squelch moment, so there is a short Squelched window (Q2). A Silenced card fires no triggers |
| EV09 | Ward | evergreen | 2 | 2 | — | On score: your cards cannot be Muted until end of turn. | L51 | Does not end a Mute already in place. Against a Silence it blocks the Mute half, so the card ends up Squelched only (C24) |
| EV10 | Mirror | evergreen | 2 | 0 | — | On reveal: choose a revealed opposing card; this card copies its current Power and Bonus until end of turn. | L75 | Reads the stats when it resolves (Q5); a face-down card is not eligible |
| EV11 | Nudge | evergreen | 2 | 3 | — | On reveal: move this card one slot to the right. | new | The ring wraps from the rightmost slot to the leftmost (R39) |
| EV12 | Cobble | evergreen | 3 | 4 | — | — | new | |
| EV13 | Lyre | evergreen | 3 | 2 | Mult ×1.5 | — | new | |
| EV14 | Pantry | evergreen | 3 | 2 | — | Ongoing: your Hand size is +2. | L35 | Stacks with copies and with Quartermaster; checked only at a Commit (R16, R17) |
| EV15 | Brace | evergreen | 3 | 4 | — | Ongoing: this card is Anchored. | new | If Brace is Squelched the Ongoing stops and it can be moved |
| EV16 | Loom | evergreen | 3 | 3 | — | On reveal: the card to the right of this card gets Power +2 until end of turn. | new | |
| EV17 | Hearth | evergreen | 4 | 5 | — | — | new | |
| EV18 | Rook | evergreen | 4 | 4 | Add +0.25 | — | new | |
| EV19 | Bolster | evergreen | 4 | 4 | — | On reveal: each of your other revealed cards gets Power +1 until end of turn. | new | |
| EV20 | Bastion | evergreen | 4 | 4 | — | Ongoing: this card cannot be Condemned. | new | If Bastion is Squelched the Ongoing stops |
| EV21 | Granite | evergreen | 5 | 6 | — | — | new | |
| EV22 | Crest | evergreen | 5 | 4 | Mult ×1.5 | — | new | |
| EV23 | Torch | evergreen | 5 | 4 | Add +0.5 | — | new | |
| EV24 | Basalt | evergreen | 6 | 7 | — | — | new | |
| EV25 | Kiln | evergreen | 6 | 6 | Mult ×1.25 | — | new | |
| EV26 | Orrery | evergreen | 6 | 3 | Mult ×2 | — | new | |
| EV27 | Vault | evergreen | 6 | 5 | Add +0.5 | — | new | |
| EV28 | Obsidian | evergreen | 7 | 9 | — | — | new | |
| EV29 | Monolith | evergreen | 7 | 6 | Mult ×1.5 | — | new | |
| EV30 | Zenith | evergreen | 7 | 4 | Add +1 | — | new | |

## 3. Power guideline and exceptions (R61)

**The guideline.** Power runs from Cost to Cost + 2 with no drawback, and up to Cost + 4
with a drawback. A drawback is text that costs its Owner a card, a Discard or Power on its
own row, or hurts both rows (Ember, Flare, Cinder, Bounty, Jackpot, Fuse, Glutton, Revive,
Immolator, Gag, Reset, Level, Quorum, Cull and Wick's decay).

**Reading of R61 for cards with a Bonus (re-tuned for the walking total, C21).** A Bonus is
paid for in Power, by sliding the whole band down. A Bonus multiplies everything scored
before the card, so it is worth most on the right of a row; the cuts below price a Bonus at
about its value in the middle of a row.

| Printed Bonus | Band slides down by |
|---|---|
| Mult ×1.25 | 2 |
| Mult ×1.5 | 3 |
| Mult ×2 | 4 |
| Add +0.25 | 1 |
| Add +0.5 | 2 |
| Add +1 (Cost 6 or 7 only) | 4 |

So Gilt (Cost 6, Mult ×1.5) is in band at Power 3 to 5, and Zenith (Cost 7, Add +1) at Power
3 to 5. Add +0.75 and other odd steps are not printed. This is my reading of R61 and is open
to Ben's veto; without it every Bonus card is an exception.

**Exceptions.** Every card outside its band, and why. All are below the band except
Colossus (Cost) and Saboteur (negative by design); no card is above its band. Most are
payoff cards whose text is meant to supply the missing points.

| Card | Cost / Power | Band | Reason |
|---|---|---|---|
| Colossus | 12 / 12 | Cost 1 to 7 | The named Cost exception (R12): Cost 7 on Turn 7 |
| Saboteur | 4 / -3 | 4 to 6 | Negative by design; it subtracts from the opposing walking total, and its ×0.75 shrinks that total (C27) |
| Banner | 4 / 3 | 4 to 6 | Payoff: +4 Power on each of your cards with no rules text |
| Refrain | 2 / 1 | 2 to 4 | Seed: grows by 1 for each other reveal |
| Scrap | 3 / 2 | 3 to 7 | Payoff: Add up to +1 from the Discard |
| Twin | 3 / 1 | 3 to 5 | Engine: makes a copy each reveal |
| Reprise | 4 / 3 | 4 to 6 | Payoff: every card Scores twice, so each Bonus applies twice on both rows |
| Encore | 5 / 4 | 5 to 7 | Payoff: doubles every other On reveal |
| Reverb | 6 / 5 | 6 to 8 | Replayable: Fleeting and cheaper each time |
| Finale | 7 / 4 | 7 to 9 | Payoff: +2 for each other reveal, about 12 at six cards |
| Litter | 3 / 2 | 3 to 5 | Three Dross for the opponent's hand |
| Jam | 4 / 3 | 4 to 6 | Payoff: Mutes N cards where N is its Power |
| Stasis | 4 / 3 | 4 to 6 | Payoff: makes every Squelch last |
| Gag | 4 / 2 | 4 to 8 | Payoff: a permanent Squelch, one use |
| Quorum | 5 / 4 | 5 to 9 | Payoff: cuts a row to two cards |
| Eclipse | 6 / 5 | 6 to 8 | Payoff: Silence |
| Fuse | 2 / 1 | 2 to 6 | Seed: grows by 1 per opposing Score, then Condemns two |
| Boneyard | 3 / 2 | 3 to 5 | Scales with both Piles, about +4 to +8 by Round 5 |
| Glutton | 4 / 2 | 4 to 8 | Payoff: gains the Power of a Condemned card, which also still Scores |
| Revive | 4 / 3 | 4 to 8 | Payoff: puts a card back on the row |
| Immolator | 5 / 4 | 5 to 9 | Payoff: mass Condemn |
| Reset | 6 / 5 | 6 to 10 | Payoff: refills both Decks |
| Tempest | 6 / 5 | 6 to 8 | Payoff: reverses a row |
| Rain | 2 / 1 | 2 to 4 | Seed: Power +1 for the match to the whole hand |
| Idler | 3 / 2 | 3 to 5 | Payoff: Power +2 and Add +0.5 on a Pass |
| Graft | 4 / 3 | 4 to 6 | Payoff: grows the next card's Mult for the match, to ×2.5 |
| Mirror | 2 / 0 | 2 to 4 | Copies another card's Power and Bonus |
| Pantry | 3 / 2 | 3 to 5 | Payoff: Hand size +2 |

## 4. Synergies and counterplay

How the strategies meet each other, as a check against the plans above.

| Strategy | Crew | Wants from the pool | Weak to |
|---|---|---|---|
| Greed | Tallyman, Void | Five or more cheap Scoring cards by Turn 4; Banner with plain bodies | Disruption, Control |
| Combo | Shade | Fade and Fleeting givers (Swell, Reprieve), then the doublers (Encore, Reprise) | Disruption |
| Disruption | none (gap) | Squelch and Mute the turn before the opponent's payoff | Ramp, Control |
| Graveyard | Veil, Salvager, Dredger | Discards and Condemns early, recursion late | Greed, Disruption |
| Control | none (gap) | Anchored (Pin, Brace) holding a Mult in the rightmost slot (Herald), reorder (Shepherd, Nudge, Tempest, Shake) | Disruption, Ramp |
| Ramp | Navigator, Captain | Memory growth on cheap cards, Colossus on Turn 7 | Greed |

Cross-checks: Dross (Litter) is counterplay to Dredger, since Dross is shuffled into the
Deck by a Pile-shuffling Crew; Wraith and Veil compete for the same Condemned card (Veil
wins); Fence and Pin do not conflict, because an Anchored card is never moved; Level
punishes Saboteur's negative Power, which sets the whole row it lands on to -3.

## 5. Flagged cards (R65)

| Card | Category | How the chart handles it |
|---|---|---|
| Wick | LOOP across Turns | Fleeting at turn end (Q10, D10); each replay costs a Commit |
| Twin | LOOP across Turns, CREATE | One copy per reveal; the copy is a new card, so no queue loop (Q1) |
| Revive | LOOP | One card per resolution, bounded by the Pile and by the Budget of 50 (Q4) |
| Encore | RETRIG | One extra resolution each, never itself, choices again (Q6) |
| Scrap | RETRIG target | Each resolution asks a Prompt and reads N again (Q5, Q6, Q9); the scenario 4 trace |
| Refrain | RETRIG target | A watcher is an On reveal ability and Encore doubles it (Q6) |
| Reprise | TWICE | Every score stage runs twice (Q7); both rows |
| Saboteur | CTRL | The card is on the opposing row; Owner never changes; Round end Discards it to its Owner (R30, D12) |
| Delve | LEAK (private) | Own Deck only, nothing public (R54) |
| Lookout | LEAK by design | Identity shown to the looking seat only (R54) |
| Litter | CREATE | Dross is Owned by the receiving seat; see section 1 |

## 6. Counts

- Greed 10, Combo 10, Disruption 10, Graveyard 10, Control 10, Ramp 10 (60 tagged).
- Evergreen 30. Total 90.
- Costs 1 to 7, except Colossus at 12.
- Source: 17 cards come from the salvage table, 36 from the card ideas, 37 are new.

## 7. Disposition of the scratch sheet (R60)

Every row of the salvage table and every card idea in [[cards/Cards]], in sheet order. "Used
as" names the card and its ID; "merged into" means the text lives in another card; "dropped"
says why. The old words appear in this table only, quoted from the sheet.

### 7.1 Salvage table

| Line | Sheet row | Disposition | Note |
|---|---|---|---|
| L68 | Ember 1 / 4, on reveal discard a card from your hand | Used as Ember (GR01) | Kept as printed |
| L69 | Fuse 2 / 1, each enemy score +1 flat, at 5 flat destroys itself and a random enemy card | Used as Fuse (GY01) | "destroys" becomes Condemn; "flat" becomes Power; the Condemn is at turn end |
| L70 | Fuse (second row) | Merged into Fuse (GY01) | A duplicate row: four copies are allowed in a Deck |
| L71 | Cinder 3 / 7, on reveal discard a card from your hand | Used as Cinder (GR05) | Kept as printed |
| L72 | Glutton 4 / 2, destroy another card of yours and gain its flat | Used as Glutton (GY06) | Condemn, and the Condemned card still Scores, so the gain is on top |
| L73 | Immolator 5 / 4, destroy any number of your cards, then as many random enemy cards | Used as Immolator (GY09) | Condemn; "other" cards, so it does not Condemn itself |
| L74 | Eddy 2 / 1, when moved +2 to its +bonus until the walk ends | Used as Eddy (CT01) | Given Add +0.25 so there is an Add to grow, by +0.25 (C19, C21); ends at turn end |
| L75 | Mirror 2 / 0, copy an enemy card's current flat and bonus | Used as Mirror (EV10) | Evergreen: a general answer, revealed cards only |
| L76 | Shepherd 3 / 3, swap places with another card on your row | Used as Shepherd (CT03) | Kept as printed |
| L77 | Herald 4 / 3, ×1.5 while on the far left of your row | Used as Herald (CT06) | Moved to the rightmost slot, where a Mult multiplies the whole walking total (C21) |
| L78 | Tempest 6 / 5, reverse the order of the enemy row | Used as Tempest (CT09) | Anchored cards stay in place (R36) |
| L79 | Sapling 2 / 1, each score ×+0.25 for the match | Used as Sapling (RA02) | Given Mult ×1.25 so there is a Mult to grow |
| L80 | Rain 2 / 1, each card in your hand +1 flat for the match | Used as Rain (RA03) | Kept as printed with Power |
| L81 | Whisper 1 / 1, +1 flat for the match | Used as Whisper (RA01) | Kept as printed with Power |
| L82 | Refrain 2 / 1, each time another of your cards reveals +1 flat this round | Used as Refrain (CB02) | "This round" is "until it leaves your row" and the Round end clears the row anyway |
| L83 | Tinker 3 / 3, the card to its right costs 1 less for the match | Used as Tinker (RA05) | Kept as printed |
| L84 | Lantern 4 / 4, your first card next turn is free | Used as Lantern (RA07) | Given an end condition |
| L85 | Reverb 6 / 5, it costs 2 less for the match | Used as Reverb (CB09) | Paired with Fleeting so the lower Cost matters |
| L86 | Empty last row of the table | Dropped | Nothing to carry over |

### 7.2 Card ideas

| Line | Idea | Disposition | Note |
|---|---|---|---|
| L25 | On reveal: add three cards to your opponent's hand (Cost 1, Power 0, Bonus ×.75 while in hand) | Used as Litter (DI03) | The ×0.75 is Dross's Ongoing, applied to the holder's walking total at Walk end (section 1) |
| L26 | Leftmost moved left / rightmost moved right: Condemn it | Used as Fence (CT05) | Ongoing; the Condemn replaces the wrap |
| L27 | Look at the top 3, draw one, shuffle the other two | Used as Delve (EV06) | Evergreen |
| L28 | On score: permanently increase the card to the right's mult by 1.2 | Used as Graft (RA08) | ×1.2 growth (R27) |
| L29 | Ongoing: +1 Power for each card in all discard piles | Used as Boneyard (GY04) | Divided by four to stay under the guideline |
| L30 | Ongoing: costs 7 on turn 7 (Power 12, Cost 12) | Used as Colossus (RA10) | The named Cost exception |
| L31 | On reveal: randomly reorder both boards | Used as Shake (CT08) | Anchored cards stay |
| L32 | On reveal: create a copy of this card in your hand | Used as Twin (CB06) | Flagged LOOP, CREATE |
| L33 | On reveal: each player chooses 5 cards in play and condemns the rest | Used as Cull (CT10) | Cost 7 |
| L34 | On commit: select one card on the board and squelch it permanently | Used as Gag (DI08) | Opposing card only; Condemns itself after one use |
| L35 | Ongoing: your hand size is +2 | Used as Pantry (EV14) | Evergreen |
| L36 | On start: +1 energy this turn | Used as Dynamo (RA04) | Revealed cards only (R50) |
| L37 | On commit: if you committed no cards this turn, +2 power +2 mult | Used as Idler (RA06) | "+2 mult" is a granted Add, re-tuned to +0.5 (C21) |
| L38 | On reveal: trigger your other on-reveals twice this turn | Used as Encore (CB08) | Flagged RETRIG |
| L39 | On commit: each card scores twice this turn | Used as Reprise (CB07) | Flagged TWICE |
| L40 | On reveal: moves to your enemy's board (Cost 3, Power -3, Mult 1.2) | Used as Saboteur (DI04) | Cost 4, Mult ×0.75 on the opposing row (C27); flagged CTRL |
| L41 | On score: draw a card | Used as Courier (GR06) | |
| L42 | On reveal: select a card + On start: mute the selected card | Used as Hex (DI05) | Mute until end of turn each Turn |
| L43 | On score: mute N random enemy cards, N is this card's Power | Used as Jam (DI06) | |
| L44 | Ongoing: squelches no longer end at the end of the turn | Used as Stasis (DI07) | Only the Squelches your own effects apply, until Stasis leaves your row |
| L45 | On reveal: discard a card in hand, +N mult, N the discarded card's Cost | Used as Scrap (CB05) | "+N mult" is a granted Add of 0.25 per point of Cost, at most +1 (C21) |
| L46 | Ongoing: each card's Power equals the lowest on that player's field | Used as Level (CT07) | |
| L47 | On reveal: the next un-revealed card moves to a random location after revealing, before scoring | Used as Skip (CT04) | |
| L48 | On discard: match-long x1.25 each time a user discards | Used as Reliquary (GY03) | Printed Mult ×1.25, growth by the ×1.2 step of R27, capped at ×2; own hand Discards, once per Turn |
| L49 | Ongoing: condemned cards un-reveal instead of going to the pile | Used as Wraith (GY05) | Fade |
| L50 | On squelch: condemn it instead | Used as Scapegoat (EV08) | "Instead" becomes "end the Squelch and Condemn" |
| L51 | On score: your cards cannot be muted this turn | Used as Ward (EV09) | |
| L52 | Ongoing: cards without abilities or squelched get +4 Power | Used as Banner (GR07), the squelched half dropped | A Squelched card does not Score, so Power on it is worthless |
| L53 | Ongoing: whenever a condemned card is sent to the pile, +1 energy next turn | Used as Tithe (GY02) | Capped at +3 |
| L54 | On commit: this card gets -1 Cost each time you commit while in your hand | Used as Layaway (RA09) | |
| L55 | On reveal: put N cards from your or opponent's pile back into the deck | Used as Exhume (GY08) | N is 2 |
| L56 | On start: each player chooses 2 cards and the rest are muted | Used as Quorum (DI09) | |
| L57 | On reveal: target card gets Fleeting | Used as Reprieve (CB04) | |
| L58 | On reveal: put a card you own from the pile onto the field and condemn this one | Used as Revive (GY07) | Flagged LOOP |
| L59 | On reveal: put your entire deck into the pile | Dropped | Every later draw becomes an empty draw, which only Void and Dredger answer; there is no glossary rule for a Deck-to-Pile move (not a Discard); with Dredger it is undone at the next draw. Revisit when Void and Dredger have been played |
| L60 | On reveal: shuffle both players' piles into their decks, then condemn this one | Used as Reset (GY10) | |
| L61 | On score: draw a card, -1 Power; at 0 Power it gets Fleeting | Used as Wick (CB01) | Flagged LOOP across Turns |
| L62 | Empty bullet | Dropped | Nothing to carry over |

## 8. Gaps found, now closed

The first draft of this note listed seven gaps in the glossary. The T07 review fixes closed
them; each now lives in [[rules/glossary]].

- **Watcher moments.** The watcher bracket and the zone bracket are defined in glossary
  section 10.
- **Created cards.** Owner of a created card is the seat it is created for (glossary, create
  and Owner).
- **Cards leaving a Pile.** Defined as "Leaving a Pile" (glossary section 2).
- **Ongoing in hand.** The zone bracket "(while in your hand)" covers Dross and Layaway.
- **Look at.** Defined in glossary section 6.
- **Replacement.** "Instead" effects are defined in glossary section 6 (Wraith, Fence).
- **Row size.** A row has no size cap (glossary, Row).
