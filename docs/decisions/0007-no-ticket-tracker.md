---
type: adr
tags: [adr, cycles, tasks, tooling]
status: accepted
related: ["[[decisions/decisions-moc]]", "[[decisions/0001-planning-decisions]]", "[[decisions/0006-token-spend]]", "[[planning/backlog]]", "[[planning/cycles]]"]
created: 2026-11-09
updated: 2026-11-09
uid: 129e7d03-b044-4649-ae42-fddcd800b00a
supersedes:
---

# ADR 0007 — No ticket tracker: tasks live in the vault

## Status

Accepted (Ben, 2026-11-09: "1a 2a 3a 4c" on the scope for dropping Linear). Replaces
planning decision P4 in [[decisions/0001-planning-decisions]], and the Linear parts of
[[decisions/0006-token-spend]] (the `blob/master` link rule and `scripts/linear-move.sh`).

## Context

Linear held one issue per task, a project per spec and a milestone per dev cycle. On
2026-11-09 the workspace reached the issue limit of its plan (275 issues), and Ben had
"not found any value in representing progress in Linear". The orchestrator also paid for
it: every status move was a tool call, and `/exercise` copied each `tasks.md` row into an
issue that then had to be kept in step with the note.

A `tasks.md` recorded no completion of its own. "Done" lived in Linear, in commit
subjects and in the Outcome column of [[planning/cycles]].

## Decision

1. **Completion lives in the task table** (1a). Every task table has a `Status` column:
   `todo`, `done` or `dropped`. `scripts/cycle-land.sh --tasks <note>` sets `done` when the
   task's merge passes the gate, and folds the change into the merge commit. Only the
   orchestrator changes a status.
2. **The backlog is a note.** Work outside any spec is a `B-nn` row of
   [[planning/backlog]], `open`, `done` or `dropped`.
3. **A static dashboard, tracked** (2a). `make dashboard` runs `scripts/dashboard.py`
   (standard library), which reads every `tasks.md`, [[planning/cycles]] and the backlog
   and writes `docs/dashboard.md`, a vault note with wikilinks to every spec (first written as `docs/dashboard.html`; changed the same day on Ben's "1a" to the question of a note or a page). `/cycle test` runs it before the merge into `master`.
4. **Grouped by spec** (3a). The page has one block per spec, labelled with the dev cycles
   that built it, because one `tasks.md` can span two cycles.
5. **Old ids rewritten** (4c). Every `NSC-nnn` in the repo became the task it stood for
   (`cycle-N Tnn`) or, for an issue that was never a task, a backlog id (B-01 to B-63, in
   the order the issues were filed). The `linear:` frontmatter field, the
   "Linear (exercised …)" sections and the links to linear.app are gone. Prose in older
   notes that describes the Linear process is left as the record of what was done then.
6. **Removed:** the `/exercise` skill, `scripts/linear-move.sh`, the `linear` server in
   `.mcp.json`, `LINEAR_API_KEY` in `.env.example`. The cycle verbs are
   `/spec` → `/cycle plan` → `/cycle run` → `/cycle test`.

## Consequences

- The record cannot drift from the repo: a status is part of the commit that earns it, and
  `master` shows a task done only once its cycle has merged.
- An implementer's brief is built from the task row, `plan.md` and the spec, not from an
  issue description. A thin task row now shows up as a thin brief, so `/spec` has to write
  rows that stand on their own with the plan.
- There is no in-flight state ("In Progress", "In Review"). `git worktree list` and the
  cycle branch's log show what is in flight.
- Status at the migration came from Linear's export of 2026-11-09: 208 of 211 task rows
  done, 7 backlog items open.
- Ben removes `LINEAR_API_KEY` from `.env`, revokes the key, and disconnects the Linear
  connector from his account; the repo cannot do those.
