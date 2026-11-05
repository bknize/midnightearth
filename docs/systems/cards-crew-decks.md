---
type: system
tags: [system, cards, crew, decks]
status: growing
related: ["[[systems/systems-moc]]", "[[systems/game-loop]]", "[[systems/bot-training]]", "[[specs/cycle-8-ramp-bounce-crew/spec]]"]
created: 2026-11-05
updated: 2026-11-05
uid: 692bf835-9b24-4738-9df5-6a5ed267a33e
linear:
supersedes:
---

# Cards, Crew and deck lists

> What a card is made of, how its one effect works, what the four decks and eight Crew do, and how to add new content without breaking the game.

All of Midnight Earth's content lives in three JSON files under `godot/engine/data/`: `cards.json` (the card pool, 80 cards), `crew.json` (the Crew pool, 8 Crew) and `decks.json` (four decks, each 20 cards plus 3 Crew). The engine loads and checks all three before any match can start. If any check fails, nothing plays. This note describes those files and the code that gives them meaning, as the code stands after cycle 11.

How a match runs (rounds, turns, the score walk, events and when triggers fire) is in [[systems/game-loop]]. How the bots learn to play these cards is in [[systems/bot-training]].

## Card anatomy

Every card has an id, a name, a **cost**, a **flat** value, at most one **bonus** and at most one **effect**. That is the whole of `CardDef` (`card_def.gd`).

| Part | What it means | Legal values |
|---|---|---|
| Cost | Energy you pay to commit it. Your budget on turn *n* is *n* plus any carried energy. | 1 to 7 |
| Flat | The points it adds when it scores. | 0 to cost + 4 |
| ×bonus (`times`) | Multiplies your running multiplier before this card scores. | ×1.25, ×1.5, ×2 |
| +bonus (`plus`) | Adds whole units to your running multiplier. | +1, +2 |
| Effect | One trigger and one verb, with an amount and rules text. | see [[#Effects]] |

The flat cap of cost + 4 is why some cards look "too big". Tallow (cost 1, flat 5) and Cataclysm (cost 7, flat 11) sit right at the cap, and they pay for it with a drawback.

In the file, a bonus is written `null`, `{"x": 125}` or `{"plus": 1}`. The ×-part is kept in hundredths (125 means ×1.25), so all the arithmetic is whole numbers. Every platform then gets the same score, and that is what lets a match replay exactly from its log.

### How a card scores

Each seat has a running multiplier that starts at ×1.00 at the start of every walk. When a card scores, three things happen in order:

1. The multiplier is multiplied by the card's ×-part, rounded to the nearest hundredth.
2. The card's +-part is added to the multiplier.
3. The card adds *flat × multiplier* to its seat's score, rounded down.

The multiplier carries forward to that seat's later cards. So order matters: a multiplier card wants to sit to the left of your big flats. Shard (flat 0, ×1.5) scores nothing itself, but a Cinder (flat 7) after it scores 10 instead of 7. Put an Ashen King (+1) between them and the multiplier becomes 2.50, so the Cinder scores 17. The code is `ScoreWalk._score()` in `score_walk.gd`.

### Effective stats: what the card shows right now

The numbers on a card face are its **effective** stats, not its printed ones. `ScoreWalk.effective()` is the only function that computes them; the walk, the previews, the views and the board all read it. It builds them up in layers:

1. **Base**: the printed flat and bonus, or the copied base if Mirror has copied another card.
2. **Memory**: anything a persisting ability gave this card for the match (see the next section).
3. **Position**: Lodestone's ×1.25 to its neighbours, and Herald's ×1.5 while it is on the far left.
4. **Board changes**: flat gained this round (`flat_delta`) and +bonus that lasts until the walk ends (`temp_plus`).
5. **Tallyman**, the Crew: ×1.25 if the card's flat is now even.
6. **No-bonus mark**: a card hit by the (currently unused) "no bonus" effect shows ×1.00 and +0, whatever came before.

The **effective cost** is the printed cost minus any cost reduction in memory, never below 0 (`ScoreWalk.effective_cost()`). Every budget check reads it: the engine's legality check, the free first card, the bot, and the board's staging.

### Card memory and growth

The rule since cycle 8 (decision C3) is simple: **a card's stat changes are board-specific unless the ability says otherwise.** Board changes live in `CardState` (`card_state.gd`). They vanish when the card leaves its row, when it is un-revealed, and at the start of every round.

Some abilities say "for the match". Those write to the card's **memory**, a `CardMemory` (`card_memory.gd`) kept per card instance. It holds a flat delta, a ×-part delta, a +-part delta, a cost reduction and the uses left on a limited ability. Memory follows the card everywhere: into the hand, back to the deck at round start, through returns, un-reveals, the destroyed pile and even a recovery by the other seat. It is only wiped when a new match is created.

Growth comes in fixed steps, which the loader enforces: +1 or +2 flat, +0.25 or +0.5 to the ×-part, +1 to the +-part, −1 or −2 cost. There is no cap except that cost cannot go below 0. A ×-part delta adds in hundredths. A printed ×1.25 grown twice reads ×1.75, and a card with no ×-bonus grown once reads ×1.25.

A card whose memory is not empty carries a small gold **◆** on its face: in your hand, on either row and in the recover strip. The mark tells a grown card from a printed one at a glance. Growth on a card in your hand is private. Your opponent never learns a hidden card's identity from its memory.

**Uses countdowns.** An effect may carry `"uses": n`. Each time it fires, the card's memory counts down. With none left, the effect fizzles with the reason "spent" and does nothing. Two cards use this today: Oak and Messenger, both once per match. Because the countdown lives in memory, a card that has spent its use also shows the ◆ mark, even if its stats never changed.

### Face down, revealed, destroyed

You commit cards **face down**. The walk **reveals** them one slot at a time, and a reveal is when most effects fire. A revealed card can be **un-revealed**: it flips face down in its slot, loses its board changes and keeps its memory. When the walk reaches it again, it reveals in full and its on-reveal effect fires again. Four things un-reveal a card today: Phoenix (instead of being destroyed), the Echo card at turn end, and the Crew Shade and Veil.

A **destroyed** card does not vanish at once. It is marked in place, keeps its slot, and scores and fires nothing for the rest of the walk. A destroyed face-down card still flips when the walk reaches it, so you see what was lost. At turn end it moves to its controller's **destroyed pile**. Its identity there is public if it was ever revealed, and private to its seat if not. At round end both destroyed piles empty into the burn piles, so anything left there is gone for good.

Every destroy, random or chosen, goes through one function, `EffectResolver.destroy()`. That is why Phoenix's protection and the Crew's "your card destroyed" trigger work the same way for every destroy effect.

**Recoveries.** Grave Robber takes a card from either seat's destroyed pile into your hand. It comes back with printed stats and no board changes, but keeps its memory. An enemy card you recover plays and scores for you for the rest of the round, then goes back to its origin's deck at round start.

## Effects

An effect is a **trigger × verb**, plus an amount, the rules text and an optional uses count. `CardEffect` (`card_effect.gd`) holds it. In JSON it looks like this:

```json
{"trigger": "on_reveal", "verb": "draw", "amount": 1, "text": "Draw a card."}
```

The trigger says *when* and the verb says *what*. Keeping them separate means a new card is usually a new pairing of existing parts, not new code.

| Trigger | Fires when |
|---|---|
| `on_reveal` | This card is revealed. |
| `on_opponent_reveal` | An enemy card is revealed while this one is face up. |
| `on_ally_reveal` | Another of your cards is revealed while this one is face up. |
| `on_score` | This card scores. |
| `on_opponent_score` | An enemy card scores while this one is face up. |
| `on_moved` | This card is moved by any effect. |
| `ongoing` | Never fires. The engine reads it when needed: in `effective()`, in the destroy, or at turn end. |

The exact ordering of these hooks inside a walk is in [[systems/game-loop]].

**Choices.** Some verbs need a target. If nothing is eligible, the effect fizzles ("no target"). If exactly one target is eligible, the engine picks it for you. If two or more are, the walk pauses on a prompt until the player chooses. Immolator's prompt is the one multi-select: you pick any number of your cards, and none is a legal answer.

**Loader checks.** The loader (`CardDb`, `card_db.gd`) refuses some pairings, not just unknown names. The grow and return verbs work only on the triggers they were designed for (`CardEffect.ALLOWED_TRIGGERS`). `on_ally_reveal` takes only the ally flat and draw verbs. A grow amount must be one of the fixed steps. A verb that is limited by name (`grow_self_times_once`, `draw_once`) must carry `uses` greater than 0.

### Verb families

Each deck's verbs live in their own file. `EffectResolver.apply()` sends each verb to its family.

| Family | File | Verbs, in plain words |
|---|---|---|
| Shared | `effect_resolver.gd` | `draw` cards; destroy a random enemy card; make your first card next turn free; swap places with one of your cards. Five older verbs from cycle 4 still load but no shipped card uses them: draw then discard, the no-bonus mark, return at turn end, flat up on score, and carry unspent energy. |
| Ruin | `ruin_effects.gd`, `effect_resolver.gd` | `destroy` your leftmost other card; destroy one of yours then draw, or then gain its flat; sacrifice any number of yours for as many random enemy destroys; discard from your hand; the `burst` (+1 flat per enemy score, explode at 5); recover a destroyed card; and the un-reveal (`unreveal_instead`), an ongoing marker that turns a destroy into a flip. |
| Drift | `drift_effects.gd` | Move yourself to the far left or right; shift your other cards one slot left; reverse the enemy row; move an enemy card to the far left; swap an enemy card with its right neighbour; copy an enemy card's stats; +2 when moved; and two ongoing position bonuses (neighbour ×1.25, far-left ×1.5). |
| Bloom | `bloom_effects.gd` | The **grow** verbs: grow yourself (flat, ×, + or a one-time ×) on score or reveal; grow another card on your row; grow every card or one card in your hand; grow every other card on your row. Growth reaches your row and hand, never your deck. |
| Echo | `echo_effects.gd` | The **return** verbs (this card, another of yours, or an enemy card goes back to hand at turn end); the turn-end flip face down; cost down for the card to your right or for yourself; draw once per match; +1 flat this round when an ally reveals. |

No verb removes a card from a row in the middle of a walk. Returns and destroys wait for turn end, so the walk's slots stay stable while it runs.

## The four decks

`decks.json` holds four preconstructed decks of 20 distinct cards each. Ids carry the deck's letter (`r`, `d`, `b`, `e`), but that is only a convention; the engine does not check it. Each table lists the cards with effects. The plain "vanilla" cards are listed after it as *name cost/flat bonus*.

| Deck | Cards at cost 1 / 2 / 3 / 4 / 5 / 6 / 7 | Average cost | Crew |
|---|---|---|---|
| Ruin | 5 / 4 / 3 / 3 / 2 / 2 / 1 | 3.15 | Salvager, Veil, Quartermaster |
| Drift | 4 / 4 / 3 / 3 / 2 / 2 / 2 | 3.45 | Navigator, Veil, Tallyman |
| Bloom | 4 / 4 / 3 / 3 / 2 / 2 / 2 | 3.45 | Gardener, Tallyman, Quartermaster |
| Echo | 4 / 4 / 3 / 3 / 2 / 2 / 2 | 3.45 | Shade, Lookout, Quartermaster |

### Ruin: burn your own cards

*"Burn your own cards for bodies above the curve and random enemy destroys."* Ruin's cheap cards are big for their cost because they hurt you: they discard from your hand or destroy your own cards. Its payoffs turn those losses into enemy destroys, cards drawn or flat gained. It has the lowest curve, so there is plenty of cheap fodder to burn. Its Crew soften the self-damage: Salvager saves a destroyed card, and Veil saves a whole row once.

| Card | Cost / flat | What it does |
|---|---|---|
| Ember | 1 / 4 | On reveal, discard a card from your hand. |
| Tallow | 1 / 5 | On reveal, destroy your leftmost other card (face up or down). |
| Fuse | 2 / 1 | Each time an enemy card scores, +1 flat. At 5 flat it destroys itself and a random enemy card. |
| Rat | 2 / 1 | Each time an enemy card reveals, draw a card. |
| Grave Robber | 2 / 2 | On reveal, take a card from either destroyed pile into your hand. |
| Butcher | 3 / 3 | On reveal, destroy another card of yours, then draw 2. |
| Cinder | 3 / 7 | On reveal, discard a card from your hand. |
| Phoenix | 4 / 3, ×1.25 | If it would be destroyed while face up, it flips face down instead. |
| Glutton | 4 / 2 | On reveal, destroy another card of yours and gain its flat. |
| Immolator | 5 / 4 | On reveal, destroy any number of your cards, then as many random enemy cards. |
| Reaper | 6 / 6 | On reveal, destroy a random enemy card. |
| Cataclysm | 7 / 11 | On reveal, destroy your leftmost other card. |

Vanilla: Scrap 1/2, Tinder 1/1 ×1.25, Shard 1/0 ×1.5, Wick 2/3 ×1.25, Pyre 3/2 ×1.5, Wreck 4/5 ×1.25, Bonfire 5/5 ×1.5, Ashen King 6/4 +1.

### Drift: position is power

*"Positional bonuses and moving cards on both rows."* Drift cares where cards sit. Lodestone boosts its neighbours and Herald wants the far left. Its movers rearrange your row to set those bonuses up, and rearrange the enemy row to break theirs. Moving a card also changes when the walk reaches it, which Drift can use to delay or skip enemy cards (see [[systems/game-loop]]). Navigator pays +1 flat for every move.

| Card | Cost / flat | What it does |
|---|---|---|
| Scout | 1 / 1, ×1.25 | On reveal, move to the far left of your row. |
| Eddy | 2 / 1 | When moved, +2 to its +bonus until the walk ends. |
| Courier | 2 / 2, ×1.25 | On reveal, move to the far right of your row. |
| Mirror | 2 / 0 | On reveal, copy an enemy card's current flat and bonus as its own. |
| Shepherd | 3 / 3 | On reveal, swap places with another card on your row. |
| Lodestone | 3 / 2 | Ongoing: the cards on either side get ×1.25. |
| Herald | 4 / 3 | Ongoing: ×1.5 while on the far left of your row. |
| Hook | 4 / 4 | On reveal, move an enemy card to the far left of its row. |
| Undertow | 5 / 4 | On reveal, your other cards each move one slot left; the leftmost goes to the far right. |
| Tempest | 6 / 5 | On reveal, reverse the order of the enemy row. |
| Maelstrom | 7 / 6 | On reveal, swap an enemy card with the card to its right. |

Vanilla: Gust 1/2, Sprite 1/1 ×1.25, Pebble 1/3, Tide 2/3 ×1.25, Current 3/4 ×1.25, Keel 4/5 ×1.25, Beacon 5/5 ×1.5, Vane 6/3 +1, Horizon 7/7 ×2.

### Bloom: grow for good

*"Grow your cards for good: bonuses that stay for the match."* Bloom is the ramp deck. Its small cards start weak and get stronger every time they score, and its spells grow your hand and row. All of that growth is memory, so it survives the round. A Sapling that reads ×1.75 at the end of round 2 still reads ×1.75 when you draw it in round 3. Bloom is slow early and strong late. Gardener adds +1 flat to your whole row at every round end.

| Card | Cost / flat | What it does |
|---|---|---|
| Seed | 1 / 1 | Each time it scores, +1 flat for the match. |
| Sapling | 2 / 1 | Each time it scores, ×+0.25 for the match. |
| Tiller | 2 / 2 | On reveal, another card on your row gets +1 flat for the match. |
| Rain | 2 / 1 | On reveal, each card in your hand gets +1 flat for the match. |
| Vine | 3 / 2 | On reveal, one card in your hand gets ×+0.25 for the match. |
| Orchard | 3 / 2 | On reveal, each other card on your row gets +1 flat for the match. |
| Grove | 4 / 3 | Each time it scores, its +bonus grows by 1 for the match. |
| Harvest | 4 / 5 | On reveal, draw a card. |
| Oak | 5 / 4 | Once per match, when it scores, ×+0.5 for the match. |
| Redwood | 6 / 6 | On reveal, each card in your hand gets +2 flat for the match. |
| World Tree | 7 / 5 | On reveal, each other card on your row gets ×+0.25 for the match. |

Vanilla: Sprout 1/2, Acorn 1/1 ×1.25, Moss 1/3, Bramble 2/3 ×1.25, Trunk 3/4 ×1.25, Elder 4/3 ×1.5, Canopy 5/5 ×1.25, Bloom 6/4 +1, Ancient 7/7 ×1.5.

### Echo: reveal it again

*"Replay your reveals: returns, flips and cards that remember."* Echo gets value by revealing the same cards more than once. Some cards bounce back to your hand at turn end so you can play them again. Others flip face down so they reveal again next walk. Watchers like Refrain and Relay reward every one of those reveals. Whisper grows a little with each reveal, and the cost reducers make the replays cheaper. Lookout draws a card for every return or flip, and Shade gives one extra flip on turn 4.

| Card | Cost / flat | What it does |
|---|---|---|
| Whisper | 1 / 1 | On reveal, +1 flat for the match (every reveal, so it grows with each replay). |
| Flicker | 1 / 1, ×1.25 | On reveal, returns to your hand at the end of the turn. |
| Echo | 2 / 2 | Ongoing: at the end of each turn it flips face down. |
| Refrain | 2 / 1 | Each time another of your cards reveals, +1 flat this round. |
| Messenger | 2 / 2 | The first time it reveals each match, draw 2 (uses 1). |
| Tinker | 3 / 3 | On reveal, the card to its right costs 1 less for the match. |
| Recall | 3 / 2 | On reveal, another card of yours returns to your hand at the end of the turn. |
| Banish | 4 / 3 | On reveal, a revealed enemy card returns to its controller's hand at the end of the turn. |
| Lantern | 4 / 4 | On reveal, your first card next turn is free. |
| Relay | 5 / 3 | Each time another of your cards reveals, draw a card. |
| Reverb | 6 / 5 | On reveal, it costs 2 less for the match. |
| Encore | 7 / 10 | On reveal, returns to your hand at the end of the turn. |

Vanilla: Spark 1/2, Glint 1/3, Ripple 2/3 ×1.25, Chime 3/4 ×1.25, Mirage 4/5 ×1.25, Signal 5/5 ×1.5, Resonance 6/3 +1, Eternity 7/7 ×2.

A returned card goes to its controller's hand at turn end. If that hand is already at the cap of 7, the card is burned instead. Either way it keeps its memory and loses its board changes. No bounce refunds energy.

## Crew

**Crew** are persistent helpers. Each deck brings three, and they stand face up in a short line beside that side's row for the whole match: yours at bottom left by the hand, the opponent's at top left. Both sides' Crew are public. They are inspired by Balatro's Jokers, with one firm rule from Ben (R44): a Crew has no cost, flat or bonus of its own. It only acts on cards, hands, draws and reveals. Crew are not cards. They are never on a row, never targeted, and never destroyed, moved or copied.

Why Crew are deck data and not picked by the player: there is no deck builder yet, so "each preconstructed deck gets 3 crew members for now" (Ben, C4). Why eight: Ben's five, plus one each for Drift (movement), Bloom (growth) and Echo (reveals), with sharing across decks (C6). Veil exists because cycle 6 wanted a one-shot board-wide un-reveal, and C7 made it a Crew power instead of a card.

### Triggers and scopes

A Crew's trigger is one of: **turn start** (after the draws, before any commit), **round end**, **your card destroyed**, **your card moved**, **your card returned or flipped face down**, or **ongoing** (read by the score, never fired). Each Crew verb is tied to exactly one trigger, and the loader checks it.

A Crew fires only *after* the effect that caused it has fully resolved, never in the middle of it. `CrewEffects` queues each event and drains the queue once the effect is done. Without that, a Crew could act halfway through Immolator's "destroy that many" and change the count. If one effect destroys several of your cards, your Crew fire for each card in row order.

The **scope** sets how often a Crew may fire. `none` means unlimited. `round` means its uses come back at every round start. `match` means its uses never come back. A Crew with nothing eligible to act on does not fire and spends nothing.

### Optional prompts, Skip and badges

Three Crew are **optional**: Shade, Salvager and Veil. An optional Crew always opens a prompt, even when only one target is possible, because saying no is always allowed. The prompt shows the Crew's name and rules text, plus a **Skip** button where the multi-select's confirm button usually sits. Skip sends a logged `decline` action. Uses are spent only when you choose, never when you skip. A Crew prompt during the walk pauses it like any card prompt. Shade's prompt comes at turn start, before you can stage; Commit is disabled until you answer.

A limited Crew wears a **uses badge**: "1 left", then "spent", with the Crew dimmed. Unlimited Crew have no badge. When a Crew fires, the board lifts and settles it the way it does a card whose effect fires. You can tap a Crew to lift it and read it.

### The eight Crew

| Crew | Decks | Trigger | What it does | Uses | Prompts? |
|---|---|---|---|---|---|
| Quartermaster | Ruin, Bloom, Echo | Turn start, turn 1 | Draw 2 extra cards on the first turn of each round. | Unlimited | No |
| Tallyman | Drift, Bloom | Ongoing | Your cards with an even flat (0 counts) get ×1.25 when they score. | Unlimited | No |
| Shade | Echo | Turn start, turn 4 | You may flip one revealed card of yours face down. | Unlimited (once a round in practice) | Yes, optional |
| Salvager | Ruin | Your card destroyed | You may discard a card from your hand; the destroyed card returns to your hand at turn end instead of going to the pile. | 1 per round | Yes, optional |
| Veil | Ruin, Drift | Your card destroyed | You may flip every revealed card you control face down instead; none of them is destroyed. | 1 per match | Yes, optional |
| Navigator | Drift | Your card moved | The moved card gets +1 flat this round. | Unlimited | No |
| Gardener | Bloom | Round end | Each card on your row gets +1 flat for the match. | Unlimited | No |
| Lookout | Echo | Your card returned or flipped face down | Draw a card. | Unlimited | No |

A few details are worth knowing. The `amount` on Quartermaster and Shade is the turn number they fire on; Quartermaster's two draws are fixed in code (`CrewEffects.QUARTERMASTER_DRAWS`). Tallyman checks the card's effective flat, after growth and board changes. Gardener's growth is memory, so it lasts the match, while Navigator's +1 is a board change and lasts the round. Veil still counts as a destroy for the effect that caused it, so Butcher still draws. The destroyed card is un-destroyed, and your other revealed cards flip with it. Lookout also fires on Phoenix's flip and on Echo's turn-end flip, which is why it sits in the Echo deck.

## Deck lists

### The format

`decks.json` is version 2. Each deck has an id, a name, a one-line theme, 20 card ids and 3 Crew ids:

```json
{"id": "ruin", "name": "Ruin", "theme": "Burn your own cards for ...",
 "cards": ["r01", "r02", "...", "r20"], "crew": ["salvager", "veil", "quartermaster"]}
```

`DeckList.validate()` (`deck_list.gd`) checks every deck against the card pool and the Crew pool. A deck must have exactly 20 card ids, none repeated, each in the pool. It must name exactly 3 distinct Crew ids, each in the Crew pool. Deck ids must be unique. Two things are deliberately *not* checked. There is no cost mix rule (cycle 6 C3), and a Crew may serve several decks. The card pool also has no fixed size: a card can sit in `cards.json` without being in any deck.

### Named decks and seeded pairings

A match needs one deck id per seat. You can name them in the deck picker (a "You" and a "Bot" column), or with the `--deck=` and `--bot-deck=` flags. When a seat has no deck named, as in autoplay, the sweep and the training runs, the engine draws one from the match seed (`DeckList.seeded_pick()`). It uses its own stream derived from the seed, so it never disturbs the game's randomness, and the same seed always gives the same pairing. Each seat draws independently, so mirror matches like Ruin against Ruin happen. Either way, the log records the deck ids actually used, and a replay rebuilds the same decks.

## Adding content

Every content change is a data change, and many also need engine work. Content changes go through the normal cycle (`/spec` → `/exercise` → `/cycle`), because each one moves the bot stamp (below).

### Add a card

1. **Write the entry** in `cards.json`, keeping `"version": 4`. Give it a new unique id, a name, a cost from 1 to 7 and a flat from 0 to cost + 4. Its bonus is `null`, `{"x": 125|150|200}` or `{"plus": 1|2}`. Its effect is `null` or a trigger, verb, amount and text, plus `uses` if it is limited.
2. **Reuse a verb if you can.** If an existing trigger and verb do the job, the data entry is the only change. The loader will reject a pairing it does not allow, a grow amount off the fixed steps, or a limited verb with no `uses`.
3. **For a new verb**, the engine needs work. Add it to the end of `CardEffect.Verb` and `VERB_NAMES`, and to `ALLOWED_TRIGGERS`, `GROW_STAT` or `LIMITED_VERBS` if they apply. Implement it in its family file and route it in `EffectResolver.apply()`. If it chooses a target, give it a zone in `choice.gd`. The board also needs to play its events. That work belongs to the engine implementer. Past cycles have raised `MatchRules.RULES_VERSION` when behaviour changed, so old logs fail cleanly instead of replaying wrongly.
4. **Put it in a deck.** A deck is exactly 20 cards, so adding one means taking one out.

### Add a Crew

1. **Write the entry** in `crew.json`: id, name, trigger, verb, amount, `optional`, `uses`, scope and text. `uses` must be 0 for scope `none` and more than 0 for `round` or `match`. The verb must sit on its own trigger (`CrewDef.VERB_TRIGGER`).
2. **For a new ability**, add the verb to `CrewDef` (`Verb`, `VERB_NAMES`, `VERB_TRIGGER`) and implement it in `crew_effects.gd`. An optional Crew needs a zone in `PROMPT_ZONES`. A Crew that prompts at turn start also needs a fixed answer rule in the bot, because the bot cannot preview a turn start.
3. **Give it to a deck** by swapping it into that deck's `crew` list, which must stay at exactly three.

### Add a deck

Add an entry to `decks.json` with a unique id, a name, a theme, 20 distinct pool card ids and 3 distinct Crew ids. The picker shows it at once, as a tile with its name and theme. Seeded pairings start drawing it at once too, so many seeds pair different decks than before, and the seed-1 golden in `test_full_match.gd` must be re-pinned. The calibration script's default pairings in `scripts/bot/calibrate.py` name decks explicitly, so add the new deck there as well.

### Every data change moves the bot stamp

The shipped bot's weights are tied to a **stamp**: the rules version plus a hash of the bytes of `cards.json`, `decks.json` and `crew.json` (`BotStamp`, `engine/bot/bot_stamp.gd`). Change any of those files in any way, even a typo in rules text, and the stamp changes. The 50-seed sweep (`make sweep`, outside `make check`) and the bot tools then print `stamp=MISMATCH`. The gate stays green, but the weights no longer match the game, so a bot rerun is due before the cycle closes. The rerun steps are in [[systems/bot-training]], and each accepted result gets a row in [[planning/bot-ladder]].

## Where to look in the code

All paths are under `godot/engine/`.

| File | Responsibility |
|---|---|
| `data/cards.json`, `data/crew.json`, `data/decks.json` | The content itself. |
| `card_db.gd` | Loads and checks the card pool; any failure stops the engine. |
| `card_def.gd`, `card_effect.gd` | A card and its one effect; trigger and verb names; allowed pairings, grow steps, limited verbs. |
| `card_memory.gd` | Per-card memory for the match: stat deltas, cost reduction, uses left. |
| `card_state.gd` | Per-card board changes for the round: flat gained, temporary +bonus, copied base, destroyed and return marks. |
| `score_walk.gd` | `effective()`, `effective_cost()`, `uses_left()`, `is_grown()`, and the scoring arithmetic. |
| `effect_resolver.gd` | Fires an effect: uses countdown, shared verbs, prompts, the destroy pipeline, returns, the turn-end clear and flip. |
| `ruin_effects.gd`, `drift_effects.gd`, `bloom_effects.gd`, `echo_effects.gd` | Each deck's verb family. |
| `choice.gd` | Which targets each prompting verb may choose. |
| `crew_def.gd`, `crew_pool.gd` | A Crew and the Crew pool loader. |
| `crew_effects.gd` | The eight Crew abilities and the Crew queue. |
| `deck_list.gd` | The deck list, its validation and the seeded pairing. |
| `match_rules.gd` | Fixed numbers: deck size 20, Crew size 3, legal bonuses, grow steps, flat cap, rules version. |
| `bot/bot_stamp.gd` | The stamp that ties bot weights to this data. |

## Related

- [[systems/systems-moc]]: the other system guides.
- [[systems/game-loop]]: rounds, turns, the score walk, events and trigger timing.
- [[systems/bot-training]]: bots, the stamp and the rerun after a data change.
- [[planning/bot-ladder]]: the ledger of bot results under each stamp.
- [[specs/cycle-4-card-effects/spec]]: the first effects, prompts and the trigger model.
- [[specs/cycle-6-constructed-decks/spec]] and [[specs/cycle-6-constructed-decks/plan]]: the card format, the deck list, Ruin and Drift.
- [[specs/cycle-8-ramp-bounce-crew/spec]] and [[specs/cycle-8-ramp-bounce-crew/plan]]: card memory, Bloom, Echo and Crew (decisions C3–C7, C13).
- [[specs/cycle-7-bot-players/spec]]: the stamp and rerun rule.
