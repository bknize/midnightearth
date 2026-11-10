# Midnight Earth — constitution

A 3D card game in Godot 4.6.3 for desktop and iOS, built feature by feature through a
spec-driven agent loop. Planning record: `docs/planning/` (21 decisions D1–D8, P1–P8,
R1–R9). This file is the short version every agent must obey.

## Layout

| Path | What | Rules |
|---|---|---|
| `docs/` | Obsidian vault (notes, specs, ADRs) | Plain Markdown + `[[wikilinks]]`; `.gdignore` hides it from Godot |
| `docs/specs/<slug>/` | `spec.md`, `plan.md`, `tasks.md` per feature | Written by `/spec`; the `Status` column of `tasks.md` is the progress record (ADR 0007) |
| `godot/` | The Godot project | Mobile renderer, Compatibility-clean shaders (D2) |
| `godot/engine/` | Pure match engine (from cycle 1) | Typed GDScript, deterministic, seeded RNG, serializable action log (D4) |
| `godot/net/` | Client network code (from cycle 12) | Protocol, codec, `NetClient`, `RemoteMatchSource`, the headless bot client; typed GDScript, no engine state on the client (ADR 0005) |
| `godot/server/` | PVP match server (from cycle 12) | Headless, server-authoritative, runs on the testing PC; rooms, hardening, PVP logs; no clock or RNG inside `godot/engine/` (ADR 0005) |
| `godot/title/` | Title and PVP entry screens (from cycle 12) | Title screen, waiting screen, device `Identity`, `PvpSession`; `main.gd` owns the flow, and the screens only raise signals |
| `trainer/` | Bot trainer service and learner (from cycle 11) | Python 3 standard library plus `mcp` and, for `fit`, numpy; runs on the training PC as an MCP service (labelling runs, `fit`, run store); unit tests with `make trainer-test`; setup in `trainer/windows/SETUP.md` |
| `scripts/pc/` | Files deployed to the training PC | Windows `.cmd` launchers (the PVP server start script); copied by hand or through the runner queue, never run on the Mac |
| `godot/addons/` | Vendored third-party code | Never edit except through a patch recorded in `addons/THIRD_PARTY_LICENSES.md` |
| `godot/tests/` | gdUnit4 suites | One suite per engine module |
| `godot/art/` | Approved art (`/art approve`) | Git LFS; every image has an entry in `art/manifest.json` (ADR 0003) |
| `art/` | `manifest.json` (tracked); `candidates/` and `ledger.jsonl` (gitignored) | Written only by the artist and `scripts/art-*` |
| `scripts/` | Gate, hooks, bootstrap, wrapper, `godot-editor.sh` (status / close / open / switch the editor between checkouts), `worktree-sweep.sh` (remove merged worktrees), `art-fetch.sh` / `art-approve.sh` / `art-sheet.py` (art pipeline), `replicate-mcp.sh` (starts the Replicate MCP with the `.env` token), `cycle-land.sh` (commit, merge and gate one task, then mark it done), `dashboard.py` (writes `docs/dashboard.html` from the task notes; `--set` changes one Status cell) | Bash, `set -uo pipefail`; `art-sheet.py` (Pillow) and `dashboard.py` (standard library) are Python |
| `.claude/` | Agents, skills, hook settings | The orchestrator pattern lives here |

## The build gate: `make check`

`scripts/check.sh` runs import → lint → parse → boot → test and exits 0 only when all
five pass. Godot's exit codes are never trusted: every stage greps its output for
`SCRIPT ERROR|Parse Error|Failed to load script|ERROR:`. Boot must print `Main ready`.
gdUnit4 exit 0 or 101 is a pass. A cycle's only acceptance criterion is "buildable and
testable", which means `make check` is green plus one screenshot per feature from the
Godot MCP (P7). If `make` itself fails on the Xcode license, use `scripts/check.sh`.
Before the gate, `/cycle test` runs `/code-review medium` then `/simplify` on the cycle's
diff, report-only and `medium` unless Ben names otherwise, never `ultra` unprompted
(`docs/decisions/0004-review-tools-in-the-cycle.md`).

`make sweep` runs the 50-seed bot sweep (`godot/tests/sweep/`) outside the gate, at
`/cycle test` and for bot reruns; `make sweep BOT=<name>` sweeps another bot.

Single stages: `make import|lint|parse|boot|test`. `parse` promotes the typed-GDScript
warnings to errors, so every project `.gd` is fully typed; test suites are exempt from
`return_value_discarded` only.

## Roles (P1)

- **Orchestrator** — the Claude Code session (Opus 5.5). Owns a dev cycle, dispatches
  implementers, runs `make check`, drives the Godot MCP, keeps the task statuses, runs
  `/code-review` and `/simplify` at `/cycle test`. Each verb starts in a new session, and
  `/cycle run` starts another at a wave boundary past about 250k of context (ADR 0006).
- **Interrogator** — a top-level session on Fable 5.1, one per `/spec` (ADR 0006);
  interviews Ben in plain-text rounds and writes spec/plan/tasks. Never writes code and
  never answers for Ben.
- **Implementer** (`implementer.md` Sonnet 5.5; `implementer-engine.md` Opus 5.5 for
  `godot/engine/`) — edits code in a worktree. **Never runs the game, Godot, or
  `make check`.** Its only feedback is the PostToolUse hook (gdlint + parse). It reports
  what it changed and what it could not verify.
- **Reviewer** (`reviewer.md`, Sonnet 5.5) — read-only findings.
- **Artist** (`artist.md`, Fable 5.1) — dispatched by `/art`; interviews Ben on art
  direction (relayed through the orchestrator), generates candidates through the Replicate
  MCP within the image cap in its brief, and shows contact sheets. Never edits code or
  imports art; the orchestrator approves picks with `scripts/art-approve.sh`.

Cycle verbs: `/spec <slug>` → `/cycle plan DC-NN` → `/cycle run
DC-NN` → `/cycle test DC-NN`. Art verbs, outside the cycle: `/art direction | explore |
generate | approve`.

## Notes (P5)

Every note in `docs/` has this frontmatter: `type` (spec | plan | tasks | adr | system |
planning | moc | reference), `tags`, `status`, `related`, `created`, `updated`, `uid`
(uuid4, for `obsidian://adv-uri?vault=docs&uid=`),
`supersedes`. Template: `docs/Templates/note.md`. Link with `[[path/from/vault/root]]`.
After writing notes run `obsidian-cli vault=docs unresolved` and `… orphans`
(the `vault=` flag goes before the command).

## Tasks (ADR 0007)

The vault is the only record of the work; there is no ticket tracker. A task is a row of
`docs/specs/<slug>/tasks.md`, cited as `T07` inside its cycle and `cycle-N T07` outside
it. Work outside any spec (follow-ups, bugs, ideas) is a row of
`docs/planning/backlog.md`, cited as `B-nn`. `docs/planning/cycles.md` has one row per
dev cycle (`DC-NN <theme>`).

A row's `Status` cell is the orchestrator's job, changed when the event actually happens,
never ahead of it: a task is **todo** (written by `/spec`; a red gate or re-dispatch keeps
it here) → **done** (merged into the cycle branch on a green gate, set by
`scripts/cycle-land.sh`) or **dropped** (left out of the cycle, with the reason in the
row). A backlog item is **open** → **done** or **dropped** the same way. The cells live on
the cycle branch, so `master` shows a task done only once the cycle has merged. Subagents
never edit a Status cell; they report, and the orchestrator sets it
(`scripts/dashboard.py --set <note> <id> <status>`). `/cycle test` runs `make dashboard`,
which rewrites `docs/dashboard.html` from these notes.

## Git

Every changeset gets its own branch, cut from `master` before its first edit (never at
commit time) and named for the set. **A dev cycle is one changeset from spec to test**
(`docs/decisions/0002-one-branch-per-cycle.md`): its branch is named for the spec slug,
`cycle-N-<theme>`, cut at `/spec`, and carries the spec, one
commit per task, review fixes and the verification outcome. It merges into `master` only
at `/cycle test`, when the cycle is complete. A cycle with no spec of its own cuts
`cycle-N-<theme>` at `/cycle plan`, with the next unused N. Approved art lands
on `art-<batch>` (or the cycle branch it belongs to). Anything else is
`tooling-<topic>` or `docs-<topic>`. Nothing is committed directly on `master`: it only
takes `--no-ff` merges of those branches, made when Ben asks or a verb's steps say so
(`/cycle test`). Commit only when Ben asks or the task list says so. Commit messages end
with the Co-Authored-By line the session provides. Never push unless Ben asks.

The main checkout sits on the cycle branch during `/spec`, so the vault
shows the new notes; from `/cycle plan` on, the branch lives in its own `git worktree`
and the main checkout is back on `master`. `/cycle run` sweeps each wave's agent
worktrees once merged and `/cycle test` sweeps the cycle worktree after the `master`
merge (`scripts/worktree-sweep.sh`). Leave the main checkout on `master` between
changesets; when another session may share it, create the branch with `git branch` and
work in a worktree.

## Secrets (P6)

Tokens live only in `.env` (gitignored). `.mcp.json` uses `${VAR}` placeholders.
Launch through `scripts/claude-with-env.sh`. Never print a token in chat, a note, a
commit.

## Do not touch

- `docs/.obsidian/` — Ben's editor state (only `.gitignore` refers to it).
- `godot/addons/*` — except via a patch recorded in `THIRD_PARTY_LICENSES.md`.
- `.env`, `godot/.godot/`, `godot/reports/` — generated or secret.
- The archive at `../midnightearth-archive` — read-only reference.

## Working with Ben

Ask decisions as numbered plain-text questions with lettered options, recommendation (a)
first, costed where cost differs. No widgets. Record every decision in the relevant note.
