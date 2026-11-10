---
type: planning
tags: [planning, phase-3]
status: closed
related: ["[[planning/planning-moc]]"]
created: 2026-11-02
updated: 2026-11-05
uid: cf1602f7-03cf-44f4-b4d4-7cfa2339fe9a
supersedes:
phase: 3-game-loop
---

# Phase 3 — Game loop: the MVP rules

Interrogation of the MVP rules before any spec is written. The brief's rules are
reproduced verbatim, then every gap an implementer would have to guess at is listed.
Decisions are recorded at the bottom as Ben makes them.

## The brief, verbatim

- A 'match' is 1v1 between two players (human or bot).
- A match has 7 rounds, with 7 turns.
- Players play cards, which increase the players' score.
- Whoever has the highest score at the end of the last turn wins the round.
- Whoever wins 4 rounds first, wins the match.
- To start: a deck is 20 cards; cards have an energy cost (1–7); players can spend up
  to Turn Number energy per turn (turn 1 is 1 energy, etc); cards have a power number,
  which adds to the turn's score.
- This is the MVP, the minimum playable feature to start with.

## What is fixed by the brief

| Rule | Value |
|---|---|
| Players | 2, each human or bot |
| Match | up to 7 rounds; first to 4 round wins |
| Round | 7 turns |
| Energy per turn | equal to the turn number, 1 through 7 |
| Deck | 20 cards |
| Card | energy cost 1–7, power number |
| Round winner | highest score at the end of turn 7 |

## Arithmetic the brief implies

- A full match is up to 49 turns per player. At roughly 15–20 seconds per turn against a
  bot, a match runs 12–16 minutes; a 4–0 match runs about 7.
- Energy across a round sums to 28. With 20 cards per deck and a one-card draw per turn,
  a player sees at most 10 cards in a round (3 opening + 7 draws), so the deck cannot be
  exhausted inside one round and the whole deck is never seen in a round.
- If the deck persisted across rounds with one draw per turn, it would run out partway
  through round 2, so either the deck is reshuffled per round or there is a
  reshuffle rule.

## Gaps an implementer would have to guess at

| # | Gap | Why it matters |
|---|---|---|
| G1 | Turn structure: simultaneous commit-and-reveal, or alternating plays? | Shapes the engine's action model, the bot, the 3D reveal choreography, and whether hidden information exists |
| G2 | Does a played card stay on the board for the round, with round score = sum of power on board, or is power banked and the card discarded? "Adds to the turn's score" is ambiguous | Board persistence is what future card effects (ongoing, on-reveal, destroy) act on |
| G3 | Hand and draw: opening hand size, draw per turn, hand cap, what happens at deck exhaustion, whether deck and hand reset each round | Determines how much of a 20-card deck is ever seen and how much variance a round has |
| G4 | Ties: a tied round, and a match where nobody reaches 4 wins within 7 rounds | Must be defined or the match can fail to end |
| G5 | Energy: may several cards be played in one turn if their costs sum to at most the turn number? Does unspent energy carry over? | Multi-card turns change hand size pressure and the bot's search space |
| G6 | Card pool for the MVP: how many distinct cards, duplicates per deck, prebuilt decks or a deck builder, and the vanilla power curve (power as a function of cost) | The MVP's content volume and the art budget |
| G7 | Bot policy: random legal play, greedy max power, or lookahead | Greedy is a few lines; lookahead needs the deterministic engine from D4 |
| G8 | Who commits first within a turn, and what the second committer sees | Resolved by R1/R8: the second committer sees the count of face-down cards; order is round 3 |
| G9 | Mulligan, pass, and concede | Small rules that are painful to add late to the UI |
| G10 | Play regions for the 3D table: hand, deck, discard, per-player board, score display; is there one shared board or a side per player, and is there a board slot limit? | Card3D collections map one-to-one onto these regions |

## Decisions

### Round 1 (Ben, 2026-11-02, all recommendations accepted)

| # | Decision | Consequence |
|---|---|---|
| R1 | **Sequential face-down commit, then reveal** (amended by R8, 2026-11-02). Within a turn, players commit in order: the first player places cards face down on their side of the shared board, the second player sees **how many** cards were placed (not which) and then commits; all cards then reveal. Card identities are hidden until reveal. Commit order is settled in round 3. | Engine turn = two committed action sets resolved together, with the second committer's visible state including the first's face-down count; the bot going second may use that count; reveal order is part of the deterministic action log (D4) |
| R2 | **Played cards stay on the board for the round.** Round score = sum of power on your side, recomputed every turn. The board clears when the round ends. | Board state is a first-class engine object; future on-reveal and ongoing effects have something to act on |
| R3 | **Every round starts fresh.** Shuffle all 20 cards, opening hand of 3, draw 1 at the start of each turn, hand cap 7 with overdraw burned. The deck cannot run out inside a round. | A player sees at most 10 cards per round; per-round shuffle seeds come from the match seed |
| R4 | **Ties.** A tied round awards no win. The match ends at 4 wins or after round 7; then more round wins takes it, and equal round wins triggers sudden-death rounds until one is won. | Match state tracks wins per player and rounds played; sudden death reuses the round loop unchanged |

### Round 2 (Ben, 2026-11-02; 1a/2a/3a accepted, 4 answered in his own words)

| # | Decision | Consequence |
|---|---|---|
| R5 | **Multi-card turns.** Any number of cards per turn as long as costs sum to at most the turn number. Unspent energy is lost. | Legal-play enumeration is a small subset-sum over a hand of at most 7 |
| R6 | **One fixed 20-card deck used by both players.** Costs 4×1, 4×2, 3×3, 3×4, 2×5, 2×6, 2×7; power = cost + 0, 1 or 2, varied per card so no two are identical. No deck builder. | MVP art = 20 illustrations; balance is a mirror match; card data is one JSON file |
| R7 | **Greedy bot.** Each turn, the legal combination with the highest total power, ties broken by the seeded RNG. | Lookahead bots are a later cycle and the engine's first real consumer |
| R8 | **Table regions (Ben's words).** Deck and discard are not on screen: drawn cards sweep in from off-screen on one side, discarded or cleared cards sweep off the opposite side. The player's hand fan sits at the bottom; the opponent's hand fan is visible face down so its card count is readable. The board is **shared**: both players' face-down commits sit on it, and the player going second sees how many cards the opponent has placed before playing. | Card3D collections: two hand fans, one shared board with two rows, plus off-screen spawn and exit anchors; HUD shows score per side, round-win pips, turn energy and a commit button |

Small rules accepted as defaults (no objection, 2026-11-02): no mulligan; passing is
committing with no cards; concede lives in a pause menu.

### Round 3 (Ben, 2026-11-02, in his own words)

| # | Decision | Consequence |
|---|---|---|
| R9 | **The player who won the last turn commits first, regardless of overall score. Cards reveal alternating, starting with the first card of the first committer.** | The engine tracks a per-turn winner; the reveal sequence interleaves the two commit lists in commit order |

Edge cases taken as defaults (stated 2026-11-02, Ben may override):

- "Won the last turn" = higher total board score after the previous turn's reveal (R2).
- Tied previous turn: the previous first committer commits first again.
- Turn 1 of a round: the loser of the previous round commits first; turn 1 of the match
  (and of a sudden-death round after a tied round count) is a seeded coin flip.
- Reveal interleaving: first committer's card 1, second committer's card 1, first
  committer's card 2, and so on; when one side's cards run out, the rest reveal in order.
  A player who committed nothing simply has no reveals.

Phase 3 is closed. Open items carried into specs: match length (49 turns) is a tuning
knob, not a rule; lookahead bots, deck building and card effects are post-MVP.

Parked (Ben, 2026-11-02, after DC-01): the DC-01 50-seed greedy-vs-greedy sweep went to
sudden death in 9 of 50 matches (39 ended on 4 wins, 2 after round 7). The mirror deck and
greedy bots may exaggerate this; revisit sudden-death frequency once a smarter bot or real
playtests give better data. See [[specs/cycle-1-match-engine/spec]] and [[planning/cycles]].

Amended (DC-07, 2026-11-04, [[specs/cycle-6-constructed-decks/spec]] C2, C3, C6):

- **R6** now reads: each seat plays a 20-card constructed deck chosen from the deck list
  (Ruin and Drift ship first); the 4-4-3-3-2-2-2 cost mix is a design guideline, not a
  loader rule, and flat may reach cost+4 on cards with a drawback. The DC-05 mirror deck is
  a test fixture only.
- **The multiplier** is a running mult in hundredths from ×1.00. A card carries at most one
  bonus: a ×-bonus (×1.25, ×1.5, ×2) multiplies the mult, a +-bonus (+1, +2) adds to it,
  and each card scores floor(flat × mult). Integer arithmetic only, so replays agree on
  every platform.

Amended (DC-09, 2026-11-05, [[specs/cycle-8-ramp-bounce-crew/spec]] C3, Ben's rule):

- **Card stats are board-specific** unless an ability says otherwise: a change ends when the
  card leaves its row or the round ends. An ability may give a card instance **memory for
  the match** (flat, ×-part and +-part deltas, a cost reduction, the uses left of a limited
  ability) that survives rounds, the hand, the deck, the piles, a return and a recovery,
  and is cleared only when a match is created. Limited-use abilities count down in that
  memory. A card's effective cost is its printed cost less its reduction, never below 0.
