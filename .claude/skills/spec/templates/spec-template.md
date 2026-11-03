---
type: spec
tags: [spec, <slug>]
status: draft
related: ["[[specs/<slug>/plan]]", "[[specs/<slug>/tasks]]", "[[planning/phase-1-tech-stack]]"]
created: YYYY-MM-DD
updated: YYYY-MM-DD
uid: <uuid4 from `uuidgen | tr A-Z a-z`>
linear:
supersedes:
---

# Spec: <feature name>

**Slug:** `<slug>`  ·  **Change type:** engine | scene | shader | tooling | vault  ·  **Status:** draft | clarified | approved

## Intent
<One sentence: what should exist after this that does not now.>

## Non-goals
- <explicitly out of scope>

## Actors
- <who or what triggers or consumes this: Ben, a player, the bot, the engine, the orchestrator, an agent role>

## Requirements (EARS)
<Behaviour only, no implementation. One requirement per line, numbered R1, R2, using
the five EARS patterns. Group under ### headings if there are many. Mark unknowns as
[NEEDS CLARIFICATION: ...].>

- R1. The <system> shall <response>.
- R2. When <trigger>, the <system> shall <response>.
- R3. If <condition>, then the <system> shall <response>.

## Clarifications (Ben, YYYY-MM-DD)
<Each interview question and the chosen answer, e.g. "1a 2b". Delete if none.>

1. <question> -> <answer>

## Scenarios
- **Given** <state>, **when** <action>, **then** <observable outcome>.

## Data touched
- New: <files, scenes, engine modules, notes>
- Read only: <files>
- Never: <anything on the do-not-touch list that is nearby>

## Definition of done
- [ ] <observable acceptance check>
- [ ] `make check` is green
- [ ] One Godot MCP screenshot per visible feature
- [ ] Constitution Check passes (see plan)
- [ ] Spec, plan and tasks signed off by Ben and committed before implementation begins
