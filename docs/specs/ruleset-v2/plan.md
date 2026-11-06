---
type: plan
tags: [plan, ruleset-v2, rules, vault, design]
status: approved
related: ["[[specs/ruleset-v2/spec]]", "[[specs/ruleset-v2/tasks]]", "[[cards/Cards]]", "[[systems/systems-moc]]", "[[planning/phase-1-tech-stack]]"]
created: 2026-11-06
updated: 2026-11-06
uid: d06f1487-1995-4f34-8d3c-fa3a565b0eaa
linear: https://linear.app/night-science-llc/project/ruleset-v2-hardened-vocabulary-resolution-chart-new-card-set-7f65436c0b01
supersedes:
---

# Plan: Ruleset v2 — hardened vocabulary, resolution chart, new card set

Implements [[specs/ruleset-v2/spec|spec]]. This is the HOW for a vault-only set: which
notes, in what order, with what contract between them, and how each is checked. Nothing
here changes a requirement. No code is written; the tech stack enters only as the thing the
canon is written to be implemented against later.

## Stack mapping

| Area | Involved | Approach and tooling |
|---|---|---|
| Godot scenes/UI | no | — |
| Engine (godot/engine + tests) | no (read only) | Implementers read `match_rules.gd`, `card_effect.gd`, `score_walk.gd` and the system guides to state today's rule beside each change; they edit nothing under `godot/` |
| Shaders/cards | no | — |
| Tooling/scripts | no | — |
| Vault/docs | yes | Seven notes under `docs/rules/` with P5 frontmatter (`type: reference`), root-relative wikilinks, link audit with `obsidian-cli vault=docs unresolved` and `orphans`; one line in [[home]]; one row in [[specs/specs-moc]] |
| Linear | yes | Project per spec, labels `area/vault`, `type/design`, `spec/ruleset-v2`, filled by `/exercise` |

## Interfaces and contracts

The contract between the notes is the glossary. It is written first and every later note
is checked against it.

| Note | Path | Owns | Must not contain |
|---|---|---|---|
| Rules MOC | `docs/rules/rules-moc.md` | One paragraph on what the canon is and the order to read it in; links to the six notes, to the spec, to [[cards/Cards]] and to [[systems/systems-moc]] | Rules sentences |
| Glossary | `docs/rules/glossary.md` | One entry per term in spec R1 (term, one-sentence definition, the moment or zone it belongs to, today's name if different), the retired-words table (R2), the status table (R31–R37: name, what it stops, default cessation, badge word), the trigger-moment table (R50) | Card lists, numbers that belong to rules-v2 |
| Rules v2 | `docs/rules/rules-v2.md` | Match, Round, Turn (R5–R9); Energy and Cost (R10–R12); Hand (R13–R17); Deck and Pile (R18–R24); card anatomy and Score maths with a worked example (R25–R30); statuses as rules (R31–R38); movement (R39–R41); hidden information (R53–R54); a "changed from today" table with today's rule, the v2 rule and the spec requirement | Trigger ordering (that is the chart's), card text |
| Resolution chart | `docs/rules/resolution.md` | The step-by-step chart (R42): a numbered list from turn start to turn end, a mermaid flowchart of one pulse with its drain points, the queue and Batch rules (R43–R45), the budget and "exhausted" (R46), variable N and retriggers (R47–R49), exits and status expiry at turn end (R35, R9), Crew Batches (R51), prompts (R52), and the worked traces of every spec scenario | New rules not in the spec |
| Crew v2 | `docs/rules/crew-v2.md` | The ten Crew (R55–R58): table with name, strategy or evergreen, trigger moment, text in glossary terms, cessation, uses and scope, prompts; a paragraph per Crew on the play it enables; Dredger as working name flagged for Ben | Card text |
| Cards v2 | `docs/rules/cards-v2.md` | The 90 cards (R59–R62, R65): six strategy sections of ten plus one evergreen section of thirty, each a table (name, Cost, Power, Bonus, text, source line in [[cards/Cards]] or "new", flags); a strategy plan paragraph per section (R62); the Power-guideline exceptions table (R61); a disposition table for every salvage row and card idea in [[cards/Cards]] (used as, merged into, dropped because) | Rules that belong in rules-v2 or the chart; the word destroy, flat, burn except in the disposition table |
| Test decks | `docs/rules/test-decks.md` | Six decks (R63–R64): name, strategy, the ten cards × 4, three Crew, average Cost, the fixture disclaimer; a paragraph on what Bloom/Ruin/Drift/Echo's names now mean | Anything that reads as canon deck lists |

Card text style, binding for `cards-v2` and `crew-v2`: moment first ("On reveal:"), one
sentence, glossary verbs only (Condemn, Squelch, Mute, Silence, Discard, draw, move, swap,
reverse, grow), every status with its cessation, every amount either a number or "N" with
N defined in the same sentence, "for the match" for Memory, no "destroy", "flat", "burn",
"return" or bare "bonus".

Frontmatter for every canon note:

```yaml
type: reference
tags: [reference, rules-v2, <note>]
status: seedling
related: ["[[specs/ruleset-v2/spec]]", "[[rules/rules-moc]]", "[[rules/glossary]]", "<the as-built guide it will replace>"]
created: 2026-11-06
updated: 2026-11-06
uid: <fresh uuidgen | tr A-Z a-z>
linear: <the task's issue URL, from /exercise>
supersedes:
```

Each note's first paragraph says it is design for ruleset v2, not yet built, and names the
as-built guide ([[systems/game-loop]] or [[systems/cards-crew-decks]]) that describes the
code today (spec R67).

## Data model

Notes only. The vocabulary the glossary fixes is the data model the next engine cycle will
serialize; the chart names what state a future `MatchState` must hold, without naming
fields:

- Per card on a row: revealed or face down, Controller, Owner, board changes, Memory, one
  exit mark or none (Condemned | Fleeting | Fade), status set drawn from {Muted, Squelched,
  Silenced, Anchored} each with a cessation (end of turn | permanent | condition).
- Per seat: hand (unbounded during a Turn), Deck (40, may be empty), Pile (public), Budget,
  Hand size, Crew with uses.
- Per Walk: the queue of Batches, the per-pulse resolution count against the budget of 50,
  the cursor per row (as cycle 5), the running multiplier per seat.
- Per Match: Round and Turn counters, Round wins, the first committer, the seed.

The plan records this so the implementation specs can cite it; it is not a requirement.

## Constitution Check

| Rule | Verdict | Note |
|---|---|---|
| All project GDScript is fully typed | PASS | No GDScript is written or edited |
| Engine is deterministic (D4) | PASS | Nothing under `godot/` changes; the chart's budget and committer-order rules are written so a future engine can be deterministic |
| `make check` gate contract | PASS | Run once at verification to confirm no code slipped in; vault-only set |
| Implementers never run Godot or `make check` | PASS | Vault implementers read code, run nothing |
| Notes carry P5 frontmatter and root-relative links | PASS | Frontmatter block above; link audit at T8 |
| No edits under the do-not-touch list | PASS | `docs/.obsidian/`, addons, `.env`, `.godot/`, `reports/`, the archive untouched; Ben's uncommitted edits to two system notes are left alone |
| Secrets only in `.env` | PASS | None involved |
| Each changeset on its own branch, one commit per task, nothing on `master`, `--no-ff` merge | PASS | Branch `ruleset-v2` cut from `master` at `/spec`; `spec: ruleset-v2`, then `exercise:`, then one commit per note |

**Result:** PASS.

## Waves and sequencing

| Wave | Tasks | Why |
|---|---|---|
| 1 | T1 glossary | Everything else is written against it |
| 2 | T2 rules-v2, T3 resolution, T4 crew-v2 | Independent given the glossary; three implementers in parallel worktrees, three files |
| 3 | T5 cards-v2 | Needs the rules, the chart (for the flags) and the Crew (so strategies and Crew agree) |
| 4 | T6 test-decks and rules-moc, home line | Needs the final card list |
| 5 | T7 reviewer vocabulary audit | Reads all seven |
| 6 | T8 verification | Orchestrator: link audit, `make check`, Ben's read |

Fixes from T7 go back to the owning task's implementer as a re-dispatch, one commit each.

After this set, the implementation order the plan expects (one paragraph, not a decision):
an engine cycle for rules-v2 and the chart (statuses, exits, the Pile, hand 4, 40-card
decks, the queue and budget, rules version 7), then a content cycle for the ten Crew and
the first strategy decks, then the rest of the pool. Each gets its own `/spec`.

## Risks and mitigations

- The glossary drifts while later notes are written (an implementer needs a term it lacks)
  -> the implementer adds the term to the glossary in the same task and says so in the
  report; T7 checks the glossary against every note, not the notes against a frozen glossary.
- 90 cards by one implementer is a long task -> T5 is sized L and may be split by the
  orchestrator into strategy and evergreen halves only if both land in the same note in one
  wave; the disposition table is the check that nothing from [[cards/Cards]] was lost.
- Design prose written by a code-oriented implementer reads like a changelog -> the brief
  for each task carries the spec's style rules and the system guides as the tone to match;
  Ben's read is the acceptance, not the reviewer's.
- Two truths in the vault (systems say one thing, rules another) -> every canon note opens
  with "design, not yet built" and names its as-built counterpart; `docs/systems/` is not
  edited here and gets its pointer when it is next rewritten.
- Loops that the budget merely truncates feel random -> the chart lists the retrigger and
  loop-prone cards (R65) and `cards-v2` keeps self-feeding pairs rare and flagged.
- Ben's uncommitted edits ride on this branch -> no task touches those two files; the
  orchestrator commits only `docs/specs/ruleset-v2`, `docs/specs/specs-moc.md` and, later,
  `docs/rules/` and `docs/home.md`.

## Open questions

- Working name of the tenth Crew (Dredger) and the exact reading of Void's "10 +2x1.5"
  (spec R56) are for Ben to confirm when he reads `crew-v2`; the note flags both.
- None blocking.
