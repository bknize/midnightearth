# Midnight Earth — constitution

A 3D card game in Godot 4.6.3 for desktop and iOS, built feature by feature through a
spec-driven agent loop. Planning record: `docs/planning/` (21 decisions D1–D8, P1–P8,
R1–R9). This file is the short version every agent must obey.

## Layout

| Path | What | Rules |
|---|---|---|
| `docs/` | Obsidian vault (notes, specs, ADRs) | Plain Markdown + `[[wikilinks]]`; `.gdignore` hides it from Godot |
| `docs/specs/<slug>/` | `spec.md`, `plan.md`, `tasks.md` per feature | Written by `/spec`, exercised into Linear by `/exercise` |
| `godot/` | The Godot project | Mobile renderer, Compatibility-clean shaders (D2) |
| `godot/engine/` | Pure match engine (from cycle 1) | Typed GDScript, deterministic, seeded RNG, serializable action log (D4) |
| `godot/addons/` | Vendored third-party code | Never edit except through a patch recorded in `addons/THIRD_PARTY_LICENSES.md` |
| `godot/tests/` | gdUnit4 suites | One suite per engine module |
| `scripts/` | Gate, hooks, bootstrap, wrapper, `godot-editor.sh` (status / close / open / switch the editor between checkouts) | Bash, `set -uo pipefail` |
| `.claude/` | Agents, skills, hook settings | The orchestrator pattern lives here |

## The build gate: `make check`

`scripts/check.sh` runs import → lint → parse → boot → test and exits 0 only when all
five pass. Godot's exit codes are never trusted: every stage greps its output for
`SCRIPT ERROR|Parse Error|Failed to load script|ERROR:`. Boot must print `Main ready`.
gdUnit4 exit 0 or 101 is a pass. A cycle's only acceptance criterion is "buildable and
testable", which means `make check` is green plus one screenshot per feature from the
Godot MCP (P7). If `make` itself fails on the Xcode license, use `scripts/check.sh`.

Single stages: `make import|lint|parse|boot|test`. `parse` promotes the typed-GDScript
warnings to errors, so every project `.gd` is fully typed; test suites are exempt from
`return_value_discarded` only.

## Roles (P1)

- **Orchestrator** — the Claude Code session (Opus 5.5). Owns a dev cycle, dispatches
  implementers, runs `make check`, drives the Godot MCP, posts to Linear.
- **Interrogator** (`.claude/agents/interrogator.md`, Fable 5.1) — interviews Ben in
  plain-text rounds and writes spec/plan/tasks. Never writes code.
- **Implementer** (`implementer.md` Sonnet 5.5; `implementer-engine.md` Opus 5.5 for
  `godot/engine/`) — edits code in a worktree. **Never runs the game, Godot, or
  `make check`.** Its only feedback is the PostToolUse hook (gdlint + parse). It reports
  what it changed and what it could not verify.
- **Reviewer** (`reviewer.md`, Sonnet 5.5) — read-only findings.

Cycle verbs: `/spec <slug>` → `/exercise <slug>` → `/cycle plan DC-NN` → `/cycle run
DC-NN` → `/cycle test DC-NN`.

## Notes (P5)

Every note in `docs/` has this frontmatter: `type` (spec | plan | tasks | adr | system |
planning | moc | reference), `tags`, `status`, `related`, `created`, `updated`, `uid`
(uuid4, for `obsidian://adv-uri?vault=docs&uid=`), `linear` (issue or project URL),
`supersedes`. Template: `docs/Templates/note.md`. Link with `[[path/from/vault/root]]`.
After writing notes run `obsidian-cli vault=docs unresolved` and `… orphans`
(the `vault=` flag goes before the command).

## Linear (P4)

One team (key `NSC`), a project per spec, a milestone per dev
cycle (`DC-NN <theme>`), labels `area/*`, `type/*`, `spec/<slug>`. Every issue carries a
`## Spec` section with the vault uid link and the GitHub blob URL (on the cycle branch
until `/cycle test` merges it, then rewritten to `master`). The orchestrator pulls
issues through the Linear MCP; nothing is pushed from Linear.

Issue status is the orchestrator's job, moved when the event actually happens, never
ahead of it: **Backlog** (follow-ups and ideas outside a cycle) → **Todo** (`/exercise`,
or picked at `/cycle plan`) → **In Progress** (its implementer is dispatched; a red gate
or re-dispatch keeps it here, with a comment quoting the failure) → **In Review** (merged
into the cycle branch on a green gate; comment names the merge commit) → **Done** (the
cycle branch is merged into `master` at `/cycle test`). An issue dropped from a cycle goes
back to Backlog with its milestone removed and a comment saying why. Subagents have no
Linear access; they report, and the orchestrator updates Linear.

## Git

Every changeset gets its own branch, cut from `master` before its first edit (never at
commit time) and named for the set. **A dev cycle is one changeset from spec to test**
(`docs/decisions/0002-one-branch-per-cycle.md`): its branch is named for the spec slug,
`cycle-N-<theme>`, cut at `/spec`, and carries the spec, the `/exercise` write-back, one
commit per task, review fixes and the verification outcome. It merges into `master` only
at `/cycle test`, when the cycle is complete. A cycle with no spec of its own cuts
`cycle-N-<theme>` at `/cycle plan`, with the next unused N. Anything else is
`tooling-<topic>` or `docs-<topic>`. Nothing is committed directly on `master`: it only
takes `--no-ff` merges of those branches, made when Ben asks or a verb's steps say so
(`/cycle test`). Commit only when Ben asks or the task list says so. Commit messages end
with the Co-Authored-By line the session provides. Never push unless Ben asks.

The main checkout sits on the cycle branch during `/spec` and `/exercise`, so the vault
shows the new notes; from `/cycle plan` on, the branch lives in its own `git worktree`
and the main checkout is back on `master`. Leave the main checkout on `master` between
changesets; when another session may share it, create the branch with `git branch` and
work in a worktree.

## Secrets (P6)

Tokens live only in `.env` (gitignored). `.mcp.json` uses `${VAR}` placeholders.
Launch through `scripts/claude-with-env.sh`. Never print a token in chat, a note, a
commit or a Linear comment.

## Do not touch

- `docs/.obsidian/` — Ben's editor state (only `.gitignore` refers to it).
- `godot/addons/*` — except via a patch recorded in `THIRD_PARTY_LICENSES.md`.
- `.env`, `godot/.godot/`, `godot/reports/` — generated or secret.
- The archive at `../midnightearth-archive` — read-only reference.

## Working with Ben

Ask decisions as numbered plain-text questions with lettered options, recommendation (a)
first, costed where cost differs. No widgets. Record every decision in the relevant note.
