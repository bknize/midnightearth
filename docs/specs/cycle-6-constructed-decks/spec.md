---
type: spec
tags: [spec, cycle-6-constructed-decks, engine, board, ui]
status: approved
related: ["[[specs/cycle-6-constructed-decks/plan]]", "[[specs/cycle-6-constructed-decks/tasks]]", "[[specs/cycle-5-walk-cursor/spec]]", "[[specs/cycle-4-card-effects/spec]]", "[[planning/phase-3-game-loop]]", "[[planning/phase-1-tech-stack]]", "[[planning/cycles]]"]
created: 2026-11-04
updated: 2026-11-04
uid: 07879b22-a661-4503-ac79-398cff33e19d
linear:
supersedes:
---

# Spec: Cycle 6 — constructed decks

**Slug:** `cycle-6-constructed-decks`  ·  **Change type:** engine + scene + ui  ·  **Status:** approved (Ben, 2026-11-04, five rounds; signed off 2026-11-04: "proceed with 6")  ·  **Runs as:** the next `DC-NN` milestone

Cycle 6 replaces the single mirror deck with constructed decks picked before the match,
rebalances the multiplier the Balatro way (a common ×-bonus, a rare +bonus, a running mult
that starts at ×1.00), and ships the first two of four themed decks: **Ruin**, a
destruction deck that destroys and discards its own cards for over-curve bodies and
random enemy destroys, and **Drift**, a movement deck built on positional bonuses and on
rearranging both rows. A pre-match picker chooses a deck for the player and one for the
bot; `--deck=` and `--bot-deck=` flags do the same for autoplay and the gate. The ramp
and bounce decks, Crew cards and per-deck bot tuning are the next two cycles (C1).

## Intent

After cycle 6, Ben launches the game, picks Ruin for himself and Drift for the bot, and
plays a match in which his cards read "×1.25" or "+1" instead of a bonus number, his row
tally climbs in hundredths, he sacrifices three of his own cards to destroy three of the
bot's at random, recovers a destroyed card from either pile, watches the bot reverse his
row, and every match, deck pairing included, still replays from its log.

## Non-goals (C1, C5, C9)

- No ramp deck, no bounce deck, no Crew cards, no per-deck bot tuning: cycle 7 (ramp,
  bounce, Crew) and cycle 8 (bot) by C1. The bot plays any deck through its current
  search (C14).
- No "card to the right gets permanent reduced cost": it moves to cycle 7's bounce deck
  (C11).
- No duplicate cards in a deck (C3), no deck builder, no more than one deck per theme.
- No card-list reader in the picker (C16); the tile shows name and theme only.
- No change to the bot's search width or its budget; NSC-74 stays in Backlog (C14).
- No card art, names are working names (C16), no sound, no iOS build (D8).
- No change to rounds, round wins, sudden death, concede, hand cap, deal or draw rules
  except where an effect says so.
- No change to the cursor rules of [[specs/cycle-5-walk-cursor/spec]] R1–R11: every
  move this cycle adds obeys them.

## Actors

- **Ben (seat 0)**: picks decks, stages, commits, answers single and multi-select
  prompts.
- **The greedy bot (seat 1, and seat 0 under autoplay)**: plays either deck through the
  engine's preview; receives the deck the picker or the flag names.
- **The engine**: owns the card pool, the decks, the controller of every card, the
  mult arithmetic, the destroyed piles, the new effects and the log.
- **The board and the picker**: the picker is a new scene shown before the board; the
  board plays the new events, faces and prompts.
- **The orchestrator**: runs `make check`, re-pins the golden, drives the Godot MCP.

## Requirements (EARS)

### The card pool and decks (C3, C5, C17)

- R1. The engine shall load a card pool in which each card has an id, a name, a cost, a
  flat value, at most one bonus and at most one effect; a bonus is either a multiplier
  from {×1.25, ×1.5, ×2} or an addition from {+1, +2} (C6).
- R2. The engine shall load a deck list in which each deck has an id, a name, a one-line
  theme and exactly 20 distinct card ids that exist in the pool; the Phase 3 cost mix
  is not enforced (C3).
- R3. If the pool or the deck list is malformed, holds an unknown bonus value, a flat
  outside 0..cost+4 (C13), an unknown trigger or verb, a deck of other than 20 cards, a
  repeated id in a deck or an id absent from the pool, then the engine shall report a
  load failure and refuse to start a match.
- R4. The pool shall hold the Ruin and Drift decks' 40 cards as the plan's tables give
  them (C7); the 20 DC-05 cards shall be kept only as a test fixture that is not in the
  deck list (C5).
- R5. When a match is created, each seat shall be given one deck by id; both seats may
  take the same deck.
- R6. When no deck is named for a seat, the engine shall draw that seat's deck from the
  deck list with a value derived from the match seed, so the same seed always pairs the
  same decks (C15).
- R7. The action log shall record both seats' deck ids with the seed, and a replay shall
  rebuild the same decks; the log shall carry a new format and rules version, and a log
  of a previous version shall fail replay with a version mismatch (cycle 1 R34).
- R8. A card instance shall keep its origin (the seat whose deck it came from, which fixes
  its definition) for the whole match, and shall be controlled by whichever seat's hand,
  row or pile holds it; a card scores for its controller (C12).
- R9. When a round starts, every card shall return to its origin's deck for the shuffle
  (Phase 3 R3), whatever seat controlled it.

### The multiplier (C2, C6)

- R10. When a walk starts, each seat's running mult shall be ×1.00.
- R11. When a card is pulsed and scored, the engine shall first multiply its seat's mult
  by the card's effective ×-part, then add the card's effective +-part to the mult, then
  add the card's effective flat times the mult, rounded down to a whole number, to the
  seat's score, and shall emit the ×-part, the +-part, the new mult and the amount added.
- R12. The mult shall be kept to a precision of one hundredth and shall be identical on
  every platform for the same log, so replay holds (D4).
- R13. A card's effective bonus shall be its printed bonus, as changed by effects on that
  instance (a copy, a temporary +-part, a neighbour's ×-part, the "no bonus" mark), with
  every ×-part multiplied together and every +-part added together.
- R14. The DC-05 "opponent's next revealed card has 0 bonus" effect shall now give that
  card no bonus (×1.00, +0) for the round; it stays in the fixture only.
- R15. The DC-05 switch effect shall be retired: no card in the pool or the fixture uses
  it, and the "Switch" prompt label goes with it (C20).

### Destroyed piles and recovery (C8, C12)

- R16. Each seat shall have a destroyed pile; when a turn ends and destroyed cards leave
  their rows (DC-06 R18), each shall go to its owner's destroyed pile instead of the burn
  pile.
- R17. When a round ends, each destroyed pile shall empty into the burn pile.
- R18. The count of each destroyed pile shall be public; the identity of a card that was
  destroyed unrevealed shall be known only to the seat that controlled it until it is
  recovered.
- R19. When the recover effect fires, the engine shall prompt its owner with every card
  in both destroyed piles, chosen by pile and position; the chosen card shall go to the
  prompting seat's hand (burned at the cap, cycle 1 R12) with printed stats and no marks.
- R20. A recovered card shall be playable, shall sit on and score for its new controller's
  row, and a return-to-hand effect shall send it to its controller's hand.
- R21. A card destroyed in the current turn shall not be eligible for recovery until the
  turn ends and it reaches the pile.

### Prompts: the multi-select (C4)

- R22. When an effect asks for any number of targets, the engine shall emit a multi-select
  prompt naming the zone and the eligible positions and shall await a set choice from the
  prompted seat, a set of zero or more distinct eligible positions.
- R23. If a set choice repeats a position, names one that is not eligible, comes from the
  wrong seat or arrives with no multi-select prompt open, then the engine shall reject it
  with a failure code, leaving state and log unchanged.
- R24. When a set choice is accepted, the engine shall log the set, apply the effect for
  that set (an empty set declines and fizzles) and resume the walk.
- R25. When a multi-select prompt has no eligible position, the engine shall fizzle the
  effect without a prompt; it shall prompt even when exactly one position is eligible,
  since zero is a legal answer.

### New triggers and effects (C7, C10, C11)

- R26. The engine shall support two new triggers: "on opponent score" (fires for a
  revealed, live card each time a card controlled by the other seat scores) and "on
  moved" (fires for a revealed, live card each time an effect changes its slot).
- R27. The engine shall implement the Ruin effects of the plan's table: discard a card
  from hand (prompt; empty hand fizzles); destroy your leftmost other card; destroy
  another card of yours then draw (prompt); destroy another card of yours then gain its
  effective flat (prompt); destroy any number of your cards to destroy that many live
  opponent cards at random (multi-select; fewer live opponent cards than chosen destroys
  them all); flat +1 on each opponent score and, the moment its effective flat is 5 or
  more by any cause, destroy itself and a random live opponent card (C10); ongoing: if
  this card would be destroyed, un-reveal it instead (C9); recover a destroyed card
  (R19); draw a card whenever an opponent card reveals; destroy a random opponent card
  (DC-05 verb).
- R28. The engine shall implement the Drift effects of the plan's table: swap places with
  a card on your row (DC-05 verb); move to the far left of your row; move to the far
  right; copy a revealed live opponent card's current flat and bonus as this card's new
  base (prompt); ongoing: the cards on either side of this one get ×1.25; ongoing: while
  on the far left of its row this card has ×1.5; move an opponent card to the far left
  of its row (prompt); move each of your other cards one slot left, the leftmost to the
  far right; reverse the order of the opponent's row; swap an opponent card with the card
  to its right (prompt, rightmost excluded); on moved: this card gains +2 until the walk
  ends (C11).
- R29. When an effect moves cards, every moved card shall follow DC-06 R5–R11: a card
  landing behind its row's cursor is not pulsed again this walk, one landing ahead is
  pulsed when reached, and the card on the pulsed slot after the reveal stage scores there.
- R30. When the un-reveal replacement fires, the card shall become unrevealed in its slot,
  not destroyed, with its stat changes reset to printed (C9); a later pulse of that slot
  shall reveal it in full again (its on-reveal, the no-bonus spend, the opponent's
  watchers); the card shall still count toward "destroy that many of the opponent's".
- R31. The un-reveal replacement shall protect only the card that carries it; other cards
  its controller has on the row are destroyed normally (C18).
- R32. Every destroy this cycle adds shall mark the card destroyed in place as DC-06 R12
  says, and every self-destroy shall count the card for the effect even when R30
  replaces it.
- R33. A temporary +-part granted "until the walk ends" shall end when the walk ends and
  shall not survive to the next turn.
- R34. The bonus copied by the copy effect shall be the target's effective bonus and flat
  at that moment, stored as the copier's new base; later changes to the target shall not
  follow.
- R35. Every random pick this cycle adds shall come from the engine's seeded stream, and
  a preview shall take the policy's pick without touching the stream (DC-05 R35).

### Bot (C14)

- R36. The bot shall play any deck with its current search; "bonus first" shall order a
  set by +-part descending, then ×-part descending, then flat descending; "flat first"
  is unchanged.
- R37. The bot shall answer a multi-select prompt by previewing, for each k from 0 to the
  number of eligible positions, the set of the k eligible cards with the lowest effective
  flat, and choosing the best own-minus-opponent score, ties by its seed.
- R38. The bot shall never return an action the engine rejects, and its choice shall
  depend only on its seed and its view; the slowest decision shall be measured per deck
  pairing at verification and posted to NSC-74 (no change to the budget).

### The picker (C16)

- R39. When the game starts with no deck flag and without autoplay, the player shall see
  a picker before the board: a "You" column and a "Bot" column, one tile per deck in the
  deck list showing its name and theme, and a Start button.
- R40. The picker shall preselect each column with the seed's own pairing (R6), and Start
  shall be enabled only while both columns have a pick.
- R41. When Start is pressed, the board shall begin a match with the picked decks and the
  seed the board would have used.
- R42. When `--deck=<id>`, `--bot-deck=<id>` or `--autoplay` is given, the picker shall
  not be shown; a named deck is used for that seat and an unnamed seat takes the seed's
  pairing (R6). An unknown deck id shall stop the launch with an error in the log.
- R43. Rematch shall keep the picked decks; the pause menu and the result panel shall
  gain a "Decks" button that ends the match (as Concede does when one is running) and
  returns to the picker.

### Board: faces, chips, piles and prompts

- R44. Each card face shall show its bonus as "×1.25"-style or "+1"-style text, nothing
  when it has none; an effect that changes the bonus or flat shall update and pulse the
  label (DC-05 R42).
- R45. The "×M" chip and the row tally shall show the mult to two decimals (for example
  "×1.56"); a card with no effective ×-part and no +-part shall show only "+N".
- R46. Each side's HUD shall show the count of that side's destroyed pile.
- R47. While a recover prompt is open for the player, the board shall lay the eligible
  destroyed cards out in a temporary strip above the rows, own cards face up and the
  opponent's unrevealed-destroyed cards as backs, glowing as eligible; the DC-06 reader
  and action button apply with the label "Recover"; the strip shall clear when the choice
  is accepted (C19). This strip is the precedent for choosing from any off-screen
  collection in later cycles (Ben, C19).
- R48. While a multi-select prompt is open for the player, a tap on an eligible card shall
  lift it to the reader with a "Select" button (or "Deselect" when it is already in the
  set); a selected card shall stay raised and glow brighter; the HUD shall show one
  confirm button reading "Destroy N" with N the current set size, enabled at 0; pressing
  it shall submit the set.
- R49. The action-button labels shall extend to the new prompts: "Discard", "Destroy",
  "Copy", "Move", "Swap", "Recover", "Select"/"Deselect".
- R50. When a card un-reveals, the board shall flip it face down in its slot and clear its
  shown stat changes; when a card is moved by any new effect, the board shall slide it
  (and every other card the effect moved) to its new slot before the walk continues.
- R51. When a destroyed card leaves at turn end, the board shall fly it off the exit side
  as DC-06 R29 does; the pile count then changes.
- R52. If the next step would move, flip, un-reveal, remove or restat the held card, then
  the board shall put it down first (DC-06 R37 extended).

### Unchanged and gate

- R53. The boot log shall still carry `Engine smoke:` then `Main ready`, and the autoplay
  board shall print `Board: match ended …` with the fields of cycle 2 R5 plus the two
  deck ids; the seed-1 values are re-pinned by the orchestrator at verification.
- R54. Every DC-05 and DC-06 requirement stays in force except: DC-05 R1–R3 (card data,
  replaced by R1–R4), R9's mirror deal (R5–R9), R14's integer mult (R10–R13), R20's
  switch and bonus-0 readings (R14, R15), R30's zones (extended by R19 and R22), R36's
  orders (R36), R41's bonus number (R44), R50–R52 (DC-06) chips' "×M" integer (R45),
  DC-06 R18's burn pile (R16), R41's label set (R49); Phase 3 R6's single deck and cost
  mix are amended (Planning amendments).

## Clarifications (Ben, 2026-11-04)

| # | Question | Decision |
|---|---|---|
| C1 | Round 1 Q1: how to cut the request | 1a: three specs. This cycle: the mult rebalance, decks as data, the picker, the destruction and movement decks, the bot untuned. Cycle 7: ramp, bounce, Crew. Cycle 8: per-deck bot tuning |
| C2 | Round 1 Q2: the mult arithmetic | 2a: the running mult in hundredths as an integer; a ×-bonus multiplies it (×1.25 → ×125/100, rounded to the nearest hundredth), a +bonus adds whole units; each card adds floor(flat × mult); chips read "×1.25" / "+1" (R10–R12) |
| C3 | Round 1 Q3: deck shape | 3a: a deck is 20 distinct card ids from one pool; the loader checks 20, unique and known, not the cost mix; both seats may pick the same deck; Phase 3 R6 amended (R2, R5) |
| C4 | Round 1 Q4: the picker | 4a: a pre-match screen with a "You" and a "Bot" column, Start, Rematch keeps picks, `--deck=` / `--bot-deck=` flags; narrowed by C16 (R39–R43) |
| C5 | Round 2 Q1: the existing 20 cards | 1c, Ben: "some of the cards are useful inspiration, but were primarily there for us to test the UI." They stay as a test-only fixture, not a pickable deck (R4) |
| C6 | Round 2 Q2: bonus kinds and scale | 2a: flat plus at most one bonus, ×1.25 / ×1.5 / ×2 or +1 / +2; mult starts ×1.00; about half the cards ×1.25, a few ×1.5, at most one ×2 per deck, one or two +1, +2 only as an effect payoff; "0 bonus" becomes "no bonus" (R1, R13, R14) |
| C7 | Round 2 Q3: table design latitude | 3a: the interrogator writes the full tables in the plan, Ben's ten as signature cards, five to seven more per deck from the same primitives, the rest vanilla with the old curve as a guideline; Ben strikes or changes rows at sign-off (R4, R27, R28) |
| C8 | Round 2 Q4: "destroy any amount of your cards" | 4a: a multi-select prompt; tap lifts with "Select", a selected card stays raised, "Destroy N" confirms and "Destroy 0" declines; the log records the set; the bot previews the k lowest-flat own cards for each k (R22–R25, R37, R48) |
| C9 | Round 3 Q2: the un-reveal replacement | 2b: the card flips face down in its slot, not destroyed or revealed, keeps its slot, its stat changes reset to printed; a later pulse reveals it in full again; it still counts toward "destroy that many" (R30) |
| C10 | Round 3 Q4: the on-opponent-score card | 4a: a new trigger; each opponent score gives +1 flat while the card is revealed; at effective flat 5 or more by any cause it destroys itself and a random live opponent card; base flat 1 at cost 2 (R26, R27). The round-3 phrase "keeps its 5 flat" under protection is superseded by C9's reset |
| C11 | Round 3 Q3: three movement rulings | 3a: the cost-reduction card moves to cycle 7's bounce deck and "move an enemy card to the far left" takes its place; "on swap" fires on any move of the card and gives +2 until the walk ends; the neighbour card gives ×1.25 to each side (R28, R33) |
| C12 | Round 3 Q1: the destroyed pile and recovery | 1b: a destroyed pile per seat, and the prompt offers either seat's pile; a stolen card scores for its new controller, which adds the origin/controller distinction (R8, R16–R21) |
| C13 | Round 4 Q1: over-curve bodies | 1a: the loader cap becomes flat 0..cost+4; vanilla rows stay within cost+2 as a guideline (R3) |
| C14 | Round 4 Q2: the bot across decks | 2a: "bonus first" = +-part, then ×-part, then flat; no new order, no per-deck hint; the multi-destroy by the k-lowest-flat rule; NSC-74 re-measured per pairing (R36–R38) |
| C15 | Round 4 Q3: the golden and the sweep | 3c: a seeded pairing per seed when no flag names a deck; the golden is seed 1 under its own pairing (R6, R53) |
| C16 | Round 4 Q4: picker flow and names | 4b: the picker as proposed but without the card-list reader; working names "Ruin" (destruction) and "Drift" (movement); flags or autoplay skip the picker; "Decks" buttons in the pause and result menus (R39–R43) |
| C18 | Round 5 Q1: the un-reveal's scope | 1a, Ben: "however a one-time-use card that does this for the entire board would be good, or maybe as a Crew power". Only the carrier is protected (R31); the board-wide one-shot is recorded as a cycle 7 idea (Open items) |
| C19 | Round 5 Q2: recovering from an off-screen pile | 2a, Ben: "this should set a precedent for viewing and selecting from off-screen decks/collections". HUD counts plus a temporary strip during the prompt (R46, R47) |
| C20 | Round 5 Q3: the switch card | 3a: the verb and its label are retired; fixture c13 becomes vanilla (R15) |
| C21 | At sign-off, Ben asked whether cycle 8 (bot tuning) could be specced and run alongside this cycle; the orchestrator advised against it since T02, T03 and T08 rewrite `GreedyBot`; Ben: "Nevermind, proceed with 6". The set is approved as written; cycle 8 follows cycle 7 |
| C17 | Defaults stated in rounds 3 and 4, no objection | "Power" means flat; the copy takes the target's current flat and bonus as the copier's base (R34); a reverse moves every card on the row under the DC-06 cursor rules (R29); a discard with an empty hand fizzles and the card still scores; a card keeps its origin and gains a controller, a recovered card goes to the recovering seat's hand and plays for it, a return sends it to its controller's hand, round start returns every card to its origin deck (R8, R9, R20); faces show "×1.25" / "+1" and the tally the mult to two decimals (R44, R45) |

## Scenarios

- **Given** a row [flat 4 ×1.25, flat 2 +1, flat 3], **when** it walks from ×1.00,
  **then** the mult goes ×1.25 → ×2.25 → ×2.25 and the score 5 → 9 → 15 (floor of 4×1.25
  = 5, 2×2.25 = 4, 3×2.25 = 6) and the chips read "×1.25", "×2.25", "+6".
- **Given** seat 0 picks Ruin and seat 1 Drift, **when** the match is logged and
  replayed, **then** the replay rebuilds both decks and an equal state; a log of rules
  version 3 fails with a version mismatch.
- **Given** seed 1 with no flags, **when** the picker opens, **then** both columns are
  preselected with the seed's pairing and Start is enabled.
- **Given** the sacrifice card flips with four own live cards, **then** a multi-select
  prompt opens; **when** Ben selects two and presses "Destroy 2", **then** two of his cards
  are marked destroyed and two random live opponent cards are too; **when** he presses
  "Destroy 0", **then** the effect fizzles.
- **Given** one of the two chosen cards carries the un-reveal ongoing, **then** it flips
  face down in its slot with printed stats instead, and the opponent still loses two.
- **Given** the burst card at flat 1 on seat 0's row, **when** four opponent cards score,
  **then** its flat reads 5 and it is destroyed with one random live opponent card.
- **Given** seat 1 destroyed seat 0's card face down last turn, **when** seat 0's
  recover card flips, **then** the prompt offers both piles, the opponent's unrevealed one
  as a back; **when** Ben recovers an opponent card, **then** it enters his hand with its
  real identity, he can play it and it scores for him; **when** the round ends, **then**
  it is back in seat 1's deck.
- **Given** the reverse card flips while the opponent's row [A, B, C] has cursor 2 (A, B
  scored), **then** the row becomes [C, B, A]: C on slot 0 and B on slot 1 are behind the
  cursor and do not score again, A on slot 2 scores again when reached (DC-06 R5–R7).
- **Given** the on-moved card is swapped forward, **then** it gains +2 until the walk ends
  and scores with it when the cursor reaches its new slot; next turn it has no +2.
- **Given** the neighbour card revealed at slot 1, **then** the cards at slots 0 and 2
  score with an extra ×1.25 while it is revealed and live.
- **Given** `--deck=drift --bot-deck=ruin --autoplay`, **when** the game boots, **then**
  no picker shows and the board prints `Board: match ended … decks=drift/ruin`.
- **Given** 50 seeds, **when** each plays bot vs bot under its seeded pairing, **then**
  every match ends, no view or prompt leaks a hidden id (destroyed piles included), every
  log replays, and the slowest decision per pairing is recorded.

## Data touched

- New: `godot/engine/data/decks.json`, the Ruin and Drift tables in the pool, a test
  fixture file for the DC-05 cards under `godot/tests/`, a picker scene under
  `godot/picker/` (or `godot/board/`), new engine suites, this spec set.
- Changed: `godot/engine/data/cards.json` (format 3), `card_def.gd`, `card_effect.gd`,
  `card_db.gd`, `card_state.gd`, `match_rules.gd`, `match_state.gd`, `match_engine.gd`,
  `score_walk.gd`, `effect_resolver.gd`, `choice.gd`, `preview_policy.gd`,
  `engine_action.gd`, `engine_error.gd`, `legal_plays.gd`, `seat_view.gd`,
  `match_event.gd`, `action_log.gd`, `bot/greedy_bot.gd`; `godot/main.gd`, `main.tscn`,
  `godot/board/*` (faces, chips, tally, HUD, prompt rules and host, effect player,
  match driver, board steps); every suite that reads a bonus or the fixture;
  `docs/specs/specs-moc.md`; `docs/planning/cycles.md` and
  `docs/planning/phase-3-game-loop.md` at `/cycle test`.
- Read only: `godot/input/*`, `scripts/*` (the boot grep keeps `Main ready`).
- Never: `godot/addons/*`, `godot/art/*`, `docs/.obsidian/`, `.env`, `godot/.godot/`,
  `godot/reports/`, the archive.

## Open items for later cycles

- A one-time-use card or Crew power that un-reveals every card you control instead of
  letting them be destroyed (Ben, C18) → cycle 7's Crew spec.
- The recover strip (R47) is the pattern for viewing and selecting from any off-screen
  collection: deck, burn pile, destroyed pile (Ben, C19).
- "The card to the right gets permanent reduced cost" → cycle 7's bounce deck (C11).

## Planning amendments

This cycle amends Phase 3 R6 ("one fixed 20-card deck used by both players", with the
cost mix) to "each seat plays a 20-card constructed deck chosen from the deck list; the
cost mix is a design guideline" (C3), and DC-05 C2's integer mult to the hundredths mult
with two bonus kinds (C2, C6). The orchestrator may append both to
[[planning/phase-3-game-loop]] at `/cycle test`, and should note cycles 7 and 8 in
[[planning/cycles]] as the planned follow-ons (C1).

## Definition of done

- [ ] Every requirement R1–R54 is covered by a named gdUnit4 case, the boot log, the
      autoplay line or a step of the MCP verification.
- [ ] `make check` is green; the test stage stays under 15 s.
- [ ] The seed-1 golden (under its seeded pairing) is re-pinned in `test_full_match.gd`,
      the boot expectation if it checks values, and the cycles log; the autoplay board
      prints the same line.
- [ ] The 50-seed sweep replays every log under seeded pairings; the slowest decision per
      pairing is posted to NSC-74.
- [ ] Ben has reviewed the Ruin and Drift tables (C7).
- [ ] Three screenshots: the picker with both columns picked; a multi-select prompt with
      two cards selected and "Destroy 2" showing; a face reading "×1.25" with a "×1.56"
      tally beside its row.
- [ ] Constitution Check passes (see plan).
- [x] Spec, plan and tasks signed off by Ben (2026-11-04); committed before implementation begins.
