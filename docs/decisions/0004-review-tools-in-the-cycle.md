---
type: adr
tags: [adr, review, cycles]
status: accepted
related: ["[[decisions/decisions-moc]]", "[[specs/cycle-10-review-tools/spec]]", "[[specs/cycle-10-review-tools/plan]]", "[[decisions/0002-one-branch-per-cycle]]"]
created: 2026-11-07
updated: 2026-11-07
uid: 1c2e1858-22cc-44da-a739-9fe366d616ab
linear: https://linear.app/night-science-llc/issue/NSC-165
supersedes:
---

# ADR 0004 — Review tools in the cycle

## Status

Accepted (Ben, 2026-11-07, spec `cycle-10-review-tools`, rounds 1 to 3).

## Context

Claude Code ships two built-in skills: `/code-review`, which reads a diff and reports
findings, and `/simplify`, which rewrites a diff for reuse, quality and efficiency. Both
are language-agnostic. Neither runs Godot, and neither knows the project's determinism
rules (seeded RNG, serializable action log, replay) or its typed-GDScript gate.

The `reviewer` agent already reads a diff and reports. Its brief overlaps `/code-review`
on correctness and `/simplify` on simplification, and it alone knows spec conformance and
the constitution.

## Decision

1. **A step 0 at `/cycle test`**, before the gate, on the cycle branch's diff against
   `master`: `/code-review medium`, then `/simplify`.
2. **Effort rule.** Report-only by default. `--fix`, `max` and `ultra` are used only when
   Ben names them. `ultra` is Ben's to launch, never the orchestrator's. Never
   `--comment`.
3. **Triage.** Findings are sorted blocker / should-fix / nit and put to Ben as one
   numbered question. Declined findings are filed in Backlog.
4. **Gate after each.** `scripts/check.sh` runs after the review fixes and again after
   `/simplify`, plus `make sweep` if `godot/engine/` changed.
5. **`/simplify` diff is read, not trusted.** The orchestrator reverts any change that
   weakens a test, touches the seeded RNG, the action log or replay, or reaches outside the
   cycle's diff.
6. **The reviewer agent drops simplification.** It keeps spec conformance, correctness
   and the constitution.
7. **Two commits per step**: `dc-NN: review fixes` and `dc-NN: simplify`, each omitted
   when empty. This bends "one commit per task" so a simplification can be reverted
   alone (Ben, round 2, 4a).

## Consequences

- One extra gate run per cycle.
- `/simplify` edits land through the orchestrator, not an implementer, so the diff read in
  item 5 is the only check between the skill and the branch.
- The one-off cleanup pass of this spec runs the same procedure over six chunks of the
  existing tree.
- The step is first exercised at the next cycle's `/cycle test` (Ben, round 3, 3b).
- Changed: `CLAUDE.md`, the `/cycle` skill and the `reviewer` agent brief.
