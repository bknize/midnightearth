# Interview Batteries

Ask in rounds of 2 to 4 numbered plain-text questions, each with lettered options and
the recommendation listed first as (a). Add a cost or effort note (XS, S, M, L, or an
extra task) wherever options differ. Never use the AskUserQuestion widget. Accept
answers like `1a 2a 3b`. Adapt the batteries to the change type, and stop when answers
stop changing the design. Anything unresolved becomes a `[NEEDS CLARIFICATION]` marker
in the spec.

## Universal (every change)

- **Intent:** In one sentence, what should exist after this that does not now?
- **Non-goals:** What is explicitly out of scope for this cycle?
- **Actors:** Who or what triggers this: the player, the bot, the engine, an agent role, a script?
- **Done:** How will we know it works? What is the observable acceptance check (a `make check` test, a screenshot, a log line)?
- **Blast radius:** Which existing scenes, engine modules, tests or notes could this affect?
- **Reversibility:** Is this a set of small commits? What is the rollback?
- **Decisions in force:** Does this touch D1 to D8? If it contradicts one, that is a planning change, not a spec detail.

## Engine rule

- What is the rule in one sentence, and which phase or step of a turn does it act in?
- What state does it read and what state does it write? Is any of it new engine state?
- What action(s) trigger it, and what is the action's shape in the log?
- Which random outcomes are involved, and are they all drawn from the seeded RNG?
- What are the illegal cases (wrong player, wrong phase, missing card, empty zone) and what must the engine do with each?
- How does it interact with existing rules (ordering, tie-breaks, simultaneity)?
- What does a replay of the action log have to reproduce, and which gdUnit4 cases prove it?
- Does the bot need to know about it?

## Scene/interaction

- Which scene, and where in the match flow does the player meet it?
- What does the player see before, during and after (cards, zones, text, animation)?
- What input drives it: mouse, touch, both? Is there any keyboard path the orchestrator must drive programmatically?
- Which Card3D pieces are reused (layout, tween, drag-drop) and what is built in-house?
- Does it need a shader or foil effect, and is it Compatibility-clean (no `SCREEN_TEXTURE`, mediump-safe)?
- What is the feedback for an illegal move?
- What does the screenshot for this feature need to show to count as proof?
- Desktop only this cycle, or is this the milestone that also builds for iOS?

## Shader/cards (when visuals are the change)

- Which card face or layer, and what is the reference look?
- Which uniforms are exposed, and who drives them (scene code, tween, engine state)?
- What is the fallback if the effect is unavailable on the Compatibility renderer?
- Is any art generated, and if so through the Replicate MCP or Recraft, with what budget?

## Tooling change (script, hook, agent, skill, MCP)

- Which script or file, and what is its exit-code contract?
- Which role consumes it (orchestrator, implementer, reviewer, Ben)?
- What happens when a required tool is missing?
- Does it touch `.env`, `.mcp.json` or anything secret? (Placeholders only.)
- How is it proven: a planted failure, a fresh clone, or a listing in the skills menu?

## Vault change (note type, convention, MOC)

- Which `type` does this touch, and does it need a new one?
- What frontmatter fields are required versus optional beyond P5?
- Which MOC(s) should link to it?
- Does it change a rule in `CLAUDE.md`? (If yes, that is an ADR; record it.)
- Is it enforced by a script, or is it a human convention?
