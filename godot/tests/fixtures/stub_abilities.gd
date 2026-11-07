class_name StubAbilities
extends RefCounted
## Stub verbs for the rules no milestone A card exercises (cycle 9 plan, "Milestone A verb
## table"; DC-13 T04): each applies its rule straight through Statuses or Movement with the
## verb's name as the cause, and returns what the rule returns, so a suite can read what a
## trigger would wake (Statuses.Applied.wakes_squelch for On squelch, the moved cards for
## On moved). DC-13 T05 adds the queue stubs (`stub_retrigger`, `stub_scores_twice`,
## `stub_condemn_random_and_rescore`). Not a suite: builders only, nothing cached.
##
## The stub match plays the deck `stubs` on both seats: ten shipped cards, four copies each,
## so seat `s`'s card of pool position `index` is `s * DECK_SIZE + index` (constants below
## for seat 0: add MatchRules.DECK_SIZE for seat 1).

const DECK_ID: String = "stubs"
## The deck's ids, four copies each, in this order.
const IDS: Array[String] = [
	"ev01", "ev02", "ev04", "ev05", "ev08", "ev11", "ev15", "ev20", "gr03", "gr06"
]
## Seat 0's first instance of each (copies follow: MOTE, MOTE + 1 ... MOTE + 3).
const MOTE: int = 0  # Power 2, plain
const WISP: int = 4  # Power 1, Mult x1.25, plain
const PEBBLE: int = 8  # Power 3, plain
const SCOUT: int = 12  # On reveal: draw a card
const SCAPEGOAT: int = 16  # On squelch
const NUDGE: int = 20  # On reveal: move this card one slot right
const BRACE: int = 24  # Ongoing: this card is Anchored
const BASTION: int = 28  # Ongoing: this card cannot be Condemned
const FLARE: int = 32  # On reveal: Condemn this card
const COURIER: int = 36  # On score: draw a card
const VERB_MUTE: String = "stub_mute"
const VERB_SQUELCH: String = "stub_squelch"
const VERB_SILENCE: String = "stub_silence"
const VERB_CONDEMN: String = "stub_condemn"
const VERB_FLEETING: String = "stub_fleeting"
const VERB_FADE: String = "stub_fade"
const VERB_SHIFT_OTHERS_LEFT: String = "stub_shift_others_left"
const VERB_SWAP: String = "stub_swap"
const VERB_REVERSE: String = "stub_reverse"


## The definitions of a stubs-vs-stubs match over the shipped pool.
static func defs() -> MatchCards:
	var listed: Array = []
	for id: String in IDS:
		for _copy: int in range(MatchRules.MAX_COPIES):
			listed.append(id)
	var deck: Dictionary = {
		"id": DECK_ID,
		"name": "Stubs",
		"tag": "evergreen",
		"theme": "Shipped cards for the status, exit and movement suites.",
		"cards": listed,
		"crew": ["tallyman", "void", "engineer"],
	}
	var decks: DeckList = DeckList.from_json(
		JSON.stringify({"version": DeckList.FORMAT_VERSION, "decks": [deck]})
	)
	var ids: Array[String] = [DECK_ID, DECK_ID]
	return MatchCards.build(CardDb.load_default(), decks, ids, CrewPool.load_default())


## A fresh state whose `seat` row is `row` (face up when `revealed`), first seat 0.
static func table(row: Array[int], revealed: bool, seat: int = 0) -> MatchState:
	var state: MatchState = MatchState.new(1)
	put_row(state, seat, row, revealed)
	return state


## Sets `seat`'s row of `state` to `row`, each card face up when `revealed`.
static func put_row(state: MatchState, seat: int, row: Array[int], revealed: bool) -> void:
	var piles: MatchState.SeatPiles = state.seats[seat]
	piles.board.assign(row)
	for card: int in row:
		if revealed:
			piles.revealed[card] = true


## Mutes `card` with `cessation` (default: until end of turn).
static func stub_mute(
	state: MatchState, cards: MatchCards, card: int, sink: Callable, cessation: Dictionary = {}
) -> Statuses.Applied:
	return Statuses.apply(state, cards, card, Statuses.MUTED, _cease(cessation), VERB_MUTE, sink)


## Squelches `card` with `cessation` (default: until end of turn).
static func stub_squelch(
	state: MatchState, cards: MatchCards, card: int, sink: Callable, cessation: Dictionary = {}
) -> Statuses.Applied:
	var cease: Dictionary = _cease(cessation)
	return Statuses.apply(state, cards, card, Statuses.SQUELCHED, cease, VERB_SQUELCH, sink)


## Silences `card` (both halves) with `cessation` (default: until end of turn).
static func stub_silence(
	state: MatchState, cards: MatchCards, card: int, sink: Callable, cessation: Dictionary = {}
) -> Statuses.Applied:
	var cease: Dictionary = _cease(cessation)
	return Statuses.apply(state, cards, card, Statuses.SILENCED, cease, VERB_SILENCE, sink)


## Condemns `card`; true when the mark landed.
static func stub_condemn(
	state: MatchState, cards: MatchCards, card: int, sink: Callable
) -> bool:
	return Statuses.mark_exit(state, cards, card, Statuses.CONDEMNED, sink)


## Gives `card` Fleeting; true when the mark landed.
static func stub_fleeting(
	state: MatchState, cards: MatchCards, card: int, sink: Callable
) -> bool:
	return Statuses.mark_exit(state, cards, card, Statuses.FLEETING, sink)


## Gives `card` Fade; true when the mark landed.
static func stub_fade(state: MatchState, cards: MatchCards, card: int, sink: Callable) -> bool:
	return Statuses.mark_exit(state, cards, card, Statuses.FADE, sink)


## "Your other cards each move one slot left": every card of `seat`'s row but `source` (-1
## for none) steps left at once; returns the On moved cards.
static func stub_shift_others_left(
	state: MatchState, cards: MatchCards, seat: int, source: int, sink: Callable
) -> Array[int]:
	var movers: Array[int] = []
	for card: int in state.seats[seat].board:
		if card != source:
			movers.append(card)
	return Movement.step_left_set(state, cards, seat, movers, VERB_SHIFT_OTHERS_LEFT, sink)


## Swaps `a` and `b`; returns the On moved cards (empty when it fizzles).
static func stub_swap(
	state: MatchState, cards: MatchCards, a: int, b: int, sink: Callable
) -> Array[int]:
	return Movement.swap(state, cards, a, b, VERB_SWAP, sink)


## Reverses `seat`'s row; returns the On moved cards.
static func stub_reverse(
	state: MatchState, cards: MatchCards, seat: int, sink: Callable
) -> Array[int]:
	return Movement.reverse(state, cards, seat, VERB_REVERSE, sink)


## A new event recorder: pass `recorder.record` as a sink.
static func recorder() -> Recorder:
	return Recorder.new()


## `cessation`, or "until end of turn" when empty.
static func _cease(cessation: Dictionary) -> Dictionary:
	if cessation.is_empty():
		return Statuses.cessation(Statuses.CEASE_TURN)
	return cessation


## Records what a module sends to its sink.
class Recorder:
	extends RefCounted

	var events: Array[MatchEvent] = []

	func record(kind: int, payload: Dictionary, owner: int = MatchEvent.PUBLIC) -> void:
		events.append(MatchEvent.new(kind, payload, owner))

	## The recorded events of `kind`, in order.
	func of_kind(kind: int) -> Array[MatchEvent]:
		var out: Array[MatchEvent] = []
		for event: MatchEvent in events:
			if event.kind == kind:
				out.append(event)
		return out

	## The `card` of each recorded event of `kind`, in order.
	func cards_of(kind: int) -> Array[int]:
		var out: Array[int] = []
		for event: MatchEvent in of_kind(kind):
			var card: int = event.payload.get("card", -1)
			out.append(card)
		return out
