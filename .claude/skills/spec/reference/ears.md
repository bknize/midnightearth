# EARS: Easy Approach to Requirements Syntax

Write every requirement and constraint as one of these five patterns. Keywords are
always in the same order (While, When, Where, If/Then, the system shall). This removes
the ambiguity that makes agents improvise.

## The five patterns

1. **Ubiquitous**: always true, no condition.
   `The <system> shall <response>.`
   > The engine shall derive every random outcome from the match seed.

2. **State-driven (While)**: true during a state.
   `While <precondition>, the <system> shall <response>.`
   > While a card is held over a play zone, the scene shall highlight that zone.

3. **Event-driven (When)**: response to a trigger.
   `When <trigger>, the <system> shall <response>.`
   > When the second committer confirms, the engine shall reveal cards alternating from the first committer's first card.

4. **Optional-feature (Where)**: applies only if a feature is present.
   `Where <feature is included>, the <system> shall <response>.`
   > Where the device reports touch input, the card scene shall start a drag on touch-down instead of on mouse-down.

5. **Unwanted-behaviour (If/Then)**: handling errors and edge cases.
   `If <condition>, then the <system> shall <response>.`
   > If an action targets a card not in the acting player's hand, then the engine shall reject it, leave the state unchanged and shall not append it to the action log.

## Rules

- One requirement per sentence; one behaviour per requirement.
- Name a concrete `<system>` (for example "the engine", "the card scene", "the foil
  shader", "`make check`"), never "it".
- Prefer measurable responses ("within 2 seconds", "exits non-zero and prints the
  `Parse Error` line") over adjectives ("fast", "smooth").
- Combine at most two conditions (for example While + When); split anything more
  complex.
- Number requirements R1, R2, ... so tasks and scenarios can cite them.
- Mark unknowns as `[NEEDS CLARIFICATION: question]` rather than guessing.
- Engine requirements describe observable state and action-log effects, not GDScript
  structure; scene requirements describe what the player sees and can do, not node
  trees.
