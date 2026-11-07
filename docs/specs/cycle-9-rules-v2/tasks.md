---
type: tasks
tags: [tasks, cycle-9-rules-v2, engine, rules-v2, cards, board]
status: approved
related: ["[[specs/cycle-9-rules-v2/spec]]", "[[specs/cycle-9-rules-v2/plan]]", "[[rules/cards-v2]]", "[[rules/crew-v2]]", "[[rules/test-decks]]", "[[rules/resolution]]", "[[decisions/0002-one-branch-per-cycle]]", "[[planning/phase-1-tech-stack]]", "[[planning/cycles]]", "[[planning/bot-ladder]]"]
created: 2026-11-06
updated: 2026-11-06
uid: 9864f294-25f9-4d49-b40b-ef82cd42f851
linear: https://linear.app/night-science-llc/project/cycle-9-rules-v2-in-the-engine-60e0297b48b8
supersedes:
---

# Tasks: Cycle 9 — rules v2 in the engine

Derived from [[specs/cycle-9-rules-v2/plan|plan]]. Numbered, dependency-ordered,
independently reviewable. Everything under `godot/engine/` goes to `implementer-engine`;
board, `main.gd` and vault work to `implementer`; `reviewer` reads diffs; `orchestrator`
runs `make check` and `make sweep`, pins the golden, drives the Godot MCP and handles Linear.
Implementers write suites but never run them; "passes" is confirmed at T11 and T18. Every
brief carries the typed-strict checklist from the DC-01 lessons, the plan's P-numbers it
implements, its verb rows, and the event and view tables, so board tasks can start from the
contract before the engine lands. R-numbers are the spec's; canon rules are cited as Qn/Dn.

## Milestone A: rules machinery, evergreen, Greed and Ramp (DC-13)

| # | Task | Area | Depends on | Acceptance check | Who |
|---|---|---|---|---|---|
| 1 | The strip (P16; R70–R75): delete every file the plan's "Deleted" list names under `engine/bot/`, `engine/bot/data/`, `tools/`, `engine/pair_preview.gd`, `engine/preview_policy.gd` and the suites and fixtures that exist only for them; remove `MatchEngine.preview*`, `_hide_opponent`, `_stage_commit`, `_finish_preview` and every `PreviewPolicy` parameter and preview branch from `score_walk.gd`, `effect_resolver.gd` and the four effect modules (which still exist at this wave); `BotRegistry` to `["random"]` with no levels, `BotPlayer` without `FULL_LEVEL` and weights, `RandomBot` with its own legal-commit enumeration; `main.gd`, `MatchDriver.create`, `board.gd` and the picker lose the level; `test_full_match.gd` keeps the golden mechanism with `GOLDEN` emptied; the sweep and harness build `random` and drop the weights and stamp print; `scripts/bot/`, `bot-eval.sh`, `bot-train.sh` and the `Makefile` untouched. No rule changes: the engine still plays rules 6 | engine, board, tooling-free | – | `make check` green on rules 6; `ls godot/engine/bot` is `bot_player.gd bot_registry.gd random_bot.gd` (plus `.uid`); `grep -rl "preview\|PreviewPolicy\|BotWeights\|BotStamp" godot/engine godot/board godot/main.gd godot/tests godot/tools` is empty; `git diff --stat master -- scripts Makefile` is empty; `test_random_bot.gd`: 20 seeds end with no rejected action and a fixed per-decision seed replays the same choices; `test_bot_registry.gd`: `make("random")` builds, `make("tuned")` is null, `default_name()` is `random`; `main.gd` with `--bot=tuned` prints the unknown-bot error naming `random` and no board | implementer-engine |
| 2 | Anatomy, data and loaders (P1–P6; R8 loader half, R16, R22, R60–R64): `MatchRules` v7 constants (rules 7 and format 5 bumped here, so `test_action_log.gd`'s pin moves to 7/5 and a format-4 log fails); `CardDef` with tag, power, bonus kind and hundredths; `CardAbility` with the P3 shape and every A verb as a known name checked against its moment and amount range; `CardDb` format 5 and the P2 checks; `CrewDef`/`CrewPool` v2 with the six A verbs; `DeckList` v3 with `validate` per P5; `MatchCards` ids with `CREATED_BASE`; `cards.json` with the 50 cards, `crew.json` with six Crew, `decks.json` with `greed` and `ramp`, every number and text exactly as [[rules/cards-v2]], [[rules/crew-v2]] and [[rules/test-decks]]; delete `{bloom,drift,echo,ruin}_effects.gd`, `card_effect.gd` and the v6 verb enum with their suites; the engine compiles with every ability inert (a stub `Abilities.fire` that fizzles `no_target`) and the walk reading `power` with a ×1 Bonus until T03; `main.gd` smoke plays plain bodies | engine | 1 | `test_card_db.gd`: the shipped file loads 50 cards with 30 `evergreen`, 10 `greed`, 10 `ramp`; a `bonus {"mult": 130}` fails `bonus out of range`; an `add` of 75 fails; `cost 12` without `cost_on_turn` fails, Colossus passes; an unknown moment, an unknown verb, `draw` on `ongoing`, a missing `text` with an ability, a duplicate id and version 4 each fail by name. `test_crew_pool.gd`: six Crew load; a moment or verb not in the table fails. `test_deck_list.gd`: 39 cards, five copies of one id, two Crew, a repeated Crew and an unknown id each fail; both shipped decks pass. `test_decks.gd`: `greed` sums to Cost 136 over 40 and `ramp` to 152, with the Crew the canon lists. `test_action_log.gd`: header `format 5, rules 7`; a format-4 log fails replay with `FORMAT_MISMATCH` | implementer-engine |
| 3 | Match structure and the walking total (P1, P7, P14 less the queue, P15; R1–R21, R25–R31, R57, R58, R65–R68): `MatchState` v7 (`pile` replaces `destroyed`/`burned`; `total`, `grants`, `committed_count`, `looked`; no `carry`), `Scoring` with the P7 arithmetic and growth, `TurnFlow` (Match start deals 4 once; Deck shuffled once; each Turn both seats draw first seat first; `DRAW_EMPTY` with no re-check and the Q11 resumed draw as hooks T07 fills; Budget = turn + grants; Commit cost with Memory reductions; the discard-down prompt with `exact` after the On commit point; Round end rows to Piles as Discards; turn end order with the exit pass as a hook T04 fills), `ScoreWalk` scoring by the walking total and `CARD_SCORED {power, bonus_value, total}`, `WALK_ENDED` rounding, `Choice` zones for Piles and the deck top, `LegalPlays` on reductions and `exact`, `SeatView` per P15 (Piles public, `totals`, `scores`, `hand_sizes`, `looked`), `MatchEvent` rebuilt to the v7 table, the harness's leak scan per P15 | engine | 2 | `test_scoring.gd`: the canon's worked rows give 16 and 24; `(1 + 0.5) × 1.25` is 18750; total 25000 with Power 1 and ×1.25 is 43750; Walk-end rounding of 43750 is 4, of -15000 is -1, of 5000 is 1; growth `×1.5 + 0.25 then ×1.2` is 210, Sapling caps at 200, Graft at 250. `test_turn_flow.gd`: four cards dealt once, none at Round 2; Deck 36 after the deal; a hand of six with Hand size 4 after a one-card Commit opens an `exact 1` prompt for that seat, a two-card set is rejected, seat 1's Commit is rejected while it is open, the Discard lands in the Pile with `reason discard_down`; Pantry read by a stub makes Hand size 6; a Pass is accepted and `committed_count` is 0; Round end sends both rows to their Owners' Piles with `reason round_end` and hands stay; an empty Deck draws nothing and emits `DRAW_EMPTY`; no card is ever burned (no event kind exists). `test_engine.gd`: Budget on Turn 5 is 5, with a grant 6, nothing carries; a Commit over Budget is rejected unchanged; a cost-3 card with Memory -1 commits on Budget 2. `test_seat_view.gd`: both Piles listed in full for both seats; the opponent's hand count only; `totals` in ten-thousandths. `test_full_match.gd`: 10 seeds of random vs random end, every log replays to an equal `full_state`, the leak scan is clean | implementer-engine |
| 4 | Statuses, exit marks and movement (P8–P10; R30–R44): `CardState` and `CardMemory` per P8, `Statuses` per P9 (both halves, Silenced derived, cessations, protections, scope ends, On squelch only when alone), exit marks with replacement and the exit pass in Q3 order reading exit-changing Ongoings once, `Movement` per P10 with Anchored, Placement, the cycle-5 cursor adjustments, `STATUS_SET/ENDED`, `EXIT_MARKED/RESOLVED`, `CARD_MOVED`, `CARD_UNREVEALED`, `CARD_RETURNED`; `tests/fixtures/stub_abilities.gd` with the plan's stub verbs | engine | 3 | `test_statuses.gd`: Muted fires nothing and Scores; Squelched Scores nothing and fires; Muted then Squelched is Silenced and the view lists `Silenced`; ending the Mute leaves Squelched and On squelch does not fire for the Silence, does for a lone Squelch; a `permanent` Squelch survives the Pile and a redraw; a `turn` Anchor ends at turn end; a board-scoped status ends on Fade; Ward blocks a Mute and turns a Silence into a Squelch; Bastion blocks Condemned. `test_statuses.gd` (exits): Fleeting then Condemned holds Condemned only; a Condemned card Scores, then goes to its Owner's Pile with `reason condemned`; Fleeting goes to its Owner's hand with Board changes gone and Memory kept; Fade flips face down keeping Memory; a card the other seat controls returns to its Owner; the pass runs first seat's row first in slot order. `test_movement.gd`: A B C with B Anchored and "others shift left" reads C B A with On moved for A and C only; Nudge from the rightmost slot wraps to slot 0; a swap naming an Anchored card fizzles; reverse and reorder keep Anchored slots; a committed card changes slot numbers without On moved; a card moved behind the cursor waits, one landing on the pulsed slot Scores now | implementer-engine |
| 5 | The trigger queue (P11, P12; R45–R56): `TriggerQueue` with Batches, snapshots, Q3 order, the 50 budget and `exhausted`, amounts at resolution, retrigger and scores-twice hooks, prompts pausing a drain and resuming at the same entry with `resume` and `step`; the ten moments with watcher and zone brackets; the twelve drain points wired through `TurnFlow` and `ScoreWalk`; `MatchState.queue` serialized; `TRIGGER_FIRED/FIZZLED`, `PROMPT_OPENED` | engine | 4 | `test_trigger_queue.gd`: a stub On score that wakes two watchers appends one Batch and finishes before either fires; a card Condemned mid-Batch still fires once; a card Muted mid-Batch does not; order is cards (first seat by slot, second seat by slot) then Crew by slot; two stubs feeding each other stop at exactly 50 resolutions with every remaining entry fizzling `exhausted` and the next pulse starting at 0; a prompt inside D8 pauses with phase `AWAIT_CHOICE`, `resume walk`, a Commit is rejected, the answer resumes at the next entry; `stub_retrigger` adds one extra resolution right after each applicable one, never to itself, with a fresh prompt and re-read N; `stub_scores_twice` runs the score stage twice and `CARD_SCORED pass 2` follows `pass 1`; a hand card with `zone hand` fires On commit, a card committed this Turn does not; On start fires for revealed cards only; a `full_state()` taken while paused replays to the same state and resumes the same way | implementer-engine |
| 6 | Card abilities A (P3 verb table, P12; R60): every verb of the plan's milestone A table in `Abilities`, with eligibility, prompts, private look-ats (`looked`, `deck_top`, `CARD_LOOKED`), Memory growth with caps, cost reductions, Energy grants, the free-first, the Pass check; every A card behaves as its canon text and Flags | engine | 5 | `test_abilities_evergreen.gd`: Tuft +1 per Score until it leaves the row; Scout draws, from an empty Deck fires On empty draw; Delve offers three, the chosen one is drawn, the other two are shuffled in with the stream, the other seat's view and events see counts only; Lookout records the card in the looker's `looked`, the other view does not, and the leak scan passes; Scapegoat on a stub Squelch ends it and Condemns itself; Ward then a stub Silence leaves Squelched; Mirror copies a revealed opposing card's Power and Bonuses until turn end and does not offer a face-down card; Nudge wraps; Pantry gives Hand size 6; Brace is not moved by a stub shift and is moved once Squelched; Loom and Bolster grant until turn end; Bastion refuses a stub Condemn; Banner gives +4 to Mote and nothing to Scout. `test_abilities_greed.gd`: Ember prompts with two hand cards and auto-chooses with one, fizzles with none; Flare Condemns itself and still Scores; Courier and Bounty draw for the right seat; Jackpot Discards every hand card, each a Batch. `test_abilities_ramp.gd`: Whisper +1 for the match survives the Pile and a Dredger shuffle; Sapling ×1.25 → ×1.50 → … caps at ×2.00; Rain grows every hand card privately; Dynamo adds +1 on the Turn it fires only; Tinker and Layaway reduce for the match with floor 0; Colossus costs 7 on Turn 7 and 12 on Turn 6; Idler fires on a Pass and not on a one-card Commit; Lantern's free first ends after one Commit or at the next turn end; Graft multiplies the right card's Mult ×1.2 to the cap and fizzles on a card with no Mult | implementer-engine |
| 7 | Crew A (P4, P13; R18, R62): `CrewAbilities` with Tallyman, Void, Engineer, Navigator, Captain and Dredger; `void_grants`, the fifth-Score Mult, the Budget bonus, the second-scorer and leftmost grants, the Pile shuffle with the Q11 resumed draw | engine | 5 | `test_crew_abilities.gd`: the seat's 5th and 10th Scoring cards get ×2 for that Score only, a Squelched card does not count, a stub twice counts twice; Void's grant gives the next Scoring card Power +10, Add +0.5 and Mult ×1.25 (Bonus value 18750) and ends after it, two empty draws stack; Engineer's Budget is turn + 1 from Turn 3 and turn on Turns 1 and 2; Navigator's second Scoring card gets +2 Memory after its Score; Captain's slot-0 card gets +1 Memory per Score; Dredger shuffles the Pile in with the stream, `PILE_SHUFFLED_IN` is public, the resumed draw succeeds once and no second On empty draw wakes; Void alone on an empty Deck draws nothing; Void and Dredger together both fire in either slot order and the draw succeeds | implementer-engine |
| 8 | Random bot v2, sweep and golden (P16; R70, R85, R86): `RandomBot` answers every v2 prompt (an exact set, an any-size set, a single choice, an optional prompt with decline); `test_sweep.gd` under `random` over `greed/greed`, `greed/ramp`, `ramp/greed`, `ramp/ramp` with the P15 leak scan, coverage counters reset for the random bot's play (prompts, discard-downs, empty draws, Pile shuffles, looked-at cards), no weights or stamp line; `GOLDEN` empty for the orchestrator's pin at T11; `main.gd` smoke line `Engine smoke: seed=1 decks=… bot=random …` | engine | 6, 7 | `test_random_bot.gd`: a discard-down answer has exactly `exact` cards from the options; an optional prompt is sometimes declined over 50 seeds; 50 seeds over the four pairings end with no rejected action. `test_full_match.gd`: seed 1 replays; the golden case skips while `GOLDEN` is empty | implementer-engine |
| 9 | Board A (P17; R76–R83): `BoardCard` faces with Power and "×1.25"/"+0.50", badge words from `statuses`; `ScoreChips.total_text` and the tally on `CARD_SCORED.total`, the HUD Score on `WALK_ENDED`/`TURN_ENDED`; HUD Energy `n / N`, two Pile counts, the Pile strip on a count tap or a Pile-zone prompt; `PromptHost` Confirm enabled only at `exact` with the "Discard N" banner and Commit disabled; `BoardSteps` for the v7 events and the new step kinds (`EXIT` to pile / to hand / flip, `STATUS`, `EMPTY_DRAW`, `SHUFFLE_IN`, `ENERGY_GRANT`, `LOOK`, `PILE_SHOW/HIDE`), `DESTROY`, `CLEAR_DESTROYED`, `BURN`, `RECOVER` removed; `exhausted` as a note on the pulsed card; `main.gd` and `MatchDriver` without the level | board, ui | 1 (the plan's event and view tables); re-run against 8 | `test_board_steps.gd`: `CARD_SCORED` yields a `PULSE` with `total`; `EXIT_RESOLVED to pile` yields `EXIT` to the Owner's Pile, `to hand` a return, `to face_down` a flip; `STATUS_SET` yields a `STATUS` step with the word; `DRAW_EMPTY` and `PILE_SHUFFLED_IN` yield their steps; a `PROMPT_OPENED` with `exact 2` carries it. `test_score_chips.gd`: 43750 reads "4.38", 160000 reads "16", -15000 reads "-1.50". `test_prompt_rules.gd`: a prompt with `exact 2` enables Confirm at two selected and not at one or three; `test_board_card_*`: a face with `add 50` reads "+0.50", badges stack two words. By node query: a Condemned card flies to the Pile at turn end; the strip shows the opponent's Pile face up | implementer |
| 10 | Review of T01–T09 against the spec and the Constitution Check, with attention to determinism (no float in `engine/`, every random draw from the stream, the queue and prompt in `to_dict`), hidden information (`looked`, `deck_top`, private events, the leak scan), the drain points (exactly D1–D12), the budget count (every pop counts, retriggers count, the reset per pulse), the exit pass order and the Ongoing read once, and that `scripts/bot/` and the `Makefile` are untouched | all | 1–9 | Ranked findings; blockers fixed before T11 (commits `dc-13: T10 review fixes`) | reviewer |
| 11 | Verification A (below) | all | 1–10 | All boxes checked | orchestrator |

**Waves (A).** W1: T01 and T09 (from the contract) in parallel worktrees. W2: T02. W3: T03.
W4: T04. W5: T05. W6: T06 and T07 in parallel (separate files on T05's hooks). W7: T08, and
T09 re-run against T08's engine. W8: T10. W9: T11.

## Milestone B: the other four strategies, Crew and the guides (DC-14)

| # | Task | Area | Depends on | Acceptance check | Who |
|---|---|---|---|---|---|
| 12 | Combo and Disruption abilities (`abilities_combo_disruption.gd` on `Abilities`' dispatch): Wick, Refrain, Swell, Reprieve, Scrap, Twin (create, P6), Reprise (twice), Encore (retrigger), Reverb, Finale; Hush, Muzzle, Litter (Dross created in the opponent's hand with its Walk-end Ongoing), Saboteur (Controller change, Owner kept), Hex (chosen card kept), Jam, Stasis, Gag, Quorum (both seats prompt), Eclipse; `CARD_CREATED`; the 20 cards in `cards.json` | engine | 11 | `test_abilities_combo.gd` and `test_abilities_disruption.gd`: one case per card text and one per Flags note of [[rules/cards-v2]], including the canon's scenario 4 (Encore and Scrap) and 5 (the budget) with real cards; Dross multiplies the holder's total at Walk end before rounding, once per Dross; Saboteur Scores for the opposing seat and goes to its Owner's Pile at Round end; Quorum prompts both seats in order | implementer-engine |
| 13 | Graveyard and Control abilities (`abilities_graveyard_control.gd`): Fuse, Tithe (`next_turn_grants`, cap 3), Reliquary, Boneyard, Wraith (instead, read once in the pass), Glutton, Revive (`CARD_PLACED` from a Pile), Exhume, Immolator, Reset; Eddy, Pin, Shepherd, Skip (the reveal-stage hook), Fence (instead of the wrap), Herald, Level, Shake (C28), Tempest, Cull (both seats); the 20 cards in `cards.json` | engine | 11 | `test_abilities_graveyard.gd` and `test_abilities_control.gd`: one case per card text and Flags note; Wraith Condemned still turns the others' Condemned into Fade; Veil (T14) beats Wraith; Fence Condemns a card that would wrap and wakes no On moved; Shake's chosen Anchored card stays and displaced cards wake On moved as one Batch; Skip's move happens after D7 and its On moved drains in D8; Revive's placed card is reached this Walk; Level sets a row to Saboteur's -3 | implementer-engine |
| 14 | Crew B, decks and data: Shade (`at_turn_end_after`, up to three random revealed), Veil (`at_turn_end_before`, Fleeting instead of Condemned), Quartermaster (Hand size set 7), Salvager (on_commit, optional Discard then draw); `decks.json` with `combo`, `disruption`, `graveyard`, `control` per [[rules/test-decks]]; the sweep over the fifteen distinct pairings of six decks (seeded); `GOLDEN` emptied for the re-pin | engine | 12, 13 | `test_crew_abilities.gd` (B): Shade prompts after the exit pass over up to three random revealed cards and skips with none; Veil's choice resolves as Fleeting in the same pass; Quartermaster with Pantry gives 9; Salvager prompts once per own Commit, a decline changes nothing, the Discard wakes On discard before the discard-down. `test_decks.gd`: six decks, each 40 with the canon's Cost sums (144, 144, 144, 156) and Crew; `test_card_db.gd`: 90 cards, ten per tag and 30 evergreen | implementer-engine |
| 15 | Board B: Dross and created cards in the fan, the Walk-end multiply shown in the tally, the `LOOK` mark on a looked-at opposing card, both-seat prompts (Quorum, Cull) in turn, a Pile-zone prompt choosing from the strip (Revive, Exhume), `CARD_PLACED` and `CARD_CREATED` steps, badges for Muted, Squelched, Silenced driven by real cards | board, ui | 11 (contract from T12/T13's events); re-run against 14 | `test_board_steps.gd`: `CARD_CREATED` into the viewer's hand yields a `DRAW`-like step with the face, into the opponent's a count; `CARD_PLACED` yields a placement; a Pile-zone `PROMPT_OPENED` opens the strip. By node query: Eclipse's target shows "Silenced"; a Quorum prompt for the human seat opens before the bot's answer is shown | implementer |
| 16 | The guides: rewrite [[systems/game-loop]] and [[systems/cards-crew-decks]] to describe rules version 7 as built (the as-built counterparts the canon notes name), set the seven canon notes' `status` from `seedling` to `built` with a first-paragraph sentence saying the rules are built since DC-14, add the cycles-row pointer; leave the uncommitted edits in the main checkout alone (the orchestrator reconciles them with Ben before merging) | vault | 14 | The two guides mention no retired word (glossary section 8) outside a "changed from v6" table; `obsidian-cli vault=docs unresolved` and `orphans` report nothing new; Ben has read both | implementer |
| 17 | Review of T12–T16 against the spec, with attention to created cards (Owner, ids, the leak scan), Controller changes, the "instead" effects, both-seat prompts, the hook, and the guides' vocabulary | all | 12–16 | Ranked findings; blockers fixed before T18 | reviewer |
| 18 | Verification B (below) | all | 12–17 | All boxes checked | orchestrator |

**Waves (B).** W1: T12, T13 and T15 (from the contract) in parallel worktrees. W2: T14, and
T15 re-run. W3: T16. W4: T17. W5: T18. Milestone B runs as its own cycle on
`cycle-9b-rules-v2`, cut from `master` after A merges.

## Verification task A (11)

Owned by the orchestrator, on `cycle-9-rules-v2`, editor opened on the cycle worktree.
Three screenshots.

- [ ] `make check` exits 0; gdUnit under 30 s (cycle 7 C15); record the case count and the
      time in the cycles row. A format-4 log fails replay (`test_action_log.gd`).
- [ ] The data diff: a script-free read of `cards.json` against the three canon tables shows
      every Cost, Power, Bonus, tag and text equal for the 50 cards, six Crew and two decks
      (spec R60–R62); any mismatch is fixed in the data, never in the canon.
- [ ] `grep -rl "preview\|PreviewPolicy\|BotWeights\|BotStamp" godot/engine godot/board
      godot/main.gd godot/tests godot/tools` is empty; `ls godot/engine/bot` holds the three
      random-bot files; `git diff --stat master -- scripts Makefile` is empty (R71–R74).
- [ ] Pin the seed-1 golden under `random` in `GOLDEN` (`test_full_match.gd`): the smoke line,
      `Board: match ended …` and the `test_match_driver` pin agree across a headless
      `--fixed-fps 60 --autoplay` run and an editor run; record the line in
      [[planning/cycles]].
- [ ] `make sweep` under `random`: every match ends, every log replays, the leak scan is clean
      (Piles public, hands and looked-at cards private), the four pairings drawn; record the
      longest match, the longest Walk, prompts, discard-downs, empty draws and Pile shuffles.
      No `make bot-eval`, no re-stamp (R75).
- [ ] **Faces and the total.** On a seed where a Mult card Scores on a fractional total: the
      chip and tally read two decimals (for example "4.38"), the face reads "×1.25", the HUD
      shows the whole-number Score at Walk end. **Screenshot 1:**
      `godot/reports/DC-13/walking-total-face.png`.
- [ ] **Discard-down.** With the human seat holding more than its Hand size after a Commit:
      the multi-select opens over the hand with "Discard N", Confirm enables only at exactly
      N selected, Commit is disabled, the chosen cards fly to the Pile and the Pile count
      rises. **Screenshot 2:** `godot/reports/DC-13/discard-down.png`.
- [ ] **Exit and Pile.** Flare Scores, then at turn end flies to its Owner's Pile; a tap on
      the Pile count shows the strip face up, the opponent's Pile too. **Screenshot 3:**
      `godot/reports/DC-13/pile-strip.png`.
- [ ] Engine scan on a seed: Dredger's shuffle (`PILE_SHUFFLED_IN`) and the resumed draw, or
      Void's grant on the next Score, appear in the log (whichever the seeds reach; the other
      is proven by `test_crew_abilities.gd`).
- [ ] No GDScript warning in the editor run; `obsidian-cli vault=docs unresolved` and
      `orphans` report nothing new; the DC-13 row in [[planning/cycles]] records the gate,
      golden, sweep and screenshots and says the bot rerun provision is suspended; one closing
      line appended to [[planning/bot-ladder]] (R75).

## Verification task B (18)

Owned by the orchestrator, on `cycle-9b-rules-v2`. Two screenshots.

- [ ] `make check` exits 0 with gdUnit under 30 s; `test_card_db.gd` reads 90 cards; the
      golden re-pinned in `GOLDEN` under six seeded decks; `make sweep` clean over the fifteen
      pairings, the leak scan covering created cards.
- [ ] **Silenced.** On a seed where Eclipse resolves against the human seat: the card shows
      "Silenced", Scores nothing and fires nothing; next Turn it is clear.
      **Screenshot 4:** `godot/reports/DC-14/silenced-badge.png`.
- [ ] **Dross.** Litter puts three Dross in the human seat's fan; at Walk end the tally
      shows the ×0.75 multiplies before the rounded Score. **Screenshot 5:**
      `godot/reports/DC-14/dross-in-hand.png`.
- [ ] Both-seat prompt (Quorum or Cull) answered by the human seat and the bot in order; a
      Revive choice made from the Pile strip.
- [ ] The two guides describe rules 7, the canon notes say built, Ben has read both guides;
      the uncommitted system-note edits in the main checkout reconciled with Ben before the
      `master` merge.
- [ ] `obsidian-cli vault=docs unresolved` and `orphans` report nothing new; the DC-14 row
      in [[planning/cycles]].

## Linear (exercised 2026-11-06)

- Project: [Cycle 9 — rules v2 in the engine](https://linear.app/night-science-llc/project/cycle-9-rules-v2-in-the-engine-60e0297b48b8) (P-NSC-11), state Planned; label `spec/cycle-9-rules-v2`
- Milestones are created at `/cycle plan`: A `DC-13 rules-v2` (T01–T11), B `DC-14 rules-v2-content` (T12–T18)
- Every issue is in Todo with `blockedBy` from the Depends column (T09 is blocked by T01 only; its wave-7 re-run against T08 is a dispatch note, not a blocker)

| Task | Issue |
|---|---|
| T01 | NSC-145 |
| T02 | NSC-146 |
| T03 | NSC-147 |
| T04 | NSC-148 |
| T05 | NSC-149 |
| T06 | NSC-150 |
| T07 | NSC-151 |
| T08 | NSC-152 |
| T09 | NSC-153 |
| T10 | NSC-154 |
| T11 | NSC-155 |
| T12 | NSC-156 |
| T13 | NSC-157 |
| T14 | NSC-158 |
| T15 | NSC-159 |
| T16 | NSC-160 |
| T17 | NSC-161 |
| T18 | NSC-162 |

## Commit plan

Milestone A is one changeset on `cycle-9-rules-v2` (`CLAUDE.md`, Git;
[[decisions/0002-one-branch-per-cycle]]), cut from `master` 92e5dc4 at `/spec`. It carries
the spec (`spec: cycle-9-rules-v2`), the Linear write-back (`exercise: cycle-9-rules-v2`),
one commit per task (`dc-13: T<nn> <task title>`), review fixes and the verification outcome
including the golden pin, each message ending with the Co-Authored-By line the session
provides; `/cycle test` merges it into `master` with `git merge --no-ff`. Milestone B is a
second cycle with no spec of its own: it cuts `cycle-9b-rules-v2` from `master` at its
`/cycle plan`, carries T12–T18 as `dc-14: T<nn> …` and merges at its `/cycle test`. Nothing
is committed directly on `master`. Never push without Ben.
