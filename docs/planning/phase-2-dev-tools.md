---
type: planning
tags: [planning, phase-2]
status: closed
related: ["[[planning/planning-moc]]"]
created: 2026-11-02
updated: 2026-11-02
uid: f15a4be6-95c4-4bbd-a816-517412cb4bde
supersedes:
phase: 2-dev-tools
---

# Phase 2 — Dev tools: Linear, Obsidian, orchestrator

Research gathered 2026-11-02. Local facts were checked on this machine; web facts come
from three research agents the same day. Decisions are recorded at the bottom as Ben
makes them.

## Target flow (from the brief)

1. Human + Claude write specs as linked Obsidian notes.
2. A complete spec is exercised into actionable Linear issues that link back to the notes.
3. Human + Claude group issues into discrete dev cycles.
4. Each cycle is fed to the orchestrator: Opus 5.5 orchestrates, a Fable subagent
   interrogates, Opus/Sonnet 5.5 implement without testing, the orchestrator tests at
   the end. Every cycle ends buildable and testable.

## What is already on this machine

| Item | State |
|---|---|
| Linear workspace | "Night Science LLC", one team `NIG`, four untouched onboarding issues, default labels (Bug/Improvement/Feature) and statuses, cycles not enabled, no projects, documents, templates or agent skills. Ben is admin. The official Linear MCP is connected to Claude Code with full access |
| Obsidian | 1.14.5 installed, CLI 1.15.0 enabled by Ben on 2026-11-02 (binary at `/Applications/Obsidian.app/Contents/MacOS/obsidian-cli`, not yet on PATH). Obsidian still registers a vault at `/Users/Crofts/Dev/nightscience/midnightearth`, left over from the archived repo that lived at this path |
| score | Ben's separate app at `/Users/Crofts/Dev/Orchestrator` (named Orchestrator until 2026-09-19). **Not part of this plan**: the brief's "Orchestrator" is the spec-driven agent/subagent pattern below, not this tool (Ben, 2026-11-02). Facts kept for reference: JIRA-only, v0.1.0 |
| Archive conventions | Vault at repo root; `Templates/note.md` schema (type, tags, status, related, created, updated); Dataview MOCs; plugins dataview, quickadd, templater, smart-connections; TF-IDF autolinker script; `vault-interrogator` skill (interrogate → spec → clarify → plan → tasks, EARS requirements, constitution check); `.gitignore` already handles `.obsidian/workspace*.json`, plugin `data.json`, `.smart-env/` |

## Linear

### Plan limits (https://linear.app/pricing)

| Feature | Free | Basic ($10/user/mo annual) | Notes |
|---|---|---|---|
| Open issues | 250 | Unlimited | Archive done issues to stay under |
| Teams | 2 | 5 | One team suffices |
| Cycles, Projects, Milestones, Documents | Yes | Yes | |
| API / MCP / webhooks | Yes | Yes | Full read-write |
| GitHub integration on a private repo | Yes | Yes | Branch-name auto-link, `Fixes ME-12` auto-close |
| Diffs (PR review inside Linear) | Yes | Yes + Guided Reviews | |
| Linear Agent + agent skills | Yes | Yes | Coding sessions need prepaid AI credits |
| Releases / pipelines, Automations, Insights | No | No | Business only |

**Free covers this flow.** The only wall is 250 open issues.

### MCP tool groups (verified against the live tool list)

| Group | R/W | Use in our flow |
|---|---|---|
| Issues, labels, statuses | RW | Spec → issues; project, milestone, labels, `blockedBy`; `patch` descriptions |
| Comments, attachments, links | RW | Progress notes; attach spec URLs |
| Projects, milestones, status updates | RW | Project per spec; milestone per dev cycle; end-of-cycle status update |
| Cycles | R (assign via `save_issue`) | Only if calendar cycles are wanted; cycles cannot be created via MCP |
| Documents | RW | Optional end-of-cycle test report |
| Diffs (get/list/update, review, merge, threads) | RW | Link PR to issues, request review, merge from the session |
| Releases | RW | Business only; skip |
| Agent skills | R | Linear's own agent's saved instructions, not Claude Code skills |

Rate limits are far above a solo orchestrator's needs (5,000 req/h OAuth).

### Agents

- There is no Anthropic-built Claude agent in Linear's directory. "Assign to Claude" from
  Linear's UI needs a third-party bridge (Cyrus, open source, runs Claude Code locally).
- Linear's own coding sessions run Claude Code or Codex in Linear's cloud sandbox for
  prepaid AI credits. They cannot reach the Godot editor on this Mac, so they do not fit
  the "orchestrator tests with Godot MCP" step.
- Conclusion: the orchestrator **pulls** issues through the MCP; nothing is pushed from
  Linear.

### Cycles versus milestones

Linear Cycles are calendar-driven (1–8 weeks, auto-rollover of unfinished issues). A
"dev cycle" in this flow is a scope-driven batch that ends when it builds and tests.
Better fits: a **project milestone** per dev cycle (`DC-01 <theme>`), or a `cycle/DC-01`
label when a cycle spans several specs. Cycles can be enabled later for cadence.

### Linking to Obsidian

- Issue descriptions are Markdown. Put both links in a `## Spec` section: the GitHub
  blob URL (always clickable) and an `obsidian://` deep link. Linear's handling of custom
  schemes is undocumented; test one.
- The Advanced URI plugin (MIT, active) opens notes by a frontmatter `uid`, so links
  survive renames. Add `uid` and `linear` to the note schema.
- Community Obsidian↔Linear plugins are all stale; the Linear MCP in the Claude session
  is the reliable bridge.

### Alternatives

GitHub Projects (free, in-repo, iterations, official MCP toolset) has a weaker triage UI
and no documents or agent layer. Plane (open source, official MCP) is rougher. Linear has
the best UI and richest MCP, and Free is enough.

## Obsidian

### Official CLI (Obsidian 1.12+, enabled here as 1.15.0)

Drives the running desktop app (launches it if closed). Vault chosen by `vault=` or by
cwd. Commands relevant to agents: `read/create/append/prepend/move/rename`,
`search`, `search:context`, `property:set/read/remove`, `backlinks`, `links`,
`unresolved`, `orphans`, `deadends`, `tags`, `tasks`, `templates`, `base:query` (JSON
out), `command id=`, `eval` (run JS inside the app, e.g. the Dataview API), `dev:*`
(console, errors, screenshot). Docs: https://obsidian.md/help/cli

### MCP servers

| Server | Needs Obsidian running | Maintained | Adds over plain files |
|---|---|---|---|
| Local REST API plugin, built-in `/mcp/` (coddingtonbear, MIT, v5.5.2 2026-10) | Yes | Yes | CRUD, PATCH into heading/frontmatter, Obsidian search, run commands. Native MCP since v4.0 |
| cyanheads/obsidian-mcp-server (Apache-2.0, 2026-10-31) | Yes (REST plugin) | Yes | Frontmatter/tag tools, scoped permissions |
| StevenStavrakis/obsidian-mcp, bitbonsai/mcpvault (MIT) | No | Yes | Offline move with backlink rewrite |
| MarkusPfundstein/mcp-obsidian | Yes | Slowing | Superseded by the plugin's own `/mcp/` |
| smart-connections-mcp (one-person) | No | 2026-08 | Semantic search over `.smart-env/`; tested on SC 3.x, SC is now v4 |
| Official Obsidian MCP | — | None exists | |

**Honest finding:** for a vault that is a git repo, an MCP's real differentiators are live
Dataview/Bases evaluation, Obsidian-correct link resolution and rename, and semantic
search. The first two are now covered by the official CLI with no server.

### Conventions worth copying

- kepano/obsidian-skills (Obsidian's CEO, MIT, 50k stars): `obsidian-markdown`,
  `obsidian-bases`, `obsidian-cli` skills. Install as a Claude Code plugin marketplace.
- Bases (`.base`, core since 1.9) replace most Dataview MOC tables and are queryable from
  the CLI, unlike Dataview.
- Spec Kit's constitution → spec → plan → tasks maps onto note `type` values; the
  archive's `vault-interrogator` already implements this and needs only its stack section
  rewritten for Phase 1 decisions.

### Vault inside the Godot repo — pitfalls

- Obsidian ignores dot-folders but indexes everything else: with the vault at repo root,
  addon READMEs, CHANGELOGs and LICENSE files become notes and unlinked-mention noise.
  `Excluded files` only hides from search and graph; nothing is a true ignore.
- Godot ignores `.md` but shows the folder in its FileSystem dock; a `.gdignore` file in
  the vault folder hides it.
- Keep the archive's `.gitignore` entries; commit `app.json`, `core-plugins.json`,
  `community-plugins.json`, and plugin `main.js`/`manifest.json` for zero-setup clones.
- Never under iCloud Drive; Obsidian Sync clashes with an in-vault `.git`.

## Orchestrator: the spec-driven agent/subagent pattern

"Orchestrator" in the brief is a pattern, not a tool (Ben, 2026-11-02): one Claude Code
session on Opus 5.5 owns a dev cycle, a Fable subagent interrogates and writes the spec,
Opus/Sonnet 5.5 subagents implement without testing, and the orchestrator session tests
at the end. Everything below is how to build that pattern on Claude Code's own
primitives.

### Primitives available

| Primitive | What it gives the pattern |
|---|---|
| `.claude/agents/<name>.md` custom subagents | A named role with its own `model` (opus, sonnet, fable), tool allowlist and system prompt; invoked by the orchestrator through the Agent tool |
| Skills (`.claude/skills/<name>/SKILL.md`) | The cycle verbs as slash commands: spec-gathering, cycle planning, dispatch, test |
| Workflow tool | Deterministic fan-out script over subagents (parallel, pipeline, phases) for independent tasks in a cycle; explicit opt-in per run |
| Worktree isolation on the Agent tool | Each implementer works on its own branch; the orchestrator merges or discards |
| Hooks (PostToolUse) | The gdlint plus parse gate from Phase 1 D5, so implementers get compile feedback without testing |
| godot-mcp-server + `make check` | The orchestrator's end-of-cycle test (Phase 1 D5/D6) |
| Linear MCP | Issues pulled per cycle; status, comments and the end-of-cycle report pushed back |
| Memory (`~/.claude/projects/.../memory/`) | Cross-session facts about Ben's preferences and project decisions |

### Role sketch

| Role | Model | Tools | Writes |
|---|---|---|---|
| Orchestrator (the session) | Opus 5.5 | everything | Linear status, merges, test report |
| Interrogator | Fable 5.1 | Read, Grep, WebSearch, Linear read | `docs/specs/<slug>/spec.md`, `plan.md`, `tasks.md` |
| Implementer | Sonnet 5.5 (Opus 5.5 for engine-critical tasks) | Read, Edit, Write, Bash (no Godot run tools) | Code in its worktree, a short report |
| Reviewer (optional) | Sonnet 5.5 | Read, Grep | Findings only |

Implementers never run the game; the PostToolUse hook and `make check` are their only
feedback. The orchestrator runs `make check`, then the Godot MCP loop, and files
follow-up issues in Linear for anything that fails.

### Cycle lifecycle

1. **Spec** (`/spec <slug>`): Interrogator interviews Ben in plain-text rounds, writes
   spec/plan/tasks notes in the vault, links them, and stops at Ben's sign-off.
2. **Exercise** (`/exercise <slug>`): the session turns tasks.md into Linear issues under a
   project for the spec, each with a `## Spec` link section and `blockedBy` relations.
3. **Cycle** (`/cycle plan DC-NN`): Ben and the session pick issues into a milestone; the
   acceptance criterion is "buildable and testable", nothing more.
4. **Run** (`/cycle run DC-NN`): dispatch implementers, one worktree per independent
   issue, Workflow tool when three or more are independent.
5. **Test** (`/cycle test DC-NN`): merge, `make check`, Godot MCP verification, Linear
   status update and end-of-cycle Document.

### Options

| Option | Effort | What makes it expensive | What you lose |
|---|---|---|---|
| Claude Code native: agents + skills + Workflow + worktrees, as sketched | S–M | Writing and tuning four role prompts and five skills; merge handling across worktrees | Nothing a GUI would show that Linear does not |
| Same, plus score as the mechanical layer (worktrees, gates, squash, PRs) | M | score is JIRA-only; adapter is 4–16 h (costing kept in the archive of this doc's history) | Parked unless the native merge flow proves painful |
| Linear coding sessions or Cyrus | S | Cloud sandbox cannot reach the Godot editor; Cyrus is another daemon | The orchestrator-tests-at-end step |

## Proposed Linear structure

One team (`ME`, "Midnight Earth"; Free allows two), cycles disabled, one **project per
spec** whose description carries the spec summary and both links, issues inside it with
`blockedBy` relations and a "spec task" issue template that pre-fills a `## Spec` section,
a **milestone per dev cycle** (`DC-01 <theme>`), labels `area/*`, `type/*`, `spec/*`,
`cycle/*`. GitHub integration on the private repo with "Copy git branch name" and
`Fixes ME-12` in PR bodies. The orchestrator posts a project status update and an
end-of-cycle Document with the test report.

## Proposed repo layout

```
midnightearth/
  docs/            Obsidian vault (.obsidian/ committed minus per-machine state; .gdignore)
    specs/<slug>/  spec.md, plan.md, tasks.md
    decisions/     ADRs
    planning/      these phase docs
    systems/       game-design notes
  godot/           Godot 4.6.3 project (project.godot, addons/, engine/, tests/)
  scripts/         make check, gates, generators
  .mcp.json        godot, linear, replicate entries with ${VAR} secrets
  .env.example
```

## Decisions

### Round 1 (Ben, 2026-11-02; 4 amended explicitly, 1a/2a/3a accepted by default)

| # | Decision | Consequence |
|---|---|---|
| P1 | **The pattern is built on Claude Code primitives.** `.claude/agents/` defines interrogator (Fable 5.1), implementer (Sonnet 5.5; Opus 5.5 for engine-critical tasks) and an optional reviewer; skills `/spec`, `/exercise`, `/cycle plan`, `/cycle run`, `/cycle test`; one worktree per independent issue; the Workflow tool when three or more issues are independent; the orchestrator session runs on Opus 5.5. | Role prompts and skills are cycle-0 deliverables; score is not used |
| P2 | **`docs/` is the Obsidian vault; the Godot project lives in `godot/`.** A `.gdignore` in `docs/` hides it from Godot. Obsidian's stale registration of the repo root is re-pointed to `docs/`. | `.obsidian/` committed minus per-machine state; planning docs stay where they are |
| P3 | **Claude works the vault as plain files plus the official CLI**, with the kepano/obsidian-skills plugin for Obsidian-flavored Markdown. The archive's vault-interrogator is ported with its stack section rewritten; the TF-IDF autolinker is retired; no Obsidian MCP server. | CLI must be on PATH for scripts; `obsidian unresolved|backlinks|orphans` run after each writing session |
| P4 | **One Linear team, key renamed `NIG` → `NSC`** (Ben's amendment; no new `ME` team). Free plan, cycles disabled, one project per spec, a milestone per dev cycle (`DC-01 <theme>`), labels `area/*`, `type/*`, `spec/*`, GitHub integration on the private repo with Linear branch names and `Fixes cycle-0 T08` in PR bodies. | Issue keys become `NSC-n`; the key rename and the GitHub app install are Ben's manual steps in Linear's UI (the MCP has no team-edit tool); the four onboarding issues get archived |

### Round 2 (Ben, 2026-11-02, all recommendations accepted)

| # | Decision | Consequence |
|---|---|---|
| P5 | **Note schema:** the archive's frontmatter (type, tags, status, related, created, updated) plus `uid` (Advanced URI), `linear` (issue or project URL) and `supersedes` (ADRs). `type` restarts small: spec, plan, tasks, adr, system, planning, moc, reference. | `docs/Templates/note.md` carries the schema; content types return only if content leaves Godot JSON |
| P6 | **MCP and secrets:** committed `.mcp.json` with godot, linear and replicate entries and `${VAR}` placeholders; committed `.env.example`; gitignored `.env`; `scripts/claude-with-env.sh` wrapper. | Replicate token never appears in a committed file or in chat |
| P7 | **Acceptance ritual per cycle:** `make check` green, then the orchestrator runs the main scene through the Godot MCP, captures one screenshot per feature, and posts a short test note as the Linear project status update. Ben's manual click-through happens only at milestones. | The `/cycle test` skill encodes exactly this; a cycle without a screenshot is not done |
| P8 | **Cycle 0 is scaffolding only:** repo layout, Godot 4.6.3 project on Mobile with Card3D and gdUnit4 vendored, `make check` and the PostToolUse hook, `.mcp.json` and `.env.example`, the agents and skills from P1, Linear labels and the spec-task template, the vault with templates. Done when `make check` passes on an empty project with one trivial gdUnit4 test. | No game code in cycle 0; cycle 1 starts on the match engine |

Phase 2 is closed. Manual steps for Ben: rename the Linear team key to `NSC`, install
Linear's GitHub integration on the private repo, re-point Obsidian at `docs/` once the
vault exists, and put `obsidian-cli` on PATH.
