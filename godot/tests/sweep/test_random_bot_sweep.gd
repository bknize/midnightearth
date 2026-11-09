class_name TestRandomBotSweep
extends GdUnitTestSuite
## The random bot's shipped-deck case (cycle 9 R70, DC-13 T08), moved out of test_random_bot.gd
## at NSC-251 (cycle-14 R43) to keep the gate's test stage under 30 s. It runs with the sweep
## (`scripts/check.sh sweep`), outside the gate, and does not read SWEEP_BOT: two random bots
## always play. It prints no `Sweep:` line.

const PAIRING_SEEDS: int = 50
const PAIRINGS: Array[Array] = [
	["greed", "greed"],
	["greed", "ramp"],
	["ramp", "greed"],
	["ramp", "ramp"],
]
const MAX_ACTIONS: int = 1000


func _bots(match_seed: int, engine: MatchEngine) -> Array[RandomBot]:
	var bots: Array[RandomBot] = []
	for seat: int in range(MatchEngine.SEATS):
		bots.append(RandomBot.new(BotRegistry.seed_for(match_seed, seat), engine.match_cards()))
	return bots


## Plays `engine` (not started) to its end with two random bots; returns the number of
## prompts answered, or -1 when an action was rejected or the cap was hit.
func _play_out(match_seed: int, engine: MatchEngine) -> int:
	if not engine.start().ok:
		fail("seed %d did not start" % match_seed)
		return -1
	var bots: Array[RandomBot] = _bots(match_seed, engine)
	var actions: int = 0
	var prompts: int = 0
	while not engine.is_over() and actions < MAX_ACTIONS:
		var seat: int = engine.awaited_seat()
		var view: SeatView = engine.view_for(seat)
		var action: EngineAction = bots[seat].choose(view, engine)
		if action == null:
			fail("seed %d action %d is null" % [match_seed, actions])
			return -1
		if action.seat != seat:
			fail("seed %d action %d for the wrong seat" % [match_seed, actions])
			return -1
		if not view.prompt.is_empty():
			prompts += 1
		var result: ApplyResult = engine.apply(action)
		if not result.ok:
			fail(
				(
					"seed %d action %d rejected (error %d): %s"
					% [match_seed, actions, result.error, str(action.to_dict())]
				)
			)
			return -1
		actions += 1
	if not engine.is_over():
		fail("seed %d did not end within %d actions" % [match_seed, MAX_ACTIONS])
		return -1
	return prompts


## R3, R70 (DC-13 T08): on the shipped Greed and Ramp decks with their abilities and Crew,
## 50 seeds spread over the four pairings (greed/greed, greed/ramp, ramp/greed, ramp/ramp,
## seed n on pairing (n - 1) mod 4) each end with no rejected action; a stalemate draw ends
## a match too (spec C12).
func test_fifty_seeds_over_the_four_pairings_end_with_no_rejected_action() -> void:
	var cards: CardDb = CardDb.load_default()
	var decks: DeckList = DeckList.load_default()
	var crew: CrewPool = CrewPool.load_default()
	var ended: int = 0
	for match_seed: int in range(1, PAIRING_SEEDS + 1):
		var listed: Array = PAIRINGS[(match_seed - 1) % PAIRINGS.size()]
		var pairing: Array[String] = []
		pairing.assign(listed)
		var engine: MatchEngine = MatchEngine.create(match_seed, cards, decks, pairing, crew)
		if _play_out(match_seed, engine) < 0:
			return
		ended += 1
	assert_int(ended).is_equal(PAIRING_SEEDS)
