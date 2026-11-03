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
| `scripts/` | Gate, hooks, bootstrap, wrapper | Bash, `set -uo pipefail` |
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
`## Spec` section with the vault uid link and the GitHub blob URL. The orchestrator pulls
issues through the Linear MCP; nothing is pushed from Linear.

## Git

Work for a set lands on a branch named for the set (`cycle-0-scaffolding`,
`dc-01-<theme>`), one commit per task, merged into `master` with `--no-ff`. Commit only
when Ben asks or the task list says so. Commit messages end with the Co-Authored-By line
the session provides.

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
