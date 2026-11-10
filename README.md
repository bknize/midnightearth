# Midnight Earth

A fresh start, 2026-11-02. The previous repository, with its full history, is archived
read-only at [bknize/midnightearth-archive](https://github.com/bknize/midnightearth-archive).

## Layout

| Path | What |
|---|---|
| `docs/` | Obsidian vault: planning notes, specs, ADRs, systems. Hidden from Godot by `docs/.gdignore` |
| `godot/` | Godot 4.6.3 project (Mobile renderer) |
| `scripts/` | `bootstrap.sh`, `check.sh` (the build gate), hooks, `claude-with-env.sh` |
| `.claude/` | Agents, skills and hooks for the spec-driven dev loop |

## Bootstrap

```bash
scripts/bootstrap.sh   # installs gdtoolkit, checks Godot, creates .env from .env.example
make check             # import → lint → parse → boot → test; exit 0 means buildable and testable
```

Godot 4.6.3 is expected at `/Applications/Godot 4.6.app`; set `GODOT_BIN` to override.
If `make` stops with "You have not agreed to the Xcode license agreements", either accept it
(`sudo xcodebuild -license accept`) or run make through the command-line tools:
`export DEVELOPER_DIR=/Library/Developer/CommandLineTools`. `scripts/check.sh` works either way.
Launch Claude Code through `scripts/claude-with-env.sh` so `.mcp.json` sees the tokens in `.env`.

Work is planned in `docs/specs/<slug>/` and tracked there too (`docs/dashboard.html` is the overview); see `CLAUDE.md` for the rules.

## How work flows

Every feature goes through the same loop, so agents build against written intent rather
than a vague prompt:

```mermaid
flowchart LR
    idea([Feature idea]) --> spec

    subgraph vault ["Obsidian vault (docs/)"]
        spec["<b>/spec #lt;slug#gt;</b><br/>Interrogator interviews Ben,<br/>writes spec · plan · tasks"]
    end

    subgraph tracker ["Task notes (tasks.md, backlog.md)"]
        plan["<b>/cycle plan DC-NN</b><br/>pick tasks and backlog items,<br/>move the branch to a worktree"]
    end

    subgraph build ["Godot repo (godot/)"]
        run["<b>/cycle run DC-NN</b><br/>implementers in worktrees,<br/>one wave at a time"]
        gate{"make check<br/>green?"}
        test["<b>/cycle test DC-NN</b><br/>Godot MCP screenshot,<br/>merge into master"]
    end

    spec -- "Ben signs off" --> plan
    plan --> run
    run --> gate
    gate -- "no: re-dispatch" --> run
    gate -- yes --> test
    test --> done([Buildable and testable])
```

### The orchestrator pattern

"Orchestrator" is a pattern, not a separate tool: the Claude Code session itself, on
Opus 5.5, owns a dev cycle from start to finish. It picks the cycle's tasks, dispatches
subagents (`.claude/agents/`) to do the work, and is the only role that tests.

| Role | Model | Does | Never |
|---|---|---|---|
| Orchestrator | Opus 5.5 (the session) | Plans cycles, cuts branches, dispatches implementers, commits and merges, runs `make check` and the Godot MCP, keeps the task Status cells and the dashboard | Hands testing to a subagent |
| Interrogator | Fable 5.1 (its own session) | Interviews Ben, writes `spec.md`, `plan.md`, `tasks.md` | Writes code |
| Implementer | Sonnet 5.5 (`implementer-engine`: Opus 5.5 for `godot/engine/`) | Implements one task in its own worktree | Runs Godot, the game or `make check` |
| Reviewer | Sonnet 5.5 | Ranks findings on a diff before the gate | Edits |

Implementers get no test feedback beyond the PostToolUse hook (gdlint and a parse check
on every saved `.gd`). That keeps the slow, stateful part, running Godot, in one place:
the orchestrator merges each wave onto the cycle branch, runs the gate, and a cycle is
done only when it is buildable and testable.

### The interrogator pattern

Before anything is built, `/spec <slug>` opens a Fable session as the interrogator. It reads
the planning notes and existing specs, then questions Ben in short rounds of numbered
plain-text questions with lettered options, its recommendation first and costed where
options differ. It stops asking once answers stop changing the design, then writes:

- `spec.md`: requirements as EARS sentences about behaviour, never implementation, with
  every `[NEEDS CLARIFICATION]` resolved before the plan;
- `plan.md`: the approach, checked against `CLAUDE.md` (the constitution);
- `tasks.md`: small, buildable tasks, each with a `Status` cell the orchestrator keeps.

The point is to capture intent, constraints and done-criteria up front, so implementers
that cannot run the game still build the right thing.

## Obsidian: the spec vault

`docs/` is an Obsidian vault and the project's long-term memory: planning phases and
their decisions (`docs/planning/`), ADRs (`docs/decisions/`), game-design notes
(`docs/systems/`) and one spec set per feature (`docs/specs/<slug>/`). It is plain
Markdown in git, so agents read and write it as files; Obsidian adds what files alone do
not, for Ben and for the agents:

- `[[wikilinks]]` and maps of content (`*-moc.md`) tie specs, plans and decisions
  together, and the official CLI audits them (`obsidian-cli vault=docs unresolved` and
  `… orphans`) after every writing session.
- Every note has the same frontmatter (`docs/Templates/note.md`), including a stable
  `uid` for deep links (`obsidian://adv-uri?vault=docs&uid=…`, opened by the Advanced URI
  plugin), so links survive renames.

`docs/.gdignore` hides the vault from Godot, and `docs/.obsidian/` is Ben's editor state,
which agents do not touch.

## Tasks: the work record

The vault also records *how far the work has got*; there is no ticket tracker
(`docs/decisions/0007-no-ticket-tracker.md`). Each task is a row of a spec's `tasks.md`
with a `Status` cell: `todo`, then `done` once its work is merged onto the cycle branch on
a green gate, or `dropped`. Work that belongs to no spec (follow-ups, bugs, ideas) is a
`B-nn` row in `docs/planning/backlog.md`, and `docs/planning/cycles.md` has one row per
dev cycle. Only the orchestrator changes a status, when the event has actually happened;
subagents report to it.

`make dashboard` reads those notes and writes `docs/dashboard.html`: every cycle, its
tasks and verification boxes, and the backlog, on one static page. It runs at the end of
each cycle, in `/cycle test`.
