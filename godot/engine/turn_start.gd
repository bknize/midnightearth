class_name TurnStart
extends RefCounted
## The turn start's Crew and its pause (cycle 8 R45, R54, plan P11). After the turn's draws
## and before any commit, each seat's TURN_START Crew fire in first-committer order: the
## first seat's slots 0..2, then the other seat's. MatchState.turn_start_at is the cursor
## over those six positions, so the pause survives in the state (to_dict, duplicate) and a
## replay reaches it the same way.
##
## A firing that needs a choice pauses the turn start on a Crew prompt (P9): the prompt the
## firing returned, stamped with `seat` (the Crew's), `card` -1, `verb` (the CrewDef.Verb),
## `optional` (the Crew's flag), `resume` Choice.RESUME_TURN_START and `crew` (its id), is
## stored in MatchState.prompt and announced by CHOICE_REQUESTED (EffectResolver.requested,
## with the Crew's verb name and rules text; public). The phase becomes AWAIT_CHOICE with
## the walk inactive, so the engine accepts only the prompted seat's choice or decline (or a
## concede) and rejects every commit. Once the answer applies, run() goes on from the Crew
## after the one that prompted; when every Crew has fired the cursor is DONE and the phase
## AWAIT_FIRST, the first committer awaited as usual.
##
## The firing is `fire`, a Callable (state: MatchState, cards: MatchCards, rng: MatchRng,
## seat: int, slot: int) -> EffectResolver.Outcome: the Outcome's events in order, and the
## prompt the Crew needs ({zone, options}, the rest stamped here; no CHOICE_REQUESTED of
## its own), or no prompt when it resolved. The Crew abilities land with DC-11 T10
## (CrewEffects); until then `fire` is unset, so no Crew fires, and the tests set a stub.
## Pure: no nodes, no clock; the only randomness is the engine stream handed to `fire`.

## MatchState.turn_start_at outside the turn start.
const DONE: int = -1

## The Crew firing (see the class comment); an invalid Callable fires nothing.
var fire: Callable = Callable()


## Starts the turn start's Crew at the first seat's slot 0 (MatchEngine._begin_turn, after
## the draws), as run() does.
func begin(state: MatchState, cards: MatchCards, rng: MatchRng, out: Array[MatchEvent]) -> void:
	state.turn_start_at = 0
	run(state, cards, rng, out)


## Runs the turn start's Crew from MatchState.turn_start_at to the end or to a Crew prompt,
## appending their events to `out`. On a prompt: the prompt is open, the cursor is past
## that Crew and the phase is AWAIT_CHOICE. Otherwise: the cursor is DONE and the phase
## AWAIT_FIRST.
func run(state: MatchState, cards: MatchCards, rng: MatchRng, out: Array[MatchEvent]) -> void:
	var total: int = 2 * MatchRules.CREW_SIZE
	while state.turn_start_at >= 0 and state.turn_start_at < total:
		var at: int = state.turn_start_at
		state.turn_start_at += 1
		var seat: int = state.first_seat if at < MatchRules.CREW_SIZE else 1 - state.first_seat
		var slot: int = at % MatchRules.CREW_SIZE
		var defs: Array[CrewDef] = cards.crew_for(seat)
		if not fire.is_valid() or slot >= defs.size():
			continue
		var def: CrewDef = defs[slot]
		if def.trigger != CrewDef.Trigger.TURN_START:
			continue
		var outcome: EffectResolver.Outcome = fire.call(state, cards, rng, seat, slot)
		if outcome == null:
			continue
		out.append_array(outcome.events)
		if outcome.needs_prompt():
			_open(state, seat, def, outcome.prompt, out)
			state.phase = MatchState.Phase.AWAIT_CHOICE
			return
	state.turn_start_at = DONE
	state.phase = MatchState.Phase.AWAIT_FIRST


## Whether `state` is paused on a Crew prompt the turn start opened.
static func is_paused(state: MatchState) -> bool:
	if state.prompt.is_empty():
		return false
	return Choice.resume_of(state.prompt) == Choice.RESUME_TURN_START


## Opens the Crew prompt of `def` (seat `seat`) from the firing's `found` (see the class
## comment) and announces it on `out`.
static func _open(
	state: MatchState, seat: int, def: CrewDef, found: Dictionary, out: Array[MatchEvent]
) -> void:
	var prompt: Dictionary = found.duplicate(true)
	prompt[EffectResolver.KEY_SEAT] = seat
	prompt[EffectResolver.KEY_CARD] = -1
	prompt[EffectResolver.KEY_VERB] = def.verb
	prompt[Choice.KEY_MULTI] = Choice.is_multi_prompt(found)
	prompt[Choice.KEY_OPTIONAL] = def.optional
	prompt[Choice.KEY_RESUME] = Choice.RESUME_TURN_START
	prompt[Choice.KEY_CREW] = def.id
	state.prompt = prompt
	var verb: String = CrewDef.VERB_NAMES[def.verb]
	var requested: Dictionary = EffectResolver.requested(prompt, verb, def.text)
	out.append(MatchEvent.new(MatchEvent.Kind.CHOICE_REQUESTED, requested))
