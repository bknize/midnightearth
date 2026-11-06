---
type: reference
tags: [reference, rules-v2, test-decks]
status: seedling
related: ["[[specs/ruleset-v2/spec]]", "[[rules/rules-moc]]", "[[rules/glossary]]", "[[rules/cards-v2]]", "[[rules/crew-v2]]", "[[systems/cards-crew-decks]]", "[[cards/Cards]]"]
created: 2026-11-06
updated: 2026-11-06
uid: b71781b5-cb69-4812-b679-e43dda713bba
linear: https://linear.app/night-science-llc/issue/NSC-142/t06-test-decks-moc-and-home
supersedes:
---

# Test decks (ruleset v2)

This note is design for ruleset v2, not yet built. It lists six 40-card test decks, one per
strategy. The decks that run today (Bloom, Ruin, Drift and Echo) are described in
[[systems/cards-crew-decks]]. The requirements are R63 and R64 of [[specs/ruleset-v2/spec]];
the cards are in [[rules/cards-v2]] and the Crew in [[rules/crew-v2]].

## These are fixtures, not canon

These decks are test fixtures for players and bots until a deck builder exists. They are not
canon: no deck list here is the "right" deck for a strategy, and the rules do not depend on
any of them. Change them freely when cards change.

## How a deck is built

Each deck is the ten cards of one strategy section of [[rules/cards-v2]], four copies of
each: 10 cards x 4 = 40 cards, the Deck size and copy limit of R18. Each deck lists three
different Crew (R58). Four copies of every card leave the average Cost unchanged:
(sum x 4) / 40 = sum / 10.

## The six decks

| Deck | Cards (each x 4) | Crew | Cost sum x 4 | Average Cost |
|---|---|---|---|---|
| Greed | Ember, Pip, Flare, Skim, Cinder, Courier, Banner, Bounty, Gilt, Jackpot | Tallyman, Void, Engineer | 34 x 4 = 136 | 136 / 40 = 3.4 |
| Combo | Wick, Refrain, Swell, Reprieve, Scrap, Twin, Reprise, Encore, Reverb, Finale | Shade, Quartermaster, Engineer | 36 x 4 = 144 | 144 / 40 = 3.6 |
| Disruption | Hush, Muzzle, Litter, Saboteur, Hex, Jam, Stasis, Gag, Quorum, Eclipse | Engineer, Salvager, Quartermaster | 35 x 4 = 140 | 140 / 40 = 3.5 |
| Graveyard | Fuse, Tithe, Reliquary, Boneyard, Wraith, Glutton, Revive, Exhume, Immolator, Reset | Veil, Salvager, Dredger | 36 x 4 = 144 | 144 / 40 = 3.6 |
| Control | Eddy, Pin, Shepherd, Skip, Fence, Herald, Level, Shake, Tempest, Cull | Captain, Engineer, Quartermaster | 39 x 4 = 156 | 156 / 40 = 3.9 |
| Ramp | Whisper, Sapling, Rain, Dynamo, Tinker, Idler, Lantern, Graft, Layaway, Colossus | Navigator, Captain, Dredger | 38 x 4 = 152 | 152 / 40 = 3.8 |

The Cost sums, from the Cost column of [[rules/cards-v2]]:

- **Greed:** 1 + 1 + 2 + 2 + 3 + 3 + 4 + 5 + 6 + 7 = 34.
- **Combo:** 1 + 2 + 2 + 3 + 3 + 3 + 4 + 5 + 6 + 7 = 36.
- **Disruption:** 1 + 2 + 3 + 3 + 3 + 4 + 4 + 4 + 5 + 6 = 35.
- **Graveyard:** 2 + 2 + 3 + 3 + 3 + 4 + 4 + 4 + 5 + 6 = 36.
- **Control:** 2 + 2 + 3 + 3 + 3 + 4 + 4 + 5 + 6 + 7 = 39.
- **Ramp:** 1 + 2 + 2 + 2 + 3 + 3 + 4 + 4 + 5 + 12 = 38 (Colossus counts at its printed Cost of 12).

## Why these Crew

Crew come from the tags in [[rules/crew-v2]] and the Crew lines of the strategy plans in
[[rules/cards-v2]].

- **Greed:** Tallyman and Void are the two Greed Crew; Engineer is the evergreen pick named in
  the Greed plan.
- **Combo:** Shade is the Combo Crew; Quartermaster (a larger Hand holds the combo pieces) and
  Engineer are the two the Combo plan names.
- **Graveyard:** Veil, Salvager and Dredger are the three Graveyard Crew.
- **Ramp:** Navigator and Captain are the two Ramp Crew; Dredger brings grown cards back from
  the Pile, as the Ramp plan says.
- **Disruption:** no Crew is tagged Disruption in [[rules/crew-v2]], so the picks are the best
  fit. Engineer pays for Eclipse (Cost 6) and the Cost 4 cards; Salvager (Graveyard) smooths
  the hand, as the Disruption plan names; Quartermaster (evergreen) lets the seat hold
  Muzzle, Hex and Eclipse until the right Turn.
- **Control:** no Crew is tagged Control either. Captain (Ramp) pairs with Pin and Herald,
  which hold the leftmost slot its Power +1 for the match needs; Engineer is the evergreen
  pick the Control plan names; Quartermaster (evergreen) keeps Cull, Tempest and Shake in hand
  until the Turn they matter.

Count: 6 decks x 3 Crew = 18 slots. Engineer fills 4, Quartermaster 3, Captain 2, Salvager 2,
Dredger 2, and Tallyman, Void, Shade, Veil and Navigator 1 each (5): 4 + 3 + 2 + 2 + 2 + 5 =
18. Sharing is allowed (R58).

## Bloom, Ruin, Drift and Echo

Bloom, Ruin, Drift and Echo are not fixtures of ruleset v2 (R64). They survive only as loose
flavour, loosely correlated with the card choices a player might make, and not as four finite
decks of the game. In Ben's words: "bloom, drift, ruin, and echo remain as loosely correlated
to the card choices, but they are not 4 finite fixtures of the game". The six decks above are
organised by strategy, and none of them takes an old name.
