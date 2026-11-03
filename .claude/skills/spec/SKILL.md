---
name: spec
description: >
  Interrogate Ben before building anything, then produce a spec -> plan -> tasks set
  under docs/specs/<slug>/. Use when someone says "spec this", "plan this", "interview
  me", "/spec <slug>", "write requirements", or "start a cycle spec", or wants to add or
  change a rule, scene, shader, tool, skill or convention in Midnight Earth. Prevents
  agent drift by capturing intent, constraints (in EARS) and done-criteria up front
  instead of generating from a vague prompt.
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, WebSearch]
license: MIT
---

# /spec: spec-driven interview

A repeatable workflow that turns a fuzzy request into three reviewable notes (spec,
plan, tasks) before any code is written. It interviews first, then emits the artifacts,
constrained by the project constitution in the root `CLAUDE.md`. It is step one of the
cycle lifecycle: `/spec <slug>` then `/exercise <slug>` then `/cycle plan|run|test`.

## Why this exists

Agents default to generating immediately and filling gaps with guesses, which drifts
from intent and decays as the project grows. A written spec is the source of truth.
This skill enforces that discipline for the 3D card game: the Godot scenes, the pure
GDScript engine, the shaders, the tooling and the vault.

## The constitution comes first

The project's non-negotiable rules live in the root `CLAUDE.md`. **Read it before
interrogating** and treat every rule there as binding: fully typed GDScript, the
deterministic engine, the `make check` gate, the P5 note frontmatter, the do-not-touch
list, secrets only in `.env`, and small reversible commits on a branch of its own
named for the set (never directly on `master`). Also skim `docs/planning/phase-1-tech-stack.md` (decisions D1 to D8) so the
interview never re-opens a closed decision unless Ben asks. Every plan this skill
produces must pass the Constitution Check (step 5).

## Interview style (this matters)

- Ask in **rounds of 2 to 4 numbered plain-text questions**, each with lettered options.
- **The recommendation is always option (a).** Where options differ in cost or effort,
  say so on the option line (for example "(b) fresh scene per card, +1 task, S").
- Never use the AskUserQuestion widget. Ben rejected it; plain text only.
- Accept compact answers such as `1a 2a 3b`. Treat "go with your picks" as all (a).
- Record each answer in the spec's Clarifications section with the date.
- **Stop when answers stop changing the design.** Do not pad rounds with questions
  whose answers would not alter a requirement, a task or a cost.

Round shape:

```
Round 1 of the interview (3 questions)

1. Where does a committed card live between the two commits?
   a) Face-down in a per-player commit zone (recommended, no new engine state)
   b) Held in the engine only, no zone shown (+1 scene task, S)
   c) Other

2. ...
```

## Workflow (specify -> clarify -> plan -> tasks -> analyze)

### 0. Frame
Pick the slug (kebab-case, e.g. `committed-reveal`; cycle-wide sets use
`cycle-N-<theme>`) and the change type: `engine`, `scene`, `shader`, `tooling` or
`vault`. All types land in `docs/specs/<slug>/`; the plan records which areas the work
touches. Check `docs/specs/` for an existing set with that slug; if one exists, update
it rather than starting a second.

Then cut the set's branch before writing anything (`CLAUDE.md`, Git). The branch is
named for the slug and is the cycle branch: it carries the spec, the `/exercise`
write-back and the whole dev cycle, and merges into `master` only at `/cycle test`.
`git switch -c <slug> master` from a clean `master` (or `git switch <slug>` when updating
a set whose cycle has not merged yet). Every note this skill writes lands on that
branch.

### 1. Interrogate
Do NOT skip to drafting. Ask the batteries in `reference/interview-batteries.md`,
adapted to the change type, in rounds as described above. Cover at minimum: intent and
non-goals, actors, triggers, inputs and outputs, constraints, edge cases, unwanted
behaviour, data touched, dependencies, blast radius and definition of done.

### 2. Specify (the WHAT, not the HOW)
Fill `templates/spec-template.md`. Requirements are written in **EARS** (see
`reference/ears.md`) so they are unambiguous. No implementation detail here: a spec
describes behaviour and outcomes, not tech choices.

### 3. Clarify
Re-read the spec and surface every remaining ambiguity or `[NEEDS CLARIFICATION]`
marker as a concrete question. Resolve them with Ben in further rounds before
planning. Do not invent answers. Move the spec `status` from `draft` to `clarified`
when none remain.

### 4. Plan (the HOW)
Fill `templates/plan-template.md`. This is where the tech stack enters. Map the work
onto the relevant areas and name the tooling each will use. The stack is fixed by
`docs/planning/phase-1-tech-stack.md`:

- **Renderer:** Godot 4.6.3, Mobile renderer, Compatibility-clean shaders (D2): mediump-safe
  math, no `SCREEN_TEXTURE`, no features the Compatibility renderer lacks.
- **Cards:** 3D cards on the vendored Card3D addon (layouts, tweens, drag-drop) plus a
  foil shader; flip, draw and play animations, play-region zones, touch input and
  rules are built in-house (D1). Never edit `godot/addons/` except through a patch
  recorded in `THIRD_PARTY_LICENSES.md`.
- **Engine:** pure, fully typed GDScript under `godot/engine/` with a seeded RNG and a
  serializable, replayable action log (D4). No backend, no network-dependent scene.
  Scenes call the engine; the engine never touches nodes.
- **Tests and gate:** gdUnit4 suites under `godot/tests/`, one per engine module, run
  through the `make check` gate (D5). Implementers never run Godot or `make check`;
  the orchestrator does.
- **Verification:** the orchestrator verifies through godot-mcp-server with the editor
  open (D6): `run_scene`, `get_runtime_log`, `take_screenshot`. Keyboard and popup
  input are driven programmatically.
- **UI:** plain Godot Theme resources (D7). No addon lift.
- **Cadence:** desktop (macOS) every cycle; iOS only at milestones (D8).
- **Art:** through the Replicate MCP and the Recraft HTTP API, never Claude spend (D3).
  Tokens live only in `.env`.

Record interfaces and contracts, the data model, and the Constitution Check result.

### 5. Constitution Check
Verify the plan against `CLAUDE.md`. List each relevant rule with PASS or FAIL. If
anything fails, revise the plan; do not proceed.

### 6. Tasks
Fill `templates/tasks-template.md`: a numbered, dependency-ordered, independently
reviewable task list derived from the plan. Each task names its area, its acceptance
check and who does it: `implementer`, `implementer-engine` (anything under
`godot/engine/`), `reviewer` or `orchestrator`. The last task is always verification.

### 7. Handoff
1. Write the three notes to `docs/specs/<slug>/spec.md`, `plan.md`, `tasks.md`, each
   with the P5 frontmatter (below). Generate a fresh `uid` per file with
   `uuidgen | tr A-Z a-z`. Set `created` and `updated` to today.
2. Present a short summary and ask for Ben's sign-off. On sign-off set `status:
   approved` on all three.
3. **The skill stops at Ben's sign-off.** Commit only when Ben says to, on the
   `<slug>` branch cut in step 0, never on `master`: `git add docs/specs/<slug>`
   (plus the specs MOC row if you added one), `git commit -m "spec: <slug>"` with the
   Co-Authored-By line the session provides. Stay on the branch: `/exercise` runs on it
   next. Do not merge it; the cycle branch merges into `master` only at `/cycle test`
   (`docs/decisions/0002-one-branch-per-cycle.md`). Never push.
4. Tell Ben the next verb is `/exercise <slug>`, which turns the tasks into Linear
   issues. Implementation is a separate step.
5. Final link audit: if `obsidian-cli` is on PATH (`command -v obsidian-cli`), run
   `obsidian-cli vault=docs unresolved` (the `vault=` flag goes before the command)
   and fix any broken link in the three new notes. If it is not on PATH, skip
   silently.

## Frontmatter (every file)

```yaml
type: spec            # spec | plan | tasks
tags: [spec, <slug>]
status: draft         # draft -> clarified -> approved
related: ["[[specs/<slug>/plan]]", "[[planning/phase-1-tech-stack]]"]
created: YYYY-MM-DD
updated: YYYY-MM-DD
uid: <uuid4, lowercase, from uuidgen>
linear:               # empty until /exercise fills it
supersedes:
```

Links use `[[path/from/vault/root]]`, never relative paths.

## Rules

- Never write the spec before the interview; never write the plan before clarify is
  resolved.
- Requirements and constraints are phrased in EARS.
- Every plan carries a Constitution Check.
- This skill writes only under `docs/specs/<slug>/` and never writes code.
- Never touch the do-not-touch list in `CLAUDE.md`.
- Keep `updated` current when editing an existing set.

## Files

- `templates/spec-template.md`: the WHAT (EARS requirements, scenarios, done).
- `templates/plan-template.md`: the HOW (stack mapping, contracts, constitution check).
- `templates/tasks-template.md`: ordered, checkable tasks with verification and commit plan.
- `reference/interview-batteries.md`: question sets per change type.
- `reference/ears.md`: the five EARS patterns with card-game examples.
