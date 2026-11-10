---
type: plan
tags: [plan, cycle-14-backlog, engine, board, pvp, trainer, tooling, vault]
status: approved
related: ["[[specs/cycle-14-backlog/spec]]", "[[specs/cycle-14-backlog/tasks]]", "[[planning/phase-1-tech-stack]]", "[[planning/bot-ladder]]", "[[planning/cycles]]", "[[decisions/0002-one-branch-per-cycle]]", "[[decisions/0004-review-tools-in-the-cycle]]", "[[decisions/0005-match-server-for-pvp]]", "[[specs/cycle-13-bot-trainer-b/plan]]", "[[specs/cycle-12-multiplayer/plan]]"]
created: 2026-11-08
updated: 2026-11-09
uid: 5879f247-28b2-4618-b63d-84d7477e1b10
supersedes:
---

# Plan: Cycle 14 — backlog sweep

Implements [[specs/cycle-14-backlog/spec|spec]]. This is the HOW. The spec is clarified
(C1–C12, no open marker). Nothing here changes a requirement; where a requirement left a
choice, the choice is in the decisions table so tasks.md can point at it.

## Stack mapping

| Area | Involved | Approach and tooling |
|---|---|---|
| Godot scenes/UI | yes | `godot/board/` (board.gd, board_steps.gd, board_step.gd, card_lift.gd, board_hud.gd, match_driver.gd, match_source.gd, deck_strip.gd and the UI cleanup list); plain Theme (D7); verified through the Godot MCP on the cycle worktree |
| Engine (godot/engine + tests) | yes | typed GDScript, seeded RNG, replayable action log (D4); `RULES_VERSION` 9; gdUnit4 cases in the existing per-module suites plus `test_card_lift.gd` on the board side |
| Shaders/cards | no | |
| Server and net | yes | `godot/server/` and `godot/net/` per ADR 0005; loopback suites; the PC redeploy over SSH with `scripts/pc/pvp-server.cmd` |
| Bots, tools, trainer | yes | `godot/engine/bot/`, `godot/tools/match_worker.gd`, `trainer/` (Python, its own tests), `scripts/bot/` |
| Tooling/scripts | yes | `scripts/worktree-sweep.sh`, the edit hook under `scripts/hooks/`; Bash with `set -uo pipefail` |
| Vault/docs | yes | `docs/rules/*`, `docs/systems/*`, `docs/planning/cycles.md` and `bot-ladder.md`, finished specs' DoD boxes, `CLAUDE.md` rows; link audit with `obsidian-cli` |
| Linear | yes | existing project cycle-14-backlog; milestone `DC-20 backlog-sweep`; `/exercise` maps tasks onto the existing issues (one task may close several) and creates issues only for the few tasks with no issue of their own |

## Decisions (the HOW the spec left open)

| # | Topic | Decision |
|---|---|---|
| P1 | Resumed draw after exhaust (R1, R2) | `TriggerQueue._exhaust` ends by calling the same "then draw" continuation the normal drain end calls, with the pending resumed-draw record it already keeps; the draw is not a queue entry and does not touch `spent`. One case in `test_trigger_queue.gd` builds a Batch whose first trigger refills the Deck and whose later entries are exhausted. |
| P2 | Random Condemn miss (R3) | `_fuse` and `_immolate` keep their RNG draws over the whole row. When `Statuses.mark_exit` returns false the pick emits `TRIGGER_FIZZLED` with reason `REASON_PROTECTED` (new constant) or `REASON_ALREADY_MARKED` for that single pick; the ability itself still counts as fired. No RNG change, so the golden line does not move for this. |
| P3 | Level on face-down cards (R4, R5) | `level_power` returns early when `card` itself is not revealed; the lowest-Power scan is unchanged. One case per row side in `test_abilities_control.gd`. |
| P4 | `uses` (R6, R7) | Cards: `Abilities` checks `_used(state, card)` against `ability.uses` before firing and records a `KIND_USED` Board change with the ability's scope (`turn`, `row`, `match`, the shipped format's `CardAbility.SCOPES`); Crew: `MatchState.crew_uses[seat][slot]` counts down from `CrewDef.initial_uses()`, `UNLIMITED` never counts. Tests use fixture pools (`fixtures/`), never the shipped JSON, so the stamp hash is untouched. |
| P5 | Created cards (R8–R11) | `MatchCards.record_created(def, owner)` requires `owner` in 0..1 and `create()` passes the creating seat; `to_pile` loses the `owner = 0` fallback (an ownerless id is a programming error surfaced by a failing test, not a runtime print). `CardDef.lifetime: String` with values `until_piled` (default) and `match`, key `lifetime`, read only when `created` is true; any other value is a load error (`ERR_LIFETIME`). `FORMAT_VERSION` stays 5 and `cards.json` is not edited. `to_pile` of a created `until_piled` card calls `MatchCards.forget_created(card)` and emits `CARD_EXPIRED {owner, card, from, reason}` (public) instead of `CARD_DISCARDED`. `MatchEvent.Kind` gains `CARD_EXPIRED`; `MatchEvent.dict` parsers updated. SeatView pile counts follow. |
| P6 | Rules version and the one re-pin (R12, R49) | `MatchRules.RULES_VERSION = 9` lands in the created-cards task (T03), the only task that is certain to move seed 1 (combo/graveyard: Litter makes Dross). At T03's merge the orchestrator fills the golden lines (`test_full_match.gd`, `test_match_driver.gd`, the `Engine smoke:` and board seed-1 lines) and the sweep summary, in T03's commit. No other task may move them (R52). |
| P7 | CREW_FIRED (R13) | Emitted by `CrewAbilities.fire` after the verb resolves, payload `{seat, slot, crew, moment, verb, uses_left}` with `uses_left` -1 for unlimited; public. `TRIGGER_FIRED` with `crew` stays. The board's `board_steps.gd` maps `CREW_FIRED` to `BoardStep.Kind.CREW_FIRE` and keeps dropping the Crew `TRIGGER_FIRED`. |
| P8 | Crew stats and hidden holder (R14, R15) | `CrewAbilities._holder_if_hidden` is deleted; Crew stats changes go through `Abilities.stats_changed(ctx, card, permanent, cause)` (the helper gains a `cause` argument, default the ability's card), which uses `Abilities.hidden_holder` and its `state.pending` check. `test_pvp_leaks.gd` gains a seeded case in which a Crew changes the stats of a card in `pending` and asserts no seat-1 event names it. |
| P9 | Free first (R16, R21) | `TURN_STARTED` payload gains `free_first: bool` per seat (array of two); `board_steps.gd` fills `BoardStep.free_first` from it; `board_hud` shows the existing free-first state. Event only, no log change. |
| P10 | Determinization pins (R18) | `Rollout._pinned` pins `card` and `subject` of each entry and the prompt's source as today; for a paused drain it pins only the kept entry's `card` and `subject` and the ids under keys the engine documents as card lists (`chosen`, `cards`), never every whole number. `test_rollout.gd` case: a paused entry carrying an amount equal to a live card id is not pinned. |
| P11 | Board fixes (R19–R25) | `board.gd._apply` calls `hud.set_piles` only on steps that change a Pile (or `set_piles` keeps `note_deck` until `note_deck` is cleared by its own timer); `may_act()` is false when `_closed`; `_on_match_closed` clears the connection note; the tap path in `card_lift`/`board.gd` checks `_halted` where the drag path does; `CARD_EXPIRED` maps to a fly-off step without a Pile arrival. `test_card_lift.gd` is a new suite over `card_lift.gd` and the halted paths. |
| P12 | PVP polish (R26–R33) | `MatchRoom.fail` called from the act path's error branch; a per-address wrong-code counter in `RoomRegistry` (5 misses per 60 s, 60 s cooling, constants); every timer in `match_server.gd`, `match_room.gd` and `net_client.gd` reads `Time.get_ticks_msec()`, `Time.get_unix_time_from_system` only in `pvp_log.gd` timestamps; `_disconnects` cap 5 per seat per match; a resync over 1 MiB closes the client with `resync_too_large`; `server.log` rotates at 8 MiB keeping 3; the bot client's `actions=` counter resets on rejoin; `PvpLog.scan_orphans` reads the header line only (the writer puts the header first). Proven by `test_match_room.gd`, `test_room_registry.gd`, `test_match_server_loopback.gd` and `test_pvp_log.gd`. |
| P13 | Trainer (R34–R39) | B-51's Python items and B-40 in one task; the Godot-side items of B-51 (`LinearBot` pass candidate, `match_worker` `_weights_stamp`) in a separate `implementer-engine` task because `LinearBot` is engine code and it moves the `linear` sweep counters (recorded, not pinned); B-50's code items in a third task after the first; protocol, hello, label reply and schema untouched (R37). The label digest of the committed 20-position file is run before T15 and after T17 on the Mac and written in the task notes. B-48 is an orchestrator check over SSH at T15. |
| P14 | Cleanup (C12) | Each cleanup issue is one task whose only acceptance is unchanged behaviour: the golden lines, the sweep summary, and the suites of the files it touches. The structural items of B-34 (step dispatch split, seven flags to a phase enum, `exit_to` enum, BoardStep field pruning, PILE_SHOW) are done inside the one board-core task after the board bug task merges, so the bug fixes are not written twice. |
| P15 | Tests and the budget (R43, R44) | The `_typed()` helper lives in `godot/tests/fixtures/typed.gd` (a static helper, no `class_name` clash: the file names one class only). The budget task runs last among code tasks; the orchestrator gives the implementer the per-suite timings from `godot/reports/test.log`, and the implementer trims the slowest suites (fewer seeds in sweeps that are not the 50-seed sweep, shared fixtures, no sleeps) without dropping a case. |
| P16 | Tooling (R41, R42) | `worktree-sweep.sh` lists worktrees with `git worktree list --porcelain`, removes only those whose branch is `git merge-base --is-ancestor` of the target and whose path lies under this checkout's `.worktrees` (or the path the Makefile uses), and before removal moves `*.png` under the worktree's `godot/reports/` and screenshot folder to `reports/screenshots/<branch>/` in the main checkout. The edit hook prepends `~/.local/bin` to PATH and prints `edit hook: gdlint not found, lint skipped` when it is still missing. |
| P17 | Documents (R45–R48) | The canon task writes the rulings in `docs/rules/` and the two systems guides; the docs task rewrites `docs/systems/bot-training.md` from the code after the trainer wave, adds the three `CLAUDE.md` rows, refreshes "Planned next", ticks or supersedes DoD boxes and lists the two Ben boxes for the orchestrator's question. The ladder row and the cycles row are the orchestrator's at T09 and T20. |
| P18 | Night 2 and the PC (R40, R50) | After T09 the orchestrator syncs the cycle branch commit to the PC, redeploys the server (`stamp=r9-857b165d5a5d755e` in `server.log`) and tells Ben night 2 may start. T17a repeats this at `r10-857b165d5a5d755e` (C15). Nothing is synced to the PC during a night; the trainer wave (T15–T17) runs before night 2 (C14). DC-20 closes at T20 regardless of nights 2 and 3. |

## Interfaces and contracts

Engine events (all public unless stated; event-only, action log unchanged, R17):

- `CREW_FIRED {seat: int, slot: int, crew: String, moment: String, verb: String, uses_left: int}`
  (`uses_left` -1 unlimited).
- `CARD_EXPIRED {owner: int, card: int, from: String, reason: String}` (the created card has
  left the Match).
- `TURN_STARTED` gains `free_first: Array[bool]` (one per seat).
- `TRIGGER_FIZZLED` reasons gain `protected` and `already_marked` (one per blocked random
  pick, carrying `card` of the pick's target).
- `STATS_CHANGED` from a Crew: the same keys and order as from a card ability, `cause` the
  Crew id; routed by `Abilities.hidden_holder` (pending Commit → first seat).

Engine API:

- `Abilities.stats_changed(ctx, card: int, permanent: bool, cause: String = "") -> void`.
- `MatchCards.record_created(def: CardDef, owner: int) -> int` (owner required),
  `MatchCards.forget_created(card: int) -> void`, `MatchCards.lifetime_of(card) -> String`.
- `CardDef.lifetime: String` (`until_piled` | `match`), `CardDef.LIFETIMES`.
- `MatchRules.RULES_VERSION = 10` (9 at T03, 10 at T17a, C15); `BotStamp.current()` = `r10-857b165d5a5d755e`.
- `MatchRules.SUDDEN_DEATH_TIES = 3`. Every sudden-death Round that did not end the Match was tied, so `MatchEngine._stalled()` reads the count from `round_number`; `MatchState` gains no field.
- `Rollout._pinned` contract: pins card ids only (P10).

Board:

- `BoardStep.Kind.CREW_FIRE` fed by `CREW_FIRED`; a new `BoardStep.Kind.CARD_EXPIRE` (card,
  owner) played as a fly-off; `BoardStep.free_first` set from `TURN_STARTED`.
- `Board.may_act() -> bool` false while `_closed`, `_halted` or paused.

Server:

- Refusal reasons gain `resync_too_large` and `too_many_codes`; `server.log` rotation files
  `server.log.1` … `server.log.3`.

Tooling:

- `scripts/worktree-sweep.sh [--into <branch>] [--apply]` exit 0; prints `kept <path>
  (unmerged)` / `kept <path> (foreign)` / `removed <path>`; screenshots moved before removal.
- Edit hook prints `edit hook: gdlint not found, lint skipped` on stderr when applicable.

Trainer:

- Protocol v2 unchanged; `fit` record gains `pair_weighting` (name and parameter); CLI
  through `argparse` with the same verbs and flags as today.

## Data model

- `MatchState`: `crew_uses` (exists) now counted down; `card_state.changes` gains
  `KIND_USED` entries with a scope; no new serialized field. `MatchCards._created_owner`
  always set; created ids removed on expiry. Serialization (`to_dict`/`from_dict`) covers the
  removal (an expired id is absent).
- Action log: `rules_version` 9; format unchanged; a rules-8 log is refused at replay.
- Card pool: optional `lifetime` key on `created` cards; shipped files untouched; stamp
  `r9-857b165d5a5d755e`.
- Weights: `godot/engine/bot/data/linear_weights.json` `stamp` re-stamped by hand to r9
  (ladder plan P18 precedent).
- Ladder: a rung-0 row at r9; r8 rows marked as measuring nothing at the current stamp.
- Trainer store: no schema change (R37); fit records gain one JSON field.

## Waves

| Wave | Tasks | Runs when | Notes |
|---|---|---|---|
| 1 rules | T01 ∥ T02 ∥ T03 ∥ T05 → T04 → T06 → T07 → T08 (review) → T09 (stamp chores) | first | T02 and T04 both edit `trigger_queue.gd`, so T04 waits; T03 carries `RULES_VERSION` 9 and the one re-pin; T09 syncs the PC and night 2 may start |
| 2 sweep | T10 → T12 → T13 (board chain) ∥ T11 (PVP) ∥ T14 (tooling) | after T09 | no PC sync during a night |
| 3 trainer | T15 ∥ T16 → T17 | before night 2 (C14) | label digest before and after |
| 3b rules 10 | T17a | after T17, before T18 (C15) | stamp chores and PC redeploy at r10 |
| 4 close | T18 (tests, budget) → T19 (docs) → T20 (verification) | after waves 2 and 3 | T18 is last among code tasks (it touches many suites) |

## Constitution Check

| Rule | Verdict | Note |
|---|---|---|
| All project GDScript is fully typed (`parse` promotes typed-GDScript warnings to errors) | PASS | every brief carries the typed-strict traps; no file names both a class and its subclass (the MatchSource + MatchDriver lesson, P15) |
| Engine is deterministic: seeded RNG, no wall-clock, no node access, serializable action log (D4) | PASS | P2 keeps the RNG draws; the server moves to monotonic ticks (P12) but is outside the engine; no engine print |
| `make check` gate contract: import, lint, parse, boot, test all green; Godot exit codes never trusted | PASS | the golden lines are red only inside T03's own merge, filled by the orchestrator before the commit (P6) |
| Implementers never run Godot or `make check`; only the orchestrator verifies | PASS | pins, sweep, bot-eval, redeploy and screenshots are orchestrator tasks (T09, T20) |
| Notes carry P5 frontmatter and `[[path/from/vault/root]]` links | PASS | three notes plus the MOC row; canon notes edited keep theirs |
| No edits under the do-not-touch list | PASS | `godot/addons/`, `docs/.obsidian/`, `.env`, `godot/.godot/`, `godot/reports/`, the archive untouched |
| Secrets only in `.env`; `.mcp.json` placeholders; no token in chat, notes, commits or Linear | PASS | the PC sync and redeploy use the existing SSH and token paths |
| Each changeset on its own branch, one commit per task, nothing on `master`, `--no-ff` merge | PASS | `cycle-14-backlog` from `/spec` to `/cycle test`; one `dc-20: Tnn` commit per task |
| Review tools at `/cycle test` (ADR 0004) | PASS | `/code-review medium` then `/simplify` on the whole diff at `/cycle test`; T08 reviews the rules wave early because night 2 trains on it |
| Ladder provision after an engine change (bot-ladder R5) | PASS | T09: `make sweep`, `make bot-eval` rung 0, ladder row, cycles row |

**Result:** PASS.

## Risks and mitigations

- A later wave-1 task moves the golden line after T03's re-pin (R52) → the orchestrator
  diffs the seed-1 event stream, and the task is fixed, not the pin.
- `uses` enforcement reaches a shipped card by accident (a `uses` parsed as non-zero) → a
  test asserts every shipped card and Crew has `uses` 0 and the sweep counters are unchanged
  apart from the Dross expiry.
- `CARD_EXPIRED` breaks a consumer that counts Piles (SeatView, bot features, PVP log replay,
  the board) → the engine task lists every `CARD_DISCARDED` consumer and the leak sweep plus
  `test_pvp_log.gd` replays are rerun at T09.
- The pending-Commit routing change hides an event the board relied on for the committer's
  own view → the first seat still receives it (`hidden_holder` returns `first_seat`); the
  board seat-0 run at T20 checks the commit flip and stats.
- Protocol drift between the Mac and the PC during the trainer wave → R37 forbids protocol
  and schema changes; T15–T17 run only between nights; the PC is re-synced once before
  night 3.
- The board core refactor (B-34) and the bug fixes collide → the chain T10 → T12 → T13 is
  strictly serial, and `test_board_steps*.gd` plus the seed-1 board line pin behaviour.
- The 30 s gdUnit budget tightens as suites grow → T18 runs last with measured timings; if a
  suite cannot be trimmed without dropping a case, the orchestrator asks Ben rather than
  waiving silently.
- The worktree sweep touches another session's worktree → P16 keeps anything outside this
  checkout's worktree folder and anything unmerged; a planted foreign worktree is the test.
- `/exercise` creates duplicates → the tasks table names every NSC id a task closes, so
  `/exercise` maps rather than creates, and creates only for T01, T08, T09, T18's budget
  half and T20 if no issue exists.

## Open questions

- None for the design. The two B-58 Definition-of-done boxes that need Ben are put to him
  at `/cycle plan` as one plain-text question (R47).
