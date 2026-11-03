class_name MatchEngine
extends RefCounted
## The match entry point (R3, C1): create from a seed and the card data, start() once,
## then apply() actions. Each accepted call runs the match to the next point that needs a
## seat's decision and returns every event on the way, in order (R4).
##
## Flow: _begin_round() -> _begin_turn() -> commit (first, face down) -> commit (second)
## -> _reveal() -> _end_turn() -> next _begin_turn(), or after turn 7 _end_round() ->
## _after_round(). Concede goes straight to _end_match().
##
## Randomness: one MatchRng seeded from the match seed. Each round start draws seat 0's
## shuffle, seat 1's shuffle, then a coin flip only while no round has been won (plan,
## replay contract). Nothing else touches the stream.
##
## An illegal action returns a failure code and changes nothing: no state, no events, no
## accepted action (R26). Nothing here prints, asserts or pushes an error (R27).

const SEATS: int = 2
const REASON_WINS: String = "wins"
const REASON_ROUNDS: String = "rounds"
const REASON_SUDDEN_DEATH: String = "sudden_death"
const REASON_CONCEDE: String = "concede"

var _cards: CardDb = null
var _rng: MatchRng = null
var _state: MatchState = null
## Every accepted action in order, copied; T07's ActionLog is built from this.
var _accepted: Array[EngineAction] = []
## Events of the call in progress.
var _events: Array[MatchEvent] = []


static func create(match_seed: int, cards: CardDb) -> MatchEngine:
	var engine: MatchEngine = MatchEngine.new()
	engine._cards = cards
	engine._rng = MatchRng.new(match_seed)
	engine._state = MatchState.new(match_seed)
	engine._state.rng_state = engine._rng.state
	return engine


## Deals round 1 and runs to the first decision point. Not logged: it is fully determined
## by the seed. Fails with CARD_DATA_INVALID on failed card data (R8) and MALFORMED when
## the match has already started; either way nothing changes.
func start() -> ApplyResult:
	if _cards == null or not _cards.is_valid():
		return ApplyResult.failure(EngineError.Code.CARD_DATA_INVALID)
	if _state.phase != MatchState.Phase.NOT_STARTED:
		return ApplyResult.failure(EngineError.Code.MALFORMED)
	_events.clear()
	_begin_round()
	_begin_turn()
	_state.rng_state = _rng.state
	return ApplyResult.success(_events)


func apply(action: EngineAction) -> ApplyResult:
	var code: int = _check(action)
	if code != EngineError.Code.NONE:
		return ApplyResult.failure(code)
	_events.clear()
	_accepted.append(action.copy())
	_state.actions_applied += 1
	if action.kind == EngineAction.Kind.CONCEDE:
		_concede(action.seat)
	else:
		_commit(action.seat, action.cards)
	_state.rng_state = _rng.state
	return ApplyResult.success(_events)


## The seat whose commit is awaited; -1 before start() and once the match is over.
func awaited_seat() -> int:
	if _state.phase == MatchState.Phase.AWAIT_FIRST:
		return _state.first_seat
	if _state.phase == MatchState.Phase.AWAIT_SECOND:
		return 1 - _state.first_seat
	return -1


func is_over() -> bool:
	return _state.phase == MatchState.Phase.OVER


## This turn's energy (R13): equal to the turn number; 0 before start().
func energy() -> int:
	return _state.turn


## The full-state read (R30), for tests and replay only: it includes hidden information.
func full_state() -> Dictionary:
	return _state.to_dict()


func accepted_action_count() -> int:
	return _accepted.size()


## Copies of the accepted actions, in order.
func accepted_actions() -> Array[EngineAction]:
	var out: Array[EngineAction] = []
	for action: EngineAction in _accepted:
		out.append(action.copy())
	return out


# --- Validation -----------------------------------------------------------------------


## EngineError.Code.NONE when the action may be applied now.
## Order: match status, then shape, then (commits only) seat, then LegalPlays.validate.
func _check(action: EngineAction) -> int:
	if _state.phase == MatchState.Phase.NOT_STARTED:
		return EngineError.Code.NOT_STARTED
	if _state.phase == MatchState.Phase.OVER:
		return EngineError.Code.MATCH_OVER
	if not _is_well_formed(action):
		return EngineError.Code.MALFORMED
	if action.kind == EngineAction.Kind.CONCEDE:
		# Either seat may concede at any time (R23).
		return EngineError.Code.NONE
	if action.seat != awaited_seat():
		return EngineError.Code.WRONG_SEAT
	var piles: MatchState.SeatPiles = _state.seats[action.seat]
	return LegalPlays.validate(action.cards, piles.hand, energy(), _cards)


## Not null, a known kind, a seat of 0 or 1, and no cards on a concede.
func _is_well_formed(action: EngineAction) -> bool:
	if action == null or action.seat < 0 or action.seat >= SEATS:
		return false
	if action.kind == EngineAction.Kind.CONCEDE:
		return action.cards.is_empty()
	return action.kind == EngineAction.Kind.COMMIT


# --- Rounds ---------------------------------------------------------------------------


## Round start (R11): refill and shuffle both decks (seat 0 first), pick turn 1's first
## committer, clear both boards, deal the opening hands.
func _begin_round() -> void:
	_state.round_number += 1
	_state.sudden_death = _state.round_number > MatchRules.ROUNDS
	_state.turn = 0
	_state.scores[0] = 0
	_state.scores[1] = 0
	_state.last_turn_winner = -1
	_state.pending.clear()
	for seat: int in range(SEATS):
		var piles: MatchState.SeatPiles = _state.seats[seat]
		piles.deck.clear()
		for index: int in range(MatchRules.DECK_SIZE):
			piles.deck.append(seat * MatchRules.DECK_SIZE + index)
		piles.hand.clear()
		piles.board.clear()
		piles.burned.clear()
		_rng.shuffle_in_place(piles.deck)
	var by_coin: bool = _state.last_round_winner < 0
	_state.first_seat = _round_first_seat()
	_emit(
		MatchEvent.Kind.ROUND_STARTED,
		{
			"round": _state.round_number,
			"sudden_death": _state.sudden_death,
			"first_seat": _state.first_seat,
			"first_by_coin": by_coin,
		}
	)
	for seat: int in range(SEATS):
		for _deal: int in range(MatchRules.OPENING_HAND):
			_deal_card(seat)


## Turn 1's first committer (R18, C9). The most recent round winner goes second; before
## any round is won, a coin flip from the engine stream decides. T05 owns and tests the
## rule beyond round 1; this is the only coin flip in the engine.
func _round_first_seat() -> int:
	if _state.last_round_winner >= 0:
		return 1 - _state.last_round_winner
	return _rng.coin_flip()


## Round end (R19, R24): the higher board wins the round; equal boards award no win.
func _end_round() -> void:
	var winner: int = _leader()
	if winner >= 0:
		_state.wins[winner] += 1
		_state.last_round_winner = winner
	_emit(
		MatchEvent.Kind.ROUND_ENDED,
		{
			"round": _state.round_number,
			"scores": _pair(_state.scores),
			"winner": winner,
			"wins": _pair(_state.wins),
		}
	)
	_after_round()


## T05 seam: decide whether the match ends (R20-R22, via _end_match) before starting the
## next round. Until T05 lands, every round leads to the next.
func _after_round() -> void:
	_begin_round()
	_begin_turn()


# --- Turns ----------------------------------------------------------------------------


## Turn start (R12, R13, R17): set the first committer, then draw 1 card per seat.
func _begin_turn() -> void:
	_state.turn += 1
	if _state.turn > 1 and _state.last_turn_winner >= 0:
		_state.first_seat = _state.last_turn_winner
	_state.phase = MatchState.Phase.AWAIT_FIRST
	_emit(
		MatchEvent.Kind.TURN_STARTED,
		{
			"round": _state.round_number,
			"turn": _state.turn,
			"energy": energy(),
			"first_seat": _state.first_seat,
		}
	)
	for seat: int in range(SEATS):
		_draw_card(seat)


## The two-step commit (R14, R15). The first commit is held face down in `pending`.
func _commit(seat: int, cards: Array[int]) -> void:
	var committed: Array[int] = []
	committed.assign(cards)
	var piles: MatchState.SeatPiles = _state.seats[seat]
	for card: int in committed:
		piles.hand.erase(card)
	_emit(
		MatchEvent.Kind.COMMITTED,
		{"seat": seat, "count": committed.size(), "cards": MatchState.plain(committed)},
		seat
	)
	if _state.phase == MatchState.Phase.AWAIT_FIRST:
		_state.pending.assign(committed)
		_state.phase = MatchState.Phase.AWAIT_SECOND
		return
	var first_cards: Array[int] = []
	first_cards.assign(_state.pending)
	_state.pending.clear()
	_reveal(first_cards, committed)
	_end_turn()


## Reveal (R15): alternate first committer's card 1, second's card 1, first's card 2, and
## so on; when one list runs out the other reveals the rest in order.
func _reveal(first_cards: Array[int], second_cards: Array[int]) -> void:
	var first: int = _state.first_seat
	var second: int = 1 - first
	var order: int = 0
	var longest: int = maxi(first_cards.size(), second_cards.size())
	for i: int in range(longest):
		if i < first_cards.size():
			_reveal_card(first, first_cards[i], order)
			order += 1
		if i < second_cards.size():
			_reveal_card(second, second_cards[i], order)
			order += 1


## Scoring (R16): each board score is the power on that side; the higher one wins the turn.
func _end_turn() -> void:
	for seat: int in range(SEATS):
		_state.scores[seat] = _board_power(seat)
	var winner: int = _leader()
	_state.last_turn_winner = winner
	_emit(
		MatchEvent.Kind.TURN_ENDED,
		{
			"round": _state.round_number,
			"turn": _state.turn,
			"scores": _pair(_state.scores),
			"winner": winner,
		}
	)
	if _state.turn >= MatchRules.TURNS:
		_end_round()
	else:
		_begin_turn()


# --- Match end ------------------------------------------------------------------------


## Concede (R23): the other seat wins at once, whoever was awaited.
func _concede(seat: int) -> void:
	_emit(MatchEvent.Kind.CONCEDED, {"seat": seat})
	_end_match(1 - seat, REASON_CONCEDE)


## Ends the match (R25). T05 calls this for the wins, rounds and sudden-death endings.
func _end_match(winner: int, reason: String) -> void:
	_state.phase = MatchState.Phase.OVER
	_state.result = {
		"winner": winner,
		"reason": reason,
		"rounds_played": _state.round_number,
	}
	_emit(
		MatchEvent.Kind.MATCH_ENDED,
		{
			"winner": winner,
			"reason": reason,
			"wins": _pair(_state.wins),
			"rounds_played": _state.round_number,
		}
	)


# --- Cards ----------------------------------------------------------------------------


func _deal_card(seat: int) -> void:
	var piles: MatchState.SeatPiles = _state.seats[seat]
	if piles.deck.is_empty():
		return
	var card: int = piles.deck[0]
	piles.deck.remove_at(0)
	piles.hand.append(card)
	_emit(MatchEvent.Kind.CARD_DEALT, {"seat": seat, "card": card}, seat)


## Draw (R12): the top card goes to the hand, or is burned when the hand is at the cap.
func _draw_card(seat: int) -> void:
	var piles: MatchState.SeatPiles = _state.seats[seat]
	if piles.deck.is_empty():
		return
	var card: int = piles.deck[0]
	piles.deck.remove_at(0)
	if piles.hand.size() >= MatchRules.HAND_CAP:
		piles.burned.append(card)
		_emit(MatchEvent.Kind.CARD_BURNED, {"seat": seat, "card": card}, seat)
		return
	piles.hand.append(card)
	_emit(MatchEvent.Kind.CARD_DRAWN, {"seat": seat, "card": card}, seat)


func _reveal_card(seat: int, card: int, order: int) -> void:
	var piles: MatchState.SeatPiles = _state.seats[seat]
	piles.board.append(card)
	var def: CardDef = _cards.card_at(card % MatchRules.DECK_SIZE)
	var def_id: String = ""
	var power: int = 0
	if def != null:
		def_id = def.id
		power = def.power
	_emit(
		MatchEvent.Kind.CARD_REVEALED,
		{"seat": seat, "card": card, "def_id": def_id, "power": power, "order": order}
	)


func _board_power(seat: int) -> int:
	var piles: MatchState.SeatPiles = _state.seats[seat]
	var total: int = 0
	for card: int in piles.board:
		var def: CardDef = _cards.card_at(card % MatchRules.DECK_SIZE)
		if def != null:
			total += def.power
	return total


## The seat with the higher board score, or -1 when they are equal.
func _leader() -> int:
	if _state.scores[0] > _state.scores[1]:
		return 0
	if _state.scores[1] > _state.scores[0]:
		return 1
	return -1


func _pair(values: Array[int]) -> Array:
	return [values[0], values[1]]


func _emit(kind: int, payload: Dictionary, owner: int = MatchEvent.PUBLIC) -> void:
	_events.append(MatchEvent.new(kind, payload, owner))
