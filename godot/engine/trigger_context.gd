class_name TriggerContext
extends RefCounted
## One resolution of one queued trigger (DC-13 T05; cycle 9 plan P11, P12): what a verb's
## prepare() and resolve() read and write. TriggerQueue builds it from a queue entry each
## time the trigger comes up, and again from the same entry when a prompt it opened is
## answered (a paused drain resumes at the same entry), so a verb keeps nothing of its own
## between the two calls except `data`, which the queue stores with the paused entry.
##
## Inputs: the match (`state`, `cards`, `rng`, `sink`), the watcher (`seat` its Controller,
## `card` or -1 for a Crew, `crew_slot` or -1 for a card, `ability` or `crew` its
## definition, `verb`), what woke it (`moment`, `subject` the card whose event it was or -1,
## `subject_seat` that card's seat or the seat of a seat event, -1 for none, `context` the
## waker's extra data), `resolution` (this one's count in the pulse or drain, 1 to
## MatchRules.TRIGGER_BUDGET), `step` (the drain point, "D1".."D12") and `extra` (true for
## a retrigger's extra resolution, Q6). After a prompt: `answered`, `declined`, `zone` and
## `indices` (positions in that zone, Choice). Amounts are read when the verb runs (Q5).
##
## Outputs: fizzle(reason) in prepare(); choose() to target (Q9: no option fizzles
## `no_target`, one is chosen at once unless the prompt is optional or a Crew's, two or
## more open a prompt); wake() and its two shorthands queue the Batches the effect causes,
## appended after it has finished (Q1); emit() sends an event.

const ZONE_ROW: String = "row"
const ZONE_HAND: String = "hand"
const KIND_CARD: String = "card"
const KIND_CREW: String = "crew"
const KEY_TEXT: String = "text"

var state: MatchState = null
var cards: MatchCards = null
var rng: MatchRng = null
var sink: Callable = Callable()
## The queue entry this resolution came from (plain data, TriggerQueue).
var entry: Dictionary = {}
var seat: int = -1
var card: int = -1
var crew_slot: int = -1
## The card's ability (null for a Crew).
var ability: CardAbility = null
## The Crew (null for a card).
var crew: CrewDef = null
var verb: String = ""
var moment: String = ""
var subject: int = -1
var subject_seat: int = -1
var context: Dictionary = {}
var resolution: int = 0
var step: String = ""
var extra: bool = false
## Set by the queue when a prompt this trigger opened has been answered (or by choose()
## when it chose the one target itself).
var answered: bool = false
var declined: bool = false
var zone: int = Choice.NO_ZONE
var indices: Array[int] = []
## The seat that chose (`indices` are positions for this seat): the prompted seat after an
## answer, the Controller for an automatic choice.
var chooser: int = -1
## Whatever the verb keeps between prepare() and resolve() across a prompt: plain data,
## serialized with the paused entry.
var data: Dictionary = {}
## Set by fizzle(): the TRIGGER_FIZZLED reason ("" when the trigger acts).
var fizzle_reason: String = ""
## Set by choose() when a prompt must open (the P12 keys but `resume` and `step`, which the
## queue fills).
var prompt: Dictionary = {}
## The Batches the effect wakes, in order: {moment, subjects, seat, context}.
var woken: Array[Dictionary] = []


## Whether the watcher is a Crew (a Crew entry has a slot, a card entry -1).
func is_crew() -> bool:
	return crew_slot >= 0


## The trigger does nothing, TRIGGER_FIZZLED with `reason` (Abilities.REASON_*).
func fizzle(reason: String) -> void:
	fizzle_reason = reason


## Targets the effect over `options` (positions in `p_zone` for `by_seat`, the Controller
## when -1), per Q9: none fizzles `no_target` (false); one is chosen at once, `answered`
## with that position (true), unless `optional` or the watcher is a Crew; two or more open a
## prompt (false). A multi-select (`multi`) takes a set of `exact` positions (Choice.ANY_SIZE
## for any size of at least `min_count` and, when `max_count` is 0 or more, at most
## `max_count`: "up to N", C15 2a); an optional count (`min_count` 0) always prompts. `text`
## overrides the prompt's banner (the source's rules text when empty). Call it from
## prepare(); after an answer `indices` holds the choice.
func choose(
	p_zone: int,
	options: Array[int],
	multi: bool = false,
	exact: int = 1,
	min_count: int = 1,
	optional: bool = false,
	by_seat: int = -1,
	text: String = "",
	max_count: int = Choice.NO_MAX
) -> bool:
	if options.is_empty():
		fizzle(Abilities.REASON_NO_TARGET)
		return false
	var asks: bool = optional or is_crew() or min_count == 0 or options.size() > 1
	if multi and exact >= 0 and exact >= options.size() and not optional and min_count > 0:
		asks = false  # Every option must be taken: nothing to ask.
	if not asks:
		answered = true
		chooser = seat if by_seat < 0 else by_seat
		zone = p_zone
		indices.assign(options if multi else options.slice(0, 1))
		return true
	var plain_options: Array = MatchState.plain(options)
	prompt = {
		Abilities.KEY_SEAT: seat if by_seat < 0 else by_seat,
		Abilities.KEY_CARD: card,
		Choice.KEY_CREW: crew.id if crew != null else "",
		Abilities.KEY_VERB: verb,
		Choice.KEY_ZONE: Choice.zone_name(p_zone),
		Choice.KEY_OPTIONS: plain_options,
		Choice.KEY_MULTI: multi,
		Choice.KEY_EXACT: exact if multi else 1,
		Choice.KEY_MIN: min_count if multi else 1,
		Choice.KEY_OPTIONAL: optional or is_crew(),
	}
	if multi and max_count >= 0:
		prompt[Choice.KEY_MAX] = max_count  # "Up to N" (C15 2a): absent means no bound.
	if text != "":
		prompt[KEY_TEXT] = text
	return false


## The card the answer names at `at` of `indices` (Choice.resolve for the prompted seat), or
## -1 when there is none.
func chosen_card(at: int = 0) -> int:
	if at < 0 or at >= indices.size():
		return -1
	var by: int = seat if chooser < 0 else chooser
	return Choice.resolve(state, by, zone, indices[at])


## Every card the answer names, in `indices` order (chosen_card() each), read before any
## of them moves.
func chosen_cards() -> Array[int]:
	var out: Array[int] = []
	for at: int in range(indices.size()):
		out.append(chosen_card(at))
	return out


## Queues the Batch of `p_moment` for `subjects` (the cards whose event it is; empty for a
## seat event of `event_seat`, or for a seatless one with -1), appended after the effect.
func wake(
	p_moment: String, subjects: Array[int], event_seat: int = -1, p_context: Dictionary = {}
) -> void:
	woken.append(
		{
			"moment": p_moment,
			"subjects": MatchState.plain(subjects),
			"seat": event_seat,
			"context": p_context.duplicate(true),
		}
	)


## Queues the On moved Batch of the cards a Movement call returned (one Batch, R40).
func wake_moved(moved: Array[int]) -> void:
	if not moved.is_empty():
		wake(CardAbility.MOMENT_MOVED, moved)


## Queues the On squelch Batch of `p_card` when Statuses.apply() says it wakes it.
func wake_squelch(p_card: int, applied: Statuses.Applied) -> void:
	if applied != null and applied.wakes_squelch:
		var subjects: Array[int] = [p_card]
		wake(CardAbility.MOMENT_SQUELCH, subjects)


## An effect's draw for `by_seat` (R18, Q11): the top card of its Deck to its hand
## (CARD_DRAWN, private), returned; with an empty Deck nothing is drawn (-1): DRAW_EMPTY,
## then its On empty draw Batch is queued like any woken Batch, and right after that Batch's
## last trigger the denied draw is made once if the Deck is no longer empty
## (TriggerQueue.KEY_THEN_DRAW). Never drains: the queue in progress does.
func draw(by_seat: int) -> int:
	var piles: MatchState.SeatPiles = state.seats[by_seat]
	if piles.deck.is_empty():
		emit(MatchEvent.Kind.DRAW_EMPTY, {"seat": by_seat})
		var none: Array[int] = []
		wake(CardAbility.MOMENT_EMPTY_DRAW, none, by_seat, {TriggerQueue.KEY_THEN_DRAW: by_seat})
		return -1
	if TurnFlow.resumed_draw(state, sink, by_seat):
		pass  # The Deck is not empty: the top card is now the last of the hand.
	var top: int = piles.hand.back()
	return top


## Sends one event to the sink (nothing when it is not valid).
func emit(kind: int, payload: Dictionary, owner: int = MatchEvent.PUBLIC) -> void:
	if sink.is_valid():
		sink.call(kind, payload, owner)
