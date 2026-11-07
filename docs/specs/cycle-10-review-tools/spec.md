---
type: spec
tags: [spec, cycle-10-review-tools, tooling, review, cleanup]
status: approved
related: ["[[specs/cycle-10-review-tools/plan]]", "[[specs/cycle-10-review-tools/tasks]]", "[[planning/phase-1-tech-stack]]", "[[planning/phase-2-dev-tools]]", "[[planning/cycles]]", "[[decisions/0002-one-branch-per-cycle]]", "[[specs/cycle-9-rules-v2/spec]]"]
created: 2026-11-06
updated: 2026-11-07
uid: cd9d730d-f266-4831-9b26-1a01ba6e5cab
linear: https://linear.app/night-science-llc/project/cycle-10-review-tools-in-the-cycle-and-one-cleanup-pass-da55e6ed55be
supersedes:
---

# Spec: Cycle 10 — review tools in the cycle, and one cleanup pass

**Slug:** `cycle-10-review-tools`  ·  **Change type:** tooling (plus a one-off cleanup pass
that edits code under `godot/`)  ·  **Status:** approved (Ben, 2026-11-06, three rounds, signed off 2026-11-07; see
Clarifications)

Ben's request: "Spec a changeset to add both of these to the workflow, and then run both of
them over the codebase in chunks based on feature." "Both of these" are the built-in Claude
Code skills `/simplify` and `/code-review`.

What the two skills are (facts the orchestrator established before the interview; Ben did
not rule on them, they are recorded here as the ground the requirements stand on):

- Both are language-agnostic and work on `.gd`, `.tscn` and `.tres`. With no target they
  review the uncommitted diff; they accept a branch, a PR or a path as target.
- `/simplify` applies quality cleanups to the working tree (reuse, simplification,
  efficiency); it does not hunt bugs. `/code-review` hunts correctness bugs at an effort
  level (`low | medium | high | xhigh | max`; `ultra` is a billed cloud multi-agent review
  only Ben can launch), report-only unless `--fix`; `--comment` posts PR comments.
- Neither runs Godot, so their edits must pass `make check` (the parse stage promotes the
  typed-GDScript warnings to errors) and, for engine code, `make sweep`. Neither knows the
  determinism rules (seeded RNG, action log) unless told.
- Both are invoked by the orchestrator session; subagents cannot run slash skills.
- They overlap with the project's `reviewer` agent, which is spec-conformance aware and sits
  inside `/cycle run`.

## Intent

After this cycle, every dev cycle's `/cycle test` runs `/code-review` and then `/simplify`
over the cycle's diff before the gate, with triage by Ben and the results committed on the
cycle branch; the rules (`CLAUDE.md`, the cycle skill, the reviewer's brief, an ADR) say so;
and the existing codebase under `godot/` has been through both tools once, chunk by chunk
in dependency order, with the gate, the sweep and the pinned golden match proving the
engine unchanged in behaviour.

## Non-goals

- No `max` or `ultra` run, and no `--fix`, unless Ben asks for it by name in the
  conversation (round 2, 3a). `ultra` is billed and is Ben's alone to launch.
- No `/simplify` on `godot/tests/` (round 1, 2a): a simplifier that tidies an assertion
  weakens the proof. Tests get `/code-review` only.
- No pass over `scripts/` (bash gate, hooks, the Python bot trainer, which is kept for a
  later bot session: [[specs/cycle-9-rules-v2/spec]] round 3, 1b) and none over
  `godot/addons/` (vendored).
- No edit to `godot/engine/data/cards.json`, `crew.json` or `decks.json` by the pass (round
  3, 3b keeps 3a's data rule): the canon is `docs/rules/`, and a data edit moves the bot
  stamp. A data finding is filed, not fixed.
- No bot rerun, re-stamp or training. The pass must leave the stamp where it is.
- No change to the `reviewer` agent's place in `/cycle run` (round 2, 2a): it keeps spec
  conformance, correctness against the spec and the constitution checks; only its
  "simplifications" item moves to `/simplify`.
- No PR comments (`--comment`): the cycle merges locally, there is no PR.
- No screenshot: a tooling cycle, proof by text lines (cycle 1 C12 waiver).
- The new `/cycle test` step is not exercised on this cycle's own diff; its first real run is
  the next cycle's `/cycle test` (round 3, 3b).
- Never the two uncommitted guides in the main checkout (`docs/systems/bot-training.md`,
  `docs/systems/cards-crew-decks.md`), which are Ben's WIP.

## Actors

- **Ben** — triages findings, names any effort above `medium`, signs off.
- **The orchestrator** (the Claude Code session) — the only actor that can invoke the two
  skills; runs them, sorts findings, applies one-line fixes, runs the gate and the sweep,
  commits, keeps Linear truthful.
- **Implementer / implementer-engine** — take any accepted fix larger than one line, in a
  worktree, as today.
- **The reviewer agent** — unchanged in place, narrower in brief.
- **`/code-review` and `/simplify`** — the tools under test; they read the tree, one of
  them edits it.
- **The gate (`make check`) and the sweep (`make sweep`)** — the only arbiters of whether an
  edit stays.

## Requirements (EARS)

### A. The standing step at `/cycle test` (round 2, 1a and 3a; round 3, 3b)

- R1. When `/cycle test DC-NN` begins, the orchestrator shall run `/code-review medium` on
  the cycle branch's diff against `master` before the gate of the ritual's step 1.
- R2. When a `/code-review` report returns, the orchestrator shall sort every finding into
  blocker, should-fix or nit and put the sorted list to Ben as one numbered plain-text
  question with lettered options before any fix is made.
- R3. When Ben accepts a finding, the orchestrator shall apply the fix itself when it is a
  one-line change and otherwise dispatch an implementer (`implementer-engine` for anything
  under `godot/engine/`) with the finding quoted in its brief.
- R4. When Ben declines a finding, the orchestrator shall file it in Linear Backlog as
  `type/bug` (a correctness finding) or `type/chore` (a quality finding), labelled
  `spec/<the cycle's slug>`.
- R5. When the accepted review fixes are in the tree and the gate is green, the orchestrator
  shall run `/simplify` on the cycle branch's diff against `master`.
- R6. When `/simplify` has edited the tree, the orchestrator shall read its diff and revert
  any edit that weakens or removes a test assertion, changes a draw from the seeded RNG
  stream, changes the action log's shape or replay, or reaches outside the cycle's diff.
- R7. The orchestrator shall run `make check` after the review fixes land and again after
  `/simplify`, and `make sweep` as well whenever either touched `godot/engine/`; while a
  run is red, the cycle branch shall not merge into `master`.
- R8. The orchestrator shall commit the review fixes and the simplifications as two
  separate commits on the cycle branch (`dc-NN: review fixes`, `dc-NN: simplify`), each
  omitted when it would be empty.
- R9. The orchestrator shall run `/code-review` at effort `medium` and without `--fix`
  unless Ben names another level or `--fix` in the conversation; `max` and `ultra` shall
  never be run unprompted.
- R10. The ritual shall not use `--comment`.
- R11. If either skill is not available in the session, the orchestrator shall say so to
  Ben, continue the ritual without it and record the skip in the cycle's row of
  [[planning/cycles]].
- R12. The `/cycle test` of this cycle (`cycle-10-review-tools`) shall skip R1 to R8; the
  first real run of the step is the next cycle's (round 3, 3b).

### B. The reviewer agent (round 2, 2a)

- R13. The reviewer agent shall report spec conformance, correctness bugs against the spec
  and constitution violations, and shall no longer report simplifications.
- R14. The reviewer's place in `/cycle run` (the review task in each spec's task list and
  the optional per-wave dispatch on engine diffs) shall be unchanged.

### C. The record (round 3, 1a)

- R15. An ADR under `docs/decisions/` shall record the decision to run both skills at
  `/cycle test`, the effort rule of R9, who may launch `ultra`, and the reviewer's narrower
  brief, with P5 frontmatter and a row in [[decisions/decisions-moc]].
- R16. `CLAUDE.md` shall name the step and the effort rule in its gate paragraph and name
  the two skills among the orchestrator's duties in Roles, in no more than two added
  lines each.
- R17. `.claude/skills/cycle/SKILL.md` shall carry the step under `/cycle test`, numbered
  before the present step 1, stating the order review → triage → fixes → gate → simplify →
  diff read → gate (and sweep) → two commits, and the rules of R9 to R12.

### D. The one-off cleanup pass (round 1, 1a to 4a; round 2, 4a; round 3, 3b)

- R18. The pass shall not start before `cycle-9b-rules-v2` (DC-14) has merged into `master`
  and `master` has then been merged into `cycle-10-review-tools`.
- R19. The pass shall cover `godot/` outside `addons/` in six chunks, in this order:

  | Chunk | Feature | Files | Tools |
  |---|---|---|---|
  | C1 | engine core | `engine/match_engine, match_state, turn_flow, match_rules, match_rng, action_log, engine_action, apply_result, replay_result, engine_error, seat_view, legal_plays, verb_handler, choice`, `engine/bot/*` | review, simplify |
  | C2 | engine rules | `engine/scoring, score_walk, statuses, movement, trigger_queue, trigger_context, card_state, card_memory, match_cards` | review, simplify |
  | C3 | engine content | `engine/abilities*, card_ability, crew_abilities, crew_def, crew_pool, card_db, card_def, deck_list` (and the ability files DC-14 adds); `engine/data/*.json` read only | review, simplify |
  | C4 | board core | `board/board, board_steps, board_step, match_driver, board_seeds, effect_player, board_hud, score_tracker`, `board/verify/*`, `board/*.tscn`, `board_theme.tres` | review, simplify |
  | C5 | board cards and input | `board/board_card, card_lift, card_spot, lift_*, row_*, score_chips, staging, deck_strip, crew_line, hand_telegraph, board_drag_strategy, prompt_*`, `input/*`, `picker/*`, `main.gd`, `main.tscn` | review, simplify |
  | C6 | tests | `tests/*`, `tests/fixtures/*`, `tests/sweep/*` | review only |

  A file DC-14 adds joins the chunk whose feature it belongs to; the orchestrator records
  the final file list of each chunk in its Linear issue before running it.
- R20. For each of C1 to C5 the orchestrator shall run `/code-review medium` on the chunk's
  paths, triage per R2 to R4, land the accepted fixes per R3, and then run `/simplify` on
  the same paths.
- R21. For C6 the orchestrator shall run `/code-review medium` only.
- R22. While a production chunk (C1 to C5) is being simplified, the pass shall not change a
  file under `godot/tests/` except for a rename the simplification forced, and the commit
  message shall name every such test change.
- R23. The pass shall not edit `godot/addons/`, `scripts/`, `godot/engine/data/*.json`, or
  the two uncommitted guides named in Non-goals.
- R24. If a finding concerns a data file, the orchestrator shall file it (R4) rather than fix
  it.
- R25. After each chunk the orchestrator shall run `make check`; after C1, C2 and C3 it
  shall also run `make sweep`, and the chunk is accepted only when every log replays, the
  leak scan is clean and the golden line pinned at the start of the pass is unchanged in
  the engine smoke, `test_full_match` and `test_match_driver`.
- R26. Each chunk shall land as two commits on the cycle branch, `dc-NN: Cn review fixes`
  and `dc-NN: Cn simplify`, each omitted when it would be empty, so that either can be
  reverted alone.
- R27. If a chunk's simplify commit turns the gate or the sweep red and the cause is not a
  one-line fix, the orchestrator shall revert that commit, re-run the gate, and either
  re-dispatch the cleanup to an implementer with the failure in its brief or file it as a
  chore.
- R28. An accepted fix larger than one line shall go to `implementer-engine` for C1 to C3 and
  to `implementer` for C4 to C6.
- R29. The pass shall leave the bot stamp unchanged (`stamp=match` in the sweep summary).

### E. Linear and done (round 3, 2a and 3b)

- R30. `/exercise` shall create one issue per task of [[specs/cycle-10-review-tools/tasks]],
  chunks included, in this spec's project.
- R31. Every declined blocker or should-fix shall become its own Backlog issue; the declined
  nits of a chunk shall be collected in one Backlog issue per chunk, all labelled
  `spec/cycle-10-review-tools`.
- R32. The cycle shall be done when the ADR, skill, `CLAUDE.md` and reviewer edits are in;
  the six chunks are committed with their gate (and C1 to C3 sweep) summaries and the
  unchanged golden line recorded in the cycle's row; every finding is fixed or filed; the
  three data files are untouched; and no screenshot is required.

## Clarifications (Ben, 2026-11-06)

Three rounds, every recommendation taken except round 3 Q3.

| # | Question | Answer |
|---|---|---|
| Round 1, 1 | When does the cleanup pass run, given DC-14 is in flight? | **1a**: the workflow half proceeds now; the chunks are blocked on DC-14's `master` merge, and the orchestrator merges `master` into this branch before the first chunk |
| Round 1, 2 | What gets which tool? | **2a**: production code gets `/code-review` then `/simplify`; tests `/code-review` only; `scripts/` stays out |
| Round 1, 3 | How is the codebase chunked? | **3a**: the six chunks C1–C6 as proposed (R19) |
| Round 1, 4 | In what order? | **4a**: C1 → C6, with the dependencies (engine, then the board that calls it, then the tests that pin both) |
| Round 2, 1 | Where do the skills sit in the standing workflow? | **1a**: at `/cycle test`, before the gate, on the cycle branch's diff against `master`; the reviewer keeps its place in `/cycle run` |
| Round 2, 2 | Relation to the `reviewer` agent? | **2a**: complement; the reviewer drops only its simplifications item |
| Round 2, 3 | Effort level and findings? | **3a**: `/code-review medium`, report-only; orchestrator triage put to Ben; one-liners by the orchestrator, else an implementer dispatch; `--fix`, `max`, `ultra` only when Ben asks by name |
| Round 2, 4 | What proves a chunk behaviour-preserving? | **4a**: gate green; sweep and golden unchanged for C1–C3; no test edits except forced renames; two commits per chunk |
| Round 3, 1 | Where is the `CLAUDE.md` rule change recorded? | **1a**: an ADR plus the skill, `CLAUDE.md` and reviewer edits |
| Round 3, 2 | Linear for the pass and its findings? | **2a**: one issue per task; declined blockers and should-fixes one issue each, nits one collecting issue per chunk |
| Round 3, 3 | Definition of done and proof? | **3b**: as 3a (no screenshot; data files untouched; six chunks committed with summaries; every finding fixed or filed) but without exercising the new step on this cycle's own diff; the next cycle is its first run |

## Scenarios

- **Given** a cycle branch with a green gate at `/cycle test`, **when** the orchestrator
  runs `/code-review medium` on its diff against `master`, **then** the findings reach Ben as
  one numbered question before any edit, accepted fixes land and are gated, `/simplify` runs
  on the same diff, its edits are read and gated (and swept if the engine changed), and two
  commits sit on the branch before the merge.
- **Given** a `/code-review` finding Ben declines, **when** the ritual continues, **then** a
  Backlog issue exists for it with `type/bug` or `type/chore` and the spec label.
- **Given** DC-14 has merged and `master` has been merged into `cycle-10-review-tools`,
  **when** the orchestrator runs chunk C1, **then** `make check` and `make sweep` are green,
  every log replays, `stamp=match`, the golden line equals the one pinned at the start of the
  pass, and the branch carries `C1 review fixes` and `C1 simplify` commits (or fewer, if one
  would be empty).
- **Given** `/simplify` on C2 rewrites a loop in `trigger_queue.gd` and the sweep then shows a
  replay mismatch, **when** the cause is not a one-line fix, **then** the `C2 simplify` commit
  is reverted, the gate re-run, and the cleanup either re-dispatched with the failure or
  filed.
- **Given** `/simplify` on C4 also edits `tests/test_board_steps.gd`, **when** the orchestrator
  reads the diff, **then** the test edit is reverted unless it is a rename the simplification
  forced, in which case the commit message names it.
- **Given** `/code-review` on C3 reports that a card in `cards.json` disagrees with the canon,
  **when** the orchestrator triages, **then** the finding is filed, the file is not edited and
  `stamp=match` holds.
- **Given** a session in which `/simplify` is not listed, **when** `/cycle test` reaches the
  step, **then** the orchestrator tells Ben, runs the rest of the ritual and records the skip
  in the cycle row.

## Data touched

- New: `docs/specs/cycle-10-review-tools/{spec,plan,tasks}.md`;
  `docs/decisions/0004-review-tools-in-the-cycle.md`; a row in
  [[decisions/decisions-moc]] and in [[specs/specs-moc]].
- Edited by the workflow tasks: `.claude/skills/cycle/SKILL.md`, `CLAUDE.md`,
  `.claude/agents/reviewer.md`.
- Edited by the pass: files under `godot/engine/` (not `data/`), `godot/engine/bot/`,
  `godot/board/`, `godot/input/`, `godot/picker/`, `godot/main.gd`, `godot/main.tscn`; files
  under `godot/tests/` only through accepted `/code-review` fixes (C6) or a forced rename
  (R22).
- Read only: `godot/engine/data/*.json`, `scripts/`, `Makefile`, the existing specs, the
  canon under `docs/rules/`.
- Never: `godot/addons/*`, `docs/.obsidian/`, `.env`, `godot/.godot/`, `godot/reports/`,
  the archive, the two uncommitted guides under `docs/systems/`.

## Definition of done

- [ ] ADR 0004 exists with P5 frontmatter and a MOC row; `CLAUDE.md`, the cycle skill and
  the reviewer's agent file carry R13, R16 and R17.
- [ ] DC-14 merged into `master`, `master` merged into the cycle branch, golden line pinned
  for the pass and recorded in the tasks note (T03).
- [ ] C1 to C6 committed per R26 with their gate summaries; C1 to C3 with sweep summaries
  showing every log replays, leak scan clean, `stamp=match`, golden unchanged.
- [ ] Every finding fixed or filed per R4 and R31; `engine/data/*.json` untouched
  (`git diff master -- godot/engine/data` empty).
- [ ] `make check` is green on the cycle branch at `/cycle test`; `make sweep` summary
  pasted.
- [ ] No screenshot (tooling cycle; waiver as cycle 1 C12).
- [ ] Constitution Check passes (see plan).
- [ ] Spec, plan and tasks signed off by Ben and committed before implementation begins.
