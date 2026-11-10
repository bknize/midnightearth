---
type: plan
tags: [plan, cycle-10-review-tools, tooling, review, cleanup]
status: approved
related: ["[[specs/cycle-10-review-tools/spec]]", "[[specs/cycle-10-review-tools/tasks]]", "[[planning/phase-1-tech-stack]]", "[[planning/phase-2-dev-tools]]", "[[planning/cycles]]", "[[decisions/0002-one-branch-per-cycle]]"]
created: 2026-11-06
updated: 2026-11-07
uid: 4323a104-1578-45a7-b5b6-3cee55be471a
supersedes:
---

# Plan: Cycle 10 — review tools in the cycle, and one cleanup pass

Implements [[specs/cycle-10-review-tools/spec|spec]]. This is the HOW. The spec is
clarified (no open `[NEEDS CLARIFICATION]`). Nothing here changes a requirement; where a
requirement left a choice, the choice is in the P-table below so tasks.md can point at it.

## Stack mapping

| Area | Involved | Approach and tooling |
|---|---|---|
| Godot scenes/UI | y | Chunks C4 and C5 edit `board/`, `input/`, `picker/`, `main.*` through `/simplify` and accepted `/code-review` fixes; no new scene, theme or animation; proof is the gate (boot prints `Main ready`) and the autoplay board smoke, no MCP screenshot |
| Engine (godot/engine + tests) | y | Chunks C1 to C3 edit `godot/engine/` (never `data/`); every chunk gated and swept; golden pinned at T03 and held; fixes larger than one line go to `implementer-engine`; C6 reviews the suites without simplifying them |
| Shaders/cards | n | |
| Tooling/scripts | y | `.claude/skills/cycle/SKILL.md` (the new `/cycle test` step), `CLAUDE.md` (two lines each in the gate paragraph and Roles), `.claude/agents/reviewer.md` (item 4 removed); `scripts/` and `Makefile` untouched |
| Vault/docs | y | ADR `docs/decisions/0004-review-tools-in-the-cycle.md`, rows in [[decisions/decisions-moc]] and [[specs/specs-moc]], the cycle row in [[planning/cycles]]; link audit with `obsidian-cli` |
| Linear | y | Project for this spec; one issue per task; declined findings filed per R31; milestone `DC-NN review-tools` assigned at `/cycle plan` (DC-14 is taken by `cycle-9b-rules-v2`, so DC-15 is expected) |

## Choices the spec left open

| # | Choice | Decision | Why |
|---|---|---|---|
| P1 | Where the pass runs | The skills run in the orchestrator session and take a path target. From `/cycle plan` the cycle branch lives in a worktree; the orchestrator targets the worktree's paths (`<worktree>/godot/engine/...`). T03 confirms once that a path outside the session's cwd is accepted by both skills; if either refuses, the fallback is to hold the cycle branch in the main checkout for the duration of the pass (the orchestrator is the only editor of the chunks; fix dispatches still go to agent worktrees and `--ff-only` merge the branch as today) and return the main checkout to `master` before `/cycle test` | Keeps the branch-in-worktree rule of `CLAUDE.md` unless the tools force the exception, and names the exception in advance |
| P2 | Target form for the standing step | `/code-review medium <cycle branch>` and `/simplify <cycle branch>` where the skill accepts a branch (it diffs against the base); otherwise the explicit path list of the cycle's changed files from `git diff --name-only master...<cycle branch>` | R1 and R5 ask for "the cycle's diff against `master`"; the branch form is that diff, the path form is the fallback |
| P3 | Target form for a chunk | The chunk's path list from R19's table, expanded to files at T03 and pasted into the chunk's Linear issue (R19) | A chunk is a set of files, not a diff |
| P4 | Golden pin for the pass | The line `test_full_match`, `test_match_driver` and the boot smoke agree on after T03's `master` merge, recorded verbatim in tasks.md T03 | DC-14 may re-pin; the pass holds whatever is pinned when it starts |
| P5 | What "one-line fix" means for R3 | A change confined to one statement in one file, with no new identifier | The orchestrator already fixes "one-line problems" at red gates (cycle skill, run step 3); same bar |
| P6 | Triage question shape | One numbered question per report: (a) fix every blocker and should-fix, file the nits; (b) fix blockers only, file the rest; (c) Ben's own pick by finding number. Findings listed above it most severe first, each with file:line and one sentence | The shape the review tasks already use (cycles log, DC-05 to DC-13: "Ben 1a 2a 3a") |
| P7 | Determinism guard for `/simplify` in the engine (R6, R25) | After `/simplify` on C1 to C3 the orchestrator greps the diff for `randi`, `randf`, `shuffle`, `Time.`, `hash(`, `Dictionary` iteration order changes and `to_dict`/`from_dict` edits before running the sweep; any hit is reverted unless the sweep replays and the golden holds | The skills do not know D4; the grep is cheap and the sweep is the arbiter |
| P8 | Typed-strict traps | `/simplify` reads `CLAUDE.md` as project instructions, which already says every project `.gd` is fully typed; the parse stage catches `:=`, untyped loop variables and Variant casts. No extra brief | The gate is the guard; the pass is gated after every chunk |
| P9 | Commit prefix | `dc-NN:` with the N assigned at `/cycle plan`; `cycle-NN:` for merges | As every cycle since DC-01 |
| P10 | Order of the workflow tasks and the pass | T01 and T02 run now in one wave (no shared files: ADR vs skill/`CLAUDE.md`/reviewer). T03 waits for DC-14's `master` merge; T04 to T09 are serial (each chunk's simplifications may touch what the next chunk calls); T10 last | Round 1, 1a and 4a |

## Interfaces and contracts

### The new `/cycle test` step (R1 to R12, R17), to be inserted before step 1

```
0. Review and simplify (ADR 0004). On <cycle branch>, before the gate:
   a. `/code-review medium <cycle branch>` (report only; never `--fix`, `max` or `ultra`
      unless Ben names it; never `--comment`). Sort the findings into blocker /
      should-fix / nit and put them to Ben as one numbered question (P6). Apply accepted
      one-line fixes yourself; dispatch anything larger to implementer (implementer-engine
      under godot/engine/) with the finding quoted. File declined findings in Backlog
      (type/bug or type/chore, label spec/<slug>). `scripts/check.sh`; `make sweep` if
      godot/engine/ changed. Commit `dc-NN: review fixes`.
   b. `/simplify <cycle branch>`. Read its diff: revert anything that weakens a test,
      touches the seeded RNG, the action log or replay, or reaches outside the cycle's
      diff. `scripts/check.sh`; `make sweep` if godot/engine/ changed. Commit
      `dc-NN: simplify`.
   Either commit is omitted when empty. If a skill is not listed in this session, tell Ben,
   skip it and note the skip in the cycle row. Red means no merge.
```

### `CLAUDE.md` (R16)

- Gate paragraph, after the "buildable and testable" sentence: one or two lines saying that
  `/cycle test` runs `/code-review medium` then `/simplify` on the cycle's diff before the
  gate, report-only and `medium` unless Ben names otherwise, never `ultra` unprompted (ADR
  0004).
- Roles, orchestrator line: add "runs `/code-review` and `/simplify` at `/cycle test`".

### `.claude/agents/reviewer.md` (R13)

Remove item 4 ("Simplifications, briefly."); add one sentence: simplifications belong to
`/simplify` at `/cycle test`, do not report them.

### ADR 0004 (R15)

`docs/decisions/0004-review-tools-in-the-cycle.md`, `type: adr`, `status: accepted`,
`supersedes:` empty. Sections: Context (the two skills, the reviewer overlap), Decision (the
step, the order, the effort rule, who launches `ultra`, the reviewer's narrower brief, the
two-commit rule), Consequences (one extra gate run per cycle; `/simplify` edits land through
the orchestrator, not an implementer; the one-off pass of this spec). Row in
[[decisions/decisions-moc]].

### Per-chunk procedure (R19 to R29), run by the orchestrator

1. Paste the chunk's final file list into its Linear issue; move it to In Progress.
2. `/code-review medium <paths>`; triage to Ben (P6); land accepted fixes (P5; else
   dispatch per R28, the agent worktree `--ff-only` merges the cycle branch first); gate;
   sweep for C1 to C3; commit `dc-NN: Cn review fixes`.
3. C6 stops here. Otherwise `/simplify <paths>`; read the diff (R6, R22, P7); gate; sweep
   for C1 to C3; check the golden line (P4) and `stamp=match`; commit `dc-NN: Cn simplify`.
4. Red on step 3 that is not a one-line fix: `git revert` the simplify commit, gate, then
   re-dispatch or file (R27).
5. Comment on the issue with the two commit hashes, the gate and sweep summary lines, the
   finding counts (fixed / filed), and move it to In Review.

### Skill invocation contract (as far as known; T03 confirms)

| Skill | Form used here | Edits the tree | Needs |
|---|---|---|---|
| `/code-review medium <target>` | branch (P2) or path list (P3) | no (`--fix` never unprompted) | the orchestrator session |
| `/simplify <target>` | branch or path list | yes, working tree of the target | the orchestrator session; a gate run after |

Neither runs Godot; neither knows D4; the gate and the sweep stand behind both.

## Data model

No engine state, action or resource changes are intended; any that `/simplify` proposes
(`to_dict`/`from_dict`, action shapes, event payloads) is reverted under R6/P7 unless the
sweep replays every log and the golden holds. Notes: one new `adr`; the three spec notes;
rows in two MOCs and the cycles log. Linear: one project, one issue per task, Backlog
issues per R31.

## Constitution Check

| Rule | Verdict | Note |
|---|---|---|
| All project GDScript is fully typed (`parse` promotes typed-GDScript warnings to errors) | PASS | Every chunk and every standing-step edit passes `make check` before it is committed (R7, R25); P8 |
| Engine is deterministic: seeded RNG, no wall-clock, no node access, serializable action log (D4) | PASS | R6, R25, R27, P7: sweep after every engine chunk, golden held, revert on mismatch; `data/*.json` untouched so the stamp holds (R23, R29) |
| `make check` gate contract: import, lint, parse, boot, test all green; Godot exit codes never trusted | PASS | The gate is unchanged; the new step runs before it and is gated by it |
| Implementers never run Godot or `make check`; only the orchestrator verifies | PASS | The skills, the gate and the sweep are all run by the orchestrator; implementers take only dispatched fixes (R3, R28) |
| Notes carry P5 frontmatter and `[[path/from/vault/root]]` links | PASS | Spec, plan, tasks, ADR 0004, MOC rows |
| No edits under the do-not-touch list | PASS | `godot/addons/`, `.env`, `godot/.godot/`, `godot/reports/`, the archive and `docs/.obsidian/` are outside every chunk (R23); the two WIP guides are named as never-touch |
| Secrets only in `.env`; no token in chat, notes, commits or Linear | PASS | Nothing here touches `.env` or `.mcp.json` |
| Each changeset on its own branch (cycle: one `cycle-N-<theme>` branch from `/spec` to `/cycle test`), one commit per task, nothing on `master`, merged `--no-ff` | PASS (noted) | One branch, `cycle-10-review-tools`. Chunk tasks land as two commits each (R26, Ben round 2 4a) so a simplification can be reverted alone; the "one commit per task" convention bends here by Ben's decision and the ADR says so. `master` is merged into the branch at T03 (a plain merge into the cycle branch, not a commit on `master`) |

**Result:** PASS.

## Risks and mitigations

- `/simplify` changes behaviour in the engine (a reordered dictionary walk, a merged branch
  that drops an edge case) → sweep after every engine chunk with replay and leak scan, the
  golden line held, P7 grep, revert of the chunk's simplify commit on any mismatch (R27).
- `/simplify` "tidies" a test → `/simplify` never runs on `tests/` (R21); on production
  chunks any test edit except a forced rename is reverted (R22).
- The pass collides with DC-14 → it does not start until DC-14 has merged and `master` is
  merged into the branch (R18, T03).
- The skills refuse a path outside the session's cwd → P1 fallback (branch in the main
  checkout for the pass), confirmed at T03 before any chunk runs.
- `/code-review` floods Ben with nits → P6 lists most severe first with the bulk option (a);
  nits are filed in one collecting issue per chunk (R31).
- Billed `ultra` run by accident → R9 in the skill, `CLAUDE.md` and the ADR; never
  unprompted.
- The gate's gdUnit budget (30 s) tightens if accepted fixes add tests → fixes in this pass
  add tests only when a correctness finding needs a pin; the orchestrator watches the gdUnit
  time in each chunk's summary.
- The DC number: DC-14 belongs to `cycle-9b-rules-v2`; this cycle takes the next unused N
  at `/cycle plan` (expected DC-15), so the `dc-NN:` prefix is fixed then, not here.

## Open questions

- None. The skill flag facts above are the orchestrator's reading before the interview; T03
  confirms the target forms (P1, P2) in practice before the first chunk.
