---
type: adr
tags: [adr, cost, cycles, linear]
status: accepted
related: ["[[decisions/decisions-moc]]", "[[decisions/0002-one-branch-per-cycle]]", "[[decisions/0004-review-tools-in-the-cycle]]"]
created: 2026-11-08
updated: 2026-11-08
uid: fd5e3707-2266-4d87-99e8-867efbcf1e49
supersedes:
---

# ADR 0006 — Cutting token spend

## Status

Accepted (Ben, 2026-11-08: "1a 2a 3a" on the token-spend audit). Amends P4's link rule and
decision 2 of [[decisions/0002-one-branch-per-cycle]], and replaces the
interrogator subagent and its relay.

## Context

An audit of every transcript from 2026-11-01 to 2026-11-08 (20 cycles, 158 merged issues)
came to about $1,301 at API list prices:

| Role | Cost | Share |
|---|---:|---:|
| Orchestrator | $583 | 45% |
| `implementer-engine` | $370 | 28% |
| Interrogator | $152 | 12% |
| Other subagents | $137 | 11% |
| `implementer` | $60 | 5% |

Three causes stood out:

- **Orchestrator turns are expensive.** It averaged 329k of context, so even a trivial turn
  cost about $0.11. Landing one issue took about seven shell calls, and 996 status-only
  `save_issue` calls each echoed the whole issue back.
- **Subagent caches last 5 minutes; the orchestrator's lasted an hour.** Each interview
  answer that took longer rewrote the whole Fable context, about $1.90 instead of $0.04 at
  150k. That was $74 across 13 specs.
- **Implementers make one tool call per turn.** 83% of their turns do, and each re-reads the
  context.

## Decision

1. **`/spec` runs as a top-level Fable 5.1 session,** with no subagent and no relay. Fable
   stays the model for interviews and spec-writing. After sign-off and commit it offers to
   start `/exercise` in a new Opus 5.5 session on the same checkout.
2. **Each verb starts in a new session,** and `/cycle run` starts another at a wave boundary
   past about 250k of context. A simulation of November showed splitting at 150k costs more
   than it saves.
3. **`scripts/cycle-land.sh`** commits, merges and gates one issue in one call.
4. **`scripts/linear-move.sh`** does bulk status moves and prints one line. The MCP remains
   for everything else, and is the fallback when `.env` has no `LINEAR_API_KEY`.
5. **Linear links point at `blob/master/` from the start,** so `/cycle test` no longer
   rewrites them (206 patches in the period).
6. **Implementers batch reads and take pinned locations from the brief.**
7. **Routing stays as it is, pending a trial.** The first wave under `godot/engine/` that is
   only data or tests goes to `implementer`, and the cycle's row records the cost and gate
   results. `/simplify` stays in every cycle ([[decisions/0004-review-tools-in-the-cycle]]).

The orchestrator stays on Opus 5.5. Sonnet 5.5 costs half as much for output and cache
writes but the same $0.20 per MTok for cache reads, which were 62% of orchestrator spend. It
would have saved about $100 (8% of the total), so it is not worth the risk to judgement work
for now.

## Consequences

- The estimated saving is $200 to $260 per 20 cycles, 15 to 20%. It is an estimate, not a
  measurement: compare against the next audit.
- GitHub links in Linear do not resolve until the cycle is merged and `master` is pushed. The
  vault link works throughout.
- A new orchestrator session re-reads state at about $1 each, which is why splitting has a
  floor.
- The 1-hour cache is the app's behaviour, not a setting of ours. It may drop to 5 minutes
  when a session is in usage overage, which would bring the interview rewrites back.
