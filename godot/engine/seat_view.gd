class_name SeatView
extends RefCounted
## One seat's redacted view of a match, rules version 7 (cycle 9 plan P15; spec R57, R58),
## built by MatchEngine.view_for().
##
## Holds both seats' deck ids (public), the seat's own hand and own face-down Commit, both
## ordered rows with what each card shows, both Piles in full and in Pile order (a Pile
## entry is public from the moment the card enters it, R19, R24), the opponent's hand and
## Deck counts, the count and slots of its face-down Commit, both walking totals (in
## ten-thousandths) and both Scores, both Budgets and both Hand sizes, both seats' Crew,
## and the opposing face-down cards this seat has looked at (`looked`, Lookout).
##
## Never holds the match seed, the stream state, any Deck order, or the id or stats of a
## card in the opponent's hand, Deck or face-down Commit, or face down on its row unless
## this seat looked at it (then only in `looked`). `free_first` and `deck_top` are this
## seat's own. Seat-indexed pairs (deck_counts, scores, totals, wins, budgets, hand_sizes)
## are indexed by seat number, like MatchState.
##
## Every array is a copy: mutating a view never touches the engine's state.

var seat: int = 0
var opponent: int = 1
## The deck id each seat plays, indexed by seat; public, like the picker.
var deck_ids: Array[String] = ["", ""]
## This seat's hand, in hand order.
var own_hand: Array[int] = []
## What each card of `own_hand` shows, in hand order: {card, cost, power, mult, add, grown,
## uses_left}, `cost` the effective Cost (Scoring.effective_cost), `power` its Power and
## `mult`, `add` its Mult (hundredths, 100 for none) and Add (hundredths, 0 for none) with
## Memory (Scoring.stats), `grown` true when its Memory is not empty and `uses_left` -1 for
## an unlimited ability. Own seat only (R58).
var own_hand_row: Array[Dictionary] = []
## The effective Cost of each card of `own_hand`, parallel to it: what the engine's Budget
## check reads, for the bot and the board's staging. Empty for a view built without
## definitions (readers then take printed costs).
var own_hand_costs: Array[int] = []
## This seat's face-down Commit while it waits for the second Commit; empty otherwise.
var own_pending: Array[int] = []
## The ordered rows: a card's slot is its index. A face-down opposing card is
## MatchEvent.HIDDEN_CARD in `opponent_board`.
var own_board: Array[int] = []
var opponent_board: Array[int] = []
## The rows with what each card shows, in slot order: {card, power, mult, add, revealed,
## cost, grown, uses_left, statuses, exit_mark}, the stats as `own_hand_row`, `statuses` the
## badge words it shows (Statuses.badges: "Silenced" for both halves) and `exit_mark` its
## exit mark (Statuses.CONDEMNED, FLEETING or FADE; "" for none).
## An opposing face-down card shows card MatchEvent.HIDDEN_CARD, Power 0, no Bonus (mult
## 100, add 0), cost 0, grown false, uses_left -1, no statuses and no mark (R58).
var own_row: Array[Dictionary] = []
var opponent_row: Array[Dictionary] = []
## This seat's Pile and the opponent's, by id in Pile order: public (R19, R24).
var own_pile: Array[int] = []
var opponent_pile: Array[int] = []
## What each Pile card shows, both Piles, keyed by instance id, each value as an
## `own_hand_row` entry with Memory. to_dict() lists them in ascending id order.
var pile_entries: Dictionary[int, Dictionary] = {}
var opponent_hand_count: int = 0
## Size and final-row slots of the opponent's face-down Commit while it waits; else 0, [].
var opponent_pending_count: int = 0
var opponent_pending_slots: Array[int] = []
var deck_counts: Array[int] = [0, 0]
## Each seat's Score: the last Walk's walking total rounded once (R27).
var scores: Array[int] = [0, 0]
## Each seat's walking total in ten-thousandths (R28, P7): the running value during a Walk,
## the last Walk's after it, 0 at Round start.
var totals: Array[int] = [0, 0]
var wins: Array[int] = [0, 0]
## Counts past MatchRules.ROUNDS in sudden death.
var round_number: int = 0
var turn: int = 0
## This seat's Budget this Turn: budgets[seat].
var energy: int = 0
## Both seats' Budgets this Turn: turn + grants (R6, R7).
var budgets: Array[int] = [0, 0]
## Both seats' Hand sizes, read now (R11): public, as the cards that change one are.
var hand_sizes: Array[int] = [MatchRules.HAND_SIZE, MatchRules.HAND_SIZE]
## True when this seat's next Commit has its leftmost card free (own seat only).
var free_first: bool = false
## The opposing face-down cards this seat has looked at (Lookout, R57, R59): opponent row
## slot to instance id. Own seat only; empty for the other seat.
var looked: Dictionary[int, int] = {}
## The top cards of this seat's Deck while its own Delve prompt is open (DC-13 T06), in
## Deck order; empty otherwise. Own seat only.
var deck_top: Array[int] = []
## A MatchState.Phase.
var phase: int = MatchState.Phase.NOT_STARTED
## The seat whose decision is awaited; -1 before the start and once the match is over.
var awaited_seat: int = -1
## This Turn's first committer.
var first_seat: int = 0
var sudden_death: bool = false
## The open prompt (plan P12). Empty when none is open. For the prompted seat: {open: true,
## seat, card, crew, verb, text, zone, options, multi, exact, min, optional, resume, step},
## `zone` a Choice.ZONE_NAMES name (Choice.zone_of reads it) and `options` the positions in
## it, ready for EngineAction.choose(seat, zone, options[i]) or, when `multi`,
## EngineAction.choose_set(seat, zone, a set of `exact` of them, or any size at least `min`
## when `exact` is -1). For the other seat only {open: true, seat}.
var prompt: Dictionary = {}
## Both seats' Crew ids in slot order, indexed by seat: public. Empty per seat for a view
## built without definitions.
var crew: Array[Array] = [[], []]
## Both seats' Crew uses left, as MatchState.crew_uses: public.
var crew_uses: Array[Array] = [[], []]


## The view of `state` for `p_seat` (0 or 1). `p_awaited` comes from the engine, which
## owns that derivation; `cards` gives the shown stats, Budgets and Hand sizes (with none,
## every card shows Power 0 and no Bonus, and the Budgets are the Turn).
static func build(
	state: MatchState, p_seat: int, p_awaited: int, cards: MatchCards = null
) -> SeatView:
	var view: SeatView = SeatView.new()
	view.seat = p_seat
	view.opponent = 1 - p_seat
	view.deck_ids.assign(state.deck_ids)
	var own: MatchState.SeatPiles = state.seats[view.seat]
	var other: MatchState.SeatPiles = state.seats[view.opponent]
	view.own_hand.assign(own.hand)
	view.own_hand_row = _hand_row(state, own.hand, cards)
	if cards != null:
		view.own_hand_costs = Scoring.effective_costs(own.hand, state, cards)
	view.own_board.assign(own.board)
	view.opponent_board.assign(_shown_ids(other))
	view.own_row = _row(state, view.seat, cards, true)
	view.opponent_row = _row(state, view.opponent, cards, false)
	view.own_pile.assign(own.pile)
	view.opponent_pile.assign(other.pile)
	view.pile_entries = _pile_entries(state, own.pile + other.pile, cards)
	view.opponent_hand_count = other.hand.size()
	if not state.pending.is_empty() or state.phase == MatchState.Phase.AWAIT_SECOND:
		if state.first_seat == view.seat:
			view.own_pending.assign(state.pending)
		else:
			view.opponent_pending_count = state.pending.size()
			view.opponent_pending_slots.assign(state.pending_slots)
	view.looked = _looked(own, other)
	_fill_pairs(view, state, cards)
	view.round_number = state.round_number
	view.turn = state.turn
	view.energy = view.budgets[view.seat]
	view.free_first = state.energy.free_first[view.seat]
	view.phase = state.phase
	view.awaited_seat = p_awaited
	view.first_seat = state.first_seat
	view.sudden_death = state.sudden_death
	view.prompt = _prompt(state, view.seat, cards)
	for index: int in range(2):
		var uses: Array = state.crew_uses[index]
		view.crew_uses[index] = uses.duplicate()
		if cards != null:
			view.crew[index] = cards.crew_ids(index)
	return view


## The seat-indexed pairs: Deck counts, Scores, walking totals, wins, Budgets and Hand sizes.
static func _fill_pairs(view: SeatView, state: MatchState, cards: MatchCards) -> void:
	for index: int in range(2):
		var piles: MatchState.SeatPiles = state.seats[index]
		view.deck_counts[index] = piles.deck.size()
		view.scores[index] = state.scores[index]
		view.totals[index] = state.totals[index]
		view.wins[index] = state.wins[index]
		view.budgets[index] = TurnFlow.budget(state, cards, index)
		view.hand_sizes[index] = TurnFlow.hand_size(state, cards, index)


## The view's prompt (see `prompt`): the full prompt for the prompted seat, only that it is
## open for the other.
static func _prompt(state: MatchState, p_seat: int, cards: MatchCards) -> Dictionary:
	if state.prompt.is_empty():
		return {}
	var asked: int = state.prompt.get(Abilities.KEY_SEAT, -1)
	if asked != p_seat:
		return {"open": true, "seat": asked}
	var source: int = state.prompt.get(Abilities.KEY_CARD, -1)
	var verb: String = state.prompt.get(Abilities.KEY_VERB, "")
	var text: String = Abilities.prompt_text(state.prompt, cards)
	if TurnFlow.is_discard_down(state.prompt):
		text = TurnFlow.discard_text(Choice.exact_of(state.prompt))
	return {
		"open": true,
		"seat": asked,
		"card": source,
		"crew": Choice.crew_of(state.prompt),
		"verb": verb,
		"text": text,
		"zone": Choice.zone_name(Choice.zone_of(state.prompt)),
		"options": MatchState.plain(Choice.options_of(state.prompt)),
		"multi": Choice.is_multi_prompt(state.prompt),
		"exact": Choice.exact_of(state.prompt),
		"min": Choice.min_of(state.prompt),
		"optional": Choice.is_optional_prompt(state.prompt),
		"resume": Choice.resume_of(state.prompt),
		"step": Choice.step_of(state.prompt),
	}


## A row's ids as the other seat may see them: a face-down card shows as
## MatchEvent.HIDDEN_CARD, since an instance id names its card definition.
static func _shown_ids(piles: MatchState.SeatPiles) -> Array[int]:
	var out: Array[int] = []
	for card: int in piles.board:
		out.append(card if piles.is_revealed(card) else MatchEvent.HIDDEN_CARD)
	return out


## `looked` (see there): the opponent's face-down row cards `own` has looked at, by slot.
static func _looked(
	own: MatchState.SeatPiles, other: MatchState.SeatPiles
) -> Dictionary[int, int]:
	var out: Dictionary[int, int] = {}
	for slot: int in range(other.board.size()):
		var card: int = other.board[slot]
		if own.looked.has(card) and not other.is_revealed(card):
			out[slot] = card
	return out


## `row_seat`'s row entries in slot order. `own` shows the stats of face-down cards too.
static func _row(
	state: MatchState, row_seat: int, cards: MatchCards, own: bool
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var piles: MatchState.SeatPiles = state.seats[row_seat]
	for card: int in piles.board:
		var revealed: bool = piles.is_revealed(card)
		var entry: Dictionary = {
			"card": MatchEvent.HIDDEN_CARD,
			"power": 0,
			"mult": MatchRules.BONUS_ONE,
			"add": 0,
			"cost": 0,
			"grown": false,
			"uses_left": -1,
		}
		if own or revealed:
			entry = _card_entry(state, card, cards)
		entry["revealed"] = revealed
		var words: Array = []  # Hidden from the other seat while face down (R58).
		var mark: String = ""
		if own or revealed:
			words.assign(Statuses.badges(state, cards, card))
			mark = Statuses.exit_mark_of(state, card)
		entry["statuses"] = words
		entry["exit_mark"] = mark
		out.append(entry)
	return out


## The entries of `hand` (this seat's own) in hand order: see `own_hand_row`.
static func _hand_row(state: MatchState, hand: Array[int], cards: MatchCards) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for card: int in hand:
		out.append(_card_entry(state, card, cards))
	return out


## `pile_entries` (see there): an entry for each card of `piled`.
static func _pile_entries(
	state: MatchState, piled: Array[int], cards: MatchCards
) -> Dictionary[int, Dictionary]:
	var out: Dictionary[int, Dictionary] = {}
	for card: int in piled:
		out[card] = _card_entry(state, card, cards)
	return out


## What `card` shows to a seat that knows it: {card, cost, power, mult, add, grown,
## uses_left}, with Memory and Board changes (Scoring.stats).
static func _card_entry(state: MatchState, card: int, cards: MatchCards) -> Dictionary:
	var stats: Scoring.Stats = Scoring.stats(card, state, cards)
	return {
		"card": card,
		"cost": maxi(Scoring.effective_cost(card, state, cards), 0),
		"power": stats.power,
		"mult": stats.mult(),
		"add": stats.add(),
		"grown": Scoring.is_grown(card, state),
		"uses_left": Scoring.uses_left(card, state, cards),
	}


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


## `pile_entries` for to_dict(): deep copies of its entries in ascending id order.
static func _plain_entries(entries: Dictionary[int, Dictionary]) -> Array:
	var ids: Array[int] = []
	ids.assign(entries.keys())
	ids.sort()
	var out: Array = []
	for card: int in ids:
		var entry: Dictionary = entries[card]
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


## The Pile of either seat in Pile order, as a copy.
func pile_of(p_seat: int) -> Array[int]:
	var out: Array[int] = []
	if p_seat == seat:
		out.assign(own_pile)
	elif p_seat == opponent:
		out.assign(opponent_pile)
	return out


## The view as plain, deep-copied data, for tests and leak scans.
func to_dict() -> Dictionary:
	var seen: Dictionary = {}
	seen.assign(looked)
	return {
		"seat": seat,
		"opponent": opponent,
		"deck_ids": _plain_strings(deck_ids),
		"own_hand": MatchState.plain(own_hand),
		"own_hand_row": _plain_row(own_hand_row),
		"own_hand_costs": MatchState.plain(own_hand_costs),
		"own_pending": MatchState.plain(own_pending),
		"own_board": MatchState.plain(own_board),
		"opponent_board": MatchState.plain(opponent_board),
		"own_row": _plain_row(own_row),
		"opponent_row": _plain_row(opponent_row),
		"own_pile": MatchState.plain(own_pile),
		"opponent_pile": MatchState.plain(opponent_pile),
		"pile_entries": _plain_entries(pile_entries),
		"opponent_hand_count": opponent_hand_count,
		"opponent_pending_count": opponent_pending_count,
		"opponent_pending_slots": MatchState.plain(opponent_pending_slots),
		"deck_counts": MatchState.plain(deck_counts),
		"scores": MatchState.plain(scores),
		"totals": MatchState.plain(totals),
		"wins": MatchState.plain(wins),
		"round": round_number,
		"turn": turn,
		"energy": energy,
		"budgets": MatchState.plain(budgets),
		"hand_sizes": MatchState.plain(hand_sizes),
		"free_first": free_first,
		"looked": seen,
		"deck_top": MatchState.plain(deck_top),
		"phase": phase,
		"awaited_seat": awaited_seat,
		"first_seat": first_seat,
		"sudden_death": sudden_death,
		"prompt": prompt.duplicate(true),
		"crew": crew.duplicate(true),
		"crew_uses": crew_uses.duplicate(true),
	}
