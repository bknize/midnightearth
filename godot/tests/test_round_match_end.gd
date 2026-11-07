class_name TestRoundMatchEnd
extends GdUnitTestSuite
## MatchEngine Round and Match end under rules 7 (cycle 9 R1 to R3; DC-13 T03): a Round is
## won by the seat with more Turn wins (spec C13) and a tied Round awards none (R1);
## Round end sends both rows to their Owners' Piles (R2); the first committer of a Round's
## Turn 1 is the previous Round's loser, after a tied Round the seat that did not commit
## first on its last Turn, and a coin flip only in Round 1 (R3); four wins end the Match,
## after Round 7 more wins take it, and level seats play sudden-death Rounds; a concede ends
## it at once; `rounds_played` counts the ROUND_ENDED events; every later action fails with
## MATCH_OVER.
##
## Round outcomes come from real actions: both seats pass turns 1-6 (each pass answering its
## discard-down), and on Turn 7 the chosen winner commits one card (every fixture card is
## affordable at 7 Energy and has Power >= 1) while the other passes. A Round where
## everyone passes is a 0-0 tie.

const SEED: int = 1
const TIE: int = -1

var _cached_db: CardDb = null
var _cached_defs: MatchCards = null

# --- Helpers --------------------------------------------------------------------------


func _db() -> CardDb:
	if _cached_db == null:
		_cached_db = FixtureDecks.cards()
	return _cached_db


func _defs() -> MatchCards:
	if _cached_defs == null:
		_cached_defs = FixtureDecks.defs(_db())
	return _cached_defs


func _typed(values: Array) -> Array[int]:
	var out: Array[int] = []
	out.assign(values)
	return out


func _started(match_seed: int) -> MatchEngine:
	var engine: MatchEngine = FixtureDecks.engine(match_seed, _db())
	engine.start()
	return engine


func _seat_list(engine: MatchEngine, key: String, seat: int) -> Array[int]:
	var state: Dictionary = engine.full_state()
	var per_seat: Array = state[key]
	var raw: Array = per_seat[seat]
	return _typed(raw)


func _state_ints(engine: MatchEngine, key: String) -> Array[int]:
	var state: Dictionary = engine.full_state()
	var raw: Array = state[key]
	return _typed(raw)


func _state_int(engine: MatchEngine, key: String) -> int:
	var state: Dictionary = engine.full_state()
	var value: int = state[key]
	return value


func _payload_int(event: MatchEvent, key: String) -> int:
	var value: int = event.payload[key]
	return value


func _payload_bool(event: MatchEvent, key: String) -> bool:
	var value: bool = event.payload[key]
	return value


func _payload_str(event: MatchEvent, key: String) -> String:
	var value: String = event.payload[key]
	return value


func _payload_ints(event: MatchEvent, key: String) -> Array[int]:
	var raw: Array = event.payload[key]
	return _typed(raw)


func _kinds(events: Array[MatchEvent]) -> Array[int]:
	var out: Array[int] = []
	for event: MatchEvent in events:
		out.append(event.kind)
	return out


func _of_kind(events: Array[MatchEvent], kind: int) -> Array[MatchEvent]:
	var out: Array[MatchEvent] = []
	for event: MatchEvent in events:
		if event.kind == kind:
			out.append(event)
	return out


## The last event of a kind; fails the test (and returns a blank event) when none exists.
func _last(events: Array[MatchEvent], kind: int) -> MatchEvent:
	var found: Array[MatchEvent] = _of_kind(events, kind)
	if found.is_empty():
		fail("no event of kind %d" % kind)
		return MatchEvent.new()
	return found[found.size() - 1]


## The Score of `card` alone on a row: its Power times its Bonus value, rounded once.
func _alone(card: int) -> int:
	var stats: Scoring.Stats = Scoring.stats(card, MatchState.new(SEED), _defs())
	return Scoring.walk_score(Scoring.step_total(0, stats.power, stats.bonus_value()))


## Plays one Round to its end with real actions (see the suite comment); `winner` TIE makes
## every seat pass every Turn. Returns every event of the Round.
func _play_round(engine: MatchEngine, winner: int) -> Array[MatchEvent]:
	var seen: Array[MatchEvent] = []
	var round_number: int = _state_int(engine, "round")
	var guard: int = 0
	while not engine.is_over() and _state_int(engine, "round") == round_number and guard < 60:
		guard += 1
		var action: EngineAction = FixtureDecks.discard_answer(engine)
		if action == null:
			var seat: int = engine.awaited_seat()
			var cards: Array[int] = []
			if seat == winner and engine.energy() == MatchRules.TURNS:
				cards.append(_seat_list(engine, "hand", seat)[0])
			action = EngineAction.commit(seat, cards)
		var result: ApplyResult = engine.apply(action)
		if not result.ok:
			fail("round action rejected with code %d" % result.error)
			return seen
		seen.append_array(result.events)
	assert_int(_of_kind(seen, MatchEvent.Kind.ROUND_ENDED).size()).is_equal(1)
	var ended: MatchEvent = _last(seen, MatchEvent.Kind.ROUND_ENDED)
	assert_int(_payload_int(ended, "winner")).is_equal(winner)
	return seen


## Plays one Round per outcome, in order; returns every event on the way.
func _play_rounds(engine: MatchEngine, outcomes: Array[int]) -> Array[MatchEvent]:
	var seen: Array[MatchEvent] = []
	for winner: int in outcomes:
		seen.append_array(_play_round(engine, winner))
	return seen


## The first committer of the Round in progress (its Turn 1's TURN_STARTED `first_seat`).
func _round_first_seat(events: Array[MatchEvent]) -> int:
	var kinds: Array[int] = _kinds(events)
	var at: int = kinds.rfind(MatchEvent.Kind.ROUND_STARTED)
	for index: int in range(at + 1, events.size()):
		if events[index].kind == MatchEvent.Kind.TURN_STARTED:
			return _payload_int(events[index], "first_seat")
	return -1


## Checks the MATCH_ENDED payload, the full-state result and that the match is over.
func _assert_match_ended(
	engine: MatchEngine,
	events: Array[MatchEvent],
	winner: int,
	reason: String,
	wins: Array[int],
	rounds_played: int
) -> void:
	assert_int(_of_kind(events, MatchEvent.Kind.MATCH_ENDED).size()).is_equal(1)
	var ended: MatchEvent = _last(events, MatchEvent.Kind.MATCH_ENDED)
	assert_int(ended.owner_seat).is_equal(MatchEvent.PUBLIC)
	assert_int(_payload_int(ended, "winner")).is_equal(winner)
	assert_str(_payload_str(ended, "reason")).is_equal(reason)
	assert_array(_payload_ints(ended, "wins")).is_equal(wins)
	assert_int(_payload_int(ended, "rounds_played")).is_equal(rounds_played)
	assert_int(events[events.size() - 1].kind).is_equal(MatchEvent.Kind.MATCH_ENDED)
	assert_int(_of_kind(events, MatchEvent.Kind.ROUND_ENDED).size()).is_equal(rounds_played)
	assert_bool(engine.is_over()).is_true()
	assert_int(engine.awaited_seat()).is_equal(-1)
	assert_array(_state_ints(engine, "wins")).is_equal(wins)
	var state: Dictionary = engine.full_state()
	var result: Dictionary = state["result"]
	assert_dict(result).is_equal(
		{"winner": winner, "reason": reason, "rounds_played": rounds_played}
	)


## Every action fails with MATCH_OVER and changes nothing.
func _assert_all_rejected_as_over(engine: MatchEngine) -> void:
	var none: Array[int] = []
	var actions: Array[EngineAction] = [
		EngineAction.commit(0, none),
		EngineAction.commit(1, none),
		EngineAction.concede(0),
		EngineAction.concede(1),
		null,
	]
	for action: EngineAction in actions:
		var before: Dictionary = engine.full_state()
		var count: int = engine.accepted_action_count()
		var result: ApplyResult = engine.apply(action)
		assert_bool(result.ok).is_false()
		assert_int(result.error).is_equal(EngineError.Code.MATCH_OVER)
		assert_array(result.events).is_empty()
		assert_dict(engine.full_state()).is_equal(before)
		assert_int(engine.accepted_action_count()).is_equal(count)


# --- R1, R2: Round end ----------------------------------------------------------------


## A won Round: Turn 7 ends with the winner's Score, the row card goes to its Owner's Pile
## as a public Discard (reason round_end), ROUND_ENDED {winner, wins, round, scores}, then
## Round 2 starts with no deal and runs to its Turn 1 draws. Hands stay; rows are empty.
func test_won_round_payload_and_flow_into_the_next_round() -> void:
	var engine: MatchEngine = _started(SEED)
	var events: Array[MatchEvent] = _play_round(engine, 1)
	var reveals: Array[MatchEvent] = _of_kind(events, MatchEvent.Kind.CARD_REVEALED)
	assert_int(reveals.size()).is_equal(1)
	var played: int = _payload_int(reveals[0], "card")
	var score: int = _alone(played)
	assert_int(score).is_greater(0)
	var ended: MatchEvent = _last(events, MatchEvent.Kind.ROUND_ENDED)
	assert_int(ended.owner_seat).is_equal(MatchEvent.PUBLIC)
	assert_int(_payload_int(ended, "round")).is_equal(1)
	assert_array(_payload_ints(ended, "scores")).is_equal(_typed([0, score]))
	assert_array(_payload_ints(ended, "wins")).is_equal(_typed([0, 1]))
	assert_array(_state_ints(engine, "wins")).is_equal(_typed([0, 1]))
	assert_int(_state_int(engine, "last_round_winner")).is_equal(1)
	var kinds: Array[int] = _kinds(events)
	var at: int = kinds.rfind(MatchEvent.Kind.ROUND_ENDED)
	var cleared: MatchEvent = events[at - 1]
	assert_int(cleared.kind).is_equal(MatchEvent.Kind.CARD_DISCARDED)
	assert_int(cleared.owner_seat).is_equal(MatchEvent.PUBLIC)
	assert_dict(cleared.payload).is_equal(
		{
			"owner": 1,
			"card": played,
			"from": "row",
			"reason": "round_end",
			"pile_index": _seat_list(engine, "pile", 1).find(played),
		}
	)
	var turn_ended: MatchEvent = events[at - 2]
	assert_int(turn_ended.kind).is_equal(MatchEvent.Kind.TURN_ENDED)
	assert_int(_payload_int(turn_ended, "turn")).is_equal(MatchRules.TURNS)
	assert_array(_payload_ints(turn_ended, "scores")).is_equal(_typed([0, score]))
	var expected_tail: Array[int] = [
		MatchEvent.Kind.ROUND_STARTED,
		MatchEvent.Kind.TURN_STARTED,
		MatchEvent.Kind.CARD_DRAWN,
		MatchEvent.Kind.CARD_DRAWN,
	]
	assert_array(_typed(kinds.slice(at + 1))).is_equal(expected_tail)
	assert_int(_state_int(engine, "round")).is_equal(2)
	assert_int(_state_int(engine, "turn")).is_equal(1)
	assert_array(_state_ints(engine, "scores")).is_equal(_typed([0, 0]))
	for seat: int in range(2):
		assert_array(_seat_list(engine, "board", seat)).is_empty()
		assert_int(_seat_list(engine, "hand", seat).size()).is_equal(MatchRules.HAND_SIZE + 1)
	assert_bool(_seat_list(engine, "pile", 1).has(played)).is_true()
	assert_array(_state_ints(engine, "pending")).is_empty()


func test_tied_round_awards_no_win() -> void:
	var engine: MatchEngine = _started(SEED)
	var events: Array[MatchEvent] = _play_round(engine, TIE)
	var ended: MatchEvent = _last(events, MatchEvent.Kind.ROUND_ENDED)
	assert_int(_payload_int(ended, "round")).is_equal(1)
	assert_array(_payload_ints(ended, "scores")).is_equal(_typed([0, 0]))
	assert_int(_payload_int(ended, "winner")).is_equal(-1)
	assert_array(_payload_ints(ended, "wins")).is_equal(_typed([0, 0]))
	assert_int(_state_int(engine, "last_round_winner")).is_equal(-1)
	assert_int(_state_int(engine, "round")).is_equal(2)


## C13 (Ben, 2a): the Round goes to the seat with more Turn wins, not the higher last Walk.
## Seat 0 commits one card on each of Turns 1 and 2 while seat 1 passes, so seat 0's row
## Scores and wins Turns 1 to 6; seat 1 commits its strongest card on Turn 7 and wins that
## Walk. Seat 0 takes the Round on Turn wins (6-1) whoever had the higher last Walk.
func test_more_turn_wins_take_the_round_over_the_last_walk() -> void:
	var engine: MatchEngine = _started(SEED)
	var defs: MatchCards = engine.match_cards()
	var seen: Array[MatchEvent] = []
	var guard: int = 0
	while not engine.is_over() and _state_int(engine, "round") == 1 and guard < 60:
		guard += 1
		var action: EngineAction = FixtureDecks.discard_answer(engine)
		if action == null:
			var seat: int = engine.awaited_seat()
			var turn: int = _state_int(engine, "turn")
			var plays: bool = (seat == 0 and turn <= 2) or (seat == 1 and turn == MatchRules.TURNS)
			var cards: Array[int] = []
			if plays:
				var best: int = -1
				var best_power: int = 0
				for card: int in _seat_list(engine, "hand", seat):
					var def: CardDef = defs.def_of(card)
					if def.cost <= engine.budget_for(seat) and def.power > best_power:
						best = card
						best_power = def.power
				if best >= 0:
					cards.append(best)
			action = EngineAction.commit(seat, cards)
		var result: ApplyResult = engine.apply(action)
		assert_bool(result.ok).is_true()
		seen.append_array(result.events)
	var ended: MatchEvent = _last(seen, MatchEvent.Kind.ROUND_ENDED)
	var turn_wins: Array[int] = _payload_ints(ended, "turn_wins")
	var scores: Array[int] = _payload_ints(ended, "scores")
	assert_array(turn_wins).is_equal(_typed([6, 1]))
	assert_int(scores[1]).is_greater(scores[0])
	assert_int(_payload_int(ended, "winner")).is_equal(0)


# --- R3: who commits first ------------------------------------------------------------


## The previous Round's loser commits first on Turn 1.
func test_the_round_loser_commits_first_on_turn_1() -> void:
	for winner: int in range(2):
		var engine: MatchEngine = _started(SEED)
		var events: Array[MatchEvent] = _play_round(engine, winner)
		assert_int(_round_first_seat(events)).is_equal(1 - winner)
		assert_int(engine.awaited_seat()).is_equal(1 - winner)


## After a tied Round the alternation goes on from its last Turn (C25): every Turn of an
## all-pass Round is tied, so its last Turn's first committer is Round 1's, and Round 2
## starts with the other seat. A tie after a won Round alternates from that Round's last.
func test_after_a_tied_round_the_alternation_continues() -> void:
	var engine: MatchEngine = _started(SEED)
	var coin: int = engine.awaited_seat()
	var events: Array[MatchEvent] = _play_round(engine, TIE)
	assert_int(_round_first_seat(events)).is_equal(1 - coin)
	events = _play_round(engine, coin)
	# Round 2's loser (1 - coin) goes first in Round 3, then a tie hands Round 4 to coin.
	assert_int(_round_first_seat(events)).is_equal(1 - coin)
	events = _play_round(engine, TIE)
	assert_int(_round_first_seat(events)).is_equal(coin)


## The engine stream draws Match start's two shuffles and Round 1's coin, and nothing else
## through Rounds that are won or tied.
func test_the_coin_flips_only_in_round_1() -> void:
	var rng: MatchRng = MatchRng.new(SEED)
	var deck: Array[int] = []
	for index: int in range(MatchRules.DECK_SIZE):
		deck.append(index)
	rng.shuffle_in_place(deck)
	rng.shuffle_in_place(deck)
	var coin: int = rng.coin_flip()
	var engine: MatchEngine = _started(SEED)
	assert_int(engine.awaited_seat()).is_equal(coin)
	assert_int(_state_int(engine, "rng_state")).is_equal(rng.state)
	_play_rounds(engine, _typed([TIE, 0, TIE]))
	assert_int(_state_int(engine, "rng_state")).is_equal(rng.state)


# --- Match end ------------------------------------------------------------------------


func test_four_straight_wins_end_the_match() -> void:
	var engine: MatchEngine = FixtureDecks.engine(SEED, _db())
	var events: Array[MatchEvent] = engine.start().events
	events.append_array(_play_rounds(engine, _typed([0, 0, 0, 0])))
	_assert_match_ended(engine, events, 0, MatchEngine.REASON_WINS, _typed([4, 0]), 4)
	_assert_all_rejected_as_over(engine)


func test_four_wins_after_ties_end_the_match_early() -> void:
	var engine: MatchEngine = FixtureDecks.engine(SEED, _db())
	var events: Array[MatchEvent] = engine.start().events
	events.append_array(_play_rounds(engine, _typed([TIE, 1, TIE, 1, 1, 1])))
	_assert_match_ended(engine, events, 1, MatchEngine.REASON_WINS, _typed([0, 4]), 6)


func test_more_wins_after_round_7_take_the_match() -> void:
	var engine: MatchEngine = FixtureDecks.engine(SEED, _db())
	var events: Array[MatchEvent] = engine.start().events
	events.append_array(_play_rounds(engine, _typed([0, 1, 0, 1, 0, TIE, TIE])))
	_assert_match_ended(engine, events, 0, MatchEngine.REASON_ROUNDS, _typed([3, 2]), 7)


## 3-3 after Round 7 goes to sudden death: Round 8 starts with `sudden_death`, a tied
## sudden-death Round starts another, and the first won one ends the Match.
func test_level_after_round_7_plays_sudden_death_until_a_win() -> void:
	var engine: MatchEngine = FixtureDecks.engine(SEED, _db())
	var events: Array[MatchEvent] = engine.start().events
	events.append_array(_play_rounds(engine, _typed([0, 1, 0, 1, 0, 1, TIE])))
	assert_bool(engine.is_over()).is_false()
	var started: MatchEvent = _last(events, MatchEvent.Kind.ROUND_STARTED)
	assert_int(_payload_int(started, "round")).is_equal(8)
	assert_bool(_payload_bool(started, "sudden_death")).is_true()
	events.append_array(_play_rounds(engine, _typed([TIE, 0])))
	_assert_match_ended(engine, events, 0, MatchEngine.REASON_SUDDEN_DEATH, _typed([4, 3]), 9)


# --- Concede --------------------------------------------------------------------------


## A concede by the seat that is not awaited ends the Match at once; the unfinished Round
## is not counted.
func test_concede_by_the_waiting_seat_ends_the_match() -> void:
	var engine: MatchEngine = _started(SEED)
	var events: Array[MatchEvent] = _play_rounds(engine, _typed([1]))
	var waiting: int = 1 - engine.awaited_seat()
	var result: ApplyResult = engine.apply(EngineAction.concede(waiting))
	assert_bool(result.ok).is_true()
	events.append_array(result.events)
	assert_array(_kinds(result.events)).is_equal(
		_typed([MatchEvent.Kind.CONCEDED, MatchEvent.Kind.MATCH_ENDED])
	)
	assert_int(_payload_int(result.events[0], "seat")).is_equal(waiting)
	var wins: Array[int] = [0, 1]
	_assert_match_ended(engine, events, 1 - waiting, MatchEngine.REASON_CONCEDE, wins, 1)
	_assert_all_rejected_as_over(engine)


## A concede while a discard-down is open ends the Match and closes the prompt.
func test_concede_while_a_discard_down_is_open() -> void:
	var engine: MatchEngine = _started(SEED)
	var none: Array[int] = []
	var seat: int = engine.awaited_seat()
	assert_bool(engine.apply(EngineAction.commit(seat, none)).ok).is_true()
	assert_dict(engine.open_prompt()).is_not_empty()
	var result: ApplyResult = engine.apply(EngineAction.concede(seat))
	assert_bool(result.ok).is_true()
	assert_bool(engine.is_over()).is_true()
	assert_dict(engine.open_prompt()).is_empty()
	var ended: MatchEvent = _last(result.events, MatchEvent.Kind.MATCH_ENDED)
	assert_int(_payload_int(ended, "winner")).is_equal(1 - seat)
	assert_int(_payload_int(ended, "rounds_played")).is_equal(0)


## After the Match ends the rows are in the Piles (the last Round end Discarded them) and
## the hands stay; each seat's view lists both Piles in full.
func test_the_final_round_end_leaves_the_rows_in_the_piles() -> void:
	var engine: MatchEngine = _started(SEED)
	var events: Array[MatchEvent] = _play_rounds(engine, _typed([0, 0, 0, 0]))
	assert_bool(engine.is_over()).is_true()
	var played: Array[int] = []
	for event: MatchEvent in _of_kind(events, MatchEvent.Kind.CARD_REVEALED):
		played.append(_payload_int(event, "card"))
	assert_int(played.size()).is_equal(4)
	for seat: int in range(2):
		assert_array(_seat_list(engine, "board", seat)).is_empty()
		assert_int(_seat_list(engine, "hand", seat).size()).is_greater(0)
		var view: SeatView = engine.view_for(seat)
		assert_array(view.own_pile).is_equal(_seat_list(engine, "pile", seat))
		assert_array(view.opponent_pile).is_equal(_seat_list(engine, "pile", 1 - seat))
	for card: int in played:
		assert_bool(_seat_list(engine, "pile", 0).has(card)).is_true()


## Stalemate (spec C12): random bots on the fixture deck, seeds 1-20, every match ends; a
## stalemate ending comes after a tied sudden-death Round with both Decks and hands empty,
## and the winner is the higher Match total Score (-1 when level). At least one seed of the
## twenty reaches it (seed 5 did before the rule existed).
func test_a_stalemate_ends_on_the_match_total_score() -> void:
	var stalemates: int = 0
	for match_seed: int in range(1, 21):
		var engine: MatchEngine = FixtureDecks.engine(match_seed, _db())
		assert_bool(engine.start().ok).is_true()
		var bots: Array[RandomBot] = []
		for seat: int in range(MatchEngine.SEATS):
			bots.append(RandomBot.new(BotRegistry.seed_for(match_seed, seat), engine.match_cards()))
		var actions: int = 0
		while not engine.is_over() and actions < 2000:
			var seat: int = engine.awaited_seat()
			var action: EngineAction = bots[seat].choose(engine.view_for(seat), engine)
			assert_bool(engine.apply(action).ok).is_true()
			actions += 1
		assert_bool(engine.is_over()).is_true()
		var state: Dictionary = engine.full_state()
		var result: Dictionary = state["result"]
		var reason: String = result["reason"]
		if reason != MatchEngine.REASON_STALEMATE:
			continue
		stalemates += 1
		var sudden: bool = state["sudden_death"]
		assert_bool(sudden).is_true()
		for seat: int in range(MatchEngine.SEATS):
			assert_array(_seat_list(engine, "deck", seat)).is_empty()
			assert_array(_seat_list(engine, "hand", seat)).is_empty()
		var totals: Array[int] = _state_ints(engine, "match_scores")
		var expected: int = TurnFlow.leader(totals)
		var winner: int = result["winner"]
		assert_int(winner).is_equal(expected)
	assert_int(stalemates).is_greater(0)
