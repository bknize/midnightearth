class_name MatchState
extends RefCounted
## All mutable match state (plan, data model). MatchEngine is the only writer; readers
## (SeatView, replay) use the fields or to_dict(), the full-state read (R30).
##
## Derived, not stored: the budget (= turn + energy.carry[seat], MatchEngine.budget_for)
## and the awaited seat (from phase and first_seat).
## Card instance ids are seat * DECK_SIZE + definition index (R9, C5).

## NOT_STARTED holds until start() succeeds; the plan's three phases follow it. AWAIT_CHOICE
## (DC-05 T05, appended so earlier ordinals hold) is a walk paused on an open `prompt`.
## While a walk runs between two decisions the phase stays AWAIT_SECOND.
enum Phase { NOT_STARTED, AWAIT_FIRST, AWAIT_SECOND, OVER, AWAIT_CHOICE }

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
## Per seat that will suffer it: the bonus-0 mark (R22). Set by the opponent's
## OPPONENT_NEXT_BONUS_ZERO effect, spent by this seat's next reveal; a bool, so setting it
## again before it is spent does not stack. Cleared at round start (MatchEngine).
var bonus_zero_pending: Array[bool] = [false, false]
## The open prompt (plan P9): {seat, card, verb, zone, options}, with `verb` a
## CardEffect.Verb, `zone` a Choice.Zone and `options` a plain Array of positions in that
## zone (Choice). Empty when no prompt is open.
var prompt: Dictionary = {}


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
		"bonus_zero_pending": _plain_flags(bonus_zero_pending),
		"prompt": prompt.duplicate(true),
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
	out.bonus_zero_pending.assign(bonus_zero_pending)
	out.prompt = prompt.duplicate(true)
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


## Whether `card` is destroyed (DC-06 R12, P4): still on its row, scoring and firing
## nothing, until turn end clears it (EffectResolver.clear_destroyed).
func is_destroyed(card: int) -> bool:
	var held: CardState = card_state(card)
	return held != null and held.destroyed


## Takes `card` off `seat`'s row (a return at turn end, R24; the turn-end clear of a
## destroyed card, DC-06 R18): it leaves the row and the revealed set, and its modifiers go
## (R21), the destroyed mark with them (R22). Returns whether the card had been revealed;
## false, changing nothing, when it was not on that row. Read the card's slot before
## calling. Where the card goes next is the caller's call. The live engine calls it only
## once a walk is over, so the walk's slot cursor never follows a row that shrinks (DC-06
## P1); the preview's MatchEngine._hide_opponent marks hidden cards destroyed in place
## instead of taking them (DC-06 P7), so no caller shrinks a row mid-walk.
func take_from_row(seat: int, card: int) -> bool:
	var piles: SeatPiles = seats[seat]
	var slot: int = piles.board.find(card)
	if slot < 0:
		return false
	piles.board.remove_at(slot)
	if clear_card_state(card):
		pass  # Its modifiers leave the board with it; nothing else to do.
	return piles.revealed.erase(card)


## The modifiers as plain data, keyed by instance id.
func _card_states_dict() -> Dictionary:
	var out: Dictionary = {}
	for card: int in card_states:
		var held: CardState = card_states[card]
		out[card] = held.to_dict()
	return out


## An untyped copy of a seat-indexed flag pair, for to_dict().
static func _plain_flags(values: Array[bool]) -> Array:
	var out: Array = []
	out.assign(values)
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


## The score walk's progress (plan P3, P5; DC-06 P1, P3), written only by ScoreWalk.
## `active` holds from ScoreWalk.begin() until a step finds no slot left to pulse.
## `next_seat` is the seat whose row is tried first on the next pulse; `cursor` is, per
## seat, the number of that row's slots the walk has passed (R1), so the next slot of a row
## is its cursor; `scored` holds every card scored at least once in this walk (a card moved
## in front of the cursor scores again, CARD_SCORED `again`); `mult` is each seat's
## running multiplier.
## `paused_card` is the card whose stage a prompt interrupted (-1 when none): the card
## revealing or scoring in the pulse, which may not be the card the pulse started on (DC-06
## C23). `paused_slot` is the slot of the pulse's row it was pulsing (-1 when none), so a
## resume scores whatever card holds that slot. With them, the ScoreWalk.Stage to resume at
## and, for the WATCHERS stage, the watcher snapshot (the on-opponent-reveal cards in row
## order when the stage first ran; empty when it has not run yet) and the snapshot index it
## goes on from (DC-05 T05, T13).
class WalkState:
	extends RefCounted

	var active: bool = false
	var next_seat: int = 0
	var cursor: Array[int] = [0, 0]
	var scored: Dictionary[int, bool] = {}
	var mult: Array[int] = [1, 1]
	## Cards revealed so far in this walk: the CARD_REVEALED `order` the board still reads
	## (kept until the board moves to the walk's events, DC-05 T08 and T11).
	var reveals: int = 0
	var paused_card: int = -1
	var paused_slot: int = -1
	var paused_stage: int = 0
	var paused_watchers: Array[int] = []
	var paused_watcher_at: int = 0

	## The ids of the cards scored in this walk, ascending.
	func scored_ids() -> Array[int]:
		var out: Array[int] = []
		out.assign(scored.keys())
		out.sort()
		return out

	func copy() -> WalkState:
		var out: WalkState = WalkState.new()
		out.active = active
		out.next_seat = next_seat
		out.cursor.assign(cursor)
		out.scored.assign(scored)
		out.mult.assign(mult)
		out.reveals = reveals
		out.paused_card = paused_card
		out.paused_slot = paused_slot
		out.paused_stage = paused_stage
		out.paused_watchers.assign(paused_watchers)
		out.paused_watcher_at = paused_watcher_at
		return out

	func to_dict() -> Dictionary:
		return {
			"active": active,
			"next_seat": next_seat,
			"cursor": MatchState.plain(cursor),
			"scored": MatchState.plain(scored_ids()),
			"mult": MatchState.plain(mult),
			"reveals": reveals,
			"paused_card": paused_card,
			"paused_slot": paused_slot,
			"paused_stage": paused_stage,
			"paused_watchers": MatchState.plain(paused_watchers),
			"paused_watcher_at": paused_watcher_at,
		}
