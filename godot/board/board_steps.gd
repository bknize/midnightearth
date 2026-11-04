class_name BoardSteps
extends RefCounted
## Maps seat-0 redacted events to BoardStep beats (R31-R38). Pure: no nodes, no clock.
## Every duration and delay is the 1x value divided by `speed`.
##
## Timing (seconds at 1x): clear 0.40, deal 0.30 with a 0.12 `delay` on every deal that
## directly follows another deal, draw 0.30, burn 0.45, bot wait 0.6, opponent commit
## 0.25 per card, player commit 0.30, round end 0.30, pulse 0.12 for a revealed card or
## 0.35 preceded by a 0.15 `delay` (the gap sits before the flip) for a first reveal, effect
## 0.25, fizzle 0.15, choice shown 0.4, stats 0.2, destroy 0.45, move 0.3, return 0.3,
## discard 0.45. Turn start, walk start, prompt, turn end and match end are instant (a prompt
## waits on the player, not on a clock). BONUS_ZERO_SET, ENERGY_CARRIED and FREE_FIRST_SET
## have no step: the next TURN_STARTED carries their result (budgets, free_first), and
## CARD_REVEALED / STATS_CHANGED carry the zeroed bonus.

const CLEAR_TIME: float = 0.40
const DEAL_TIME: float = 0.30
const DEAL_STAGGER: float = 0.12
const DRAW_TIME: float = 0.30
const BURN_TIME: float = 0.45
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
const DESTROY_TIME: float = 0.45
const MOVE_TIME: float = 0.3
const RETURN_TIME: float = 0.3
const DISCARD_TIME: float = 0.45
const ROUND_END_TIME: float = 0.30


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
		if event.kind == MatchEvent.Kind.CARD_REVEALED:
			var scored_at: int = _scored_after(events, at)
			var scored: MatchEvent = null
			if scored_at >= 0:
				folded[scored_at] = true
				scored = events[scored_at]
			made.append(_pulse(event, scored))
		elif event.kind == MatchEvent.Kind.CARD_SCORED:
			made.append(_pulse(null, event))
		else:
			made = _steps_for(event, viewer, after_deal)
		for step: BoardStep in made:
			step.duration = step.duration / divisor
			step.delay = step.delay / divisor
			steps.append(step)
		if not made.is_empty():
			previous_kind = made[made.size() - 1].kind
	return steps


## Index of the CARD_SCORED that answers the CARD_REVEALED at `at` (same card, before the
## next reveal, walk or turn end), or -1.
static func _scored_after(events: Array[MatchEvent], at: int) -> int:
	var card: int = events[at].payload["card"]
	var found: int = -1
	for i: int in range(at + 1, events.size()):
		var next: MatchEvent = events[i]
		if next.kind == MatchEvent.Kind.CARD_SCORED:
			var scored_card: int = next.payload["card"]
			if scored_card == card:
				found = i
				break
		elif (
			next.kind == MatchEvent.Kind.CARD_REVEALED
			or next.kind == MatchEvent.Kind.WALK_STARTED
			or next.kind == MatchEvent.Kind.TURN_ENDED
		):
			break
	return found


## One PULSE from a reveal and/or its score. With a reveal the card flips first
## (`revealed = false`); without one it was already face up.
static func _pulse(reveal: MatchEvent, scored: MatchEvent) -> BoardStep:
	var main: MatchEvent = reveal if reveal != null else scored
	var step: BoardStep = _card_step(BoardStep.Kind.PULSE, main)
	var payload: Dictionary = main.payload
	step.slot = payload.get("slot", -1)
	step.flat = payload.get("flat", 0)
	step.bonus = payload.get("bonus", 0)
	if reveal != null:
		step.revealed = false
		step.order = reveal.payload.get("order", 0)
		step.duration = REVEAL_TIME
		step.delay = REVEAL_GAP
	else:
		step.duration = PULSE_TIME
	if scored != null:
		var values: Dictionary = scored.payload
		step.flat = values.get("flat", step.flat)
		step.bonus = values.get("bonus", step.bonus)
		step.mult = values.get("mult", 1)
		step.added = values.get("added", 0)
		step.score = values.get("score", -1)
	return step


static func _steps_for(event: MatchEvent, viewer: int, after_deal: bool) -> Array[BoardStep]:
	var out: Array[BoardStep] = []
	var payload: Dictionary = event.payload
	match event.kind:
		MatchEvent.Kind.ROUND_STARTED:
			var round_number: int = payload["round"]
			if round_number > 1:
				var clear: BoardStep = _make(BoardStep.Kind.CLEAR_TABLE, event)
				clear.round_number = round_number
				clear.duration = CLEAR_TIME
				out.append(clear)
		MatchEvent.Kind.CARD_DEALT:
			var deal: BoardStep = _card_step(BoardStep.Kind.DEAL, event)
			deal.duration = DEAL_TIME
			deal.delay = DEAL_STAGGER if after_deal else 0.0
			out.append(deal)
		MatchEvent.Kind.CARD_DRAWN:
			var draw: BoardStep = _card_step(BoardStep.Kind.DRAW, event)
			draw.duration = DRAW_TIME
			out.append(draw)
		MatchEvent.Kind.CARD_BURNED:
			var burn: BoardStep = _card_step(BoardStep.Kind.BURN, event)
			burn.duration = BURN_TIME
			out.append(burn)
		MatchEvent.Kind.TURN_STARTED:
			var start: BoardStep = _make(BoardStep.Kind.TURN_START, event)
			var start_round: int = payload["round"]
			var start_turn: int = payload["turn"]
			var start_energy: int = payload["energy"]
			start.round_number = start_round
			start.turn = start_turn
			start.energy = start_energy
			start.budget = start_energy
			var budgets: Array = payload.get("budgets", [])
			if viewer >= 0 and viewer < budgets.size():
				var own_budget: int = budgets[viewer]
				start.budget = own_budget
			var frees: Array = payload.get("free_first", [])
			if viewer >= 0 and viewer < frees.size():
				var own_free: bool = frees[viewer]
				start.free_first = own_free
			out.append(start)
		MatchEvent.Kind.COMMITTED:
			_append_commit(out, event, viewer)
		MatchEvent.Kind.WALK_STARTED:
			out.append(_make(BoardStep.Kind.WALK_START, event))
		MatchEvent.Kind.EFFECT_FIRED:
			var fired: BoardStep = _card_step(BoardStep.Kind.EFFECT, event)
			fired.verb = payload.get("verb", "")
			fired.trigger = payload.get("trigger", "")
			fired.duration = EFFECT_TIME
			out.append(fired)
		MatchEvent.Kind.EFFECT_FIZZLED:
			var fizzled: BoardStep = _card_step(BoardStep.Kind.FIZZLE, event)
			fizzled.verb = payload.get("verb", "")
			fizzled.duration = FIZZLE_TIME
			out.append(fizzled)
		MatchEvent.Kind.CHOICE_REQUESTED:
			# Only the viewer's own prompt shows; the bot's request has no beat.
			var asked_seat: int = payload["seat"]
			if asked_seat == viewer:
				var prompt: BoardStep = _card_step(BoardStep.Kind.PROMPT, event)
				var raw_options: Array = payload.get("options", [])
				prompt.verb = payload.get("verb", "")
				prompt.text = payload.get("text", "")
				prompt.zone = payload.get("zone", "")
				prompt.options.assign(raw_options)
				out.append(prompt)
		MatchEvent.Kind.CHOICE_MADE:
			var shown: BoardStep = _card_step(BoardStep.Kind.CHOICE_SHOW, event)
			shown.zone = payload.get("zone", "")
			shown.index = payload.get("index", -1)
			shown.target = payload.get("target", -1)
			shown.duration = CHOICE_SHOW_TIME
			out.append(shown)
		MatchEvent.Kind.STATS_CHANGED:
			var stats: BoardStep = _card_step(BoardStep.Kind.STATS, event)
			stats.flat = payload.get("flat", 0)
			stats.bonus = payload.get("bonus", 0)
			stats.cause = payload.get("cause", "")
			stats.duration = STATS_TIME
			out.append(stats)
		MatchEvent.Kind.CARD_DESTROYED:
			var destroyed: BoardStep = _card_step(BoardStep.Kind.DESTROY, event)
			destroyed.slot = payload.get("slot", -1)
			destroyed.duration = DESTROY_TIME
			out.append(destroyed)
		MatchEvent.Kind.CARD_MOVED:
			var moved: BoardStep = _card_step(BoardStep.Kind.MOVE, event)
			moved.from_slot = payload.get("from_slot", -1)
			moved.slot = payload.get("to_slot", -1)
			moved.duration = MOVE_TIME
			out.append(moved)
		MatchEvent.Kind.CARD_RETURNED:
			var returned: BoardStep = _card_step(BoardStep.Kind.RETURN, event)
			returned.slot = payload.get("slot", -1)
			returned.duration = RETURN_TIME
			out.append(returned)
		MatchEvent.Kind.CARD_DISCARDED:
			var discarded: BoardStep = _card_step(BoardStep.Kind.DISCARD, event)
			discarded.duration = DISCARD_TIME
			out.append(discarded)
		MatchEvent.Kind.TURN_ENDED:
			var turn_end: BoardStep = _make(BoardStep.Kind.TURN_END, event)
			var ended_round: int = payload["round"]
			var ended_turn: int = payload["turn"]
			var ended_scores: Array = payload["scores"]
			turn_end.round_number = ended_round
			turn_end.turn = ended_turn
			turn_end.scores.assign(ended_scores)
			out.append(turn_end)
		MatchEvent.Kind.ROUND_ENDED:
			var round_end: BoardStep = _make(BoardStep.Kind.ROUND_END, event)
			var done_round: int = payload["round"]
			var round_winner: int = payload["winner"]
			var round_scores: Array = payload["scores"]
			var round_wins: Array = payload["wins"]
			round_end.round_number = done_round
			round_end.seat = round_winner
			round_end.scores.assign(round_scores)
			round_end.wins.assign(round_wins)
			round_end.duration = ROUND_END_TIME
			out.append(round_end)
		MatchEvent.Kind.MATCH_ENDED:
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


## The opponent's commit waits for the bot, then slides the cards; the viewer's is instant.
static func _append_commit(out: Array[BoardStep], event: MatchEvent, viewer: int) -> void:
	var seat: int = event.payload["seat"]
	var count: int = event.payload["count"]
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


## A step for an event with `seat` and `card`; the card index follows the instance id.
static func _card_step(kind: int, event: MatchEvent) -> BoardStep:
	var step: BoardStep = _make(kind, event)
	var seat: int = event.payload["seat"]
	var card: int = event.payload["card"]
	step.seat = seat
	step.card = card
	if card >= 0:
		step.def_index = card % MatchRules.DECK_SIZE
	return step
