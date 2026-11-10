---
type: tasks
tags: [tasks, <slug>]
status: draft
related: ["[[specs/<slug>/spec]]", "[[specs/<slug>/plan]]", "[[planning/phase-1-tech-stack]]"]
created: YYYY-MM-DD
updated: YYYY-MM-DD
uid: <uuid4 from `uuidgen | tr A-Z a-z`>
supersedes:
---

# Tasks: <feature name>

Derived from [[specs/<slug>/plan|plan]]. Numbered, dependency-ordered, independently
reviewable. Each task names its area, its acceptance check and who does it.
`implementer` edits code in a worktree; `implementer-engine` takes anything under
`godot/engine/`; `reviewer` reads a diff and returns findings; `orchestrator` runs
`make check`, drives the Godot MCP and keeps the Status column. A row starts `todo`; it
becomes `done` when its work is merged into the cycle branch on a green gate, or `dropped`
with the reason (`CLAUDE.md`, Tasks).

| # | Task | Area | Depends on | Acceptance check | Who | Status |
|---|---|---|---|---|---|---|
| 1 | <task> | scene / engine / shader / tooling / vault | – | <observable check> | implementer | todo |
| 2 | <task> | | 1 | | implementer-engine | todo |
| 3 | <task; name any backlog item it closes, `B-nn`> | | 1, 2 | | reviewer | todo |

## Verification task (always last)

Task N, owned by the orchestrator:

- [ ] `make check` exits 0.
- [ ] <end-to-end proof of the whole feature: gdUnit4 suite names, scene run through the Godot MCP, runtime log line, or vault diff review>
- [ ] One `take_screenshot` per visible feature (P7), saved under `godot/reports/DC-NN/`.
- [ ] `obsidian-cli vault=docs unresolved` reports nothing new.

## Commit plan

The whole cycle is one changeset on one branch named for the spec slug
(`cycle-N-<theme>`; `CLAUDE.md`, Git), cut from `master` at `/spec` before the first
note. It carries the spec (`spec: <slug>`),
one commit per task (`dc-NN: T<nn> <task title>`), review fixes and the verification
outcome, each message ending with the Co-Authored-By line the session provides. When the
verification task passes, `/cycle test` merges the branch into `master` with a merge
commit (`git merge --no-ff`) so the cycle stays visible in history. Nothing is committed
directly on `master`.
