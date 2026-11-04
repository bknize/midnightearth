class_name MatchEngine
extends RefCounted
## The match entry point (R3, C1): create from a seed and the card data, start() once,
## then apply() actions. Each accepted call runs the match to the next point that needs a
## seat's decision and returns every event on the way, in order (R4).
##
## Flow: _begin_round() -> _begin_turn() -> commit (first, face down, with its slots) ->
## commit (second) -> _resolve() (both commits merge into their rows, then the walk starts)
## -> _run_walk() (ScoreWalk pulses every card on both rows; an effect with two or more
## targets pauses it on a prompt, phase AWAIT_CHOICE, until apply(CHOOSE) from the prompted
## seat resumes it, DC-05 T05) -> _end_turn() (return marks, energy) -> next
## _begin_turn(), or after turn 7 _end_round() ->
## _after_round(), which either ends the match (R20-R22) or begins the next round.
## Concede goes straight to _end_match().
##
## Randomness: one MatchRng seeded from the match seed. Each round start draws seat 0's
## shuffle, seat 1's shuffle, then a coin flip only while no round has been won (plan,
## replay contract). The only other draw is the random destroy (plan P11, R27): one
## pick_index at the moment the effect fires in the walk. Walk order is deterministic given
## the log, so ActionLog replay reproduces every destroy.
##
## Round boundaries (orchestrator, DC-05 T04): round start clears `energy.carry`,
## `energy.free_first` and `bonus_zero_pending` along with the rows, so an effect that
## fires in a round's last turn (a carry, a free first card, a bonus-0 mark) does nothing
## for the next round.
##
## An illegal action returns a failure code and changes nothing: no state, no events, no
## accepted action (R26). Nothing here prints, asserts or pushes an error (R27).
##
## Commits are positional (plan P1). A commit with cards and no slots takes the
## compatibility default (EngineAction): its slots resolve to the row's right end,
## row_size .. row_size + k - 1, when it is validated, and the resolved slots are what the
## state, the COMMITTED event and the action log hold.

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
	var accepted: EngineAction = action.copy()
	if accepted.kind == EngineAction.Kind.COMMIT:
		accepted.slots = _resolved_slots(accepted)
	_accepted.append(accepted.copy())
	_state.actions_applied += 1
	if accepted.kind == EngineAction.Kind.CONCEDE:
		_concede(accepted.seat)
	elif accepted.kind == EngineAction.Kind.CHOOSE:
		_choose(accepted.index)
	else:
		_commit(accepted.seat, accepted.cards, accepted.slots)
	_state.rng_state = _rng.state
	return ApplyResult.success(_events)


## The seat whose decision is awaited: the committer, or while a prompt is open the
## prompted seat (P9); -1 before start() and once the match is over.
func awaited_seat() -> int:
	if _state.phase == MatchState.Phase.AWAIT_FIRST:
		return _state.first_seat
	if _state.phase == MatchState.Phase.AWAIT_SECOND:
		return 1 - _state.first_seat
	if _state.phase == MatchState.Phase.AWAIT_CHOICE:
		return _prompt_seat()
	return -1


## A copy of the open prompt (plan P9: {seat, card, verb, zone, options}), or {} when none.
## It names no hidden card: options are positions (Choice) and the source is revealed.
func open_prompt() -> Dictionary:
	return _state.prompt.duplicate(true)


func is_over() -> bool:
	return _state.phase == MatchState.Phase.OVER


## This turn's base energy (R13): equal to the turn number; 0 before start(). A seat's
## actual budget adds its carry: budget_for().
func energy() -> int:
	return _state.turn


## `seat`'s energy budget this turn (R9): the turn number plus the energy an effect
## carried into this turn for that seat. 0 for a seat other than 0 or 1.
func budget_for(seat: int) -> int:
	if seat < 0 or seat >= SEATS:
		return 0
	return _state.turn + _state.energy.carry[seat]


## Both seats' budgets, indexed by seat (R9).
func budgets() -> Array[int]:
	var out: Array[int] = [budget_for(0), budget_for(1)]
	return out


## The redacted view for seat 0 or 1 (R28, R29): no seed, no deck order and no id from
## the opponent's hand, deck, face-down commit or burn. Null for any other seat.
func view_for(seat: int) -> SeatView:
	if seat < 0 or seat >= SEATS:
		return null
	return SeatView.build(_state, seat, awaited_seat(), budgets(), _cards)


## The full-state read (R30), for tests and replay only: it includes hidden information,
## everything view_for() omits (seed, stream state, decks, hands, pending, burns).
func full_state() -> Dictionary:
	return _state.to_dict()


## The replayable log (R31): this match's seed and copies of its accepted actions only.
func action_log() -> ActionLog:
	return ActionLog.create(_state.match_seed, _accepted)


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
## Order: match status, then shape, then (commits only) seat, then LegalPlays.validate
## with the resolved slots, the seat's row size, its budget and its free first card.
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
	if action.kind == EngineAction.Kind.CHOOSE:
		return _check_choice(action)
	return _check_commit(action)


## A well-formed choice (R31): a prompt is open (NO_PROMPT), the action is the prompted
## seat's (WRONG_SEAT) and its zone and index are one of the prompt's options
## (NOT_ELIGIBLE).
func _check_choice(action: EngineAction) -> int:
	if _state.phase != MatchState.Phase.AWAIT_CHOICE or _state.prompt.is_empty():
		return EngineError.Code.NO_PROMPT
	if action.seat != _prompt_seat():
		return EngineError.Code.WRONG_SEAT
	if not Choice.is_offered(_state.prompt, action.zone, action.index):
		return EngineError.Code.NOT_ELIGIBLE
	return EngineError.Code.NONE


## A well-formed commit: the awaited seat, then LegalPlays.validate. While a prompt is
## open the engine awaits a choice, so every commit fails with WRONG_SEAT.
func _check_commit(action: EngineAction) -> int:
	if _state.phase == MatchState.Phase.AWAIT_CHOICE or action.seat != awaited_seat():
		return EngineError.Code.WRONG_SEAT
	var piles: MatchState.SeatPiles = _state.seats[action.seat]
	return LegalPlays.validate(
		action.cards,
		_resolved_slots(action),
		piles.hand,
		piles.board.size(),
		budget_for(action.seat),
		_state.energy.free_first[action.seat],
		_cards
	)


## A commit's explicit slots: its own, or for the compatibility default (cards with no
## slots) the right end of the seat's row, row_size .. row_size + k - 1.
func _resolved_slots(action: EngineAction) -> Array[int]:
	if not action.slots.is_empty() or action.cards.is_empty():
		var own: Array[int] = []
		own.assign(action.slots)
		return own
	var piles: MatchState.SeatPiles = _state.seats[action.seat]
	return LegalPlays.append_slots(piles.board.size(), action.cards.size())


## Not null, a known kind, a seat of 0 or 1, and no cards or slots on a concede or a
## choice.
func _is_well_formed(action: EngineAction) -> bool:
	if action == null or action.seat < 0 or action.seat >= SEATS:
		return false
	if action.kind == EngineAction.Kind.CONCEDE or action.kind == EngineAction.Kind.CHOOSE:
		return action.cards.is_empty() and action.slots.is_empty()
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
	_state.pending_slots.clear()
	# The boards clear, so every card leaves them: their modifiers go too (plan, card_states).
	_state.card_states.clear()
	_state.walk = MatchState.WalkState.new()
	_state.prompt = {}
	# Effects do not reach across rounds (see the class comment).
	_state.energy = MatchState.EnergyState.new()
	_state.bonus_zero_pending[0] = false
	_state.bonus_zero_pending[1] = false
	for seat: int in range(SEATS):
		var piles: MatchState.SeatPiles = _state.seats[seat]
		piles.deck.clear()
		for index: int in range(MatchRules.DECK_SIZE):
			piles.deck.append(seat * MatchRules.DECK_SIZE + index)
		piles.hand.clear()
		piles.board.clear()
		piles.revealed.clear()
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


## Turn 1's first committer (R18, C9). The most recent round winner of the match goes
## second, looking past tied rounds and including sudden-death rounds; before any round is
## won, a coin flip from the engine stream decides. This is the only coin flip in the
## engine, so the stream is consumed by coins only until the first won round.
func _round_first_seat() -> int:
	if _state.last_round_winner >= 0:
		return 1 - _state.last_round_winner
	return _rng.coin_flip()


## Round end (R19, R24): the higher board wins the round; equal boards award no win. The
## event carries the turn-7 scores. The table is not cleared here (C15): when the match
## goes on, the next _begin_round() resets scores, pending, hands, boards, burns and decks;
## when this round ends the match, its boards, hands and scores stay as the final table.
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
	_after_round(winner)


## Match end checks after a round (R20-R22), in this order:
## - a won sudden-death round ends the match, reason sudden_death, even when that win is
##   the seat's fourth (3-3 after round 7 into a sudden-death win);
## - a seat on 4 wins ends it, reason wins;
## - after round 7, the seat with more wins takes it, reason rounds.
## Otherwise the next round starts; past round 7 it is a sudden-death round, so a tied
## sudden-death round starts another. A match end leaves the finished round's table in
## place (C15); only _begin_round() clears it.
func _after_round(winner: int) -> void:
	var played: int = _state.round_number
	if _state.sudden_death:
		if winner >= 0:
			_end_match(winner, REASON_SUDDEN_DEATH, played)
			return
	elif winner >= 0 and _state.wins[winner] >= MatchRules.WINS_TO_TAKE:
		_end_match(winner, REASON_WINS, played)
		return
	elif _state.round_number >= MatchRules.ROUNDS:
		var leader: int = _wins_leader()
		if leader >= 0:
			_end_match(leader, REASON_ROUNDS, played)
			return
	_begin_round()
	_begin_turn()


# --- Turns ----------------------------------------------------------------------------


## Turn start (R12, R13, R17, plan P14): set the first committer, clear this turn's
## spend, then draw 1 card per seat. `energy` is the base (the turn); `budgets` and
## `free_first` are per seat.
func _begin_turn() -> void:
	_state.turn += 1
	if _state.turn > 1 and _state.last_turn_winner >= 0:
		_state.first_seat = _state.last_turn_winner
	_state.phase = MatchState.Phase.AWAIT_FIRST
	_state.energy.spent[0] = 0
	_state.energy.spent[1] = 0
	var free: Array = []
	free.assign(_state.energy.free_first)
	_emit(
		MatchEvent.Kind.TURN_STARTED,
		{
			"round": _state.round_number,
			"turn": _state.turn,
			"energy": energy(),
			"budgets": _pair(budgets()),
			"free_first": free,
			"first_seat": _state.first_seat,
		}
	)
	for seat: int in range(SEATS):
		_draw_card(seat)


## The two-step commit (R5, R7, R14, R15). `slots` are explicit (already resolved). The
## commit's cost (with the free first card) is recorded in `energy.spent`, and the seat's
## free first card is consumed whether or not it was used (plan P7). The first commit is
## held face down in `pending` and `pending_slots`; the COMMITTED event's `slots` are
## public, its `cards` private.
func _commit(seat: int, cards: Array[int], slots: Array[int]) -> void:
	var committed: Array[int] = []
	committed.assign(cards)
	var committed_slots: Array[int] = []
	committed_slots.assign(slots)
	var piles: MatchState.SeatPiles = _state.seats[seat]
	for card: int in committed:
		piles.hand.erase(card)
	var cost: int = LegalPlays.commit_cost(committed, _state.energy.free_first[seat], _cards)
	_state.energy.spent[seat] = maxi(cost, 0)
	_state.energy.free_first[seat] = false
	_emit(
		MatchEvent.Kind.COMMITTED,
		{
			"seat": seat,
			"count": committed.size(),
			"cards": MatchState.plain(committed),
			"slots": MatchState.plain(committed_slots),
		},
		seat
	)
	if _state.phase == MatchState.Phase.AWAIT_FIRST:
		_state.pending.assign(committed)
		_state.pending_slots.assign(committed_slots)
		_state.phase = MatchState.Phase.AWAIT_SECOND
		return
	var first_cards: Array[int] = []
	first_cards.assign(_state.pending)
	var first_slots: Array[int] = []
	first_slots.assign(_state.pending_slots)
	_state.pending.clear()
	_state.pending_slots.clear()
	_resolve(first_cards, first_slots, committed, committed_slots)


## Resolution (R8, plan P2): both commits merge into their rows at their slots, first
## committer first, before anything is revealed or scored; then the walk runs.
func _resolve(
	first_cards: Array[int],
	first_slots: Array[int],
	second_cards: Array[int],
	second_slots: Array[int]
) -> void:
	var first: int = _state.first_seat
	_merge_into_row(first, first_cards, first_slots)
	_merge_into_row(1 - first, second_cards, second_slots)
	ScoreWalk.begin(_state)
	_emit(
		MatchEvent.Kind.WALK_STARTED,
		{"round": _state.round_number, "turn": _state.turn, "first_seat": _state.first_seat}
	)
	_run_walk()


## Places `cards` into `seat`'s row at their final slots (plan P1): walks the merged row's
## indices 0..n-1, taking the committed card whose slot matches, else the next card
## already on the row. Played cards keep their relative order.
func _merge_into_row(seat: int, cards: Array[int], slots: Array[int]) -> void:
	var piles: MatchState.SeatPiles = _state.seats[seat]
	var old_row: Array[int] = []
	old_row.assign(piles.board)
	var merged: Array[int] = []
	var next_new: int = 0
	var next_old: int = 0
	for slot: int in range(old_row.size() + cards.size()):
		if next_new < cards.size() and slots[next_new] == slot:
			merged.append(cards[next_new])
			next_new += 1
		elif next_old < old_row.size():
			merged.append(old_row[next_old])
			next_old += 1
	piles.board.assign(merged)


## The walk (R11-R17, plan P3): pulses until the walk ends, then ends the turn. Every walk
## recomputes every card on both rows, so cards played in earlier turns score again (they
## are already revealed: no second CARD_REVEALED). Effects fire inside the pulses
## (ScoreWalk, EffectResolver) with the engine stream and no preview policy, and their
## events reach `_events` through `_emit` with their owners. A pulse that opens a prompt
## (DC-05 T05) pauses the walk here: phase AWAIT_CHOICE, the prompted seat awaited, the
## turn not ended. _choose() applies the answer and calls this again, and the walk resumes
## in the same pulse (ScoreWalk.step).
func _run_walk() -> void:
	var sink: Callable = _emit
	while _state.walk.active:
		if ScoreWalk.step(_state, _cards, _rng, sink, null):
			_state.phase = MatchState.Phase.AWAIT_CHOICE
			return
	_end_turn()


## An accepted choice (R32, plan P3): the prompt closes, the choice applies (CHOICE_MADE and
## the verb's events), and the walk resumes where it paused. The phase returns to the one a
## walk runs in (AWAIT_SECOND) until the walk pauses again or the turn ends.
func _choose(index: int) -> void:
	_state.phase = MatchState.Phase.AWAIT_SECOND
	_events.append_array(EffectResolver.answer(_state, _cards, index))
	_run_walk()


## The open prompt's seat, or -1 when none is open.
func _prompt_seat() -> int:
	if _state.prompt.is_empty():
		return -1
	var seat: int = _state.prompt.get(EffectResolver.KEY_SEAT, -1)
	return seat


## Turn end (R17, R24, plan P14), only once the walk is complete: the return marks resolve
## first (EffectResolver.resolve_returns: each marked card goes back to its owner's hand,
## or burns at the cap), then per-seat energy is settled (EffectResolver.settle_energy: a
## revealed carry card on the row carries `budget - spent`, else the carry is 0, so a
## returned carry card carries nothing); then the scores are the walk totals and the higher
## one wins the turn, as cycle 1 R16 did from power.
func _end_turn() -> void:
	_events.append_array(EffectResolver.resolve_returns(_state))
	_events.append_array(EffectResolver.settle_energy(_state, _cards))
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


## Concede (R23): the other seat wins at once, whoever was awaited. A concede always falls
## inside a round, and that unfinished round does not count as played.
func _concede(seat: int) -> void:
	_emit(MatchEvent.Kind.CONCEDED, {"seat": seat})
	_end_match(1 - seat, REASON_CONCEDE, _state.round_number - 1)


## Ends the match (R25). `rounds_played` counts completed rounds, sudden death included,
## so it equals the number of ROUND_ENDED events in the match; a concede in round N
## reports N-1 (C14). The table is left as it stands (C15): hands, boards and scores of
## the last round, so view_for() shows the final table on every end path. Every later
## action fails with MATCH_OVER (_check).
func _end_match(winner: int, reason: String, rounds_played: int) -> void:
	_state.phase = MatchState.Phase.OVER
	# A concede can come while a prompt is open; nothing answers it any more.
	_state.prompt = {}
	_state.result = {
		"winner": winner,
		"reason": reason,
		"rounds_played": rounds_played,
	}
	_emit(
		MatchEvent.Kind.MATCH_ENDED,
		{
			"winner": winner,
			"reason": reason,
			"wins": _pair(_state.wins),
			"rounds_played": rounds_played,
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
## The same draw as the DRAW effect's (EffectResolver.draw_card, R25).
func _draw_card(seat: int) -> void:
	var drawn: MatchEvent = EffectResolver.draw_card(_state, seat)
	if drawn != null:
		_events.append(drawn)


## The seat with the higher board score, or -1 when they are equal.
func _leader() -> int:
	if _state.scores[0] > _state.scores[1]:
		return 0
	if _state.scores[1] > _state.scores[0]:
		return 1
	return -1


## The seat with more round wins, or -1 when they are level.
func _wins_leader() -> int:
	if _state.wins[0] > _state.wins[1]:
		return 0
	if _state.wins[1] > _state.wins[0]:
		return 1
	return -1


func _pair(values: Array[int]) -> Array:
	return [values[0], values[1]]


func _emit(kind: int, payload: Dictionary, owner: int = MatchEvent.PUBLIC) -> void:
	_events.append(MatchEvent.new(kind, payload, owner))
