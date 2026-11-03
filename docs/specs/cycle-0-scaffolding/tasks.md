---
type: tasks
tags: [tasks, cycle-0, scaffolding]
status: approved
related: ["[[specs/cycle-0-scaffolding/spec]]", "[[specs/cycle-0-scaffolding/plan]]"]
created: 2026-11-02
updated: 2026-11-02
uid: 31332efb-308d-4a9e-94e4-03961f6f3ad7
linear: https://linear.app/night-science-llc/project/cycle-0-scaffolding-6db3f9c856a0
supersedes:
---

# Tasks: Cycle 0 — scaffolding

Derived from [[specs/cycle-0-scaffolding/plan|plan]]. Numbered, dependency-ordered, independently reviewable. "Who"
follows C1: the orchestrator session does the work itself; a Sonnet subagent is used
only for the mechanical ports marked so. Every task is one commit on `master`.

| # | Task | Area | Depends on | Acceptance check | Who |
|---|---|---|---|---|---|
| 1 | Repo skeleton: `godot/`, `scripts/`, `.claude/`, `docs/.gdignore`, `.gitignore` per R3, README section on bootstrap | tooling | – | `tree -a -L 2` matches R1; `git check-ignore` confirms `.env`, `godot/.godot/`, `docs/.obsidian/workspace.json` ignored and `docs/.obsidian/app.json` not | session |
| 2 | Godot project: `project.godot` per plan settings table, `main.tscn` (Node3D, Camera3D, Label3D), `main.gd` printing `Main ready`, `icon.svg` | tooling | 1 | Headless `--import` clean; headless run of main scene prints `Main ready` within 2 s | session |
| 3 | Vendor gdUnit4 6.2.3 under `godot/addons/gdUnit4/`, enable plugin, add `godot/tests/test_smoke.gd` with one passing assertion | tooling | 2 | `GdUnitCmdTool` run exits 0 or 101 with one passed test in the JUnit report | subagent (Sonnet) |
| 4 | Vendor Card3D 3.0.2 under `godot/addons/card3d/`, apply the `is_running` patch, create `godot/addons/THIRD_PARTY_LICENSES.md` with all three entries | tooling | 2 | Headless `--import` emits no error pattern; license file lists version, URL, license, patch | subagent (Sonnet) |
| 5 | Vendor godot-mcp editor plugin 0.6.1 under `godot/addons/godot_mcp/`, enable it, register `MCPRuntime` autoload | tooling | 2 | `--import` clean; with the editor open, `get_godot_status` from the MCP reports connected | session |
| 6 | `scripts/bootstrap.sh` per plan | tooling | 1 | On this machine: installs gdtoolkit 4.5.x, `gdlint --version` works afterwards, warns about `obsidian-cli`, creates `.env` from `.env.example` | session |
| 7 | `scripts/check.sh` with import/lint/parse/boot/test stages and the shared error grep; `Makefile` with `check`, `import`, `lint`, `parse`, `boot`, `test`, `bootstrap` | tooling | 3, 4, 5, 6 | Spec scenario 1 (green on the empty project, under 60 s) and scenario 2 (planted parse error → non-zero exit with the line printed; file removed afterwards) | session |
| 8 | `scripts/hooks/gd-edit-gate.sh` and `.claude/settings.json` PostToolUse entry | tooling | 6 | Spec scenario 3: editing a `.gd` with a parse error returns the error as hook feedback in under 5 s; editing a `.md` is silent; with gdlint renamed away the hook warns and passes | session |
| 9 | `.mcp.json`, `.env.example`, `scripts/claude-with-env.sh` | tooling | 1 | `git grep -i token` finds only `${REPLICATE_API_TOKEN}`; `claude mcp list` from the wrapper shows godot, linear, replicate | session |
| 10 | Root `CLAUDE.md` constitution per R29 | docs | 1 | Covers layout, `make check` contract, note schema, implementers-never-run rule, secrets rule, do-not-touch list; under 120 lines | session |
| 11 | `.claude/agents/`: interrogator, implementer, implementer-engine, reviewer per plan table | tooling | 10 | Each file has valid frontmatter (`name`, `description`, `model`, `tools`); `/agents` lists all four; implementer has no MCP tool in its list | session |
| 12 | `.claude/skills/spec/`: port vault-interrogator SKILL.md, three templates, EARS and interview references; rewrite the stack section to D1–D8; point the constitution at `CLAUDE.md`; templates carry P5 frontmatter | tooling | 10 | No mention of Django, AWS, Penpot, Cursor or `AGENTS.md` remains; `/spec` appears in the skill list | subagent (Sonnet) |
| 13 | `.claude/skills/exercise/` and `.claude/skills/cycle/` SKILL.md per plan table | tooling | 10, 11 | Each describes inputs, Linear MCP calls, outputs and the P7 ritual; `/exercise` and `/cycle` appear in the skill list | session |
| 14 | Vault: `docs/Templates/note.md` with the P5 schema; MOC notes for planning, specs, decisions, systems; ADR 0001 (planning decisions by reference); add `uid` to the three phase notes; set `status: approved` on spec/plan/tasks | docs | 1 | `obsidian unresolved` and `obsidian orphans` report nothing outside `docs/.obsidian/`; every note has every P5 field | session |
| 15 | Linear: create labels, "Spec task" template, project "Cycle 0 — scaffolding", milestone `DC-00 scaffolding`, one issue per task 1–16 with `## Spec` links and `blockedBy`; archive the four onboarding issues; write the project URL into the three notes' `linear` field | docs | 14 | `list_issues` for the project returns 16 issues with correct labels and blockers; onboarding issues archived; notes link to the project | session |
| 16 | Verification (below) | tooling | 1–15 | All boxes checked | session |

## Verification task (16)

- [x] Fresh clone (branch `cycle-0-scaffolding`): `scripts/bootstrap.sh && make check` exit 0 in 7 s (2026-11-02). `make` needed `DEVELOPER_DIR=/Library/Developer/CommandLineTools` because the Xcode license is unaccepted; documented in README.
- [x] Planted `godot/engine/_broken.gd`: gate exits 1 at the lint stage with the error line; a typed-strict violation that gdlint passes is caught by the parse stage.
- [x] Godot editor open: `get_godot_status` connected (server 0.6.1 = plugin 0.6.1), `run_scene` with runtime connected in 4.5 s, console log contains `Main ready`, `get_errors` 0, screenshot `godot/reports/DC-00/main-ready.png` (1063×598).
- [x] Secret grep returns nothing.
- [x] `obsidian-cli vault=docs unresolved` and `orphans` empty (14 notes).
- [x] Linear status update "DC-00 done" posted with the screenshot; DC-00 issues moved to Done. The "Spec task" template remains Ben's manual step (follow-up issue).

## Linear (exercised 2026-11-02)

Project [Cycle 0 — scaffolding](https://linear.app/night-science-llc/project/cycle-0-scaffolding-6db3f9c856a0),
milestone `DC-00 scaffolding`. Task n is issue `NSC-(n+4)`: T01 = NSC-5 … T16 = NSC-20.
The "Spec task" template could not be
created through the MCP and is Ben's step.

## Commit plan

One commit per task on branch `cycle-0-scaffolding`, named for the set (Ben, 2026-11-02).
Messages: `cycle-0: <task title>`. When T16 passes, the branch merges into `master` with a
merge commit (`--no-ff`) so the set stays visible in history. Later cycles follow the same
pattern with the branch named for the milestone (`dc-01-<theme>`). The spec set itself was
committed on `master` first as `spec: cycle-0-scaffolding`.

## Manual steps for Ben (not tasks)

- Rename Linear team key `NIG` → `NSC` (Team settings → General).
- Install Linear's GitHub integration on the private repo.
- Put `obsidian-cli` on PATH, e.g. a symlink in `/usr/local/bin`.
- Install the Advanced URI community plugin in Obsidian so `obsidian://adv-uri` links resolve.
- Optional: forget the stale root vault entry in Obsidian's vault switcher.
