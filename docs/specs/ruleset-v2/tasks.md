---
type: tasks
tags: [tasks, ruleset-v2, rules, vault, design]
status: approved
related: ["[[specs/ruleset-v2/spec]]", "[[specs/ruleset-v2/plan]]", "[[cards/Cards]]", "[[planning/phase-1-tech-stack]]"]
created: 2026-11-06
updated: 2026-11-09
uid: 0ed7d2ea-9a29-4b9c-aeca-c6aadb17f836
supersedes:
---

# Tasks: Ruleset v2 — hardened vocabulary, resolution chart, new card set

Derived from [[specs/ruleset-v2/plan|plan]]. Numbered, dependency-ordered, independently
reviewable. Every build task is a vault task: the implementer writes one note under
`docs/rules/` in a worktree from the spec, the plan's note contract and the glossary, reads
`godot/engine/` and `docs/systems/` only to state today's rule, and edits nothing else.
`reviewer` reads the notes and returns findings; `orchestrator` runs the link audit and
`make check`, relays Ben's read and handles Linear. Six waves (plan).

| # | Task | Area | Depends on | Acceptance check | Who | Status |
|---|---|---|---|---|---|---|
| 1 | **Glossary.** Write `docs/rules/glossary.md`: one entry per term in spec R1 with its one-sentence meaning, zone or moment, and today's name where it differs; the retired-words table (R2); the status table (R31–R37: name, what it stops, default cessation, how Silenced forms and splits); the trigger-moment table (R50). Frontmatter per the plan | vault | – | Every R1 term and every R2 retired word has a row; Silenced's rule reads as C5; no entry uses an undefined term; P5 frontmatter with a fresh uid | implementer | done |
| 2 | **Rules v2.** Write `docs/rules/rules-v2.md`: Match, Round, Turn phases and turn-end steps (R5–R9); Energy and Cost (R10–R12); Hand and the discard-down (R13–R17); Deck and Pile (R18–R24); card anatomy, Bonus growth and Score maths with one worked row (R25–R30); the statuses as rules (R31–R38); movement (R39–R41); hidden information (R53–R54); a "changed from today" table (today's rule, v2 rule, requirement) | vault | 1 | Each of R5–R41 and R53–R54 is traceable to a sentence; the worked example reproduces today's maths on a three-card row; the table covers energy, hand, deck, pile, destroy, statuses, movement; glossary terms only | implementer | done |
| 3 | **Resolution chart.** Write `docs/rules/resolution.md`: the numbered turn walkthrough from turn start to turn end with every queue drain point (R42); a mermaid flowchart of one pulse (reveal stage, drain, score stage, drain); queue, Batch, snapshot and order rules (R43–R45); the 50-resolution budget and "exhausted" (R46); variable N, retriggers, "Scores twice" (R47–R49); exits and status expiry (R35, R9); Crew Batches and prompts (R51–R52); a traced walkthrough of every spec scenario | vault | 1 | A reader can trace each of the spec's nine scenarios to the step that decides it; the flowchart has exactly the drain points R43 names; the committer-order rule and the budget are stated once each; glossary terms only | implementer | done |
| 4 | **Crew v2.** Write `docs/rules/crew-v2.md`: the ten Crew (R55–R58) as a table (name, evergreen or strategy, moment, text, cessation, uses and scope, prompts) and a paragraph each on the play it enables; Dredger flagged as a working name; Void's reading flagged for Ben (R56); three per deck with sharing (R58) | vault | 1 | Ten rows; Tallyman says +5 Add, Captain says leftmost slot; every status a Crew grants carries a cessation; each Crew tagged; the two flags present | implementer | done |
| 5 | **Cards v2.** Write `docs/rules/cards-v2.md`: six strategy sections of ten cards and one evergreen section of thirty (R59), each card with name, Cost, Power, Bonus, text, source line in [[cards/Cards]] or "new", flags (R65); a strategy plan paragraph per section (R62); the Power-guideline exceptions table (R61); a disposition table for every salvage row and card idea in [[cards/Cards]] (used as, merged into, dropped because) (R60). Size L | vault | 2, 3, 4 | 90 cards, 60 tagged and 30 evergreen; every line of the scratch sheet's salvage table and ideas list appears in the disposition table; no "destroy", "flat", "burn", "return" or bare "bonus" outside that table; each strategy plan names the Round 2, Round 5 and dry-deck intent; loops, retriggers, leaks and Controller changes flagged | implementer | done |
| 6 | **Test decks, MOC and home.** Write `docs/rules/test-decks.md` (six 40-card decks, three Crew each, average Cost, the fixture disclaimer, the Bloom/Ruin/Drift/Echo paragraph; R63–R64) and `docs/rules/rules-moc.md` (what the canon is, reading order, links to the six notes, the spec, [[cards/Cards]], [[systems/systems-moc]]); add one bullet to [[home]] pointing at the rules MOC (R66) | vault | 5 | Six decks of exactly 40 from the ten tagged cards × 4 with three Crew from crew-v2; the disclaimer present; the MOC links all seven paths; home has the line and nothing else changed | implementer | done |
| 7 | **Vocabulary and consistency review.** Read all seven notes. Report every rules sentence whose noun or verb does not resolve to a glossary entry (R69), every contradiction between notes, every spec requirement with no sentence behind it, and every card whose text the chart cannot resolve. Findings only | vault | 6 | A findings list grouped by note with the offending sentence quoted; "nothing" is a legal result per group | reviewer | done |
| 8 | **Verification** (below) | vault | 7 | All boxes checked | orchestrator | done |

Fixes from T7 are re-dispatched to the owning task's implementer, one commit each
(`dc-NN: T07 fixes <note>`), before T8.

## Verification task (always last)

Task 8, owned by the orchestrator:

- [x] `make check` exits 0 (no code was touched; this proves nothing slipped into `godot/`).
- [x] `git status` shows only `docs/rules/`, `docs/home.md`, `docs/specs/ruleset-v2/` and
      `docs/specs/specs-moc.md` changed on the branch, plus Ben's pre-existing edits to the
      two system notes untouched.
- [ ] Every canon note has P5 frontmatter, `type: reference`, a fresh uid, and opens with
      the "design, not yet built" sentence naming its as-built guide (R67). (superseded: the canon notes are built, so the 'design, not yet built' opener no longer applies (DC-13, DC-14), DC-20 T19)
- [x] The spec's definition-of-done list is checked line by line against the notes.
- [x] No screenshot: a vault-only set (P7 covers visible features).
- [x] `obsidian-cli vault=docs unresolved` and `obsidian-cli vault=docs orphans` report
      nothing new for `docs/rules/` or `docs/specs/ruleset-v2/` (R68).
- [x] Ben has read each of the seven notes and said so; his changes are applied as T7-style
      fix commits before the branch merges.

## Commit plan

The whole set is one changeset on the branch `ruleset-v2`, cut from `master` at `/spec`
before the first note (`CLAUDE.md`, Git; [[decisions/0002-one-branch-per-cycle]]). It
carries the spec (`spec: ruleset-v2`, with the specs MOC row), the Linear write-back
(`exercise: ruleset-v2`), one commit per task (`dc-NN: T<nn> <note>`), the T7 fixes and the
verification outcome, each message ending with the Co-Authored-By line the session
provides. Ben's uncommitted edits to `docs/systems/bot-training.md` and
`docs/systems/cards-crew-decks.md` are his to commit and are not staged by any task. When
T8 passes, `/cycle test` merges the branch into `master` with `git merge --no-ff`. Nothing
is committed directly on `master`.
