---
type: reference
tags: [reference, rules-v2, crew-v2]
status: seedling
related: ["[[specs/ruleset-v2/spec]]", "[[rules/rules-moc]]", "[[rules/glossary]]", "[[systems/cards-crew-decks]]", "[[cards/Cards]]"]
created: 2026-11-06
updated: 2026-11-06
uid: 26ab55eb-ddf5-41d2-8013-ecc04ea1a9ea
linear: https://linear.app/night-science-llc/issue/NSC-140/t04-crew-v2
supersedes:
---

# Crew (ruleset v2)

This note is design for ruleset v2, not yet built. It lists the ten Crew. The eight Crew
that run today (rules version 6) are described in [[systems/cards-crew-decks]]; the nine
Crew Ben sketched for v2 are in the "Crew" section of [[cards/Cards]], and this note adds a
tenth. The requirements are R55 to R58 of [[specs/ruleset-v2/spec]]. Every word below is
defined in [[rules/glossary]]; the rules a Crew relies on (Hand size, Budget, the Pile, the
exit marks) are in [[rules/rules-v2]], and the order Crew fire in is in
[[rules/resolution]].

## What a Crew is

A Crew is a non-card: it has no Cost, Power or Bonus of its own. It is never on a row, never a
target, and is never Condemned, moved or copied (R51). A Crew fires only after the effect
that caused it has fully resolved, as a Batch of its own, and among Crew in one Batch the
order is slot order (R45). A Crew prompt is optional and may be skipped (R52); a skipped
prompt spends nothing.

Where a Crew gives a seat's card a change, the change has an end condition stated in the
table, as the glossary requires of every status-granting ability (R34). A change that says
"for the match" is Memory.

## The ten Crew

Tags are evergreen or one of Greed, Combo, Disruption, Graveyard, Control, Ramp (R57).
"Uses" says how often the Crew may fire; "unlimited" means every time its moment occurs.

| Crew | Tag | Moment | Text | End condition | Uses and scope | Prompts |
|---|---|---|---|---|---|---|
| Tallyman | Greed | On score | After four of your cards have Scored in a Walk, your next Scoring card gets Add +5. | The +5 Add ends when that card has Scored; the count of four starts again at the next Walk, and a count left over at the end of a Walk is lost. | Unlimited; counts your cards only; the count is kept per Walk. | No |
| Shade | Combo | At turn end, after exit marks resolve | Choose one of up to three randomly selected revealed cards of yours and Un-reveal it. | The Un-reveal is immediate; the card keeps its Memory and loses its Board changes. | Unlimited; once per Turn; your row only. | Yes, optional |
| Veil | Graveyard | At turn end, before exit marks resolve | Choose one Condemned card of yours; it gets Fleeting instead of Condemned. | Fleeting resolves in the same turn end pass, sending the card to its Owner's hand. | Unlimited; once per Turn; your row only. | Yes, optional |
| Navigator | Ramp | On score | The second of your cards to Score in a Walk gets Power +2 permanently, after it has Scored. | Permanent: the +2 is Memory and follows the card everywhere. | Unlimited; once per Walk; your cards only. | No |
| Void | Greed | On empty draw | You draw nothing, and your next Scoring card gets Power +10, Add +2 and Mult ×1.5. | Ends when that card has Scored, or at turn end if none of your cards Scored. | Unlimited; once per empty draw; your Deck only. | No |
| Engineer | evergreen | Ongoing | From Turn 3 of each Round, your Budget is +1 Energy. | Ongoing: it applies for as long as the Crew is in play. | Unlimited; your Budget only. | No |
| Quartermaster | evergreen | Ongoing | Your Hand size is 7. | Ongoing: it applies for as long as the Crew is in play. | Unlimited; your Hand size only. | No |
| Salvager | Graveyard | On commit | You may Discard a card from your hand, then draw a card. | None needed: no status is granted. | Unlimited; once per Commit of yours. | Yes, optional |
| Captain | Ramp | On score | When the card in the leftmost slot of your row Scores, it gets Power +1 for the match, after it has Scored. | Permanent: the +1 is Memory and follows the card everywhere. | Unlimited; leftmost slot of your row, read when it Scores. | No |
| Dredger (working name) | Graveyard | On empty draw | Before you would draw from an empty Deck, shuffle your Pile into your Deck, then draw. | None needed: no status is granted. | Unlimited; your Deck and Pile only. | No |

No Crew is tagged Disruption or Control; those two strategies take Crew chosen from the
evergreen pair and from the others (see the sharing rule below). A later Crew may fill the
gap.

## Three Crew per deck, and sharing

Each deck lists exactly three Crew, chosen in the deck list (R58). Sharing is allowed: the
same Crew may appear in more than one deck, and both seats of a Match may bring the same
Crew. A deck lists three different Crew (my reading of "three Crew"; see the notes below).
Crew are not drawn, not part of the 40-card Deck and do not count against its limit of four
copies per card (R18).

## The play each Crew enables

**Tallyman (Greed).** Early Score leads come from many cheap cards Scoring in a row. After
four of your cards have Scored, the fifth is boosted by Add +5, so a Walk with five or more
Scoring cards has a spike where the fifth card is big. It rewards a wide row and punishes
losing cards to Squelch or Condemn before they Score, since a card that does not Score does
not count.

**Shade (Combo).** The Walk reveals a card once, but Shade lets a card reveal again on a
later Turn: at turn end it Un-reveals one of your revealed cards, so its On reveal fires
again next Turn. It keeps the card's Memory, so a card grown "for the match" returns bigger.
The randomness (three offered, you pick one) means you plan around having several good
On reveal cards on the row.

**Veil (Graveyard).** A Condemned card normally goes to the Pile at turn end. Veil takes one
of them and swaps its exit mark for Fleeting, so it goes to your hand instead. In a Graveyard
deck that Condemns its own cards for Power, this turns a one-shot body into a reusable one,
at the cost of a Commit to play it again.

**Navigator (Ramp).** The second of your cards to Score each Walk grows by Power +2 for the
match. Over a Match the card in that position gets steadily bigger wherever it goes, so a
Ramp deck wants a reliable card that reaches the second Scoring position each Turn, and
cheap cards ahead of it to hold the first.

**Void (Greed).** Void rewards running dry: each time a draw from an empty Deck
happens, the Crew gives your next Scoring card a large swing, Power +10 with Add +2 and Mult
×1.5. In the last Rounds, when Decks are empty, a Greed deck without a Pile-shuffling Crew
turns every empty draw into a finishing push instead of a dead draw. Void's exact reading is
flagged below.

**Engineer (evergreen).** One more Energy every Turn from Turn 3, so a Round's Budget is
28 + 5 = 33 rather than 28. Any deck uses it; it favours decks with expensive cards that
otherwise lose a Turn of tempo.

**Quartermaster (evergreen).** A Hand size of 7 means the discard-down after your Commit
fires later and less often, so you can hold cards for a big Turn. It supports any deck with
many draws, and it supports the Salvager's Discard-and-draw by giving it more to choose from.

**Salvager (Graveyard).** Each of your Commits, you may swap a card from your hand for a
fresh draw, and the Discard fires On discard, which Graveyard cards watch for. It also
smooths your hand ahead of the discard-down: the Discard comes first, so you may keep your
best card and send a dead one to the Pile.

**Captain (Ramp).** The card in your leftmost slot gains Power +1 for the match every time
it Scores. Because the Walk reads left to right, that card Scores first each Turn, and it
carries its growth into later Rounds as Memory. It wants a card you intend to keep in the
leftmost slot, and Anchored cards that hold that slot.

**Dredger (Graveyard, working name).** When your Deck is empty, Dredger shuffles your whole
Pile into your Deck and then the draw proceeds. Cards that went to the Pile as Discards come
back to be drawn again, so a Graveyard deck can recur its best cards late in the Match and
draw into them again. Pile contents are public, so the other seat knows what you can
draw.

## Flags for Ben

**Dredger is a working name.** Ben's tenth Crew is: when you would draw from an empty Deck,
shuffle your Pile into your Deck first (R55). Dredger is a placeholder; please give the
name.

**Void's reading, for Ben to confirm (R56).** Ben's sketch is "when you would draw on an
empty deck, get 10 +2x1.5 before the next walk". This note reads it as Power 10, Add +2 and
Mult ×1.5, all granted to the seat's next Scoring card, applied in that order before the
card Scores, and ending when the card has Scored (or at turn end if none Scored). "Power 10"
is read as a gain of 10 Power. The alternatives are the Bonus applying to the whole next Walk,
or the Power replacing rather than adding to the card's Power.

## Notes on the reading

These are places where the sketch in [[cards/Cards]] did not say, and this note chose.

- **Tallyman**: "every 4 score triggers, the next score gets +5 mult" is read as: your
  fifth Scoring card in a Walk gets Add +5, counting your own cards only, restarting each
  Walk. "+5 mult" is Add, as R56 states.
- **Shade and Veil**: "at the end of every turn" is turn end. Veil fires before exit marks
  resolve (it needs the Condemned mark), and Shade fires after (it needs the cards that
  remain). Shade offers up to three randomly chosen revealed cards, fewer if you have fewer;
  with none, it fizzles with the reason "no target".
- **Navigator**: "the second time a card scores" is the second of your cards to Score in the
  Walk, and the +2 applies after that Score, because a Crew fires after the effect that
  caused it.
- **Captain**: "the first card on your board" is the leftmost slot of your row, as R56 states;
  the slot is read when the card Scores, and "on score" is a Crew moment, so the +1 applies
  after that Score.
- **Quartermaster**: Ben's text says "7", which sets Hand size to 7 rather than adding
  to it. R14 also writes "+2" as an example of a Hand size change; that is for card
  abilities.
- **Salvager**: Ben's text says "On commit"; it fires once per accepted Commit of yours,
  before that seat's discard-down.
- **Dredger and Void together**: both fire On empty draw in slot order. If Dredger fires
  first and the Deck is no longer empty, the draw succeeds and Void does not fire. This is
  the only ordering rule this note adds.
