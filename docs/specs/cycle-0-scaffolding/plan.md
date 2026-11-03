---
type: plan
tags: [plan, cycle-0, scaffolding]
status: approved
related: ["[[specs/cycle-0-scaffolding/spec]]", "[[specs/cycle-0-scaffolding/tasks]]", "[[planning/phase-1-tech-stack]]", "[[planning/phase-2-dev-tools]]"]
created: 2026-11-02
updated: 2026-11-02
uid: 4c863c6d-322c-47df-a8d6-df34e515d021
linear: https://linear.app/night-science-llc/project/cycle-0-scaffolding-6db3f9c856a0
supersedes:
---

# Plan: Cycle 0 — scaffolding

Implements [[specs/cycle-0-scaffolding/spec|spec]] (clarified 2026-11-02). This is the HOW. Nothing here changes a
requirement; where a requirement left a choice, the choice is recorded in a table so
tasks.md can point at it.

## Stack mapping

| Layer | Involved | Approach and tooling |
|---|---|---|
| Repo and scripts | yes | Bash scripts under `scripts/`, a thin `Makefile` that only dispatches to them. Scripts are POSIX-ish bash with `set -euo pipefail`, ported from the archive's `test_engine.sh` and `lint_engine.sh` |
| Godot project | yes | Godot 4.6.3 at `/Applications/Godot 4.6.app/Contents/MacOS/Godot` (overridable by `GODOT_BIN`). Mobile renderer. Placeholder main scene only |
| Addons | yes | Copied source (C2): Card3D 3.0.2 from github.com/tdecker91/Card3D, gdUnit4 6.2.3 from github.com/MikeSchulze/gdUnit4, godot-mcp editor plugin 0.6.1 from the `godot-mcp-server` npm package's `addons/` folder. Download each to a fresh scratchpad dir, verify the version file, copy only the `addons/<name>/` subtree |
| Claude Code | yes | `.claude/settings.json` (hook), `.claude/agents/*.md`, `.claude/skills/*/SKILL.md`, root `CLAUDE.md`. Ported from the archive's vault-interrogator with the stack section rewritten |
| MCP | yes | `.mcp.json` with godot (stdio, npx), linear (http), replicate (stdio, `npx replicate-mcp`, env `REPLICATE_API_TOKEN=${REPLICATE_API_TOKEN}`) |
| Linear | yes | Through the connected Linear MCP from this session: labels, template, project, milestone, issues, archive onboarding issues |
| Obsidian vault | yes | Plain files plus `obsidian-cli` for the link audit. `docs/.obsidian/` is Ben's; only its gitignore rules are mine |
| Art, backend, iOS export | no | Out of scope (spec non-goals) |

## Interfaces and contracts

### Makefile targets

| Target | Script | Exit | Contract |
|---|---|---|---|
| `make check` | `scripts/check.sh` | 0 pass, 1 fail, 2 missing tool | Runs import → lint → parse → boot → test in order, stops at the first failure, prints the offending lines |
| `make import` | `scripts/check.sh import` | same | `godot --headless --path godot --import`, output grepped |
| `make lint` | `scripts/check.sh lint` | same | `gdlint` over `godot/**/*.gd` minus `addons/`; `gdformat --check` is reported but not failing in cycle 0 |
| `make parse` | `scripts/check.sh parse` | same | Per-file `--check-only -s res://…` with a temporary `godot/override.cfg` promoting the six typed-GDScript warnings to errors (archive recipe); trap deletes the override |
| `make boot` | `scripts/check.sh boot` | same | Runs the main scene headless for 2 s via `timeout`/background kill, requires `Main ready` in stdout, fails on any error pattern |
| `make test` | `scripts/check.sh test` | same | `GdUnitCmdTool.gd --ignoreHeadlessMode --continue --add res://tests`, JUnit under `godot/reports/`, exit 0/101 pass |
| `make bootstrap` | `scripts/bootstrap.sh` | 0 or 2 | gdtoolkit 4.5.x via `uv tool install` (fallback `pipx`, then `pip --user`); checks Godot; warns if `obsidian-cli` missing; copies `.env.example` → `.env` if absent |

Error pattern (one grep, shared by every stage): `SCRIPT ERROR|Parse Error|Failed to load script|ERROR:`.
Godot writes those to stderr; every stage captures `2>&1`.

### Edit hook

`.claude/settings.json`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [{ "type": "command", "command": "scripts/hooks/gd-edit-gate.sh", "timeout": 10 }]
      }
    ]
  }
}
```

`scripts/hooks/gd-edit-gate.sh` reads the tool input JSON from stdin, extracts
`file_path`, exits 0 silently unless the path matches `godot/**/*.gd` outside `addons/`,
then runs `gdlint <file>` and `godot --headless --path godot --check-only -s res://<rel>`
and prints findings to stderr with exit 2 (feedback to the agent). Missing gdlint or
Godot: print one warning, exit 0 (R21).

### Agents

| File | model | tools | Prompt core |
|---|---|---|---|
| `.claude/agents/interrogator.md` | fable | Read, Grep, Glob, WebSearch, WebFetch, Write, Edit (prompt restricts writes to `docs/specs/`) | The `/spec` workflow: interview in plain-text rounds, EARS, stop at sign-off |
| `.claude/agents/implementer.md` | sonnet | Read, Grep, Glob, Edit, Write, Bash | Implement one Linear issue in the current worktree; never run Godot or `make check`; report files changed and anything unverified |
| `.claude/agents/implementer-engine.md` | opus | same as implementer | Same prompt plus the determinism rules from D4 |
| `.claude/agents/reviewer.md` | sonnet | Read, Grep, Glob, Bash (read-only git) | Findings only, ranked, no edits |

Agent tool allowlists cannot exclude MCP servers by name in frontmatter, so the
`.mcp.json` godot server is excluded from implementers by listing only the built-in
tools above (R30). The orchestrator session keeps everything.

### Skills

| Skill | Verbs | What it encodes |
|---|---|---|
| `.claude/skills/spec/` | `/spec <slug>` | Vault-interrogator port: `SKILL.md`, `templates/{spec,plan,tasks}-template.md`, `reference/{ears,interview-batteries}.md`, stack section rewritten to D1–D8, constitution = root `CLAUDE.md`, artifacts under `docs/specs/<slug>/` with P5 frontmatter and a fresh `uid` |
| `.claude/skills/exercise/` | `/exercise <slug>` | tasks.md → Linear project (name from spec title), `spec/<slug>` label, one issue per task with `## Spec` section (GitHub blob URL + `obsidian://adv-uri?vault=docs&uid=…`), `blockedBy` from the Depends column, write the project URL back into the note's `linear` field |
| `.claude/skills/cycle/` | `/cycle plan DC-NN`, `/cycle run DC-NN`, `/cycle test DC-NN` | plan: pick issues into milestone `DC-NN <theme>`; run: one worktree per independent issue via the Agent tool, Workflow tool at three or more; test: merge, `make check`, Godot MCP run + one screenshot per feature, Linear project status update and end-of-cycle Document (P7) |

### `.mcp.json`

```json
{
  "mcpServers": {
    "godot":     { "command": "npx", "args": ["-y", "godot-mcp-server@0.6.1"] },
    "linear":    { "type": "http", "url": "https://mcp.linear.app/mcp" },
    "replicate": { "command": "npx", "args": ["-y", "replicate-mcp"],
                   "env": { "REPLICATE_API_TOKEN": "${REPLICATE_API_TOKEN}" } }
  }
}
```

`.env.example` lists `REPLICATE_API_TOKEN=` and `GODOT_BIN=` (optional override), each
with a comment. Recraft is HTTP-only and keyed later (D3); its variable is added when
first used.

### Godot project settings

| Setting | Value | Why |
|---|---|---|
| `config/features` | `4.6`, `Mobile` | D2 |
| `rendering/renderer/rendering_method` | `mobile` | D2 |
| `rendering/renderer/rendering_method.mobile` | `gl_compatibility` | iOS Simulator path (D2) |
| `display/window/size` | 1280×720, stretch `canvas_items`/`expand`, orientation landscape | Archive values; 3D viewport is unaffected |
| `run/main_scene` | `res://main.tscn` | Node3D + Camera3D + a Label3D "Midnight Earth"; `main.gd` prints `Main ready` in `_ready()` |
| `editor_plugins/enabled` | `godot_mcp`, `gdUnit4` | Card3D has no editor plugin to enable |
| Autoloads | `MCPRuntime` from the godot_mcp addon only | Required for `run_scene`/`take_screenshot` |

### Linear structure (C4)

| Object | Value |
|---|---|
| Labels | `area/engine`, `area/cards`, `area/ui`, `area/tooling`, `area/docs`, `type/feature`, `type/bug`, `type/chore`, `spec/cycle-0-scaffolding` |
| Template | "Spec task": body `## Spec\n- Vault: obsidian://adv-uri?vault=docs&uid=<uid>\n- GitHub: <blob url>\n\n## Acceptance\n- [ ] ` |
| Project | "Cycle 0 — scaffolding", description = spec Intent + both links, `linear` field in spec.md set to its URL |
| Milestone | `DC-00 scaffolding` |
| Issues | one per row of tasks.md, labels `area/tooling` or `area/docs` + `type/chore` + `spec/cycle-0-scaffolding`, `blockedBy` from Depends |
| Cleanup | archive the four onboarding issues |

## Data model

Note frontmatter (P5), carried by `docs/Templates/note.md`:

```yaml
type: spec | plan | tasks | adr | system | planning | moc | reference
tags: []
status: draft | clarified | approved | closed      # spec/plan/tasks
        # proposed | accepted | superseded          # adr
        # seedling | growing | evergreen            # everything else
related: []
created: YYYY-MM-DD
updated: YYYY-MM-DD
uid: <uuid4>
linear: <issue or project URL, or empty>
supersedes: <adr note, or empty>
```

Vault folders after cycle 0: `planning/` (three phase notes + MOC), `specs/<slug>/`
(spec, plan, tasks), `decisions/` (ADR 0001 + MOC), `systems/` (MOC only), `Templates/`
(note.md). Links are plain `[[note]]` wikilinks; no managed AUTO-LINKS blocks (P3).

## Constitution Check

The root `CLAUDE.md` does not exist yet; it is task 10. Until then the constitution is
the 21 planning decisions plus the archive rules that survive (never touch
`.obsidian/`, never commit a secret, small reversible commits).

| Rule | Verdict | Note |
|---|---|---|
| D2 renderer and version | PASS | Mobile, 4.6, gl_compatibility fallback |
| D5 gate = `make check` + hook, grep-based | PASS | Exit codes never trusted |
| D6 MCP plugin 0.6.1 with editor open | PASS | Pinned in `.mcp.json` and vendored plugin |
| P2 layout: `docs/` vault, `godot/` project, `.gdignore` | PASS | |
| P3 plain files + CLI, no Obsidian MCP, autolinker retired | PASS | |
| P5 note schema | PASS | Template carries it; three existing planning notes get `uid` added |
| P6 secrets only in `.env` | PASS | `${VAR}` in `.mcp.json`; `.env` gitignored |
| P7 acceptance ritual | PASS | Verification task runs it end to end |
| P8 cycle 0 scope | PASS | No game code; placeholder scene only |
| Do not touch `docs/.obsidian/` | PASS | Only gitignore rules reference it |
| Small, reversible commits | PASS | One commit per task; direct on `master` for cycle 0, PRs from cycle 1 |

**Result:** PASS.

## Risks and mitigations

- Card3D 3.0.2 targets Godot 4.7; it may import with warnings on 4.6.3 → import is a
  gate stage, so a hard error surfaces in task 4; if it does, pin the last 4.6-compatible
  tag and record it in the license file.
- godot-mcp-server 0.6.1's editor plugin may differ from the archive's 0.5.0 in
  autoload name or settings → verify `get_godot_status` in task 15 before anything else.
- The typed-strict parse stage will flag Card3D's own scripts if the find is not scoped
  → every stage excludes `godot/addons/` explicitly.
- `uv` may not be on this machine → bootstrap falls back to `pipx`, then `pip --user`,
  and prints which it used.
- Linear team key is still `NIG` → issues are created anyway; the key rename does not
  change issue identity, only the prefix.
- Obsidian's Advanced URI plugin is not installed, so `obsidian://adv-uri` links do not
  resolve yet → links are still written; installing the plugin is Ben's one-click step
  and is listed in the README.

## Open questions

None. C1–C4 are closed in the spec.
