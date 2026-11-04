class_name SeatView
extends RefCounted
## One seat's redacted view of a match (R28, R29, C4), built by MatchEngine.view_for().
##
## Holds both seats' deck ids (public, DC-07 R5), the seat's own hand and own face-down
## commit, both ordered rows, the opponent's hand and face-down commit counts and that
## commit's slots (R7), both deck counts, both
## board scores and walk multipliers, both round-win counts, both budgets, the round, the
## turn, the energy, the phase and the awaited seat. Each row also comes with every card's
## shown flat, ×-part and +-part and its revealed flag (own_row, opponent_row). Both
## destroyed piles in pile order (DC-07 P6): its own by id, the opponent's by id only where
## the identity is public (own_destroyed, opponent_destroyed).
##
## Never holds the match seed, the stream state, any deck order, or the id of any card in
## the opponent's hand, deck, face-down commit or burn pile, or of an opponent pile card that
## left its row face down. `free_first` is this seat's
## own free-first grant only. Seat-indexed pairs
## (deck_counts, scores, wins, budgets) are indexed by seat number, like MatchState.
##
## Every array is a copy: mutating a view never touches the engine's state.

var seat: int = 0
var opponent: int = 1
## The deck id each seat plays, indexed by seat (DC-07 R5, P2); public, like the picker.
var deck_ids: Array[String] = ["", ""]
## This seat's hand, in hand order.
var own_hand: Array[int] = []
## This seat's face-down commit while the opponent is awaited; empty otherwise.
var own_pending: Array[int] = []
## The ordered rows (R4): a card's slot is its index. Pending cards are not on a row.
var own_board: Array[int] = []
var opponent_board: Array[int] = []
## The same rows with what each card shows (plan, SeatView additions): one entry per card
## in slot order, {card, flat, times, plus, revealed, destroyed}, the stats from
## ScoreWalk.effective() (`times` in hundredths, `plus` in whole units; DC-07 P5). An
## opponent card not yet revealed (only possible mid-walk, while a prompt pauses it) shows
## flat 0, times 100 and plus 0 (no bonus) and card MatchEvent.HIDDEN_CARD, as it does in
## `opponent_board`. `destroyed` is public for every card (DC-06 R20): a destroyed
## face-down card shows its slot as destroyed and still hides its id.
var own_row: Array[Dictionary] = []
var opponent_row: Array[Dictionary] = []
## This seat's destroyed pile (DC-07 R16, R18, P6), in pile order.
var own_destroyed: Array[int] = []
## The opponent's destroyed pile in pile order: an entry's id where its identity is public
## (`destroyed_known`: it was revealed when it left the row), else MatchEvent.HIDDEN_CARD.
## Its size is public either way.
var opponent_destroyed: Array[int] = []
var opponent_hand_count: int = 0
## Size of the opponent's face-down commit while this seat is awaited second; else 0.
var opponent_pending_count: int = 0
## The final-row slots of that face-down commit (R7, plan P2), without its card ids;
## empty unless this seat is awaited second.
var opponent_pending_slots: Array[int] = []
var deck_counts: Array[int] = [0, 0]
var scores: Array[int] = [0, 0]
## Each seat's walk multiplier in hundredths (R14; DC-07 P4): the running value during a
## walk, the last walk's final value after it, 100 (×1.00) before the round's first walk.
var mults: Array[int] = [MatchRules.MULT_ONE, MatchRules.MULT_ONE]
var wins: Array[int] = [0, 0]
## Counts past MatchRules.ROUNDS in sudden death.
var round_number: int = 0
var turn: int = 0
## This seat's budget this turn: budgets[seat] (R9).
var energy: int = 0
## Both seats' budgets this turn, turn + carry (R9).
var budgets: Array[int] = [0, 0]
## True when this seat's next commit has its leftmost card free (R10, plan P7). Own seat
## only (plan, SeatView additions; DC-05 T07); TURN_STARTED announces both seats' grants.
var free_first: bool = false
## A MatchState.Phase.
var phase: int = MatchState.Phase.NOT_STARTED
## The seat whose commit is awaited; -1 before the start and once the match is over.
var awaited_seat: int = -1
## This turn's first committer, as announced by ROUND_STARTED and TURN_STARTED.
var first_seat: int = 0
var sudden_death: bool = false
## The open prompt (plan, SeatView additions; DC-05 T05). Empty when none is open. For the
## prompted seat: {open: true, seat, card, verb, text, zone, options}, with `verb` the
## CardEffect.Verb, `zone` the Choice.Zone (relative to this seat) and `options` the
## eligible positions in it, ready for EngineAction.choose(seat, zone, options[i]). For the
## other seat only {open: true, seat}.
var prompt: Dictionary = {}


## The view of `state` for `p_seat` (0 or 1). `p_awaited` and `p_budgets` come from the
## engine, which owns those derivations; `cards` gives the rows' shown stats (with none,
## every card shows flat 0 and no bonus).
static func build(
	state: MatchState, p_seat: int, p_awaited: int, p_budgets: Array[int], cards: MatchCards = null
) -> SeatView:
	var view: SeatView = SeatView.new()
	view.seat = p_seat
	view.opponent = 1 - p_seat
	view.deck_ids.assign(state.deck_ids)
	var own: MatchState.SeatPiles = state.seats[view.seat]
	var other: MatchState.SeatPiles = state.seats[view.opponent]
	view.own_hand.assign(own.hand)
	view.own_board.assign(own.board)
	view.opponent_board.assign(_shown_ids(other))
	view.own_row = _row(state, view.seat, cards, true)
	view.opponent_row = _row(state, view.opponent, cards, false)
	view.own_destroyed.assign(own.destroyed)
	view.opponent_destroyed.assign(_shown_destroyed(other))
	view.opponent_hand_count = other.hand.size()
	# `pending` belongs to the first committer while the second is awaited.
	if state.phase == MatchState.Phase.AWAIT_SECOND:
		if state.first_seat == view.seat:
			view.own_pending.assign(state.pending)
		else:
			view.opponent_pending_count = state.pending.size()
			view.opponent_pending_slots.assign(state.pending_slots)
	for index: int in range(2):
		var piles: MatchState.SeatPiles = state.seats[index]
		view.deck_counts[index] = piles.deck.size()
		view.scores[index] = state.scores[index]
		view.mults[index] = state.walk.mult[index]
		view.wins[index] = state.wins[index]
		view.budgets[index] = p_budgets[index]
	view.round_number = state.round_number
	view.turn = state.turn
	view.energy = view.budgets[view.seat]
	view.free_first = state.energy.free_first[view.seat]
	view.phase = state.phase
	view.awaited_seat = p_awaited
	view.first_seat = state.first_seat
	view.sudden_death = state.sudden_death
	view.prompt = _prompt(state, view.seat, cards)
	return view


## The view's prompt (see `prompt`): the full prompt for the prompted seat, only that it is
## open for the other.
static func _prompt(state: MatchState, p_seat: int, cards: MatchCards) -> Dictionary:
	if state.prompt.is_empty():
		return {}
	var asked: int = state.prompt.get(EffectResolver.KEY_SEAT, -1)
	if asked != p_seat:
		return {"open": true, "seat": asked}
	var source: int = state.prompt.get(EffectResolver.KEY_CARD, -1)
	var verb: int = state.prompt.get(EffectResolver.KEY_VERB, -1)
	var zone: int = state.prompt.get(Choice.KEY_ZONE, Choice.NO_ZONE)
	var text: String = ""
	var effect: CardEffect = EffectResolver.effect_of(source, cards)
	if effect != null:
		text = effect.text
	return {
		"open": true,
		"seat": asked,
		"card": source,
		"verb": verb,
		"text": text,
		"zone": zone,
		"options": MatchState.plain(Choice.options_of(state.prompt)),
	}


## A row's ids as the other seat may see them: a card not yet revealed (only possible while
## a walk is paused on a prompt, DC-05 T05) shows as MatchEvent.HIDDEN_CARD, since an
## instance id names its card definition (R29).
static func _shown_ids(piles: MatchState.SeatPiles) -> Array[int]:
	var out: Array[int] = []
	for card: int in piles.board:
		out.append(card if piles.is_revealed(card) else MatchEvent.HIDDEN_CARD)
	return out


## A destroyed pile as the other seat may see it (R18): a public identity by id, any other
## entry as MatchEvent.HIDDEN_CARD, in pile order.
static func _shown_destroyed(piles: MatchState.SeatPiles) -> Array[int]:
	var out: Array[int] = []
	for card: int in piles.destroyed:
		out.append(card if piles.is_destroyed_known(card) else MatchEvent.HIDDEN_CARD)
	return out


## `row_seat`'s row entries in slot order. `own` shows the stats of unrevealed cards too.
static func _row(
	state: MatchState, row_seat: int, cards: MatchCards, own: bool
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var piles: MatchState.SeatPiles = state.seats[row_seat]
	for card: int in piles.board:
		var revealed: bool = piles.is_revealed(card)
		var stats: ScoreWalk.Effective = ScoreWalk.Effective.new()
		var shown: int = MatchEvent.HIDDEN_CARD
		if own or revealed:
			stats = ScoreWalk.effective(card, state, cards)
			shown = card
		var entry: Dictionary = {
			"card": shown,
			"flat": stats.flat,
			"times": stats.times,
			"plus": stats.plus,
			"revealed": revealed,
			"destroyed": state.is_destroyed(card),
		}
		out.append(entry)
	return out


## An untyped copy of a String array, for to_dict().
static func _plain_strings(values: Array[String]) -> Array:
	var out: Array = []
	out.assign(values)
	return out


## Deep, untyped copies of row entries, for to_dict().
static func _plain_row(row: Array[Dictionary]) -> Array:
	var out: Array = []
	for entry: Dictionary in row:
		out.append(entry.duplicate(true))
	return out


func is_awaited() -> bool:
	return awaited_seat == seat


## The ordered row of either seat, as a copy.
func board_of(p_seat: int) -> Array[int]:
	var out: Array[int] = []
	if p_seat == seat:
		out.assign(own_board)
	elif p_seat == opponent:
		out.assign(opponent_board)
	return out


## The view as plain, deep-copied data, for tests and leak scans.
func to_dict() -> Dictionary:
	return {
		"seat": seat,
		"opponent": opponent,
		"deck_ids": _plain_strings(deck_ids),
		"own_hand": MatchState.plain(own_hand),
		"own_pending": MatchState.plain(own_pending),
		"own_board": MatchState.plain(own_board),
		"opponent_board": MatchState.plain(opponent_board),
		"own_row": _plain_row(own_row),
		"opponent_row": _plain_row(opponent_row),
		"own_destroyed": MatchState.plain(own_destroyed),
		"opponent_destroyed": MatchState.plain(opponent_destroyed),
		"opponent_hand_count": opponent_hand_count,
		"opponent_pending_count": opponent_pending_count,
		"opponent_pending_slots": MatchState.plain(opponent_pending_slots),
		"deck_counts": MatchState.plain(deck_counts),
		"scores": MatchState.plain(scores),
		"mults": MatchState.plain(mults),
		"wins": MatchState.plain(wins),
		"round": round_number,
		"turn": turn,
		"energy": energy,
		"budgets": MatchState.plain(budgets),
		"free_first": free_first,
		"phase": phase,
		"awaited_seat": awaited_seat,
		"first_seat": first_seat,
		"sudden_death": sudden_death,
		"prompt": prompt.duplicate(true),
	}
