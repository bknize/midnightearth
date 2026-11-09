---
type: tasks
tags: [tasks, cycle-10-review-tools, tooling, review, cleanup]
status: approved
related: ["[[specs/cycle-10-review-tools/spec]]", "[[specs/cycle-10-review-tools/plan]]", "[[planning/phase-1-tech-stack]]", "[[planning/cycles]]", "[[decisions/0002-one-branch-per-cycle]]"]
created: 2026-11-06
updated: 2026-11-09
uid: 3ccb76be-2914-468b-80ff-3f0555b8e293
linear: https://linear.app/night-science-llc/project/cycle-10-review-tools-in-the-cycle-and-one-cleanup-pass-da55e6ed55be
supersedes:
---

# Tasks: Cycle 10 — review tools in the cycle, and one cleanup pass

Derived from [[specs/cycle-10-review-tools/plan|plan]]. Numbered, dependency-ordered,
independently reviewable. `implementer` edits in a worktree; `implementer-engine` takes
anything under `godot/engine/`; `orchestrator` runs the two skills (only the session can),
the gate, the sweep, and handles Linear. The chunk tasks T04 to T09 are the orchestrator's
because the skills are; an accepted fix larger than one line inside them is a dispatch
(R3, R28), not a task of its own.

| # | Task | Area | Depends on | Acceptance check | Who |
|---|---|---|---|---|---|
| 1 | ADR 0004 `docs/decisions/0004-review-tools-in-the-cycle.md` per plan (Context, Decision: the step and its order, `medium` report-only by default, `--fix`/`max`/`ultra` only when Ben names them, `ultra` is Ben's to launch, the reviewer drops simplifications, two commits per step; Consequences), P5 frontmatter, row in [[decisions/decisions-moc]] (R15) | vault | – | File has every P5 field and `status: accepted`; MOC row present; `obsidian-cli vault=docs unresolved` and `orphans` report nothing new | implementer |
| 2 | The standing step: insert step 0 under `/cycle test` in `.claude/skills/cycle/SKILL.md` per the plan's contract (R1–R12, R17); add the gate-paragraph lines and the Roles phrase to `CLAUDE.md` (R16, at most two lines each); remove item 4 from `.claude/agents/reviewer.md` and add the one-sentence pointer (R13); leave the reviewer's place in `/cycle run` unchanged (R14) | tooling | – | `grep -n "code-review\|simplify" .claude/skills/cycle/SKILL.md CLAUDE.md .claude/agents/reviewer.md` shows the step, the effort rule, the `ultra` rule, the two-commit rule and the reviewer pointer; `grep -c "Simplifications" .claude/agents/reviewer.md` is 0; `CLAUDE.md` grew by at most four lines; `make check` green (no `.gd` touched) | implementer |
| 3 | Baseline for the pass (R18, P1, P2, P4): after `cycle-9b-rules-v2` has merged into `master`, merge `master` into `cycle-10-review-tools` (`--no-ff`, message `cycle-NN: merge master after DC-14`); `scripts/check.sh` and `make sweep` green; record the golden line verbatim below under "Golden pinned for the pass"; expand R19's chunk table into exact file lists (DC-14's new files assigned to their chunks) and paste each into its Linear issue; confirm both skills accept a target outside the session's cwd (P1) and a branch target (P2), recording the outcome below; if P1 fails, hold the branch in the main checkout for the pass and say so in the cycle row | tooling | 1, 2, DC-14 merged | `git merge-base --is-ancestor master cycle-10-review-tools` true; gate and sweep summaries pasted below; golden line recorded; six file lists in Linear; P1/P2 outcome recorded | orchestrator |
| 4 | Chunk C1 engine core (R19–R29, plan per-chunk procedure): `/code-review medium` on the C1 paths, triage to Ben (P6), accepted fixes (one-liners by the orchestrator, else `implementer-engine`), gate + sweep, commit `dc-NN: C1 review fixes`; `/simplify` on the C1 paths, diff read (R6, R22, P7), gate + sweep, golden and `stamp=match` held, commit `dc-NN: C1 simplify`; declined findings filed (R31) | engine | 3 | Both commits (or fewer, if empty) on the branch; `make check` green; `make sweep`: every log replays, leak scan clean, `stamp=match`, golden unchanged; `git diff master -- godot/tests` after the simplify commit shows only forced renames named in its message; Linear comment with hashes, summaries and finding counts | orchestrator |
| 5 | Chunk C2 engine rules, same procedure as T04 | engine | 4 | As T04 for C2 | orchestrator |
| 6 | Chunk C3 engine content, same procedure as T04; `engine/data/*.json` read only, data findings filed (R23, R24) | engine | 5 | As T04 for C3; `git diff master -- godot/engine/data` empty | orchestrator |
| 7 | Chunk C4 board core, same procedure as T04 but without the sweep; fixes larger than one line to `implementer`; the board autoplay smoke (`board/verify/board_autoplay.tscn`, headless `--fixed-fps 60 -- --autoplay --seed=1`) prints the golden line after the simplify commit | scene | 6 | Both commits (or fewer); `make check` green; autoplay board line equals the golden; `git diff master -- godot/tests` shows only forced renames named in the message; Linear comment | orchestrator |
| 8 | Chunk C5 board cards and input, same procedure as T07 (includes `input/`, `picker/`, `main.gd`, `main.tscn`) | scene | 7 | As T07 for C5; boot prints `Main ready` | orchestrator |
| 9 | Chunk C6 tests: `/code-review medium` on `godot/tests/` only (R21); triage to Ben; accepted fixes (one-liners by the orchestrator, else `implementer`); gate; commit `dc-NN: C6 review fixes`; no `/simplify` | tests | 8 | One commit (or none); `make check` green, case count equal or higher than at T03, gdUnit time within the 30 s budget; no `simplify` commit for C6; Linear comment | orchestrator |
| 10 | Verification (below) | all | 1–9 | All boxes checked | orchestrator |

Waves: W1 T01 + T02 (no shared files). Then wait for DC-14's `master` merge. W2 T03. W3 to
W8 T04, T05, T06, T07, T08, T09, strictly serial (plan P10). W9 T10.

Note at sign-off (2026-11-07): DC-14 had already merged (`cycle-14: rules-v2-content`,
4905225) and that merge is in this branch, so the wait before W2 is over; T03 still merges
`master` into the branch (it carries at least `tooling-deck-picker-scroll`, bee0500) and
pins the golden before the first chunk.

## Golden pinned for the pass (filled at T03)

- Merge: `master` (bee0500) was already in the branch, fast-forwarded at sign-off before
  any cycle commit, so no `--no-ff` merge was needed; `git merge-base --is-ancestor master
  cycle-10-review-tools` is true.
- Line: `seed=1 decks=combo/graveyard bot=random winner=1 wins=3-4 rounds=7 end=wins actions=265`
  (the DC-14 golden, pinned in `test_full_match`, `test_match_driver` and the boot smoke).
- Gate summary at T03 (4343048): import, lint, parse, boot, test all passed in 87 s; test
  stage 18 s.
- Sweep summary at T03: `Sweep: longest=322 seed=37 longest_walk=19 walk_seed=10
  slowest_us=4296 prompts=3799 discard_downs=714 empty_draws=968 pile_shuffles=221 looked=0
  stalemates=2 draws=0 pile_seen=285590 sets=910 crew_prompts=2151 declines=547
  memory_hidden=289 bot=random p95_us=265 p99_us=1142`; exit 0, every log replays, leak
  scan clean. No `stamp=` field while the bot rerun provision is suspended (cycle 9 R75).
- P1 outcome (path target outside cwd): the skills run in the orchestrator session, whose
  tools read and edit absolute paths, so each chunk is passed as absolute paths into the
  cycle worktree; confirmed on first use at T04, fallback (main checkout) not needed unless
  that fails.
- P2 outcome (branch target): a branch target reviews only the branch's diff against
  `master` (here the T01/T02 docs), so the pass uses path lists (P3); the branch form stays
  the standing step's form at `/cycle test`.

### Chunk file lists (paths under `godot/`)

- C1 engine core: `engine/` match_engine, match_state, match_event, turn_flow, match_rules,
  match_rng, action_log, engine_action, apply_result, replay_result, engine_error,
  seat_view, legal_plays, verb_handler, choice; `engine/bot/` bot_player, bot_registry,
  random_bot.
- C2 engine rules: `engine/` scoring, score_walk, statuses, movement, trigger_queue,
  trigger_context, card_state, card_memory, match_cards.
- C3 engine content: `engine/` abilities, abilities_combo_disruption,
  abilities_graveyard_control, card_ability, crew_abilities, crew_def, crew_pool, card_db,
  card_def, deck_list; `engine/data/*.json` read only.
- C4 board core: `board/` board (.gd, .tscn), board_steps, board_step, match_driver,
  board_seeds, effect_player, board_hud (.gd, .tscn), score_tracker; `board/verify/`
  board_autoplay.tscn, board_seed1.tscn.
- C5 board cards and input: `board/` board_card (.gd, .tscn), card_lift, card_spot,
  card_arrivals, lift_layout, lift_rules, row_slots, row_tally (.gd, .tscn), row_targets,
  score_chips (.gd, .tscn), staging, deck_strip, crew_line, hand_telegraph, board_glow,
  board_drag_strategy, prompt_host, prompt_rules, prompt_tap; `input/` pointer_event,
  pointer_shim, pointer_tracker; `picker/` deck_pick_state, deck_picker (.gd, .tscn);
  `main.gd`, `main.tscn`.
- C6 tests: `tests/` (suites, fixtures, sweep), review only.

## Verification task (10)

Owned by the orchestrator, on `cycle-10-review-tools`. Tooling cycle: no screenshot
(spec Non-goals; cycle 1 C12 waiver). The new step itself is **not** run on this cycle's
own diff (spec R12, Ben round 3 3b); its first real run is the next cycle's `/cycle test`.

- [x] `scripts/check.sh` exits 0 on the cycle branch; stage summary pasted into the cycle
  row.
- [x] `make sweep`: every log replays, leak scan clean, `stamp=match`, golden line equal to
  the one pinned at T03; summary lines pasted.
- [x] `git log master..cycle-10-review-tools --oneline` shows the T01/T02 commits, the T03
  merge, and for each chunk its `review fixes` and/or `simplify` commit, none for C6
  simplify.
- [x] `git diff master -- godot/engine/data godot/addons scripts` is empty.
- [x] `grep -n "code-review\|simplify\|ultra" CLAUDE.md .claude/skills/cycle/SKILL.md
  .claude/agents/reviewer.md` shows R13, R16, R17 in place; ADR 0004 listed in the
  decisions MOC.
- [x] Every `/code-review` finding across C1 to C6 is either in a commit or in a Backlog
  issue labelled `spec/cycle-10-review-tools` (R31): counts per chunk recorded in the cycle
  row.
- [x] `obsidian-cli vault=docs unresolved` and `orphans` report nothing new; the cycle row in
  [[planning/cycles]] records the gate, the sweep, the golden, the finding counts, the P1
  outcome and any skill skip (R11).

## Linear (exercised 2026-11-07)

- Project: [Cycle 10 — review tools in the cycle, and one cleanup pass](https://linear.app/night-science-llc/project/cycle-10-review-tools-in-the-cycle-and-one-cleanup-pass-da55e6ed55be) (`planned`)
- Milestone: `DC-NN review-tools` (N assigned at `/cycle plan`; DC-14 is `cycle-9b-rules-v2`,
  so DC-15 is expected)
- Issue mapping: T01 = NSC-165, T02 = NSC-166, T03 = NSC-167, T04 = NSC-168,
  T05 = NSC-169, T06 = NSC-170, T07 = NSC-171, T08 = NSC-172, T09 = NSC-173,
  T10 = NSC-174 (all Todo; blockers follow the Depends column)
- Declined findings: one Backlog issue per blocker or should-fix, one collecting issue per
  chunk for nits, `type/bug` or `type/chore`, label `spec/cycle-10-review-tools` (R31)

## Commit plan

The whole cycle is one changeset on `cycle-10-review-tools`, cut from `master` at `/spec`
before the first note ([[decisions/0002-one-branch-per-cycle]]). It carries the spec
(`spec: cycle-10-review-tools`), the Linear write-back (`exercise: cycle-10-review-tools`),
one commit each for T01 and T02 (`dc-NN: T01 …`, `dc-NN: T02 …`), the T03 merge of `master`
after DC-14 (`cycle-NN: merge master after DC-14`), two commits per chunk (`dc-NN: Cn
review fixes`, `dc-NN: Cn simplify`, each omitted when empty; C6 has no simplify commit; Ben
round 2 4a), any revert under R27, and the verification outcome. Every message ends with the
Co-Authored-By line the session provides. The orchestrator commits; the implementers never
do. When T10 passes, `/cycle test` merges the branch into `master` with `git merge --no-ff`
(`cycle-NN: review-tools`), skipping the new step 0 on this cycle (R12). Nothing is committed
directly on `master`.
