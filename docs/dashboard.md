---
cssclasses: [dashboard]
type: moc
tags: [moc, dashboard, planning]
status: evergreen
related: ["[[planning/cycles]]", "[[planning/backlog]]", "[[specs/specs-moc]]", "[[decisions/0007-no-ticket-tracker]]"]
created: 2026-11-09
updated: 2026-11-09
uid: 5d0c3b1e-7a52-4c8e-9f41-2b6e0a7d9c13
supersedes:
---

# Dashboard

Written by `make dashboard` from every spec's `tasks.md`, [[planning/cycles]] and
[[planning/backlog]] ([[decisions/0007-no-ticket-tracker]]). Do not edit it: change the
source note and run `make dashboard` again.

| Dev cycles done | Tasks done | Tasks to do | Open backlog items |
|---|---|---|---|
| 21 / 21 | 208 / 210 | 2 | 7 |

## Cycles

> [!success]- [[specs/cycle-14-backlog/spec|Cycle 14 — backlog sweep]] · 21 / 21
> <progress value="21" max="21"></progress> DC-20 · [[specs/cycle-14-backlog/spec|spec]] · [[specs/cycle-14-backlog/plan|plan]] · [[specs/cycle-14-backlog/tasks|tasks]]
>
> - **DC-20 backlog-sweep** · 2026-11-08 → 2026-11-09 · done, merged on Ben's 2a
>
> | # | Task | Area | Who | Status |
> |---|---|---|---|---|
> | T01 | Canon rulings | vault | implementer | <span class="st st-done">done</span> |
> | T02 | Trigger queue | engine | implementer-engine | <span class="st st-done">done</span> |
> | T03 | Created cards, Level and the random miss | engine | implementer-engine | <span class="st st-done">done</span> |
> | T04 | Crew: `uses` enforced for cards and Crew (R6, R7, P4); `CREW_FIRED` (R13, P7); Crew `STATS_CHANGED` through… | engine | implementer-engine | <span class="st st-done">done</span> |
> | T05 | Determinization pins card ids only | engine | implementer-engine | <span class="st st-done">done</span> |
> | T06 | Engine rules cleanup list | engine | implementer-engine | <span class="st st-done">done</span> |
> | T07 | Engine loaders and dispatch cleanup | engine | implementer-engine | <span class="st st-done">done</span> |
> | T08 | Review of the rules wave | engine | reviewer | <span class="st st-done">done</span> |
> | T09 | Stamp chores | engine, tooling, vault | orchestrator | <span class="st st-done">done</span> |
> | T10 | Board feedback bugs | scene | implementer | <span class="st st-done">done</span> |
> | T11 | PVP server polish | server, net | implementer | <span class="st st-done">done</span> |
> | T12 | Board core cleanup | scene | implementer | <span class="st st-done">done</span> |
> | T13 | Board UI cleanup | scene | implementer | <span class="st st-done">done</span> |
> | T14 | Tooling (R41, R42, P16): `worktree-sweep.sh` keeps unmerged and foreign worktrees and saves screenshots before… | tooling | implementer | <span class="st st-done">done</span> |
> | T15 | Trainer Python | trainer | implementer | <span class="st st-done">done</span> |
> | T16 | Trainer Godot side of B-51 | engine, tools | implementer-engine | <span class="st st-done">done</span> |
> | T17 | Trainer code items of B-50 | trainer | implementer | <span class="st st-done">done</span> |
> | T17a | Rules 10 (R53, R54, C15): three tied sudden-death Rounds in a row end the Match in a stalemate;… | engine, vault | implementer-engine | <span class="st st-done">done</span> |
> | T18 | Tests (R43, R44, P15): one `_typed()` helper in `tests/fixtures/typed.gd`, the 22 copies gone; gdUnit under 30… | tests | implementer | <span class="st st-done">done</span> |
> | T19 | Documents (R46, R47, P17): `docs/systems/bot-training.md` rewritten from the code; `CLAUDE.md` rows for… | vault | implementer | <span class="st st-done">done</span> |
> | T20 | Verification | all | orchestrator | <span class="st st-done">done</span> |
>
> **Verification: 0 of 11 checked**
>
> - ☐ `make check` exits 0
> - ☐ …
> - ☐ Rulings: the gdUnit cases of tasks 2–4 named in the row, plus a seed scan showing a
> - ☐ `test_pvp_leaks.gd` and `test_pvp_leaks_sweep` pass with the pending-Commit Crew case
> - ☐ Board, seed 1 in the editor
> - ☐ PVP: a headless `--join` bot joins the editor's room, the bot leaves, the board shows
> - ☐ Trainer: `trainer/tests` green on the Mac and the PC; the label digest before task 15
> - ☐ Tooling: the three planted worktree cases and the hook line (task 14) rerun by the
> - ☐ Ladder and cycles
> - ☐ `obsidian-cli vault=docs unresolved` and `orphans` report nothing new.
> - ☐ Linear: every DC-20 issue Done at `/cycle test`; cycle-13 T10, cycle-13 T11, B-54, B-56 and

> [!todo]+ [[specs/cycle-13-bot-trainer-b/spec|Cycle 13 — bot trainer, cycle B]] · 9 / 11
> <progress value="9" max="11"></progress> DC-18 · [[specs/cycle-13-bot-trainer-b/spec|spec]] · [[specs/cycle-13-bot-trainer-b/plan|plan]] · [[specs/cycle-13-bot-trainer-b/tasks|tasks]]
>
> - **DC-18 bot-trainer-b** · 2026-11-08 → 2026-11-08 · done on what was merged
>
> | # | Task | Area | Who | Status |
> |---|---|---|---|---|
> | T01 | Features. `godot/engine/bot/bot_features.gd` | engine, tests | implementer-engine | <span class="st st-done">done</span> |
> | T02 | Weights file, the `linear` bot, the registry. `bot_weights.gd` | engine, tests, data | implementer-engine | <span class="st st-done">done</span> |
> | T03 | Workers and the sweep. Protocol v2 in `playout_protocol.gd` and `playout_handler.gd` | tooling (godot/tools, tests/sweep) | implementer | <span class="st st-done">done</span> |
> | T04 | Driver, `bot-eval.sh`, Makefile. `driver.py eval --weights-a/--weights-b` forwarded to the worker,… | tooling (scripts, Makefile) | implementer | <span class="st st-done">done</span> |
> | T05 | Trainer: features in the store, weights in the config. `config.py` (`rollout_weights`, `generator_weights`),… | trainer | implementer | <span class="st st-done">done</span> |
> | T06 | The learner, `fit` and `get_artifact`. `trainer/fit.py` | trainer | implementer | <span class="st st-done">done</span> |
> | T07 | Review. Read T01 to T06 against the spec | review | reviewer | <span class="st st-done">done</span> |
> | T08 | Verification on the Mac and the PC smoke. Mac | verification | orchestrator | <span class="st st-done">done</span> |
> | T09 | Iteration 0. Per plan P16 | verification (PC night 1) | orchestrator | <span class="st st-done">done</span> |
> | T10 | Iterations 1 and 2. Per plan P16 | verification (PC nights 2–3) | orchestrator | <span class="st st-todo">todo</span> |
> | T11 | Promotion and close. If the best weights pass both gates | verification | orchestrator | <span class="st st-todo">todo</span> |
>
> **Verification: 3 of 5 checked**
>
> - ☑ `make check` exits 0 after every task
> - ☐ End-to-end proof by lines
> - ☐ Rung 1 in [[planning/bot-ladder]]
> - ☑ No screenshot
> - ☑ `obsidian-cli vault=docs unresolved` reports nothing new.

> [!success]- [[specs/cycle-12-multiplayer/spec|Cycle 12 — PVP through a match server on the testing PC]] · 14 / 14
> <progress value="14" max="14"></progress> DC-19 · [[specs/cycle-12-multiplayer/spec|spec]] · [[specs/cycle-12-multiplayer/plan|plan]] · [[specs/cycle-12-multiplayer/tasks|tasks]]
>
> - **DC-19 multiplayer** · 2026-11-07 → 2026-11-08 · done: `/cycle test` (2026-11-08): `/code-review medium` found 5, no blockers; Ben 1a: three should-fixes fixed in a16e56b (a WebSocket heartbeat plus a 5 s ping…
>
> | # | Task | Area | Who | Status |
> |---|---|---|---|---|
> | T01 | Serialization helpers.… | engine (adjacent) | implementer-engine | <span class="st st-done">done</span> |
> | T02 | Protocol and codec. `godot/net/net_protocol.gd`, `net_codec.gd` | net | implementer | <span class="st st-done">done</span> |
> | T03 | The room and the registry. `godot/server/match_room.gd`, `room_registry.gd`, `room_codes.gd` | server | implementer-engine | <span class="st st-done">done</span> |
> | T04 | The log writer. `godot/server/pvp_log.gd` | server | implementer | <span class="st st-done">done</span> |
> | T05 | The socket layer and the server entry. `godot/server/match_server.gd`, `server_main.gd` | server, tooling | implementer | <span class="st st-done">done</span> |
> | T06 | The client and the remote source. `godot/net/net_client.gd`, `remote_match_source.gd`, `net_defaults.gd` | net | implementer | <span class="st st-done">done</span> |
> | T07 | The board on a `MatchSource`. `godot/board/match_source.gd` | scene | implementer | <span class="st st-done">done</span> |
> | T08 | Title screen, identity, waiting screen, one-column picker. `godot/title/title_screen.tscn/.gd`,… | scene | implementer | <span class="st st-done">done</span> |
> | T09 | PVP wired end to end, and the bot client. `main.gd` drives `RemoteMatchSource` for Host and Join, shows the wa… | scene, net | implementer | <span class="st st-done">done</span> |
> | T10 | The end-to-end loopback suite. `test_pvp_loopback.gd` | tests | implementer | <span class="st st-done">done</span> |
> | T11 | ADR 0005 and the record. `docs/decisions/0005-match-server-for-pvp.md` | vault | implementer (vault); orchestrator for `CLAUDE.md` and `.claude/` | <span class="st st-done">done</span> |
> | T12 | Deploy to the PC. The orchestrator over SSH as `trainer` | deployment | orchestrator (Ben for the admin steps) | <span class="st st-done">done</span> |
> | T13 | Review. The reviewer over the cycle's diff in plan P19's order | review | reviewer | <span class="st st-done">done</span> |
> | T14 | Verification. See below. | verification | orchestrator | <span class="st st-done">done</span> |
>
> **Verification: 9 of 11 checked**
>
> - ☑ `make check` exits 0 on the cycle branch
> - ☑ The server on the PC answers
> - ☑ Editor on the cycle worktree
> - ☑ …
> - ☑ Over SSH: the match's file exists under `C:\Users\trainer\pvp-logs\<date>\`,…
> - ☑ Hardening probes against the live server
> - ☑ Reconnect: the bot client killed mid-match and restarted with `--join=<code>` within
> - ☑ Abandonment: the bot client killed and not restarted; after two minutes the editor
> - ☐ Ben's checklist complete
> - ☐ Three screenshots
> - ☑ The cycle's row in [[planning/cycles]]

> [!success]- [[specs/cycle-11-bot-trainer/spec|Cycle 11 — bot trainer, cycle A]] · 14 / 14
> <progress value="14" max="14"></progress> DC-16, DC-17 · [[specs/cycle-11-bot-trainer/spec|spec]] · [[specs/cycle-11-bot-trainer/plan|plan]] · [[specs/cycle-11-bot-trainer/tasks|tasks]]
>
> - **DC-16 bot-trainer-a1** · 2026-11-07 → 2026-11-07 · done: `/cycle test` (2026-11-07): `/code-review medium` found 7, no blockers; Ben 1a 2a 3a (spec C10): fixed F1 (every candidate of a label played on the same d…
> - **DC-17 bot-trainer-a2** · 2026-11-07 → 2026-11-07 · done: `/cycle test` (2026-11-07): `/code-review medium` found 9, no blockers; Ben 1a 2a 3a: fixed 1–6 in one implementer dispatch (23f895a: the `hours` cap ends…
>
> **Milestone A1: the Mac side**
>
> | # | Task | Area | Who | Status |
> |---|---|---|---|---|
> | T01 | The stamp. Restore `godot/engine/bot/bot_stamp.gd` over the three data files | engine, tooling | implementer-engine | <span class="st st-done">done</span> |
> | T02 | The match worker. `godot/tools/match_worker.gd` and `match_worker_records.gd` with the cycle 7 contract minus… | tooling (godot/tools), tests | implementer | <span class="st st-done">done</span> |
> | T03 | The driver on both platforms, the old tooling gone. `driver.py` keeps `eval` and `selftest` | tooling (scripts, Makefile) | implementer | <span class="st st-done">done</span> |
> | T04 | The rollout entry and determinization.… | engine, tests | implementer-engine | <span class="st st-done">done</span> |
> | T05 | The play-out worker. `godot/tools/playout_protocol.gd` | tooling (godot/tools), tests | implementer | <span class="st st-done">done</span> |
> | T06 | Review A1. Read the diffs of T01 to T05 against the spec's A to D | review | reviewer | <span class="st st-done">done</span> |
> | T07 | Verification A1. `make check` | verification | orchestrator | <span class="st st-done">done</span> |
>
> **Milestone A2: the PC side (`cycle-11b-bot-trainer`)**
>
> | # | Task | Area | Who | Status |
> |---|---|---|---|---|
> | T08 | Trainer package skeleton, seeds, store, config. `trainer/__init__.py`, `__main__.py` | trainer, tooling | implementer | <span class="st st-done">done</span> |
> | T09 | Farm and run loop. `farm.py` | trainer | implementer | <span class="st st-done">done</span> |
> | T10 | MCP server, verbs, token. `server.py` | trainer | implementer | <span class="st st-done">done</span> |
> | T11 | `sync_code` and the Windows scripts. `sync.py` | trainer, windows | implementer | <span class="st st-done">done</span> |
> | T12 | Review A2. Read T08 to T11 against E to H | review | reviewer | <span class="st st-done">done</span> |
> | T13 | The bots guide and the layout row. Rewrite `docs/systems/bot-training.md` from the code and the spec | vault | implementer | <span class="st st-done">done</span> |
> | T14 | Verification A2. On the Mac | verification | orchestrator | <span class="st st-done">done</span> |
>
> **Verification: 4 of 4 checked**
>
> - ☑ `make check` exits 0
> - ☑ End-to-end proof by lines
> - ☑ No screenshot
> - ☑ `obsidian-cli vault=docs unresolved` reports nothing new.

> [!success]- [[specs/cycle-10-review-tools/spec|Cycle 10 — review tools in the cycle, and one cleanup pass]] · 10 / 10
> <progress value="10" max="10"></progress> DC-15 · [[specs/cycle-10-review-tools/spec|spec]] · [[specs/cycle-10-review-tools/plan|plan]] · [[specs/cycle-10-review-tools/tasks|tasks]]
>
> - **DC-15 review-tools** · 2026-11-07 → 2026-11-07 · done: verified (T10). ADR 0004 and the standing `/cycle test` step 0 (`/code-review medium` then `/simplify`, findings triaged to Ben) are in; the reviewer keep…
>
> | # | Task | Area | Who | Status |
> |---|---|---|---|---|
> | T01 | ADR 0004 `docs/decisions/0004-review-tools-in-the-cycle.md` per plan | vault | implementer | <span class="st st-done">done</span> |
> | T02 | The standing step | tooling | implementer | <span class="st st-done">done</span> |
> | T03 | Baseline for the pass | tooling | orchestrator | <span class="st st-done">done</span> |
> | T04 | Chunk C1 engine core | engine | orchestrator | <span class="st st-done">done</span> |
> | T05 | Chunk C2 engine rules, same procedure as T04 | engine | orchestrator | <span class="st st-done">done</span> |
> | T06 | Chunk C3 engine content, same procedure as T04 | engine | orchestrator | <span class="st st-done">done</span> |
> | T07 | Chunk C4 board core, same procedure as T04 but without the sweep | scene | orchestrator | <span class="st st-done">done</span> |
> | T08 | Chunk C5 board cards and input, same procedure as T07 | scene | orchestrator | <span class="st st-done">done</span> |
> | T09 | Chunk C6 tests | tests | orchestrator | <span class="st st-done">done</span> |
> | T10 | Verification | all | orchestrator | <span class="st st-done">done</span> |
>
> **Verification: 7 of 7 checked**
>
> - ☑ `scripts/check.sh` exits 0 on the cycle branch
> - ☑ `make sweep`
> - ☑ `git log master..cycle-10-review-tools --oneline` shows the T01/T02 commits, the T03
> - ☑ `git diff master -- godot/engine/data godot/addons scripts` is empty.
> - ☑ …
> - ☑ Every `/code-review` finding across C1 to C6 is either in a commit or in a Backlog
> - ☑ `obsidian-cli vault=docs unresolved` and `orphans` report nothing new

> [!success]- [[specs/cycle-9-rules-v2/spec|Cycle 9 — rules v2 in the engine]] · 18 / 18
> <progress value="18" max="18"></progress> DC-13, DC-14 · [[specs/cycle-9-rules-v2/spec|spec]] · [[specs/cycle-9-rules-v2/plan|plan]] · [[specs/cycle-9-rules-v2/tasks|tasks]]
>
> - **DC-13 rules-v2** · 2026-11-06 → 2026-11-06 · verified (T11), awaiting `/cycle test` for the `master` merge: T01–T10 in eight waves plus review fixes and T11 fixes; gate green in 67 s, 599 cases, none skipp…
> - **DC-14 rules-v2-content** · 2026-11-06 → 2026-11-06 · done: verified (T18); Ben read both guides (2026-11-07). Waves: (1) T12, T13, T15 first pass (with B-18, B-19); (2) T14, T15 reconciled; (3) T16; (4) T17 review…
>
> **Milestone A: rules machinery, evergreen, Greed and Ramp (DC-13)**
>
> | # | Task | Area | Who | Status |
> |---|---|---|---|---|
> | T01 | The strip (P16; R70–R75): delete every file the plan's "Deleted" list names under `engine/bot/`,… | engine, board, tooling-free | implementer-engine | <span class="st st-done">done</span> |
> | T02 | Anatomy, data and loaders | engine | implementer-engine | <span class="st st-done">done</span> |
> | T03 | Match structure and the walking total | engine | implementer-engine | <span class="st st-done">done</span> |
> | T04 | Statuses, exit marks and movement | engine | implementer-engine | <span class="st st-done">done</span> |
> | T05 | The trigger queue | engine | implementer-engine | <span class="st st-done">done</span> |
> | T06 | Card abilities A | engine | implementer-engine | <span class="st st-done">done</span> |
> | T07 | Crew A (P4, P13; R18, R62): `CrewAbilities` with Tallyman, Void, Engineer, Navigator, Captain and Dredger;… | engine | implementer-engine | <span class="st st-done">done</span> |
> | T08 | Random bot v2, sweep and golden | engine | implementer-engine | <span class="st st-done">done</span> |
> | T09 | Board A (P17; R76–R83): `BoardCard` faces with Power and "×1.25"/"+0.50", badge words from `statuses`;… | board, ui | implementer | <span class="st st-done">done</span> |
> | T10 | Review of T01–T09 against the spec and the Constitution Check, with attention to determinism | all | reviewer | <span class="st st-done">done</span> |
> | T11 | Verification A | all | orchestrator | <span class="st st-done">done</span> |
>
> **Milestone B: the other four strategies, Crew and the guides (DC-14)**
>
> | # | Task | Area | Who | Status |
> |---|---|---|---|---|
> | T12 | Combo and Disruption abilities | engine | implementer-engine | <span class="st st-done">done</span> |
> | T13 | Graveyard and Control abilities | engine | implementer-engine | <span class="st st-done">done</span> |
> | T14 | Crew B, decks and data | engine | implementer-engine | <span class="st st-done">done</span> |
> | T15 | Board B: Dross and created cards in the fan, the Walk-end multiply shown in the tally, the `LOOK` mark on a lo… | board, ui | implementer | <span class="st st-done">done</span> |
> | T16 | The guides: rewrite [[systems/game-loop]] and [[systems/cards-crew-decks]] to describe rules version 7 as buil… | vault | implementer | <span class="st st-done">done</span> |
> | T17 | Review of T12–T16 against the spec, with attention to created cards | all | reviewer | <span class="st st-done">done</span> |
> | T18 | Verification B | all | orchestrator | <span class="st st-done">done</span> |
>
> **Verification: 14 of 16 checked**
>
> - ☑ `make check` exits 0
> - ☑ The data diff
> - ☑ …
> - ☑ Pin the seed-1 golden under `random` in `GOLDEN`
> - ☑ `make sweep` under `random`
> - ☑ Faces and the total. On a seed where a Mult card Scores on a fractional total
> - ☑ Discard-down. With the human seat holding more than its Hand size after a Commit
> - ☑ Exit and Pile. Flare Scores, then at turn end flies to its Owner's Pile
> - ☑ Engine scan on a seed
> - ☑ No GDScript warning in the editor run
> - ☑ `make check` exits 0 with gdUnit under 30 s
> - ☑ Silenced. On a seed where Eclipse resolves against the human seat
> - ☑ Dross. Litter puts three Dross in the human seat's fan
> - ☐ Both-seat prompt
> - ☐ The two guides describe rules 7, the canon notes say built, Ben has read both guides
> - ☑ `obsidian-cli vault=docs unresolved` and `orphans` report nothing new

> [!success]- [[specs/ruleset-v2/spec|Ruleset v2 — hardened vocabulary, resolution chart, new card set]] · 8 / 8
> <progress value="8" max="8"></progress> DC-12 · [[specs/ruleset-v2/spec|spec]] · [[specs/ruleset-v2/plan|plan]] · [[specs/ruleset-v2/tasks|tasks]]
>
> - **DC-12 ruleset-v2** · 2026-11-06 → 2026-11-06 · done: design-only vault cycle, five waves. Seven canon notes under `docs/rules/` (glossary, rules-v2, resolution chart, crew-v2, 90-card cards-v2, six test deck…
>
> | # | Task | Area | Who | Status |
> |---|---|---|---|---|
> | T01 | Glossary. Write `docs/rules/glossary.md` | vault | implementer | <span class="st st-done">done</span> |
> | T02 | Rules v2. Write `docs/rules/rules-v2.md` | vault | implementer | <span class="st st-done">done</span> |
> | T03 | Resolution chart. Write `docs/rules/resolution.md` | vault | implementer | <span class="st st-done">done</span> |
> | T04 | Crew v2. Write `docs/rules/crew-v2.md` | vault | implementer | <span class="st st-done">done</span> |
> | T05 | Cards v2. Write `docs/rules/cards-v2.md` | vault | implementer | <span class="st st-done">done</span> |
> | T06 | Test decks, MOC and home. Write `docs/rules/test-decks.md` | vault | implementer | <span class="st st-done">done</span> |
> | T07 | Vocabulary and consistency review. Read all seven notes. Report every rules sentence whose noun or verb does n… | vault | reviewer | <span class="st st-done">done</span> |
> | T08 | Verification | vault | orchestrator | <span class="st st-done">done</span> |
>
> **Verification: 6 of 7 checked**
>
> - ☑ `make check` exits 0
> - ☑ `git status` shows only `docs/rules/`, `docs/home.md`, `docs/specs/ruleset-v2/` and
> - ☐ Every canon note has P5 frontmatter,…
> - ☑ The spec's definition-of-done list is checked line by line against the notes.
> - ☑ No screenshot
> - ☑ `obsidian-cli vault=docs unresolved` and `obsidian-cli vault=docs orphans` report
> - ☑ Ben has read each of the seven notes and said so

> [!success]- [[specs/cycle-8-ramp-bounce-crew/spec|Cycle 8 — ramp, bounce, Crew]] · 14 / 14
> <progress value="14" max="14"></progress> DC-09, DC-11 · [[specs/cycle-8-ramp-bounce-crew/spec|spec]] · [[specs/cycle-8-ramp-bounce-crew/plan|plan]] · [[specs/cycle-8-ramp-bounce-crew/tasks|tasks]]
>
> - **DC-09 ramp-bounce** · 2026-11-04 → 2026-11-05 · done: 5 build tasks in four waves (T01 with T05, then T02, T03, T04), a review (T06) and its fixes (Ben 1c: the blocker, four should-fixes and the nits, in an e…
> - **DC-11 crew** · 2026-11-05 → 2026-11-05 · done (milestone B; cycle-7 T16, the overnight training, stays open for Ben): waves T08 with B-13, T09, T10 with T12 (the orchestrator added…
>
> **Milestone A: Bloom, Echo and card memory**
>
> | # | Task | Area | Who | Status |
> |---|---|---|---|---|
> | T01 | Card memory and effective cost | engine | implementer-engine | <span class="st st-done">done</span> |
> | T02 | Bloom: `BloomEffects.grow` and the nine grow verbs (P4), the uses countdown (P7) with `EFFECT_FIRED.uses_left`… | engine | implementer-engine | <span class="st st-done">done</span> |
> | T03 | Echo: `EchoEffects` (P6): the three return verbs through `return_marked`, `unreveal_at_turn_end` and… | engine | implementer-engine | <span class="st st-done">done</span> |
> | T04 | Tables and bot | engine | implementer-engine | <span class="st st-done">done</span> |
> | T05 | Board A (P16): `BoardCard.show_entry` with `CostLabel` effective cost and `GrownMark`, hand faces from… | board | implementer | <span class="st st-done">done</span> |
> | T06 | Review of T01–T05 against the spec and the Constitution Check, with attention to hidden information | all | reviewer | <span class="st st-done">done</span> |
> | T07 | Verification A | all | orchestrator | <span class="st st-done">done</span> |
>
> **Milestone B: Crew**
>
> | # | Task | Area | Who | Status |
> |---|---|---|---|---|
> | T08 | Crew data: `crew.json` with the eight Crew (P12), `CrewDef`, `CrewPool`, `decks.json` v2 with `crew` lists and… | engine | implementer-engine | <span class="st st-done">done</span> |
> | T09 | Optional prompts and the decline | engine | implementer-engine | <span class="st st-done">done</span> |
> | T10 | Crew triggers and abilities | engine | implementer-engine | <span class="st st-done">done</span> |
> | T11 | Bot B and stamp | engine | implementer-engine | <span class="st st-done">done</span> |
> | T12 | Board B (P17): `CrewLine` per side from `MATCH_STARTED.crew`, badges from `crew_uses`, `CREW_FIRE` step and pu… | board, ui | implementer | <span class="st st-done">done</span> |
> | T13 | Review of T08–T12 against the spec and the Constitution Check, with attention to the queue | all | reviewer | <span class="st st-done">done</span> |
> | T14 | Verification B | all | orchestrator | <span class="st st-done">done</span> |
>
> **Verification: 15 of 15 checked**
>
> - ☑ `make check` exits 0
> - ☑ Re-pin the seed-1 golden under the four-deck seeded pairing in `GOLDEN_TUNED`
> - ☑ Re-pin the frozen-fixture stamp digest in `test_bot_stamp.gd`
> - ☑ 50-seed sweep over four decks
> - ☑ Cycle 7 rerun provision as restated
> - ☑ Memory. On a seed where Sapling scores twice
> - ☑ Bounce. Echo flips face down at turn end in its slot and reveals again next walk
> - ☑ Ben has reviewed the Bloom and Echo tables and any row change is in `cards.json`, the
> - ☑ No GDScript warning in the editor run
> - ☑ `make check` exits 0 with gdUnit under 30 s
> - ☑ Crew line. Both sides show three Crew with names
> - ☑ Decline. On a Salvager prompt the eligible hand cards glow, the reader shows
> - ☑ Turn start. With Echo
> - ☑ Bot vs bot on every deck pairing and Crew ends with no rejected action
> - ☑ `obsidian-cli vault=docs unresolved` and `orphans` report nothing new.

> [!success]- [[specs/cycle-7-bot-players/spec|Cycle 7 — bot players]] · 17 / 17
> <progress value="17" max="17"></progress> DC-08, DC-10 · [[specs/cycle-7-bot-players/spec|spec]] · [[specs/cycle-7-bot-players/plan|plan]] · [[specs/cycle-7-bot-players/tasks|tasks]]
>
> - **DC-08 bot-players** · 2026-11-04 → 2026-11-04 · done (milestone A): 12 issues in four waves (W1 T01 + T08, W2 T02 + T03, W3 T04 + T06, W4 T05 + T07 + T09), a review pass and verification. Gate green in 82 s,…
> - **DC-10 bot-training** · 2026-11-05 → 2026-11-05 · done (milestone B less the trained weights, which move to T16 at the end of DC-11): waves (1) T12 `preview_pair`, T14 the trainer, B-14 the sweep split; (2) T13…
>
> **Milestone A: the tuned bot, the interface, the references, the harness**
>
> | # | Task | Area | Who | Status |
> |---|---|---|---|---|
> | T01 | Bot interface and registry | engine | implementer-engine | <span class="st st-done">done</span> |
> | T02 | Frozen reference | engine | implementer-engine | <span class="st st-done">done</span> |
> | T03 | Candidates, bound, evaluator, weights and stamp | engine | implementer-engine | <span class="st st-done">done</span> |
> | T04 | `TunedBot` (P9): top-K previews, evaluator, push, prompts and set prompts, `decision_rng` tags; registry… | engine | implementer-engine | <span class="st st-done">done</span> |
> | T05 | Sweep and stamp line | engine (tests) | implementer-engine | <span class="st st-done">done</span> |
> | T06 | Worker (P17): `tools/bot_worker.gd` with the CLI, pair sets with seat and deck swaps, timing, replay check, th… | tooling | implementer | <span class="st st-done">done</span> |
> | T07 | Launcher and driver flags | board, ui | implementer | <span class="st st-done">done</span> |
> | T08 | Driver eval | tooling | implementer | <span class="st st-done">done</span> |
> | T09 | Ledger and process | vault, tooling | orchestrator | <span class="st st-done">done</span> |
> | T10 | Review of T01–T09 against the spec and the Constitution Check, with attention to hidden information | all | reviewer | <span class="st st-done">done</span> |
> | T11 | Verification A | all | orchestrator | <span class="st st-done">done</span> |
>
> **Milestone B: training, the matrix bot, calibration**
>
> | # | Task | Area | Who | Status |
> |---|---|---|---|---|
> | T12 | Joint preview | engine | implementer-engine | <span class="st st-done">done</span> |
> | T13 | `HandSampler`, `RegretMatching`, `MatrixBot` | engine | implementer-engine | <span class="st st-done">done</span> |
> | T14 | Driver train | tooling | implementer | <span class="st st-done">done</span> |
> | T15 | Driver calibrate | tooling | implementer | <span class="st st-done">done</span> |
> | T16 | (Moved to the end of DC-11, decision 1a; DC-10 verifies the loop with short runs only.) The training run:… | tooling | orchestrator | <span class="st st-dropped">dropped</span> |
> | T17 | Review of T12–T16 against the spec and the Constitution Check, with attention to hidden information through… | all | reviewer | <span class="st st-done">done</span> |
> | T18 | Verification B | all | orchestrator | <span class="st st-done">done</span> |
>
> **Verification: 9 of 13 checked**
>
> - ☑ `make check` exits 0, test stage under 30 s of gdUnit time
> - ☑ Re-pin the seed-1 golden under the tuned bot
> - ☑ `--bot=greedy` reproduces cycle 6's golden line
> - ☑ Worker smoke
> - ☑ Stamp provision
> - ☑ MCP on seed 1 against the tuned bot
> - ☑ `obsidian-cli vault=docs unresolved` and `orphans` report nothing new
> - ☐ `make check` exits 0
> - ☐ `make bot-eval`
> - ☑ One match from the training run replays from its log to an equal state
> - ☐ `make bot-train HOURS=0.2 LABEL=smoke` resumes from a checkpoint after an
> - ☐ The calibration table is in the ledger
> - ☑ `obsidian-cli vault=docs unresolved` and `orphans` report nothing new.

> [!success]- [[specs/cycle-6-constructed-decks/spec|Cycle 6 — constructed decks]] · 13 / 13
> <progress value="13" max="13"></progress> DC-07 · [[specs/cycle-6-constructed-decks/spec|spec]] · [[specs/cycle-6-constructed-decks/plan|plan]] · [[specs/cycle-6-constructed-decks/tasks|tasks]]
>
> - **DC-07 constructed-decks** · 2026-11-04 → 2026-11-04 · done: 13 tasks plus B-11 in eight waves, a review pass (Ben 1a 2a 3a, C22) and T13 fixes. Gate green in 60 s, 609 cases, none skipped (gdUnit 13.8 s; the 15 s t…
>
> | # | Task | Area | Who | Status |
> |---|---|---|---|---|
> | T01 | Pool format 3 and the deck list | engine | implementer-engine | <span class="st st-done">done</span> |
> | T02 | Decks in the match | engine | implementer-engine | <span class="st st-done">done</span> |
> | T03 | The hundredths mult | engine | implementer-engine | <span class="st st-done">done</span> |
> | T04 | Destroyed piles and recovery | engine | implementer-engine | <span class="st st-done">done</span> |
> | T05 | The set choice | engine | implementer-engine | <span class="st st-done">done</span> |
> | T06 | The destroy pipeline and the Ruin verbs | engine | implementer-engine | <span class="st st-done">done</span> |
> | T07 | The Drift verbs and `ON_MOVED` | engine | implementer-engine | <span class="st st-done">done</span> |
> | T08 | The tables and the bot | engine | implementer-engine | <span class="st st-done">done</span> |
> | T09 | Board faces, chips, tally, piles and steps | board | implementer | <span class="st st-done">done</span> |
> | T10 | The multi-select prompt and the recover strip | board, ui | implementer | <span class="st st-done">done</span> |
> | T11 | The picker and the launch path | ui, board | implementer | <span class="st st-done">done</span> |
> | T12 | Review of T01–T11 against the spec and the Constitution Check, with attention to hidden information | all | reviewer | <span class="st st-done">done</span> |
> | T13 | Verification | all | orchestrator | <span class="st st-done">done</span> |
>
> **Verification: 9 of 9 checked**
>
> - ☑ `make check` exits 0, test stage under 15 s
> - ☑ Re-pin the seed-1 golden under its seeded pairing
> - ☑ 50-seed sweep passes under seeded pairings, every log replays with its decks, the
> - ☑ Picker. With no flags
> - ☑ Mult. On a seed where a ×-card scores
> - ☑ Sacrifice. On a turn where Immolator flips for seat 0
> - ☑ Un-reveal, recover, moves. By node query or the event stream
> - ☑ Ben has reviewed the Ruin and Drift tables
> - ☑ No GDScript warning in the editor run

> [!success]- [[specs/cycle-5-walk-cursor/spec|Cycle 5 — the walk cursor]] · 9 / 9
> <progress value="9" max="9"></progress> DC-06 · [[specs/cycle-5-walk-cursor/spec|spec]] · [[specs/cycle-5-walk-cursor/plan|plan]] · [[specs/cycle-5-walk-cursor/tasks|tasks]]
>
> - **DC-06 walk-cursor** · 2026-11-04 → 2026-11-04 · done: 7 build tasks in four waves, plus a review-fix pass and one cycle-5 T01 rework after Ben's C23 ruling (the score stage belongs to the slot). Gate green in…
>
> | # | Task | Area | Who | Status |
> |---|---|---|---|---|
> | T01 | The slot cursor | engine | implementer-engine | <span class="st st-done">done</span> |
> | T02 | Destroyed as a state | engine | implementer-engine | <span class="st st-done">done</span> |
> | T03 | Preview and sweep | engine | implementer-engine | <span class="st st-done">done</span> |
> | T04 | Board steps and tracker | board | implementer | <span class="st st-done">done</span> |
> | T05 | The destroyed look | board | implementer | <span class="st st-done">done</span> |
> | T06 | Chips, tally and the HUD | board, ui | implementer | <span class="st st-done">done</span> |
> | T07 | The prompt reader | board, ui | implementer | <span class="st st-done">done</span> |
> | T08 | Review of T01–T07 against the spec and the Constitution Check, with attention to hidden information | all | reviewer | <span class="st st-done">done</span> |
> | T09 | Verification | all | orchestrator | <span class="st st-done">done</span> |
>
> **Verification: 9 of 9 checked**
>
> - ☑ `make check` exits 0, test stage under 15 s
> - ☑ Re-pin the seed-1 golden
> - ☑ 50-seed sweep passes with prompts and destroys
> - ☑ Cursor (amended 2026-11-04, C23). On a scripted or seeded turn where c12 swaps
> - ☑ Destroyed. After a destroy the card stays in `OpponentRow`
> - ☑ Chips and tally. On a pulse of a bonus card
> - ☑ Prompt pause. During c12's prompt no chip shows for c12, tally and HUD hold
> - ☑ Prompt reader. On the first seed-1 turn in which seat 0 is prompted
> - ☑ No GDScript warning in the editor run

> [!success]- [[specs/cycle-4-card-effects/spec|Cycle 4 — card effects]] · 14 / 14
> <progress value="14" max="14"></progress> DC-05 · [[specs/cycle-4-card-effects/spec|spec]] · [[specs/cycle-4-card-effects/plan|plan]] · [[specs/cycle-4-card-effects/tasks|tasks]]
>
> - **DC-05 card-effects** · 2026-11-03 → 2026-11-04 · done: 14 issues in seven waves, plus one T05 re-dispatch and one review-fix dispatch. Gate green in 41 s (test stage 12 s): 420 cases (258 + 162 new), none skip…
>
> | # | Task | Area | Who | Status |
> |---|---|---|---|---|
> | T01 | Card data format 2 | engine | implementer-engine | <span class="st st-done">done</span> |
> | T02 | Positional commits and energy | engine | implementer-engine | <span class="st st-done">done</span> |
> | T03 | `ScoreWalk` and `CardState` | engine | implementer-engine | <span class="st st-done">done</span> |
> | T04 | Effect framework and non-prompt verbs | engine | implementer-engine | <span class="st st-done">done</span> |
> | T05 | Prompts and prompt verbs | engine | implementer-engine | <span class="st st-done">done</span> |
> | T06 | Preview and bot | engine | implementer-engine | <span class="st st-done">done</span> |
> | T07 | Full match and smoke | engine, board | implementer-engine | <span class="st st-done">done</span> |
> | T08 | Board steps and staging | board | implementer | <span class="st st-done">done</span> |
> | T09 | Card faces and rim removal | board | implementer | <span class="st st-done">done</span> |
> | T10 | Row and commit on the board | board | implementer | <span class="st st-done">done</span> |
> | T11 | The walk and effects on the board | board | implementer | <span class="st st-done">done</span> |
> | T12 | Prompt UI: `PromptRules` (glow set, tap routing) with suite; banner, per-card glow, dimmer, tap →… | board, ui | implementer | <span class="st st-done">done</span> |
> | T13 | Review of T01–T12 against the spec and the Constitution Check, with attention to hidden information | all | reviewer | <span class="st st-done">done</span> |
> | T14 | Verification | all | orchestrator | <span class="st st-done">done</span> |
>
> **Verification: 9 of 9 checked**
>
> - ☑ `make check` exits 0, test stage under 15 s
> - ☑ Re-pin the seed-1 golden
> - ☑ 50-seed sweep passes with prompts and random destroys
> - ☑ Faces. On `board_seed1.tscn`, every hand card shows name, cost, flat, bonus
> - ☑ Slots and commit. Stage a card between two played cards
> - ☑ Walk. At walk start both HUD scores read 0 and `×1`
> - ☑ Prompt. On the first seed-1 turn in which seat 0 is prompted
> - ☑ Effects by node query
> - ☑ No GDScript warning in the editor run

> [!success]- [[specs/cycle-3-board-feedback/spec|Cycle 3 — board feedback]] · 8 / 8
> <progress value="8" max="8"></progress> DC-04 · [[specs/cycle-3-board-feedback/spec|spec]] · [[specs/cycle-3-board-feedback/plan|plan]] · [[specs/cycle-3-board-feedback/tasks|tasks]]
>
> - **DC-04 board-feedback** · 2026-11-03 → 2026-11-03 · done: nine issues in four waves plus review fixes. Gate green in 24 s, 258 cases (237 + 21 new). Smoke and seed-1 autoplay…
>
> | # | Task | Area | Who | Status |
> |---|---|---|---|---|
> | T01 | cycle-3 T01 pointer and drag hygiene | input, board, addon | implementer | <span class="st st-done">done</span> |
> | T02 | cycle-3 T02 layout | board, ui | implementer | <span class="st st-done">done</span> |
> | T03 | `board/lift_rules.gd` | board | implementer | <span class="st st-done">done</span> |
> | T04 | Unseen rim: `Rim` in `board_card.tscn`, `set_unseen` / `is_unseen` / `copy_face_from` in `board_card.gd`;… | board | implementer | <span class="st st-done">done</span> |
> | T05 | Drop-zone glows | board | implementer | <span class="st st-done">done</span> |
> | T06 | Card pick-up | board | implementer | <span class="st st-done">done</span> |
> | T07 | Review of T01–T06 against the spec and the Constitution Check, reading the `drag_controller.gd` patch in full | all | reviewer | <span class="st st-done">done</span> |
> | T08 | Verification | all | orchestrator | <span class="st st-done">done</span> |
>
> **Verification: 10 of 10 checked**
>
> - ☑ `make check` exits 0
> - ☑ Boot log and seed-1 autoplay unchanged
> - ☑ Pick-up on `board_seed1.tscn`, turn 1. A tap on hand card id 8 lifted it
> - ☑ A tap on a face-down opponent hand card was ignored. A tap on a revealed opponent
> - ☑ A real click on Commit, then a tap on the committed card, lifted it during the
> - ☑ Zones. An unaffordable drag
> - ☑ Rims. A staged card has a rim. Dragging it along the row keeps the rim
> - ☑ cycle-3 T02. In both screenshots the opponent fan sits clear of `TopInfo`, now top
> - ☑ cycle-3 T01 / B-05. A gitignored harness, deleted after the run, made 10 scripted
> - ☑ `obsidian-cli vault=docs orphans` reports nothing new

> [!success]- [[specs/cycle-2-board/spec|Cycle 2 — the board]] · 11 / 11
> <progress value="11" max="11"></progress> DC-03 · [[specs/cycle-2-board/spec|spec]] · [[specs/cycle-2-board/plan|plan]] · [[specs/cycle-2-board/tasks|tasks]]
>
> - **DC-03 board** · 2026-11-03 → 2026-11-03 · done: 11 issues in 6 waves plus two fix dispatches; gate green in 20 s, 237 cases (175 + 62 new); smoke `seed=1 winner=0 wins=4-0 rounds=4 end=wins actions=56`…
>
> | # | Task | Area | Who | Status |
> |---|---|---|---|---|
> | T01 | Pointer shim | input | implementer | <span class="st st-done">done</span> |
> | T02 | Card3D DragController patch to take `PointerShim` input | addon | implementer | <span class="st st-done">done</span> |
> | T03 | `board/match_driver.gd` | board | implementer | <span class="st st-done">done</span> |
> | T04 | `board/staging.gd` | board | implementer | <span class="st st-done">done</span> |
> | T05 | `board/board_step.gd`, `board/board_steps.gd` | board | implementer | <span class="st st-done">done</span> |
> | T06 | Card and HUD scenes | board | implementer | <span class="st st-done">done</span> |
> | T07 | Board scene, autoplay path | board | implementer | <span class="st st-done">done</span> |
> | T08 | Board scene, player path | board | implementer | <span class="st st-done">done</span> |
> | T09 | Main wiring: `main.gd` instances the board after the smoke run and prints `Main ready` once it is in the tree;… | scene, tooling | implementer | <span class="st st-done">done</span> |
> | T10 | Review of T01–T09 against the spec and the Constitution Check, reading the Card3D patch in full | all | reviewer | <span class="st st-done">done</span> |
> | T11 | Verification | all | orchestrator | <span class="st st-done">done</span> |
>
> **Verification: 11 of 11 checked**
>
> - ☑ `make check` exits 0
> - ☑ The boot log holds…
> - ☑ MCP `run_scene` on `board/verify/board_autoplay.tscn`
> - ☑ MCP `run_scene` on `board/verify/board_seed1.tscn`, turn 1, energy 1, hand ids 19,
> - ☑ Screenshot 1
> - ☑ Clicking Commit resolved the turn
> - ☑ Pause, then Concede. The first real click on Concede closed the menu without
> - ☑ Screenshot 2
> - ☑ Clicking Rematch hid the result panel, cleared both rows and dealt a fresh 4-card
> - ☑ Two screenshots kept
> - ☑ `obsidian-cli vault=docs unresolved` and `… orphans` report nothing new.

> [!success]- [[specs/cycle-1-match-engine/spec|Cycle 1 — match engine]] · 12 / 12
> <progress value="12" max="12"></progress> DC-01, DC-02 · [[specs/cycle-1-match-engine/spec|spec]] · [[specs/cycle-1-match-engine/plan|plan]] · [[specs/cycle-1-match-engine/tasks|tasks]]
>
> - **DC-01 match-engine** · 2026-11-02 → 2026-11-02 · done: 12 tasks, merged as 6467a08; gate green in 16 s, 166 cases (first recorded as 178, a miscount; corrected 2026-11-03); smoke…
> - **DC-02 hardening** · 2026-11-03 → 2026-11-03 · done: 3 issues, merged as 47f0974; B-04 landed on master early as 1a5e391 (Ben: 2a) because Claude Code runs the edit hook from the main checkout, so agent work…
>
> | # | Task | Area | Who | Status |
> |---|---|---|---|---|
> | T01 | Card data: `engine/data/cards.json` with the plan's table, `CardDef`, `CardDb` load and validation,… | engine | implementer-engine | <span class="st st-done">done</span> |
> | T02 | `MatchRules` constants and `MatchRng` | engine | implementer-engine | <span class="st st-done">done</span> |
> | T03 | `LegalPlays` subset enumeration and commit validation, `test_legal_plays.gd` | engine | implementer-engine | <span class="st st-done">done</span> |
> | T04 | Core flow: `EngineAction`, `EngineError`, `MatchEvent`, `ApplyResult`, `MatchState`, `MatchEngine` start, deal… | engine | implementer-engine | <span class="st st-done">done</span> |
> | T05 | Round and match end | engine | implementer-engine | <span class="st st-done">done</span> |
> | T06 | `SeatView`,… | engine | implementer-engine | <span class="st st-done">done</span> |
> | T07 | `ActionLog`: header, JSON round trip, `replay()` with failure index and version checks; `test_action_log.gd` | engine | implementer-engine | <span class="st st-done">done</span> |
> | T08 | `GreedyBot` under `engine/bot/` | engine | implementer-engine | <span class="st st-done">done</span> |
> | T09 | `test_full_match.gd` | engine | implementer-engine | <span class="st st-done">done</span> |
> | T10 | Smoke run in `godot/main.gd` per the plan, printing… | scene | implementer | <span class="st st-done">done</span> |
> | T11 | Review of T01–T10 against the spec and the Constitution Check | engine | reviewer | <span class="st st-done">done</span> |
> | T12 | Verification | engine | orchestrator | <span class="st st-done">done</span> |
>
> **Verification: 7 of 7 checked**
>
> - ☑ `make check` exits 0
> - ☑ The boot log under `godot/reports/` carries…
> - ☑ Pin the seed-1 winner, round wins, rounds played, end reason and action count from
> - ☑ The 50-seed sweep's longest match
> - ☑ Planted check
> - ☑ No screenshot and no recording
> - ☑ `obsidian-cli vault=docs orphans` reports nothing new

> [!success]- [[specs/cycle-0-scaffolding/spec|Cycle 0 — scaffolding]] · 16 / 16
> <progress value="16" max="16"></progress> DC-00 · [[specs/cycle-0-scaffolding/spec|spec]] · [[specs/cycle-0-scaffolding/plan|plan]] · [[specs/cycle-0-scaffolding/tasks|tasks]]
>
> - **DC-00 scaffolding** · 2026-11-02 → 2026-11-02 · done: 16 tasks, gate green in 7 s on a fresh clone, screenshot via Godot MCP; see [[specs/cycle-0-scaffolding/tasks]]
>
> | # | Task | Area | Who | Status |
> |---|---|---|---|---|
> | T01 | Repo skeleton | tooling | session | <span class="st st-done">done</span> |
> | T02 | Godot project | tooling | session | <span class="st st-done">done</span> |
> | T03 | Vendor gdUnit4 6.2.3 under `godot/addons/gdUnit4/`, enable plugin, add `godot/tests/test_smoke.gd` with one pa… | tooling | subagent (Sonnet) | <span class="st st-done">done</span> |
> | T04 | Vendor Card3D 3.0.2 under `godot/addons/card3d/`, apply the `is_running` patch, create… | tooling | subagent (Sonnet) | <span class="st st-done">done</span> |
> | T05 | Vendor godot-mcp editor plugin 0.6.1 under `godot/addons/godot_mcp/`, enable it, register `MCPRuntime` autoloa… | tooling | session | <span class="st st-done">done</span> |
> | T06 | `scripts/bootstrap.sh` per plan | tooling | session | <span class="st st-done">done</span> |
> | T07 | `scripts/check.sh` with import/lint/parse/boot/test stages and the shared error grep | tooling | session | <span class="st st-done">done</span> |
> | T08 | `scripts/hooks/gd-edit-gate.sh` and `.claude/settings.json` PostToolUse entry | tooling | session | <span class="st st-done">done</span> |
> | T09 | `.mcp.json`, `.env.example`, `scripts/claude-with-env.sh` | tooling | session | <span class="st st-done">done</span> |
> | T10 | Root `CLAUDE.md` constitution per R29 | docs | session | <span class="st st-done">done</span> |
> | T11 | `.claude/agents/` | tooling | session | <span class="st st-done">done</span> |
> | T12 | `.claude/skills/spec/` | tooling | subagent (Sonnet) | <span class="st st-done">done</span> |
> | T13 | `.claude/skills/exercise/` and `.claude/skills/cycle/` SKILL.md per plan table | tooling | session | <span class="st st-done">done</span> |
> | T14 | Vault: `docs/Templates/note.md` with the P5 schema; MOC notes for planning, specs, decisions, systems; ADR 000… | docs | session | <span class="st st-done">done</span> |
> | T15 | Linear: create labels, "Spec task" template, project "Cycle 0 — scaffolding", milestone `DC-00 scaffolding`, o… | docs | session | <span class="st st-done">done</span> |
> | T16 | Verification | tooling | session | <span class="st st-done">done</span> |
>
> **Verification: 6 of 6 checked**
>
> - ☑ Fresh clone
> - ☑ Planted `godot/engine/_broken.gd`
> - ☑ Godot editor open
> - ☑ Secret grep returns nothing.
> - ☑ `obsidian-cli vault=docs unresolved` and `orphans` empty
> - ☑ Linear status update "DC-00 done" posted with the screenshot

## Backlog

> [!todo]+ Open · 7
> | # | Item | Status | Where |
> |---|---|---|---|
> | B-54 | PVP server: router forward, CGNAT check and public address | <span class="st st-open">open</span> | Training nights and router |
> | B-56 | Linear bot overruns the 10 ms decision budget | <span class="st st-open">open</span> | DC-21 training-rounds |
> | B-59 | Trainer: protocol and schema items split from B-50 | <span class="st st-open">open</span> | Training nights and router |
> | B-60 | Limited `uses`: latent oddities left by the DC-20 review | <span class="st st-open">open</span> | – |
> | B-61 | DC-20 review nits: resync failure reason, free-first drop, verb handler allocation, expired Dross Memory | <span class="st st-open">open</span> | – |
> | B-62 | PC at the DC-20 tip: redeploy, trainer tests, planted log rotation | <span class="st st-open">open</span> | Training nights and router |
> | B-63 | Hidden card ids in public exit and unreveal events (sweep fails on trained linear weights) | <span class="st st-open">open</span> | DC-21 training-rounds |

> [!success]- Closed · 56
> | # | Item | Status | Where |
> |---|---|---|---|
> | B-01 | Manual: create the "Spec task" issue template, rename team key to NSC, install GitHub integration, accept Xcode license | <span class="st st-done">done</span> | – |
> | B-02 | Engine: keep the final table after MATCH_ENDED (spec C15) | <span class="st st-done">done</span> | DC-02 hardening |
> | B-03 | Engine hardening: bound action ints, recursive no-print scan, bot CardDb fallback | <span class="st st-done">done</span> | DC-02 hardening |
> | B-04 | Tooling: edit hook skips the gate's typed-strict warnings; cycle skill screenshot rule vs C12 | <span class="st st-done">done</span> | DC-02 hardening |
> | B-05 | Concede click once closed the pause menu without conceding (not reproduced) | <span class="st st-done">done</span> | DC-04 board-feedback |
> | B-06 | Edit hook skips gdlint silently when ~/.local/bin is not on its PATH | <span class="st st-done">done</span> | cycle-14 T14 (DC-20) |
> | B-07 | Board: tap path halt check and a card_lift suite | <span class="st st-done">done</span> | cycle-14 T10 (DC-20) |
> | B-08 | HUD shows a provisional score while a reveal prompt pauses the walk | <span class="st st-done">done</span> | – |
> | B-09 | Bot's slowest decision is about 15 ms, over plan P13's 10 ms budget | <span class="st st-done">done</span> | DC-08 bot-players |
> | B-10 | /cycle test: worktree sweep deletes the cycle's screenshots | <span class="st st-done">done</span> | cycle-14 T14 (DC-20) |
> | B-11 | Prompt reader: the action button overlaps the bottom of the lifted card | <span class="st st-done">done</span> | DC-07 constructed-decks |
> | B-12 | DC-07 visual follow-ups: glow washes out faces, strip overlap, two-part bonus label, picker selection contrast | <span class="st st-dropped">dropped</span> | – |
> | B-13 | DC-09 follow-up: own face-down grown card may reveal with its printed face | <span class="st st-done">done</span> | DC-11 crew |
> | B-14 | Test-time headroom before DC-11: gdUnit at 29.2 s of the 30 s budget | <span class="st st-done">done</span> | DC-10 bot-training |
> | B-15 | DC-10 follow-up: deferred review nits | <span class="st st-dropped">dropped</span> | – |
> | B-16 | DC-11 follow-up: CrewPool.fires is in neither the stamp nor the log | <span class="st st-dropped">dropped</span> | – |
> | B-17 | DC-11 follow-up: Crew card text overflows and the badge covers it; own reveal face unchecked on the board | <span class="st st-dropped">dropped</span> | – |
> | B-18 | DC-13 follow-up: the Pile strip covers the opponent's row | <span class="st st-done">done</span> | DC-14 rules-v2-content |
> | B-19 | DC-13 follow-up: the multi-select glow washes out the hand's card faces | <span class="st st-done">done</span> | DC-14 rules-v2-content |
> | B-20 | to_pile files a created card with no owner in seat 0's Pile | <span class="st st-done">done</span> | cycle-14 T03 (DC-20) |
> | B-21 | Random bot: same-turn prompts with no source card share one seed | <span class="st st-dropped">dropped</span> | – |
> | B-22 | C1 review nits: dead prompt branches, empty-prompt bot answer, double cost scan, seat count | <span class="st st-done">done</span> | cycle-14 T02 (DC-20) |
> | B-23 | Q11 resumed draw is dropped when the trigger budget runs out | <span class="st st-done">done</span> | cycle-14 T02 (DC-20) |
> | B-24 | Created cards and replaced definitions live outside MatchState | <span class="st st-done">done</span> | cycle-14 T03 |
> | B-25 | C2 nits: engine rules cleanup left by DC-15 | <span class="st st-done">done</span> | cycle-14 T06 (DC-20) |
> | B-26 | Immolator and Fuse random picks include cards a Condemn cannot change | <span class="st st-done">done</span> | cycle-14 T03 (DC-20) |
> | B-27 | Limited `uses` on abilities and Crew are never enforced | <span class="st st-done">done</span> | cycle-14 T04 (DC-20) |
> | B-28 | Level can raise a face-down card's Power | <span class="st st-done">done</span> | cycle-14 T03 (DC-20) |
> | B-29 | Crew STATS_CHANGED should use the shared Abilities helper | <span class="st st-done">done</span> | cycle-14 T04 (DC-20) |
> | B-30 | C3 nits: card content cleanup left by DC-15 | <span class="st st-done">done</span> | cycle-14 T07 (DC-20) |
> | B-31 | Board never learns Lantern's free first card | <span class="st st-done">done</span> | cycle-14 T03, cycle-14 T10 (DC-20) |
> | B-32 | Crew firings get no beat on the board (CREW_FIRED is never emitted) | <span class="st st-done">done</span> | cycle-14 T04, cycle-14 T10 (DC-20) |
> | B-33 | Deck notes vanish at the next step (set_piles every step) | <span class="st st-done">done</span> | cycle-14 T10 (DC-20) |
> | B-34 | C4 nits: board core cleanup left by DC-15 | <span class="st st-done">done</span> | cycle-14 T12 (DC-20) |
> | B-35 | C5 nits: board UI, input and main cleanup left by DC-15 | <span class="st st-done">done</span> | cycle-14 T13 (DC-20) |
> | B-36 | C6 nit: one shared _typed() test helper | <span class="st st-done">done</span> | cycle-14 T18 (DC-20) |
> | B-37 | bot-eval aggregates count the dropped pair of a deciding seed | <span class="st st-done">done</span> | DC-18 bot-trainer-b |
> | B-38 | Play-out worker: numeric seeds above 2^53 lose precision silently | <span class="st st-done">done</span> | DC-18 bot-trainer-b |
> | B-39 | Play-out worker may allocate a 16 MiB read buffer per request | <span class="st st-done">done</span> | DC-18 bot-trainer-b |
> | B-40 | Play-out worker relies on print() flushing each reply | <span class="st st-done">done</span> | cycle-14 T15 (DC-20) |
> | B-41 | Rollout label rebuilds view, hidden sets and card data for every play-out | <span class="st st-done">done</span> | DC-17 bot-trainer-a2 |
> | B-42 | Rollout outcome serializes the full state to read the Round wins | <span class="st st-done">done</span> | DC-17 bot-trainer-a2 |
> | B-43 | Match worker enumerates legal commits at every decision for a diagnostic field | <span class="st st-done">done</span> | DC-18 bot-trainer-b |
> | B-44 | Determinization pins non-card numbers of a paused trigger as card ids | <span class="st st-done">done</span> | cycle-14 T05 (DC-20) |
> | B-45 | Trainer: sync_code never cleans inbox bundles | <span class="st st-done">done</span> | DC-18 bot-trainer-b |
> | B-46 | Trainer: SETUP.md layout omits trainer-data | <span class="st st-done">done</span> | DC-18 bot-trainer-b |
> | B-47 | Trainer: a failed report write turns a finished run into failed | <span class="st st-done">done</span> | DC-18 bot-trainer-b |
> | B-48 | Trainer: PC rollouts per worker are a third of the Mac's | <span class="st st-done">done</span> | cycle-14 T15 (DC-20) |
> | B-49 | Trainer: fold inspect into the label reply | <span class="st st-done">done</span> | DC-18 bot-trainer-b |
> | B-50 | Trainer: deeper cleanups left out of the DC-17 simplify pass | <span class="st st-done">done</span> | cycle-14 T17 (DC-20) |
> | B-51 | Trainer: four nits from the DC-18 T07 review | <span class="st st-done">done</span> | cycle-14 T15, cycle-14 T16 (DC-20) |
> | B-52 | PVP server: review nits from DC-19 | <span class="st st-done">done</span> | cycle-14 T10, cycle-14 T11 (DC-20) |
> | B-53 | Stalemate when a sudden-death Round has no commits (rules 8) | <span class="st st-done">done</span> | DC-18 bot-trainer-b |
> | B-55 | Crew Power changes can reach the opponent while the card is in a pending Commit | <span class="st st-done">done</span> | cycle-14 T04 (DC-20) |
> | B-57 | gdUnit total back over the 30 s budget (30.8 s with DC-18) | <span class="st st-done">done</span> | cycle-14 T18 (DC-20) |
> | B-58 | Refresh cycles.md "Planned next" and the stale boxes in finished specs | <span class="st st-done">done</span> | cycle-14 T19 (DC-20) |
