class_name BoardSteps
extends RefCounted
## Maps seat-0 redacted events to BoardStep beats (R31-R38, spec M, plan P17). Pure: no
## nodes, no clock. Every duration and delay is the 1x value divided by `speed`.
##
## Engine-facing: events are matched by the NAME of their MatchEvent.Kind (kind_name()), with
## the payload keys of the v7 event table (engine/match_event.gd), so this one file is the
## whole seam to the engine's event shapes.
##
## Timing (seconds at 1x): clear 0.40, deal 0.30 with a 0.12 `delay` on every deal that
## directly follows another deal, draw 0.30, bot wait 0.6, opponent commit 0.25 per card,
## player commit 0.30, round end 0.30, pulse 0.12 for a revealed card or 0.35 preceded by a
## 0.15 `delay` (the gap sits before the flip) for a first reveal, effect 0.25, fizzle 0.15,
## choice shown 0.4, stats 0.2, status 0.2, move 0.3 (a run of CARD_MOVED events is one
## step), return 0.3, discard 0.45, exit 0.45, empty draw 0.4, shuffle-in 0.5, energy grant
## 0.3, look 0.4, unreveal 0.35, pile strip show / hide 0.25 (made by the board's prompt code
## through pile_step(), no event maps to them), walk end 0.6 (the tally fly-in and the count).
## Turn start, walk start, prompt, turn end and match end are instant (a prompt waits on the
## player, not on a clock). TURN_STARTED carries the Budget; ENERGY_GRANTED raises it.

const CLEAR_TIME: float = 0.40
const DEAL_TIME: float = 0.30
const DEAL_STAGGER: float = 0.12
const DRAW_TIME: float = 0.30
const BOT_WAIT_TIME: float = 0.6
const COMMIT_TIME_PER_CARD: float = 0.25
const REVEAL_TIME: float = 0.35
const REVEAL_GAP: float = 0.15
const PULSE_TIME: float = 0.12
const PLAYER_COMMIT_TIME: float = 0.30
const EFFECT_TIME: float = 0.25
const FIZZLE_TIME: float = 0.15
const CHOICE_SHOW_TIME: float = 0.4
const STATS_TIME: float = 0.2
const STATUS_TIME: float = 0.2
const WALK_END_TIME: float = 0.6
const MOVE_TIME: float = 0.3
const RETURN_TIME: float = 0.3
const DISCARD_TIME: float = 0.45
const EXIT_TIME: float = 0.45
const EMPTY_DRAW_TIME: float = 0.4
const SHUFFLE_TIME: float = 0.5
const ENERGY_TIME: float = 0.3
const LOOK_TIME: float = 0.4
const ROUND_END_TIME: float = 0.30
const UNREVEAL_TIME: float = 0.35
const PILE_TIME: float = 0.25
const CREW_TIME: float = 0.25
const DECLINE_TIME: float = 0.15


## The MatchEvent.Kind name of an event ("CARD_SCORED"): the match below reads kinds by name.
static func kind_name(event: MatchEvent) -> String:
	return MatchEvent.kind_name(event.kind)


## Steps for `events` (as `viewer` may see them) in event order. `speed` is 1 normally and
## 4 under autoplay; a non-positive speed counts as 1.
static func from_events(
	events: Array[MatchEvent], speed: float, viewer: int = 0
) -> Array[BoardStep]:
	var divisor: float = speed if speed > 0.0 else 1.0
	var steps: Array[BoardStep] = []
	var previous_kind: int = -1
	# Indices of CARD_SCORED events folded into the PULSE of their card's reveal.
	var folded: Dictionary = {}
	for at: int in range(events.size()):
		if folded.has(at):
			continue
		var event: MatchEvent = events[at]
		var after_deal: bool = previous_kind == BoardStep.Kind.DEAL
		var made: Array[BoardStep] = []
		match kind_name(event):
			"CARD_REVEALED":
				var scored_at: int = _scored_after(events, at)
				var scored: MatchEvent = null
				if scored_at >= 0:
					folded[scored_at] = true
					scored = events[scored_at]
				made.append(_pulse(event, scored))
			"CARD_SCORED":
				made.append(_pulse(null, event))
			"CARD_MOVED":
				made.append(_move_run(events, at, folded))
			_:
				made = _steps_for(event, viewer, after_deal)
		for step: BoardStep in made:
			step.duration = step.duration / divisor
			step.delay = step.delay / divisor
			step.chip_delay = step.chip_delay / divisor
			steps.append(step)
		if not made.is_empty():
			previous_kind = made[made.size() - 1].kind
	return steps


## The badge word of an engine status or exit mark: "muted" reads "Muted" (R79).
static func status_word(raw: String) -> String:
	return raw.capitalize()


## One MOVE step for the run of consecutive CARD_MOVED events of one seat from `at` on, every
## card in it moving in a single re-layout. Later events of the run are marked in `folded`.
## The slots are `from` and `to` in the v7 table (`from_slot` / `to_slot` are read first).
static func _move_run(events: Array[MatchEvent], at: int, folded: Dictionary) -> BoardStep:
	var first: MatchEvent = events[at]
	var step: BoardStep = _card_step(BoardStep.Kind.MOVE, first)
	var seat: int = step.seat
	step.duration = MOVE_TIME
	var i: int = at
	while i < events.size() and kind_name(events[i]) == "CARD_MOVED":
		var next: Dictionary = events[i].payload
		var next_seat: int = _seat_of(next)
		if next_seat != seat:
			break
		var id: int = next.get("card", -1)
		var from_slot: int = next.get("from_slot", next.get("from", -1))
		var to_slot: int = next.get("to_slot", next.get("to", -1))
		step.cards.append(id)
		step.from_slots.append(from_slot)
		step.slots_to.append(to_slot)
		if i > at:
			folded[i] = true
		i += 1
	step.from_slot = step.from_slots[0]
	step.slot = step.slots_to[0]
	return step


## The CREW_FIRE step of a CREW_FIRED event {seat, crew, slot, moment} (cycle 8 R61).
static func _crew_fire(event: MatchEvent) -> BoardStep:
	var step: BoardStep = _make(BoardStep.Kind.CREW_FIRE, event)
	var payload: Dictionary = event.payload
	step.seat = payload.get("seat", -1)
	step.slot = payload.get("slot", -1)
	step.crew = payload.get("crew", "")
	step.verb = payload.get("verb", "")
	step.trigger = payload.get("moment", payload.get("trigger", ""))
	step.uses_left = payload.get("uses_left", -1)
	step.duration = CREW_TIME
	return step


static func _unreveal(event: MatchEvent) -> BoardStep:
	var step: BoardStep = _card_step(BoardStep.Kind.UNREVEAL, event)
	step.slot = event.payload.get("slot", -1)
	step.duration = UNREVEAL_TIME
	return step


## A PILE_SHOW or PILE_HIDE step for the Pile strip (R78): no engine event maps to it.
static func pile_step(show: bool, speed: float) -> BoardStep:
	var step: BoardStep = BoardStep.new()
	step.kind = BoardStep.Kind.PILE_SHOW if show else BoardStep.Kind.PILE_HIDE
	step.duration = PILE_TIME / (speed if speed > 0.0 else 1.0)
	return step


## Index of the CARD_SCORED that answers the CARD_REVEALED at `at` (same card, before the
## next reveal, walk or turn end), or -1. A move of the card in between (c12's swap) also
## stops the fold: the card flips where it was, the move plays, and its score then pulses
## at the slot it landed on, so the chips never show before the move (DC-06 T08 item 4).
static func _scored_after(events: Array[MatchEvent], at: int) -> int:
	var card: int = events[at].payload["card"]
	var found: int = -1
	for i: int in range(at + 1, events.size()):
		var next: MatchEvent = events[i]
		var named: int = next.payload.get("card", -1)
		var next_name: String = kind_name(next)
		if next_name == "CARD_SCORED":
			if named == card:
				found = i
				break
		elif next_name == "CARD_MOVED" and named == card:
			break
		elif (
			next_name == "CARD_REVEALED"
			or next_name == "WALK_STARTED"
			or next_name == "WALK_ENDED"
			or next_name == "TURN_ENDED"
		):
			break
	return found


## One PULSE from a reveal and/or its score. With a reveal the card flips first
## (`revealed = false`); without one it was already face up. CARD_REVEALED {seat, card, slot,
## power, mult, add, statuses}; CARD_SCORED {seat, card, slot, power, bonus_value, total, pass}.
static func _pulse(reveal: MatchEvent, scored: MatchEvent) -> BoardStep:
	var main: MatchEvent = reveal if reveal != null else scored
	var step: BoardStep = _card_step(BoardStep.Kind.PULSE, main)
	var payload: Dictionary = main.payload
	step.slot = payload.get("slot", -1)
	step.power = payload.get("power", 0)
	if reveal != null:
		step.mult = payload.get("mult", 0)
		step.add = payload.get("add", 0)
		var raw: Array = payload.get("statuses", [])
		for word: Variant in raw:
			var named: String = word
			step.statuses.append(status_word(named))
		step.revealed = false
		step.order = payload.get("order", 0)
		step.duration = REVEAL_TIME
		step.delay = REVEAL_GAP
	else:
		step.duration = PULSE_TIME
	if scored != null:
		var values: Dictionary = scored.payload
		step.power = values.get("power", step.power)
		step.bonus_value = values.get("bonus_value", ScoreChips.SCALE)
		step.total = values.get("total", 0)
		step.scored = true
		var pass_number: int = values.get("pass", 1)
		step.again = pass_number > 1
		# On a first reveal the chips wait for the flip to finish (R31).
		step.chip_delay = REVEAL_TIME if reveal != null else 0.0
		step.duration = maxf(step.duration, step.chip_delay + ScoreChips.chips_time(step))
	return step


static func _steps_for(event: MatchEvent, viewer: int, after_deal: bool) -> Array[BoardStep]:
	var out: Array[BoardStep] = []
	var payload: Dictionary = event.payload
	match kind_name(event):
		"ROUND_STARTED":
			var round_number: int = payload["round"]
			if round_number > 1:
				var clear: BoardStep = _make(BoardStep.Kind.CLEAR_TABLE, event)
				clear.round_number = round_number
				clear.duration = CLEAR_TIME
				out.append(clear)
		"CARD_DEALT":
			var deal: BoardStep = _card_step(BoardStep.Kind.DEAL, event)
			deal.duration = DEAL_TIME
			deal.delay = DEAL_STAGGER if after_deal else 0.0
			out.append(deal)
		"CARD_DRAWN":
			var draw: BoardStep = _card_step(BoardStep.Kind.DRAW, event)
			draw.duration = DRAW_TIME
			out.append(draw)
		"DRAW_EMPTY":
			var empty: BoardStep = _make(BoardStep.Kind.EMPTY_DRAW, event)
			empty.seat = _seat_of(payload)
			empty.duration = EMPTY_DRAW_TIME
			out.append(empty)
		"PILE_SHUFFLED_IN":
			var shuffled: BoardStep = _make(BoardStep.Kind.SHUFFLE_IN, event)
			shuffled.seat = _seat_of(payload)
			shuffled.count = payload.get("count", 0)
			shuffled.duration = SHUFFLE_TIME
			out.append(shuffled)
		"TURN_STARTED":
			out.append(_turn_start(event, viewer))
		"ENERGY_GRANTED":
			var granted: BoardStep = _make(BoardStep.Kind.ENERGY_GRANT, event)
			granted.seat = _seat_of(payload)
			granted.amount = payload.get("amount", 0)
			granted.duration = ENERGY_TIME
			out.append(granted)
		"COMMITTED":
			_append_commit(out, event, viewer)
		"WALK_STARTED":
			out.append(_make(BoardStep.Kind.WALK_START, event))
		"WALK_ENDED":
			var walk_end: BoardStep = _make(BoardStep.Kind.WALK_END, event)
			var totals: Array = payload.get("totals", [])
			var walk_scores: Array = payload.get("scores", [])
			walk_end.totals.assign(totals)
			walk_end.scores.assign(walk_scores)
			walk_end.duration = WALK_END_TIME
			out.append(walk_end)
		"TRIGGER_FIRED":
			# A Crew's firing is CREW_FIRED's beat; a card's lifts it.
			var fired_crew: String = payload.get("crew", "")
			if fired_crew == "":
				var fired: BoardStep = _card_step(BoardStep.Kind.EFFECT, event)
				fired.verb = payload.get("verb", "")
				fired.trigger = payload.get("moment", "")
				fired.duration = EFFECT_TIME
				out.append(fired)
		"TRIGGER_FIZZLED":
			var fizzled_crew: String = payload.get("crew", "")
			if fizzled_crew == "":
				var fizzled: BoardStep = _card_step(BoardStep.Kind.FIZZLE, event)
				fizzled.verb = payload.get("verb", "")
				fizzled.reason = payload.get("reason", "")
				fizzled.duration = FIZZLE_TIME
				out.append(fizzled)
		"PROMPT_OPENED":
			# Only the viewer's own prompt shows; the bot's request has no beat.
			if _seat_of(payload) == viewer:
				out.append(_prompt(event))
		"CHOICE_MADE":
			var shown: BoardStep = _card_step(BoardStep.Kind.CHOICE_SHOW, event)
			shown.zone = payload.get("zone", "")
			shown.index = payload.get("index", -1)
			shown.target = payload.get("target", -1)
			shown.duration = CHOICE_SHOW_TIME
			out.append(shown)
		"STATS_CHANGED":
			# A hand card's change is private to its holder: the other seat's copy has the
			# card hidden and shows nothing (cycle 8 P4, P16).
			if event.is_private() and event.owner_seat != viewer:
				return out
			var stats: BoardStep = _card_step(BoardStep.Kind.STATS, event)
			stats.seat = event.owner_seat if event.is_private() else -1
			stats.cost = payload.get("cost", -1)
			stats.permanent = payload.get("permanent", false)
			stats.in_hand = event.is_private()
			stats.power = payload.get("power", 0)
			stats.mult = payload.get("mult", 0)
			stats.add = payload.get("add", 0)
			stats.cause = payload.get("cause", "")
			stats.duration = STATS_TIME
			out.append(stats)
		"STATUS_SET", "STATUS_ENDED", "EXIT_MARKED":
			_append_status(out, event)
		"EXIT_RESOLVED":
			var exit_step: BoardStep = _card_step(BoardStep.Kind.EXIT, event)
			exit_step.exit_to = payload.get("to", "")
			var mark: String = payload.get("mark", "")
			exit_step.word = status_word(mark)
			exit_step.duration = EXIT_TIME
			out.append(exit_step)
		"CREW_FIRED":
			out.append(_crew_fire(event))
		"CHOICE_DECLINED":
			var declined: BoardStep = _make(BoardStep.Kind.DECLINE, event)
			declined.seat = _seat_of(payload)
			declined.duration = DECLINE_TIME
			out.append(declined)
		"CARD_UNREVEALED":
			out.append(_unreveal(event))
		"CARD_RETURNED":
			var returned: BoardStep = _card_step(BoardStep.Kind.RETURN, event)
			returned.slot = payload.get("slot", -1)
			returned.duration = RETURN_TIME
			out.append(returned)
		"CARD_DISCARDED":
			var discarded: BoardStep = _card_step(BoardStep.Kind.DISCARD, event)
			var from_zone: String = payload.get("from", "hand")
			discarded.from_row = from_zone == "row"
			discarded.reason = payload.get("reason", "")
			discarded.pile_index = payload.get("pile_index", -1)
			discarded.duration = DISCARD_TIME
			out.append(discarded)
		"CARD_LOOKED":
			# Private to the looking seat: the viewer's own look only.
			if _seat_of(payload) == viewer:
				var looked: BoardStep = _card_step(BoardStep.Kind.LOOK, event)
				looked.slot = payload.get("slot", -1)
				looked.from_seat = payload.get("from_seat", -1)
				looked.duration = LOOK_TIME
				out.append(looked)
		"TURN_ENDED":
			var turn_end: BoardStep = _make(BoardStep.Kind.TURN_END, event)
			var ended_scores: Array = payload.get("scores", [])
			var ended_wins: Array = payload.get("wins", [])
			turn_end.seat = payload.get("winner", -1)
			turn_end.scores.assign(ended_scores)
			turn_end.wins.assign(ended_wins)
			out.append(turn_end)
		"ROUND_ENDED":
			var round_end: BoardStep = _make(BoardStep.Kind.ROUND_END, event)
			var round_wins: Array = payload["wins"]
			round_end.seat = payload["winner"]
			round_end.round_number = payload.get("round", 0)
			round_end.wins.assign(round_wins)
			round_end.duration = ROUND_END_TIME
			out.append(round_end)
		"MATCH_ENDED":
			var match_end: BoardStep = _make(BoardStep.Kind.MATCH_END, event)
			var match_winner: int = payload["winner"]
			var match_wins: Array = payload["wins"]
			match_end.seat = match_winner
			match_end.wins.assign(match_wins)
			out.append(match_end)
		_:
			# CONCEDED has no beat of its own: MATCH_ENDED follows it and carries the reason.
			pass
	return out


## TURN_STARTED {round, turn, first_seat, budgets}: the viewer's Budget is `budgets[viewer]`.
static func _turn_start(event: MatchEvent, viewer: int) -> BoardStep:
	var payload: Dictionary = event.payload
	var start: BoardStep = _make(BoardStep.Kind.TURN_START, event)
	start.round_number = payload["round"]
	start.turn = payload["turn"]
	var budgets: Array = payload.get("budgets", [])
	if viewer >= 0 and viewer < budgets.size():
		var own_budget: int = budgets[viewer]
		start.budget = own_budget
	start.energy = start.budget
	return start


## STATUS_SET {card, status, cessation, cause}, STATUS_ENDED {card, status, cause} and
## EXIT_MARKED {card, mark, replaced}: a badge word appears or goes. A hidden card (id -1,
## a face-down card the viewer may not name) has no badge to show.
static func _append_status(out: Array[BoardStep], event: MatchEvent) -> void:
	var payload: Dictionary = event.payload
	var card: int = payload.get("card", -1)
	if card < 0:
		return
	var step: BoardStep = _make(BoardStep.Kind.STATUS, event)
	step.card = card
	var named: String = payload.get("status", payload.get("mark", ""))
	step.word = status_word(named)
	step.status_on = kind_name(event) != "STATUS_ENDED"
	step.cause = payload.get("cause", "")
	var replaced: Variant = payload.get("replaced", "")
	if replaced is String:
		var old: String = replaced
		step.old_word = status_word(old)
	step.duration = STATUS_TIME
	out.append(step)


## PROMPT_OPENED: the prompt of P12 {seat, card, crew, verb, zone, options, multi, exact, min,
## optional, resume, step} plus `text`.
static func _prompt(event: MatchEvent) -> BoardStep:
	var payload: Dictionary = event.payload
	var step: BoardStep = _make(BoardStep.Kind.PROMPT, event)
	step.seat = _seat_of(payload)
	step.card = payload.get("card", -1)
	step.crew = payload.get("crew", "")
	step.verb = payload.get("verb", "")
	step.text = payload.get("text", "")
	step.zone = payload.get("zone", "")
	step.multi = payload.get("multi", false)
	step.optional = payload.get("optional", false)
	step.exact = payload.get("exact", -1)
	step.step = payload.get("step", "")
	var raw_options: Array = payload.get("options", [])
	step.options.assign(raw_options)
	return step


## The opponent's commit waits for the bot, then slides the cards; the viewer's is instant.
## COMMITTED {seat, cards, slots, cost, pass}: the card count is the length of `cards`, whose
## ids are hidden from the other seat but still counted.
static func _append_commit(out: Array[BoardStep], event: MatchEvent, viewer: int) -> void:
	var seat: int = event.payload["seat"]
	var cards: Array = event.payload.get("cards", [])
	var count: int = event.payload.get("count", cards.size())
	var raw_slots: Array = event.payload.get("slots", [])
	if seat == viewer:
		var own: BoardStep = _make(BoardStep.Kind.PLAYER_COMMIT, event)
		own.seat = seat
		own.count = count
		own.slots.assign(raw_slots)
		own.duration = PLAYER_COMMIT_TIME
		out.append(own)
		return
	var wait: BoardStep = _make(BoardStep.Kind.BOT_WAIT, event)
	wait.seat = seat
	wait.duration = BOT_WAIT_TIME
	out.append(wait)
	var slide: BoardStep = _make(BoardStep.Kind.OPPONENT_COMMIT, event)
	slide.seat = seat
	slide.count = count
	slide.slots.assign(raw_slots)
	slide.duration = COMMIT_TIME_PER_CARD * float(count)
	out.append(slide)


static func _make(kind: int, event: MatchEvent) -> BoardStep:
	var step: BoardStep = BoardStep.new()
	step.kind = kind
	step.source = event
	return step


## The seat an event names: `seat`, else `owner` (CARD_DISCARDED, EXIT_RESOLVED), else -1.
static func _seat_of(payload: Dictionary) -> int:
	var seat: int = payload.get("seat", payload.get("owner", -1))
	return seat


## A step for an event with a seat and a card; either may be missing (-1).
static func _card_step(kind: int, event: MatchEvent) -> BoardStep:
	var step: BoardStep = _make(kind, event)
	step.seat = _seat_of(event.payload)
	step.card = event.payload.get("card", -1)
	return step
