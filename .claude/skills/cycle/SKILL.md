---
name: cycle
description: Run a Midnight Earth dev cycle - plan it (pick Linear issues into a DC-NN milestone), run it (dispatch implementer subagents in worktrees), or test it (merge, make check, Godot MCP screenshots, Linear status update). Use for "/cycle plan DC-01", "/cycle run", "/cycle test", "start the next cycle", "dispatch the cycle", "close out the cycle".
allowed-tools: Read, Edit, Write, Bash, Grep, Glob, Agent
---

# /cycle <plan|run|test> DC-NN

The orchestrator's verbs. Read `CLAUDE.md` first. You are the orchestrator session: you
dispatch, you merge, you test. Implementers never run Godot; you do. `$ARGUMENTS` is
`<verb> DC-NN [theme]`.

`<cycle branch>` below is the cycle's one branch, `cycle-N-<theme>`, named for its spec
slug (`CLAUDE.md`, Git; `docs/decisions/0002-one-branch-per-cycle.md`). It already holds
the spec and the `/exercise` write-back, takes every task merge, and merges into
`master` only at `/cycle test`.

## Sessions (ADR 0006)

Each verb starts in a new session, and `/cycle run` starts a new one at a wave boundary
once the context passes about 250k. Do not split more often: below about 150k a new
session costs more than it saves. Nothing is lost, because the state lives outside the
session. To pick a cycle up, read the milestone's issues (`list_issues`), the plan row in
`docs/planning/cycles.md`, `git log` on the cycle branch and `git worktree list`.

## /cycle plan DC-NN <theme>

1. List candidate issues: `list_issues` with state `Todo` or `Backlog`, team `NSC`,
   not already in a `DC-*` milestone. Show Ben a table: identifier, title, project,
   blockers, area, a size guess (S/M/L).
2. Propose a set that is buildable and testable on its own: every blocker inside the
   set or already Done; at most one `L`; prefer finishing a spec over starting another.
   Ask Ben as one numbered question with lettered options: (a) the proposed set, (b)
   the proposed set minus the largest item, (c) Ben's own pick.
3. On the answer: `save_milestone` `DC-NN <theme>` on each touched project (a milestone
   belongs to a project; when the set spans projects, create the same-named milestone
   in each), then `save_issue` each chosen issue with that milestone and state `Todo`.
   Linear statuses follow the lifecycle in `CLAUDE.md` (Linear); every verb below names
   its move.
4. The cycle branch exists already when the cycle has a spec (cut by `/spec`). For a
   cycle with no spec of its own, create it: `git branch cycle-N-<theme> master` with the
   next unused N (never `git switch -c`). Put the main checkout back on `master` (clean;
   `git switch master`), clear what earlier cycles left behind with
   `scripts/worktree-sweep.sh --apply`, then keep the cycle branch in its own worktree:
   `git worktree add <scratchpad>/<cycle branch> <cycle branch>`. On the cycle branch,
   record the plan row in `docs/planning/cycles.md` (create from the note template if
   missing): milestone, date, issues, theme. Report.

## /cycle run DC-NN

1. Build the dependency order from `blockedBy`. Group issues into waves: a wave is a set
   of issues with no unmet blockers and no overlapping files (judge from the issues'
   Work sections; when unsure, serialize).
2. For each wave: one `Agent` call per issue, `subagent_type` `implementer`
   (`implementer-engine` when the issue carries `area/engine` or touches
   `godot/engine/`), `isolation: "worktree"`, prompt = the issue's full description plus
   the spec section it points at plus: "Agent worktrees are cut from `master`: first run
   `git merge --ff-only <cycle branch>`. Do not run Godot or make. Never commit. Report
   files changed and anything unverified." When the plan or the issue says where the work
   is, the brief names those files with their functions or line ranges, so the agent does
   not rediscover them. Every brief also lists the typed-strict traps:
   no `:=`; typed loop variables; never pass a Variant into `int()`, `str()` or a typed
   parameter (assign to a typed local first); use the return values of `resize()`,
   `Dictionary.erase()` and `pop_back()` outside tests; no `.uid` files. Three or more
   independent issues in a wave may go through the Workflow tool instead, if Ben has
   opted in. In the same message as the dispatch, move the wave's issues in one call:
   `scripts/linear-move.sh --state "In Progress" NSC-a NSC-b ...` (exit 3 means no API key:
   use the MCP's `save_issue`).
   **Routing trial (ADR 0006):** the first time a wave under `godot/engine/` is only data
   or tests, dispatch it with `implementer` instead, and record its cost and gate results
   in the cycle's row. Remove this trial once a row records the outcome.
3. When a wave returns, land each issue in one call from anywhere:
   `scripts/cycle-land.sh --co-author "<the session's Co-Authored-By name and email>"
   <agent worktree> <cycle worktree> <NN> <issue id> "<title>"`, in the background (the gate
   runs longer than two minutes). It commits the worktree as `dc-NN: <issue id> <title>`,
   merges with `--no-ff` as `cycle-NN: <issue id> <title>`, runs `scripts/check.sh` in the
   cycle worktree and folds generated `.uid` files into the merge commit. Land the wave's
   issues one at a time, and act on the exit code:
   - `0`: green. Move the issue:
     `scripts/linear-move.sh --state "In Review" --comment "Merged as <commit>" <issue id>`.
   - `1`: a red gate stops the wave, and the merge stays. Read the printed gate output, then
     fix a one-line problem yourself or re-dispatch the issue with that output. The issue
     stays `In Progress` with a comment quoting the failing stage. Run planted-failure
     checks under `timeout 120`.
   - `3`: conflict, merge left in progress. Resolve it, or `git merge --abort` and
     re-dispatch with the conflict in the brief.
   - `4`: nothing landed; it says why.
   An issue dropped from the cycle goes back to `Backlog`, milestone removed, with a comment
   saying why.
4. Optional: dispatch `reviewer` on the wave's diff before merging when the wave touches
   `godot/engine/`.
5. When every issue in the wave is merged on a green gate, remove the wave's agent
   worktrees and branches: `scripts/worktree-sweep.sh --into <cycle branch> --apply`. It
   removes only worktrees whose commit is in the cycle branch and whose only leftovers are
   untracked `.uid` files, and skips locked (still-running) agents; an issue awaiting
   re-dispatch keeps its worktree. Read its `keep` lines: anything kept for uncommitted
   changes is work you have not merged yet.
6. Report after each wave: merged, gate result, worktrees removed and kept, remaining
   waves.

## /cycle test DC-NN

The acceptance ritual (P7). A cycle is done only when every box is ticked. A spec may
waive the screenshot for an engine- or tooling-only cycle (DC-01 C12): then the proof is
the gate summary plus the spec's text smoke lines, and steps 2-3 are skipped.

0. Review and simplify (ADR 0004). On `<cycle branch>`, before the gate:
   a. `/code-review medium <cycle branch>` (report only; never `--fix`, `max` or `ultra`
      unless Ben names it; never `--comment`). Sort the findings into blocker /
      should-fix / nit and put them to Ben as one numbered question. Apply accepted
      one-line fixes yourself; dispatch anything larger to `implementer`
      (`implementer-engine` under `godot/engine/`) with the finding quoted. File declined
      findings in Backlog (`type/bug` or `type/chore`, label `spec/<slug>`).
      `scripts/check.sh`; `make sweep` if `godot/engine/` changed. Commit
      `dc-NN: review fixes`.
   b. `/simplify <cycle branch>`. Read its diff: revert anything that weakens a test,
      touches the seeded RNG, the action log or replay, or reaches outside the cycle's
      diff. `scripts/check.sh`; `make sweep` if `godot/engine/` changed. Commit
      `dc-NN: simplify`.
   Either commit is omitted when empty. If a skill is not listed in this session, tell
   Ben, skip it and note the skip in the cycle row. Red means no merge.
1. `scripts/check.sh` on `<cycle branch>`: must exit 0. Paste the stage summary. Then run
   `make sweep` (the 50-seed sweep, outside the gate since NSC-133) and paste its summary
   lines (`Sweep: ...`, the `Sweep pairing` lines, the `stamp=` and `p99_us=` fields).
1b. Ladder provision (`docs/planning/bot-ladder.md`; cycle 11 R5): if this cycle changed
   `RULES_VERSION`, the card pool JSON, the deck list JSON or the Crew JSON (anything that
   moves the stamp), run `make bot-eval` (`random` vs `random`, the rung-0 check) and
   `make sweep` (the `stamp=` and `p99_us=` fields), add a rung-0 row at the new stamp and
   mark every higher rung unproven until it is re-measured against the yardstick. Record
   the outcome in the cycle's row and in the ladder note.
2. Point the editor at the cycle branch: `scripts/godot-editor.sh switch <cycle branch>`.
   It closes any open editor (the MCP port takes one at a time), opens the cycle
   worktree's `godot/` and waits for the MCP plugin. `get_godot_status` must report that
   worktree's path. `run_scene` on the main scene: `get_console_log` must contain
   `Main ready`, and `get_errors` must show no error or warning. If the switch reports an
   editor that will not quit (a save prompt), ask Ben to close it.
3. One screenshot per feature in the cycle: drive the scene through the Godot MCP
   (`send_input`, `call_method`, `set_node_properties`; keyboard and popups are driven
   programmatically) to the state that shows the feature, `take_screenshot`, save under
   `godot/reports/DC-NN/<issue>.png` (gitignored) and upload each to Linear with
   `prepare_file_upload` for the status update.
4. On the cycle branch, append the outcome row to `docs/planning/cycles.md` and commit
   it, then merge `<cycle branch>` into `master` with `--no-ff` (message
   `cycle-NN: <theme>`), only after 1–3 pass, from the main checkout. Hand the editor
   back with `scripts/godot-editor.sh switch main` (the sweep skips a worktree an editor
   still has open), then remove the cycle worktree and every agent worktree merged with it:
   `scripts/worktree-sweep.sh --apply`. The cycle branch itself is kept. Do not push
   unless Ben asks.
5. Linear: `save_status_update` on each touched project ("DC-NN done": gate summary,
   screenshots, what was verified, what was left out); move every DC-NN issue to `Done`
   in one call, only after the step 4 merge (`scripts/linear-move.sh --state Done ...`);
   create follow-up issues in `Backlog` (`type/bug`
   or `type/chore`, label `spec/<slug>`) for anything that failed or was skipped.
   Issues already point at `blob/master/` (ADR 0006), so they resolve once Ben has
   `master` pushed; ask whether to push. A project exercised before ADR 0006 still has
   `blob/<cycle branch>/` links: rewrite those this once.
   Optionally `save_document` with the full test note.
6. Report to Ben with the screenshot paths, the follow-ups and the sweep's last line. Ben's manual
   click-through happens only at milestones; say whether this cycle is one.

## Rules

- Never dispatch an implementer with Godot MCP tools or `make`; the agent files already
  exclude them, do not override with `tools` in the Agent call.
- Never skip the screenshot unless the spec waives it: a cycle without one per feature
  is not done.
- Never push, never force, never rewrite history on `master`, never commit directly on
  `master`: a fix found after the merge goes on a branch of its own (`CLAUDE.md`, Git).
- Leave no merged worktree behind: every verb that merges ends with the sweep above.
  Never `git worktree remove` by hand a worktree the sweep kept without reading why.
- Keep Linear truthful: state changes happen when the merge or test actually happened.
