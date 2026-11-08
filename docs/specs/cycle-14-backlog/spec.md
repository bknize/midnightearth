---
type: spec
tags: [spec, cycle-14-backlog, engine, board, pvp, trainer, tooling, vault]
status: approved
related: ["[[specs/cycle-14-backlog/plan]]", "[[specs/cycle-14-backlog/tasks]]", "[[planning/phase-1-tech-stack]]", "[[planning/cycles]]", "[[planning/bot-ladder]]", "[[rules/resolution]]", "[[rules/cards-v2]]", "[[rules/crew-v2]]", "[[rules/glossary]]", "[[decisions/0005-match-server-for-pvp]]", "[[specs/cycle-13-bot-trainer-b/spec]]", "[[specs/cycle-12-multiplayer/spec]]", "[[specs/cycle-10-review-tools/spec]]", "[[systems/bot-training]]", "[[specs/specs-moc]]"]
created: 2026-11-08
updated: 2026-11-08
uid: c8aa5fd2-7c20-4eb7-a929-fcf46d9068f3
linear: https://linear.app/night-science-llc/project/cycle-14-backlog-sweep-1f4a4af95173
supersedes:
---

# Spec: Cycle 14 — backlog sweep

**Slug:** `cycle-14-backlog`  ·  **Change type:** mixed (engine rules, board scene, server and
net, trainer, tooling, vault)  ·  **Status:** approved

## Intent

Every Backlog issue left by cycles 3 to 13 is either closed by dev cycle DC-20 or lives
under its own milestone in the one project [Cycle 14 — backlog sweep](https://linear.app/night-science-llc/project/cycle-14-backlog-sweep-1f4a4af95173)
(P-NSC-16), so that every earlier project is complete. Ben (2026-11-08): "For next cycle,
I want to collect all the backlogs, so every other cycle can be closed out as complete."

The cycle settles six rules rulings first, moves the rules version to 9 once, and then
sweeps the player-visible board bugs, the behaviour-preserving cleanups, the PVP server
polish, the trainer items that must land between training nights, the tooling nits and
the stale documents.

## Non-goals

- Training night 2 and 3 (NSC-243), the promotion of a learned policy (NSC-244), the
  linear bot's 10 ms budget (NSC-250) and Ben's router checklist (NSC-248). They stay in
  P-NSC-16 under their own milestone and do not hold DC-20 open.
- The protocol and schema items of NSC-233 (feature names in the hello, `feature_set`
  dropped from the label reply, the `fits.runs` column): they stay in P-NSC-16 for the
  training milestone, because a protocol change between two nights risks a Mac/PC mismatch
  (C10).
- NSC-176 (the random bot's shared seed for same-turn prompts without a source card): closed
  as won't-fix (C7). The shared seed is deterministic and legal.
- New cards, Crew, decks or rules beyond the six rulings below. No art. No iOS build.
- Any change to the card pool, deck list or Crew JSON files: the stamp's hash half stays
  `857b165d5a5d755e`; only the rules prefix moves.

## Actors

- Ben: rules authority (the rulings), sign-off, the two Definition-of-done boxes of
  NSC-252 that need his word.
- A player: sees the board fixes (deck notes, Crew beats, Lantern's free first card, the
  tap path, the abandoned PVP board) and the PVP server's behaviour.
- The engine: carries the rulings, the new events and rules version 9.
- The bots (`random`, `linear`), the match and play-out workers, the trainer on the PC:
  consume the stamp and the rollout determinization.
- The orchestrator: re-pins the golden lines, re-measures rung 0, redeploys the PC server,
  runs the gate, drives the Godot MCP, moves Linear.
- Implementers (`implementer`, `implementer-engine`), the reviewer.

## Requirements (EARS)

### A. Rules rulings (rules version 9)

- R1. When a seat's draw finds the Deck empty and its On empty draw Batch ends because the
  pulse's Budget (trigger) of Q4 is spent, the engine shall still make the denied draw once
  if the Deck is no longer empty, exactly as it does when the Batch ends by resolving
  (NSC-178, C1).
- R2. The engine shall treat the resumed draw of Q11 as a game step, not a trigger: it
  shall not count against the Budget and shall not fizzle as "exhausted".
- R3. When Immolator or Fuse chooses a random opposing card to Condemn, the engine shall
  draw from the whole opposing row, as today, and a pick that lands on a card that cannot
  be Condemned (Bastion's protection) or that already holds the Condemned mark shall be a
  visible miss: the engine shall emit a fizzle for that pick whose reason names the
  protection or the existing mark, and the pick shall still consume its RNG draw (NSC-181,
  C2).
- R4. While a Level is read on either row, the engine shall level only the revealed cards of
  a row: a face-down card on that row shall keep its own Power until it is revealed, and
  from its reveal shall be levelled like any revealed card (NSC-183, C3).
- R5. The engine shall read the lowest Power for Level among the revealed cards only, as
  today; R4 changes which cards receive the levelled Power, not which cards supply it.
- R6. When a card ability or a Crew with a `uses` count above 0 fires, the engine shall count
  that ability's uses down by one for the scope its data names, and once none is left shall
  not fire it again within that scope (NSC-182, C4; cycle 8 R6 and R43 made good).
- R7. If an ability's `uses` is 0 or absent, then the engine shall treat it as unlimited, as
  today, so no shipped card or Crew changes behaviour.
- R8. The engine shall give every created card an Owner at the moment it is created (the
  seat whose hand or row it is created in), and shall never file a card in a Pile by a
  fallback seat (NSC-175, C6).
- R9. The card format shall let a created card carry a lifetime of either `until_piled`
  (the default when absent) or `match`; the format version shall not change and the shipped
  card pool file shall not be edited (C9).
- R10. When a created card with lifetime `until_piled` would be sent to a Pile, the engine
  shall remove it from the Match instead (it enters no Pile, no Deck and no hand again) and
  shall emit one public event naming the Owner, the card, where it came from and the reason
  (C9: Ben, "most of them will disappear when they're sent to the pile").
- R11. When a created card with lifetime `match` would be sent to a Pile, the engine shall
  file it in its Owner's Pile like any card.
- R12. The engine shall set `RULES_VERSION` to 9, so the stamp becomes `r9-857b165d5a5d755e`
  and a rules-8 action log is refused at replay rather than replayed under the new rules
  (C9, reversing C8).

### B. Events and hidden information

- R13. When a Crew's ability fires, the engine shall emit a public `CREW_FIRED` event
  carrying the seat, the Crew slot, the Crew id, the moment, the verb and the uses left
  (unlimited shown as such), in addition to the `TRIGGER_FIRED` it emits today (NSC-187,
  C5).
- R14. When a Crew changes a card's stats, the engine shall emit that `STATS_CHANGED` with the
  same cost clamp, key order and `cause` as a card ability's stats change (NSC-184).
- R15. While a card sits in a pending face-down Commit, the engine shall route every private
  event about it (including a Crew's `STATS_CHANGED`) to the committing seat only, never to
  the opponent (NSC-249).
- R16. When a seat's Turn starts with a free first card (Lantern), the engine shall say so in
  the `TURN_STARTED` event, so a viewer can learn it without reading the SeatView (NSC-186).
- R17. The engine shall not change the action log's format or contents for any of R13 to
  R16: they are event changes, and every rules-9 log shall replay to the same result.
- R18. When the rollout determinizes a paused trigger drain, it shall pin only the numbers
  that are card ids (the entry's card and subject, the prompt's source) and shall not treat
  other numbers in the kept entry or its data as cards (NSC-213, C10).

### C. The board (PVE and PVP)

- R19. While a deck note is showing, the board shall keep it through every later step until
  the note's own end, instead of clearing it at the next step (NSC-188).
- R20. When the board receives a `CREW_FIRED` event, it shall play its Crew-fire beat (the
  Crew lifts and settles) for that Crew slot (NSC-187).
- R21. When a Turn starts with a free first card for the player's seat, the board shall show
  it (the HUD's free-first state), and shall clear it once the free card is committed or the
  Turn ends (NSC-186).
- R22. If the board is halted (match ended, closed, or a prompt that forbids it), then a tap
  on a card shall not lift it, matching what the drag path already does (NSC-58).
- R23. The board shall have a `test_card_lift.gd` suite covering lift, put-down, the halted
  tap and the halted drag (NSC-58).
- R24. When a PVP match is abandoned under the player, the board shall clear the "Connection
  … lost" note, disable Pass and Commit, and show "Match abandoned" with Leave only
  (NSC-246 board sub-item).
- R25. When the board receives the created-card removal event of R10, it shall take the
  card off the table (the card flies off; the Pile count does not change).

### D. The PVP server

- R26. If a room's act path fails, then the server shall mark the room failed through the
  one failure path (`MatchRoom.fail`), close its clients with the failure reason and keep
  every other room running (NSC-246 R41).
- R27. If one address sends a wrong room code more than a small fixed number of times within
  a minute, then the server shall refuse its next join attempts for a cooling period and
  log it (NSC-246 room-code guessing).
- R28. The server shall measure every timeout, grace period and reconnect window with a
  monotonic clock, so a wall-clock change never fires or delays one; wall-clock time shall
  appear only in log timestamps (NSC-246).
- R29. If a seat disconnects and reconnects more than a fixed cap of times in one match,
  then the server shall treat the next disconnect as the seat leaving (NSC-246 flapping).
- R30. If a resync message would exceed the 1 MiB send limit, then the server shall close
  that client with a stated reason instead of dropping the message silently (NSC-246).
- R31. The server shall rotate `server.log` by size, keeping a fixed small number of past
  files (NSC-246).
- R32. When a bot client rejoins a room, the server shall count its `actions=` from the
  actions actually accepted after the rejoin, not from zero (NSC-246).
- R33. When the server starts, `PvpLog.scan_orphans` shall read only each file's header
  (not parse every log) to mark interrupted matches incomplete (NSC-246).

### E. The trainer (between training nights)

- R34. The fit shall weight paired positions as NSC-245 describes, and shall report the
  weighting in the fit record, so night 3's fits are reproducible (C10).
- R35. The trainer shall apply the remaining NSC-245 items: `validate_runs` rejects mixed
  policies, the Windows lock uses `os.replace`, the large-hand path matches the Godot side,
  fit validation runs outside the lock, the Makefile honours `WEIGHTS`, power iteration
  starts from a stated vector, `match_worker` reports its weights stamp, the farm records the
  feature set, and `LinearBot` offers the pass candidate.
- R36. The trainer shall own one run state machine (store-owned, one `ActiveRun`, one
  restart loop, one Godot path, one sampling path, a shared stamp module, `argparse`,
  run-row counters, the pool_key memo and candidate-independent feature base, power
  iteration on XtX) as NSC-233's code items describe; the label digest of the committed
  position file shall be recorded before and after and any change explained (C10).
- R37. The trainer shall not change the play-out protocol version, the hello message, the
  label reply or the `fits` table schema in this cycle (C10).
- R38. The play-out worker shall flush its output explicitly after every reply, never relying
  on `print()` buffering (NSC-209).
- R39. The orchestrator shall check the PC's rollouts per worker against the Mac's and record
  the batch and worker sizing it settles on (NSC-231); anything needing admin is noted, not
  done.
- R40. The trainer wave shall land only between training nights, never during one, and
  nothing shall be synced to the PC while a night runs (Ben, 2026-11-08).

### F. Tooling

- R41. `scripts/worktree-sweep.sh` shall never delete a worktree whose branch is not merged
  into the target, shall never remove a worktree registered by another checkout or session,
  and shall preserve the cycle's gitignored screenshots (or move them to a stated folder)
  before removing a merged cycle worktree (NSC-75).
- R42. If `gdlint` is not on the edit hook's PATH, then the hook shall print one line saying
  so instead of skipping the lint silently, and shall look in `~/.local/bin` first (NSC-57).
- R43. `make check`'s test stage shall finish its gdUnit suites in under 30 s on the Mac with
  every suite still run (NSC-251).
- R44. The test tree shall have one shared `_typed()` helper, and no suite shall carry its
  own copy (NSC-191).

### G. Documents and ledger

- R45. `docs/rules/` shall carry each ruling in its one place: Q11 (R1), the GY01 and GY09
  notes (R3), the CT07 note (R4), the glossary's Uses and created-card entries (R6, R9, R10),
  and `systems/game-loop` and `systems/cards-crew-decks` shall match.
- R46. `docs/systems/bot-training.md` shall describe the trainer as it stands after this cycle
  (the linear bot, `fit`, the PC runner, the ladder) and `CLAUDE.md`'s layout table shall
  gain rows for `trainer/`, `godot/title/` and `scripts/pc/` (NSC-204).
- R47. `docs/planning/cycles.md` shall have a current "Planned next" paragraph, and every
  Definition-of-done box in a finished spec shall be ticked or marked superseded; the two
  boxes that need Ben shall be put to him as one plain-text question at `/cycle plan`
  (NSC-252).
- R48. When the stamp moves to r9, [[planning/bot-ladder]] shall gain a rung-0 row at
  `r9-857b165d5a5d755e` with the `bot-eval` line, the r8 rows marked as measuring nothing at
  the current stamp, and the committed `linear_weights.json` re-stamped by hand (ladder R5).

### H. Cycle shape

- R49. The rules wave (section A and B) shall merge into the cycle branch before any other
  wave, and the golden lines and the sweep summary shall be re-pinned once, at the merge of
  the task that moves them (C9, Ben: "Rules wave first").
- R50. When the rules wave has merged and been synced to the PC, training night 2 may start;
  DC-20 shall not wait for night 2 or 3 to finish (C11).
- R51. The cycle shall run as one `/cycle run` in waves; two tasks that edit the same file
  shall not run in the same wave.
- R52. If any task outside the rules wave moves the golden line or the sweep summary, then
  the orchestrator shall treat it as a defect of that task, not re-pin.

## Clarifications (Ben, 2026-11-08)

Settled before the interview by the orchestrator's conversation with Ben (2026-11-08):

| # | Question | Answer |
|---|---|---|
| S1 | One project for every Backlog issue; DC-20 one cycle run in waves; the PC-night trainer work (NSC-243, NSC-244, NSC-250) and the router checklist (NSC-248) under their own milestone, not holding DC-20 open; the one-L-per-cycle rule broken knowingly | 1a |
| S2 | This short spec first; it settles the rulings and golden-line moves, then the waves | 2a |
| S3 | The engine-rule wave lands first; the spec decides whether it moves the stamp; night 2 starts on the final stamp once that wave merges; trainer-code items land between nights | "Rules wave first" |

The interview:

| # | Round, question | Answer |
|---|---|---|
| C1 | R1 Q1, NSC-178: does the resumed draw survive an exhausted Budget? | 1a: yes, it is a game step, not a trigger (R1, R2) |
| C2 | R1 Q2, NSC-181: should Immolator and Fuse leave protected and Condemned cards out of the pool? | 2b: no, the whole row stays the pool; a blocked pick is a visible miss (R3) |
| C3 | R1 Q3, NSC-183: does Level apply to face-down cards? | 3a: no (R4, R5) |
| C4 | R1 Q4, NSC-182: enforce `uses` or remove it? | 4a: enforce now (R6, R7) |
| C5 | R2 Q1, NSC-187: CREW_FIRED from the engine or a board mapping? | 1a: the engine emits CREW_FIRED with the uses left (R13, R20) |
| C6 | R2 Q2, NSC-175: Owner at creation or refuse in `to_pile`? | 2a, with: "dross cards also have a duration, like buffs. Some 'created' cards can last the whole match, but most of them will disappear when they're sent to the pile." (R8; the duration became C9) |
| C7 | R2 Q3, NSC-176: accept the random bot's seed fix and its golden move? | 3b: leave it, close as won't-fix |
| C8 | R2 Q4: bump `RULES_VERSION` to 9? | 4b: no (superseded by C9) |
| C9 | R3 Q1: where does the created-card lifetime rule land? | 1a: in this cycle's rules wave, with `RULES_VERSION` 9 after all, the re-pin, the rung-0 re-measure and the PC redeploy (R9–R12, R48, R49) |
| C10 | R3 Q2: which trainer items are in DC-20? | 2a: NSC-245 whole (pair weighting included), NSC-233's code items, NSC-209, NSC-231, NSC-213 in the rules wave; NSC-233's protocol and schema items stay for the training milestone (R18, R34–R39) |
| C11 | R3 Q3: when does night 2 start, and where does the trainer wave sit? | 3a: night 2 once the rules wave has merged and been deployed to the PC; the trainer wave after night 2, before night 3 (R40, R50) |
| C12 | R3 Q4: all the cleanup, or local items only? | 4a: all of it, the structural items as their own tasks (NSC-185, NSC-189, NSC-190) |

Facts corrected during the interview: the PC's PVP server already ran stamp
`r8-857b165d5a5d755e` (redeployed at `master` cc2b695, 80 gate suites green), so the only
redeploy this cycle is the one C9 brings.

## Scenarios

- **Given** a seat with an empty Deck and a Dredger, **when** its draw wakes an On empty draw
  Batch that spends the pulse's last trigger before Dredger resolves, **then** Dredger
  fizzles "exhausted" and nothing is drawn; **but when** Dredger resolves before the Budget is
  spent and a later trigger of the same Batch is exhausted, **then** the seat still draws the
  denied card (R1).
- **Given** an opposing row of Bastion and one other card, **when** Fuse reaches Power 5 and
  Condemns itself and one random opposing card, **then** either the other card is marked or
  the pick lands on Bastion and a fizzle naming the protection is emitted; the RNG stream
  advances the same way in both cases (R3).
- **Given** Level revealed on a row with a face-down 7-Power card, **when** the owner's
  private stats are read before the reveal, **then** the card shows Power 7; **when** it is
  revealed, **then** it shows the row's lowest revealed Power (R4).
- **Given** a fixture Crew with `uses` 1, **when** its moment occurs twice in the scope,
  **then** it fires once, the `CREW_FIRED` event shows `uses_left` 0, and the second moment
  wakes no firing (R6, R13).
- **Given** Litter creates two Dross in the opponent's hand, **when** the opponent
  discards down and a Dross is chosen, **then** the Dross leaves the Match with the removal
  event, the opponent's Pile count is unchanged, a later Dredger shuffles no Dross into the
  Deck, and the board flies the card off the table (R10, R25).
- **Given** a PVP match where seat 0 has committed face down and a Crew raises that card's
  Power, **when** the leak scan runs, **then** no event about the card reaches seat 1 until
  the reveal (R15).
- **Given** a Lantern seat's Turn start, **when** the board applies `TURN_STARTED`, **then**
  the HUD shows the free first card, and a cost-7 drop on a budget of 4 is accepted (R16,
  R21).
- **Given** a PVP board whose opponent has abandoned, **when** the close arrives, **then**
  the connection note is gone, Pass and Commit are disabled, and only Leave shows (R24).
- **Given** the rules wave merged and synced to the PC, **when** `make bot-eval` runs
  `random` against `random`, **then** the line ends `stamp=match` at `r9-857b165d5a5d755e`
  and a rung-0 row is added (R48).

## Data touched

- New: `docs/specs/cycle-14-backlog/` (this set); `godot/tests/test_card_lift.gd`; a shared
  `_typed()` test helper; one rung-0 ladder row; the `CARD_EXPIRED` (name decided in the
  plan) and `CREW_FIRED` emissions; the `lifetime` card key (optional, no file edited).
- Changed: `godot/engine/` (trigger_queue, turn_flow, abilities*, crew_abilities, card_def,
  card_db, match_cards, match_rules `RULES_VERSION` 9, match_event, rollout, bot/linear_bot,
  bot/data/linear_weights.json stamp); `godot/board/`; `godot/server/`, `godot/net/`;
  `godot/tools/match_worker.gd`; `trainer/`; `scripts/worktree-sweep.sh`, the edit hook under
  `scripts/hooks/`; `godot/tests/` (golden pins, sweep summary, leak suite, timings);
  `docs/rules/*`, `docs/systems/*`, `docs/planning/cycles.md`, `docs/planning/bot-ladder.md`,
  `CLAUDE.md` (three layout rows), finished specs' Definition-of-done boxes.
- Read only: `godot/engine/data/*.json` (unchanged; the stamp's hash half must stay
  `857b165d5a5d755e`), `docs/decisions/*`.
- Never: `godot/addons/`, `docs/.obsidian/`, `.env`, `godot/.godot/`, `godot/reports/`, the
  archive.

## Definition of done

- [ ] Rulings R1–R12 in the engine with a gdUnit case each, and in `docs/rules/` (R45).
- [ ] `RULES_VERSION` 9; golden lines and the sweep summary re-pinned once (R49); `make sweep`
  `p99_us` under 10000; rung-0 `bot-eval` PASS at r9 with its ladder row (R48);
  `linear_weights.json` re-stamped; the PC server prints `stamp=r9-857b165d5a5d755e`.
- [ ] The PVP leak scan includes a Crew stats change on a card in a pending Commit and passes
  (R15).
- [ ] Board fixes R19–R25 verified in the editor on the cycle worktree, one screenshot each
  for the deck note, the Crew beat, the free first card and the abandoned PVP board.
- [ ] PVP server R26–R33 proven by the loopback suites and the server log text.
- [ ] Trainer R34–R39 landed between nights 2 and 3; trainer tests green on the Mac and the
  PC; the label digest recorded before and after R36.
- [ ] Tooling R41–R44: a planted unmerged worktree survives a sweep; the hook prints its
  missing-gdlint line; gdUnit under 30 s; no `_typed()` copies left.
- [ ] Documents R45–R47 updated; the two NSC-252 boxes decided by Ben.
- [ ] Every DC-20 issue in P-NSC-16 is Done at `/cycle test`; NSC-243, NSC-244, NSC-248 and
  NSC-250 and the NSC-233 protocol items remain under the training milestone.
- [ ] `make check` is green.
- [ ] Constitution Check passes (see plan).
- [ ] Spec, plan and tasks signed off by Ben and committed before implementation begins.
