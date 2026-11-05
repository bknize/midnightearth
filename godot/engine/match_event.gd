class_name MatchEvent
extends RefCounted
## One thing that happened during start() or apply() (R4). Payload keys per kind are in
## the plan's event table. Private events (deal, draw, burn, commit, and the destroy of a
## face-down card, DC-05 T04; the discard, a face-down card's move and a choice of a hand or
## face-down card, DC-05 T05; the turn-end clear of a destroyed card never revealed, DC-06
## R21; a growth's STATS_CHANGED on a hand or face-down card, cycle 8 P4) carry the owning
## seat; public events carry PUBLIC.
## redacted_for() gives each seat its copy (R29). A private CHOICE_MADE hides only its
## `target` (R34); every other private event hides its `card` and `cards`, and a private
## STATS_CHANGED also shows neutral stats (STATS_HIDDEN), since a hidden card's effective
## flat, bonus and cost would name it through the public deck lists (cycle 8 R8, R73).

enum Kind {
	ROUND_STARTED,
	CARD_DEALT,
	TURN_STARTED,
	CARD_DRAWN,
	CARD_BURNED,
	COMMITTED,
	CARD_REVEALED,
	TURN_ENDED,
	ROUND_ENDED,
	CONCEDED,
	MATCH_ENDED,
	# DC-05 (cycle-4-card-effects plan, event table). Appended so earlier ordinals hold.
	WALK_STARTED,
	CARD_SCORED,
	EFFECT_FIRED,
	EFFECT_FIZZLED,
	CHOICE_REQUESTED,
	CHOICE_MADE,
	STATS_CHANGED,
	CARD_DESTROYED,
	CARD_MOVED,
	CARD_RETURNED,
	CARD_DISCARDED,
	BONUS_ZERO_SET,
	ENERGY_CARRIED,
	FREE_FIRST_SET,
	# DC-06 (cycle-5-walk-cursor plan, event table). Appended so earlier ordinals hold.
	DESTROYED_CLEARED,
	# DC-07 (cycle-6-constructed-decks plan, event table). Appended so earlier ordinals hold.
	## The first event of start(): {decks: [seat 0's deck id, seat 1's]}. Public (R5); it
	## carries no seed, which would predict every shuffle (R28, R29).
	MATCH_STARTED,
	## A card left a destroyed pile for a hand (DC-07 R19, T04): {seat: its new controller,
	## card, from_seat: the pile's seat, position: its index in that pile}. Public when the
	## card's identity was (it left its row revealed); else private to `seat`, so the other
	## seat sees the pile and position but not the card. At the hand cap a CARD_BURNED with
	## the same owner follows.
	CARD_RECOVERED,
	## A destroy replaced by the un-reveal (DC-07 P9, R30, T06): {seat, card, slot}. The card
	## flips face down in its slot with printed stats and is not destroyed. Public, since the
	## card was revealed; from then on the face-down rules hide it as any face-down card.
	CARD_UNREVEALED,
}

## owner_seat of an event every seat may see in full.
const PUBLIC: int = -1
## What a redacted copy shows in place of each hidden card id.
const HIDDEN_CARD: int = -1
const KEY_CARD: String = "card"
const KEY_CARDS: String = "cards"
const KEY_TARGET: String = "target"
## What the other seat's copy of a private STATS_CHANGED shows in place of the hidden card's
## stats and memory flag (cycle 8 R8, R73): no flat, no bonus (×1.00, +0), cost 0, not
## permanent. `seat` and `cause` stay, so the event still counts as a change on that seat.
const STATS_HIDDEN: Dictionary = {
	"flat": 0, "times": MatchRules.MULT_ONE, "plus": 0, "cost": 0, "permanent": false
}

var kind: int = Kind.ROUND_STARTED
var payload: Dictionary = {}
var owner_seat: int = PUBLIC


func _init(
	p_kind: int = Kind.ROUND_STARTED, p_payload: Dictionary = {}, p_owner: int = PUBLIC
) -> void:
	kind = p_kind
	payload = p_payload
	owner_seat = p_owner


func is_private() -> bool:
	return owner_seat != PUBLIC


## A plain, deep-copied form for comparisons and logging.
func to_dict() -> Dictionary:
	return {"kind": kind, "owner": owner_seat, "payload": payload.duplicate(true)}


## The copy of this event that `seat` may see (R29). Public events and the owner's own
## private events come back unchanged; for anyone else a private event keeps its kind,
## owner and `seat`, and every card id under `card` or `cards` becomes HIDDEN_CARD (the
## COMMITTED `count` stays); a private STATS_CHANGED also takes STATS_HIDDEN's values for
## its stats; a private CHOICE_MADE keeps `card` and hides `target`. Always
## a new object with a deep-copied payload: this event is never mutated, and mutating the
## copy cannot reach it.
func redacted_for(seat: int) -> MatchEvent:
	var copied: Dictionary = payload.duplicate(true)
	if is_private() and seat != owner_seat and kind == Kind.CHOICE_MADE:
		# The chosen card is the secret; the source card is revealed on its row (R34).
		copied[KEY_TARGET] = HIDDEN_CARD
	elif is_private() and seat != owner_seat:
		if copied.has(KEY_CARD):
			copied[KEY_CARD] = HIDDEN_CARD
		if copied.has(KEY_CARDS):
			var hidden: Array = copied[KEY_CARDS]
			var masked: Array = []
			for _card: Variant in hidden:
				masked.append(HIDDEN_CARD)
			copied[KEY_CARDS] = masked
		if kind == Kind.STATS_CHANGED:
			# The stats of a hidden card would name it (cycle 8 R8): neutral values.
			copied.merge(STATS_HIDDEN, true)
	return MatchEvent.new(kind, copied, owner_seat)
