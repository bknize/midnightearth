---
type: adr
tags: [adr, git, cycles]
status: accepted
related: ["[[decisions/decisions-moc]]", "[[decisions/0001-planning-decisions]]", "[[planning/cycles]]"]
created: 2026-11-03
updated: 2026-11-03
uid: d644d7c5-7644-406e-baac-18b2471bc9fc
supersedes:
---

# ADR 0002 — One branch per dev cycle, from spec to test

## Status

Accepted (Ben, 2026-11-03).

## Context

Until now a dev cycle used three branches, each merged into `master` on its own:
`spec-<slug>` for the spec set, `exercise-<slug>` for the Linear write-back, and
`dc-NN-<theme>` for the code. The spec reached `master` before any code existed,
because `/exercise` wrote GitHub links that point at `master`. While the spec for
cycle 3 (`cycle-3-board-feedback`) was being signed off, Ben said: "I want the
entire cycle to work off of a feature branch, and merge to master when it's complete."

## Decision

Ben's answers on 2026-11-03 (`1b 2b 3a 4a`):

1. **One branch per cycle, named for the spec slug** (1b): `cycle-N-<theme>`, cut from
   `master` at `/spec` before the first note. It carries the spec, the `/exercise`
   write-back, one commit per task, review fixes and the verification outcome. It
   merges into `master` with `--no-ff` only at `/cycle test`. A cycle with no spec of
   its own cuts `cycle-N-<theme>` at `/cycle plan`, with the next unused N. The Linear
   milestone keeps its `DC-NN <theme>` name.
2. **GitHub links point at the cycle branch** (2b). `/exercise` writes
   `blob/<cycle branch>/…` links and asks Ben whether to push the branch so they
   resolve. After the merge, `/cycle test` rewrites every link in the project and its
   issues to `blob/master/…`.
3. **Cycle 3 adopts it now** (3a): `spec-cycle-3-board-feedback` is renamed
   `cycle-3-board-feedback` and keeps its spec commit.
4. **This rule change lands first** (4a), on `tooling-cycle-branch`, merged into `master`
   before `/exercise`, because Claude Code reads skills from the main checkout.

Unchanged: `tooling-<topic>` and `docs-<topic>` changesets keep their own short
branches, nothing is committed directly on `master`, and nothing is pushed unless Ben
asks.

## Consequences

- `master` only ever holds finished cycles: spec, code and verification arrive in one
  `--no-ff` merge, and a dropped cycle leaves `master` untouched.
- The main checkout sits on the cycle branch during `/spec` and `/exercise`, so Obsidian
  shows the new notes. From `/cycle plan` on, the branch lives in its own worktree and
  the main checkout is back on `master`, so until the merge the new notes are visible
  only in the cycle worktree.
- The links in Linear issues resolve only once the cycle branch is pushed, and after the
  merge only once `master` is pushed.
- Changed: `CLAUDE.md` (Git, Linear), the `/spec`, `/exercise` and `/cycle` skills,
  the plan and tasks templates, and the interrogator agent.
