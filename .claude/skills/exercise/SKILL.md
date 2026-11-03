---
name: exercise
description: Turn an approved spec's tasks.md into Linear issues under a project for that spec. Use after /spec sign-off, when Ben says "exercise <slug>", "create the Linear issues", or "push this spec to Linear".
allowed-tools: Read, Edit, Bash, Grep, Glob
---

# /exercise <slug>

Converts `docs/specs/<slug>/tasks.md` into a Linear project with one issue per task.
Read `CLAUDE.md` first. Requires the Linear MCP (connected in this repo's `.mcp.json`).

## Preconditions

1. `docs/specs/<slug>/spec.md` has `status: approved` (or `clarified` with Ben's explicit
   go-ahead in this conversation). Otherwise stop and say what is missing.
2. `tasks.md` has the task table (`# | Task | Area | Depends on | Acceptance check | Who`).
3. The three notes have a `uid`. If `linear` is already filled, this is a re-run: update
   existing issues by title prefix (`Tnn`) instead of creating duplicates.
4. Branch `spec-<slug>` is merged into `master` (`git branch --merged master`), so the
   GitHub links in step 2 resolve. Otherwise stop and ask Ben to merge it.

## Steps

1. **Label.** Ensure `spec/<slug>` exists (`list_issue_labels`, else `save_issue_label`,
   color `#26B5CE`). Area labels map from the Area column: engine, cards, ui, tooling,
   docs → `area/<x>`. Type label: `type/feature` for player-visible or engine behaviour,
   `type/chore` for tooling and docs, `type/bug` only when the spec says so.
2. **Project.** `save_project` with the spec's title, team `NSC`, lead `me`, `state`
   `planned`, description = the spec's Intent paragraph, then a `## Spec` section with:
   `obsidian://adv-uri?vault=docs&uid=<spec uid>` and the GitHub blob URLs for spec, plan
   and tasks on `master`. Add `links` for spec.md and tasks.md.
3. **Issues.** For each task row, `save_issue` with:
   - title `Tnn <task>` (two-digit nn),
   - team `NSC`, project from step 2, labels from step 1,
   - description: `## Spec` (vault link using the **tasks** uid, GitHub tasks URL,
     "(task nn; requirements …)"), `## Work` (the row's task text expanded from plan.md),
     `## Acceptance` as checkboxes from the Acceptance column, and when Who is a
     subagent add "Suitable for a <who> subagent."
   Create all issues first, then a second pass per issue with `blockedBy` from the
   Depends column (task n → the identifier created for row n) and `state` `Todo`.
4. **Write back.** Put the project URL into the `linear:` field of spec.md, plan.md and
   tasks.md, and append a `## Linear (exercised <date>)` section to tasks.md with the
   project link and the row → identifier mapping. Do not commit unless Ben asks; the
   write-back is its own changeset, committed on branch `exercise-<slug>` cut from
   `master` (never on `master`), then merged with `--no-ff` when Ben says.
5. **Report** in a short table: issue identifier, title, blockers. Say the next verb is
   `/cycle plan DC-NN` and that the project is in `planned` until a cycle picks it up.

## Rules

- Never create a Linear team, cycle, or template (the MCP cannot; those are Ben's).
- One task, one issue. Do not split or merge rows; if a row is too big, say so and stop.
- Keep under the Free plan's 250 open issues: if the team has more than 200 open, warn.
- Issue identifiers are `NSC-n`.
