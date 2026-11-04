class_name TestMatchDriver
extends GdUnitTestSuite
## MatchDriver (R2, R5, R6, C11): the seed-1 autoplay match through the driver equals the
## smoke match and prints the board's result line, seat 0 never sees a seat-1 card id, a
## seat-0 concede ends the match with reason "concede", and bot turns are due exactly when
## the human is not awaited. DC-05 T07: play_bot() answers a bot's prompt, and seat 0's
## prompt is read with open_prompt() and answered with submit_choice().

const SEED: int = 1
const MAX_ACTIONS: int = 2000
## Seeds tried, in order (1 first), until the prompt a case needs turns up.
const PROMPT_SEEDS: int = 10
## An index no prompt offers (options are positions in a zone of at most a few cards).
const NOT_AN_OPTION: int = 99
## Seed 1's pinned board result line. Empty while unpinned (re-pinned at DC-05 T14, card
## data format 2): the test then compares against a direct bot-vs-bot engine run instead.
const EXPECTED_LINE: String = ""
## Event kinds whose card ids are private to their owner.
const PRIVATE_KINDS: Array[int] = [
	MatchEvent.Kind.CARD_DEALT,
	MatchEvent.Kind.CARD_DRAWN,
	MatchEvent.Kind.CARD_BURNED,
	MatchEvent.Kind.COMMITTED,
]

var _cached_db: CardDb = null

# --- Helpers --------------------------------------------------------------------------


func _db() -> CardDb:
	if _cached_db == null:
		_cached_db = CardDb.load_default()
	return _cached_db


## Every int under an event payload's `card` or `cards` key.
func _event_card_ids(event: MatchEvent) -> Array[int]:
	var out: Array[int] = []
	var single: Variant = event.payload.get(MatchEvent.KEY_CARD)
	if single is int:
		var card: int = single
		out.append(card)
	var many: Variant = event.payload.get(MatchEvent.KEY_CARDS)
	if many is Array:
		var items: Array = many
		for item: Variant in items:
			if item is int:
				var listed: int = item
				out.append(listed)
	return out


## The seat-1 card ids named by the private events in `events`, as strings for the message.
## A public burn is skipped: since DC-05 T05 a card returned to a full hand burns in public,
## having been face up on its row.
func _opponent_leaks(events: Array[MatchEvent]) -> Array[String]:
	var found: Array[String] = []
	for event: MatchEvent in events:
		if not PRIVATE_KINDS.has(event.kind) or not event.is_private():
			continue
		for card: int in _event_card_ids(event):
			if card >= MatchRules.DECK_SIZE:
				found.append("event %d names card %d" % [event.kind, card])
	return found


## Seed 1 played bot-vs-bot straight through MatchEngine, as main.gd's smoke run plays it,
## written as the board's result line; a message naming the problem when it fails.
func _smoke_line() -> String:
	var engine: MatchEngine = MatchEngine.create(SEED, _db())
	if not engine.start().ok:
		return "smoke match did not start"
	var bots: Array[GreedyBot] = [
		GreedyBot.new(GreedyBot.seed_for(SEED, 0), _db()),
		GreedyBot.new(GreedyBot.seed_for(SEED, 1), _db()),
	]
	var ended: Dictionary = {}
	var actions: int = 0
	while not engine.is_over() and actions < MAX_ACTIONS:
		var seat: int = engine.awaited_seat()
		var action: EngineAction = bots[seat].choose(engine.view_for(seat), engine)
		var result: ApplyResult = engine.apply(action)
		if not result.ok:
			return "smoke action %d rejected" % actions
		actions += 1
		for event: MatchEvent in result.events:
			if event.kind == MatchEvent.Kind.MATCH_ENDED:
				ended = event.payload
	if ended.is_empty():
		return "smoke match did not end"
	var winner: int = ended["winner"]
	var reason: String = ended["reason"]
	var rounds: int = ended["rounds_played"]
	var raw_wins: Array = ended["wins"]
	var wins: Array[int] = []
	wins.assign(raw_wins)
	return (
		"Board: match ended seed=%d winner=%d wins=%d-%d rounds=%d end=%s actions=%d"
		% [SEED, winner, wins[0], wins[1], rounds, reason, actions]
	)


## True when `events` holds an event of `kind`.
func _has_kind(events: Array[MatchEvent], kind: int) -> bool:
	for event: MatchEvent in events:
		if event.kind == kind:
			return true
	return false


## The seat a prompt is open for in seat 0's view, or -1 when none is open.
func _prompted_seat(driver: MatchDriver) -> int:
	var prompt: Dictionary = driver.view().prompt
	if prompt.is_empty():
		return -1
	var seat: int = prompt.get("seat", -1)
	return seat


## A human-seat driver for `match_seed`, started and played until a prompt opens for seat 0
## (or the match ends, or the cap): seat 1 by play_bot(), seat 0 by submit_player() with
## the commit a GreedyBot of its own would choose. Null when a step was rejected.
func _drive_to_player_prompt(match_seed: int) -> MatchDriver:
	var driver: MatchDriver = MatchDriver.create(match_seed, _db(), false)
	driver.start()
	var bot: GreedyBot = GreedyBot.new(GreedyBot.seed_for(match_seed, 0), _db())
	var steps: int = 0
	while not driver.is_over() and steps < MAX_ACTIONS:
		if not driver.open_prompt().is_empty():
			return driver
		var result: ApplyResult = null
		if driver.bot_turn_due():
			result = driver.play_bot()
		else:
			result = driver.submit_player(bot.choose(driver.view(), driver._engine))
		if not result.ok:
			return null
		steps += 1
	return driver


# --- Tests ----------------------------------------------------------------------------


func test_seed_1_autoplay_equals_the_smoke_match() -> void:
	var driver: MatchDriver = MatchDriver.create(SEED, _db(), true)
	assert_bool(driver.autoplay).is_true()
	assert_int(driver.match_seed).is_equal(SEED)
	assert_str(driver.result_line()).is_empty()
	var leaks: Array[String] = _opponent_leaks(driver.start())
	var steps: int = 0
	while driver.bot_turn_due() and steps < MAX_ACTIONS:
		var result: ApplyResult = driver.play_bot()
		assert_bool(result.ok).override_failure_message("action %d rejected" % steps).is_true()
		if not result.ok:
			return
		leaks.append_array(_opponent_leaks(driver.last_events()))
		steps += 1
	assert_bool(driver.is_over()).override_failure_message("not over after %d" % steps).is_true()
	assert_bool(driver.bot_turn_due()).is_false()
	var expected: String = EXPECTED_LINE
	if expected == "":
		expected = _smoke_line()
	assert_str(driver.result_line()).is_equal(expected)
	assert_int(driver.action_count()).is_equal(steps)
	# R6: across the whole match, no seat-1 card id reached seat 0.
	assert_array(leaks).override_failure_message("leaks: %s" % [leaks]).is_empty()


func test_seat_0_concede_ends_the_match_with_concede() -> void:
	var driver: MatchDriver = MatchDriver.create(SEED, _db(), false)
	var started: Array[MatchEvent] = driver.start()
	assert_bool(started.is_empty()).is_false()
	assert_str(driver.result_line()).is_empty()
	var result: ApplyResult = driver.submit_player(EngineAction.concede(0))
	assert_bool(result.ok).is_true()
	assert_bool(driver.is_over()).is_true()
	assert_bool(driver.bot_turn_due()).is_false()
	var line: String = driver.result_line()
	assert_bool(line.contains("end=concede")).override_failure_message(line).is_true()
	assert_bool(line.contains("winner=1")).override_failure_message(line).is_true()


func test_bot_turn_is_due_exactly_when_seat_0_is_not_awaited() -> void:
	var driver: MatchDriver = MatchDriver.create(SEED, _db(), false)
	assert_bool(driver.autoplay).is_false()
	driver.start()
	var passes: int = 0
	var bot_moves: int = 0
	var steps: int = 0
	while not driver.is_over() and steps < 100:
		var awaited: int = driver.view().awaited_seat
		assert_bool(driver.bot_turn_due()).is_equal(awaited != 0)
		var result: ApplyResult = null
		if driver.bot_turn_due():
			result = driver.play_bot()
			bot_moves += 1
		else:
			var none: Array[int] = []
			result = driver.submit_player(EngineAction.commit(0, none))
			passes += 1
		assert_bool(result.ok).override_failure_message("step %d rejected" % steps).is_true()
		if not result.ok:
			return
		steps += 1
	assert_int(passes).is_greater(0)
	assert_int(bot_moves).is_greater(0)


func test_play_bot_refuses_when_the_human_is_awaited() -> void:
	var driver: MatchDriver = MatchDriver.create(SEED, _db(), false)
	driver.start()
	# Play bot turns until seat 0 is awaited, then ask for a bot action anyway.
	var steps: int = 0
	while driver.bot_turn_due() and steps < MAX_ACTIONS:
		assert_bool(driver.play_bot().ok).is_true()
		steps += 1
	assert_bool(driver.is_over()).is_false()
	var refused: ApplyResult = driver.play_bot()
	assert_bool(refused.ok).is_false()
	assert_int(refused.error).is_equal(EngineError.Code.WRONG_SEAT)


## A bot's prompt (DC-05 T07): play_bot() answers it with a CHOICE action the engine
## accepts, and seat 0 sees the CHOICE_MADE. open_prompt() is seat 0's prompt only: empty
## while seat 1 is prompted, set while seat 0 is. Stops at the first answered prompt.
func test_play_bot_answers_a_bot_prompt() -> void:
	var answered: int = 0
	for match_seed: int in range(1, PROMPT_SEEDS + 1):
		var driver: MatchDriver = MatchDriver.create(match_seed, _db(), true)
		driver.start()
		var steps: int = 0
		while driver.bot_turn_due() and steps < MAX_ACTIONS:
			var prompted: int = _prompted_seat(driver)
			if prompted == 1:
				assert_dict(driver.open_prompt()).is_empty()
			elif prompted == 0:
				assert_bool(driver.open_prompt().is_empty()).is_false()
			var result: ApplyResult = driver.play_bot()
			var where: String = "seed %d action %d" % [match_seed, steps]
			assert_bool(result.ok).override_failure_message(where + " rejected").is_true()
			if not result.ok:
				return
			if prompted >= 0:
				answered += 1
				var made: bool = _has_kind(driver.last_events(), MatchEvent.Kind.CHOICE_MADE)
				assert_bool(made).override_failure_message(where + ": no CHOICE_MADE").is_true()
			steps += 1
			if answered > 0:
				break
		if answered > 0:
			break
	assert_int(answered).override_failure_message("no bot prompt in the seeds").is_greater(0)


## Seat 0's prompt (DC-05 T07): with no prompt open submit_choice() fails with NO_PROMPT;
## once one opens, open_prompt() gives its zone and options, an option it does not offer
## fails with NOT_ELIGIBLE and changes nothing, and an offered option is accepted.
func test_submit_choice_answers_the_open_player_prompt() -> void:
	var idle: MatchDriver = MatchDriver.create(SEED, _db(), false)
	idle.start()
	assert_dict(idle.open_prompt()).is_empty()
	var early: ApplyResult = idle.submit_choice(Choice.Zone.OWN_HAND, 0)
	assert_bool(early.ok).is_false()
	assert_int(early.error).is_equal(EngineError.Code.NO_PROMPT)
	var driver: MatchDriver = null
	for match_seed: int in range(1, PROMPT_SEEDS + 1):
		var candidate: MatchDriver = _drive_to_player_prompt(match_seed)
		var rejected: String = "seed %d: a step was rejected" % match_seed
		assert_bool(candidate != null).override_failure_message(rejected).is_true()
		if candidate != null and not candidate.open_prompt().is_empty():
			driver = candidate
			break
	assert_object(driver).override_failure_message("no seat-0 prompt in the seeds").is_not_null()
	if driver == null:
		return
	var prompt: Dictionary = driver.open_prompt()
	var seat: int = prompt.get("seat", -1)
	assert_int(seat).is_equal(MatchDriver.PLAYER_SEAT)
	assert_int(_prompted_seat(driver)).is_equal(MatchDriver.PLAYER_SEAT)
	assert_bool(driver.bot_turn_due()).is_false()
	var zone: int = prompt.get(Choice.KEY_ZONE, Choice.NO_ZONE)
	var options: Array[int] = Choice.options_of(prompt)
	assert_int(options.size()).is_greater_equal(2)
	assert_bool(options.has(NOT_AN_OPTION)).is_false()
	var count: int = driver.action_count()
	var refused: ApplyResult = driver.submit_choice(zone, NOT_AN_OPTION)
	assert_bool(refused.ok).is_false()
	assert_int(refused.error).is_equal(EngineError.Code.NOT_ELIGIBLE)
	assert_int(driver.action_count()).is_equal(count)
	assert_dict(driver.open_prompt()).is_equal(prompt)
	var answered: ApplyResult = driver.submit_choice(zone, options[0])
	assert_bool(answered.ok).is_true()
	assert_int(driver.action_count()).is_equal(count + 1)
	var made: bool = _has_kind(driver.last_events(), MatchEvent.Kind.CHOICE_MADE)
	assert_bool(made).override_failure_message("no CHOICE_MADE for seat 0").is_true()
