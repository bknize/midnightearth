class_name Statuses
extends RefCounted
## Statuses, protections and exit marks (cycle 9 plan P8, P9; spec R32 to R41; the canon's
## glossary section 9, resolution step 12 and section 4). Static and pure over a MatchState:
## no node, no clock, no randomness. Events go to `sink` as sink.call(kind, payload, owner)
## when the sink is valid.
##
## - The seven statuses: MUTED, SQUELCHED, SILENCED, ANCHORED and the exit marks CONDEMNED,
##   FLEETING, FADE. Silenced is never stored: it is both halves (MUTED and SQUELCHED)
##   present, so ending one half leaves the other (R34, C22). Each half keeps its own
##   cessation (cessation()): "turn" ends at turn end (on_turn_end()), "permanent" is Memory
##   (CardMemory.permanent_statuses) and survives the Pile, a redraw and an un-reveal (R35,
##   R36), "condition" ends when its condition is met (CONDITION_SOURCE_ON_ROW: the source
##   card leaves its row or is Un-revealed). Board-scoped statuses live in
##   CardState.statuses and end when the card leaves its row (on_leave_row()) or is
##   Un-revealed (on_unreveal()).
## - apply() gives a status; it drops only the part a protection blocks (R37, C24: a Silence
##   against "cannot be Muted" lands Squelched only) and never ends an X already in place.
##   Its Applied result says what landed and whether On squelch wakes: only when the
##   Squelched half lands on a card that was not Squelched and is not Muted after (R34). The
##   trigger queue (DC-13 T05) reads `Applied.wakes_squelch` to wake the card's On squelch.
## - Protections: a seat's (Ward, MatchState.seat_protections, over the cards on that seat's
##   row), a card's own from an effect (CardState.protections), and the Ongoing ones read
##   from the definition while the Ongoing is read (Bastion `cannot_condemn_self`). An
##   Ongoing is read on a revealed row card that is not Squelched (Scoring.reads_ongoing).
## - Anchored (is_anchored()): the status, or Brace's Ongoing `anchored_self` while read.
## - Exit marks (mark_exit()): at most one per card, a newer replaces an older (R38),
##   EXIT_MARKED {card, mark, replaced}. A marked card still Scores and fires (R39).
## - exit_pass() (resolution step 12, R41): the first seat's row first, each in slot order;
##   the Ongoings that change exit marks are read once at its start (Wraith); Condemned to
##   its Owner's Pile as a Discard (reason condemned), Fleeting to its Owner's hand
##   (CARD_RETURNED {owner, card, seat, slot}), Fade flips face down in place
##   (CARD_UNREVEALED), each announced by EXIT_RESOLVED {card, mark, owner, to, seat, slot}
##   (+ `instead_of`, the mark an "instead" replaced). `seat` is the row's and `slot` the
##   card's index before it leaves, so the other seat can find a hidden card's exit by slot
##   (its redacted copy hides `card`, `mark` and `instead_of`, MatchEvent.redacted_for).
##   Returns the Discarded cards, in pass order, for the D10 On discard Batches.
##
## STATUS_SET {card, status, cessation, cause} carries the half's word (`status`) and the
## cessation's kind; STATUS_ENDED {card, status, cause}. An event about a face-down card is
## private to the seat whose row holds it (the other seat's copy hides `card`).

const MUTED: String = "muted"
const SQUELCHED: String = "squelched"
const SILENCED: String = "silenced"
const ANCHORED: String = "anchored"
const CONDEMNED: String = "condemned"
const FLEETING: String = "fleeting"
const FADE: String = "fade"
## The exit marks (R38).
const EXIT_MARKS: Array[String] = [CONDEMNED, FLEETING, FADE]
## The badge word of each status, as the view lists them (glossary section 9).
const BADGES: Dictionary[String, String] = {
	MUTED: "Muted",
	SQUELCHED: "Squelched",
	SILENCED: "Silenced",
	ANCHORED: "Anchored",
	CONDEMNED: "Condemned",
	FLEETING: "Fleeting",
	FADE: "Fade",
}
## Cessation kinds (plan P8).
const CEASE_TURN: String = "turn"
const CEASE_PERMANENT: String = "permanent"
const CEASE_CONDITION: String = "condition"
const KEY_KIND: String = "kind"
const KEY_CONDITION: String = "condition"
const KEY_SOURCE: String = "source"
## The one named condition: the status lasts while its source card stays face up on its row
## (Pin, Stasis).
const CONDITION_SOURCE_ON_ROW: String = "source_on_row"
## STATUS_ENDED causes the rules give.
const CAUSE_TURN_END: String = "turn_end"
const CAUSE_LEAVE_ROW: String = "leave_row"
const CAUSE_UNREVEAL: String = "unreveal"
## EXIT_RESOLVED `to`.
const TO_PILE: String = "pile"
const TO_HAND: String = "hand"
const TO_FACE_DOWN: String = "face_down"
## Ongoing verbs that make their own card unable to take a status, while read (plan P3).
const PROTECTING_VERBS: Dictionary[String, String] = {"cannot_condemn_self": CONDEMNED}
## The Ongoing verb that makes its own card Anchored while read (Brace).
const ANCHOR_VERB: String = "anchored_self"
## Ongoing verbs that change exit marks (Wraith): read once per exit pass.
const EXIT_CHANGING_VERBS: Array[String] = [AbilitiesGraveyardControl.VERB_WRAITH]

# --- Reading ----------------------------------------------------------------------------


## A cessation (plan P8): {kind, condition, source}.
static func cessation(kind: String, condition: String = "", source: int = -1) -> Dictionary:
	return {KEY_KIND: kind, KEY_CONDITION: condition, KEY_SOURCE: source}


## Whether `card` holds `status` now: a half (board or permanent), ANCHORED as a status
## (not Brace's Ongoing: is_anchored()), SILENCED when both halves are held, an exit mark
## when it is the card's mark.
static func has(state: MatchState, card: int, status: String) -> bool:
	if status == SILENCED:
		return has(state, card, MUTED) and has(state, card, SQUELCHED)
	var held: CardState = state.card_state(card)
	if EXIT_MARKS.has(status):
		return held != null and held.exit_mark == status
	if held != null and held.statuses.has(status):
		return true
	var kept: CardMemory = state.memory_of(card)
	return kept != null and kept.permanent_statuses.has(status)


## Whether `card`'s triggered abilities fire (R33): not while Muted (or Silenced).
static func fires(state: MatchState, card: int) -> bool:
	return not has(state, card, MUTED)


## Whether `card` cannot be moved by an effect (R40): the Anchored status, or its own
## Ongoing `anchored_self` while read (Brace).
static func is_anchored(state: MatchState, cards: MatchCards, card: int) -> bool:
	return has(state, card, ANCHORED) or _reads_own(state, cards, card, ANCHOR_VERB)


## Whether `status` cannot be applied to `card` now (R37): its row seat's protection
## (Ward), its own protection from an effect, or its read Ongoing (Bastion).
static func is_protected(state: MatchState, cards: MatchCards, card: int, status: String) -> bool:
	var seat: int = row_seat(state, card)
	if seat >= 0 and state.seat_protections[seat].has(status):
		return true
	var held: CardState = state.card_state(card)
	if held != null and held.protections.has(status):
		return true
	for verb: String in PROTECTING_VERBS:
		if PROTECTING_VERBS[verb] == status and _reads_own(state, cards, card, verb):
			return true
	return false


## `card`'s exit mark, "" for none.
static func exit_mark_of(state: MatchState, card: int) -> String:
	var held: CardState = state.card_state(card)
	return held.exit_mark if held != null else ""


## The badge words `card` shows (the view's `statuses`, CARD_REVEALED's): Silenced, or
## Muted / Squelched; Anchored (the status or a read Brace); its exit mark's word.
static func badges(state: MatchState, cards: MatchCards, card: int) -> Array[String]:
	var out: Array[String] = []
	var muted: bool = has(state, card, MUTED)
	var squelched: bool = has(state, card, SQUELCHED)
	if muted and squelched:
		out.append(BADGES[SILENCED])
	elif muted:
		out.append(BADGES[MUTED])
	elif squelched:
		out.append(BADGES[SQUELCHED])
	if is_anchored(state, cards, card):
		out.append(BADGES[ANCHORED])
	var mark: String = exit_mark_of(state, card)
	if mark != "":
		out.append(BADGES[mark])
	return out


## The seat whose row holds `card`, or -1.
static func row_seat(state: MatchState, card: int) -> int:
	for seat: int in range(state.seats.size()):
		if state.seats[seat].board.has(card):
			return seat
	return -1


# --- Giving and ending ------------------------------------------------------------------


## Gives `card` (on a row) `status` with `p_cessation` (R32 to R37). SILENCED gives both
## halves; an exit mark goes through mark_exit(). A part a protection blocks is dropped and
## listed in `blocked`; each landed half emits STATUS_SET. A card on no row takes nothing.
static func apply(
	state: MatchState,
	cards: MatchCards,
	card: int,
	status: String,
	p_cessation: Dictionary,
	cause: String,
	sink: Callable
) -> Applied:
	var out: Applied = Applied.new()
	if EXIT_MARKS.has(status):
		if mark_exit(state, cards, card, status, sink):
			out.landed.append(status)
		else:
			out.blocked.append(status)
		return out
	if row_seat(state, card) < 0:
		return out
	var parts: Array[String] = _parts(status)
	var was_squelched: bool = has(state, card, SQUELCHED)
	for part: String in parts:
		if is_protected(state, cards, card, part):
			out.blocked.append(part)
			continue
		_hold(state, card, part, p_cessation)
		out.landed.append(part)
		var kind: String = p_cessation.get(KEY_KIND, CEASE_TURN)
		var payload: Dictionary = {"card": card, "status": part, "cessation": kind, "cause": cause}
		_emit(state, sink, MatchEvent.Kind.STATUS_SET, payload, card)
	out.wakes_squelch = (
		out.landed.has(SQUELCHED) and not was_squelched and not has(state, card, MUTED)
	)
	return out


## Ends `status` on `card`, board-scoped and permanent alike (SILENCED ends both halves, an
## exit mark clears the mark): one STATUS_ENDED per status it held. True when any ended.
static func end(
	state: MatchState, card: int, status: String, cause: String, sink: Callable
) -> bool:
	var parts: Array[String] = _parts(status)
	var ended: bool = false
	for part: String in parts:
		if not has(state, card, part):
			continue
		var held: CardState = state.card_state(card)
		if held != null:
			if EXIT_MARKS.has(part):
				held.exit_mark = ""
			elif held.statuses.erase(part):
				pass  # The board-scoped half goes.
		var kept: CardMemory = state.memory_of(card)
		if kept != null:
			kept.permanent_statuses.erase(part)
		_emit(state, sink, MatchEvent.Kind.STATUS_ENDED, _ended(card, part, cause), card)
		ended = true
	return ended


## Gives `card` (on a row) the exit mark `mark` (R38): blocked by a protection (Bastion),
## else it replaces any older mark, EXIT_MARKED {card, mark, replaced} ("" for none). True
## when the mark landed.
static func mark_exit(
	state: MatchState, cards: MatchCards, card: int, mark: String, sink: Callable
) -> bool:
	if not EXIT_MARKS.has(mark) or row_seat(state, card) < 0:
		return false
	if is_protected(state, cards, card, mark):
		return false
	var held: CardState = state.card_state_for(card)
	var replaced: String = held.exit_mark
	held.exit_mark = mark
	var payload: Dictionary = {"card": card, "mark": mark, "replaced": replaced}
	_emit(state, sink, MatchEvent.Kind.EXIT_MARKED, payload, card)
	return true


## Gives `seat` the protection `status` over the cards on its row until `p_cessation` ends
## (Ward: MUTED, turn). It ends nothing already in place (R37).
static func protect_seat(
	state: MatchState, seat: int, status: String, p_cessation: Dictionary
) -> void:
	state.seat_protections[seat][status] = p_cessation.duplicate(true)


## Makes `card` unable to take `status` while it stays on its row (a Board change).
static func protect_card(state: MatchState, card: int, status: String) -> void:
	var held: CardState = state.card_state_for(card)
	if not held.protections.has(status):
		held.protections.append(status)


# --- Scope ends -------------------------------------------------------------------------


## Turn end, step 14 (R35): every "turn" status on every card ends, and every "condition"
## one whose condition is met (STATUS_ENDED, cause turn_end), cards in ascending id; the
## seats' "turn" protections end too. Exit marks are untouched: one given after the exit
## pass waits for the next turn end.
static func on_turn_end(state: MatchState, sink: Callable) -> void:
	var ids: Array[int] = []
	ids.assign(state.card_states.keys())
	ids.sort()
	for card: int in ids:
		var held: CardState = state.card_states[card]
		var listed: Array[String] = []
		listed.assign(held.statuses.keys())
		for status: String in listed:
			var cease: Dictionary = held.statuses[status]
			if _ends_at_turn_end(state, cease):
				_end_board(state, card, status, CAUSE_TURN_END, sink)
	for seat: int in range(state.seat_protections.size()):
		var guards: Dictionary = state.seat_protections[seat]
		for status: Variant in guards.keys():
			var cease: Dictionary = guards[status]
			if _ends_at_turn_end(state, cease) and guards.erase(status):
				pass  # The seat's protection lapses.


## `card` is leaving its row (R36): every status whose condition names it as source ends on
## the cards still on the rows. Its own board-scoped statuses leave with its Board changes
## (MatchState.take_from_row); a permanent one stays in Memory.
static func on_leave_row(state: MatchState, card: int, sink: Callable) -> void:
	_end_sourced(state, card, CAUSE_LEAVE_ROW, sink)


## `card` is Un-revealed (R36, glossary Un-reveal): its board-scoped statuses end
## (STATUS_ENDED, cause unreveal), its Board changes go, every status sourced by it ends; its
## Memory stays.
static func on_unreveal(state: MatchState, card: int, sink: Callable) -> void:
	var held: CardState = state.card_state(card)
	if held != null:
		var listed: Array[String] = []
		listed.assign(held.statuses.keys())
		for status: String in listed:
			var ended: Dictionary = _ended(card, status, CAUSE_UNREVEAL)
			_emit(state, sink, MatchEvent.Kind.STATUS_ENDED, ended, card)
		if state.clear_card_state(card):
			pass  # An Un-revealed card loses its Board changes.
	_end_sourced(state, card, CAUSE_UNREVEAL, sink)


## Takes `card` off `seat`'s row with its scope ends (on_leave_row(), then
## MatchState.take_from_row). Returns whether it had been revealed.
static func take_from_row(state: MatchState, seat: int, card: int, sink: Callable) -> bool:
	on_leave_row(state, card, sink)
	return state.take_from_row(seat, card)


## Flips `card` face down in its slot on `seat`'s row (Un-reveal): on_unreveal(), then it
## leaves the revealed set and CARD_UNREVEALED {seat, card, slot} is public. False, changing
## only the Board changes, when it was already face down.
static func unreveal(state: MatchState, seat: int, card: int, sink: Callable) -> bool:
	var piles: MatchState.SeatPiles = state.seats[seat]
	on_unreveal(state, card, sink)
	if not piles.revealed.erase(card):
		return false
	var payload: Dictionary = {"seat": seat, "card": card, "slot": piles.board.find(card)}
	_emit_to(sink, MatchEvent.Kind.CARD_UNREVEALED, payload, MatchEvent.PUBLIC)
	return true


# --- The exit pass ----------------------------------------------------------------------


## The exit pass (resolution step 12, R41). Returns the cards sent to a Pile as Discards,
## in pass order.
static func exit_pass(state: MatchState, cards: MatchCards, sink: Callable) -> Array[int]:
	var read: Array[Array] = _exit_ongoings(state, cards)
	var discarded: Array[int] = []
	for seat: int in [state.first_seat, 1 - state.first_seat]:
		var row: Array[int] = []
		row.assign(state.seats[seat].board)
		for card: int in row:
			var held: String = exit_mark_of(state, card)
			var mark: String = _mark_under(held, read[seat])
			if mark != "" and _resolve_exit(state, cards, sink, seat, card, mark, held):
				discarded.append(card)
	return discarded


## Resolves `mark` on `card` of `seat`'s row; true when it was Discarded. `held` is the
## mark the card held when an "instead" changed it (EXIT_RESOLVED `instead_of`, Wraith).
static func _resolve_exit(
	state: MatchState,
	cards: MatchCards,
	sink: Callable,
	seat: int,
	card: int,
	mark: String,
	held: String = ""
) -> bool:
	var owner: int = cards.origin_of(card) if cards != null else -1
	if owner < 0:
		owner = seat
	var piles: MatchState.SeatPiles = state.seats[seat]
	var hidden: bool = not piles.is_revealed(card)
	var to: String = TO_FACE_DOWN
	if mark == CONDEMNED:
		to = TO_PILE
	elif mark == FLEETING:
		to = TO_HAND
	state.card_state_for(card).exit_mark = ""
	var slot: int = piles.board.find(card)  # Before it leaves: the other seat finds it by slot.
	var resolved: Dictionary = {
		"card": card, "mark": mark, "owner": owner, "to": to, "seat": seat, "slot": slot
	}
	if held != "" and held != mark:
		resolved["instead_of"] = held
	# A face-down card that stays hidden (to its hand, or a Fade that leaves it face down)
	# is private to its seat; one going to a Pile is public there (DC-14 T14 leak scan).
	var privately: int = seat if hidden and to != TO_PILE else MatchEvent.PUBLIC
	_emit_to(sink, MatchEvent.Kind.EXIT_RESOLVED, resolved, privately)
	if to == TO_FACE_DOWN:
		if unreveal(state, seat, card, sink):
			pass  # Fade: face down in place, Memory kept.
		return false
	if take_from_row(state, seat, card, sink):
		pass  # Revealed or not, the card leaves its row.
	if to == TO_PILE:
		TurnFlow.to_pile(state, cards, sink, card, TurnFlow.FROM_ROW, TurnFlow.REASON_CONDEMNED)
		return true
	state.seats[owner].hand.append(card)
	var returned: Dictionary = {"owner": owner, "card": card, "seat": seat, "slot": slot}
	_emit_to(sink, MatchEvent.Kind.CARD_RETURNED, returned, owner if hidden else MatchEvent.PUBLIC)
	return false


## The Ongoings that change exit marks, read once at the start of the pass (Wraith, DC-14
## T13): per seat, the EXIT_CHANGING_VERBS read on that seat's row (revealed, not
## Squelched), so a Wraith Condemned in this pass still applies to every card of its row.
static func _exit_ongoings(state: MatchState, cards: MatchCards) -> Array[Array]:
	var out: Array[Array] = []
	for seat: int in range(state.seats.size()):
		var verbs: Array = []
		for verb: String in EXIT_CHANGING_VERBS:
			if not Scoring.ongoing_on_row(state, cards, seat, verb).is_empty():
				verbs.append(verb)
		out.append(verbs)
	return out


## The mark that resolves for `mark` on a card of a row whose exit-changing Ongoings are
## `read`: Wraith ("your Condemned cards have Fade instead") turns Condemned into Fade.
## Veil (CrewAbilities, At turn end before the pass, D9) has already turned its card
## Fleeting, which Wraith leaves alone, so Veil wins (cards-v2 section 4).
static func _mark_under(mark: String, read: Array) -> String:
	if mark == CONDEMNED and read.has(AbilitiesGraveyardControl.VERB_WRAITH):
		return FADE
	return mark


# --- Helpers ----------------------------------------------------------------------------


## The parts `status` stands for: both halves for SILENCED, else itself.
static func _parts(status: String) -> Array[String]:
	var out: Array[String] = []
	if status == SILENCED:
		out.append(MUTED)
		out.append(SQUELCHED)
	else:
		out.append(status)
	return out


## Holds the half (or ANCHORED) `part` on `card`: in Memory when permanent, else as a Board
## change with its cessation (a newer cessation replaces an older one).
static func _hold(state: MatchState, card: int, part: String, p_cessation: Dictionary) -> void:
	var kind: String = p_cessation.get(KEY_KIND, CEASE_TURN)
	if kind == CEASE_PERMANENT:
		var kept: CardMemory = state.memory_for(card)
		if not kept.permanent_statuses.has(part):
			kept.permanent_statuses.append(part)
		return
	var held: CardState = state.card_state_for(card)
	var stored: Dictionary = cessation(kind)
	stored.merge(p_cessation, true)
	held.statuses[part] = stored


## Whether a cessation ends at turn end: "turn", or a met condition.
static func _ends_at_turn_end(state: MatchState, cease: Dictionary) -> bool:
	var kind: String = cease.get(KEY_KIND, CEASE_TURN)
	if kind == CEASE_TURN:
		return true
	if kind != CEASE_CONDITION:
		return false
	var condition: String = cease.get(KEY_CONDITION, "")
	var source: int = cease.get(KEY_SOURCE, -1)
	if condition == CONDITION_SOURCE_ON_ROW:
		var seat: int = row_seat(state, source)
		return seat < 0 or not state.seats[seat].is_revealed(source)
	return false


## Ends the board-scoped `status` of `card` with STATUS_ENDED.
static func _end_board(
	state: MatchState, card: int, status: String, cause: String, sink: Callable
) -> void:
	var held: CardState = state.card_state(card)
	if held == null or not held.statuses.erase(status):
		return
	_emit(state, sink, MatchEvent.Kind.STATUS_ENDED, _ended(card, status, cause), card)


## Ends, on every other card, each status whose condition is sourced by `source`.
static func _end_sourced(state: MatchState, source: int, cause: String, sink: Callable) -> void:
	var ids: Array[int] = []
	ids.assign(state.card_states.keys())
	ids.sort()
	for card: int in ids:
		if card == source:
			continue
		var held: CardState = state.card_states[card]
		var listed: Array[String] = []
		listed.assign(held.statuses.keys())
		for status: String in listed:
			var cease: Dictionary = held.statuses[status]
			var kind: String = cease.get(KEY_KIND, CEASE_TURN)
			var from: int = cease.get(KEY_SOURCE, -1)
			if kind == CEASE_CONDITION and from == source:
				_end_board(state, card, status, cause, sink)


## Whether `card`'s own Ongoing with `verb` is read now: a revealed row card, not Squelched
## (AbilitiesGraveyardControl.own_ongoing, which skips a verb no card of the match carries).
static func _reads_own(state: MatchState, cards: MatchCards, card: int, verb: String) -> bool:
	if cards == null:
		return false
	return AbilitiesGraveyardControl.own_ongoing(state, cards, card, verb) != null


## The STATUS_ENDED payload.
static func _ended(card: int, status: String, cause: String) -> Dictionary:
	return {"card": card, "status": status, "cause": cause}


## Emits an event about `card`: private to its row seat while it is face down there.
static func _emit(
	state: MatchState, sink: Callable, kind: int, payload: Dictionary, card: int
) -> void:
	var owner: int = MatchEvent.PUBLIC
	var seat: int = row_seat(state, card)
	if seat >= 0 and not state.seats[seat].is_revealed(card):
		owner = seat
	_emit_to(sink, kind, payload, owner)


static func _emit_to(sink: Callable, kind: int, payload: Dictionary, owner: int) -> void:
	if sink.is_valid():
		sink.call(kind, payload, owner)


## What apply() did: the parts that `landed` and those a protection `blocked`, and whether
## the card's On squelch wakes (`wakes_squelch`, read by the trigger queue, DC-13 T05).
class Applied:
	extends RefCounted

	var landed: Array[String] = []
	var blocked: Array[String] = []
	var wakes_squelch: bool = false

	## True when any part landed.
	func ok() -> bool:
		return not landed.is_empty()
