---
type: spec
tags: [spec, cycle-11-bot-trainer, engine, tooling, bot, training, windows, mcp]
status: approved
related: ["[[specs/cycle-11-bot-trainer/plan]]", "[[specs/cycle-11-bot-trainer/tasks]]", "[[planning/bot-trainer-architecture]]", "[[planning/bot-trainer-spike]]", "[[planning/bot-ladder]]", "[[systems/bot-training]]", "[[specs/cycle-9-rules-v2/spec]]", "[[specs/cycle-7-bot-players/spec]]", "[[rules/test-decks]]", "[[planning/cycles]]", "[[planning/phase-1-tech-stack]]"]
created: 2026-11-07
updated: 2026-11-09
uid: 98fa6820-8ac6-4413-8a30-e30ed6cb3a6b
supersedes:
---

# Spec: Cycle 11 — bot trainer, cycle A (play-outs, the ladder from random, the trainer service)

**Slug:** `cycle-11-bot-trainer`  ·  **Change type:** engine + tooling  ·  **Status:** approved (Ben, 2026-11-07, two rounds, signed off 2026-11-07; see Clarifications)

This is cycle A of the bot trainer designed in [[planning/bot-trainer-architecture]] and
measured in [[planning/bot-trainer-spike]] (verdict Go, 2026-11-07). Ben's decisions T1 to T8
of 2026-11-06 are in force and are not reopened here: native Windows on the PC (T1), code to
the PC as a `git bundle` over MCP (T2), the LLM only from cycle C (T3), the staged policy
forms (T4), play-outs to the end of the match (T5), the trainer code in `trainer/` in this
repo (T6), SSH as the non-admin `trainer` account for maintenance (T7) and fixed MCP verbs
for runs (T8). The spike's facts stand as facts: the PC and the Mac play byte-identical
matches; the PC sustains about 1,500 random matches a minute at 16 workers; a Windows SSH
session kills its processes at disconnect, so long jobs go through the `trainer-runner`
scheduled task; `mcp` 2.3.0 names its server class `MCPServer`.

It also rebuilds what DC-13 removed ([[specs/cycle-9-rules-v2/spec]] R70 to R75): a match
worker, the stamp and a yardstick ladder, this time starting from `random`.

Two milestones, one spec (Ben, round 1, 1a):

- **Milestone A1** (this branch, `cycle-11-bot-trainer`): the stamp, the match worker and
  `make bot-eval` driving again, the engine's rollout entry with determinization, the
  play-out worker, `scripts/bot/` Windows-safe with the genetic tooling deleted, the ladder
  reopened with `random` as rung 0. Every piece is proven on the Mac.
- **Milestone A2** (`cycle-11b-bot-trainer`): `trainer/` on the PC: the run store, the
  play-out farm and its checkpoints, the MCP server with its bearer token and nine verbs,
  `sync_code` by bundle, the Windows runner scripts, the first labelled dataset, the
  rewritten bots guide.

## Intent

After A1, a position in a rules-7 match (a seed and an action-log prefix) can be labelled
on the Mac: the engine builds determinized copies of the position from one seat's view and
plays each candidate commit out to the end of the match, and a long-lived headless worker
does this on request over JSON lines, reproducibly across machines; `make bot-eval` measures
one bot against another again, and the ladder says what a yardstick is. After A2, the Mac
starts a labelling run on the PC through fixed MCP verbs, watches it, stops and resumes it
across an interruption, and reads the dataset it produced, with the PC's labels equal to
the Mac's for the same position.

## Non-goals

- **No learner, no policy, no weights file, no new bot.** `random` stays the only bot (round
  1, 2a); the first learned policy is cycle B's. `get_artifact` waits for cycle B (round 1,
  4a).
- **No LLM** (T3: cycle C), no plan language, no plan-aware rollout policy.
- **No prompt labels** (round 2, 2a): prompts opened during a rollout are answered by the
  rollout policy; only commit decisions are labelled.
- **No board, picker or scene change**; no iOS build (D8).
- **No calibration, levels or genetic training**: `evolve.py`, `calibrate.py`,
  `scripts/bot-train.sh`, `make bot-train` and `make bot-calibrate` are deleted (round 1, 3a).
- **No automatic promotion or ledger write by the trainer**; rungs are added by the
  orchestrator at verification.
- **No edit** to Ben's uncommitted working-copy changes to `docs/systems/bot-training.md` in
  the main checkout; the guide rewrite (round 2, 4a) waits until Ben has committed or
  discarded them, on the cycle branch only.
- **No push**, no commit on `master`, no token in chat, notes, commits or Linear (P6).

## Actors

- **Ben**: decides, does the admin steps at the PC, signs off.
- **The orchestrator** (the Mac session): runs the gate, drives the Mac side, reaches the PC
  by SSH as `trainer` and over MCP, posts to Linear, writes the ledger and cycle rows.
- **The engine**: `godot/engine/`, now with a rollout entry.
- **The match worker**: a headless Godot process that plays seed pairs of two named bots and
  writes records for the SPRT.
- **The play-out worker**: a long-lived headless Godot process that answers position
  requests over JSON lines.
- **The driver**: `scripts/bot/driver.py eval`, the Mac's `make bot-eval`.
- **The trainer service** (A2): one Python process on the PC: the run store, the farm, the
  scheduler and the MCP server.
- **The `trainer-runner` task** (A2): the scheduled task that starts long jobs on the PC.
- **Implementer-engine, implementer, reviewer**: the roles of `CLAUDE.md`.

## Requirements (EARS)

"The engine" is `godot/engine/`. "A log" is the serialized action log (D4). "A position"
is a match seed, two deck ids and a log prefix, with the seat whose commit is awaited after
the prefix. "The seat's view" is `SeatView` for that seat (cycle 9 R57). "A label" is one
position, its candidate commits and the value of each. Values are integers.

### A. The stamp and the ladder (A1; cycle 7 R33, cycle 8 R58, [[planning/bot-ladder]])

- R1. The engine shall compute a stamp `r<rules version>-<first 16 hex digits of SHA-256
  over the bytes of the card pool file, then the deck list file, then the Crew pool file>`,
  and the driver shall compute the same string for the same files; today it begins `r7-`.
- R2. Every record set the match worker, the play-out worker and the driver write shall
  carry the stamp they were produced under.
- R3. The ladder note shall define a **rung** as one measured bot at one stamp and the
  **yardstick** as the highest rung at the current stamp; `random` shall be rung 0.
- R4. The ladder note shall state the promotion rule for later cycles: a policy becomes the
  next rung only after a gainer SPRT PASS against the yardstick and a quiet 50-seed sweep
  with a p99 decision under 10 ms on the Mac; nothing in this cycle promotes anything.
- R5. When the stamp changes, the ladder note shall require a new rung-0 row (no re-stamp
  is needed, `random` has no weights) and shall mark every higher rung unproven until
  re-measured; the "rerun provision suspended" line of DC-13 shall be replaced by this rule.
- R6. The ladder note's `## Calibration` block shall be removed with the levels it measured.

### B. The match worker and `make bot-eval` (A1; cycle 7 R24 to R32)

- R7. The match worker shall play bot `a` against bot `b` over a seed range: per seed the
  games (a at seat 0, b at seat 1) and (b at seat 0, a at seat 1), and when the two decks
  differ the same two with the decks swapped, the pairing being the seed's seeded pick or a
  given `<id>/<id>`.
- R8. The match worker shall write one JSON line per decision (with its time in
  microseconds), per game, per pair (points for `a`: 0, 0.5, 1, 1.5 or 2) and one end record
  (games, rejected actions, overruns per side, replay mismatches, p95, slowest, stamp), in
  the field names the driver reads today.
- R9. When a game ends, the match worker shall replay its log and compare the final full
  state; a difference shall count as a replay mismatch.
- R10. The match worker shall exit 0 on success, 1 on any rejected action or replay mismatch
  (every record still written), 2 on bad arguments or an unknown bot, 3 when the engine
  cannot start; it shall accept no level and no weights flag.
- R11. The driver shall spawn one match worker per processor core on disjoint seed batches
  (batch size a flag), feed pairs to the pentanomial SPRT in seed order, stop at the
  deciding pair and print the one summary line of today without weights fields:
  `bot-eval: a=.. b=.. result=.. bound=.. pairs=.. games=.. winrate=..±.. first_committer=..
  p95_us=.. p99_us=.. slowest_us=.. overruns_a=.. overruns_b=.. stamp=.. exit=..`.
- R12. The driver shall run unchanged on macOS and on native Windows (T1): paths through the
  standard library, the Godot binary from `GODOT_BIN` (a `.exe` on the PC), no shell, no
  POSIX-only call, no quoting that depends on the shell.
- R13. `make bot-eval` with `random` against `random` shall end PASS (non-regression) or CAP
  with a win rate within 0.05 of 0.500, zero rejected actions and zero replay mismatches;
  this is the driver's live selftest this cycle.
- R14. `make bot-selftest` shall run the unit tests of the driver, the SPRT and the records
  module, and nothing of the deleted tooling shall remain: no `evolve.py`, `calibrate.py`,
  their tests, `scripts/bot-train.sh`, nor the `bot-train` and `bot-calibrate` targets.
- R15. `make bot-eval` shall never be part of `make check` and shall need no network.

### C. The rollout entry and determinization (A1; engine)

- R16. The engine shall build, from a running match at a commit decision for seat `s` and a
  determinization seed, a **determinized copy**: a match that accepts actions from that
  point, in which everything the seat's view shows is unchanged.
- R17. When a determinized copy is built, the engine shall replace the identity of every
  card the seat's view does not name (the other seat's hand, the other seat's face-down
  Commit, the other seat's face-down row cards the seat has not looked at, and both Decks'
  orders beyond the cards the view's `deck_top` names) by a uniform permutation, drawn from
  a generator seeded by the determinization seed, within the set of identities hidden from
  that seat and owned by the same seat; a card's Memory and created-card definition shall
  move with its identity, and its Board changes, statuses and `chosen` mark shall stay with
  the row slot (zone and position), so the seat's view of the copy equals its view of the
  original (amended at T06, C9).
- R18. The determinized copy's random stream shall be seeded from the determinization seed,
  never from the real match's stream state.
- R19. The engine shall leave the real match unchanged by building or playing any number of
  determinized copies: its full state, log and events before and after shall be equal.
- R20. When a rollout is run, the engine shall apply the candidate action to the copy, then
  let the named rollout policy (a registry bot, seeded per seat from the determinization
  seed) choose for both seats until the match ends or an action cap is reached, and shall
  report the value for seat `s`.
- R21. The value shall be 1000 for a win, 0 for a draw and −1000 for a loss, plus ten times
  the difference between the seat's Round wins and the other seat's at the end (T5: the
  match result with the round-win difference as a small tiebreak).
- R22. If a rollout reaches the action cap, then the engine shall report a draw with a
  `capped` mark; if the copy rejects the candidate action, then the engine shall report the
  candidate as `rejected` with no value and shall not count it.
- R23. The same position, candidate, determinization seed and rollout policy shall give the
  same action sequence and the same value on every machine (D4), and a suite shall pin one
  rollout's value and action count on seed 1.
- R24. The rollout entry shall not be reachable from the shipped decision path: no bot and
  no scene shall call it; it exists for the workers and the tests.

### D. The play-out worker (A1; tooling under `godot/`)

- R25. The play-out worker shall start once per process, print one `hello` line (stamp,
  rules version, log format, Godot version) and then answer requests read as JSON lines on
  standard input with one JSON line each on standard output, in request order, until a
  `quit` request or end of input.
- R26. The play-out worker shall answer a `play` request (seed, two deck ids or the seeded
  pick, generator bot name) with the finished match's log, result and the list of its
  commit decision indices by seat, so a position can be chosen from it.
- R27. The play-out worker shall answer a `label` request (a position, `k`, `determinizations`,
  a rollout bot name, a label seed) by replaying the prefix, listing the seat's legal commits,
  keeping all of them when there are at most `k` and otherwise `k` drawn uniformly from the
  label seed, and returning per candidate the mean value, the spread, the counts of wins,
  draws, losses and capped rollouts, and the rollouts made; the candidate list shall also
  be accepted explicitly in place of `k`.
- R28. The play-out worker shall derive every determinization seed from the label seed and
  the determinization index, so every candidate of a label is played on the same deals and a
  label set reproduces exactly from its seeds (amended at `/cycle test` DC-16, C10).
- R29. The play-out worker shall carry the request `id` and the stamp on every reply, report
  the microseconds spent, and answer a malformed request or a prefix that fails to replay
  with an error reply naming the problem, never by exiting.
- R30. A mid-match rollout shall cost no more than a full match from the start on the same
  machine, and the verification shall record rollouts per second per worker on the Mac
  (A1) and on the PC (A2) in the cycle row.
- R31. Two runs of the same requests, on one worker or spread over eight, shall give the
  same label digest (SHA-256 over the replies with timing fields removed).

### E. The run store, the farm and resume (A2; `trainer/`)

- R32. The trainer shall keep every run's config, state, progress and labels in a store under
  one data folder outside the repository, with the labels also readable as JSON lines
  shards, each carrying the run id, position, candidates, values, stamp and commit.
- R33. When a run starts, the trainer shall generate positions by self-play of the named
  generator bot on the shipped decks (seeded pairing or every ordered pairing in turn),
  one position per generated match, chosen uniformly among that match's commit decisions
  by a seed derived from the run seed and the position index, and shall label each with
  the run's `k`, `determinizations` and rollout bot.
- R34. The trainer shall keep every configured worker busy with one long-lived play-out
  worker process each, restart a worker that dies, and count the restart in the run's
  status.
- R35. The trainer shall commit progress in batches of a configured size; when a run is
  stopped or interrupted at any point, at most one batch of labels shall be lost.
- R36. When a stopped or interrupted run is resumed, the trainer shall continue from the
  last committed batch, and the resumed run's full dataset shall equal the dataset of the
  same run never interrupted (same digest).
- R37. When the trainer service starts and finds a run marked running, it shall mark it
  interrupted and shall not resume it on its own.
- R38. The trainer shall run one run at a time; a second `start_run` while one is active
  shall be refused with a message naming the active run.
- R39. The trainer shall run with the Python standard library plus the `mcp` package (pinned
  `>=2.3,<3`) only, and `make trainer-test` shall run its unit tests on either machine.

### F. The MCP server, its verbs and the token (A2)

- R40. The trainer service shall expose one MCP server over streamable HTTP on the PC's LAN
  address and the port the firewall rule opens (8765), and shall refuse to start when no
  bearer token is configured.
- R41. If a request lacks the configured bearer token or carries a different one, then the
  server shall answer 401 and shall run no tool.
- R42. The token shall be read on the PC from a file outside the repository readable only
  by `trainer`, and on the Mac from `.env` (`BOT_TRAINER_TOKEN`, with `BOT_TRAINER_URL`),
  which `.mcp.json` references as `${VAR}` placeholders in a `bot-trainer` entry; the token
  shall never be printed, logged or echoed by any tool.
- R43. The server shall expose exactly these nine tools and no tool that runs a shell or an
  arbitrary command: `health`, `sync_code`, `start_run`, `run_status`, `stop_run`,
  `resume_run`, `list_runs`, `get_report`, `sample_positions`.
- R44. `health` shall return the host, Python, Godot and `mcp` versions, the checked-out
  commit and stamp, workers busy and total, the active run id if any, GPU name and memory
  when `nvidia-smi` answers, free disk and the service's uptime.
- R45. `start_run` shall take a typed config (positions, `k`, determinizations, rollout bot,
  generator bot, deck selection, workers, batch size, run seed, hours cap) with defaults,
  shall validate it and shall return the new run id; a config error shall be returned, not
  started.
- R46. `run_status` shall return the run's state (queued, running, stopping, stopped,
  interrupted, done, failed), positions done and total, labels, rollouts, rollouts per
  minute, labels per hour, the ETA, the last checkpoint time, worker restarts and the last
  error.
- R47. `stop_run` shall stop at the next batch boundary and `resume_run` shall continue a
  stopped or interrupted run (R36); each shall return the resulting state.
- R48. `list_runs` shall return every run with its id, state, config summary, stamp, commit,
  counts and timestamps.
- R49. `get_report` shall return a finished or stopped run's summary: config, stamp, commit,
  positions, labels, rollouts, wall time, rollouts per second, a histogram of candidate
  counts, the mean spread of values within a position, the dataset digest and the shard
  paths.
- R50. `sample_positions` shall return `n` positions of a run with their seat, Round, Turn,
  the seat's hand as card ids and names, each candidate as card ids and slots with its
  value and counts, ordered best first, for Ben and the orchestrator to read.

### G. `sync_code` (A2; T2)

- R51. `sync_code` shall accept a `git bundle` either inline (base64) or by the name of a
  file already placed in the service's inbox folder, shall verify it, fetch it into the
  PC's training repository, check out the named commit in the training worktree, run the
  Godot import there and return the commit, the stamp and the import's duration.
- R52. If a run is active, then `sync_code` shall refuse and name the run; if the bundle
  fails verification or does not contain the named commit, then `sync_code` shall change
  nothing and return the error.

### H. The Windows runner scripts (A2; round 2, 1a)

- R53. The repository shall carry under `trainer/windows/` the runner script (polls the
  queue folder, runs every `.cmd` it finds, logs each to its own file, and on its own start
  runs every `.cmd` in an `autostart` folder), the batch-logon grant script from the spike,
  a `start-mcp.cmd` that starts the trainer service from the training worktree, a
  `runner-shim.ps1` that the existing `trainer-runner` task's file is replaced with (it runs
  the stable copy of the runner), and a `SETUP.md` listing the admin steps of a fresh PC
  only (the account, SSH, the firewall rules, the batch-logon right, the task); on the
  current PC every A2 step runs over SSH as `trainer`, with no admin (C11).
- R54. When the runner starts after a reboot, the trainer service shall start from
  `autostart` and shall report the interrupted run through `health` and `run_status` (R37).
- R55. The trainer shall never call a bash script; every PC-side path shall go through the
  standard library's path handling (T1).

### I. Vault and guide (A2; round 2, 4a; T6)

- R56. `docs/systems/bot-training.md` shall be rewritten on the cycle branch to describe
  what is built: rung 0, the stamp, `make bot-eval`, the play-out worker and its requests,
  the run store, the MCP verbs and the PC setup, with the architecture note left as the
  design record; the task is blocked until Ben has committed or discarded his working-copy
  edits to that file.
- R57. `CLAUDE.md`'s layout table shall gain a `trainer/` row (T6), and the Makefile
  `trainer-test`.

### J. The gate and verification

- R58. `make check` shall be green at the end of every task, gdUnit under the 30 s budget,
  with both workers typed-strict under `parse` and lint.
- R59. `make sweep` under `random` shall stay clean, and the seed-1 golden
  (`seed=1 decks=combo/graveyard bot=random winner=1 wins=3-4 rounds=7 end=wins
  actions=265`) shall be unchanged: nothing here alters live play.
- R60. The cycle shall be proven by text lines, not screenshots (engine and tooling cycle):
  A1 on the Mac (R13, R23, R31, the suite names), A2 on the PC from the Mac over MCP and
  SSH (round 2, 3b): `make trainer-test` green on both machines, `sync_code`, a bounded
  `start_run`, `run_status` to the end, `stop_run` then `resume_run` across a forced stop
  with the digest unchanged (R36), `get_report`, `sample_positions`, a second run on the
  same config and run seed giving the same digest, and one sampled position labelled again
  by the Mac's play-out worker giving the PC's values.

## Clarifications (Ben, 2026-11-07)

Ben's request, in his words: "Spec it", after the orchestrator proposed cycle A as "a match
worker, a stamp, and a yardstick ladder that starts from random. It also adds the play-out
entry point, the run store, and the MCP server with its bearer token."

| # | Question | Answer |
|---|---|---|
| C1 | Round 1 Q1, scope: (a) one spec, two milestones (A1 this branch: stamp, match worker, play-out worker, rollout entry, Windows-safe scripts, ladder from `random`, proven on the Mac; A2 `cycle-11b-bot-trainer`: `trainer/`, run store, MCP server with token, `sync_code`, runner scripts, first dataset on the PC); (b) one milestone; (c) A1 only now | 1a |
| C2 | Round 1 Q2, the ladder with only `random`: (a) `random` is rung 0 at stamp `r7-…`, the stamp rebuilt both sides, `make bot-eval` drives again (`random` vs `random` as selftest), the yardstick is the top rung, candidates are every legal commit sampled to K, rollouts by `random`, no new bot; (b) plus a scripted `power` bot as rung 1 and rollout policy | 2a |
| C3 | Round 1 Q3, the old tooling: (a) delete `evolve.py`, `calibrate.py`, their tests, `bot-train.sh`, the `bot-train` and `bot-calibrate` targets and the ladder's Calibration block; keep `driver.py eval`, `sprt.py`, `records.py`, `bot-eval`, `bot-selftest` Windows-safe; (b) keep inert; (c) port too | 3a |
| C4 | Round 1 Q4, MCP verbs: (a) nine (`health`, `sync_code`, `start_run`, `run_status`, `stop_run`, `resume_run`, `list_runs`, `get_report`, `sample_positions`), `get_artifact` in cycle B; (b) the five named for cycle A; (c) all ten | 4a |
| C5 | Round 2 Q1, starting the MCP server on the PC: (a) through the runner queue, the runner and grant scripts tracked under `trainer/windows/`, Ben re-points the task once at a stable copy outside the worktree; (b) the spike's untracked runner as is; (c) a second scheduled task | 1a |
| C6 | Round 2 Q2, labelled decisions: (a) commits only, prompts answered by the rollout policy; (b) commits and prompts | 2a |
| C7 | Round 2 Q3, verification: (a) Mac first then PC with a Mac trainer run; (b) A1 proven on the Mac, A2's end-to-end proof on the PC only (no Mac trainer run); (c) plus a PC reboot mid-run | 3b. Read as: `make trainer-test` still runs on both machines (T6 says it is runnable on both), but the end-to-end labelled run is proven on the PC only |
| C8 | Round 2 Q4, the bots guide: (a) a rewrite task at the end of A2 on the cycle branch, blocked until Ben has committed or discarded his working-copy edits; (b) a new guide beside the old; (c) nothing this cycle | 4a |
| C9 | T06 review (DC-16), S1: R17 and plan P6 disagreed with each other and with the code on which per-card records follow a permuted identity. (a) Amend R17 and P6 to the implemented rule: Memory and created-card definitions are keyed by card id and move with the identity; Board changes, statuses and `chosen` stay with the row slot, because moving them would put a status on a different visible slot and change the seat's view; (b) change the code to re-key everything through the permutation | 1a (Ben, 2026-11-07) |
| C10 | `/cycle test` DC-16 code review: F1, candidates were played on different deals (the determinization seed held the candidate index), so a label's ranking carried the deal noise and a move's value depended on `k`; F5, the match worker seeded bots by seat only, so `random` against `random` replayed every seat-swapped game as a mirror and the rung-0 check could not see a seat bias. (a) fix both before the merge (R28 and P10 amended: the determinization seed is `derive_seed(label_seed, [det_index])`; the worker seeds a bot off its seat by its side), re-pin and redo rung 0; (b) F1 only; (c) neither | 1a (Ben, 2026-11-07) |
| C11 | After DC-16 (amends C5): Ben wants the PC maintained over SSH, not at the PC. C5's one-time re-point of the `trainer-runner` task needs admin (a non-admin SSH session cannot change a scheduled task), but the task only launches `C:\Users\trainer\spike\runner.ps1`, a file `trainer` owns. (a) Replace that file over SSH with a shim that runs the stable copy `C:\Users\trainer\trainer\runner.ps1` (refreshed by `sync_code`), and swap the live runner by a queued job that starts the new one and stops the old; no admin step in A2, `SETUP.md` keeps admin steps for a fresh PC only; (b) keep the re-point | 1a (Ben, 2026-11-07) |

Defaults stated by the interrogator, open to Ben's veto at sign-off (none changes a
decision above): a hidden card's identity is permuted within its owner's hidden set, so a
card never changes Owner in a determinization (R17); created cards (Dross, Twin copies) in
hidden zones are hidden like any other and carry their definition with them; the rollout
action cap is the harness's 2000; run defaults are 2,000 positions, `k` 8, 16
determinizations, batch 25, 16 workers on the PC, rollout and generator `random`, the
seeded pairing; the stop and resume test forces the stop with `stop_run`, not a reboot
(C7); `sync_code` inline bundles are meant for incremental bundles, a full bundle goes to
the inbox over SSH; the `bot-trainer` entry is added to the repository's `.mcp.json` with
`${BOT_TRAINER_URL}` and the bearer header from `${BOT_TRAINER_TOKEN}`, so a machine without
the variables simply shows the server disconnected; the dataset digest is SHA-256 over the
label shards' lines with timing fields removed.

## Scenarios

- **Given** the shipped `cards.json`, `decks.json` and `crew.json`, **when** the engine and
  the driver compute the stamp, **then** both print the same `r7-<16 hex>` string, and
  editing one byte of `crew.json` changes it on both (R1).
- **Given** `make bot-eval` with `a=random b=random`, **when** it runs, **then** it ends
  PASS or CAP with a win rate within 0.05 of 0.500, `rejected=0` implied by `exit=0`, and
  the summary line carries `stamp=r7-…` (R11, R13).
- **Given** seed 1 (combo against graveyard) replayed to seat 1's first Round 3 commit,
  **when** a determinized copy is built for seat 1 with seed 7, **then** seat 1's hand, both
  rows' revealed cards, both Piles and the Crew are unchanged, seat 0's hand holds the same
  count of cards drawn from seat 0's unseen cards, and the real match's full state is equal
  before and after (R16, R17, R19).
- **Given** that position and a candidate commit, **when** 16 rollouts run under `random`
  with determinization seeds derived from label seed 11, **then** the 16 values are the
  same on a second run and on the PC, each is a win, draw or loss of ±1000 plus a tiebreak
  within ±40, and the pinned seed-1 rollout value and action count hold (R20 to R23).
- **Given** a play-out worker, **when** it reads a `play` request for seed 1 and a `label`
  request for the position above with `k` 8, **then** it answers each with the same `id`,
  the stamp and the microseconds spent; a second worker given the same lines answers with
  the same values; a `label` whose prefix does not replay answers with an error line and
  stays alive (R25 to R29, R31).
- **Given** a run of 200 positions started over MCP, **when** `stop_run` is called at
  position 90 and `resume_run` later, **then** `run_status` shows stopped then running then
  done, at most 25 labels were redone, and `get_report`'s digest equals a never-stopped
  run's on the same config and run seed (R35, R36, R47, R49).
- **Given** the trainer service restarted by the runner after a reboot with a run marked
  running, **when** `health` is called, **then** it names the run as interrupted and
  `resume_run` continues it (R37, R54).
- **Given** a request with no bearer header, **when** it reaches the server, **then** the
  reply is 401 and no tool runs; with the right token, `health` answers in under a second
  (R41, R44).
- **Given** a bundle of the cycle branch scp'd to the inbox, **when** `sync_code` names it
  and its head commit, **then** the training worktree is on that commit, the import ran and
  the reply carries the new stamp; while a run is active the same call is refused (R51,
  R52).
- **Given** `sample_positions` with `n` 3, **when** Ben reads the reply, **then** each
  position shows the seat's hand by card name and its candidates by card names and slots,
  best first, with values and counts (R50).

## Data touched

- New: `docs/specs/cycle-11-bot-trainer/{spec,plan,tasks}.md`; one row in
  [[specs/specs-moc]]; by its tasks: the engine's stamp and rollout modules and their
  suites, `godot/tools/` with the match worker, its records helper and the play-out worker,
  `trainer/` (package, tests, `windows/`), the `trainer-test` Makefile target, a
  `bot-trainer` entry in `.mcp.json`, two variables in `.env.example`, a `trainer/` row in
  `CLAUDE.md`.
- Rewritten: `scripts/bot/driver.py`, `records.py` (Windows-safe, no weights), their tests,
  `scripts/bot-eval.sh`, the Makefile's `bot-*` targets, [[planning/bot-ladder]] (rungs,
  rule, no Calibration block), `docs/systems/bot-training.md` (A2, R56).
- Deleted: `scripts/bot/evolve.py`, `calibrate.py`, `test_evolve.py`, `test_calibrate.py`,
  `scripts/bot/fixtures/matrix_weights.json`, `scripts/bot-train.sh`.
- Read only: `godot/engine/` except the new modules; `docs/rules/*`; `docs/planning/*`
  except the ladder; the archive.
- Appended at verification by the orchestrator: DC rows in [[planning/cycles]], rung-0 row
  in [[planning/bot-ladder]].
- Never: `docs/.obsidian/`; `godot/addons/*`; `.env`; `godot/.godot/`; `godot/reports/`;
  the archive; Ben's uncommitted edits to `docs/systems/bot-training.md` in the main
  checkout (R56 waits for him); the token, anywhere but `.env` and the PC's token file.

## Definition of done

Milestone A1 (this branch):

- [x] `make check` green, gdUnit under 30 s; golden unchanged; `make sweep` clean (R58, R59).
- [x] Engine and driver stamps equal, `r7-…` (R1), and a suite pins that a changed data
      file changes the stamp.
- [x] `make bot-selftest` green on the Mac; `make bot-eval` with `random` against `random`
      PASS or CAP near 0.500 with `exit=0` (R13, R14); the deleted tooling is gone (R14).
- [x] The rollout suite passes: determinized copy preserves the view and the real state,
      hidden identities move with their records, same seeds same values, the seed-1 pin
      (R16 to R23); `grep -rn Rollout godot/engine/bot godot/board godot/main.gd` is empty
      (R24).
- [x] The play-out worker answers `hello`, `play`, `label`, an error and `quit`; two runs of
      a 20-position request file on 1 and 8 workers print the same digest (R25 to R31);
      rollouts per second per worker recorded in the cycle row (R30).
- [x] Ladder note: rungs table with `random` at rung 0 and the new stamp, the promotion and
      re-stamp rules, no Calibration block (R3 to R6).
- [x] Constitution Check passes (see plan); spec, plan and tasks signed off by Ben and
      committed before implementation begins.

Milestone A2 (`cycle-11b-bot-trainer`):

- [x] `make trainer-test` green on the Mac and over SSH on the PC (R39).
- [x] From the Mac over MCP against the PC: `health`; `sync_code` of the cycle branch;
      `start_run` of a bounded run; `run_status` to done; `stop_run` then `resume_run` on a
      second run with the digest equal to the first; `get_report`; `sample_positions`
      readable by Ben; a request without the token answered 401 (R40 to R52, R60).
- [x] One sampled position labelled again by the Mac's play-out worker gives the PC's
      values (R23, R60).
- [x] The runner, shim, grant and start scripts and `SETUP.md` are tracked; the task's file
      is the shim, swapped in over SSH with no admin step (C11); after a service restart an
      interrupted run is reported (R53, R54).
- [x] `docs/systems/bot-training.md` rewritten (after Ben's working-copy edits are settled),
      `CLAUDE.md` has the `trainer/` row, the cycle rows carry the PC's rollouts per second
      (R56, R57). (DC-17: rollouts per second recorded; the guide and the `CLAUDE.md` row went
      to Backlog with T13, cycle-11 T13, Ben 3b 2026-11-07.) (done at DC-20 T19, cycle-11 T13)
