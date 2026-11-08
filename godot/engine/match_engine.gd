class_name MatchEngine
extends RefCounted
## The match entry point: create from a seed, the card pool, the deck list and a deck id per
## seat (every definition then comes from MatchCards), start() once, then apply() actions.
## Each accepted call runs the match to the next point that needs a seat's decision and
## returns every event on the way, in order (R4).
##
## Rules version 7 (cycle 9 plan P14; DC-13 T03). The rules of a Turn outside the Walk are
## TurnFlow's, the Walk is ScoreWalk's and the arithmetic Scoring's; this class validates
## actions and sequences them:
## start(): MATCH_STARTED, Match start (TurnFlow.start_match: both Decks shuffled once, four
## cards dealt), Round 1, Turn 1 -> commit (first, face down) -> its On commit and
## discard-down (TurnFlow.after_commit; a discard-down prompt is phase AWAIT_CHOICE until the
## seat's CHOOSE_SET answers it) -> commit (second; both Commits merge into their rows) -> its
## On commit and discard-down -> the Walk (ScoreWalk; a prompt pauses it) -> turn end
## (TurnFlow.end_turn) -> the next Turn, or after Turn 7 Round end (TurnFlow.end_round) ->
## the match end checks (_after_round). Concede goes straight to _end_match().
##
## Randomness: one MatchRng seeded from the match seed. Match start draws seat 0's shuffle
## then seat 1's; Round 1 draws the coin flip for the first committer; the card abilities
## and Crew (TriggerQueue, Abilities, CrewAbilities) draw from the same stream as they
## resolve.
##
## An illegal action returns a failure code and changes nothing: no state, no events, no
## accepted action (R9). Nothing here prints, asserts or pushes an error.
##
## Commits are positional. A commit with cards and no slots takes the compatibility default
## (EngineAction): its slots resolve to the row's right end when it is validated, and the
## resolved slots are what the state, the COMMITTED event and the action log hold.

## The seat count, owned here only (TurnFlow, SeatView and the tools read it; NSC-177).
const SEATS: int = 2
const REASON_WINS: String = "wins"
const REASON_ROUNDS: String = "rounds"
const REASON_SUDDEN_DEATH: String = "sudden_death"
const REASON_STALEMATE: String = "stalemate"
const REASON_CONCEDE: String = "concede"

## The match's definitions by instance id; built by create() only when the pool, the list
## and both deck ids are good, else an empty MatchCards.
var _cards: MatchCards = MatchCards.new()
## Why start() must fail (EngineError.Code), decided by create(); NONE when it may start.
var _setup_error: int = EngineError.Code.NONE
var _rng: MatchRng = null
var _state: MatchState = null
## Every accepted action in order, copied; the ActionLog is built from this.
var _accepted: Array[EngineAction] = []
## Events of the call in progress.
var _events: Array[MatchEvent] = []


## A match on `match_seed` where seat s plays the deck `deck_ids[s]` of `decks`, its cards
## from the pool `cards` and its three Crew from the Crew pool `crew`. An empty id resolves
## to DeckList.seeded_pick(match_seed, seat), so deck_ids() and the log hold the resolved
## ids. Never fails here: a bad pool, Crew pool or list makes start() fail with
## CARD_DATA_INVALID, and an id the list does not hold (or a `deck_ids` other than one id
## per seat) with DECK_UNKNOWN.
static func create(
	match_seed: int, cards: CardDb, decks: DeckList, ids: Array[String], crew: CrewPool
) -> MatchEngine:
	var engine: MatchEngine = MatchEngine.new()
	engine._rng = MatchRng.new(match_seed)
	engine._state = MatchState.new(match_seed)
	engine._state.rng_state = engine._rng.state
	var resolved: Array[String] = _resolved_deck_ids(match_seed, decks, ids)
	engine._state.deck_ids.assign(resolved)
	engine._setup_error = _deck_problem(cards, decks, crew, ids.size(), resolved)
	if engine._setup_error == EngineError.Code.NONE:
		engine._cards = MatchCards.build(cards, decks, resolved, crew)
		if not engine._cards.is_valid():
			engine._setup_error = EngineError.Code.CARD_DATA_INVALID
	return engine


## TRAINING ONLY, never for live play (cycle 11 R24, plan P5): an engine around `state`,
## which it keeps as its own (pass a MatchState.duplicate(), as Rollout.determinize does),
## with a copy of `cards` (MatchCards.copy(), so cards created here are never recorded on
## the original), a fresh MatchRng seeded `rng_seed` written into `state.rng_state` (P7)
## and no accepted action, so its action_log() does not replay to its state. It accepts
## actions from the state's decision point on. start() fails on a `cards` that is null or
## failed its build (CARD_DATA_INVALID); a started `state` refuses start() as any match.
static func from_state(state: MatchState, cards: MatchCards, rng_seed: int) -> MatchEngine:
	var engine: MatchEngine = MatchEngine.new()
	engine._rng = MatchRng.new(rng_seed)
	engine._state = state
	engine._state.rng_state = engine._rng.state
	if cards != null:
		engine._cards = cards.copy()
	if not engine._cards.is_valid() or engine._cards.size() == 0:
		engine._setup_error = EngineError.Code.CARD_DATA_INVALID
	return engine


## Starts the match and runs to the first decision point. Not logged: it is fully determined
## by the seed and the deck ids. Its first event is MATCH_STARTED {decks, crew}. Fails with
## CARD_DATA_INVALID on a failed pool or deck list, DECK_UNKNOWN on a deck id the list does
## not hold, and MALFORMED when the match has already started; either way nothing changes.
func start() -> ApplyResult:
	if _setup_error != EngineError.Code.NONE:
		return ApplyResult.failure(_setup_error)
	if _state.phase != MatchState.Phase.NOT_STARTED:
		return ApplyResult.failure(EngineError.Code.MALFORMED)
	_events.clear()
	# The seed stays out of every event: it would predict each shuffle.
	var crew: Array = [_cards.crew_ids(0), _cards.crew_ids(1)]
	var decks: Array = MatchState.plain_strings(_state.deck_ids)
	_emit(MatchEvent.Kind.MATCH_STARTED, {"decks": decks, "crew": crew})
	TurnFlow.start_match(_state, _cards, _rng, _emit)
	_begin_round()
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
		var picked: Array[int] = [accepted.index]
		_answer(accepted.zone, picked, false)
	elif accepted.kind == EngineAction.Kind.CHOOSE_SET:
		_answer(accepted.zone, accepted.indices, false)
	elif accepted.kind == EngineAction.Kind.DECLINE:
		var none: Array[int] = []
		_answer(Choice.NO_ZONE, none, true)
	else:
		_commit(accepted.seat, accepted.cards, accepted.slots)
	_state.rng_state = _rng.state
	return ApplyResult.success(_events)


## The seat whose decision is awaited: the committer, or while a prompt is open the
## prompted seat; -1 before start() and once the match is over.
func awaited_seat() -> int:
	if _state.phase == MatchState.Phase.AWAIT_FIRST:
		return _state.first_seat
	if _state.phase == MatchState.Phase.AWAIT_SECOND:
		return 1 - _state.first_seat
	if _state.phase == MatchState.Phase.AWAIT_CHOICE:
		return _prompt_seat()
	return -1


## A copy of the open prompt (MatchState.prompt, plan P12), or {} when none is open. It
## names no hidden card: options are positions (Choice) and the source is revealed (or a
## Crew, which is public).
func open_prompt() -> Dictionary:
	return _state.prompt.duplicate(true)


func is_over() -> bool:
	return _state.phase == MatchState.Phase.OVER


## Both seats' Round wins, indexed by seat: a copy of what full_state()["wins"] holds,
## read without serializing the match (Rollout's outcomes, NSC-211). Public.
func round_wins() -> Array[int]:
	var out: Array[int] = []
	out.assign(_state.wins)
	return out


## The match result's winner: the seat that won, or -1 for a draw or while the match is
## in progress (full_state()["result"]["winner"], read without serializing). Public.
func match_winner() -> int:
	var held: int = _state.result.get("winner", -1)
	return held


## The Turn number: every seat's base Energy (R6); 0 before start().
func energy() -> int:
	return _state.turn


## `seat`'s Budget this Turn (R6, R7): TurnFlow.budget, the Turn plus the Energy granted for
## it. 0 for a seat other than 0 or 1.
func budget_for(seat: int) -> int:
	return TurnFlow.budget(_state, _cards, seat)


## Both seats' Budgets, indexed by seat.
func budgets() -> Array[int]:
	var out: Array[int] = [budget_for(0), budget_for(1)]
	return out


## `seat`'s Hand size now (R11): TurnFlow.hand_size. The base for a seat other than 0 or 1.
func hand_size_for(seat: int) -> int:
	return TurnFlow.hand_size(_state, _cards, seat)


## The redacted view for seat 0 or 1 (R57): no seed, no Deck order and no id from the
## opponent's hand, Deck or face-down Commit. Null for any other seat.
func view_for(seat: int) -> SeatView:
	if seat < 0 or seat >= SEATS:
		return null
	return SeatView.build(_state, seat, awaited_seat(), _cards)


## The full-state read, for tests and replay only: it includes hidden information,
## everything view_for() omits (seed, stream state, Decks, hands, pending). Its `dross`
## lists the Dross cards still in the Match, instance id to {def, owner}, from their one
## record in MatchCards (DC-20 T03, NSC-179); an expired card is gone from it.
func full_state() -> Dictionary:
	var out: Dictionary = _state.to_dict()
	out["dross"] = _dross_dict()
	return out


## A deep copy of the full state (MatchState.duplicate()), for the training entry (Rollout)
## and tests only: like full_state() it holds hidden information.
func state_copy() -> MatchState:
	return _state.duplicate()


## The replayable log: this match's seed, its resolved deck ids and copies of its accepted
## actions only.
func action_log() -> ActionLog:
	return ActionLog.create(_state.match_seed, _state.deck_ids, _accepted)


## The deck id each seat plays, indexed by seat, as resolved by create(). A copy.
func deck_ids() -> Array[String]:
	var out: Array[String] = []
	out.assign(_state.deck_ids)
	return out


## The match's definitions by instance id, for the bot and the board; an empty MatchCards
## when start() would fail.
func match_cards() -> MatchCards:
	return _cards


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
## Order: match status, then shape, then the per-kind check.
func _check(action: EngineAction) -> int:
	if _state.phase == MatchState.Phase.NOT_STARTED:
		return EngineError.Code.NOT_STARTED
	if _state.phase == MatchState.Phase.OVER:
		return EngineError.Code.MATCH_OVER
	if not _is_well_formed(action):
		return EngineError.Code.MALFORMED
	return _check_kind(action)


## The per-kind check of a well-formed action in a running match.
func _check_kind(action: EngineAction) -> int:
	match action.kind:
		EngineAction.Kind.CONCEDE:
			# Either seat may concede at any time.
			return EngineError.Code.NONE
		EngineAction.Kind.CHOOSE:
			return _check_choice(action)
		EngineAction.Kind.CHOOSE_SET:
			return _check_set(action)
		EngineAction.Kind.DECLINE:
			return _check_decline(action)
	return _check_commit(action)


## A prompt is open (NO_PROMPT) and the action is the prompted seat's (WRONG_SEAT).
func _check_prompted(action: EngineAction) -> int:
	if _state.phase != MatchState.Phase.AWAIT_CHOICE or _state.prompt.is_empty():
		return EngineError.Code.NO_PROMPT
	if action.seat != _prompt_seat():
		return EngineError.Code.WRONG_SEAT
	return EngineError.Code.NONE


## A well-formed choice: _check_prompted, then its zone and index are one of the options of
## a single-target prompt (NOT_ELIGIBLE, which a CHOOSE on a multi-select also returns).
func _check_choice(action: EngineAction) -> int:
	var code: int = _check_prompted(action)
	if code != EngineError.Code.NONE:
		return code
	if Choice.is_multi_prompt(_state.prompt):
		return EngineError.Code.NOT_ELIGIBLE
	if not Choice.is_offered(_state.prompt, action.zone, action.index):
		return EngineError.Code.NOT_ELIGIBLE
	return EngineError.Code.NONE


## A well-formed set choice: _check_prompted, the prompt is a multi-select (else
## NOT_ELIGIBLE), and the set is in the prompt's zone, every index one of its options, none
## repeated, and its size the prompt's `exact` and at least its `min` (BAD_SET; R14: the
## discard-down takes exactly the excess).
func _check_set(action: EngineAction) -> int:
	var code: int = _check_prompted(action)
	if code != EngineError.Code.NONE:
		return code
	if not Choice.is_multi_prompt(_state.prompt):
		return EngineError.Code.NOT_ELIGIBLE
	if not Choice.is_valid_set(_state.prompt, action.zone, action.indices):
		return EngineError.Code.BAD_SET
	return EngineError.Code.NONE


## A well-formed decline: _check_prompted and the prompt is optional (NOT_OPTIONAL), or a
## single-target prompt that offers nothing, which no choice could answer (NSC-177).
func _check_decline(action: EngineAction) -> int:
	var code: int = _check_prompted(action)
	if code != EngineError.Code.NONE:
		return code
	if Choice.is_optional_prompt(_state.prompt):
		return EngineError.Code.NONE
	if not Choice.is_multi_prompt(_state.prompt) and Choice.options_of(_state.prompt).is_empty():
		return EngineError.Code.NONE
	return EngineError.Code.NOT_OPTIONAL


## A well-formed commit: the awaited committer (while a prompt is open every commit fails
## with WRONG_SEAT), then LegalPlays.validate_with over the hand's effective costs and the
## seat's Budget (R8, R9).
func _check_commit(action: EngineAction) -> int:
	if _state.phase == MatchState.Phase.AWAIT_CHOICE or action.seat != awaited_seat():
		return EngineError.Code.WRONG_SEAT
	var piles: MatchState.SeatPiles = _state.seats[action.seat]
	return LegalPlays.validate_with(
		action.cards,
		_resolved_slots(action),
		piles.hand,
		Scoring.effective_costs(piles.hand, _state, _cards),
		piles.board.size(),
		budget_for(action.seat),
		_state.energy.free_first[action.seat]
	)


## A commit's explicit slots: its own, or for the compatibility default (cards with no
## slots) the right end of the seat's row.
func _resolved_slots(action: EngineAction) -> Array[int]:
	if not action.slots.is_empty() or action.cards.is_empty():
		var own: Array[int] = []
		own.assign(action.slots)
		return own
	var piles: MatchState.SeatPiles = _state.seats[action.seat]
	return LegalPlays.append_slots(piles.board.size(), action.cards.size())


## Not null, a known kind, a seat of 0 or 1, no cards or slots on a concede, a decline or
## a (set) choice, and no set on anything but a set choice.
func _is_well_formed(action: EngineAction) -> bool:
	if action == null or action.seat < 0 or action.seat >= SEATS:
		return false
	if action.kind == EngineAction.Kind.CHOOSE_SET:
		return action.cards.is_empty() and action.slots.is_empty()
	if not action.indices.is_empty():
		return false
	if action.kind == EngineAction.Kind.COMMIT:
		return true
	var bare: bool = action.cards.is_empty() and action.slots.is_empty()
	return bare and EngineAction.Kind.values().has(action.kind)


# --- The flow -------------------------------------------------------------------------


func _begin_round() -> void:
	TurnFlow.begin_round(_state, _rng, _emit)
	_begin_turn()


## Turn start; a drain paused on a prompt (T05, T07) leaves the phase AWAIT_CHOICE.
func _begin_turn() -> void:
	if TurnFlow.begin_turn(_state, _cards, _rng, _emit):
		_state.phase = MatchState.Phase.AWAIT_CHOICE


## An accepted Commit: TurnFlow.accept_commit, then its On commit and discard-down.
func _commit(seat: int, picked: Array[int], slots: Array[int]) -> void:
	TurnFlow.accept_commit(_state, _cards, _emit, seat, picked, slots)
	if TurnFlow.after_commit(_state, _cards, _rng, _emit, seat):
		_state.phase = MatchState.Phase.AWAIT_CHOICE
		return
	_commit_done(seat)


## `seat`'s Commit step is complete (its discard-down done): the second seat is awaited
## after the first's, and the Walk starts after the second's.
func _commit_done(seat: int) -> void:
	_state.phase = MatchState.Phase.AWAIT_SECOND
	if seat == _state.first_seat:
		return
	ScoreWalk.begin(_state)
	_emit(MatchEvent.Kind.WALK_STARTED, {"first_seat": _state.first_seat})
	_run_walk()


## The Walk: pulses until it ends (WALK_ENDED), then turn end. A pulse finding an open
## prompt pauses it here: phase AWAIT_CHOICE, the prompted seat awaited.
func _run_walk() -> void:
	while _state.walk.active:
		if ScoreWalk.step(_state, _cards, _rng, _emit):
			_state.phase = MatchState.Phase.AWAIT_CHOICE
			return
	_end_turn()


## An accepted answer to the open prompt: positions `indices` of `zone`, or the decline.
## The discard-down is TurnFlow's and resumes its Commit (unless its D4 or D6 drain paused);
## a prompt a drain paused on resumes that drain at the same entry (TriggerQueue.answer).
## Any other prompt (none in play: every ability prompt is a paused drain's; the tests open
## one by hand) closes through Abilities (CHOICE_MADE or CHOICE_DECLINED). Either way the
## match then goes on through _resume_after: the step after the drain point, or the
## prompt's own `resume` and `step` (NSC-177).
func _answer(zone: int, indices: Array[int], declined: bool) -> void:
	if TurnFlow.is_discard_down(_state.prompt):
		var seat: int = _prompt_seat()
		if TurnFlow.answer_discard_down(_state, _cards, _rng, _emit, indices):
			_state.phase = MatchState.Phase.AWAIT_CHOICE
		else:
			_commit_done(seat)
		return
	_state.phase = MatchState.Phase.AWAIT_SECOND
	if _state.queue.is_paused():
		if TriggerQueue.answer(_state, _cards, _rng, _emit, zone, indices, declined):
			_state.phase = MatchState.Phase.AWAIT_CHOICE
			return
		var drain_step: String = _state.queue.step
		var resume: String = TriggerQueue.RESUME_OF_STEP.get(drain_step, "")
		_resume_after(resume, drain_step, _state.queue.seat)
		return
	var own_resume: String = Choice.resume_of(_state.prompt)
	var own_step: String = Choice.step_of(_state.prompt)
	var asked: int = _prompt_seat()
	if declined:
		_events.append_array(Abilities.decline(_state))
	else:
		_events.append_array(Abilities.answer(_state, zone, indices))
	_resume_after(own_resume, own_step, asked)


## Resumes the match per `resume` once the prompt at drain point `step` (for `seat`) is
## answered and its drain, if any, has finished (DC-13 T05, plan P12 `resume`): turn start
## goes on with its draws and On start, a Commit with its discard-down, the Walk with the
## pulse's score stage after a D7 and the next pulse, turn end with its next step, Round end
## with the award. A drain that pauses again leaves the phase AWAIT_CHOICE. Every
## Choice.RESUMES value has a branch (test_engine.gd pins it, NSC-177), and Choice.resume_of
## maps an unknown `resume` to RESUME_WALK, so no answered prompt is left awaiting nobody.
func _resume_after(resume: String, step: String, seat: int) -> void:
	if resume == Choice.RESUME_TURN_START:
		_state.phase = MatchState.Phase.AWAIT_FIRST
		if TurnFlow.continue_turn_start(_state, _cards, _rng, _emit, step, seat):
			_state.phase = MatchState.Phase.AWAIT_CHOICE
	elif resume == Choice.RESUME_COMMIT:
		var commit_drain: bool = (
			step == TurnFlow.STEP_FIRST_COMMIT or step == TurnFlow.STEP_SECOND_COMMIT
		)
		if commit_drain and TurnFlow.open_discard_down(_state, _cards, _emit, seat):
			_state.phase = MatchState.Phase.AWAIT_CHOICE
		else:
			_commit_done(seat)
	elif resume == Choice.RESUME_WALK:
		if step == ScoreWalk.STEP_REVEAL and ScoreWalk.resume_pulse(_state, _cards, _rng, _emit):
			_state.phase = MatchState.Phase.AWAIT_CHOICE
		else:
			_run_walk()
	elif resume == Choice.RESUME_TURN_END:
		if TurnFlow.continue_end_turn(_state, _cards, _rng, _emit, step):
			_state.phase = MatchState.Phase.AWAIT_CHOICE
		else:
			_turn_over()
	elif resume == Choice.RESUME_ROUND_END:
		_after_round(TurnFlow.award_round(_state, _cards, _emit))


## The open prompt's seat, or -1 when none is open.
func _prompt_seat() -> int:
	if _state.prompt.is_empty():
		return -1
	var seat: int = _state.prompt.get(Abilities.KEY_SEAT, -1)
	return seat


## Turn end (TurnFlow.end_turn), then the next Turn, or after Turn 7 the Round end.
func _end_turn() -> void:
	if TurnFlow.end_turn(_state, _cards, _rng, _emit):
		_state.phase = MatchState.Phase.AWAIT_CHOICE
		return
	_turn_over()


## After turn end: the next Turn, or after Turn 7 the Round end (its D12 drain may pause on
## a prompt: the Round is awarded once it has finished, _resume_after).
func _turn_over() -> void:
	if _state.turn >= MatchRules.TURNS:
		var winner: int = TurnFlow.end_round(_state, _cards, _rng, _emit)
		if winner == TurnFlow.ROUND_PAUSED:
			_state.phase = MatchState.Phase.AWAIT_CHOICE
			return
		_after_round(winner)
	else:
		_begin_turn()


# --- Match end ------------------------------------------------------------------------


## Match end checks after a Round (R1), in this order:
## - a won sudden-death Round ends the match, reason sudden_death;
## - a seat on 4 wins ends it, reason wins;
## - after Round 7, the seat with more wins takes it, reason rounds;
## - a tied sudden-death Round ends it, reason stalemate, when both Decks and hands are
##   empty (spec C12) or when neither seat committed a card all Round (rules 8, cycle 13 C9
##   (Ben, 2026-11-08)): the higher Match total Score wins, equal totals draw (winner -1).
## Otherwise the next Round starts; past Round 7 it is a sudden-death Round. A match end
## leaves the table as it stands.
func _after_round(winner: int) -> void:
	var played: int = _state.round_number
	if _state.sudden_death:
		if winner >= 0:
			_end_match(winner, REASON_SUDDEN_DEATH, played)
			return
		if _stalled():
			_end_match(TurnFlow.leader(_state.match_scores), REASON_STALEMATE, played)
			return
	elif winner >= 0 and _state.wins[winner] >= MatchRules.WINS_TO_TAKE:
		_end_match(winner, REASON_WINS, played)
		return
	elif _state.round_number >= MatchRules.ROUNDS:
		var leader: int = TurnFlow.leader(_state.wins)
		if leader >= 0:
			_end_match(leader, REASON_ROUNDS, played)
			return
	_begin_round()


## Stalemate after a tied sudden-death Round, when either:
## - (Ben, spec C12) both Decks and both hands are empty and no seat can refill (review 3a:
##   a seat whose Crew shuffles its Pile in on an empty draw, with a non-empty Pile, can
##   still play); or
## - (rules 8, cycle 13 C9 (Ben, 2026-11-08)) neither seat committed a card all Round
##   (`round_committed` 0), whatever the seats still hold. A tied Round with any card
##   committed goes on to the next Round.
## The higher Match total Score (`match_scores`) takes the Match; equal totals draw.
func _stalled() -> bool:
	if _state.round_committed == 0:
		return true
	for seat: int in range(_state.seats.size()):
		var held: MatchState.SeatPiles = _state.seats[seat]
		if not held.deck.is_empty() or not held.hand.is_empty():
			return false
		if not held.pile.is_empty() and _refills_from_pile(seat):
			return false
	return true


## True when `seat` has a Crew that shuffles its Pile into its Deck (Dredger).
func _refills_from_pile(seat: int) -> bool:
	return CrewAbilities.crew_with(_cards, seat, CrewAbilities.VERB_DREDGE) != null


## Concede: the other seat wins at once, whoever was awaited. A concede always falls inside
## a Round, and that unfinished Round does not count as played.
func _concede(seat: int) -> void:
	_emit(MatchEvent.Kind.CONCEDED, {"seat": seat})
	_end_match(1 - seat, REASON_CONCEDE, _state.round_number - 1)


## Ends the match. `rounds_played` counts completed Rounds, sudden death included, so it
## equals the number of ROUND_ENDED events in the match. The table is left as it stands.
## Every later action fails with MATCH_OVER.
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
			"wins": MatchState.plain(_state.wins),
			"rounds_played": rounds_played,
		}
	)


# --- Decks ----------------------------------------------------------------------------


## `deck_ids` with each empty id replaced by the seat's seeded pick, when `decks` loaded;
## otherwise unchanged. Seats beyond SEATS are not looked at.
static func _resolved_deck_ids(
	match_seed: int, decks: DeckList, ids: Array[String]
) -> Array[String]:
	var out: Array[String] = []
	for seat: int in range(mini(ids.size(), SEATS)):
		var deck_id: String = ids[seat]
		if deck_id == "" and decks != null and decks.is_valid():
			deck_id = decks.seeded_pick(match_seed, seat)
		out.append(deck_id)
	return out


## Why a match on these inputs cannot start (an EngineError.Code), or NONE: a failed or
## missing pool, or a deck list that failed to load or to validate against it and the Crew
## pool `crew`, is CARD_DATA_INVALID; a `deck_ids` that does not name one deck per seat, or
## names one the list does not hold, is DECK_UNKNOWN.
static func _deck_problem(
	cards: CardDb, decks: DeckList, crew: CrewPool, requested: int, resolved: Array[String]
) -> int:
	if cards == null or not cards.is_valid() or decks == null:
		return EngineError.Code.CARD_DATA_INVALID
	if decks.validate(cards, crew) != "":
		return EngineError.Code.CARD_DATA_INVALID
	if requested != SEATS:
		return EngineError.Code.DECK_UNKNOWN
	for deck_id: String in resolved:
		if not decks.has_deck(deck_id):
			return EngineError.Code.DECK_UNKNOWN
	return EngineError.Code.NONE


func _emit(kind: int, payload: Dictionary, owner: int = MatchEvent.PUBLIC) -> void:
	_events.append(MatchEvent.new(kind, payload, owner))


## The Dross cards still recorded (MatchCards.def_of() not null), ascending id up to the
## state's next_dross_id: instance id to {def: its pool id, owner: its Owner's seat}.
## Empty without definitions (a failed setup).
func _dross_dict() -> Dictionary:
	var out: Dictionary = {}
	if _cards == null:
		return out
	for card: int in range(MatchCards.DROSS_BASE, _state.next_dross_id):
		var def: CardDef = _cards.def_of(card)
		if def != null:
			out[card] = {"def": def.id, "owner": _cards.origin_of(card)}
	return out
