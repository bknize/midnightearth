class_name BoardSteps
extends RefCounted
## Maps seat-0 redacted events to BoardStep beats (R31-R38). Pure: no nodes, no clock.
## Every duration and delay is the 1x value divided by `speed`.
##
## Timing (seconds at 1x): clear 0.40, deal 0.30 with a 0.12 `delay` on every deal that
## directly follows another deal, draw 0.30, burn 0.45, bot wait 0.6, opponent commit
## 0.25 per card, reveal 0.35 preceded by a 0.15 `delay` (the gap sits before the flip),
## round end 0.30. Turn start, player commit, turn end and match end are instant.

const CLEAR_TIME: float = 0.40
const DEAL_TIME: float = 0.30
const DEAL_STAGGER: float = 0.12
const DRAW_TIME: float = 0.30
const BURN_TIME: float = 0.45
const BOT_WAIT_TIME: float = 0.6
const COMMIT_TIME_PER_CARD: float = 0.25
const REVEAL_TIME: float = 0.35
const REVEAL_GAP: float = 0.15
const ROUND_END_TIME: float = 0.30


## Steps for `events` (as `viewer` may see them) in event order. `speed` is 1 normally and
## 4 under autoplay; a non-positive speed counts as 1.
static func from_events(
	events: Array[MatchEvent], speed: float, viewer: int = 0
) -> Array[BoardStep]:
	var divisor: float = speed if speed > 0.0 else 1.0
	var steps: Array[BoardStep] = []
	var previous_kind: int = -1
	for event: MatchEvent in events:
		var after_deal: bool = previous_kind == BoardStep.Kind.DEAL
		var made: Array[BoardStep] = _steps_for(event, viewer, after_deal)
		for step: BoardStep in made:
			step.duration = step.duration / divisor
			step.delay = step.delay / divisor
			steps.append(step)
		if not made.is_empty():
			previous_kind = made[made.size() - 1].kind
	return steps


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
			out.append(start)
		MatchEvent.Kind.COMMITTED:
			_append_commit(out, event, viewer)
		MatchEvent.Kind.CARD_REVEALED:
			var reveal: BoardStep = _card_step(BoardStep.Kind.REVEAL, event)
			var reveal_power: int = payload["power"]
			var reveal_order: int = payload["order"]
			reveal.power = reveal_power
			reveal.order = reveal_order
			reveal.duration = REVEAL_TIME
			reveal.delay = REVEAL_GAP
			out.append(reveal)
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
	if seat == viewer:
		var own: BoardStep = _make(BoardStep.Kind.PLAYER_COMMIT, event)
		own.seat = seat
		own.count = count
		out.append(own)
		return
	var wait: BoardStep = _make(BoardStep.Kind.BOT_WAIT, event)
	wait.seat = seat
	wait.duration = BOT_WAIT_TIME
	out.append(wait)
	var slide: BoardStep = _make(BoardStep.Kind.OPPONENT_COMMIT, event)
	slide.seat = seat
	slide.count = count
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
