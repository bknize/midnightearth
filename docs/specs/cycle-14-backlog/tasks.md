---
type: tasks
tags: [tasks, cycle-14-backlog, engine, board, pvp, trainer, tooling, vault]
status: approved
related: ["[[specs/cycle-14-backlog/spec]]", "[[specs/cycle-14-backlog/plan]]", "[[planning/phase-1-tech-stack]]", "[[planning/bot-ladder]]", "[[planning/cycles]]", "[[decisions/0002-one-branch-per-cycle]]"]
created: 2026-11-08
updated: 2026-11-09
uid: b651b610-2175-4087-a64f-d9651ab6a9ca
supersedes:
---

# Tasks: Cycle 14 — backlog sweep

Derived from [[specs/cycle-14-backlog/plan|plan]]. Numbered, dependency-ordered,
independently reviewable. Each task names its area, the Linear issues it closes (the
project's issues already exist; `/exercise` maps, and creates only where "new" is written),
its acceptance check and who does it. `implementer` edits code in a worktree;
`implementer-engine` takes anything under `godot/engine/`; `reviewer` reads a diff and
returns findings; `orchestrator` runs `make check`, drives the Godot MCP, the PC and Linear.

Two tasks that edit the same file never share a wave (R51). Every implementer brief carries
the typed-strict traps and the rule that no `.gd` file names both a class and its subclass.

| # | Task | Area | Closes | Depends on | Acceptance check | Who | Status |
|---|---|---|---|---|---|---|---|
| 1 | Canon rulings (R45, P17): Q11 gains the exhausted-Batch sentence (R1); GY01 and GY09 notes say a random Condemn may land on a protected or already-marked card and miss (R3); CT07 note says a face-down card is not levelled (R4); glossary Uses entry says the engine enforces limited uses (R6) and the Dross/created-card entries gain the lifetime (R9, R10); `systems/game-loop` and `systems/cards-crew-decks` match | vault | new (`type/docs`) | – | the six places read as the spec's C1–C4, C6, C9; `obsidian-cli vault=docs unresolved` nothing new | implementer | done |
| 2 | Trigger queue: the resumed draw after exhaust (R1, R2, P1); the B-22 leftovers (dead `_answer` branch, `_resume_after` gap, empty-prompt bot answer, double cost scan, seat count) | engine | B-23, B-22 | – | `test_trigger_queue.gd`: a Batch whose first trigger refills the Deck and whose rest is exhausted still draws; `spent` unchanged by the draw; golden lines unchanged at this merge | implementer-engine | done |
| 3 | Created cards, Level and the random miss (P2, P3, P5, P6, P9): `record_created` requires an Owner, `to_pile` loses the seat-0 fallback, `CardDef.lifetime` (`until_piled` default, `match`), `CARD_EXPIRED` and `forget_created`, Dross expires; `level_power` skips face-down cards; Fuse and Immolator emit `protected`/`already_marked` fizzles per blocked pick; `TURN_STARTED` carries `free_first`; `RULES_VERSION` 9; the B-24 remainder (created cards recorded twice; `replace_def` fixtures-only). The orchestrator fills the golden lines and the sweep summary at the merge, in this task's commit (the one re-pin, R49) | engine | B-20, B-28, B-26, B-24, engine half of B-31 | – | `test_abilities_graveyard.gd`: Bastion pick fizzles `protected`, RNG stream equal; `test_abilities_control.gd`: face-down 7 stays 7, levelled after reveal; `test_abilities_disruption.gd` + `test_match_cards.gd`: a discarded Dross expires (event, no Pile entry, Dredger shuffles none back), a `match` lifetime card is filed; `test_card_db.gd`: bad lifetime is a load error, every shipped card has no `lifetime` key; `test_action_log.gd`: a rules-8 log is refused; `test_turn_flow.gd`: `free_first` in `TURN_STARTED`; `BotStamp.current()` = `r9-857b165d5a5d755e` | implementer-engine | done |
| 4 | Crew: `uses` enforced for cards and Crew (R6, R7, P4); `CREW_FIRED` (R13, P7); Crew `STATS_CHANGED` through `Abilities.stats_changed` with `cause` (R14, P8); `_holder_if_hidden` deleted so a pending-Commit card's events reach the first seat only (R15); the leak-suite case | engine | B-27, B-29, B-55, engine half of B-32 | 2, 3 | `test_crew_abilities.gd`: fixture Crew `uses` 1 fires once, `uses_left` 0, `CREW_FIRED` payload keys; `test_abilities_evergreen.gd` (fixture card `uses` 1 per Turn); shipped pool and Crew assert `uses` 0; `test_pvp_leaks.gd`: Crew stats change on a pending card reaches seat 0 only; golden lines and sweep summary unchanged from task 3 | implementer-engine | done |
| 5 | Determinization pins card ids only (R18, P10) | engine | B-44 | – | `test_rollout.gd`: a paused entry carrying an amount equal to a live card id is not pinned; the seed-1 rollout pin unchanged; label digest of the 20-position file recorded in the task notes | implementer-engine | done |
| 6 | Engine rules cleanup list (B-25), behaviour-preserving (P14) | engine | B-25 | 4 | every engine suite green; golden lines and sweep summary unchanged; `git diff master -- godot/engine/data` empty | implementer-engine | done |
| 7 | Engine loaders and dispatch cleanup (B-30): verb dispatch written once, a verb coverage test, JSON loader boilerplate shared, `CrewDef`/`CardAbility` helpers (P14) | engine | B-30 | 6 | the new verb coverage test lists every verb once; loaders' error strings unchanged (`test_card_db.gd`, `test_crew_pool.gd`, `test_deck_list.gd`); golden lines and sweep summary unchanged | implementer-engine | done |
| 8 | Review of the rules wave (tasks 2–7) against spec A, B and the hidden-information rules; findings to Ben as a costed list | engine | new (`type/review`) | 7 | findings file with blockers / should-fix / nits; no blocker open before task 9 | reviewer | done |
| 9 | Stamp chores (R12, R48, R50, P6, P18): review fixes from task 8; `make sweep` (`p99_us` < 10000, summary recorded); `linear_weights.json` re-stamped to r9; `make bot-eval` `random` vs `random` PASS at r9; rung-0 row in `planning/bot-ladder`, r8 rows marked; `test_pvp_log.gd` and the leak sweep green; the cycle branch synced to the PC, `make check` there, server redeployed (`server.log` shows `stamp=r9-857b165d5a5d755e`); Ben told night 2 may start | engine, tooling, vault | new (`type/chore`, ladder provision) | 8 | the `bot-eval` line ends `stamp=match exit=0`; the ladder row and the server log line quoted in the task notes | orchestrator | done |
| 10 | Board feedback bugs (R19–R25, P11): deck note survives later steps; `CREW_FIRED` → `CREW_FIRE` beat; free first card shown and cleared; halted tap does not lift; abandoned PVP board clears the note and disables Pass and Commit; `CARD_EXPIRED` fly-off; new `test_card_lift.gd` | scene | B-33, B-31, B-07, board half of B-32, board sub-item of B-52 | 9 | `test_board_steps*.gd` cases for each mapping; `test_card_lift.gd` runs; `test_board_hud_text.gd` free-first text; seed-1 board line equals the task 3 pin | implementer | done |
| 11 | PVP server polish (R26–R33, P12): `MatchRoom.fail` on the act path; wrong-code cooling; monotonic timers; disconnect flapping cap; oversized resync closes with reason; `server.log` rotation; rejoined bot `actions=`; header-only orphan scan | server, net | B-52 (remaining sub-items) | 9 | `test_match_room.gd`, `test_room_registry.gd`, `test_match_server_loopback.gd`, `test_pvp_log.gd` cases for each; `grep get_unix_time godot/server godot/net` matches only `pvp_log.gd`; loopback suite time unchanged within 1 s | implementer | done |
| 12 | Board core cleanup (B-34, P14): split step dispatch, seven flags to a phase enum, `BoardStep` fields, `PILE_SHOW`, `exit_to` enum, behaviour-preserving | scene | B-34 | 10 | all `test_board_*.gd` suites green unchanged in count; seed-1 board line equals the pin; no file names both `MatchSource` and `MatchDriver` | implementer | done |
| 13 | Board UI cleanup (B-35, P14): zone string compares, launch args read once, strip ownership and the rest of the list | scene | B-35 | 12 | `test_deck_strip_layout.gd`, `test_lift_layout.gd`, `test_staging*.gd`, `test_prompt_host.gd` green; seed-1 board line equals the pin | implementer | done |
| 14 | Tooling (R41, R42, P16): `worktree-sweep.sh` keeps unmerged and foreign worktrees and saves screenshots before removal; the edit hook finds `~/.local/bin` and prints its missing-gdlint line | tooling | B-10, B-06 | – | a planted unmerged worktree and a planted foreign worktree print `kept`; a merged one with a planted `.png` prints `removed` and the file is in `reports/screenshots/<branch>/`; the hook with an empty PATH prints the line and exits 0 | implementer | done |
| 15 | Trainer Python (R34, R35, R38, R39, P13): B-51's Python items including the pair weighting recorded in the fit record; B-40 explicit flush; B-48 orchestrator check over SSH noted in the task | trainer | B-51 (Python half), B-40, B-48 | 9 (C14: before night 2) | `trainer/tests` green on the Mac; `make fit` on two recorded runs prints the weighting; the play-out worker answers with stdout unbuffered under `python -u` and without; B-48 numbers written in the task notes | implementer | done |
| 16 | Trainer Godot side of B-51 (P13): `LinearBot` pass candidate; `match_worker` `_weights_stamp` | engine, tools | B-51 (Godot half) | 9 (C14: before night 2) | `test_linear_bot.gd` pass candidate case; `make sweep BOT=linear` counters recorded (not pinned), `p99_us` recorded; `test_match_worker_records.gd` stamp case | implementer-engine | done |
| 17 | Trainer code items of B-50 (R36, R37, P13): store-owned run state machine, `ActiveRun`, restart loop, one Godot path, one sampling path, shared stamp module, `argparse`, run-row counters, pool_key memo, feature base, power iteration on XtX; protocol, hello, label reply and schema untouched | trainer | B-50 (code items; the protocol and schema items stay in cycle-14-backlog under the training milestone) | 15 | `trainer/tests` green on the Mac and the PC; the 20-position label digest before and after, equal or explained; `trainer/server.py` hello and label reply byte-identical; `fits` schema unchanged | implementer | done |
| 17a | Rules 10 (R53, R54, C15): three tied sudden-death Rounds in a row end the Match in a stalemate; `RULES_VERSION` 10, stamp pins, canon and the stalemate result text. The orchestrator re-stamps `linear_weights.json`, adds the rung-0 row, runs both sweeps and redeploys the PC server (T09's steps at r10) | engine, vault | cycle-14 T17a | 17 | `test_round_match_end.gd`: two ties go on, the third ends `stalemate` on the higher total, equal totals draw, a won third Round ends `sudden_death`; `test_action_log.gd`: a rules-9 log is refused; `make sweep BOT=linear` passes; the `bot-eval` line ends `stamp=match exit=0` at `r10-857b165d5a5d755e` | implementer-engine | done |
| 18 | Tests (R43, R44, P15): one `_typed()` helper in `tests/fixtures/typed.gd`, the 22 copies gone; gdUnit under 30 s with every suite still run, using the orchestrator's per-suite timings | tests | B-36, B-57 | 7, 11, 13, 16, 17a | `grep -c "func _typed" godot/tests` is 1; `make check` test stage reports the gdUnit time under 30 s; case count equal to the sum before the task | implementer | done |
| 19 | Documents (R46, R47, P17): `docs/systems/bot-training.md` rewritten from the code; `CLAUDE.md` rows for `trainer/`, `godot/title/`, `scripts/pc/`; cycles.md "Planned next" refreshed; DoD boxes in finished specs ticked or superseded; the two Ben boxes listed for the orchestrator | vault | cycle-11 T13, B-58 | 17 | the guide names no deleted tool (`bot-train`, `bot-calibrate`, levels); `obsidian-cli vault=docs unresolved` and `orphans` nothing new; the two boxes decided by Ben and recorded in B-58 | implementer | done |
| 20 | Verification (below) | all | new (`type/verification`) | 18, 19 | all boxes below | orchestrator | done |

## Verification task (always last)

Task 20, owned by the orchestrator, on the cycle worktree with the editor open there:

- [ ] `make check` exits 0; the gdUnit time printed under 30 s (R43); case count recorded.
- [ ] `Engine smoke:`, `test_full_match`, `test_match_driver` and a headless `--fixed-fps 60
  --autoplay` run print the one seed-1 line pinned at task 3 (R49); `make sweep` summary
  equals the task 9 record, `p99_us` under 10000.
- [ ] Rulings: the gdUnit cases of tasks 2–4 named in the row, plus a seed scan showing a
  `CARD_EXPIRED`, a `CREW_FIRED` with `uses_left`, and a `protected` fizzle in the event log
  text.
- [ ] `test_pvp_leaks.gd` and `test_pvp_leaks_sweep` pass with the pending-Commit Crew case
  (R15).
- [ ] Board, seed 1 in the editor: a deck note still showing two steps later (R19); a Crew
  lift-and-settle on a `CREW_FIRED` (R20); the HUD free-first state at a Lantern Turn and a
  cost-7 drop on budget 4 accepted (R21); a tap on a card after the match ends does not lift
  it (R22). One `take_screenshot` each for the deck note, the Crew beat and the free first
  card.
- [ ] PVP: a headless `--join` bot joins the editor's room, the bot leaves, the board shows
  "Match abandoned" with Leave only and no connection note, Pass and Commit disabled (R24);
  one `take_screenshot`. The PC server's `server.log` shows `stamp=r10-857b165d5a5d755e`
  and a rotated file after a planted size (R31).
- [ ] Trainer: `trainer/tests` green on the Mac and the PC; the label digest before task 15
  and after task 17 recorded with its explanation; the PC synced once before night 3.
- [ ] Tooling: the three planted worktree cases and the hook line (task 14) rerun by the
  orchestrator.
- [ ] Ladder and cycles: the r9 rung-0 row present; the DC-20 row written in
  [[planning/cycles]] with the `bot-eval` line, the sweep summary and the case count.
- [ ] `obsidian-cli vault=docs unresolved` and `orphans` report nothing new.
- [ ] Linear: every DC-20 issue Done at `/cycle test`; cycle-13 T10, cycle-13 T11, B-54, B-56 and
  the B-50 protocol items remain in cycle-14-backlog under the training milestone.

Four screenshots in all (P7: one per visible feature); nothing else is captured.

## Commit plan

The whole cycle is one changeset on the branch `cycle-14-backlog` (`CLAUDE.md`, Git;
[[decisions/0002-one-branch-per-cycle]]), cut from `master` (cc2b695) at `/spec`. It carries
the spec (`spec: cycle-14-backlog`), the Linear write-back (`exercise: cycle-14-backlog`), one
commit per task (`dc-20: Tnn <task title>`; task 3's commit includes the orchestrator's one
re-pin), the task 8 review fixes, the task 9 ladder and stamp chores, and the verification
outcome, each message ending with the Co-Authored-By line the session provides. From
`/cycle plan` the branch lives in its own worktree and the main checkout returns to `master`.
When task 20 passes, `/cycle test` runs `/code-review medium` then `/simplify` on the diff,
merges the branch into `master` with `git merge --no-ff`, and sweeps the worktree with the
fixed `scripts/worktree-sweep.sh`. Nothing is committed directly on `master`.

