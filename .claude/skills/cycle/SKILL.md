---
name: cycle
description: Run a Midnight Earth dev cycle - plan it (pick Linear issues into a DC-NN milestone), run it (dispatch implementer subagents in worktrees), or test it (merge, make check, Godot MCP screenshots, Linear status update). Use for "/cycle plan DC-01", "/cycle run", "/cycle test", "start the next cycle", "dispatch the cycle", "close out the cycle".
allowed-tools: Read, Edit, Write, Bash, Grep, Glob, Agent
---

# /cycle <plan|run|test> DC-NN

The orchestrator's verbs. Read `CLAUDE.md` first. You are the orchestrator session: you
dispatch, you merge, you test. Implementers never run Godot; you do. `$ARGUMENTS` is
`<verb> DC-NN [theme]`.

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
4. Create the branch `git branch dc-NN-<theme> master` (never `git switch -c`: the main
   checkout stays on `master`) and keep it in its own worktree:
   `git worktree add <scratchpad>/dc-NN-<theme> dc-NN-<theme>`. On the cycle branch,
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
   `git merge --ff-only dc-NN-<theme>`. Do not run Godot or make. Never commit. Report
   files changed and anything unverified." Every brief also lists the typed-strict traps:
   no `:=`; typed loop variables; never pass a Variant into `int()`, `str()` or a typed
   parameter (assign to a typed local first); use the return values of `resize()`,
   `Dictionary.erase()` and `pop_back()` outside tests; no `.uid` files. Three or more
   independent issues in a wave may go through the Workflow tool instead, if Ben has
   opted in. Move each issue to `In Progress` in Linear in the same message as its
   dispatch.
3. When a wave returns: commit each worktree as `dc-NN: <issue id or Tnn> <title>`, then
   merge it from the cycle worktree into `dc-NN-<theme>` (`--no-ff`, message
   `cycle-NN: <issue id> <title>`); on conflict, resolve or re-dispatch with the
   conflict in the brief. Run `scripts/check.sh` there after every merge; after a green
   gate fold any generated `.uid` files into the merge commit. A red gate stops the
   wave: open the report, either fix a one-line problem yourself or re-dispatch the
   issue with the gate output; the issue stays `In Progress` with a comment quoting the
   failing stage. Run planted-failure checks under `timeout 120`. On a green gate move
   the issue to `In Review` in Linear with a one-line comment naming the merge commit.
   An issue dropped from the cycle goes back to `Backlog`, milestone removed, with a
   comment saying why.
4. Optional: dispatch `reviewer` on the wave's diff before merging when the wave touches
   `godot/engine/`.
5. Report after each wave: merged, gate result, remaining waves.

## /cycle test DC-NN

The acceptance ritual (P7). A cycle is done only when every box is ticked. A spec may
waive the screenshot for an engine- or tooling-only cycle (DC-01 C12): then the proof is
the gate summary plus the spec's text smoke lines, and steps 2-3 are skipped.

1. `scripts/check.sh` on `dc-NN-<theme>`: must exit 0. Paste the stage summary.
2. Open the Godot editor on `godot/` (ask Ben if it is not already open; the MCP needs
   it). `get_godot_status` must report connected. `run_scene` on the main scene,
   `get_runtime_log` must contain `Main ready` and no error pattern.
3. One screenshot per feature in the cycle: drive the scene through the Godot MCP
   (`send_input`, `call_method`, `set_node_properties`; keyboard and popups are driven
   programmatically) to the state that shows the feature, `take_screenshot`, save under
   `godot/reports/DC-NN/<issue>.png` (gitignored) and upload each to Linear with
   `prepare_file_upload` for the status update.
4. Merge `dc-NN-<theme>` into `master` with `--no-ff` (message `cycle-NN: <theme>`),
   only after 1–3 pass, from the main checkout. Do not push unless Ben asks.
5. Linear: `save_status_update` on each touched project ("DC-NN done": gate summary,
   screenshots, what was verified, what was left out); move every DC-NN issue to
   `Done` (only after the step 4 merge); create follow-up issues in `Backlog` (`type/bug`
   or `type/chore`, label `spec/<slug>`) for anything that failed or was skipped.
   Optionally `save_document` with the full test note.
6. Append the outcome to `docs/planning/cycles.md`. Report to Ben with the screenshot
   paths and the follow-ups. Ben's manual click-through happens only at milestones; say
   whether this cycle is one.

## Rules

- Never dispatch an implementer with Godot MCP tools or `make`; the agent files already
  exclude them, do not override with `tools` in the Agent call.
- Never skip the screenshot unless the spec waives it: a cycle without one per feature
  is not done.
- Never push, never force, never rewrite history on `master`.
- Keep Linear truthful: state changes happen when the merge or test actually happened.
