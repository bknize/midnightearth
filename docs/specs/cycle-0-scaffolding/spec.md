---
type: spec
tags: [spec, cycle-0, scaffolding]
status: approved
related: ["[[planning/phase-1-tech-stack]]", "[[planning/phase-2-dev-tools]]", "[[planning/phase-3-game-loop]]"]
created: 2026-11-02
updated: 2026-11-02
uid: 8185c02f-3b93-4b9d-9c11-651bcb7784bf
linear: https://linear.app/night-science-llc/project/cycle-0-scaffolding-6db3f9c856a0
supersedes:
---

# Spec: Cycle 0 — scaffolding

**Slug:** `cycle-0-scaffolding`  ·  **Change type:** infra  ·  **Status:** clarified (Ben, 2026-11-02: 1a 2a 3a 4a)

Cycle 0 builds the floor every later cycle stands on: the repo layout, an empty Godot
project that passes one gate, the gate itself, the agent roles and skills that make up
the orchestrator pattern, the MCP wiring, the Linear structure, and the vault
conventions. It ships no game code. It is the one cycle whose spec is written before
the pattern that will write all other specs exists, so this session acts as the
interrogator and the orchestrator for it.

## Intent

After cycle 0, a fresh clone of the repo can run `make check` and get a green result on
an empty Godot 4.6.3 project with one passing gdUnit4 test, and a Claude Code session
opened in the repo has the agents, skills, hooks and MCP servers it needs to run cycle 1
through the `/spec → /exercise → /cycle` lifecycle.

## Non-goals

- No game code, no card scenes, no match engine, no UI. The main scene is a placeholder.
- No art generation. The Replicate entry is wired but not exercised.
- No iOS or Windows export presets. Those arrive with the first milestone build (D8).
- No Erodenn runtime MCP trial; that needs something on screen to capture (D6, cycle 1).
- No continuous integration on GitHub. The orchestrator runs `make check` locally every
  cycle (D8); CI is revisited once PRs carry Linear links (C3).
- No Obsidian community plugins beyond what Ben already has; Dataview and the TF-IDF
  autolinker from the archive are retired (P3).
- No porting of archive game content, notes or ADRs.

## Actors

- **Ben** — approves the spec, performs the manual Linear and Obsidian steps, does the
  milestone click-through.
- **Orchestrator session** (Opus 5.5) — runs `make check`, drives the Godot MCP, posts
  Linear updates. For cycle 0 only, this session plays the role directly, because the
  agents and skills are cycle-0 outputs (C1).
- **Interrogator** (Fable 5.1 subagent) — writes spec/plan/tasks for every later cycle.
- **Implementer** (Sonnet 5.5, Opus 5.5 for engine-critical work) — edits code in a
  worktree, never runs the game, gets feedback only from the hook and `make check`.
- **Reviewer** (Sonnet 5.5, optional) — reads a diff, returns findings.
- **Godot 4.6.3 editor** — runs headless for the gate, with the editor open for MCP.
- **Linear** (team NSC) — holds the project, milestone and issues for each cycle.

## Requirements (EARS)

### Repo layout

- R1. The repo shall contain `docs/` (Obsidian vault), `godot/` (Godot project),
  `scripts/`, `.claude/`, `Makefile`, `.mcp.json`, `.env.example` and `.gitignore` at
  the root, and nothing else that is not a dotfile.
- R2. The `docs/` folder shall contain a `.gdignore` file so the Godot FileSystem dock
  never shows the vault.
- R3. The `.gitignore` shall exclude `.env`, `godot/.godot/`, `godot/reports/`,
  `godot/override.cfg`, `docs/.obsidian/workspace*.json`,
  `docs/.obsidian/plugins/*/data.json`, `.smart-env/` and OS cruft, and shall not
  exclude `docs/.obsidian/app.json`, `core-plugins.json`, `community-plugins.json` or
  plugin `main.js`/`manifest.json`.
- R4. When Obsidian opens the vault, the repo root shall not also be registered as a
  vault. (Ben's manual step: remove the stale root registration and the root
  `.obsidian/` folder.)

### Godot project

- R5. The project at `godot/project.godot` shall declare features `4.6` and `Mobile`,
  landscape orientation, and a main scene that exists.
- R6. When the main scene is run, it shall print exactly one line containing
  `Main ready` to stdout within two seconds and then keep running until quit.
- R7. The project shall vendor Card3D v3.0.2 (MIT) and gdUnit4 6.2.x (MIT) under
  `godot/addons/`, each recorded in `godot/addons/THIRD_PARTY_LICENSES.md` with its
  version, source URL and license. Vendoring means copied source, not submodules or
  Asset Library installs (C2).
- R8. The project shall vendor the godot-mcp-server editor plugin at 0.6.1 under
  `godot/addons/godot_mcp/` and enable it in `project.godot`, so the orchestrator's
  MCP connection works with the editor open.
- R9. Card3D's known `is_running` bug (D1) shall be patched on import and the patch
  noted in `THIRD_PARTY_LICENSES.md`.
- R10. The project shall contain exactly one gdUnit4 test suite under `godot/tests/`
  with one trivially passing test.
- R11. The vendored addons shall not emit errors on headless import.

### Build gate

- R12. `make check` shall run, in order: headless import, gdlint on every `.gd` file
  outside `godot/addons/`, a typed-strict parse check of every `.gd` outside
  `godot/addons/`, a two-second boot of the main scene, and the gdUnit4 suite with
  JUnit output under `godot/reports/`.
- R13. If any stage's output matches `SCRIPT ERROR`, `Parse Error`, `Failed to load
  script` or `ERROR:`, then `make check` shall exit non-zero and print the matching
  lines, regardless of Godot's own exit code.
- R14. If the boot stage output does not contain `Main ready`, then `make check` shall
  exit non-zero.
- R15. `make check` shall treat gdUnit4 exit codes 0 and 101 as pass and every other
  code as fail.
- R16. `make check` shall locate Godot from `GODOT_BIN` and default to the installed
  4.6.3 binary, and shall exit with code 2 and a one-line instruction if the binary is
  missing.
- R17. `make check` shall complete in under 60 seconds on the empty project.
- R18. `scripts/bootstrap.sh` shall install or verify gdtoolkit 4.5.x, check the Godot
  binary, check that `obsidian-cli` is on PATH (warn, not fail), and copy
  `.env.example` to `.env` if absent.
- R19. `make lint`, `make test` and `make boot` shall each run their single stage of
  R12 for faster iteration.

### Edit hook

- R20. When an Edit or Write tool call touches a `.gd` file under `godot/` outside
  `addons/`, the PostToolUse hook shall run gdlint and a single-file `--check-only`
  parse on that file and surface any finding as hook feedback.
- R21. The hook shall finish in under five seconds per file and shall never block a
  tool call on a tooling failure of its own (missing gdlint → warn and pass).
- R22. The hook configuration shall live in a committed `.claude/settings.json`.

### MCP and secrets

- R23. The committed `.mcp.json` shall define `godot` (npx godot-mcp-server),
  `linear` (https://mcp.linear.app/mcp) and `replicate` (official MCP with
  `${REPLICATE_API_TOKEN}`), and shall contain no literal secret.
- R24. `.env.example` shall list every variable `.mcp.json` references, each with a
  one-line comment and an empty value.
- R25. `scripts/claude-with-env.sh` shall source `.env` if present, warn if absent, and
  exec `claude` with all arguments passed through.

### Orchestrator pattern

- R26. `.claude/agents/` shall define `interrogator.md` (model fable, read-only tools
  plus Write under `docs/specs/`), `implementer.md` (model sonnet; Read, Edit, Write,
  Bash; no Godot MCP tools), `implementer-engine.md` (same as implementer on model
  opus) and `reviewer.md` (model sonnet, read-only).
- R27. `.claude/skills/` shall define `spec`, `exercise` and `cycle` (with `plan`,
  `run`, `test` sub-verbs), each as a SKILL.md that encodes the lifecycle in Phase 2
  and the acceptance ritual in P7.
- R28. The `spec` skill shall port the archive's vault-interrogator templates
  (spec/plan/tasks, EARS reference, interview batteries) with the stack section
  rewritten to the Phase 1 decisions and the constitution check pointed at this
  repo's `CLAUDE.md`.
- R29. A root `CLAUDE.md` shall state the constitution: the repo layout, the `make
  check` contract, the note schema, the "implementers never run the game" rule, the
  secrets rule, and the do-not-touch list (`docs/.obsidian/`, `godot/addons/*` except
  via a recorded patch).
- R30. Implementer agents shall have no access to Godot MCP tools or `make check`
  itself. (They receive the hook's feedback only; the orchestrator runs the gate.)

### Linear

- R31. Team NSC shall carry labels `area/engine`, `area/cards`, `area/ui`,
  `area/tooling`, `area/docs`, `type/feature`, `type/bug`, `type/chore` and
  `spec/<slug>` for each exercised spec.
- R32. Team NSC shall have an issue template "Spec task" that pre-fills a `## Spec`
  section with placeholders for the GitHub blob URL and `obsidian://` link.
- R33. A Linear project "Cycle 0 — scaffolding" shall exist with milestone
  `DC-00 scaffolding` and one issue per task in this spec's tasks.md, each linking
  back to the vault note. This is the first, hand-driven run of the exercise step; the
  `/exercise` skill is first used in cycle 1 (C4).
- R34. The four onboarding issues in team NSC shall be archived.

### Vault

- R35. `docs/Templates/note.md` shall carry the P5 schema: type, tags, status,
  related, created, updated, uid, linear, supersedes; with `type` limited to spec,
  plan, tasks, adr, system, planning, moc, reference.
- R36. `docs/specs/`, `docs/decisions/`, `docs/systems/` and `docs/planning/` shall
  exist, each with a MOC note.
- R37. `docs/decisions/` shall contain ADR 0001 recording the 21 planning decisions by
  reference to the three phase notes.
- R38. After cycle 0, `obsidian unresolved` and `obsidian orphans` run against the
  vault shall report zero items outside `docs/.obsidian/`.

## Clarifications (Ben, 2026-11-02)

| # | Question | Decision |
|---|---|---|
| C1 | Who runs cycle 0? | This session, directly. Subagents only for mechanical ports from the archive. Cycle 1 is the first run of the pattern |
| C2 | Addon vendoring | Copied source under `godot/addons/`, pinned by version and URL in the license file; the Card3D patch recorded there |
| C3 | CI on GitHub | None in cycle 0 |
| C4 | Dog-food Linear | Yes: cycle 0 is the first Linear project, milestone `DC-00 scaffolding`, one issue per task, created through the Linear MCP |

Also decided: the stale root `.obsidian/` folder was removed on 2026-11-02 (R4 satisfied
on this machine; the root vault entry in Obsidian's switcher is Ben's to forget).

## Scenarios

- **Given** a fresh clone with Godot 4.6.3 installed and gdtoolkit absent, **when**
  `scripts/bootstrap.sh && make check` runs, **then** gdtoolkit is installed, the
  project imports, the boot prints `Main ready`, one test passes, and the exit code
  is 0.
- **Given** a `.gd` file with a deliberate parse error under `godot/engine/`, **when**
  `make check` runs, **then** it exits non-zero and prints the `Parse Error` line,
  even though Godot itself exits 0.
- **Given** the same broken file, **when** an implementer agent saves it with Edit,
  **then** the PostToolUse hook returns the parse error as feedback within five
  seconds.
- **Given** the Godot editor open on `godot/`, **when** the orchestrator calls the
  Godot MCP `run_scene` then `take_screenshot`, **then** a screenshot of the
  placeholder main scene is returned and the runtime log contains `Main ready`.
- **Given** Claude Code launched through `scripts/claude-with-env.sh` with a filled
  `.env`, **when** the session lists MCP servers, **then** godot, linear and replicate
  are connected and no token appears in any committed file.
- **Given** the vault in Obsidian, **when** a spec note is created from
  `Templates/note.md`, **then** it has every P5 field and a fresh `uid`.

## Data touched

- New: everything under `godot/`, `scripts/`, `.claude/`, `docs/Templates/`,
  `docs/decisions/`, `docs/systems/`, `docs/specs/cycle-0-scaffolding/`, root
  `Makefile`, `CLAUDE.md`, `.mcp.json`, `.env.example`, `.gitignore`.
- Read only: `docs/planning/*`, the archive repo (templates, scripts, license file).
- Linear: labels, one template, one project, one milestone, issues, four archived
  onboarding issues.
- Never: `docs/.obsidian/` (Ben's), `.env`.

## Definition of done

- [ ] `scripts/bootstrap.sh && make check` exits 0 on a fresh clone (P8).
- [ ] The parse-error scenario fails `make check` and triggers the hook.
- [ ] Godot MCP returns a screenshot of the main scene with `Main ready` in the log (P7).
- [ ] Agents, skills, `CLAUDE.md`, `.mcp.json`, `.env.example` committed; no secret in git.
- [ ] Linear labels, template, project, milestone and issues exist; onboarding issues archived.
- [ ] `obsidian unresolved` and `obsidian orphans` are clean.
- [ ] Constitution Check passes (see plan).
- [ ] Spec, plan and tasks committed before implementation begins.
