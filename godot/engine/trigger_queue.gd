class_name TriggerQueue
extends RefCounted
## The one trigger queue (DC-13 T05; cycle 9 plan P11, P12; spec R45 to R56; canon
## [[rules/resolution]] Q1 to Q9). Its data lives in MatchState.queue, so to_dict() and
## replay carry a drain paused on a prompt; the functions are static and pure over a
## MatchState: no node, no clock, every random draw from the engine stream passed in.
##
## - wake() snapshots the eligible watchers of one event as one Batch (Q2) in Q3 order:
##   cards first (the Turn's first seat's row by slot, then its hand, then the second seat's
##   the same way, then a Discarded subject in its Pile), then Crew (first seat's by slot,
##   then the second's). One entry per (watcher, ability, subject). Brackets (P3): a card
##   on a row must be revealed (zone `row`), a `zone: hand` ability fires from its
##   Controller's hand; `watch` self, other_own, opposing or any relates the watcher to the
##   event's subject card (or to the seat of a seat event: On commit, On empty draw); On
##   start and At turn end have no subject and wake every eligible watcher. A Crew watches
##   its own seat's events (and every seatless one).
## - drain() pops entries oldest Batch first. Whether a card is Muted is read at the pop
##   (Q2): a Muted card's entry is dropped without counting or any event. Every other pop
##   counts one resolution (Q4) and asks the verb (MatchCards.verb_handler() first, then
##   CrewAbilities or Abilities): prepare() fizzles it (TRIGGER_FIZZLED) or it fires
##   (TRIGGER_FIRED {seat, card, crew, moment, verb, resolution}); a prompt then pauses the
##   drain (MatchState.prompt with `resume` and `step`, PROMPT_OPENED, the entry kept in
##   `current`) until answer() resumes it at the same entry; else resolve() applies it. The
##   Batches the effect woke are appended after it (Q1); a retrigger adds its extra
##   resolutions at the front (Q6).
## - The budget (Q4): MatchRules.TRIGGER_BUDGET resolutions per pulse across D7 and D8
##   (`walk.resolutions`, reset by ScoreWalk at each pulse), and per drain outside the Walk
##   (`resolutions`, reset by each drain() at D1 to D6 and D9 to D12). When it is spent,
##   every entry still queued fizzles `exhausted` (one public TRIGGER_FIZZLED each) and the
##   queue empties.
## - Retrigger (Q6): `walk.retrigger_on_reveal[seat]` lists the cards whose "trigger your
##   other On reveals twice" applies this Turn (add_retrigger()); each one other than the
##   card adds one extra resolution of that card's On reveal right after it, never to an
##   extra resolution. Scores twice (Q7) is ScoreWalk's (`walk.scores_twice`).
##
## Events go to `sink` as sink.call(kind, payload, owner); an invalid sink emits nothing.
## API for the verbs (DC-13 T06, T07): TriggerContext and VerbHandler.

const KIND_CARD: String = TriggerContext.KIND_CARD
const KIND_CREW: String = TriggerContext.KIND_CREW
const MOMENT_REVEAL: String = "on_reveal"
const MOMENT_DISCARD: String = "on_discard"
## Moments with no subject and no seat: every eligible watcher wakes.
const SEATLESS_MOMENTS: Array[String] = ["on_start", "at_turn_end_before", "at_turn_end_after"]
## Moments of a seat (On commit, On empty draw): watchers relate to the seat.
const SEAT_MOMENTS: Array[String] = ["on_commit", "on_empty_draw"]
## The Walk's two drains: they share the pulse's budget.
const WALK_STEPS: Array[String] = ["D7", "D8"]
## What an answered prompt resumes, by the drain point it opened at (P12 `resume`).
const RESUME_OF_STEP: Dictionary[String, String] = {
	"D1": Choice.RESUME_TURN_START,
	"D2": Choice.RESUME_TURN_START,
	"D3": Choice.RESUME_COMMIT,
	"D4": Choice.RESUME_COMMIT,
	"D5": Choice.RESUME_COMMIT,
	"D6": Choice.RESUME_COMMIT,
	"D7": Choice.RESUME_WALK,
	"D8": Choice.RESUME_WALK,
	"D9": Choice.RESUME_TURN_END,
	"D10": Choice.RESUME_TURN_END,
	"D11": Choice.RESUME_TURN_END,
	"D12": Choice.RESUME_ROUND_END,
}

## Context key of an On empty draw Batch woken by an effect's draw (TriggerContext.draw):
## the seat whose denied draw is made once right after the Batch's last trigger (Q11).
const KEY_THEN_DRAW: String = "then_draw"

## The queued Batches, oldest first: {id, at (the drain point it was woken in), entries}.
## An entry is {kind, seat, card, crew_slot, ability (index into the card's abilities),
## moment, subject, subject_seat, context, extra, batch}.
var batches: Array[Dictionary] = []
## Resolutions of the drain in progress outside the Walk (the Walk counts in
## `walk.resolutions`).
var resolutions: int = 0
## The drain point of the drain in progress or paused ("D1".."D12"), "" when none ran.
var step: String = ""
## The seat the drain belongs to (the drawing, committing or discarding seat), -1 for none:
## what the step after it resumes for.
var seat: int = -1
## While paused on a prompt: {entry, data, resolution, woken (what the entry woke before a
## second prompt)}; else empty.
var current: Dictionary = {}
## The id the next Batch takes (Batch ids only tell Batches apart).
var next_batch: int = 0


## Whether no entry is queued (a paused entry is not queued).
func is_empty() -> bool:
	return batches.is_empty()


## Whether a drain is paused on a prompt.
func is_paused() -> bool:
	return not current.is_empty()


## The number of queued entries.
func size() -> int:
	var count: int = 0
	for batch: Dictionary in batches:
		var entries: Array = batch["entries"]
		count += entries.size()
	return count


func copy() -> TriggerQueue:
	var out: TriggerQueue = TriggerQueue.new()
	for batch: Dictionary in batches:
		out.batches.append(batch.duplicate(true))
	out.resolutions = resolutions
	out.step = step
	out.seat = seat
	out.current = current.duplicate(true)
	out.next_batch = next_batch
	return out


func to_dict() -> Dictionary:
	var listed: Array = []
	for batch: Dictionary in batches:
		listed.append(batch.duplicate(true))
	return {
		"batches": listed,
		"resolutions": resolutions,
		"step": step,
		"seat": seat,
		"current": current.duplicate(true),
		"next_batch": next_batch,
	}


# --- Waking ---------------------------------------------------------------------------


## Wakes one Batch of `moment` (Q1, Q2): the eligible watchers of the event of `subjects`
## (cards; empty for a seat event of `event_seat` or a seatless one), snapshotted now in Q3
## order, appended to `state.queue`. Returns the Batch, empty (and nothing appended) when
## nothing watches.
static func wake(
	state: MatchState,
	cards: MatchCards,
	moment: String,
	subjects: Array[int],
	event_seat: int = -1,
	context: Dictionary = {}
) -> Dictionary:
	var queue: TriggerQueue = state.queue
	var entries: Array[Dictionary] = watchers(state, cards, moment, subjects, event_seat)
	if entries.is_empty():
		return {}
	var batch_id: int = queue.next_batch
	queue.next_batch += 1
	var listed: Array = []
	for entry: Dictionary in entries:
		entry["context"] = context.duplicate(true)
		entry["batch"] = batch_id
		listed.append(entry)
	var batch: Dictionary = {"id": batch_id, "at": queue.step, "entries": listed}
	var then_draw: int = context.get(KEY_THEN_DRAW, -1)
	if then_draw >= 0:
		batch[KEY_THEN_DRAW] = then_draw
	queue.batches.append(batch)
	return batch


## The entries the event would wake, in Q3 order (see the class comment); nothing is queued.
static func watchers(
	state: MatchState, cards: MatchCards, moment: String, subjects: Array[int], event_seat: int
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if cards == null:
		return out
	var subject_seats: Array[int] = []
	for subject: int in subjects:
		subject_seats.append(state.controller_of(subject))
	var event: Dictionary = {
		"moment": moment, "subjects": subjects, "seats": subject_seats, "seat": event_seat
	}
	var order: Array[int] = [state.first_seat, 1 - state.first_seat]
	for watcher_seat: int in order:
		var piles: MatchState.SeatPiles = state.seats[watcher_seat]
		for card: int in piles.board:
			if piles.is_revealed(card):
				_card_entries(out, cards, event, card, watcher_seat, TriggerContext.ZONE_ROW)
		for card: int in piles.hand:
			_card_entries(out, cards, event, card, watcher_seat, TriggerContext.ZONE_HAND)
	if moment == MOMENT_DISCARD:
		_pile_entries(out, state, cards, event)
	for watcher_seat: int in order:
		_crew_entries(out, cards, event, watcher_seat)
	return out


# --- Draining -------------------------------------------------------------------------


## Drains `state.queue` at the drain point `p_step` for `p_seat` (-1 for none): outside the
## Walk the budget starts again at 0 (a fresh queue, Q1); in the Walk it is the pulse's.
## True when the drain paused on a prompt (MatchState.prompt open); the caller resumes
## through answer().
static func drain(
	state: MatchState,
	cards: MatchCards,
	rng: MatchRng,
	sink: Callable,
	p_step: String,
	p_seat: int = -1
) -> bool:
	var queue: TriggerQueue = state.queue
	queue.step = p_step
	queue.seat = p_seat
	if not WALK_STEPS.has(p_step):
		queue.resolutions = 0
	return _run(state, cards, rng, sink)


## Answers the prompt the drain paused on with positions `indices` of `zone` (validated by
## the engine), or its decline: CHOICE_MADE (private to the prompted seat) or
## CHOICE_DECLINED, then the paused entry resolves (not when declined), its woken Batches
## and retriggers queue, and the drain goes on from the next entry. True when it paused
## again. False, changing nothing, when no drain is paused.
static func answer(
	state: MatchState,
	cards: MatchCards,
	rng: MatchRng,
	sink: Callable,
	zone: int,
	indices: Array[int],
	declined: bool
) -> bool:
	var queue: TriggerQueue = state.queue
	if not queue.is_paused():
		return false
	var prompt: Dictionary = state.prompt
	var events: Array[MatchEvent] = []
	if declined:
		events = Abilities.decline(state)
	else:
		events.append(Abilities.choice_made(state, prompt, zone, indices))
	_forward(events, sink)
	state.prompt = {}
	var held: Dictionary = queue.current
	queue.current = {}
	var entry: Dictionary = held["entry"]
	var number: int = held["resolution"]
	var kept: Dictionary = held["data"]
	var ctx: TriggerContext = _context(state, cards, rng, sink, entry, number)
	ctx.data = kept.duplicate(true)
	var woken: Array = held.get("woken", [])
	ctx.woken.assign(woken)
	ctx.answered = true
	ctx.declined = declined
	ctx.zone = zone
	ctx.indices.assign(indices)
	ctx.chooser = prompt.get(Abilities.KEY_SEAT, ctx.seat)
	if not declined:
		_apply(ctx)
	if _reopens(state, cards, ctx, number):
		return true
	_finish(state, cards, ctx)
	return _run(state, cards, rng, sink)


## The resolutions counted so far in the pulse (in the Walk) or in the drain outside it.
static func spent(state: MatchState) -> int:
	if WALK_STEPS.has(state.queue.step):
		return state.walk.resolutions
	return state.queue.resolutions


## Records that `source`'s retrigger applies to `seat`'s other On reveals this Turn (Q6;
## Encore, `stub_retrigger` in the tests). Stacks by one per call.
static func add_retrigger(state: MatchState, for_seat: int, source: int) -> void:
	var sources: Array = state.walk.retrigger_on_reveal[for_seat]
	sources.append(source)


## The loop of a drain: pops until the queue is empty, the budget is spent (every queued
## entry fizzles `exhausted`) or a prompt pauses it (true).
static func _run(state: MatchState, cards: MatchCards, rng: MatchRng, sink: Callable) -> bool:
	var queue: TriggerQueue = state.queue
	while not queue.batches.is_empty():
		if spent(state) >= MatchRules.TRIGGER_BUDGET:
			_exhaust(state, cards, sink)
			return false
		var entry: Dictionary = _pop(queue)
		if entry.is_empty():
			continue
		# Each pop counts one (P11), a silent Muted one too.
		_count(state)
		var card: int = entry["card"]
		if card >= 0 and not Statuses.fires(state, card):
			# Q2: Muted (or Silenced) when its trigger comes up: no event, no effect, no wakes.
			_then_draw(state, sink, entry)
			continue
		if _resolve(state, cards, rng, sink, entry, spent(state)):
			return true
	return false


## One popped entry, counted as resolution `number`: prepare, then fizzle, or fire and
## either pause on a prompt (true) or resolve.
static func _resolve(
	state: MatchState,
	cards: MatchCards,
	rng: MatchRng,
	sink: Callable,
	entry: Dictionary,
	number: int
) -> bool:
	var ctx: TriggerContext = _context(state, cards, rng, sink, entry, number)
	if ctx.ability == null and ctx.crew == null:
		ctx.fizzle(Abilities.REASON_NO_TARGET)
	else:
		_prepare(ctx)
	if ctx.fizzle_reason != "":
		_fizzled(ctx, ctx.fizzle_reason)
		_finish(state, cards, ctx)
		return false
	_fired(ctx)
	if _reopens(state, cards, ctx, number):
		return true
	_apply(ctx)
	if _reopens(state, cards, ctx, number):
		return true
	_finish(state, cards, ctx)
	return false


## When `ctx` asked a prompt: opens it (MatchState.prompt with `resume` and `step`,
## PROMPT_OPENED with `text`), keeps the entry in `current` and returns true.
static func _reopens(
	state: MatchState, cards: MatchCards, ctx: TriggerContext, number: int
) -> bool:
	if ctx.prompt.is_empty():
		return false
	var queue: TriggerQueue = state.queue
	var prompt: Dictionary = ctx.prompt.duplicate(true)
	var text: String = prompt.get(TriggerContext.KEY_TEXT, "")
	if prompt.erase(TriggerContext.KEY_TEXT):
		pass  # The banner travels in PROMPT_OPENED only.
	prompt[Choice.KEY_RESUME] = RESUME_OF_STEP.get(queue.step, Choice.RESUME_WALK)
	prompt[Choice.KEY_STEP] = queue.step
	state.prompt = prompt
	var woken: Array = []
	for batch: Dictionary in ctx.woken:
		woken.append(batch.duplicate(true))
	queue.current = {
		"entry": ctx.entry.duplicate(true),
		"data": ctx.data.duplicate(true),
		"resolution": number,
		"woken": woken,
	}
	var opened: Dictionary = prompt.duplicate(true)
	opened[TriggerContext.KEY_TEXT] = text if text != "" else Abilities.prompt_text(prompt, cards)
	ctx.emit(MatchEvent.Kind.PROMPT_OPENED, opened)
	return true


## After `ctx` resolved or fizzled: its woken Batches are appended in order (Q1), then a
## retrigger's extra resolutions go to the front of the queue (Q6).
static func _finish(state: MatchState, cards: MatchCards, ctx: TriggerContext) -> void:
	var queue: TriggerQueue = state.queue
	_then_draw(state, ctx.sink, ctx.entry)
	for woken: Dictionary in ctx.woken:
		var subjects: Array[int] = []
		var listed: Array = woken["subjects"]
		subjects.assign(listed)
		var moment: String = woken["moment"]
		var event_seat: int = woken["seat"]
		var context: Dictionary = woken["context"]
		if wake(state, cards, moment, subjects, event_seat, context).is_empty():
			pass  # Nothing watches that event.
	var extra: int = _retriggers(state, ctx)
	if extra <= 0:
		return
	var entries: Array = []
	for _copy: int in range(extra):
		var again: Dictionary = ctx.entry.duplicate(true)
		again["extra"] = true
		entries.append(again)
	var batch_id: int = ctx.entry.get("batch", -1)
	queue.batches.push_front({"id": batch_id, "at": queue.step, "entries": entries})


## Q11 for an effect's draw: after the last trigger of its On empty draw Batch, the seat
## named by the entry's `then_draw` makes the denied draw once if its Deck is no longer
## empty (CARD_DRAWN, private); with the Deck still empty nothing happens.
static func _then_draw(state: MatchState, sink: Callable, entry: Dictionary) -> void:
	var drawer: int = entry.get(KEY_THEN_DRAW, -1)
	if drawer < 0 or drawer >= state.seats.size():
		return
	if TurnFlow.resumed_draw(state, sink, drawer):
		pass  # The refilled Deck gave the denied draw.


## How many extra resolutions the retriggers add after `ctx` (Q6): one per source in its
## seat's `walk.retrigger_on_reveal` other than its own card, for an On reveal of a card
## that is not itself an extra resolution.
static func _retriggers(state: MatchState, ctx: TriggerContext) -> int:
	if ctx.extra or ctx.is_crew() or ctx.moment != MOMENT_REVEAL:
		return 0
	if ctx.seat < 0 or ctx.seat >= state.walk.retrigger_on_reveal.size():
		return 0
	var count: int = 0
	var sources: Array = state.walk.retrigger_on_reveal[ctx.seat]
	for source: Variant in sources:
		var source_card: int = source
		if source_card != ctx.card:
			count += 1
	return count


## The budget is spent: every queued entry fizzles `exhausted`, in queue order (a Muted or
## Silenced one silently drops), and the queue empties (Q4).
static func _exhaust(state: MatchState, cards: MatchCards, sink: Callable) -> void:
	var queue: TriggerQueue = state.queue
	var guard: int = queue.size()
	while not queue.batches.is_empty() and guard >= 0:
		guard -= 1
		var entry: Dictionary = _pop(queue)
		if entry.is_empty():
			continue
		var card: int = entry["card"]
		if card >= 0 and not Statuses.fires(state, card):
			continue  # A Muted (or Silenced) entry stays silent, budget or not (Q2).
		var ctx: TriggerContext = _context(state, cards, null, sink, entry, spent(state))
		_fizzled(ctx, Abilities.REASON_EXHAUSTED)
	queue.batches.clear()


## Takes the oldest entry off the queue (dropping an emptied Batch); {} when none.
static func _pop(queue: TriggerQueue) -> Dictionary:
	while not queue.batches.is_empty():
		var batch: Dictionary = queue.batches[0]
		var entries: Array = batch["entries"]
		if entries.is_empty():
			queue.batches.remove_at(0)
			continue
		var entry: Dictionary = entries.pop_front()
		if entries.is_empty():
			queue.batches.remove_at(0)
			if batch.has(KEY_THEN_DRAW):
				entry[KEY_THEN_DRAW] = batch[KEY_THEN_DRAW]
		return entry
	return {}


## Counts one resolution against the budget of the drain in progress.
static func _count(state: MatchState) -> void:
	if WALK_STEPS.has(state.queue.step):
		state.walk.resolutions += 1
	else:
		state.queue.resolutions += 1


## The context of `entry` as resolution `number`.
static func _context(
	state: MatchState,
	cards: MatchCards,
	rng: MatchRng,
	sink: Callable,
	entry: Dictionary,
	number: int
) -> TriggerContext:
	var ctx: TriggerContext = TriggerContext.new()
	ctx.state = state
	ctx.cards = cards
	ctx.rng = rng
	ctx.sink = sink
	ctx.entry = entry
	ctx.seat = entry["seat"]
	ctx.card = entry["card"]
	ctx.crew_slot = entry["crew_slot"]
	ctx.moment = entry["moment"]
	ctx.subject = entry["subject"]
	ctx.subject_seat = entry["subject_seat"]
	var context: Dictionary = entry.get("context", {})
	ctx.context = context
	ctx.extra = entry.get("extra", false)
	ctx.resolution = number
	ctx.step = state.queue.step
	ctx.chooser = ctx.seat
	if ctx.crew_slot >= 0:
		ctx.crew = cards.crew_def(ctx.seat, ctx.crew_slot) if cards != null else null
		ctx.verb = ctx.crew.verb if ctx.crew != null else ""
		return ctx
	var index: int = entry["ability"]
	var def: CardDef = cards.def_of(ctx.card) if cards != null else null
	if def != null and index >= 0 and index < def.abilities.size():
		ctx.ability = def.abilities[index]
		ctx.verb = ctx.ability.verb
	return ctx


## The verb's prepare(): the match's extra verb table first, then Crew or card abilities.
static func _prepare(ctx: TriggerContext) -> void:
	var handler: VerbHandler = ctx.cards.verb_handler()
	if handler != null and handler.handles(ctx.verb):
		handler.prepare(ctx)
	elif ctx.is_crew():
		CrewAbilities.prepare(ctx)
	else:
		Abilities.prepare(ctx)


## The verb's resolve(), dispatched as _prepare().
static func _apply(ctx: TriggerContext) -> void:
	ctx.prompt = {}
	var handler: VerbHandler = ctx.cards.verb_handler()
	if handler != null and handler.handles(ctx.verb):
		handler.resolve(ctx)
	elif ctx.is_crew():
		CrewAbilities.resolve(ctx)
	else:
		Abilities.resolve(ctx)


## TRIGGER_FIRED {seat, card, crew, moment, verb, resolution}: public. A card firing from
## its hand is public too (C14, the telegraph) and adds `from_hand: true`; a card firing from
## its Deck stays private to its seat (_owner).
static func _fired(ctx: TriggerContext) -> void:
	var fired: Dictionary = {
		"seat": ctx.seat,
		"card": ctx.card,
		"crew": ctx.crew.id if ctx.crew != null else "",
		"moment": ctx.moment,
		"verb": ctx.verb,
		"resolution": ctx.resolution,
	}
	_mark_hand(ctx, fired)
	ctx.emit(MatchEvent.Kind.TRIGGER_FIRED, fired, _owner(ctx))


## TRIGGER_FIZZLED {seat, card, crew, verb, reason}: public, except as _fired().
static func _fizzled(ctx: TriggerContext, reason: String) -> void:
	var fizzled: Dictionary = {
		"seat": ctx.seat,
		"card": ctx.card,
		"crew": ctx.crew.id if ctx.crew != null else "",
		"verb": ctx.verb,
		"reason": reason,
	}
	_mark_hand(ctx, fizzled)
	ctx.emit(MatchEvent.Kind.TRIGGER_FIZZLED, fizzled, _owner(ctx))


## Adds `from_hand: true` to a trigger payload whose card is in its seat's hand, so the board
## telegraphs it to both seats (rules-v2 section 8, C14).
static func _mark_hand(ctx: TriggerContext, payload: Dictionary) -> void:
	var piles: MatchState.SeatPiles = _seat_piles(ctx)
	if piles != null and piles.hand.has(ctx.card):
		payload[MatchEvent.KEY_FROM_HAND] = true


## The owner of a trigger event: the seat when its card is in that seat's Deck (hidden from
## the other seat, whose copy hides `card`, MatchEvent.redacted_for), else
## MatchEvent.PUBLIC. A hand trigger is public (C14).
static func _owner(ctx: TriggerContext) -> int:
	var piles: MatchState.SeatPiles = _seat_piles(ctx)
	if piles != null and piles.deck.has(ctx.card):
		return ctx.seat
	return MatchEvent.PUBLIC


## The piles of the trigger's seat, or null for a Crew trigger or an out-of-range seat.
static func _seat_piles(ctx: TriggerContext) -> MatchState.SeatPiles:
	if ctx.card < 0 or ctx.seat < 0 or ctx.seat >= ctx.state.seats.size():
		return null
	var piles: MatchState.SeatPiles = ctx.state.seats[ctx.seat]
	return piles


# --- Watchers -------------------------------------------------------------------------


## Appends the entries of `card` (Controlled by `watcher_seat`, in `zone`) for `event`.
static func _card_entries(
	out: Array[Dictionary],
	cards: MatchCards,
	event: Dictionary,
	card: int,
	watcher_seat: int,
	zone: String
) -> void:
	var def: CardDef = cards.def_of(card)
	if def == null:
		return
	var moment: String = event["moment"]
	var subjects: Array[int] = event["subjects"]
	var subject_seats: Array[int] = event["seats"]
	var event_seat: int = event["seat"]
	for index: int in range(def.abilities.size()):
		var ability: CardAbility = def.abilities[index]
		if ability.moment != moment or ability.zone != zone:
			continue
		if subjects.is_empty() or SEATLESS_MOMENTS.has(moment) or SEAT_MOMENTS.has(moment):
			if _seat_watches(ability.watch, watcher_seat, event_seat, moment):
				out.append(_entry(KIND_CARD, watcher_seat, card, -1, index, moment, -1, event_seat))
			continue
		for at: int in range(subjects.size()):
			var subject: int = subjects[at]
			var subject_seat: int = subject_seats[at]
			if _card_watches(ability.watch, card, watcher_seat, subject, subject_seat):
				out.append(
					_entry(KIND_CARD, watcher_seat, card, -1, index, moment, subject, subject_seat)
				)


## On discard: a Discarded subject in a Pile fires its own `watch: self` abilities.
static func _pile_entries(
	out: Array[Dictionary], state: MatchState, cards: MatchCards, event: Dictionary
) -> void:
	var subjects: Array[int] = event["subjects"]
	var subject_seats: Array[int] = event["seats"]
	for at: int in range(subjects.size()):
		var subject: int = subjects[at]
		var holder: int = subject_seats[at]
		if holder < 0 or not state.seats[holder].pile.has(subject):
			continue
		var def: CardDef = cards.def_of(subject)
		if def == null:
			continue
		for index: int in range(def.abilities.size()):
			var ability: CardAbility = def.abilities[index]
			if ability.moment == MOMENT_DISCARD and ability.watch == CardAbility.WATCH_SELF:
				out.append(
					_entry(KIND_CARD, holder, subject, -1, index, MOMENT_DISCARD, subject, holder)
				)


## Appends the entries of `seat`'s Crew for `event`, by Crew slot: a seatless event wakes
## every Crew on its moment, a seat event that seat's, a card event its subject's seat's
## (once per subject).
static func _crew_entries(
	out: Array[Dictionary], cards: MatchCards, event: Dictionary, crew_seat: int
) -> void:
	var moment: String = event["moment"]
	var subjects: Array[int] = event["subjects"]
	var subject_seats: Array[int] = event["seats"]
	var event_seat: int = event["seat"]
	for slot: int in range(MatchRules.CREW_SIZE):
		var crew: CrewDef = cards.crew_def(crew_seat, slot)
		if crew == null or crew.moment != moment:
			continue
		if SEATLESS_MOMENTS.has(moment) or (SEAT_MOMENTS.has(moment) and event_seat == crew_seat):
			out.append(_entry(KIND_CREW, crew_seat, -1, slot, 0, moment, -1, event_seat))
			continue
		for at: int in range(subjects.size()):
			if subject_seats[at] == crew_seat:
				out.append(_entry(KIND_CREW, crew_seat, -1, slot, 0, moment, subjects[at], crew_seat))


## Whether a watcher of `watch` Controlled by `watcher_seat` wakes for a seat event of
## `event_seat` (any seat for a seatless moment).
static func _seat_watches(
	watch: String, watcher_seat: int, event_seat: int, moment: String
) -> bool:
	if SEATLESS_MOMENTS.has(moment) or event_seat < 0:
		return true
	if watch == CardAbility.WATCH_OPPOSING:
		return watcher_seat != event_seat
	if watch == CardAbility.WATCH_ANY:
		return true
	return watcher_seat == event_seat


## Whether `watcher` (of `watcher_seat`) with `watch` wakes for the event of `subject` (of
## `subject_seat`): self its own, other_own another card of its seat, opposing a card of
## the other seat, any every card.
static func _card_watches(
	watch: String, watcher: int, watcher_seat: int, subject: int, subject_seat: int
) -> bool:
	if watch == CardAbility.WATCH_OTHER_OWN:
		return watcher != subject and watcher_seat == subject_seat
	if watch == CardAbility.WATCH_OPPOSING:
		return subject_seat >= 0 and watcher_seat != subject_seat
	if watch == CardAbility.WATCH_ANY:
		return true
	return watcher == subject


## One queue entry as plain data.
static func _entry(
	kind: String,
	entry_seat: int,
	card: int,
	crew_slot: int,
	ability: int,
	moment: String,
	subject: int,
	subject_seat: int
) -> Dictionary:
	return {
		"kind": kind,
		"seat": entry_seat,
		"card": card,
		"crew_slot": crew_slot,
		"ability": ability,
		"moment": moment,
		"subject": subject,
		"subject_seat": subject_seat,
		"context": {},
		"extra": false,
		"batch": -1,
	}


## Sends prepared events to `sink` with their owners when the sink is valid.
static func _forward(events: Array[MatchEvent], sink: Callable) -> void:
	if not sink.is_valid():
		return
	for event: MatchEvent in events:
		sink.call(event.kind, event.payload, event.owner_seat)
