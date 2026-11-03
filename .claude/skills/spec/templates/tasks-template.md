---
type: tasks
tags: [tasks, <slug>]
status: draft
related: ["[[specs/<slug>/spec]]", "[[specs/<slug>/plan]]", "[[planning/phase-1-tech-stack]]"]
created: YYYY-MM-DD
updated: YYYY-MM-DD
uid: <uuid4 from `uuidgen | tr A-Z a-z`>
linear:
supersedes:
---

# Tasks: <feature name>

Derived from [[specs/<slug>/plan|plan]]. Numbered, dependency-ordered, independently
reviewable. Each task names its area, its acceptance check and who does it.
`implementer` edits code in a worktree; `implementer-engine` takes anything under
`godot/engine/`; `reviewer` reads a diff and returns findings; `orchestrator` runs
`make check`, drives the Godot MCP and handles Linear.

| # | Task | Area | Depends on | Acceptance check | Who |
|---|---|---|---|---|---|
| 1 | <task> | scene / engine / shader / tooling / vault | – | <observable check> | implementer |
| 2 | <task> | | 1 | | implementer-engine |
| 3 | <task> | | 1, 2 | | reviewer |

## Verification task (always last)

Task N, owned by the orchestrator:

- [ ] `make check` exits 0.
- [ ] <end-to-end proof of the whole feature: gdUnit4 suite names, scene run through the Godot MCP, runtime log line, or vault diff review>
- [ ] One `take_screenshot` per visible feature (P7), attached to the Linear status update.
- [ ] `obsidian-cli vault=docs unresolved` reports nothing new.

## Linear

Filled by `/exercise <slug>`. Empty until then.

- Project: <URL>
- Milestone: <DC-NN theme>
- Issue mapping: task n is issue <KEY-m> (T01 = <KEY-…> … T<N> = <KEY-…>)

## Commit plan

One commit per task on a branch named for the set (`<slug>` or `dc-NN-<theme>`).
Messages: `<set>: T<nn> <task title>`, ending with the Co-Authored-By line the session
provides. When the verification task passes, the branch merges into `master` with a
merge commit (`git merge --no-ff`) so the set stays visible in history. The spec set
itself is committed on `master` first as `spec: <slug>`, and only when Ben says to.
