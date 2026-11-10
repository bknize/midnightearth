---
type: spec
tags: [spec, cycle-8-ramp-bounce-crew, engine, board, cards]
status: approved
related: ["[[specs/cycle-8-ramp-bounce-crew/plan]]", "[[specs/cycle-8-ramp-bounce-crew/tasks]]", "[[specs/cycle-6-constructed-decks/spec]]", "[[specs/cycle-7-bot-players/spec]]", "[[specs/cycle-5-walk-cursor/spec]]", "[[specs/cycle-4-card-effects/spec]]", "[[planning/phase-3-game-loop]]", "[[planning/phase-1-tech-stack]]", "[[planning/cycles]]"]
created: 2026-11-04
updated: 2026-11-09
uid: 919b9406-6aea-4411-95d3-dac408f59245
supersedes:
---

# Spec: Cycle 8 — ramp, bounce, Crew

**Slug:** `cycle-8-ramp-bounce-crew`  ·  **Change type:** engine + scene (cards data, engine verbs and triggers, Crew as a new engine concept, board UI for Crew and the optional-trigger decline, bot)  ·  **Status:** approved (Ben, 2026-11-04, three rounds, C1–C11; signed off 2026-11-04: "Looks good"; reconciled with DC-08 as merged and re-approved, C12: "1a")  ·  **Runs as:** two milestones, A as DC-09 then B as DC-11 (cycle 7 milestone B is DC-10 between them, C12)

Cycle 8 finishes the four-deck set Ben asked for at cycle 6 and adds Crew. **Milestone A**
ships **Bloom**, a ramp deck whose cards grow for the rest of the match (bonuses that
survive the round, the hand and even a recovery by the other seat), and **Echo**, a bounce
deck that replays its reveals (cards that return to hand or flip face down at turn end,
cards that remember their reveals, the "card to the right costs less" effect from cycle 6
C11, and a watcher for your own reveals). Under both sits one new engine idea: a card's
stats are board-specific unless an ability says otherwise, and an ability may give a card
instance **memory** that persists across zones and rounds within a match (stat deltas, a
cost reduction, a use countdown). **Milestone B** adds **Crew**: three persistent, public
abilities per deck, Balatro-Joker-like, with no raw power or bonus of their own, their own
triggers (turn start, round end, your card destroyed, moved or returned, ongoing), optional
triggers the player may decline through a new UI, and limited uses shown as a countdown.
The board-wide one-shot un-reveal of cycle 6 C18 ships as a Crew power.

## Intent

After milestone A, Ben picks Bloom against Echo, watches a Sapling read "×1.50" then
"×1.75" over two turns and still read "×1.75" in his hand next round, sees an Echo card flip
face down at turn end and re-fire its reveal next turn, pays 2 for a card printed at 3, and
every match still replays from its log. After milestone B, three Crew stand beside each row
with their uses counted, a Crew prompt opens before he stages on turn 4 and he can press
Skip, and the bot plays every deck and Crew without a rejected action.

## Non-goals

- No Crew picker, no Crew flags, no deck builder: Crew is deck data (Ben, C4). The picker
  tile keeps name and theme only (cycle 6 C16).
- No new deck beyond Bloom and Echo; no duplicate cards in a deck (cycle 6 C3); no card art,
  names are working names; no sound; no iOS build (D8).
- No energy refund on any bounce; no activated (button-pressed) Crew ability: every Crew
  ability is triggered, and the player's only input is the optional prompt's choice or Skip.
- No change to the bot's search or budget beyond what the new prompts and costs need; the
  tuned bot of [[specs/cycle-7-bot-players/spec]] stays the shipped bot and its stamp and
  rerun rule (cycle 7 R33–R36) apply to this cycle's data changes.
- No change to rounds, round wins, sudden death, concede, hand cap, deal or draw rules except
  where an ability says so; no change to the cursor rules of [[specs/cycle-5-walk-cursor/spec]]
  R1–R11.
- No per-deck bot tuning: it is a `make bot-train` run under cycle 7's provision, not work here.

## Actors

- **Ben (seat 0)**: picks decks, stages, commits, answers prompts, declines optional ones,
  reads Crew.
- **The shipped bot (seat 1, and seat 0 under autoplay)**: cycle 7's tuned bot through the
  registry; plays any deck and Crew.
- **The engine**: owns card memory, the new triggers and verbs, Crew, optional prompts, the
  turn-start pause and the log.
- **The board**: shows grown stats and costs on every face, the Crew line, the Skip button,
  and plays the new events.
- **The orchestrator**: runs `make check` and `make bot-eval`, re-pins the golden, drives the
  Godot MCP, runs cycle 7's rerun provision.

## Requirements (EARS)

Requirements R1–R38 are milestone A; R39–R70 are milestone B; R71–R74 are both.

### Card memory: the persistence rule (C3)

- R1. A card's stat changes shall be board-specific: they shall end when the card leaves its
  row or the round ends, as cycles 4–6 fixed, unless the ability that made them says it
  persists.
- R2. The engine shall keep, per card instance, a memory of what persisting abilities gave
  it: a flat delta, a ×-part delta in hundredths, a +-part delta, a cost reduction and the
  uses left of its limited ability; the memory shall survive round start, the hand, the deck,
  the burn and destroyed piles, a return to hand, an un-reveal and a recovery by the other
  seat, and shall be cleared only when a match is created.
- R3. A card's effective stats shall be its base (printed, or a copy's stored base) plus its
  memory deltas, then the board-specific changes of cycle 6 R13 (positional ×-parts,
  `flat_delta`, `temp_plus`, the no-bonus mark); a ×-part delta adds to the ×-part in
  hundredths (a printed ×1.25 grown twice by +0.25 reads ×1.75; a card with no ×-bonus grown
  once reads ×1.25), and the no-bonus mark still makes the shown bonus ×1.00 and +0 for the
  round without erasing the memory.
- R4. A card's effective cost shall be its printed cost less its cost reduction, never below
  0; every budget check (a commit's legality, the free first card, the bot's enumeration, the
  board's staging) shall use the effective cost.
- R5. Memory growth shall be in fixed steps named by the ability (+1 or +2 flat, +0.25 or
  +0.5 to the ×-part, +1 to the +-part, −1 or −2 cost) with no cap other than cost 0; the
  loader's flat cap (cycle 6 R3) applies to printed values only.
- R6. When an ability with a limited number of uses fires, the engine shall count down that
  card's uses in its memory and shall not fire it again once none is left; the uses shall be
  public wherever the card is public.
- R7. Every face a seat may see (its own hand, both rows, the recover strip) shall show the
  card's effective flat, bonus and cost, and shall mark a card whose memory is not empty so
  the player can tell a grown card from a printed one.
- R8. The memory shall be part of the full state, shall replay from the log, and shall
  travel hidden with a hidden card: a change to a card in a hand shall reach only that hand's
  seat, and the other seat's view shall never learn a hidden card's identity from its memory.

### The pool and the decks (C7 of cycle 6 applies)

- R9. The pool shall gain the Bloom and Echo decks' 40 cards as the plan's tables give them,
  with the new verbs and the new trigger below; the pool format shall carry an optional
  `uses` count on an effect (absent or 0 means unlimited).
- R10. The deck list shall gain `bloom` and `echo`; the seeded pairing of cycle 6 R6 shall
  draw from all four decks, so the seed-1 golden is re-pinned.
- R11. If the pool names a `uses` that is not a whole number, a grow amount that is not one
  of the fixed steps, or a verb on a trigger the plan does not allow, then the engine shall
  report a load failure and refuse to start a match (cycle 6 R3 extended).

### Bloom: growth (C3, C9)

- R12. The engine shall implement the Bloom growth verbs of the plan's table: this card gains
  a step of flat, ×-part or +-part for the match whenever it scores; once per match, when it
  scores, ×+0.5 (R6); on reveal, another card of yours on the row gains a step (prompt); on
  reveal, each card in your hand gains a step; on reveal, a chosen card in your hand gains a
  step (prompt); on reveal, each other card on your row gains a step.
- R13. A growth verb shall reach cards on your row and in your hand only, never cards still
  in the deck (C9); a target set with no card shall fizzle; a growth on a hand card shall
  show at once on that hand's faces.
- R14. A grown card returned to its origin's deck at round start, drawn again, played again
  or recovered by the other seat shall carry its growth, and shall score with it for
  whichever seat controls it.

### Echo: bounce and replay (C5)

- R15. The engine shall support a new trigger, "on ally reveal": it fires for a revealed,
  live card each time another card controlled by the same seat is revealed, in row order as
  snapshotted when the first is due, with the same pause-and-resume rules as "on opponent
  reveal" (cycle 4 R19, cycle 6 R26).
- R16. The engine shall implement the Echo verbs of the plan's table: this card returns to
  its controller's hand at the end of the turn (printed, no prompt); another card of yours
  returns to your hand at the end of the turn (prompt); an enemy card returns to its
  controller's hand at the end of the turn (prompt, revealed live cards only); at the end of
  the turn this card flips face down (ongoing); on reveal this card gains +1 flat for the
  match (the growth verb on an on-reveal trigger); on reveal the card to the right of this
  one on your row costs 1 less for the match (fizzles when none); on reveal this card costs
  less for the match; the first time this card reveals each match, draw 2 (R6); whenever
  another card of yours reveals, this card gains +1 flat for the round; whenever another
  card of yours reveals, draw a card; next turn your first card is free (the DC-05 verb).
- R17. A return at turn end shall follow cycle 4 R24–R25 and cycle 6 R20: the card leaves the
  row when the turn ends (never mid-walk), goes to its controller's hand, is burned at the
  cap, loses its board-specific changes and keeps its memory; a destroyed card marked to
  return is cleared instead (cycle 5 R19).
- R18. When the turn ends, after the returns and the destroyed clear, every revealed live
  card carrying the turn-end flip shall un-reveal in its slot as cycle 6 R30 says (board
  changes reset, memory kept); it reveals in full again when the next walk's cursor reaches
  it, its on-reveal and the watchers firing again, and it counts as a card that flipped face
  down for Crew that watch for it (R51).
- R19. The rows shall shrink only at turn end (cycle 5 P1 holds): no verb this cycle removes a
  card from a row during a walk.

### Prompts and eligibility

- R20. The new prompt verbs shall choose from these zones: another card of yours to grow,
  own row, live cards but the source; a hand card to grow, own hand, every position; another
  card of yours to return, own row, live cards but the source; an enemy card to return,
  opponent row, revealed live cards; every one follows cycle 4 R28–R34 (fizzle on none,
  auto-choose on one, log the choice).

### Bot (cycle 7 R1–R9 apply)

- R21. The shipped bot shall enumerate its candidates and value its energy with effective
  costs (R4), so a card whose cost was reduced is affordable to it exactly when the engine
  accepts it; the frozen reference bot of cycle 7 R21 shall stay unedited and keep reading
  printed costs, which never exceed the effective ones, so its commits stay legal and its
  pinned choices hold.
- R22. The shipped bot shall answer the new single-target prompts by preview, as cycle 7 R9
  says, except a hand-growth prompt, which it shall answer by rule (the hand card with the
  highest effective flat, ties by position) since a hand card never scores in a preview.
- R23. The bot shall never return an action the engine rejects, and its choice shall depend
  only on its seed and its view (cycle 7 R2, R3).

### Board (milestone A)

- R24. Each face in the player's hand shall show the card's effective cost, flat and bonus
  and shall refresh when a hand card's memory changes (R13); the staging rules shall read the
  effective cost, so a card printed at 3 and reduced to 2 stages on a budget of 2.
- R25. A card whose memory is not empty shall carry a visible mark on its face (R7), wherever
  it is shown, including the recover strip.
- R26. When a card's memory changes by an ability, the board shall update and pulse the
  label as cycle 4 R42 does; a change to a hand card shall play on the hand's face.
- R27. When a card returns to a hand at turn end, the board shall play the existing return;
  when a card flips face down at turn end (R18), the board shall play the existing un-reveal
  flip in its slot; the player's own face-down card still lifts face up to read (cycle 5).
- R28. If the next step would move, flip, un-reveal, remove or restat the held card, the board
  shall put it down first (cycle 6 R52 holds).

### Milestone A gate

- R29. The action log shall carry a new rules version; a log of rules version 4 shall fail
  replay with a version mismatch; the log format is unchanged in A.
- R30. The boot log shall still carry `Engine smoke:` then `Main ready`, and the autoplay
  board shall print `Board: match ended …` with the fields of cycle 7 R56; the seed-1 values
  are re-pinned under the four-deck pairing.
- R31. The 50-seed sweep shall run under seeded pairings over all four decks, every log
  shall replay, no view or event shall leak a hidden id (memory included), and the
  99th-percentile bot decision shall stay under cycle 7's 10 ms with the slowest printed,
  as cycle 7 R17 reads since its C14.
- R32. Because the pool and the deck list change, `/cycle test` of milestone A shall run
  cycle 7's rerun provision (R36 there) with what exists at that point: `make check` prints
  `stamp=MISMATCH`, `make bot-eval` (the shipped bot against `greedy_v1`, non-regression)
  must pass; since `make bot-train` arrives only with cycle 7 milestone B (after this
  milestone, C2) and the shipped weights are the untrained defaults, the orchestrator shall
  re-stamp the committed weights file by hand with the new stamp, unchanged otherwise, and
  record a ledger row saying so (C12); no training is run in this cycle.
- R33. The gdUnit stage shall stay under 30 s of gdUnit run time, the budget cycle 7 C15 set;
  this spec does not change it (C8 as restated in C12).
- R34–R38. Reserved (no requirement; numbering kept stable for the plan).

### Crew: data and presence (milestone B; C4, C6)

- R39. The engine shall load a Crew pool in which each Crew has an id, a name, a trigger, a
  verb, an amount, an optional flag, a uses count and a scope ("round", "match" or none) and
  rules text; a Crew has no cost, flat or bonus.
- R40. Each deck in the deck list shall name exactly three distinct Crew ids that exist in
  the pool; a Crew may serve more than one deck; the Crew pool shall hold the eight Crew of
  the plan's table (C6).
- R41. If the Crew pool is malformed, names an unknown trigger or verb, or a deck names other
  than three distinct known Crew, then the engine shall report a load failure and refuse to
  start a match.
- R42. When a match starts, each seat shall hold its deck's three Crew for the whole match;
  both seats' Crew shall be public (in the match-started event and in every view), and Crew
  shall not be cards: never on a row, never a target, never destroyed, moved, returned or
  copied.
- R43. The engine shall keep, per seat and Crew, the uses left of a limited Crew ability;
  "once per round" shall reset at round start, "once per match" never; the counts shall be
  public and part of the full state.
- R44. A Crew ability shall give no raw power or bonus of its own: every Crew effect acts on
  cards, hands, draws or reveals (Ben).

### Crew triggers and abilities (C2, C6, C7)

- R45. The engine shall fire Crew abilities on these triggers: turn start (after the turn's
  draws, before any commit), round end (after the last turn's end, before the round's winner
  is decided), your card destroyed (after the effect that destroyed it has resolved, for each
  card of yours it destroyed, in row order), your card moved (after the move, for each moved
  card of yours), your card returned or flipped face down (when a card of yours leaves a row
  for your hand or un-reveals by an ability), and ongoing (read by the walk, never fired).
- R46. A Crew ability that fires inside a walk shall fire after the effect that caused it
  has fully resolved, never inside it, so an effect's count ("destroy that many") is settled
  before any Crew acts; a Crew prompt pauses the pulse as a watcher's prompt does and the
  pulse resumes after the answer.
- R47. The engine shall implement the eight Crew of the plan's table: Quartermaster (draw 2
  extra on the first turn of each round); Tallyman (ongoing: your cards with an even
  effective flat, 0 included, get ×1.25 when they score); Shade (at the start of turn 4, you
  may flip one revealed card of yours face down; optional); Salvager (once per round, when a
  card of yours is destroyed, you may discard a card from your hand so the destroyed card
  returns to your hand at the end of the turn instead of going to your pile; optional);
  Veil (once per match, when a card of yours is destroyed, you may flip every revealed card
  you control face down instead, none of them destroyed, their board changes reset; the
  destroyed card still counts for the effect that destroyed it; optional, the cycle 6 C18
  one-shot, C7); Navigator (whenever a card of yours is moved, it gets +1 flat for the
  round); Gardener (when a round ends, each card on your row gains +1 flat for the match);
  Lookout (whenever a card of yours returns to your hand or flips face down by an ability,
  draw a card).
- R48. Where a Crew ability needs a target and the eligible set is empty, the Crew shall not
  fire and its uses shall not count down; where it is not optional and exactly one target is
  eligible, it shall choose it without a prompt.
- R49. When an optional Crew ability fires with at least one eligible target, the engine
  shall open an optional prompt for its seat even when exactly one target is eligible (a
  decline is always a legal answer), and the uses shall count down only when the prompt is
  answered with a choice, not a decline.
- R50. When Veil is accepted, the engine shall un-mark the destroyed card and un-reveal it and
  every other revealed card of that seat's row (cycle 6 R30 for each), and shall count Veil's
  single use; a Veil never accepted stays available.
- R51. When Salvager is accepted, the chosen hand card shall be discarded at once and the
  destroyed card shall leave its row at turn end for the chooser's hand (burned at the cap)
  instead of the destroyed pile, with no board-specific change and its memory kept.

### Optional prompts and the decline (C5)

- R52. The engine shall mark a prompt optional when its ability says so and shall accept a
  decline action from the prompted seat while an optional prompt is open; a decline shall be
  logged like a choice, shall close the prompt without applying the ability, and shall resume
  the walk or the turn start where it paused.
- R53. If a decline arrives with no prompt open, from the wrong seat, or on a prompt that is
  not optional, then the engine shall reject it with a failure code, leaving state and log
  unchanged.
- R54. A Crew prompt that opens at turn start shall pause the turn before any commit: the
  engine shall await the prompted seat's choice or decline, shall reject commits meanwhile,
  and shall then await the first committer as usual.
- R55. The log format shall rise for the decline action; a log of the previous format shall
  fail replay with a format mismatch; the rules version shall rise again for milestone B.

### Bot (milestone B)

- R56. The shipped bot shall answer an optional prompt inside a walk by previewing each
  option and the decline, choosing the best own-minus-opponent score, ties by its seed.
- R57. The shipped bot shall answer a turn-start Crew prompt by a fixed rule, since no walk
  can be previewed: for Shade, the revealed card of its own with an on-reveal effect and the
  highest effective flat, else decline.
- R58. The stamp of cycle 7 R33 shall cover the Crew pool file as well as the card pool and
  deck list, on the engine side and the script side alike, so a Crew change re-runs the bot
  provision; the frozen-fixture pin of the stamp (DC-08 T11) shall gain a Crew fixture and
  be re-pinned, and the shipped data shall stay unpinned so a data change keeps the gate
  green.

### Board (milestone B; C5)

- R59. Each side's three Crew shall stand face up in a short line beside that side's row
  (the player's bottom-left next to the hand, the opponent's top-left), readable at table
  distance (name and rules text), for the whole match.
- R60. A Crew with a limited ability shall show a badge with its uses left ("2 left"), which
  updates when a use is spent and reads "spent" with the Crew dimmed when none is left; a
  per-round Crew's badge resets at round start.
- R61. When a Crew ability fires, the board shall lift and settle that Crew as it does a
  card whose effect fires, before the ability's own steps play.
- R62. A tap on a Crew shall lift it to read and a second tap or a table tap shall put it
  down, as a face-up card lifts outside a prompt; a Crew cannot be dragged.
- R63. While an optional prompt is open for the player, the board shall show the prompt as
  any other (banner, glows, dimmer, the reader and its action button) plus one "Skip" button
  where the multi-select's confirm button sits; pressing Skip shall submit the decline.
- R64. While a Crew prompt is open at turn start, the board shall show it before the player
  can stage, with Commit disabled and the hand not draggable, and shall restore staging when
  the prompt closes.
- R65. When Veil flips a row face down, the board shall play one un-reveal flip per card as
  cycle 6 R50 does; when Salvager returns a card at turn end, the board shall play the return
  from the row (not the fly-off) and the pile count shall not rise for it.
- R66. The prompt banner for a Crew prompt shall read the Crew's rules text and name the Crew.
- R67–R70. Reserved.

### Both milestones

- R71. Every DC-05, DC-06 and DC-07 requirement stays in force except: cycle 6 R1 (a card's
  effect gains `uses`, R9), R3 (extended by R11, R41), R13 (extended by R3), R26 (one more
  trigger, R15), cycle 4 R9/R10 and cycle 6 R36 where they read a printed cost (R4, R21),
  cycle 4 R28/R29 for optional prompts (R49, R52), cycle 5 R18 for a salvaged card (R51), and
  cycle 6's "no change to the bot's search" where the new prompts need an answer (R21–R23,
  R56–R57). Cycle 7's requirements apply to the shipped bot throughout.
- R72. Every random outcome this cycle adds shall come from the engine's seeded stream and a
  preview shall never touch it (cycle 6 R35); the new verbs add no random pick.
- R73. Every new event shall be redacted as the plan's event table says, and the sweep's leak
  scan shall cover memory on hidden cards and Crew prompts.
- R74. The orchestrator shall verify each milestone with `make check` green, the re-pinned
  golden, the sweep line and the screenshots the tasks name.

## Clarifications (Ben, 2026-11-04)

| # | Question | Decision |
|---|---|---|
| C1 | Round 1 Q1: how to cut the work | 1a: one spec, two milestones; A = the ramp and bounce decks with the memory machinery and the cost reduction; B = Crew with the decline UI, finite abilities and the one-shot un-reveal. Each is its own cycle branch |
| C2 | Round 1 Q2: sequencing against cycle 7 | 2a: `/cycle plan` for milestone A waits until cycle 7 milestone A (DC-08) merges to `master`, and this cycle runs before cycle 7 milestone B, so the overnight training happens once on four decks and Crew; the bot work targets cycle 7's `BotRegistry` / `TunedBot` / `CandidateGen` |
| C3 | Round 1 Q3: what a permanent buff is | 3a, with Ben's rule: "changes to cards should normally not persist, so persistent stat changes are, itself, an ability. Limited-use abilities ALSO persist, as a countdown. The general rule is that card stats are board-specific unless otherwise noted, but we need design space for cards to have persistent memory between zones and rounds when design calls for it." Memory per instance, additive fixed steps, no cap but cost 0 (R1–R8) |
| C4 | Round 1 Q4: how a seat gets its Crew | 4c, Ben: "Crew is a deck construction decision and we don't have a deckbuilder yet. Let's say each preconstructed deck gets 3 crew members for now." No Crew picker, no flags; three Crew per deck in the deck list (R40, R42) |
| C5 | Round 2 Q1: Crew on the table and the decline UI | 1a: three face-up Crew in a line beside each row with a uses badge; a Crew lifts when it fires and lifts to read; an optional prompt adds a "Skip" button where the confirm sits, submitting a logged `decline`; a turn-start Crew prompt opens before staging (R52–R54, R59–R64) |
| C6 | Round 2 Q2: the Crew pool | 2a: eight Crew, Ben's five plus three (a movement Crew for Drift, a growth Crew for Bloom, a reveal Crew for Echo); each deck lists three with sharing (R40, R47) |
| C7 | Round 2 Q3: the cycle 6 C18 one-shot | 3a: a Crew power (Veil), once per match, optional: flip every revealed card you control face down instead; none destroyed; the destroyed card still counts (R47, R50) |
| C8 | Round 3 Q1: the gdUnit budget | 1a: raised to 20 s of gdUnit run time with the sweep kept in `make check`. Superseded on reconciliation (C12): cycle 7 C15 had already set 30 s (gdUnit ran about 26 s at DC-08), so this spec keeps 30 s and lowers nothing (R33) |
| C9 | Round 3 Q2: per-instance countdowns on cards | 2a: one or two cards in the new decks use them (Oak, Messenger), so the machinery is proven on cards and Crew (R6, R12, R16) |
| C10 | Round 3 Q3: where ramp growth reaches | 3a: a card on your row (itself or another) or cards in your hand (one chosen, or all), never the deck; hand faces refresh at once (R13, R24) |
| C12 | Reconciliation with DC-08 as merged (2026-11-04), Ben 1a: "reconcile with DC-08 before /exercise" | The notes are aligned with cycle 7 milestone A as shipped (merged as fbb0d38; this branch re-based onto it): the 30 s gdUnit budget (C15 there) replaces C8's 20 s (R33); the sweep's latency check is the 99th percentile (R31); `make bot-train` does not exist until cycle 7 milestone B, so milestone A's rerun provision is `make bot-eval` plus a hand re-stamp of the untrained default weights with a ledger row (R32); `BotStamp`, `CandidateGen`, `TunedBot`, `GreedyBot` and `Evaluator` exist and are extended, never created, the frozen `greedy_v1` is not edited (R21); the golden is DC-08's `GOLDEN_TUNED` line and the stamp pin lives on frozen fixtures (R58); milestone numbering decided by Ben in the change list (1a): this spec's milestone A takes DC-09, cycle 7 milestone B becomes DC-10 and this spec's milestone B DC-11; the orchestrator amends the DC-08 cycles row and the ledger sentence at our `/cycle plan`. Change list approved by Ben 2026-11-04 ("1a") |
| C11 | Round 2 Q4 and the round 3 defaults, no objection | The bounce toolkit of R16 with the enemy bounce; working names Bloom and Echo; rules version 5 in A and 6 in B, log format 4 in B; Crew are not cards; a memory travels hidden with a hidden card; the bot previews an optional prompt's options plus the decline and answers a turn-start Crew prompt by rule (R42, R55–R57) |
| C13 | DC-11 T13 review (2026-11-05) | Ben 1a: fix the three should-fixes (Veil on an own destroyed card keeps the board's destroyed look, R65; the Crew queue fires in destroy order rather than row order, R45; Salvager at the hand cap emits a pile-less clear and a slotless burn instead of a row burn, R51, R65) and the `board_steps` pile-count nit; record the `CrewPool.fires` replay nit as a follow-up. Ben 2c: with live Crew the matrix bot measured p99 10.43 and 10.46 ms (at k 6, k_opp 3, samples 2, rm_iterations 50), so it is exempt from the 10 ms budget (cycle 7 R17) until the training run (cycle 7 T16); the tuned bot, the shipped opponent, keeps the budget (p99 9.47 ms). Rejected: k 5 (2a), one sample (2b) |

## Scenarios

- **Given** Sapling (flat 1, no bonus) on seat 0's row, **when** it scores on turns 3, 4 and
  5, **then** its face reads ×1.25, ×1.50, ×1.75 and the mult grows accordingly; **when** the
  round ends and Sapling is drawn again in round 3, **then** its hand face still reads
  "×1.75" with the grown mark and it scores with it.
- **Given** Rain reveals with four cards in seat 0's hand, **then** each gains +1 flat for the
  match, the four hand faces pulse, and seat 1 sees four hidden-card stat events and no id.
- **Given** Tinker reveals at slot 1 with a card printed at cost 3 on slot 2, **then** that
  card costs 2 for the match; **when** it later returns to hand and is staged on a budget of
  2, **then** the board accepts it and the engine accepts the commit.
- **Given** Echo (ongoing flip) revealed on slot 0, **when** the turn ends, **then** it flips
  face down in its slot with printed board stats; **when** the next walk reaches slot 0,
  **then** it reveals in full again and the opponent's watchers fire again.
- **Given** Messenger reveals for the first time this match, **then** seat 0 draws 2 and its
  uses read 0; **when** it is bounced and reveals again, **then** nothing is drawn.
- **Given** Banish chooses the opponent's Lodestone, **when** the turn ends, **then**
  Lodestone goes to seat 1's hand with printed stats and the neighbours lose their ×1.25.
- **Given** seat 0 plays Ruin with Salvager and Veil, **when** Immolator destroys two of its
  own cards, **then** after the sacrifice resolves Salvager's prompt opens for the first card
  (optional, one "Skip"); **when** Ben discards a hand card, **then** at turn end that card
  returns to his hand and the pile count rises by one, not two; **when** on a later turn a
  Fuse burst destroys his Phoenix-less card, **then** Veil's prompt opens; **when** he
  accepts, **then** every revealed card on his row flips face down, none is destroyed, Veil
  reads "spent".
- **Given** seat 0 plays Echo with Shade, **when** turn 4 starts, **then** before he can stage
  a prompt offers his revealed cards and a Skip button; **when** he picks one, **then** it
  flips face down and Lookout draws him a card; **when** he presses Skip instead, **then**
  nothing changes and the turn begins.
- **Given** a log of rules version 4, **when** it is replayed, **then** the replay fails with a
  version mismatch; **given** a format-3 log under milestone B, **then** a format mismatch.
- **Given** 50 seeds under seeded pairings of four decks, **when** each plays bot vs bot,
  **then** every match ends, every log replays, no hidden id leaks, and the slowest decision
  is under 10 ms.

## Data touched

- New: `godot/engine/data/crew.json` (B), `godot/engine/card_memory.gd`, `crew_def.gd`,
  `crew_pool.gd`, `bloom_effects.gd`, `echo_effects.gd`, `crew_effects.gd` (names in the
  plan), board `crew_line.gd` (B), new suites, this spec set.
- Changed: `godot/engine/data/cards.json` (format 4, +40 cards), `decks.json` (v2: `bloom`,
  `echo`, `crew` lists), `card_effect.gd`, `card_db.gd`, `deck_list.gd`, `match_cards.gd`,
  `match_rules.gd`, `match_state.gd`, `card_state.gd`, `score_walk.gd`,
  `effect_resolver.gd`, `choice.gd`, `legal_plays.gd`, `engine_action.gd`,
  `engine_error.gd`, `action_log.gd`, `match_engine.gd`, `seat_view.gd`, `match_event.gd`,
  `preview_policy.gd`, cycle 7's `bot/candidate_gen.gd`, `tuned_bot.gd`, `greedy_bot.gd`,
  `evaluator.gd` (effective costs), `bot_stamp.gd` and `scripts/bot/records.py` (the Crew
  file in the stamp, B), `bot/data/tuned_weights.json` (re-stamped by hand, R32),
  `tests/fixtures/dc05_cards.json` (format 4), `tests/fixtures/dc05_crew.json` (new, B),
  `tests/test_action_log.gd` and `test_bot_stamp.gd` (version and fixture pins),
  `tests/test_full_match.gd` (`GOLDEN_TUNED`), `docs/planning/bot-ladder.md` (a ledger row
  per milestone); never `bot/reference/greedy_v1_bot.gd` (R21); `godot/board/*`
  (faces, hand faces, steps, prompt host and rules, HUD Skip, Crew line, lift rules, staging
  cost), `main.gd` (smoke), `match_driver.gd` (decline); `docs/specs/specs-moc.md`;
  `docs/planning/cycles.md` (rows) at `/cycle test`.
- Read only: `godot/picker/*` (no change, C4), `godot/input/*`, `scripts/*`.
- Never: `godot/addons/*`, `godot/art/*`, `docs/.obsidian/`, `.env`, `godot/.godot/`,
  `godot/reports/`, the archive.

## Open items for later cycles

- A Crew picker or deck builder once decks are built, not preconstructed (Ben, C4).
- Activated Crew abilities (a button on the Crew) if a design calls for them.
- Per-deck bot tuning as a `make bot-train` run per pairing (cycle 7 open items).
- Memory that persists across matches (a campaign) is out of scope by Ben's request
  ("but not matches").

## Planning amendments

The persistence rule of C3 is a design principle for every later card: the orchestrator may
append it to [[planning/phase-3-game-loop]] at milestone A's `/cycle test` ("card stats are
board-specific unless an ability says otherwise; an ability may give a card instance memory
for the match"). The gdUnit budget stays the 30 s cycle 7 C15 recorded (C12).

## Definition of done

Milestone A
- [x] R1–R33 and R71–R74 each covered by a named gdUnit4 case, the boot log, the sweep line
      or a step of the verification.
- [x] `make check` green, gdUnit under 30 s; the seed-1 golden (`GOLDEN_TUNED`) re-pinned
      under the four-deck pairing; the sweep line clean with `p99_us` under 10 ms and
      `stamp=match` after the re-stamp.
- [x] Cycle 7's rerun provision as R32 restates it: the `make bot-eval` line and the hand
      re-stamp pasted into the cycles row and a ledger row.
- [ ] Ben has reviewed the Bloom and Echo tables (cycle 6 C7). (superseded: the Bloom and Echo decks were replaced by the rules-v2 canon (DC-13, DC-14), DC-20 T19)
- [x] Two screenshots: a hand face with a grown mark and a reduced cost beside the printed
      row card; an Echo card face down in its slot at turn end next to a revealed neighbour.

Milestone B
- [x] R39–R66 covered as above; a format-3 log fails replay.
- [x] `make check` green under 30 s; golden re-pinned if the Crew change it; sweep clean
      (`p99_us` under 10 ms); the stamp covers `crew.json` and the fixture pin is re-pinned.
- [x] Two screenshots: the Crew line with a "1 left" badge and a "spent" Crew; an optional
      prompt with the Skip button beside the glowing eligible cards.
- [x] Constitution Check passes (see plan).
- [x] Spec, plan and tasks signed off by Ben (2026-11-04: "Looks good"); committed before implementation begins.
