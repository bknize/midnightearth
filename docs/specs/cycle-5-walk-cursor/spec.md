---
type: spec
tags: [spec, cycle-5-walk-cursor, engine, board]
status: approved
related: ["[[specs/cycle-5-walk-cursor/plan]]", "[[specs/cycle-5-walk-cursor/tasks]]", "[[specs/cycle-4-card-effects/spec]]", "[[specs/cycle-3-board-feedback/spec]]", "[[planning/phase-3-game-loop]]", "[[planning/phase-1-tech-stack]]", "[[planning/cycles]]"]
created: 2026-11-04
updated: 2026-11-04
uid: 7d2789fb-7ac5-4a11-9226-2e4b6d7bf00a
supersedes:
---

# Spec: Cycle 5 — the walk cursor

**Slug:** `cycle-5-walk-cursor`  ·  **Change type:** engine + scene  ·  **Status:** approved (Ben, 2026-11-04, five rounds after five answers settled in the `/spec` conversation; signed off 2026-11-04)  ·  **Runs as:** milestone `DC-06 walk-cursor`

Cycle 5 amends the DC-05 walk ([[specs/cycle-4-card-effects/spec]] R11–R23). The cursor
becomes a position on each row rather than a set of cards already pulsed, so a swap changes
the order in which cards score: a card swapped behind the cursor is not scored or revealed
this turn, and a card swapped in front of it scores again. Destroy becomes a card state: a
destroyed card keeps its slot, reveals when the cursor reaches it, scores nothing, and is
discarded at the end of the turn. On the board, a destroyed card dims, tilts and cracks in
place; scoring gets Balatro-style chips above the card, a running tally beside each row,
and a tally that flies into the HUD score at turn end; and a prompt's eligible card lifts
to the reader view with an action button before it is chosen.

## Intent

After cycle 5, Ben can swap a card forward with c12 and watch it score twice, swap a card
behind the cursor and see it skipped for the turn, see a destroyed card lie cracked in its
slot until the turn ends, read "×M" and "+N" chips rise from each card as it scores while a
tally by his row climbs, and watch that tally fly into his score at turn end; the bot's
preview follows the same cursor, and every match still replays from its log.

## Non-goals

- No new card, no change to the 20-card table, no second deck.
- No change to prompt eligibility or zones beyond C9, and no reader-with-button outside a
  prompt (staging stays a drag, C22); no change to the bot's search (B-09 stays in
  Backlog; its number is re-measured, C16).
- No art generation inside the cycle (D3): the cracked overlay is a procedural placeholder
  behind one texture slot; a later `/art` run replaces it (C13).
- No cursor ring on the table (DC-05 C9 stands).
- No iOS build (D8), no sound, no foil.
- No change to rounds, round wins, sudden death, concede, hand cap, deal or draw.
- No change to the action log's format: the same actions, a new rules version (R24).

## Actors

- **Ben (seat 0)**: commits, answers c12's prompt, reads the chips and the tally.
- **The greedy bot (seat 1, and seat 0 under autoplay)**: previews through the same cursor.
- **The engine**: owns the cursor, the destroyed state, the turn-end discard and the log.
- **The board**: plays pulses in the engine's slot order, the destroyed look, the chips,
  the tally and the turn-end count.
- **The orchestrator**: runs `make check`, re-pins the golden line, measures the bot and
  drives the Godot MCP at verification.

## Requirements (EARS)

### The cursor (replaces DC-05 R12 and R16; C1, C6)

- R1. During a walk, the engine shall keep one cursor per row: the number of that row's
  slots the walk has passed, 0 for both rows when the walk starts.
- R2. When the cursor pulses a slot, that slot shall count as passed from the start of the
  pulse, before any effect fired by that pulse resolves.
- R3. During a walk, the cursor shall pulse the first unpassed slot of the turn's first
  committer's row, then the first unpassed slot of the second committer's row, alternating
  slot by slot; when one row has no unpassed slot left, the other row's remaining slots
  shall be pulsed in order; when neither has one, the walk shall end.
- R4. A walk shall pulse every slot of both rows exactly once, so the number of pulses in a
  walk equals the number of slots on both rows when the walk starts.
- R5. A pulse's reveal stage shall belong to the card occupying the slot when the pulse
  starts; its score stage shall belong to the card occupying that slot once the reveal
  stage's effects have resolved (C23, amended 2026-11-04). When that card is not the one
  that revealed and is unrevealed, it shall first reveal in full (bonus-0 spend, its
  on-reveal effect, the opponent's on-reveal watchers) and then score (C24); when it has
  already scored in this walk, it shall score again as R9 says (C25); when it is destroyed,
  it shall flip if face down and score nothing (R13, R14).
- R6. When an effect moves a card to a slot of its row the cursor has not passed, the
  cursor shall pulse that card again when it reaches that slot.
- R7. When an effect moves a card to a slot of its row the cursor has passed, the cursor
  shall not pulse that card again in this walk.
- R8. While a card moved behind the cursor is unrevealed, it shall stay unrevealed until a
  later walk's cursor reaches it: no reveal, no on-reveal effect and no bonus-0 spend this
  turn.
- R9. When a card already scored in this walk is pulsed again, the engine shall not emit a
  reveal, shall add the card's effective bonus to its seat's multiplier again, shall add
  its effective flat times that multiplier to the seat's score again, and shall fire its
  on-score effect again.
- R10. When a swap moves two cards, R5–R8 shall apply to each card separately.
- R11. When an effect fired by a pulse moves the pulsed card off its slot, the moved card
  shall not score in that pulse: it shall score when the cursor reaches its new slot if that
  slot is unpassed (R6), and not in this walk if it is passed (R7) (C23, amended
  2026-11-04; the card that landed on the pulsed slot scores in its place, R5).

### Destroyed cards (replaces DC-05 R23; C5, C7–C9, C11)

- R12. When a card is destroyed, the engine shall mark it destroyed and leave it in its
  slot, face up or face down as it stands; the row's slot count shall not change.
- R13. While a card is destroyed, the engine shall not score it, shall not fire its
  on-score effect and shall emit no score event for it.
- R14. When the cursor pulses an unrevealed destroyed card, the engine shall reveal it and
  nothing more: no on-reveal effect, no bonus-0 spend (the mark waits for the seat's next
  live reveal) and no on-opponent-reveal watcher.
- R15. While a card is destroyed, none of its effects shall fire by any trigger; a destroyed
  energy-carry card shall carry nothing at turn end.
- R16. While a card is destroyed, it shall be an eligible target of the swap and shall not
  be an eligible target of the switch, the return or the random destroy.
- R17. If the opponent's row holds no card that is not destroyed, then the random destroy
  shall fizzle and shall draw nothing from the seeded stream.
- R18. When a turn ends, every destroyed card shall leave its row for its owner's burn pile
  after the return marks resolve and before energy settles, and the engine shall emit that
  it left, with its slot.
- R19. When a destroyed card carries a return mark at turn end, it shall be discarded, not
  returned.
- R20. When a face-down card is destroyed, the opponent's view and events shall show the
  seat and the slot and shall not show the card's identity; the card shall stay face down
  until the cursor reaches it.
- R21. If a destroyed card is still unrevealed when it leaves at turn end, then the event of
  its leaving shall hide its identity from the opponent.
- R22. The destroyed mark shall be part of the full state, shall replay, and shall end when
  the card leaves the board.

### Preview, bot, log

- R23. The pure preview shall run the same cursor and destroyed rules as the live walk; the
  opponent's face-down cards shall count as slots that score nothing rather than as absent,
  so slot positions match the live row (amends DC-05 R35's "count as absent").
- R24. The engine shall raise its rules version; a log of the previous rules version shall
  fail replay with a version mismatch (cycle 1 R34). The log format shall not change.
- R25. The bot shall still never return an action the engine rejects, and its slowest
  decision over the 50-seed sweep shall be measured and recorded at verification (B-09 is
  not changed by this cycle).

### Board: the destroyed look (C10, C13)

- R26. When a card is destroyed, the board shall mark it in place in the destroy step:
  dimmed, tilted askew in its slot and stamped with a cracked overlay; a face-down card
  shall show the same treatment on its back.
- R27. The cracked overlay shall be drawn in-house this cycle behind one texture slot, so a
  later approved image from `godot/art/` replaces it without a code change, and shall be
  Compatibility-clean (D2).
- R28. When the cursor pulses a destroyed card, the board shall flip it if face down with
  the reveal beat and shall not lift it, show a chip or change a tally.
- R29. When the turn ends, the board shall fly every destroyed card off the exit side, face
  up or face down as it stands (the DC-05 destroy fly-out, moved to turn end).
- R30. The board shall pulse cards in the engine's slot order, including a second pulse of a
  card already pulsed this walk, and shall not pulse a card the engine did not pulse.

### Board: chips, tally and the HUD (C14, C15, C17)

- R31. When a card scores, the board shall show above it, in two beats, a "×M" chip (M the
  seat's new multiplier) when the card's effective bonus is not 0, then a "+N" chip (N the
  points the pulse added), each rising and fading; a card with bonus 0 shall show only
  "+N".
- R32. During a walk, each side shall show a running tally beside its row: the walk's score
  so far and the seat's multiplier, updated at each of that side's pulses.
- R33. While a walk runs, each side's HUD score shall hold the previous turn's total (0 at
  the start of a round) and shall not show the walk's running number or multiplier.
- R34. When the turn ends, each side's tally shall fly into that side's HUD score, the HUD
  score shall count from the held total to the turn's total, and the tally shall clear.
- R35. While a prompt pauses the walk, the chips, the tally and the HUD shall hold their
  last values (this closes B-08).
- R36. Under autoplay, chip, tally and count durations shall divide by the speed like every
  other step.
- R37. If the next step would destroy, flip, move, re-pulse or clear the held card, then the
  board shall put it down first (DC-04 R9, DC-05 R54 extended).

### Board: the prompt reader (C19–C22; replaces DC-05 R56's first clause)

- R40. While a prompt is open for the player, a tap on an eligible (glowing) card shall lift
  it to the DC-04 reader view and show one action button, and shall not submit the choice.
- R41. The action button's text shall name the prompt's verb: "Swap" for the swap, "Discard"
  for the draw-then-discard, "Switch" for the switch and "Return" for the return.
- R42. When the action button is pressed, the board shall submit the lifted card as the
  choice and put it down; the DC-05 R57 clearing follows.
- R43. While an eligible card is lifted, a tap on it, on the table or Escape shall put it
  down with the prompt still waiting and the button hidden; a tap on another eligible card
  shall lift that card instead.
- R44. While a prompt is open, a tap on a non-eligible face-up card shall lift it to read
  with no action button, as DC-05 R56 and C16 already allow.
- R45. When the player lifts one of the player's own face-down cards during a prompt, the
  reader view shall show its face and shall flip it back face down when it is put down.
- R46. When the player lifts an opponent's face-down card, the reader view shall show its
  back and shall not reveal the face.
- R47. The action button shall be hidden whenever no eligible card is lifted, and shall not
  exist outside a prompt; staging a hand card stays a drag.

### Unchanged and gate

- R38. The boot log shall still carry `Engine smoke:` then `Main ready`, and the autoplay
  board shall print `Board: match ended …` with the fields of cycle 2 R5; the seed-1 values
  are re-pinned by the orchestrator at verification.
- R39. Every DC-05 requirement stays in force except: R12 and R16 (the cursor, replaced by
  R1–R11), R23 (destroy, replaced by R12–R22), R35's "count as absent" (amended by R23),
  R50–R52 (the HUD during a walk, replaced by R31–R35), R53's destroy clause (the sweep-off
  moves to turn end, R29), R56's first clause (a tap on a glowing card submits; replaced by
  R40–R47) and R59's pinned values (R38).

## Clarifications (Ben, 2026-11-04)

C1–C5 were settled in the `/spec` conversation before the interview; C6–C17 in four
rounds; C19–C22 in a fifth round after Ben added the prompt reader at sign-off; C18 is the
defaults stated in rounds 2 and 4 with no objection.

| # | Question | Decision |
|---|---|---|
| C1 | Ben's request | In his words: "Swap positions changes the order in which the cards are scored. If you swap a card behind where the cursor already scored, then that card does not get scored or revealed this turn. Likewise, if you swap an already-scored card in front of the cursor, it gets scored again" |
| C2 | c12 swaps with a card that has already scored; it lands on c12's slot, the one being pulsed. Behind or in front? | "Behind. The cursor scored this slot already to initiate the swap, so the newly-swapped card does not score on this slot." (R11) Superseded by C23 (2026-11-04). |
| C3 | c12 swaps forward: score now and again, or only at the new slot? | "Now and again. The swap effect is only on reveal so no other ability fires." (R5, R6) Superseded by C23 (2026-11-04). |
| C4 | A card scoring a second time: on-score again or points only? | "On-score triggers again" (R9) |
| C5 | A face-down card swapped behind the cursor: hidden until a later turn? | "Yes, next turn it will reveal as normal" (R8) |
| C6 | Destroying a card left of the cursor shifts the row | "A 'destroyed' card is a state. It doesn't score or trigger score-events, it DOES reveal, and at the end of the turn it's discarded from the board." Replaces DC-05 R23 (R12–R22) |
| C7 | Round 1 Q1: what c12's running pulse does once c12 has moved | 1a: the pulse belongs to c12 and completes wherever it landed; the slot counts as passed; forward scores again, behind does not (R2, R5–R7) Superseded by C23 (2026-11-04). |
| C8 | Round 1 Q2: what else happens at a destroyed card's flip | 2a: nothing; inert beyond the flip: no on-reveal, no bonus-0 spend, no watcher, no energy carry (R14, R15) |
| C9 | Round 1 Q3: can a destroyed card be targeted | 3a: only by the swap; switch, return and random destroy skip it; destroy fizzles with no live card (R16, R17) |
| C10 | Round 1 Q4: which pile at turn end | 4a: the burn pile, no new pile (R18) |
| C11 | Round 2 Q1: the board's destroyed look | Ben: "all three: dimmed, askew, and stamped with a sort of shattered/cracked graphic" (R26) |
| C12 | Round 2 Q2: hidden information for a destroyed face-down card | 2a: the destroy keeps the identity hidden; the card stays face down and the cursor's flip is the public reveal; never flipped, it leaves at turn end still hidden (R20, R21) |
| C13 | Round 2 Q3 and Round 3 Q1: scope and the crack art | Ben: "big overhaul. Let's add an animation above a card as it pulses, showing the new score and bonus like balatro. Then, at the end of the round, that gets added to the round total with another animation"; then 1a: a procedural crack placeholder behind one texture slot, the real overlay through `/art` later, outside the cycle (R27) |
| C14 | Round 3 Q2: the chip's content | 2a: Balatro-style, "×M" chip when the bonus is non-zero, then "+N"; a destroyed card's flip shows nothing (R31, R28) |
| C15 | Round 3 Q3: when and how the tally runs | "a and c", resolved by C17: a running tally by each row during the walk, flying into the HUD score at turn end with a count (R32, R34) |
| C16 | Round 3 Q4: B-09 | 4a: out; stays in Backlog; verification measures the slowest decision again and records it (R25) |
| C17 | Round 4: the HUD number while the walk runs | 1a: holds the previous turn's total until the tally flies in, then counts to the new total; the live number lives in the row tally only; B-08 closes with this cycle (R33–R35) |
| C19 | Ben's addition after the first sign-off request | In his words: "When selecting a card, for instance, tapping the card should zoom it in like the typical reader view, with an additional action button. This lets players read the card before selecting it. The action button's text should change based on the action. 'Swap', 'Discard', etc." (R40–R47) |
| C20 | Round 5 Q1 and Q2: the tap flow and the button | 1a: a tap on a glowing card lifts it with one action button; the button submits; a tap on the card, the table or Escape puts it down; another glowing card swaps the lift; non-eligible face-up cards lift with no button. 2a: a HUD button under the lifted card, plain Theme, labels "Swap", "Discard", "Switch", "Return"; the banner keeps the rules text (R40–R44, R47) |
| C21 | Round 5 Q3: a face-down card in the reader during a prompt | 3a, with Ben's caveat: "In the case of selecting an enemy's card, it will not flip over and show the face." Own face-down cards show their face and flip back on put-down; an opponent's stay a back (R45, R46) |
| C22 | Round 5 Q4: scope of the reader-with-button | 4a: prompts only this cycle; staging a hand card stays a drag (R47) |
| C23 | After T08, Ben reconsidered C2, C3 and C7 | In his words: "This change cements 'reveal' as an event before 'scoring'. Therefore, a swap which happens BEFORE scoring, should score the fresh card now and the original card later." The score stage of a pulse belongs to the slot: the card on it once the reveal stage's effects resolve scores. The moved card scores later if it landed ahead, not this walk if behind (R5, R11). Built by reopening cycle-5 T01 (T01) and re-dispatching the engine agent (3a) |
| C24 | The card landing on the pulsed slot is face down | 1a: it reveals in full now (bonus-0 spend, its on-reveal, the opponent's watchers), then scores (R5) |
| C25 | The card landing on the pulsed slot already scored this walk | 2a: it scores again now, with `again` (R5, R9). A destroyed card landing there flips if face down and scores nothing (orchestrator default, existing rule R13) |
| C18 | Defaults stated in rounds 2 and 4, no objection | A return-marked destroyed card is discarded, not returned (R19); the random destroy picks only among live cards (R17); the preview treats the opponent's face-down cards as inert slots rather than removing them (R23); the HUD's "×mult" readout leaves the HUD for the tally and the chips (R33) |

## Scenarios

- **Given** seat 0's row [A, B, C] with the cursor at slot 1 (A scored), **when** c12 at
  slot 1 flips and swaps with A, **then** A, now on slot 1, scores again in this pulse
  (`again`), c12 on slot 0 does not score this walk, and the cursor pulses C next (C23,
  C25).
- **Given** the same row with C face down, **when** c12 at slot 1 swaps with C, **then** C,
  now on slot 1, reveals in full and scores in this pulse, and c12 scores once when the
  cursor reaches slot 2 (C23, C24).
- **Given** c06 (on-score flat-up) swapped forward, **when** it scores twice in one walk,
  **then** its flat is base + 2 and the second pulse used base + 1 (C4).
- **Given** a face-down card swapped behind the cursor, **then** it stays face down this
  turn with no reveal event, and next turn's walk flips it in slot order (C5).
- **Given** a destroyed c05 (energy carry) on seat 1's row, **when** the turn ends, **then**
  seat 1 carries nothing, the card leaves for the burn pile after the return marks resolve,
  and the row is one shorter next turn (C6, C8).
- **Given** c19 destroys a face-down card at slot 2, **then** the opponent's view shows slot
  2 destroyed with no identity; **when** the cursor reaches slot 2, **then** the card flips
  (public) and no on-reveal, bonus-0 spend or score follows (C8, C12).
- **Given** c12 flips with a destroyed card and two live cards on its row, **then** the
  prompt names all three; **given** c13 (switch) flips, **then** its targets exclude the
  destroyed card (C9).
- **Given** seat 1's row holds only destroyed cards, **when** c19 flips for seat 0, **then**
  it fizzles and the stream is untouched (C9).
- **Given** both rows hold n and m slots at walk start, **then** the walk emits exactly
  n + m pulses whatever swaps and destroys happen (R4).
- **Given** a preview mid-walk with an opponent card face down at slot 0, **then** the
  preview's walk still pulses the opponent's slots in live order and scores nothing for
  that slot (R23).
- **Given** a DC-05 log (rules 2), **when** replayed, **then** the replay fails with a
  version mismatch (R24).
- **Given** a card scores with bonus 1 on multiplier 1, **then** a "×2" chip rises first,
  then "+N", and the row tally reads the new score and ×2; the HUD still shows the previous
  total (R31–R33).
- **Given** the walk ends, **then** each tally flies into its HUD score, the HUD counts to
  the turn's total, and the tally clears (R34).
- **Given** c12's prompt pauses the walk before c12 scores, **then** no chip shows for c12,
  the tally and HUD hold, and the walk's values resume after the choice (R35).
- **Given** c12's prompt is open with three glowing cards, **when** Ben taps one, **then**
  it lifts to the reader view and a "Swap" button appears and nothing is submitted;
  **when** he taps another glowing card, **then** that one is lifted instead; **when** he
  presses "Swap", **then** the choice is submitted, the card goes down and the walk
  resumes (R40–R43).
- **Given** a prompt is open, **when** Ben lifts one of his own face-down cards, **then** he
  sees its face, and it flips back down on put-down; **when** he lifts an opponent's
  face-down card, **then** he sees its back (R45, R46).
- **Given** 50 seeds, **when** each plays bot vs bot, **then** every match ends, no view or
  event leaks a hidden id (destroyed face-down cards included), every log replays to an
  equal state, and the slowest decision is recorded (R25).

## Data touched

- Changed: `godot/engine/score_walk.gd`, `match_state.gd` (`WalkState`, `CardState`
  destroyed flag), `card_state.gd`, `effect_resolver.gd`, `choice.gd`, `match_engine.gd`
  (preview hiding, turn end), `preview_policy.gd`, `seat_view.gd`, `match_event.gd`,
  `match_rules.gd` (rules version 3); `godot/board/board_steps.gd`, `board_step.gd`,
  `board.gd`, `board_card.gd`, `board_card.tscn`, `effect_player.gd`, `score_tracker.gd`,
  `board_hud.gd`, `board_hud.tscn`, `lift_rules.gd`, `prompt_rules.gd`, `prompt_host.gd`,
  `prompt_tap.gd`, `card_lift.gd`; `godot/tests/test_score_walk.gd`,
  `test_effects.gd`, `test_choices.gd`, `test_seat_view.gd`, `test_greedy_bot.gd`,
  `test_action_log.gd`, `test_full_match.gd` (golden re-pin), `test_board_steps.gd`,
  `test_score_tracker.gd`, `test_lift_rules.gd`, `test_prompt_rules.gd`;
  `docs/specs/specs-moc.md`;
  `docs/planning/cycles.md` at `/cycle test`.
- New: a `ScoreChips`/tally scene under `godot/board/`, the crack placeholder material or
  mesh, this spec set.
- Read only: `godot/engine/data/cards.json`, `godot/input/*`, `scripts/*`,
  `docs/planning/*`.
- Never: `godot/addons/*`, `godot/art/*` (no approved image this cycle), `docs/.obsidian/`,
  `.env`, `godot/.godot/`, `godot/reports/`, the archive.

## Planning amendments

This cycle amends DC-05's walk (R12, R16, R23 replaced) and its HUD (R50–R52). Phase 3's
planning note needs no change: the walk and the burn pile are as recorded there. The
orchestrator may append the new cursor rule to [[planning/phase-3-game-loop]] at
`/cycle test` beside the DC-05 amendments.

## Definition of done

- [ ] Every requirement R1–R47 is covered by a named gdUnit4 case, the boot log, the
      autoplay line or a step of the MCP verification.
- [ ] `make check` is green; the test stage stays under 15 s.
- [ ] The seed-1 golden line is re-pinned in `test_full_match.gd`, `scripts/check.sh`'s
      boot expectation if it checks the values, and the cycles log; the autoplay board
      prints the same line.
- [ ] The 50-seed sweep replays every log; the slowest bot decision and the longest walk
      are recorded for B-09.
- [ ] Three screenshots: a destroyed card lying dimmed, askew and cracked on a row with the
      row tally visible; the chips above a scoring card; an eligible card lifted during
      c12's prompt with the "Swap" button.
- [ ] B-08 is closed by the orchestrator when the cycle merges, citing R33–R35.
- [ ] Constitution Check passes (see plan).
- [x] Spec, plan and tasks signed off by Ben (2026-11-04); committed before implementation begins.
