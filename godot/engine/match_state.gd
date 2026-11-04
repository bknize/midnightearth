class_name MatchState
extends RefCounted
## All mutable match state (plan, data model). MatchEngine is the only writer; readers
## (SeatView, replay) use the fields or to_dict(), the full-state read (R30).
##
## Derived, not stored: the budget (= turn + energy.carry[seat], MatchEngine.budget_for)
## and the awaited seat (from phase and first_seat).
## Card instance ids are seat * DECK_SIZE + definition index (R9, C5).

## NOT_STARTED holds until start() succeeds; the plan's three phases follow it.
enum Phase { NOT_STARTED, AWAIT_FIRST, AWAIT_SECOND, OVER }

var match_seed: int = 0
## Mirror of the engine stream's state, refreshed by the engine after every change.
var rng_state: int = 0
## Counts past MatchRules.ROUNDS in sudden death.
var round_number: int = 0
var turn: int = 0
var sudden_death: bool = false
var phase: int = Phase.NOT_STARTED
## This turn's first committer.
var first_seat: int = 0
## Per seat, indexed by seat number.
var seats: Array[SeatPiles] = []
## The first committer's face-down cards, in commit order (= slot order).
var pending: Array[int] = []
## The final-row slot of each card in `pending` (plan P1, P2); always explicit.
var pending_slots: Array[int] = []
## Per-seat energy state (plan P7).
var energy: EnergyState = EnergyState.new()
## Board scores (each seat's last walk total, R17; the running total during a walk) and
## round wins.
var scores: Array[int] = [0, 0]
var wins: Array[int] = [0, 0]
## Winner of the last resolved turn in this round; -1 for a tie or none yet.
var last_turn_winner: int = -1
## Seat that won the most recent won round of the match; -1 until one is won (C9).
var last_round_winner: int = -1
## winner, reason, rounds_played; empty while the match is in progress.
var result: Dictionary = {}
## Accepted actions so far; equals the action log's length.
var actions_applied: int = 0
## Per-instance modifiers of cards on the rows (plan, MatchState additions), by instance
## id. Cleared at round start and whenever a card leaves the board (clear_card_state).
var card_states: Dictionary[int, CardState] = {}
## The score walk's resumable progress (plan P3), driven by ScoreWalk.
var walk: WalkState = WalkState.new()


func _init(p_match_seed: int = 0) -> void:
	match_seed = p_match_seed
	for _seat: int in range(2):
		seats.append(SeatPiles.new())


## The full state as plain data, deep-copied. Two states are equal when these are equal.
## `revealed` is listed per seat as the ascending ids of its revealed cards.
func to_dict() -> Dictionary:
	var decks: Array = []
	var hands: Array = []
	var boards: Array = []
	var burns: Array = []
	var revealed: Array = []
	for piles: SeatPiles in seats:
		decks.append(plain(piles.deck))
		hands.append(plain(piles.hand))
		boards.append(plain(piles.board))
		burns.append(plain(piles.burned))
		revealed.append(plain(piles.revealed_ids()))
	return {
		"seed": match_seed,
		"rng_state": rng_state,
		"round": round_number,
		"turn": turn,
		"sudden_death": sudden_death,
		"phase": phase,
		"first_seat": first_seat,
		"deck": decks,
		"hand": hands,
		"board": boards,
		"revealed": revealed,
		"burned": burns,
		"pending": plain(pending),
		"pending_slots": plain(pending_slots),
		"energy": energy.to_dict(),
		"scores": plain(scores),
		"wins": plain(wins),
		"last_turn_winner": last_turn_winner,
		"last_round_winner": last_round_winner,
		"result": result.duplicate(true),
		"actions_applied": actions_applied,
		"card_states": _card_states_dict(),
		"walk": walk.to_dict(),
	}


## A deep copy: no array, dictionary or inner object is shared with this state (plan P12,
## the preview's clone). The copy's to_dict() equals this one's.
func duplicate() -> MatchState:
	var out: MatchState = MatchState.new(match_seed)
	out.rng_state = rng_state
	out.round_number = round_number
	out.turn = turn
	out.sudden_death = sudden_death
	out.phase = phase
	out.first_seat = first_seat
	out.seats.clear()
	for piles: SeatPiles in seats:
		out.seats.append(piles.copy())
	out.pending.assign(pending)
	out.pending_slots.assign(pending_slots)
	out.energy = energy.copy()
	out.scores.assign(scores)
	out.wins.assign(wins)
	out.last_turn_winner = last_turn_winner
	out.last_round_winner = last_round_winner
	out.result = result.duplicate(true)
	out.actions_applied = actions_applied
	for card: int in card_states:
		var held: CardState = card_states[card]
		out.card_states[card] = held.copy()
	out.walk = walk.copy()
	return out


## `card`'s modifiers, or null when it has none.
func card_state(card: int) -> CardState:
	if card_states.has(card):
		return card_states[card]
	return null


## `card`'s modifiers, created at their defaults when it has none (T04 and T05 write them).
func card_state_for(card: int) -> CardState:
	if not card_states.has(card):
		card_states[card] = CardState.new()
	return card_states[card]


## Drops `card`'s modifiers: call whenever the card leaves the board. True when it had any.
func clear_card_state(card: int) -> bool:
	return card_states.erase(card)


## The modifiers as plain data, keyed by instance id.
func _card_states_dict() -> Dictionary:
	var out: Dictionary = {}
	for card: int in card_states:
		var held: CardState = card_states[card]
		out[card] = held.to_dict()
	return out


## An untyped copy, so serialized forms hold plain data only.
static func plain(values: Array[int]) -> Array:
	var out: Array = []
	out.assign(values)
	return out


## One seat's card piles, as ordered instance ids. `board` is the ordered row (R4): a
## card's slot is its index.
class SeatPiles:
	extends RefCounted

	var deck: Array[int] = []
	var hand: Array[int] = []
	var board: Array[int] = []
	var burned: Array[int] = []
	## Cards on the row that have been revealed (plan, MatchState additions).
	var revealed: Dictionary[int, bool] = {}

	## The revealed card ids, ascending.
	func revealed_ids() -> Array[int]:
		var out: Array[int] = []
		out.assign(revealed.keys())
		out.sort()
		return out

	## Whether `card` has been revealed on this row.
	func is_revealed(card: int) -> bool:
		return revealed.has(card) and revealed[card]

	func copy() -> SeatPiles:
		var out: SeatPiles = SeatPiles.new()
		out.deck.assign(deck)
		out.hand.assign(hand)
		out.board.assign(board)
		out.burned.assign(burned)
		out.revealed.assign(revealed)
		return out


## Per-seat energy (plan P7), each pair indexed by seat. The budget is turn + carry; a
## true `free_first` makes the leftmost card of that seat's next commit cost 0 and is
## consumed by that commit; `spent` is what the seat's commit this turn cost.
class EnergyState:
	extends RefCounted

	var carry: Array[int] = [0, 0]
	var free_first: Array[bool] = [false, false]
	var spent: Array[int] = [0, 0]

	func copy() -> EnergyState:
		var out: EnergyState = EnergyState.new()
		out.carry.assign(carry)
		out.free_first.assign(free_first)
		out.spent.assign(spent)
		return out

	func to_dict() -> Dictionary:
		var flags: Array = []
		flags.assign(free_first)
		return {
			"carry": MatchState.plain(carry),
			"free_first": flags,
			"spent": MatchState.plain(spent),
		}


## The score walk's progress (plan P3, P5), written only by ScoreWalk. `active` holds from
## ScoreWalk.begin() until a step finds no card left to pulse. `next_seat` is the seat whose
## row is tried first on the next pulse; `pulsed` holds every card pulsed in this walk, so
## nothing is pulsed twice whatever moves; `mult` is each seat's running multiplier.
class WalkState:
	extends RefCounted

	var active: bool = false
	var next_seat: int = 0
	var pulsed: Dictionary[int, bool] = {}
	var mult: Array[int] = [1, 1]
	## Cards revealed so far in this walk: the CARD_REVEALED `order` the board still reads
	## (kept until the board moves to the walk's events, DC-05 T08 and T11).
	var reveals: int = 0

	## The pulsed card ids, ascending.
	func pulsed_ids() -> Array[int]:
		var out: Array[int] = []
		out.assign(pulsed.keys())
		out.sort()
		return out

	func copy() -> WalkState:
		var out: WalkState = WalkState.new()
		out.active = active
		out.next_seat = next_seat
		out.pulsed.assign(pulsed)
		out.mult.assign(mult)
		out.reveals = reveals
		return out

	func to_dict() -> Dictionary:
		return {
			"active": active,
			"next_seat": next_seat,
			"pulsed": MatchState.plain(pulsed_ids()),
			"mult": MatchState.plain(mult),
			"reveals": reveals,
		}
