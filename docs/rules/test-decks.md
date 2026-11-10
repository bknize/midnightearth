---
type: reference
tags: [reference, rules-v2, test-decks]
status: built
related: ["[[specs/ruleset-v2/spec]]", "[[rules/rules-moc]]", "[[rules/glossary]]", "[[rules/cards-v2]]", "[[rules/crew-v2]]", "[[systems/cards-crew-decks]]", "[[cards/Cards]]"]
created: 2026-11-06
updated: 2026-11-06
uid: b71781b5-cb69-4812-b679-e43dda713bba
supersedes:
---

# Test decks (ruleset v2)

The rules in this note are built since DC-14 (rules version 7); the DC-13 and DC-14 rows of
[[planning/cycles]] record how and the readings made on the way. It lists six 40-card test
decks, one per strategy, as built in [[systems/cards-crew-decks]]. The requirements are R63 and R64 of [[specs/ruleset-v2/spec]];
the cards are in [[rules/cards-v2]] and the Crew in [[rules/crew-v2]].

## These are fixtures, not canon

These decks are test fixtures for players and bots until a deck builder exists. They are not
canon: no deck list here is the "right" deck for a strategy, and the rules do not depend on
any of them. Change them freely when cards change.

## How a deck is built

Each deck is the ten cards of one strategy section of [[rules/cards-v2]], four copies of
each: 10 cards × 4 = 40 cards, the Deck size and copy limit of R18. Each deck lists three
different Crew (R58). Four copies of every card leave the average Cost unchanged. The T07 re-tune of the printed Bonuses changed Power and Bonus only, no Cost, so every sum and average below is unchanged and was re-checked against the Cost column of [[rules/cards-v2]]:
(sum × 4) / 40 = sum / 10.

## The six decks

| Deck | Cards (each × 4) | Crew | Cost sum × 4 | Average Cost |
|---|---|---|---|---|
| Greed | Ember, Pip, Flare, Skim, Cinder, Courier, Banner, Bounty, Gilt, Jackpot | Tallyman, Void, Engineer | 34 × 4 = 136 | 136 / 40 = 3.4 |
| Combo | Wick, Refrain, Swell, Reprieve, Scrap, Twin, Reprise, Encore, Reverb, Finale | Shade, Quartermaster, Engineer | 36 × 4 = 144 | 144 / 40 = 3.6 |
| Disruption | Hush, Muzzle, Litter, Saboteur, Hex, Jam, Stasis, Gag, Quorum, Eclipse | Engineer, Salvager, Quartermaster | 36 × 4 = 144 | 144 / 40 = 3.6 |
| Graveyard | Fuse, Tithe, Reliquary, Boneyard, Wraith, Glutton, Revive, Exhume, Immolator, Reset | Veil, Salvager, Dredger | 36 × 4 = 144 | 144 / 40 = 3.6 |
| Control | Eddy, Pin, Shepherd, Skip, Fence, Herald, Level, Shake, Tempest, Cull | Captain, Engineer, Quartermaster | 39 × 4 = 156 | 156 / 40 = 3.9 |
| Ramp | Whisper, Sapling, Rain, Dynamo, Tinker, Idler, Lantern, Graft, Layaway, Colossus | Navigator, Captain, Dredger | 38 × 4 = 152 | 152 / 40 = 3.8 |

The Cost sums, from the Cost column of [[rules/cards-v2]]:

- **Greed:** 1 + 1 + 2 + 2 + 3 + 3 + 4 + 5 + 6 + 7 = 34.
- **Combo:** 1 + 2 + 2 + 3 + 3 + 3 + 4 + 5 + 6 + 7 = 36.
- **Disruption:** 1 + 2 + 3 + 3 + 4 + 4 + 4 + 4 + 5 + 6 = 36 (Saboteur is Cost 4, C27).
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
- **Control:** no Crew is tagged Control either. Captain (Ramp) pairs with Pin:
  Pin holds the leftmost slot its Power +1 for the match needs (Herald wants the rightmost
  slot instead); Engineer is the evergreen pick the Control plan names; Quartermaster (evergreen) keeps Cull, Tempest and Shake in hand
  until the Turn they matter.

Count: 6 decks × 3 Crew = 18 slots. Engineer fills 4, Quartermaster 3, Captain 2, Salvager 2,
Dredger 2, and Tallyman, Void, Shade, Veil and Navigator 1 each (5): 4 + 3 + 2 + 2 + 2 + 5 =
18. Sharing is allowed (R58).

## Bloom, Ruin, Drift and Echo

Bloom, Ruin, Drift and Echo are not fixtures of ruleset v2 (R64). They survive only as loose
flavour, loosely correlated with the card choices a player might make, and not as four finite
decks of the game. In Ben's words: "bloom, drift, ruin, and echo remain as loosely correlated
to the card choices, but they are not 4 finite fixtures of the game". The six decks above are
organised by strategy, and none of them takes an old name.
