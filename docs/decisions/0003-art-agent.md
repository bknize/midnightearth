---
type: adr
tags: [adr, art, agents, tooling]
status: accepted
related: ["[[decisions/decisions-moc]]", "[[decisions/0001-planning-decisions]]", "[[planning/phase-1-tech-stack]]", "[[planning/phase-2-dev-tools]]"]
created: 2026-11-03
updated: 2026-11-03
uid: ff0299b9-0ac0-41a1-82d3-f94730c09ebd
linear:
supersedes:
---

# ADR 0003 — The art agent

## Status

Accepted (Ben, 2026-11-03).

## Context

Decision D3 ([[planning/phase-1-tech-stack]]) puts art on Replicate (official MCP, API
token, $30/month target, never Claude spend). It plans a FLUX LoRA once 15–30 reference
cards are approved, with Recraft's HTTP API for icons and UI. P6
([[planning/phase-2-dev-tools]]) wired the `replicate` entry in `.mcp.json`. Nothing
yet said who makes the art, how Ben reviews it, or where approved images live. R6 sets
the MVP's art at 20 illustrations, one per card. On 2026-11-03, while the cycle-4
session ran, Ben asked to "start getting the art agent set up".

## Decision

Ben's answers on 2026-11-03 (`1a 2b 3b 4b 5b`):

1. **A tooling changeset, built directly** (1a): branch `tooling-art-agent`, in its own
   worktree so it stays clear of the running cycle. No `/spec` interview.
2. **A Fable 5.1 `artist` subagent plus an `/art` skill** (2b). The artist interviews,
   writes prompts, generates within the image cap in its brief, builds contact sheets
   and recommends picks. It talks to Ben through the orchestrator with the same
   `ROUND` / `REVIEW` / `DONE` relay as the interrogator. Its tools are file tools,
   WebFetch (model price pages) and the Replicate prediction, model and file tools. It
   gets no training tools until a LoRA step asks for them. The orchestrator approves
   and imports; the artist never edits code or `godot/`.
3. **The art direction is set fresh in an interview** (3b), `/art direction`, written to
   `docs/art/art-direction.md`. The archive's "ethereal arcana" direction and style tile
   are one option to show, not the default.
4. **A cheap exploration pass comes first** (4b): `/art explore` runs FLUX schnell
   class models (about $0.003 an image), capped at 50 images, before any reference or
   card set.
5. **Approved images go in Git LFS** (5b): `godot/art/<kind>/<id>.png`, tracked by
   `.gitattributes`. `art/manifest.json` (tracked) records each one's model, version,
   seed, full input and prediction id, so it can be regenerated. Candidates
   (`art/candidates/`) and the spend ledger (`art/ledger.jsonl`) are gitignored.

Set by the orchestrator on the same day, for Ben to overrule:

- Branches: `/art direction` writes on `docs-art-direction`; approved art lands on
  `art-<batch>`, or on the cycle branch it belongs to. Candidates need no branch.
- Spend control: the brief caps images per batch; `scripts/art-fetch.sh` logs an
  estimate per prediction from the published price and exits 3 once the month reaches
  `ART_MONTHLY_BUDGET_USD` (default 30). There is no hard stop: Replicate stopped
  offering spend limits to new customers on 2025-07-01.
- Card art is 5:7 portrait, 1024 × 1440 where the model allows it. Prompts carry a
  seed, and never ask for text in the image or name living artists, brands or
  copyrighted characters.

## Consequences

- Git LFS on GitHub Free gives 10 GiB of storage and 10 GiB of download bandwidth a
  month. Twenty cards at about 2 MB each, with revisions, use well under 1 GiB.
  Pushing uses storage only; every clone or fetch of the images counts against
  bandwidth.
- `git lfs install --local` has to run once per clone (`.git/config`). Worktrees share
  it.
- Subagent definitions load from the session's checkout, so the artist can be
  dispatched only once this branch is on `master` (as with the edit hook in DC-02).
- The Replicate token must be in the main checkout's `.env`. On 2026-11-03 the token
  was empty and the MCP answered 401. The desktop app never runs
  `scripts/claude-with-env.sh`, so `.mcp.json` now starts the server through
  `scripts/replicate-mcp.sh`, which reads the token from `.env` itself (falling back
  to the main checkout's `.env` inside a worktree). This works from the desktop app and
  from a terminal.
- `scripts/art-sheet.py` is the first Python script under `scripts/`. It needs Pillow,
  which is in the user site-packages, so it runs as plain `python3` (not `-I`). It reads
  images only as arguments, so nothing in a candidate folder is ever imported.
- Recraft is deferred until icon or UI work needs it; `.env.example` gains its key then.
