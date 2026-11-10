---
type: planning
tags: [planning, backlog]
status: growing
related: ["[[planning/cycles]]", "[[specs/specs-moc]]", "[[decisions/0007-no-ticket-tracker]]"]
created: 2026-11-09
updated: 2026-11-09
uid: 541c3d09-80ee-4ad5-9246-8d72c0ba7625
supersedes:
---

# Backlog

Work that is not a row in a spec's `tasks.md`: follow-ups from a review or a test, bugs and
ideas. Each item has a `B-nn` id that notes, code comments and commit subjects may cite. An
item is `open` until a cycle picks it up (the task that takes it names it in its `Closes`
column or its text); it becomes `done` when its work is merged into the cycle branch on a green gate, or
`dropped` with a reason. New items take the next unused number and go
at the end of the open table. `make dashboard` reads this note
([[decisions/0007-no-ticket-tracker]]).

B-01 to B-63 were Linear issues until 2026-11-09, renumbered in the order they were filed.

## Open

| # | Item | Status | Where |
|---|---|---|---|
| B-54 | PVP server: router forward, CGNAT check and public address | open | Training nights and router |
| B-56 | Linear bot overruns the 10 ms decision budget | open | DC-21 training-rounds |
| B-59 | Trainer: protocol and schema items split from B-50 | open | Training nights and router |
| B-60 | Limited `uses`: latent oddities left by the DC-20 review | open | – |
| B-61 | DC-20 review nits: resync failure reason, free-first drop, verb handler allocation, expired Dross Memory | open | – |
| B-62 | PC at the DC-20 tip: redeploy, trainer tests, planted log rotation | open | Training nights and router |
| B-63 | Hidden card ids in public exit and unreveal events (sweep fails on trained linear weights) | open | DC-21 training-rounds |

## Closed

| # | Item | Status | Where |
|---|---|---|---|
| B-01 | Manual: create the "Spec task" issue template, rename team key to NSC, install GitHub integration, accept Xcode license | done | – |
| B-02 | Engine: keep the final table after MATCH_ENDED (spec C15) | done | DC-02 hardening |
| B-03 | Engine hardening: bound action ints, recursive no-print scan, bot CardDb fallback | done | DC-02 hardening |
| B-04 | Tooling: edit hook skips the gate's typed-strict warnings; cycle skill screenshot rule vs C12 | done | DC-02 hardening |
| B-05 | Concede click once closed the pause menu without conceding (not reproduced) | done | DC-04 board-feedback |
| B-06 | Edit hook skips gdlint silently when ~/.local/bin is not on its PATH | done | cycle-14 T14 (DC-20) |
| B-07 | Board: tap path halt check and a card_lift suite | done | cycle-14 T10 (DC-20) |
| B-08 | HUD shows a provisional score while a reveal prompt pauses the walk | done | – |
| B-09 | Bot's slowest decision is about 15 ms, over plan P13's 10 ms budget | done | DC-08 bot-players |
| B-10 | /cycle test: worktree sweep deletes the cycle's screenshots | done | cycle-14 T14 (DC-20) |
| B-11 | Prompt reader: the action button overlaps the bottom of the lifted card | done | DC-07 constructed-decks |
| B-12 | DC-07 visual follow-ups: glow washes out faces, strip overlap, two-part bonus label, picker selection contrast | dropped | – |
| B-13 | DC-09 follow-up: own face-down grown card may reveal with its printed face | done | DC-11 crew |
| B-14 | Test-time headroom before DC-11: gdUnit at 29.2 s of the 30 s budget | done | DC-10 bot-training |
| B-15 | DC-10 follow-up: deferred review nits | dropped | – |
| B-16 | DC-11 follow-up: CrewPool.fires is in neither the stamp nor the log | dropped | – |
| B-17 | DC-11 follow-up: Crew card text overflows and the badge covers it; own reveal face unchecked on the board | dropped | – |
| B-18 | DC-13 follow-up: the Pile strip covers the opponent's row | done | DC-14 rules-v2-content |
| B-19 | DC-13 follow-up: the multi-select glow washes out the hand's card faces | done | DC-14 rules-v2-content |
| B-20 | to_pile files a created card with no owner in seat 0's Pile | done | cycle-14 T03 (DC-20) |
| B-21 | Random bot: same-turn prompts with no source card share one seed | dropped | – |
| B-22 | C1 review nits: dead prompt branches, empty-prompt bot answer, double cost scan, seat count | done | cycle-14 T02 (DC-20) |
| B-23 | Q11 resumed draw is dropped when the trigger budget runs out | done | cycle-14 T02 (DC-20) |
| B-24 | Created cards and replaced definitions live outside MatchState | done | cycle-14 T03 |
| B-25 | C2 nits: engine rules cleanup left by DC-15 | done | cycle-14 T06 (DC-20) |
| B-26 | Immolator and Fuse random picks include cards a Condemn cannot change | done | cycle-14 T03 (DC-20) |
| B-27 | Limited `uses` on abilities and Crew are never enforced | done | cycle-14 T04 (DC-20) |
| B-28 | Level can raise a face-down card's Power | done | cycle-14 T03 (DC-20) |
| B-29 | Crew STATS_CHANGED should use the shared Abilities helper | done | cycle-14 T04 (DC-20) |
| B-30 | C3 nits: card content cleanup left by DC-15 | done | cycle-14 T07 (DC-20) |
| B-31 | Board never learns Lantern's free first card | done | cycle-14 T03, cycle-14 T10 (DC-20) |
| B-32 | Crew firings get no beat on the board (CREW_FIRED is never emitted) | done | cycle-14 T04, cycle-14 T10 (DC-20) |
| B-33 | Deck notes vanish at the next step (set_piles every step) | done | cycle-14 T10 (DC-20) |
| B-34 | C4 nits: board core cleanup left by DC-15 | done | cycle-14 T12 (DC-20) |
| B-35 | C5 nits: board UI, input and main cleanup left by DC-15 | done | cycle-14 T13 (DC-20) |
| B-36 | C6 nit: one shared _typed() test helper | done | cycle-14 T18 (DC-20) |
| B-37 | bot-eval aggregates count the dropped pair of a deciding seed | done | DC-18 bot-trainer-b |
| B-38 | Play-out worker: numeric seeds above 2^53 lose precision silently | done | DC-18 bot-trainer-b |
| B-39 | Play-out worker may allocate a 16 MiB read buffer per request | done | DC-18 bot-trainer-b |
| B-40 | Play-out worker relies on print() flushing each reply | done | cycle-14 T15 (DC-20) |
| B-41 | Rollout label rebuilds view, hidden sets and card data for every play-out | done | DC-17 bot-trainer-a2 |
| B-42 | Rollout outcome serializes the full state to read the Round wins | done | DC-17 bot-trainer-a2 |
| B-43 | Match worker enumerates legal commits at every decision for a diagnostic field | done | DC-18 bot-trainer-b |
| B-44 | Determinization pins non-card numbers of a paused trigger as card ids | done | cycle-14 T05 (DC-20) |
| B-45 | Trainer: sync_code never cleans inbox bundles | done | DC-18 bot-trainer-b |
| B-46 | Trainer: SETUP.md layout omits trainer-data | done | DC-18 bot-trainer-b |
| B-47 | Trainer: a failed report write turns a finished run into failed | done | DC-18 bot-trainer-b |
| B-48 | Trainer: PC rollouts per worker are a third of the Mac's | done | cycle-14 T15 (DC-20) |
| B-49 | Trainer: fold inspect into the label reply | done | DC-18 bot-trainer-b |
| B-50 | Trainer: deeper cleanups left out of the DC-17 simplify pass | done | cycle-14 T17 (DC-20) |
| B-51 | Trainer: four nits from the DC-18 T07 review | done | cycle-14 T15, cycle-14 T16 (DC-20) |
| B-52 | PVP server: review nits from DC-19 | done | cycle-14 T10, cycle-14 T11 (DC-20) |
| B-53 | Stalemate when a sudden-death Round has no commits (rules 8) | done | DC-18 bot-trainer-b |
| B-55 | Crew Power changes can reach the opponent while the card is in a pending Commit | done | cycle-14 T04 (DC-20) |
| B-57 | gdUnit total back over the 30 s budget (30.8 s with DC-18) | done | cycle-14 T18 (DC-20) |
| B-58 | Refresh cycles.md "Planned next" and the stale boxes in finished specs | done | cycle-14 T19 (DC-20) |
