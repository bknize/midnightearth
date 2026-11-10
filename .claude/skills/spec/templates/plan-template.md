---
type: plan
tags: [plan, <slug>]
status: draft
related: ["[[specs/<slug>/spec]]", "[[specs/<slug>/tasks]]", "[[planning/phase-1-tech-stack]]"]
created: YYYY-MM-DD
updated: YYYY-MM-DD
uid: <uuid4 from `uuidgen | tr A-Z a-z`>
supersedes:
---

# Plan: <feature name>

Implements [[specs/<slug>/spec|spec]]. This is the HOW. Do not start until the spec is
**clarified** (no open `[NEEDS CLARIFICATION]`). Nothing here changes a requirement;
where a requirement left a choice, record the choice in a table so tasks.md can point
at it.

## Stack mapping
Which areas this touches and the tooling for each. Delete rows that do not apply, or
mark them "no".

| Area | Involved | Approach and tooling |
|---|---|---|
| Godot scenes/UI | y/n | scenes and nodes affected; plain Godot Theme (D7); Card3D layouts and tweens for cards (D1); verified through the Godot MCP |
| Engine (godot/engine + tests) | y/n | typed GDScript, seeded RNG, replayable action log (D4); gdUnit4 suite per module under `godot/tests/` |
| Shaders/cards | y/n | foil and card shaders, Compatibility-clean (D2): mediump-safe, no `SCREEN_TEXTURE` |
| Tooling/scripts | y/n | `scripts/`, `Makefile`, hooks, `.claude/` agents and skills; Bash with `set -uo pipefail` |
| Vault/docs | y/n | notes under `docs/` with P5 frontmatter; link audit with `obsidian-cli` |

## Interfaces and contracts
<Engine function signatures and action shapes, signals between scenes and engine,
scene node paths, shader uniforms, script CLI contracts, or note frontmatter.>

## Data model
<Engine state fields and their types, action-log entries, resources, or note types and
their links. State what is serialized and what is derived.>

## Constitution Check
Verify against the root `CLAUDE.md`. Every relevant rule, with a verdict.

| Rule | Verdict | Note |
|---|---|---|
| All project GDScript is fully typed (`parse` promotes typed-GDScript warnings to errors) | PASS/FAIL | |
| Engine is deterministic: seeded RNG, no wall-clock, no node access, serializable action log (D4) | PASS/FAIL | |
| `make check` gate contract: import, lint, parse, boot, test all green; Godot exit codes never trusted | PASS/FAIL | |
| Implementers never run Godot or `make check`; only the orchestrator verifies | PASS/FAIL | |
| Notes carry P5 frontmatter (`type`, `tags`, `status`, `related`, `created`, `updated`, `uid`, `supersedes`) and `[[path/from/vault/root]]` links | PASS/FAIL | |
| No edits under the do-not-touch list (`docs/.obsidian/`, `godot/addons/*` outside a recorded patch, `.env`, `godot/.godot/`, `godot/reports/`, the archive) | PASS/FAIL | |
| Secrets only in `.env`; `.mcp.json` uses `${VAR}` placeholders; no token in chat, notes or commits | PASS/FAIL | |
| Each changeset on its own branch (a cycle: one `cycle-N-<theme>` branch from `/spec` to `/cycle test`), one commit per task, nothing committed directly on `master`, merged with `--no-ff` | PASS/FAIL | |

**Result:** PASS / needs revision.

## Risks and mitigations
- <risk> -> <mitigation>

## Open questions
- <none, or list>
