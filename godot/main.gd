extends Node3D
## Placeholder main scene. Runs the engine smoke match (R39, R40) and prints the lines the
## build gate looks for: the "Engine smoke:" line, then "Main ready".

const SMOKE_SEED: int = 1
const MAX_ACTIONS: int = 2000


func _ready() -> void:
	var cards: CardDb = CardDb.load_default()
	if not cards.is_valid():
		push_error("Card data failed to load: %s" % cards.load_error())
		return
	if not _run_smoke(cards):
		return
	print("Main ready")


## Plays seed 1 to the end with one GreedyBot per seat and prints the summary line.
## Returns false after a push_error: a rejected action, the action cap or a start failure.
func _run_smoke(cards: CardDb) -> bool:
	var engine: MatchEngine = MatchEngine.create(SMOKE_SEED, cards)
	var started: ApplyResult = engine.start()
	if not started.ok:
		push_error("Engine smoke: start rejected, code %d" % started.error)
		return false
	var bots: Array[GreedyBot] = []
	for seat: int in MatchEngine.SEATS:
		bots.append(GreedyBot.new(GreedyBot.seed_for(SMOKE_SEED, seat), cards))
	var actions: int = 0
	var last: ApplyResult = started
	while not engine.is_over():
		if actions >= MAX_ACTIONS:
			push_error("Engine smoke: match not over after %d actions" % MAX_ACTIONS)
			return false
		var seat: int = engine.awaited_seat()
		var action: EngineAction = bots[seat].choose(engine.view_for(seat))
		last = engine.apply(action)
		if not last.ok:
			push_error("Engine smoke: action rejected, code %d" % last.error)
			return false
		actions += 1
	for event: MatchEvent in last.events:
		if event.kind != MatchEvent.Kind.MATCH_ENDED:
			continue
		var payload: Dictionary = event.payload
		var winner: int = payload["winner"]
		var reason: String = payload["reason"]
		var rounds: int = payload["rounds_played"]
		var raw_wins: Array = payload["wins"]
		var wins: Array[int] = []
		wins.assign(raw_wins)
		print(
			(
				"Engine smoke: seed=%d winner=%d wins=%d-%d rounds=%d end=%s actions=%d"
				% [SMOKE_SEED, winner, wins[0], wins[1], rounds, reason, actions]
			)
		)
		return true
	push_error("Engine smoke: match ended without a MATCH_ENDED event")
	return false
