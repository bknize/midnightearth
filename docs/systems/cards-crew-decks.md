---
type: system
tags: [system, cards, crew, decks]
status: growing
related: ["[[systems/systems-moc]]", "[[systems/game-loop]]", "[[systems/bot-training]]", "[[rules/rules-moc]]", "[[rules/cards-v2]]", "[[rules/crew-v2]]", "[[rules/test-decks]]", "[[planning/cycles]]", "[[specs/cycle-9-rules-v2/spec]]"]
created: 2026-11-05
updated: 2026-11-09
uid: 692bf835-9b24-4738-9df5-6a5ed267a33e
linear: https://linear.app/night-science-llc/issue/NSC-160
supersedes:
---

# Cards, Crew and deck lists

> What a card is made of, how its abilities work, what the 90 cards, the ten Crew and the six decks do, and how to add new content without breaking the game.

All of Midnight Earth's content lives in three JSON files under `godot/engine/data/`: `cards.json` (the card pool, format 5: 90 cards, plus Dross, which only an ability makes), `crew.json` (the Crew pool, format 2: 10 Crew) and `decks.json` (format 3: six decks, each 40 cards plus 3 Crew). The engine loads and checks all three before any match can start. If any check fails, nothing plays. This note describes those files and the code that gives them meaning, as the code stands after DC-14 (rules version 10). It is the as-built counterpart of the design canon in [[rules/rules-moc]]: the cards are [[rules/cards-v2]], the Crew [[rules/crew-v2]] and the decks [[rules/test-decks]]. Where the build reads the canon differently, [[#Where the build differs from the canon]] says so. Every capitalised word is defined in [[rules/glossary]].

How a match runs (Rounds, Turns, the Walk, the trigger queue, events) is in [[systems/game-loop]]. The one bot is in [[systems/bot-training]]. How the cards were built is in the DC-13 and DC-14 rows of [[planning/cycles]].

## Card anatomy

Every card has an id, a name, a **tag** (its strategy, or evergreen), a **Cost**, a **Power**, at most one printed **Bonus** and any number of **abilities** with their rules text. That is the whole of `CardDef` (`card_def.gd`). A card with no Bonus and no text is a plain body.

| Part | What it means | Legal values |
|---|---|---|
| Tag | Greed, Combo, Disruption, Graveyard, Control, Ramp, or evergreen. | `CardDef.TAGS` |
| Cost | Energy you pay to Commit it. Your Budget on Turn *n* is *n* plus granted Energy. | 1 to 7; Colossus is 12 (see below) |
| Power | The points it adds to your walking total when it Scores. It may be negative. | -20 to 40 as loaded; in practice -3 to 12 |
| Bonus | A Mult or an Add. A Mult multiplies the card's Bonus value; an Add adds to it. | Mult ×1.25, ×1.5, ×2; Add +0.25, +0.5, +1; Saboteur's Mult ×0.75 |
| Abilities | Each has exactly one trigger moment, a verb and its amounts. | see [[#Abilities]] |

Power runs from Cost to Cost + 2 with no drawback and up to Cost + 4 with one, and a Bonus slides that band down (a Mult ×1.5 by 3, an Add +0.5 by 2); the exceptions are listed in [[rules/cards-v2]] section 3. Colossus (Cost 12, Power 12) has the one named Cost exception: its Ongoing sets its Cost to 7 on Turn 7 while it is in your hand (the verb `cost_on_turn`).

In the file, a Bonus is written `null`, `{"mult": 125}` or `{"add": 25}`, in hundredths, so all the arithmetic is whole numbers. Every platform then gets the same Score, and that is what lets a match replay exactly from its log.

### How a card Scores

When a card Scores, for its Controller's seat, in this order ([[systems/game-loop]] has the worked row):

1. The seat's walking total gains the card's **Power**.
2. The card's **Bonus value** starts at 1, gains every Add it carries, then is multiplied by every Mult it carries. A card with no Bonus has a Bonus value of 1.
3. The walking total is multiplied by the Bonus value.

A card carries its printed Bonus plus any it was granted (Void, Tallyman, Idler, Scrap). A Mult on the far right of a row multiplies the whole total, so Power wants to sit to the left of Bonuses. The code is `Scoring.step_total()` in `scoring.gd`, called from `ScoreWalk.score()`.

### Effective stats: what the card shows right now

The numbers on a card face are its **effective** stats, not its printed ones. `Scoring.stats()` is the only function that computes them; the Walk, the views and the board all read it. It builds them up in layers:

1. **Base**: the printed Power and Bonus, or the copied base if Mirror has copied another card.
2. **Memory**: anything a persisting ability gave this card for the match (see below).
3. **Board changes**: granted Power, Adds and Mults.
4. **Ongoing reads**: Banner's Power for plain cards, Boneyard's Power, Herald's Mult, Level's lowest Power, which only revealed cards receive (a face-down card is not levelled).
5. At Score time, **Crew grants** (`Scoring.score_stats()`): Void's held grants and Tallyman's Mult on the fifth Score.

The **effective Cost** is the printed Cost (or Colossus's 7 on Turn 7) plus Memory's Cost change, never below 0 (`Scoring.effective_cost()`). Every Budget check reads it.

### Memory and Board changes

The rule since cycle 8 (decision C3) is simple: **a change to a card is a Board change unless the ability says "for the match" or "permanently".** Board changes live in `CardState` (`card_state.gd`). They vanish when the card leaves its row, when it is Un-revealed, and at Round end.

Abilities that say "for the match" write to the card's **Memory**, a `CardMemory` (`card_memory.gd`) kept per card instance. It holds a Power gain, Mult growth steps (additive, then multiplicative, with a cap), Add growth, a Cost change, the uses left on a limited ability and any status given permanently. Memory follows the card everywhere: into the hand, back to a Deck, to the Pile and out of it, through Fleeting and Fade. It is wiped only when a new match is created.

Growth is stated by the ability: an Add gains +N, a Mult gains +N or is multiplied by ×N. It applies as the base, then the additive steps, then the multiplicative steps, rounded to the hundredth and capped where the card says (Sapling to ×2, Reliquary to ×2, Graft to ×2.5).

A card whose Memory is not empty carries a small gold **◆** on its face: in your hand, on either row and in a Pile. Growth on a card in your hand is private.

### Face down, revealed, Condemned

You Commit cards **face down**. The Walk **reveals** them one slot at a time, and a reveal is when most abilities fire. A revealed card can be **Un-revealed**: it flips face down in its slot, loses its Board changes and keeps its Memory, and its On reveal fires again when the Walk reaches it. Fade and Shade do this.

A **Condemned** card does not leave at once. It is marked, keeps its slot, and still Scores and still fires for the rest of the Walk. At turn end it goes to its Owner's **Pile**, which is public. Nothing leaves play except to a Pile, and a Pile lasts the whole Match: Revive, Exhume, Reset and the Crew Dredger are the ways out. A card entering a Pile is known to both seats.

The seven statuses (Muted, Squelched, Silenced, Condemned, Fleeting, Fade, Anchored) and the exit pass are in [[systems/game-loop]].

## Abilities

An ability is **one trigger moment × one verb**, plus amounts, an optional scope, watcher and zone brackets, a cap, a uses count and its rules text. `CardAbility` (`card_ability.gd`) holds it. In JSON it looks like this:

```json
{"moment": "on_score", "verb": "grow_self_mult_add", "amount": 25, "cap": 200,
 "scope": "match", "text": "On score: this card's Mult gets +0.25 for the match, to a maximum of ×2."}
```

The moment says *when* and the verb says *what*. The ten moments (and Ongoing):

| Moment | Fires when |
|---|---|
| `on_reveal` | The card flips face up in the Walk. |
| `on_score` | The card Scores. |
| `on_commit` | Its Controller's Commit is accepted, before that seat's discard-down. Revealed row cards, and hand cards whose text says "while in your hand". |
| `on_start` | Turn start, after the draws. Revealed cards only. |
| `on_discard` | A card enters a Pile. |
| `on_squelch` | The card becomes Squelched alone. |
| `on_empty_draw` | A seat would draw from an empty Deck. |
| `on_moved` | The card changes slot by a Move (not Placement). |
| `at_turn_end_before`, `at_turn_end_after` | Turn end, before or after the exit pass. |
| `ongoing` | Never fires. The engine reads it when needed: in `Scoring.stats()`, `TurnFlow.hand_size()`, `Statuses`, at Walk end. |

Two brackets refine this. A **watcher bracket** (`watch`: `self`, `other_own`, `opposing`, `any`) says whose event the ability watches: "On reveal (another card of yours)". A **zone bracket** (`zone`: `row`, `hand`) says where the card must be for the ability to act: "(while in your hand)". The exact order in which triggers resolve is in [[systems/game-loop]] and [[rules/resolution]].

**Choices.** Some verbs need a target. With no eligible target the ability fizzles ("no target"). With exactly one, the engine picks it. With two or more, play pauses on a prompt. Immolator and Exhume always prompt and may choose none. A random Condemn (Immolator, Fuse) picks from the whole opposing row; a pick on a protected or already Condemned card misses, visibly. Immolator's prompt is a multi-select with a minimum of 0, not an optional prompt: an empty set is its "none". Exhume asks once for "up to two" cards over both Piles (a prompt with a maximum, spec C15): an empty set or a Skip chooses none.

**Loader checks.** The loader (`CardDb`, `card_db.gd`) refuses a bad pool outright: format 5; unique ids; a known tag; Cost 1 to 7 (more only with the `cost_on_turn` verb); Power in range; a Bonus from the legal lists; each ability checked by `CardAbility.problem_of` (a known moment and verb, the verb allowed on that moment, amounts in the verb's range, a known scope, watcher and zone, whole uses, its own text); and a card `text` when it has abilities.

### Verb families

`Abilities.prepare()` and `resolve()` send each verb to its family.

| Family | File | Verbs, in plain words |
|---|---|---|
| Shared, Greed, Ramp, evergreen | `abilities.gd` | Draw, opponent draws, Discard a card or the hand; Condemn this card; Power growth for the row, the match or the Turn; Mult growth (Sapling, Graft); Mirror's copy; Nudge's ring shift; Delve and Lookout (look-ats, private); Energy grants; Cost reduction; Lantern's free first card; the Ongoings Banner, Brace, Bastion, Pantry and Colossus. |
| Combo and Disruption | `abilities_combo_disruption.gd` | Wick, Swell, Reprieve, Scrap, Twin, Reprise (Scores twice), Encore (retrigger), Reverb, Finale; Mute, Squelch and Silence; Litter's Dross; Saboteur's move to the other row; Hex, Jam, Stasis, Gag, Quorum. |
| Graveyard and Control | `abilities_graveyard_control.gd` | Fuse, Tithe, Reliquary, Glutton, Revive, Exhume, Immolator, Reset, Boneyard, Wraith; Eddy, Pin, Shepherd, Skip, Shake, Tempest, Cull, and the Ongoings Fence, Herald and Level. |

No ability removes a card from a row in the middle of a Walk. Condemn, Fleeting and Fade wait for the exit pass, so the Walk's slots stay stable while it runs.

## The 90 cards

The pool is ten cards for each of six strategies and thirty evergreen cards, with Costs 1 to 7 (Colossus 12). The text of each card is the text in `cards.json`; the design reasons and the Power guideline are in [[rules/cards-v2]]. Dross is the extra definition in the file: Cost 1, Power 0, no Bonus, "Ongoing (while in your hand): at the end of the Walk, before rounding, your walking total is multiplied by ×0.75 for each Dross in your hand". Litter creates it in the opponent's hand; Twin creates copies of itself. Every card an ability creates is a Dross card (C13). A Dross card is Owned by the seat it is created for from the moment it is created, is in no Deck, and has base values and no Memory. Within the Round it moves like any card: a Discard files it in its Owner's Pile. A Dross card lasts until the end of the Round, when it is removed from every zone (hand, row, Pile, Deck); a few last the whole Match (lifetime `match`, `CardDef.lifetime`; the default `round`). `CardDb` marks the Dross definition with the pool key `"created": true` (`CardDef.dross`), so no Deck may list it.

### Greed

*Raw numbers early. Cheap, efficient bodies for the first Rounds, a few cards that pay a Discard or a card for Power, and one finisher.* Tallyman and Void are its Crew. It wins by being ahead early and loses to a single Squelch on a spike card.

| Card | Cost | Power | Bonus | Rules text |
|---|---|---|---|---|
| Ember | 1 | 4 | - | On reveal: Discard a card from your hand. |
| Pip | 1 | 3 | - | - |
| Flare | 2 | 5 | - | On reveal: Condemn this card. |
| Skim | 2 | 2 | Mult ×1.25 | - |
| Cinder | 3 | 7 | - | On reveal: Discard a card from your hand. |
| Courier | 3 | 3 | - | On score: draw a card. |
| Banner | 4 | 3 | - | Ongoing: each of your cards that has no rules text has Power +4. |
| Bounty | 5 | 7 | - | On score: your opponent draws a card. |
| Gilt | 6 | 4 | Mult ×1.5 | - |
| Jackpot | 7 | 10 | - | On reveal: Discard your hand. |

### Combo

*Reveals and other triggers, set up cheaply and paid off late.* Combo wants cards to reveal more than once: Swell and Shade bring them back, Encore doubles the On reveals, Reprise makes every card Score twice (on both rows), and Finale and the Mult cards belong on the right of the row.

| Card | Cost | Power | Bonus | Rules text |
|---|---|---|---|---|
| Wick | 1 | 2 | - | On score: draw a card, then this card gets Power -1; then, if its Power is 0 or less, it gets Fleeting. |
| Refrain | 2 | 1 | - | On reveal (another card of yours): this card gets Power +1 until it leaves your row. |
| Swell | 2 | 2 | - | On reveal: another card of yours gets Fade. |
| Reprieve | 3 | 3 | - | On reveal: choose a card on either row; it gets Fleeting. |
| Scrap | 3 | 2 | - | On reveal: Discard a card from your hand; this card gets Add +N until end of turn, where N is 0.25 for each point of that card's Cost, at most 1. |
| Twin | 3 | 1 | - | On reveal: create a copy of this card in your hand. |
| Reprise | 4 | 3 | - | On commit: every card on both rows Scores twice this Turn. |
| Encore | 5 | 4 | - | On reveal: until end of turn, each of your other On reveal abilities resolves twice. |
| Reverb | 6 | 5 | - | On reveal: this card gets Fleeting and costs 2 less for the match. |
| Finale | 7 | 4 | - | On reveal: this card gets Power +2 for each of your other cards revealed this Turn, until end of turn. |

### Disruption

*Stop the other seat's win condition with Squelch and Mute.* Disruption aims at the far right of the opposing row, where Bonuses multiply the most. Litter fills the opponent's hand with Dross; Saboteur's negative Power and ×0.75 land last on the opposing row.

| Card | Cost | Power | Bonus | Rules text |
|---|---|---|---|---|
| Hush | 1 | 1 | - | On reveal: Mute an opposing card until end of turn. |
| Muzzle | 2 | 2 | - | On reveal: Squelch an opposing card until end of turn. |
| Litter | 3 | 2 | - | On reveal: create three Dross in your opponent's hand. |
| Saboteur | 4 | -3 | Mult ×0.75 | On reveal: move this card to the rightmost slot of your opponent's row. |
| Hex | 3 | 3 | - | On reveal: choose a card on either row. On start: Mute the chosen card until end of turn. |
| Jam | 4 | 3 | - | On score: Mute N random opposing cards until end of turn, where N is this card's Power. |
| Stasis | 4 | 3 | - | Ongoing: each Squelch applied by your effects lasts until this card leaves your row instead of until end of turn. |
| Gag | 4 | 2 | - | On commit: Squelch an opposing card permanently, then Condemn this card. |
| Quorum | 5 | 4 | - | On start: each seat chooses two of its revealed cards; every other revealed card on both rows is Muted until end of turn. |
| Eclipse | 6 | 5 | - | On reveal: Silence an opposing card until end of turn. |

### Graveyard

*Condemnation and Discard, with tools to cushion the losses and bring cards back.* Its Round is the dry Deck: Exhume and Reset refill Decks, and Dredger shuffles the Pile in on an empty draw.

| Card | Cost | Power | Bonus | Rules text |
|---|---|---|---|---|
| Fuse | 2 | 1 | - | On score (an opposing card): this card gets Power +1 until it leaves your row; then, if its Power is 5 or more, Condemn this card and one random opposing card. |
| Tithe | 2 | 2 | - | On discard (a Condemned card of yours Discarded at turn end): you have +1 Energy next Turn for each such card, at most +3 per turn end. |
| Reliquary | 3 | 2 | Mult ×1.25 | On discard (a card of yours entering your Pile from your hand): this card's Mult is multiplied by ×1.2 for the match, at most once per Turn, to a maximum of ×2. |
| Boneyard | 3 | 2 | - | Ongoing: this card has Power +1 for each four cards in both Piles, rounded down. |
| Wraith | 3 | 3 | - | Ongoing: your Condemned cards have Fade instead of Condemned when exit marks resolve. |
| Glutton | 4 | 2 | - | On reveal: Condemn one of your other cards; this card gets Power +N until it leaves your row, where N is that card's Power. |
| Revive | 4 | 3 | - | On reveal: choose a card in your Pile; put it face down on your row in the slot to the right of this card, then Condemn this card. |
| Exhume | 4 | 4 | - | On reveal: choose up to two cards in either Pile; shuffle each into its Owner's Deck. |
| Immolator | 5 | 4 | - | On reveal: Condemn any number of your other cards, then Condemn that many random opposing cards. |
| Reset | 6 | 5 | - | On reveal: shuffle both seats' Piles into their Decks, then Condemn this card. |

### Control

*Card movement and board manipulation.* Control arranges its own row to put a Mult in the rightmost slot (Herald) and pulls the other row apart with Tempest, Shake and Skip; Pin and Brace hold slots still; Fence and Cull punish wide rows.

| Card | Cost | Power | Bonus | Rules text |
|---|---|---|---|---|
| Eddy | 2 | 1 | Add +0.25 | On moved: this card's Add gets +0.25 until end of turn. |
| Pin | 2 | 2 | - | On reveal: choose a card on either row; it gets Anchored until this card leaves its row. |
| Shepherd | 3 | 3 | - | On reveal: swap this card with another card on your row. |
| Skip | 3 | 3 | - | On reveal: the next card to be revealed this Walk is moved to a different random slot of its row after its On reveal resolves and before it Scores. |
| Fence | 3 | 3 | - | Ongoing: when a card on either row would be moved left from the leftmost slot or right from the rightmost slot, Condemn it instead of moving it. |
| Herald | 4 | 3 | - | Ongoing: while this card is in the rightmost slot of your row, its Mult is ×1.5. |
| Level | 4 | 4 | - | Ongoing: each card's Power is the lowest Power among the revealed cards on its Controller's row, read before any Level applies. |
| Shake | 5 | 5 | - | On reveal: in each row, choose at random half of its cards, rounded down; Anchored cards can be chosen. Each chosen card, from left to right, swaps with the card to its left, wrapping from the leftmost slot to the rightmost. A chosen Anchored card does not move, and a moving card passes over an Anchored card to the next slot on its left. |
| Tempest | 6 | 5 | - | On reveal: reverse the order of the opposing row; Anchored cards stay in their slots. |
| Cull | 7 | 7 | - | On reveal: each seat chooses five cards on its row; Condemn every card on both rows that was not chosen. |

### Ramp

*Persistent card improvements across the Match, so late Rounds belong to the seat that invested.* Most of its growth is Memory, so it survives the Pile and the Deck. Colossus costs 7 on Turn 7.

| Card | Cost | Power | Bonus | Rules text |
|---|---|---|---|---|
| Whisper | 1 | 1 | - | On reveal: this card gets Power +1 for the match. |
| Sapling | 2 | 1 | Mult ×1.25 | On score: this card's Mult gets +0.25 for the match, to a maximum of ×2. |
| Rain | 2 | 1 | - | On reveal: each card in your hand gets Power +1 for the match. |
| Dynamo | 2 | 2 | - | On start: you have +1 Energy this Turn. |
| Tinker | 3 | 3 | - | On reveal: the card to the right of this card costs 1 less for the match. |
| Idler | 3 | 2 | - | On commit: if you Pass this Turn, this card gets Power +2 and Add +0.5 until end of turn. |
| Lantern | 4 | 4 | - | On reveal: the first card you commit next Turn costs 0, until you commit a card or next Turn ends. |
| Graft | 4 | 3 | - | On score: the card to the right of this card has its Mult multiplied by ×1.2 permanently, to a maximum of ×2.5. |
| Layaway | 5 | 6 | - | On commit (while in your hand): this card costs 1 less for the match. |
| Colossus | 12 | 12 | - | Ongoing (while in your hand): on Turn 7 this card's Cost is 7. |

### Evergreen

*Thirty broadly useful cards, mostly simple. Every deck can play them.* They carry no strategy tag; Delve and Lookout are the two cards that look at hidden information, shown to the looking seat only.

| Card | Cost | Power | Bonus | Rules text |
|---|---|---|---|---|
| Mote | 1 | 2 | - | - |
| Wisp | 1 | 1 | Mult ×1.25 | - |
| Tuft | 1 | 1 | - | On score: this card gets Power +1 until it leaves your row. |
| Pebble | 2 | 3 | - | - |
| Scout | 2 | 2 | - | On reveal: draw a card. |
| Delve | 2 | 2 | - | On reveal: look at the top three cards of your Deck, draw one of them and shuffle the other two into your Deck. |
| Lookout | 2 | 2 | - | On reveal: look at one face-down card on the opposing row. |
| Scapegoat | 2 | 3 | - | On squelch: end this card's Squelch and Condemn this card. |
| Ward | 2 | 2 | - | On score: your cards cannot be Muted until end of turn. |
| Mirror | 2 | 0 | - | On reveal: choose a revealed opposing card; this card copies its current Power and Bonus until end of turn. |
| Nudge | 2 | 3 | - | On reveal: move this card one slot to the right. |
| Cobble | 3 | 4 | - | - |
| Lyre | 3 | 2 | Mult ×1.5 | - |
| Pantry | 3 | 2 | - | Ongoing: your Hand size is +2. |
| Brace | 3 | 4 | - | Ongoing: this card is Anchored. |
| Loom | 3 | 3 | - | On reveal: the card to the right of this card gets Power +2 until end of turn. |
| Hearth | 4 | 5 | - | - |
| Rook | 4 | 4 | Add +0.25 | - |
| Bolster | 4 | 4 | - | On reveal: each of your other revealed cards gets Power +1 until end of turn. |
| Bastion | 4 | 4 | - | Ongoing: this card cannot be Condemned. |
| Granite | 5 | 6 | - | - |
| Crest | 5 | 4 | Mult ×1.5 | - |
| Torch | 5 | 4 | Add +0.5 | - |
| Basalt | 6 | 7 | - | - |
| Kiln | 6 | 6 | Mult ×1.25 | - |
| Orrery | 6 | 3 | Mult ×2 | - |
| Vault | 6 | 5 | Add +0.5 | - |
| Obsidian | 7 | 9 | - | - |
| Monolith | 7 | 6 | Mult ×1.5 | - |
| Zenith | 7 | 4 | Add +1 | - |

## Crew

**Crew** are persistent helpers. Each deck brings three, and they stand face up in a short line beside that side's row for the whole Match: yours at bottom left by the hand, the opponent's at top left. Both sides' Crew are public. A Crew has no Cost, Power or Bonus of its own. It only acts on cards, hands, draws, Budgets and Scores. Crew are not cards: never on a row, never a Target, never Condemned, moved or copied. `crew_def.gd` holds the data, `crew_pool.gd` loads `crew.json`, and `crew_abilities.gd` gives each verb its behaviour.

Why Crew are deck data and not picked by the player: there is no deck builder yet, so each preconstructed deck names its three (Ben, C4). Sharing is allowed: the same Crew may serve several decks, and both seats of a Match may bring the same one. A deck lists three different Crew.

### Moments and prompts

A Crew's moment is one of: Ongoing (read, never fired), On score, On commit, On empty draw, At turn end before the exit pass, At turn end after it. Each Crew verb sits on exactly one moment, and the loader checks it (`CrewDef.VERBS`).

A Crew fires only *after* the effect that caused it has fully resolved, as part of a Batch, after the cards (Q8 in [[rules/resolution]]). Among one seat's Crew the order is Crew slot order, the order of its deck list.

Three Crew are **optional** and always prompt, even for one target, because saying no is always allowed: Shade, Veil and Salvager. The prompt shows the Crew's name and text and a **Skip** button, which sends a logged `decline`. A decline does nothing and spends nothing. The other seven never prompt.

### The ten Crew

| Crew | Tag | Moment | What it does | Prompts? |
|---|---|---|---|---|
| Tallyman | Greed | Ongoing | Your 5th, 10th, 15th ... Scoring card in a Walk gets Mult ×2 for that Score. A card that Scores twice counts twice; a Squelched card does not count. | No |
| Void | Greed | On empty draw | Your next Scoring card gets Power +10, Add +0.5 and Mult ×1.25 until it Scores or turn end. Two empty draws in a Turn stack. | No |
| Engineer | evergreen | Ongoing | From Turn 3 of each Round, your Budget is +1 Energy. | No |
| Navigator | Ramp | On score | The second of your cards to Score in a Walk gets Power +2 permanently, after it has Scored. | No |
| Captain | Ramp | On score | When the card in the leftmost slot of your row Scores, it gets Power +1 for the match, after it has Scored. | No |
| Dredger | Graveyard | On empty draw | Shuffle your Pile into your Deck. The denied draw then resumes. | No |
| Shade | Combo | At turn end (after the exit pass) | Choose one of up to three random revealed cards of yours and Un-reveal it. | Yes, optional |
| Veil | Graveyard | At turn end (before the exit pass) | Choose one Condemned card of yours; it gets Fleeting instead of Condemned. | Yes, optional |
| Quartermaster | evergreen | Ongoing | Your Hand size is 7. | No |
| Salvager | Graveyard | On commit | You may Discard a card from your hand, then draw a card. | Yes, optional |

A few details are worth knowing. Pantry's +2 stacks on Quartermaster's 7 (9 in all); sets apply first, then additions. Void and Dredger both fire On empty draw with no re-check that the Deck is still empty (spec C29): Dredger shuffles the Pile in, Void's grant lands, and the resumed draw then succeeds, in either Crew slot order. Veil acts before the exit pass, so it also beats Wraith, which turns Condemned into Fade. Shade offers up to three random revealed cards from the Walk's rows after the exit pass has left them, and the card it Un-reveals fires its On reveal again next Turn. No Crew is tagged Disruption or Control, so those decks take Crew from the evergreen pair and the others.

Every Crew of this pool has unlimited uses (`uses` 0 in `crew.json`), so a Crew fires every time its moment occurs, once per subject, and does nothing when it has nothing eligible to act on.

## The six decks

`decks.json` holds six preconstructed decks of 40 cards each: the ten cards of one strategy, four copies of each, plus three Crew. They are test fixtures for players and the bot until a deck builder exists ([[rules/test-decks]]), not canon. The names Bloom, Ruin, Drift and Echo survive only as flavour; none is a deck.

| Deck | Cards (each ×4) | Crew | Cost sum | Average Cost |
|---|---|---|---|---|
| Greed | Ember, Pip, Flare, Skim, Cinder, Courier, Banner, Bounty, Gilt, Jackpot | Tallyman, Void, Engineer | 136 | 3.4 |
| Combo | Wick, Refrain, Swell, Reprieve, Scrap, Twin, Reprise, Encore, Reverb, Finale | Shade, Quartermaster, Engineer | 144 | 3.6 |
| Disruption | Hush, Muzzle, Litter, Saboteur, Hex, Jam, Stasis, Gag, Quorum, Eclipse | Engineer, Salvager, Quartermaster | 144 | 3.6 |
| Graveyard | Fuse, Tithe, Reliquary, Boneyard, Wraith, Glutton, Revive, Exhume, Immolator, Reset | Veil, Salvager, Dredger | 144 | 3.6 |
| Control | Eddy, Pin, Shepherd, Skip, Fence, Herald, Level, Shake, Tempest, Cull | Captain, Engineer, Quartermaster | 156 | 3.9 |
| Ramp | Whisper, Sapling, Rain, Dynamo, Tinker, Idler, Lantern, Graft, Layaway, Colossus | Navigator, Captain, Dredger | 152 (Colossus at 12) | 3.8 |

Greed and Ramp were built first (DC-13), the other four in DC-14. The deck tiles in the picker show the name and theme; the evergreen cards are in no deck, so a player cannot play them until the deck builder exists.

### The format

`decks.json` is version 3. Each deck has an id, a name, a tag, a one-line theme, 40 card ids and 3 Crew ids:

```json
{"id": "greed", "name": "Greed", "tag": "greed", "theme": "Raw numbers early. ...",
 "cards": ["gr01", "gr01", "gr01", "gr01", "gr02", "...", "gr10"], "crew": ["tallyman", "void", "engineer"]}
```

`DeckList.validate()` (`deck_list.gd`) checks every deck against the card pool and the Crew pool. A deck must have exactly 40 card ids (`MatchRules.DECK_SIZE`), each in the pool, none a Dross definition (the Dross card), with at most four copies of any id (`MAX_COPIES`). It must name exactly 3 different Crew ids, each in the Crew pool. Deck ids must be unique. Not checked: a cost mix rule, and the strategy of the cards (the canon lets a Deck draw from the whole pool). A Crew may serve several decks.

### Named decks and seeded pairings

A match needs one deck id per seat. You can name them in the deck picker (a "You" and a "Bot" column), or with the `--deck=` and `--bot-deck=` flags. When a seat has no deck named, as in autoplay and the sweep, the engine draws one from the match seed (`DeckList.seeded_pick()`). It uses its own stream derived from the seed, so it never disturbs the game's randomness, and the same seed always gives the same pairing. Each seat draws independently, so mirror matches happen. Either way, the log records the deck ids actually used.

## Adding content

Every content change is a data change, and many also need engine work. Content changes go through the normal cycle (`/spec` → `/exercise` → `/cycle`).

### Add a card

1. **Write the entry** in `cards.json`, keeping `"version": 5`. Give it a new unique id, a name, a tag, a Cost from 1 to 7, a Power, a Bonus (`null`, `{"mult": 125|150|200|75}` or `{"add": 25|50|100}`; 75, ×0.75, is the named below-×1 exception, `MatchRules.MULT_BELOW_ONE`, which Saboteur prints and Dross's ×0.75 per card mirrors at Walk end) and its abilities, each with a moment, a verb, amounts and its text. A card with abilities needs its own `text`.
2. **Reuse a verb if you can.** If an existing moment and verb do the job, the data entry is the only change. The loader rejects a verb on a moment it does not allow and amounts out of range.
3. **For a new verb**, the engine needs work. Add it to `CardAbility.VERBS` with its moments and ranges, implement it in the family file and route it from `Abilities.prepare()` and `resolve()`. If it chooses a target, give it a zone in `choice.gd`. The board also needs to play its events. That work belongs to the engine implementer. Past cycles raised `MatchRules.RULES_VERSION` when behaviour changed, so old logs fail cleanly instead of replaying wrongly.
4. **Put it in a deck.** A deck is exactly 40 cards with at most four copies of one, so adding a card means taking one out.

### Add a Crew

1. **Write the entry** in `crew.json`: id, name, tag, moment, verb, amounts, `optional`, `uses` and `scope`, and text. The verb must sit on its own moment (`CrewDef.VERBS`).
2. **For a new ability**, add the verb to `CrewDef.VERBS` and implement it in `crew_abilities.gd`. An optional Crew needs a zone for its prompt.
3. **Give it to a deck** by swapping it into that deck's `crew` list, which must stay at exactly three different ones.

### Add a deck

Add an entry to `decks.json` with a unique id, a name, a tag, a theme, 40 pool card ids (at most four of one) and 3 different Crew ids. The picker shows it at once. Seeded pairings start drawing it at once too, so many seeds pair different decks than before, and the seed-1 golden in `test_full_match.gd` must be pinned again.

### Data changes and the bot

There is no bot stamp any more: the shipped bot is the `random` bot, and the weights, the stamp and the bot ladder rerun went with the other bots (spec R70 to R75; the rerun provision is suspended). A data change can still move the sweep and the seed-1 golden. The golden in `godot/tests/test_full_match.gd` is empty until DC-14 pins it at T18. `make sweep` runs the multi-seed sweep outside the gate.

## Changed from v6

| Topic | Rules version 6 | Rules version 7 (built) |
|---|---|---|
| Card | Cost, a flat value, a ×-part and a +-part, one effect | Cost, Power, at most one printed Bonus (a Mult or an Add) and any number of abilities |
| Pool | 80 cards, four themed families | 90 cards by strategy (6 × 10 plus 30 evergreen), plus Dross |
| Decks | Four decks of 20 cards: Ruin, Drift, Bloom, Echo | Six decks of 40 cards (4 copies each) named for their strategy; the four old names are flavour only |
| Crew | Eight, with uses badges and scopes | Ten; all unlimited; three Crew prompts are optional |
| Removal | A destroy verb family, a destroyed pile, a burn pile | Condemn at turn end; one public Pile for the Match |
| Return | Return verbs, burned at the hand cap | Fleeting to the Owner's hand, with no cap |
| Triggers | Seven triggers | Ten moments, brackets and one queue |
| Format | cards v4, crew v1, decks v2 | cards 5, crew 2, decks 3; format 5 and rules 7 in the log |
| Bot stamp | Rules version plus a hash of the three data files | Gone with the other bots |
| Verb files | `ruin_effects.gd`, `drift_effects.gd`, `bloom_effects.gd`, `echo_effects.gd`, `effect_resolver.gd`, `crew_effects.gd` | `abilities.gd` and its two siblings, `crew_abilities.gd`, `statuses.gd`, `movement.gd`, `trigger_queue.gd` |

## Where the build differs from the canon

- **Data equals the canon.** The 90 cards, ten Crew and six decks match [[rules/cards-v2]], [[rules/crew-v2]] and [[rules/test-decks]] on Cost, Power, Bonus, tag and text. The differences are in code readings, below.
- **Pool size.** The file holds 91 card entries: 90 cards and the Dross card (a Dross definition).
- **Saboteur** is Cost 4, Power -3, Mult ×0.75 (spec C27); the loader names ×0.75 an exception to the printed Mult list.
- **Rounding.** The canon rounds only the final Score; the build rounds each multiply to a ten-thousandth ([[systems/game-loop]]).
- **Void's scope** is `turn` in the data: its grants end when the card has Scored or the Turn ends.
- **Navigator and Captain** carry scope `match` for the Power they give, which is Memory.
- **Readings where the canon is silent** (spec C15, accepted as built): Tithe's cap of +3 applies per Tithe; in Cull the Controller chooses first and in Quorum the first committer, and the second chooser sees the first's public picks; Fence's "wrap" is stepping off the ring of non-Anchored slots, and on a row with no ring (fewer than two non-Anchored slots) Fence does nothing; Skip's random slot is among the non-Anchored slots of the row; Fuse Condemns itself and a random opposing card each time it fires at Power 5 or more; Exhume asks once, "choose up to two", rather than once per card.
- **Stale comments.** A few headers in the engine still name T-numbers; the code is current.

## Where to look in the code

All paths are under `godot/engine/`.

| File | Responsibility |
|---|---|
| `data/cards.json`, `data/crew.json`, `data/decks.json` | The content itself. |
| `card_db.gd`, `card_def.gd`, `card_ability.gd` | The pool loader and its checks; a card; an ability with its moments, verbs, brackets and ranges. |
| `card_memory.gd`, `card_state.gd` | Memory for the match; Board changes for the row. |
| `scoring.gd` | Effective stats and Cost, Bonus value and the walking-total arithmetic. |
| `abilities.gd`, `abilities_combo_disruption.gd`, `abilities_graveyard_control.gd` | Each card verb family. |
| `statuses.gd`, `movement.gd` | The seven statuses and exit marks; Moves, Placement and the ring. |
| `trigger_queue.gd`, `trigger_context.gd`, `verb_handler.gd` | The queue and what an ability reads and writes. |
| `choice.gd` | Which targets each prompting verb may choose. |
| `crew_def.gd`, `crew_pool.gd`, `crew_abilities.gd` | A Crew, the Crew pool loader and the ten Crew behaviours. |
| `match_cards.gd` | Instance ids to definitions, including Dross cards (`record_dross`, `forget_dross`). |
| `deck_list.gd` | The deck list, its validation and the seeded pairing. |
| `match_rules.gd` | Fixed numbers: Deck size 40, copies 4, Crew size 3, Hand size 4, the trigger budget, the legal Bonuses, the rules version. |

## Related

- [[systems/systems-moc]]: the other system guides.
- [[systems/game-loop]]: Rounds, Turns, the Walk, statuses, the trigger queue and events.
- [[systems/bot-training]]: the bot.
- [[rules/rules-moc]]: the canon; [[rules/cards-v2]], [[rules/crew-v2]] and [[rules/test-decks]] are the notes this guide mirrors.
- [[planning/cycles]]: the DC-13 and DC-14 rows.
- [[specs/cycle-9-rules-v2/spec]]: requirements and Ben's clarifications.
- [[specs/cycle-8-ramp-bounce-crew/spec]]: where Memory and Crew began (decisions C3 to C7).
