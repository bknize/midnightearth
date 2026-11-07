class_name MatchState
extends RefCounted
## All mutable match state, rules version 7 (cycle 9 plan, Data model). MatchEngine, TurnFlow
## and ScoreWalk are its writers; readers (SeatView, replay) use the fields or to_dict(), the
## full-state read.
##
## Derived, not stored: the Budget (turn + grants, TurnFlow.budget), the Hand size
## (TurnFlow.hand_size), a card's effective Power, Bonuses and Cost (Scoring) and the awaited
## seat (from phase, first_seat and the open prompt).
## Card instance ids are Owner seat * DECK_SIZE + index into that seat's deck list (plan P6,
## MatchCards); `deck_ids` names each seat's deck.
##
## Rules 7 (DC-13 T03): each seat has one public Pile for the Match (no destroyed or burn
## pile), a walking total in ten-thousandths (`totals`) beside the Walk's Score (`scores`),
## the Energy granted this Turn (`energy.grants`, no carry), the cards it committed this Turn
## (`committed_count`) and the opposing face-down cards it has looked at (`looked`).

## NOT_STARTED holds until start() succeeds. AWAIT_CHOICE is a prompt open (`prompt`): the
## discard-down, or a prompt a drain paused on (T05). While a Walk runs between two
## decisions the phase stays AWAIT_SECOND.
enum Phase { NOT_STARTED, AWAIT_FIRST, AWAIT_SECOND, OVER, AWAIT_CHOICE }

var match_seed: int = 0
## The deck id each seat plays, indexed by seat: resolved at create(), never "" once started.
var deck_ids: Array[String] = ["", ""]
## Mirror of the engine stream's state, refreshed by the engine after every change.
var rng_state: int = 0
## Counts past MatchRules.ROUNDS in sudden death.
var round_number: int = 0
var turn: int = 0
var sudden_death: bool = false
var phase: int = Phase.NOT_STARTED
## This Turn's first committer.
var first_seat: int = 0
## Per seat, indexed by seat number. A seat's piles hold the cards it controls; a card's
## Owner is MatchCards.origin_of().
var seats: Array[SeatPiles] = []
## The first committer's face-down Commit, in slot order, until the second Commit is
## accepted and both merge into their rows.
var pending: Array[int] = []
## The final-row slot of each card in `pending`; always explicit.
var pending_slots: Array[int] = []
## Per-seat Energy (plan Data model).
var energy: EnergyState = EnergyState.new()
## The cards each seat committed this Turn (0 for a Pass or before its Commit, P14).
var committed_count: Array[int] = [0, 0]
## Each seat's Score: the last Walk's walking total rounded once (R27).
var scores: Array[int] = [0, 0]
## Each seat's walking total in ten-thousandths (R25, R28): 0 at Walk start, the total after
## its last Scoring card once the Walk ends.
var totals: Array[int] = [0, 0]
var wins: Array[int] = [0, 0]
## Each seat's Score summed over every Walk of the Match; the stalemate tie-break (spec C12).
var match_scores: Array[int] = [0, 0]
## Winner of the last resolved Turn in this Round; -1 for a tie or none yet.
var last_turn_winner: int = -1
## Turns each seat has won in this Round; the more takes the Round (spec C13).
var turn_wins: Array[int] = [0, 0]
## Winner of the previous Round (R3): -1 after a tied Round or before any Round ended.
var last_round_winner: int = -1
## winner, reason, rounds_played; empty while the match is in progress.
var result: Dictionary = {}
## Accepted actions so far; equals the action log's length.
var actions_applied: int = 0
## Board changes of cards on the rows, by instance id (CardState). Dropped when the card
## leaves its row.
var card_states: Dictionary[int, CardState] = {}
## Memory for the match by instance id (CardMemory): never cleared.
var memory: Dictionary[int, CardMemory] = {}
## The Walk's resumable progress, driven by ScoreWalk.
var walk: WalkState = WalkState.new()
## The open prompt (plan P12): {seat, card, crew, verb, zone, options, multi, exact, min,
## optional, resume, step}, `zone` a Choice.ZONE_NAMES name, `options` positions in that
## zone, `exact` the set size a multi-select requires (-1 for any size), `resume` what its
## answer resumes and `step` the drain point (D1..D12). Empty when none is open.
var prompt: Dictionary = {}
## Per seat, the uses left of each of its Crew in slot order: CrewDef.UNLIMITED (-1) for an
## unlimited Crew. Filled at Match start (reset_crew_uses). Public.
var crew_uses: Array[Array] = [[], []]
## Per seat, the protections over every card that seat controls (Ward: "your cards cannot be
## Muted", DC-13 T04, plan P9): status to cessation, as CardState.statuses. Written by
## Statuses; the `turn` ones end at turn end.
var seat_protections: Array[Dictionary] = [{}, {}]
## The trigger queue (DC-13 T05, plan P11): its Batches, the drain in progress and the entry
## a drain paused on, so a full state taken while paused replays and resumes alike.
var queue: TriggerQueue = TriggerQueue.new()
## Per seat, the Void grants its next Scoring card will take (DC-13 T07, plan P13): a count
## that stacks, spent when that card Scores and cleared at turn end (CrewAbilities). Public.
var void_grants: Array[int] = [0, 0]


func _init(p_match_seed: int = 0) -> void:
	match_seed = p_match_seed
	for _seat: int in range(2):
		seats.append(SeatPiles.new())


## The full state as plain data, deep-copied. Two states are equal when these are equal.
## `revealed` and `looked` are listed per seat as ascending ids.
func to_dict() -> Dictionary:
	var decks: Array = []
	var hands: Array = []
	var boards: Array = []
	var piles: Array = []
	var revealed: Array = []
	var looked: Array = []
	for held: SeatPiles in seats:
		decks.append(plain(held.deck))
		hands.append(plain(held.hand))
		boards.append(plain(held.board))
		piles.append(plain(held.pile))
		revealed.append(plain(held.revealed_ids()))
		looked.append(plain(held.looked_ids()))
	return {
		"seed": match_seed,
		"deck_ids": _plain_strings(deck_ids),
		"rng_state": rng_state,
		"round": round_number,
		"turn": turn,
		"sudden_death": sudden_death,
		"phase": phase,
		"first_seat": first_seat,
		"deck": decks,
		"hand": hands,
		"board": boards,
		"pile": piles,
		"revealed": revealed,
		"looked": looked,
		"pending": plain(pending),
		"pending_slots": plain(pending_slots),
		"energy": energy.to_dict(),
		"committed_count": plain(committed_count),
		"scores": plain(scores),
		"totals": plain(totals),
		"wins": plain(wins),
		"match_scores": plain(match_scores),
		"last_turn_winner": last_turn_winner,
		"turn_wins": plain(turn_wins),
		"last_round_winner": last_round_winner,
		"result": result.duplicate(true),
		"actions_applied": actions_applied,
		"card_states": _card_states_dict(),
		"memory": _memory_dict(),
		"walk": walk.to_dict(),
		"prompt": prompt.duplicate(true),
		"crew_uses": _crew_uses_list(),
		"seat_protections": _seat_protections_list(),
		"queue": queue.to_dict(),
		"void_grants": plain(void_grants),
	}


## A deep copy: no array, dictionary or inner object is shared with this state. The copy's
## to_dict() equals this one's.
func duplicate() -> MatchState:
	var out: MatchState = MatchState.new(match_seed)
	out.deck_ids.assign(deck_ids)
	out.rng_state = rng_state
	out.round_number = round_number
	out.turn = turn
	out.sudden_death = sudden_death
	out.phase = phase
	out.first_seat = first_seat
	out.seats.clear()
	for held: SeatPiles in seats:
		out.seats.append(held.copy())
	out.pending.assign(pending)
	out.pending_slots.assign(pending_slots)
	out.energy = energy.copy()
	out.committed_count.assign(committed_count)
	out.scores.assign(scores)
	out.totals.assign(totals)
	out.wins.assign(wins)
	out.match_scores.assign(match_scores)
	out.last_turn_winner = last_turn_winner
	out.turn_wins.assign(turn_wins)
	out.last_round_winner = last_round_winner
	out.result = result.duplicate(true)
	out.actions_applied = actions_applied
	for card: int in card_states:
		var changes: CardState = card_states[card]
		out.card_states[card] = changes.copy()
	for card: int in memory:
		var kept: CardMemory = memory[card]
		out.memory[card] = kept.copy()
	out.walk = walk.copy()
	out.prompt = prompt.duplicate(true)
	out.crew_uses.assign(_crew_uses_list())
	out.seat_protections.assign(_seat_protections_list())
	out.queue = queue.copy()
	out.void_grants.assign(void_grants)
	return out


## `card`'s Board changes, or null when it has none.
func card_state(card: int) -> CardState:
	if card_states.has(card):
		return card_states[card]
	return null


## `card`'s Board changes, created at their defaults when it has none (the writers' call).
func card_state_for(card: int) -> CardState:
	if not card_states.has(card):
		card_states[card] = CardState.new()
	return card_states[card]


## `card`'s Memory, or null when no ability has given it one. Readers use this, so reading
## never creates an entry.
func memory_of(card: int) -> CardMemory:
	if memory.has(card):
		return memory[card]
	return null


## `card`'s Memory, created at its defaults when it has none (the writers' call).
func memory_for(card: int) -> CardMemory:
	if not memory.has(card):
		memory[card] = CardMemory.new()
	return memory[card]


## Match start: each seat's Crew uses from `cards`, each Crew's CrewDef.initial_uses() (a v2
## Crew's uses are for the match). A seat that already has its counts keeps them.
func reset_crew_uses(cards: MatchCards) -> void:
	for seat: int in range(crew_uses.size()):
		var defs: Array[CrewDef] = cards.crew_for(seat)
		var held: Array = crew_uses[seat]
		if held.size() == defs.size():
			continue
		var out: Array = []
		for def: CrewDef in defs:
			out.append(def.initial_uses())
		crew_uses[seat] = out


## Drops `card`'s Board changes: call whenever the card leaves its row. True when it had any.
func clear_card_state(card: int) -> bool:
	return card_states.erase(card)


## The seat whose piles hold `card` (its Controller on a row; the holder of a hand, Deck or
## Pile), or the first committer for a card in the face-down `pending` Commit; -1 when no
## pile holds it.
func controller_of(card: int) -> int:
	if pending.has(card):
		return first_seat
	for seat: int in range(seats.size()):
		if seats[seat].holds(card):
			return seat
	return -1


## Takes `card` off `seat`'s row: it leaves the row, the revealed set and every seat's
## `looked`, and its Board changes go (R30). Returns whether the card had been revealed;
## false, changing nothing, when it was not on that row. Where it goes next is the caller's.
func take_from_row(seat: int, card: int) -> bool:
	var held: SeatPiles = seats[seat]
	var slot: int = held.board.find(card)
	if slot < 0:
		return false
	held.board.remove_at(slot)
	if clear_card_state(card):
		pass  # Its Board changes leave the row with it.
	for watcher: SeatPiles in seats:
		if watcher.looked.erase(card):
			pass  # A looked-at card is no longer face down on a row.
	return held.revealed.erase(card)


## The Board changes as plain data, keyed by instance id.
func _card_states_dict() -> Dictionary:
	var out: Dictionary = {}
	for card: int in card_states:
		var changes: CardState = card_states[card]
		out[card] = changes.to_dict()
	return out


## The Memory as plain data, keyed by instance id.
func _memory_dict() -> Dictionary:
	var out: Dictionary = {}
	for card: int in memory:
		var kept: CardMemory = memory[card]
		out[card] = kept.to_dict()
	return out


## The Crew uses per seat as plain, copied lists (to_dict() and duplicate()).
func _crew_uses_list() -> Array:
	var out: Array = []
	for seat_uses: Array in crew_uses:
		out.append(seat_uses.duplicate())
	return out


## The seat protections as deep-copied dictionaries (to_dict() and duplicate()).
func _seat_protections_list() -> Array:
	var out: Array = []
	for held: Dictionary in seat_protections:
		out.append(held.duplicate(true))
	return out


## An untyped copy of the deck ids, for to_dict().
static func _plain_strings(values: Array[String]) -> Array:
	var out: Array = []
	out.assign(values)
	return out


## An untyped copy, so serialized forms hold plain data only.
static func plain(values: Array[int]) -> Array:
	var out: Array = []
	out.assign(values)
	return out


## One seat's card zones, as ordered instance ids. `board` is the ordered row (R4): a card's
## slot is its index. `pile` is the seat's public Pile in Pile order (R19 to R21).
class SeatPiles:
	extends RefCounted

	var deck: Array[int] = []
	var hand: Array[int] = []
	var board: Array[int] = []
	var pile: Array[int] = []
	## Cards on the row that have been revealed.
	var revealed: Dictionary[int, bool] = {}
	## Opposing face-down row cards this seat has looked at (Lookout, P15), by instance id;
	## an entry leaves when the card is revealed or leaves its row.
	var looked: Dictionary[int, bool] = {}

	## The revealed card ids, ascending.
	func revealed_ids() -> Array[int]:
		var out: Array[int] = []
		out.assign(revealed.keys())
		out.sort()
		return out

	## The looked-at card ids, ascending.
	func looked_ids() -> Array[int]:
		var out: Array[int] = []
		out.assign(looked.keys())
		out.sort()
		return out

	## Whether `card` has been revealed on this row.
	func is_revealed(card: int) -> bool:
		return revealed.has(card) and revealed[card]

	## Whether any of these zones holds `card`.
	func holds(card: int) -> bool:
		return deck.has(card) or hand.has(card) or board.has(card) or pile.has(card)

	func copy() -> SeatPiles:
		var out: SeatPiles = SeatPiles.new()
		out.deck.assign(deck)
		out.hand.assign(hand)
		out.board.assign(board)
		out.pile.assign(pile)
		out.revealed.assign(revealed)
		out.looked.assign(looked)
		return out


## Per-seat Energy, each pair indexed by seat (R6, R7). The Budget is turn + `grants` (plus
## any Crew bonus, TurnFlow.budget); nothing carries. `next_turn_grants` (milestone B, Tithe)
## move into `grants` when a Turn ends; a true `free_first` makes the leftmost card of that
## seat's next Commit cost 0 and is consumed by that Commit or the next turn end (Lantern);
## `spent` is what the seat's Commit this Turn cost. `free_first_next` (DC-13 T06) is a
## free first card granted for the next Turn (Lantern's On reveal): at turn end it becomes
## `free_first` (Abilities.end_turn_changes), and a `free_first` not used that Turn ends.
class EnergyState:
	extends RefCounted

	var grants: Array[int] = [0, 0]
	var next_turn_grants: Array[int] = [0, 0]
	var free_first: Array[bool] = [false, false]
	var spent: Array[int] = [0, 0]
	var free_first_next: Array[bool] = [false, false]

	func copy() -> EnergyState:
		var out: EnergyState = EnergyState.new()
		out.grants.assign(grants)
		out.next_turn_grants.assign(next_turn_grants)
		out.free_first.assign(free_first)
		out.spent.assign(spent)
		out.free_first_next.assign(free_first_next)
		return out

	func to_dict() -> Dictionary:
		var flags: Array = []
		flags.assign(free_first)
		var next_flags: Array = []
		next_flags.assign(free_first_next)
		return {
			"grants": MatchState.plain(grants),
			"next_turn_grants": MatchState.plain(next_turn_grants),
			"free_first": flags,
			"spent": MatchState.plain(spent),
			"free_first_next": next_flags,
		}


## The Walk's progress, written only by ScoreWalk. `active` holds from ScoreWalk.begin()
## until a pulse finds no slot left. `next_seat` is the seat whose row is tried first on the
## next pulse; `cursor` is, per seat, the number of that row's slots the Walk has passed, so
## the next slot of a row is its cursor (cycle 5 cursor rules); `scored` holds every card
## that Scored at least once this Walk; `scored_count` the Scores per seat this Walk (a card
## Scoring twice counts twice; Navigator and Tallyman read it, T07). DC-13 T05:
## `resolutions` counts the trigger resolutions of the pulse in progress (Q4, reset at each
## pulse); `pulse_seat` and `pulse_slot` name that pulse (a drain paused in its D7 resumes
## its score stage); `scores_twice` (Q7) runs the score stage of every later pulse twice
## (`pulse_twice` is its value when the pulse in progress started), and
## `retrigger_on_reveal[seat]` lists the cards whose retrigger applies to that seat's other
## On reveals (Q6); both last the Turn (TurnFlow clears them at turn end). DC-14 T13, the
## reveal-stage hook (Skip): `hook_pending` counts the Skips waiting for the next reveal;
## that reveal arms `hook_card` with `hook_moves` moves, made after its D7
## (AbilitiesGraveyardControl.arm_skip, skip_hook); ScoreWalk.begin clears all three.
class WalkState:
	extends RefCounted

	var active: bool = false
	var next_seat: int = 0
	var cursor: Array[int] = [0, 0]
	var scored: Dictionary[int, bool] = {}
	var scored_count: Array[int] = [0, 0]
	var resolutions: int = 0
	var pulse_seat: int = -1
	var pulse_slot: int = -1
	var scores_twice: bool = false
	var pulse_twice: bool = false
	var retrigger_on_reveal: Array[Array] = [[], []]
	var hook_pending: int = 0
	## -1 when no reveal is armed.
	var hook_card: int = -1
	var hook_moves: int = 0

	## The ids of the cards Scored this Walk, ascending.
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
		out.scored_count.assign(scored_count)
		out.resolutions = resolutions
		out.pulse_seat = pulse_seat
		out.pulse_slot = pulse_slot
		out.scores_twice = scores_twice
		out.pulse_twice = pulse_twice
		out.retrigger_on_reveal.assign(_retriggers())
		out.hook_pending = hook_pending
		out.hook_card = hook_card
		out.hook_moves = hook_moves
		return out

	func to_dict() -> Dictionary:
		return {
			"active": active,
			"next_seat": next_seat,
			"cursor": MatchState.plain(cursor),
			"scored": MatchState.plain(scored_ids()),
			"scored_count": MatchState.plain(scored_count),
			"resolutions": resolutions,
			"pulse_seat": pulse_seat,
			"pulse_slot": pulse_slot,
			"scores_twice": scores_twice,
			"pulse_twice": pulse_twice,
			"retrigger_on_reveal": _retriggers(),
			"hook_pending": hook_pending,
			"hook_card": hook_card,
			"hook_moves": hook_moves,
		}

	## Clears the Turn's retriggers and Scores twice (turn end).
	func clear_turn_effects() -> void:
		scores_twice = false
		for sources: Array in retrigger_on_reveal:
			sources.clear()

	## The retrigger sources per seat as plain, copied lists.
	func _retriggers() -> Array:
		var out: Array = []
		for sources: Array in retrigger_on_reveal:
			out.append(sources.duplicate())
		return out
