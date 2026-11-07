class_name VerbHandler
extends RefCounted
## An extra table of verbs a match may carry beside Abilities and CrewAbilities (DC-13 T05):
## the trigger queue asks MatchCards.verb_handler() first, and a handler that handles() a
## verb prepares and resolves it in their place. The engine ships none; the test fixtures
## install one for the stub verbs no milestone A card exercises (tests/fixtures/
## stub_abilities.gd). Pure like the rest of the engine: no node, no clock, every random draw
## from TriggerContext.rng.
##
## The protocol is the queue's (TriggerQueue): prepare(ctx) runs when the trigger comes up
## and either fizzles it (ctx.fizzle), asks a prompt (ctx.choose with two or more targets,
## or an optional one), or leaves it to resolve; resolve(ctx) applies the effect, reading
## ctx.indices for a chosen target and every amount now (Q5), and wakes what it causes
## through ctx.wake (Q1: the Batch is appended after resolve returns).


## Whether this handler takes the verb named `_verb`. The base takes none.
func handles(_verb: String) -> bool:
	return false


## The trigger came up (see the class comment). The base leaves it to resolve.
func prepare(_ctx: TriggerContext) -> void:
	pass


## The trigger resolves (see the class comment). The base does nothing.
func resolve(_ctx: TriggerContext) -> void:
	pass
