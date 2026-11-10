---
type: moc
tags: [moc, systems]
status: growing
related: ["[[home]]", "[[systems/game-loop]]", "[[systems/cards-crew-decks]]", "[[systems/bot-training]]"]
created: 2026-11-02
updated: 2026-11-05
uid: 9f6cc5ad-1669-465a-8323-bfcc7f791323
supersedes:
---

# Systems

Plain-language guides to how the game works today, written from the code. The specs in
[[specs/specs-moc|Specs]] record what each cycle set out to build and why; these notes
describe the result, and link back to the specs for edge cases.

- [[systems/game-loop|Game loop, events and triggers]]: how a match runs, from a commit
  through the reveal and score walk to the end of a round; what each event means and who
  sees it; when card effects and Crew fire; replay and hidden information.
- [[systems/cards-crew-decks|Cards, Crew and deck lists]]: card anatomy and growth, the
  effect model, the four decks card by card, the eight Crew, and how to add content.
- [[systems/bot-training|Bots and training]]: the bots, how strength is measured, the
  stamp and rerun rule, the overnight training loop, calibration, and how to run it.

The original rules sketch is still in [[planning/phase-3-game-loop]].
