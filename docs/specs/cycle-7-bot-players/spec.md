---
type: spec
tags: [spec, cycle-7-bot-players, engine, bot, tooling]
status: approved
related: ["[[specs/cycle-7-bot-players/plan]]", "[[specs/cycle-7-bot-players/tasks]]", "[[specs/cycle-6-constructed-decks/spec]]", "[[specs/cycle-4-card-effects/spec]]", "[[specs/cycle-1-match-engine/spec]]", "[[planning/phase-3-game-loop]]", "[[planning/phase-1-tech-stack]]", "[[planning/cycles]]"]
created: 2026-11-04
updated: 2026-11-05
uid: 9586d342-7d13-4094-b199-d93b9f7d6a9a
linear: https://linear.app/night-science-llc/project/cycle-7-bot-players-c711d1c8bc83
supersedes:
---

# Spec: Cycle 7 — bot players

**Slug:** `cycle-7-bot-players`  ·  **Change type:** engine + tooling (a one-line board swap)  ·  **Status:** approved (Ben, 2026-11-04, three rounds, C1–C13; signed off 2026-11-04: "Sign off")  ·  **Runs as:** two milestones, A then B, the next two `DC-NN` numbers after cycle 6's DC-07

Cycle 7 turns the single greedy bot into a bot system. Milestone A ships the **tuned bot**
as the game's opponent: the greedy search pruned to a fixed number of exact previews and
scored by a small linear evaluator whose weights are a committed data file, with a level
knob that weakens it gracefully; one bot interface the board, the smoke, the sweep and the
scripts all use; two frozen reference bots; and a strength harness that plays paired,
seat-and-deck-swapped matches on every core and decides with a sequential test, run from
`make bot-eval` outside `make check`. Milestone B adds the training scripts that evolve
the weights overnight with no Claude spend and promote a candidate only when it passes the
test against both references, the **matrix bot** (the report's rung 2: own commits versus
the opponent's likely commits, solved by regret matching over a joint preview) as the
first "superior" bot the harness has to prove, and the level calibration. A stamp on every
weights file and report, plus two make targets, says how all of it is re-run after an
engine change.

The research this spec draws on is the report "Pruned lookahead and tuned evaluation beat
learning for card bots" (scratchpad, 2026-11-04); its ladder, measurement method, deck
handling and tier advice are the evidence behind the choices, not instructions.

## Intent

After cycle 7, the bot on seat 1 decides in under 10 ms with weights Ben's own machine
produced overnight, its strength is a number with an interval against a frozen yardstick
rather than a feeling, a second bot that models the simultaneous commit beats it by a
measured margin, and when a later cycle changes the rules the cycles log tells the
orchestrator exactly which two commands to run before merging.

## Non-goals

- No rung 3–5 (two-turn lookahead, determinized hand search, learned leaf evaluator) and
  never rung 6 (end-to-end RL): a later spec, ordered 3 then 5 then 4 per the report.
- No cheating full-information bot, even as a test ceiling (open item).
- No tier UI in the picker and no "thinking delay" presentation (open item); the level is a
  flag and a harness parameter only (C7).
- No threaded or frame-sliced decision in the client; the decision stays synchronous and
  under the budget by a fixed candidate count (C10).
- No GDExtension, C# or any hot path outside GDScript.
- No opponent-deck inference: both deck ids are public after cycle 6, so the matrix bot's
  hand sampler needs no prior.
- No rules, card or deck change; no new events the board must play; no iOS build (D8).
- No Claude or other model call inside any script this spec adds (C2, C4).

## Actors

- **Ben**: launches `make bot-eval` and `make bot-train` (or a cron does), reads one
  summary line and the ledger, picks `--bot=` and `--bot-level=` when he wants a
  particular opponent.
- **The player (seat 0)**: meets the tuned bot on the board; may later meet the matrix bot.
- **The bots**: the tuned bot (milestone A's opponent), the matrix bot (milestone B), the
  random bot and the frozen greedy bot (references), and the current greedy bot until the
  tuned bot replaces it. Each is a pure decision function over its seat's view, its seed and
  the engine's previews.
- **The engine**: owns the previews, including milestone B's joint preview, and the stamp
  inputs (rules version, card pool, deck list).
- **The harness**: the headless worker that plays batches of paired matches and the driver
  that spawns workers, aggregates, tests and trains.
- **The orchestrator**: runs `make check`, re-pins the golden, runs `make bot-eval` at
  verification, launches the training run at milestone B, keeps the ledger and the
  `/cycle test` checklist.

## Requirements (EARS)

### The bot interface (C1, C5)

- R1. The game shall select the bot for a seat by name from a fixed set (`greedy`, `tuned`,
  `random`, `greedy_v1`; `matrix` from milestone B); the board, autoplay, the smoke, the
  sweep and the harness shall all select bots through that one mechanism.
- R2. Every bot shall read only its own seat's redacted view and its own seed, and shall ask
  the engine only for previews of hypothetical actions; a bot's choice shall depend only on
  its seed, its view, its parameters and the previews, so the same inputs always give the
  same action (DC-01 R35, R37 generalised to every bot).
- R3. No bot shall return an action the engine rejects (DC-01 R38 generalised).
- R4. When the game starts without `--bot=`, the opponent shall be the tuned bot at full
  strength; `--bot=<name>` shall pick another, and an unknown name shall stop the launch
  with an error in the log and no `Main ready`.
- R5. The greedy bot's behaviour shall be unchanged by this cycle, so a log it produced
  under cycle 6's rules still replays and the greedy golden still holds while it is the
  smoke's bot.

### The tuned bot (milestone A; C1, C5)

- R6. The tuned bot shall enumerate the same candidate commits as the greedy bot (every
  legal set, the ordered variants, both row ends, the free-first order) and shall list each
  distinct commit once.
- R7. The tuned bot shall rank candidates by a cheap bound on the commit's own-score
  contribution that needs no preview, and shall preview exactly the top K of that ranking
  (fewer when fewer exist), where K is a whole number read from the weights file and never a
  measure of time.
- R8. The tuned bot shall value each previewed candidate by a weighted sum over a fixed,
  named list of features of the preview result and the view (the two preview scores, the
  energy and cards left, turns left, the round-win state, the opponent's hand and pending
  counts among them; the plan fixes the list), with the weights read from the weights file.
- R9. The tuned bot shall answer a single-target prompt by previewing each option and a set
  prompt as cycle 6 R37 does, valued by the same evaluator, ties by its seed.
- R10. The weights file shall carry a format version, the bot name it is for, K, the
  feature weights by name, the level constants, and the stamp (R33).
- R11. If the weights file is missing, malformed or names an unknown feature, then the bot
  shall use built-in default weights (the plain own-minus-opponent score, K at its default)
  and the launcher shall print one `Bot weights:` warning line; the engine itself prints
  nothing (DC-01 R27).
- R12. With the default weights and K at least the candidate count, the tuned bot shall
  choose the same action as the greedy bot on the same view and seed, so the pruned search
  is testable against the old one.

### The level knob (C7)

- R13. Every bot built on the evaluator (tuned, matrix) shall take a level from 0 to 20;
  at level 20 the bot shall choose the best-valued candidate exactly as R8 says, and the
  level shall change nothing else about the search, the previews or the candidate set.
- R14. While the level is below 20, the bot shall add to each previewed candidate's value a
  push drawn from a generator seeded from the bot's per-decision seed, scaled by the gap
  between that candidate and the best and by the level (the plan gives the formula), and
  shall choose the highest pushed value; a candidate whose gap exceeds the spread cap
  shall receive no push that can lift it above the best.
- R15. The level shall never grant the bot any information its view does not hold and shall
  never cut the previewed candidate count.
- R16. `--bot-level=<0..20>` shall set the opponent's level for the board and autoplay, and
  the worker shall take a level per seat; the default is 20.

### The decision budget (NSC-74; C10)

- R17. On the verification machine, the 99th-percentile decision of the 50-seed sweep by the
  shipped bot at full strength shall be under 10 ms, and the sweep shall print the 95th and
  99th percentiles and the slowest decision in microseconds (amended by C14).
- R18. The candidate caps that keep R17 shall be whole numbers in the weights file, so the
  sweep and the harness are deterministic across machines; no bot shall read a clock.
- R19. The sweep shall keep every invariant it checks today (every match ends, no hand over
  the cap, no commit over budget, no hidden id in any view or event, every log replays) for
  the shipped bot, and shall print the bot name and the stamp check (R35) on its line.

### Reference bots (C11)

- R20. The random bot shall choose uniformly, with its per-decision seed, among the legal
  candidate commits and among a prompt's options, and shall satisfy R2 and R3.
- R21. The frozen greedy bot (`greedy_v1`) shall be a copy of the greedy bot as it stands
  when cycle 6 merges, and its choices on a fixed suite of views and seeds shall be pinned
  by tests that never change.
- R22. Edits to the frozen greedy bot shall be limited to what a changed engine API forces,
  each recorded in the ledger (R37), and shall leave its pinned choices unchanged wherever
  the rules still allow those actions.
- R23. "Best-so-far" shall mean the weights file committed in the repository; no other copy
  of a bot is a reference.

### The strength harness (milestone A; C2, C3, C6, C9, C11)

- R24. The worker shall run headless, take two bot names with their levels and weights
  paths, a seed range, a deck pairing (two ids, or `seeded`), an output path and a batch
  label, and shall play every seed as a pair set: both bots in both seats and, when the two
  decks differ, under both deck assignments, so each bot plays each deck in each seat on the
  same shuffle.
- R25. The worker shall score each seed's pair set as one pentanomial outcome and shall
  write per-decision records (seed, round, turn, seat, bot, legal candidate count,
  candidates previewed, chosen action, best value, second-best value, chosen value, level,
  push drawn, wall-clock microseconds) and per-game records (winner, rounds, per-round
  margins, first committer and whether it won, deck pairing, action count) as JSON lines.
- R26. The worker shall replay every finished match's action log to an equal state and
  shall count rejected actions and decisions over 10 ms; a nonzero count of either shall
  fail the batch.
- R27. The driver shall spawn one worker per processor core on disjoint seed ranges, merge
  their outputs, and compute per bot: the win rate with a 95% interval against each
  opponent, the first-committer win rate, 95th-percentile and slowest decision, pass rate
  when a non-pass commit was legal, per-card play rate when in hand and drawn win rate,
  action-type entropy per turn, the rounds-to-win distribution and the share of matches
  reaching any cap.
- R28. The driver shall decide a comparison by a sequential probability ratio test with
  alpha and beta 0.05 on the pentanomial pair results, with gainer bounds [0, +25] and
  non-regression bounds [−25, 0] in Elo-equivalent units; the test shall end the run, with a
  configurable cap that only guards a runaway, and the summary shall say which bound ended
  it or that the cap did.
- R29. `make bot-eval` shall run the non-regression test of the shipped bot (the tuned bot
  with the committed weights) against the frozen greedy bot, print one summary line, exit 0
  on pass, 1 on fail, 2 when the cap ended the run and 3 on an error, and shall be sized to
  finish in about ten minutes on Ben's machine.
- R30. The harness shall never run inside `make check` and shall never need a network; it
  shall need only Godot, Bash and Python 3's standard library.
- R31. If a worker fails to start or exits abnormally, then the driver shall report which
  worker and its last lines, shall discard that worker's partial batch and shall exit 3.
- R32. Every output of the worker and the driver shall be written under `godot/reports/bot/`
  (untracked), named by batch label and date; nothing under `godot/` outside that folder
  and the weights file shall be written by a run.

### The stamp and the rerun provision (Ben: "with provisions on how to rerun these systems after significant engine changes"; C8)

- R33. The stamp shall be the engine's rules version together with a hash of the card pool
  and the deck list files; the engine side and the script side shall compute the same stamp
  for the same files.
- R34. Every weights file written by training and every harness report shall carry the
  stamp of the engine it was produced on.
- R35. When `make check`'s sweep runs, it shall compare the committed weights file's stamp
  with the current engine's and shall print `match` or `MISMATCH` on its line; a mismatch
  shall not fail the gate.
- R36. When a cycle changes the rules version, the card pool or the deck list, its
  `/cycle test` shall run `make bot-eval` before the merge into `master`, and if that fails
  or the stamp mismatches, shall run `make bot-train` and commit the re-stamped weights in
  the same cycle; the checklist item shall live in the `/cycle test` skill and the cycles
  log row shall record the outcome.
- R37. The vault shall gain a ledger note with one row per accepted bot or reference change:
  date, bot, stamp, what it was tested against, the test result and games, 95th-percentile
  and slowest decision, and the commit.
- R38. If `make bot-eval` or `make bot-train` is run with a weights file whose stamp does
  not match the engine, then the driver shall say so on its first line and continue, and the
  summary shall repeat the mismatch.

### Training (milestone B; C2, C4, C9, C10)

- R39. `make bot-train` shall evolve the tuned bot's weights by a population method whose
  fitness is pentanomial points from paired matches within the population and against the
  frozen greedy bot, with every seed drawn from a run seed written in the run's report, so a
  run is reproducible.
- R40. The training run shall take a wall-clock limit (default eight hours), shall write a
  checkpoint after every generation and shall resume from the latest checkpoint when
  started again with the same label.
- R41. When a generation ends, the driver shall take its best individual as a candidate and
  shall run the gainer test (R28) against the frozen greedy bot and against best-so-far; only
  a candidate that passes both, with zero rejected actions, zero replay mismatches and its
  99th-percentile decision (side a's, the R17 measure) under the 10 ms budget, shall be
  promoted (amended by C16; it read "zero decisions over budget", which an eval run on all
  cores can never meet). The summary line prints `p99_us=` and the counts of overruns, and
  names the failed condition as `reason=p99`, `reason=rejected` or `reason=replay`.
- R42. When a candidate is promoted, the driver shall write it as the weights file with the
  current stamp, keep the previous file beside it under `godot/reports/bot/`, and print a
  ledger-ready line; it shall not commit.
- R43. If no candidate is promoted before the wall-clock limit, then the driver shall leave
  the weights file untouched and shall exit 2 with the best candidate's result in the summary.
- R44. A training run shall spend no model tokens: it is scripts only, and an agent's part is
  at most to launch it and read its summary line.
- R45. Every match a training run plays shall be replayable from its log; the driver shall
  replay a sample of each generation's logs and fail the run on any mismatch.
- R46. `make bot-train` shall accept the matrix bot's name so the same loop tunes its
  evaluator weights and its candidate caps.

### The matrix bot (milestone B; C5)

- R47. The engine shall offer a joint preview: given a seat, that seat's hypothetical commit
  and a hypothetical opponent commit, it shall return the two scores the walk would end on
  with both commits on the rows, and shall change no state, event, log or stream.
- R48. The joint preview shall treat the opponent's real face-down commit as absent and
  shall place the hypothesis in its stead; when the opponent has committed first, the
  hypothesis shall be required to match the public count and slots, and otherwise shall be
  any commit legal for the opponent's public budget.
- R49. The joint preview shall accept as hypothesis any card of the opponent's deck that the
  seat's view does not show, and its result shall not depend on where that card really is
  (hand, deck or burn), so the caller learns nothing about the opponent's hidden piles.
- R50. The matrix bot shall sample opponent hands consistent with the view (the opponent's
  deck list minus every card the view shows, sized to the opponent's hand count) from its
  per-decision seed, shall build opponent candidate commits from those hands bounded by a
  cap from the weights file, and shall build its own candidates as the tuned bot does.
- R51. The matrix bot shall evaluate the joint preview of each own candidate against each
  opponent candidate with the evaluator (R8), shall run regret matching for a fixed
  iteration count from the weights file to a mixed strategy over its own candidates, and
  shall choose by sampling that strategy with its per-decision seed.
- R52. The matrix bot shall answer prompts as the tuned bot does, and shall satisfy R2, R3,
  R13–R16 (the push applies to its candidates' expected payoffs) and R17.
- R53. The matrix bot shall take the second committer's observed count into account by
  filtering the opponent's candidate commits to that count and those slots.
- R54. Milestone B shall be accepted only when the matrix bot with its trained weights passes
  the gainer test against the frozen greedy bot and against the tuned bot's best-so-far.

### Calibration (milestone B; C7)

- R55. `make bot-calibrate` shall measure, for a grid of levels and deck pairings, the
  shipped bot's win rate with an interval against the frozen greedy bot, and shall write a
  table to the ledger naming tiers by measured win rate, not by level number.

### Gate and board

- R56. The smoke, the autoplay result line and the sweep line shall carry the bot name
  (`bot=tuned`); the seed-1 golden is re-pinned by the orchestrator at milestone A's
  verification under the tuned bot.
- R57. Every requirement of cycle 6 R36–R38 stays in force for the greedy bot; DC-01 R35–R38
  and cycle 4 R36–R38 are generalised by R2, R3 and R6–R9 to every bot; cycle 6 C14's "no
  change to the bot's search width or budget" is lifted by this spec.

## Clarifications (Ben, 2026-11-04)

| # | Question | Decision |
|---|---|---|
| C1 | Round 1 Q1: what "online" means | 1a: the pruned, tunable bot is the in-game opponent on the board, in autoplay and the smoke, under the 10 ms budget (closes NSC-74); one bot interface for board, smoke, sweep and scripts |
| C2 | Round 1 Q2: what "low effort and token spend" bounds | 2c: "Only runtime matters; the build may be as long as it needs"; a run spends zero model tokens |
| C3 | Round 1 Q3: how much of phase 2 goes in this spec | 3b: both phases in full, one spec, two milestones |
| C4 | Round 1 Q4: which engine | 4a: cycle 6's; `/cycle plan` waits for cycle 6 to merge; the orchestrator re-bases or re-cuts the branch. Ben's rider: "with provisions on how to rerun these systems after significant engine changes" (R33–R38) |
| C5 | Round 2 Q1: the ladder split | 1a: milestone A = rung 1 + interface + references + harness; milestone B = weight training + rung 2 matrix bot with a joint preview; rungs 3–5 a later spec |
| C6 | Round 2 Q2: where the scripts run | 2a: headless Godot workers (one per core, JSONL), a Python 3 stdlib driver under `scripts/` for fan-out, SPRT and evolution; `make bot-eval` / `make bot-train` outside `make check` |
| C7 | Round 2 Q3: difficulty tiers | 3a: the level mechanism now (gap-scaled seeded push, never peeking or depth cuts), `--bot-level=` and a harness parameter, default full strength; calibration in milestone B; picker UI later |
| C8 | Round 2 Q4: rerun after engine changes | 4a: a rules-version + data-hash stamp on weights and reports; `/cycle test` of a rules or data change runs `bot-eval`, then `bot-train` on failure or mismatch; `make check` warns on a mismatch and stays green; checklist in the `/cycle test` skill and the cycles log |
| C9 | Round 3 Q1: what "superior" means | 1a: SPRT alpha = beta = 0.05 on paired seat-and-deck-swapped seeds scored pentanomially; gainer [0, +25] Elo-equivalent against the frozen greedy and best-so-far with zero rejected actions and zero overruns; non-regression [−25, 0]; the test ends the run |
| C10 | Round 3 Q2: time budgets | 2a: 10 ms per decision kept, enforced by fixed candidate caps, synchronous in the client; `bot-eval` about ten minutes on all cores; `bot-train` a wall-clock argument (default 8 h), checkpoint per generation, resumable |
| C11 | Round 3 Q3: where artefacts live | 3a: weights committed under `godot/engine/bot/data/` with the stamp; logs and reports under `godot/reports/bot/` (untracked); a ledger `docs/planning/bot-ladder.md` kept like `cycles.md` |
| C12 | Round 3 Q4: proof | 4a: milestone A: `make check` with the new sweep line, golden re-pinned, a `bot-eval` summary in the cycles log, one screenshot of the tuned bot's first commit; milestone B: SPRT pass lines for the trained weights and the matrix bot, committed weights, one training match replayed |
| C13 | Round 3 defaults, no objection | The frozen reference is cycle 6's final GreedyBot copied after its T08, never edited beyond R22; the random bot is the floor; best-so-far is the committed weights file |
| C14 | DC-08 run, latency (2026-11-04) | 1a: the shipped cap is k = 24 (the built-in default too): it chose as `greedy_v1` in every game of a 111-pair non-regression `bot-eval` (PASS), quiet-run p99 7.0 ms; k = 48 barely pruned (13–77 candidates a position). 2a: the sweep asserts the 99th percentile under 10 ms and prints the slowest without asserting it, since one OS stall on a shared machine decides the slowest (46–393 ms seen); R17 amended |
| C15 | DC-08 T11, test budget (2026-11-04) | 1b: the test stage's budget is 30 s of gdUnit time, up from 15 s (cycle 6 C23), and every test is kept: gdUnit ran about 25 s, the 50-seed tuned sweep about 8 s and `test_tuned_bot` about 9 s (its 20-seed full-search parity check about 4.7 s). Rejected: trimming the parity and repeat checks to reach about 19 s (a), or also halving the sweep to hold 15 s (c) |
| C16 | DC-10 T17 review (2026-11-05) | 1a: R41 amended: a candidate is promoted only if it passes the gainer test against the frozen greedy bot and against best-so-far, with zero rejected actions, zero replay mismatches and its 99th-percentile decision under the 10 ms budget (the R17 p99 measure), instead of "zero decisions over budget"; under a parallel eval on all cores the shipped tuned bot itself ran 241-389 overruns per eval (OS contention), so the zero-overrun rule could never promote anything. 2a: the matrix bot ships k 6, k_opp 4, samples 2, rm_iterations 50 (measured p99 was 59 ms at 12/12/4/200 against 10 ms); the trainer caps k at 6 and k_opp at 4 (samples and rm_iterations are not tunable); latency is measured at T18 (Verification B), and if 2a still misses 10 ms the orchestrator brings the next step down back to Ben. 3a: every review finding fixed in one pass: the default train label is `<bot>-<stamp>` and a checkpoint of another stamp is refused; a pending candidate survives a crash and is re-promoted on resume; a rejected action in the candidate eval is a candidate FAIL, not a run abort; the R38 mismatch repeats in the final lines; `bot-calibrate` writes the ledger (R55); the rerun provision covers the matrix weights. Nits are recorded in tasks.md, not fixed. T18 follow-up (Ben, 2026-11-05, 1a): 6/4/2/50 measured p99 10.9 ms on three runs, so the matrix bot ships k_opp 3 (6/3/2/50) and the trainer caps k_opp at 3; rejected: one sample at k_opp 4 (1b) |

## Scenarios

- **Given** the game starts with no flags, **when** seat 1 commits, **then** the bot was
  the tuned bot at level 20 and the result line later reads `bot=tuned`.
- **Given** `--bot=greedy_v1 --bot-level=5`, **then** the launch fails with an error (the
  frozen bot has no level) and no `Main ready`; **given** `--bot=tuned --bot-level=5`,
  **then** the bot occasionally picks a second-best commit and never a clearly losing one.
- **Given** a view and seed, **when** the tuned bot runs with default weights and K above
  the candidate count, **then** its action equals the greedy bot's.
- **Given** the weights file is deleted, **when** the game boots, **then** one
  `Bot weights:` warning line prints, the smoke still runs and `Main ready` prints.
- **Given** the 50-seed sweep under the tuned bot, **then** every invariant holds, the
  99th-percentile decision is under 10 ms, and the line reads `… bot=tuned p95_us=…
  p99_us=… stamp=match` with `slowest_us=…` printed (C14).
- **Given** `make bot-eval` with a healthy weights file, **when** it runs, **then** eight
  workers play paired batches, the SPRT crosses a bound within about ten minutes, the
  summary names the bound and the game count, and the exit code is 0.
- **Given** a cycle bumps the rules version, **when** `make check` runs, **then** the sweep
  line reads `stamp=MISMATCH` and the gate is green; **when** `/cycle test` runs
  `make bot-eval` and it fails, **then** `make bot-train` is run and the re-stamped weights
  are committed before the merge.
- **Given** `make bot-train HOURS=8`, **when** it is interrupted and started again with the
  same label, **then** it resumes from the last checkpoint; **when** a generation's best
  passes both gainer tests, **then** the weights file is rewritten with the stamp and a
  ledger-ready line prints.
- **Given** the matrix bot as second committer with the opponent's two face-down cards on
  slots 0 and 1, **then** every opponent hypothesis it previews has two cards on slots 0
  and 1, and no joint preview result depends on where an unseen card really sits.
- **Given** the trained matrix bot, **when** `make bot-eval BOT=matrix` runs against the
  frozen greedy and against the tuned best-so-far, **then** both gainer tests pass.

## Data touched

- New: `godot/engine/bot/` (interface, registry, random bot, frozen greedy copy, candidate
  generator, evaluator, weights loader, stamp, tuned bot, matrix bot, hand sampler, regret
  matching), `godot/engine/bot/data/tuned_weights.json` (and `matrix_weights.json`),
  `godot/tools/bot_worker.gd`, `scripts/bot/` (driver, SPRT, evolution), `scripts/bot-eval.sh`,
  `scripts/bot-train.sh`, Makefile targets, new suites, `docs/planning/bot-ladder.md`, this
  spec set.
- Changed: `godot/engine/match_engine.gd` (joint preview), `godot/engine/bot/greedy_bot.gd`
  (adopts the interface, no behaviour change), `godot/main.gd` and
  `godot/board/match_driver.gd` (bot by name, level, result line), `godot/tests/test_full_match.gd`
  (bot by name, p95, stamp line), `docs/planning/cycles.md`, `docs/specs/specs-moc.md`, the
  `/cycle test` checklist (orchestrator).
- Read only: `godot/engine/data/cards.json`, `decks.json` (hashed, never written),
  `godot/board/*` beyond the driver, `godot/picker/*`.
- Never: `godot/addons/*`, `godot/art/*`, `docs/.obsidian/`, `.env`, `godot/.godot/`, the
  archive. `godot/reports/` is written only by the harness and the gate.

## Open items for later specs

- Rungs 3–5 (two-turn lookahead with a pure step function, learned leaf, determinized
  search), ordered 3, 5, 4.
- A cheating full-information bot as a diagnostic ceiling and blunder labeller.
- Tier names in the picker, a thinking delay scaled by candidate spread.
- Per-card drawn win rate and matchup matrix as the balance tool for the ramp and bounce
  decks (the harness already emits the counters).

## Definition of done

Milestone A
- [ ] R1–R38 and R56–R57 each covered by a named gdUnit4 case, the sweep line, the boot
      log, a harness run or a step of the verification.
- [ ] `make check` green, test stage under 30 s of gdUnit time (C15); sweep line shows
      `bot=tuned`, p99 under 10 ms (C14), `stamp=match`; the seed-1 golden re-pinned under
      the tuned bot.
- [ ] `make bot-eval` exits 0 with its summary line pasted into the cycles log; the ledger
      has its first two rows (greedy_v1 frozen, tuned v1 shipped).
- [ ] One screenshot: the board at the tuned bot's first commit.
- [ ] The `/cycle test` checklist carries R36.

Milestone B
- [ ] R39–R55 covered as above.
- [ ] A training run of at least one promotion: SPRT pass lines against both references,
      the weights committed, one training match replayed from its log to an equal state.
- [ ] The matrix bot passes the gainer test against both references (R54); its sweep line
      is under 10 ms.
- [ ] The calibration table is in the ledger.
- [ ] Constitution Check passes (see plan).
- [x] Spec, plan and tasks signed off by Ben (2026-11-04); committed before implementation begins.
