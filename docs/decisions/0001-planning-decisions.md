---
type: adr
tags: [adr, planning]
status: accepted
related: ["[[decisions/decisions-moc]]", "[[planning/phase-1-tech-stack]]", "[[planning/phase-2-dev-tools]]", "[[planning/phase-3-game-loop]]"]
created: 2026-11-02
updated: 2026-11-02
uid: 285595b4-b038-4bbb-b0a7-cc553591cb82
supersedes:
---

# ADR 0001 — The planning decisions of 2026-11-02

## Status

Accepted (Ben, 2026-11-02).

## Context

The repo restarted from an empty tree on 2026-11-02 with the previous work archived at
bknize/midnightearth-archive. Three planning phases were run in one day, each as research
tables followed by numbered questions with lettered options; Ben accepted or amended each.

## Decision

The 21 decisions are recorded, with their consequences, in the phase notes:

- **D1–D8, tech stack:** [[planning/phase-1-tech-stack#Decisions]] — 3D cards on Card3D,
  Godot 4.6.3 Mobile, Replicate + Recraft for art, no backend with a deterministic
  engine, `make check` gate plus edit hook, godot-mcp-server for verification, no
  night_ui, desktop every cycle and iOS at milestones.
- **P1–P8, dev tools:** [[planning/phase-2-dev-tools#Decisions]] — the orchestrator is a
  Claude Code agent pattern, `docs/` is the vault and `godot/` the project, plain
  files plus the Obsidian CLI, one Linear team (NSC) with a project per spec and a
  milestone per cycle, the P5 note schema, committed `.mcp.json` with `.env` secrets,
  the screenshot-backed acceptance ritual, a scaffolding-only cycle 0.
- **R1–R9, game loop:** [[planning/phase-3-game-loop#Decisions]] — sequential face-down
  commits with visible counts, persistent shared board, fresh shuffle per round with
  3+1 draws, tie and sudden-death rules, multi-card turns, one mirrored 20-card deck, a
  greedy bot, off-screen deck and discard, last-turn winner commits first with
  alternating reveal.

This ADR exists so later ADRs have a single note to supersede when one of the 21 changes.

## Consequences

Cycle 0 ([[specs/cycle-0-scaffolding/spec]]) implements P8. Any later change to a
planning decision is a new ADR naming this one in `supersedes` and the decision id in
its title.
