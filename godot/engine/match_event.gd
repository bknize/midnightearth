class_name MatchEvent
extends RefCounted
## One thing that happened during start() or apply() (R4). Payload keys per kind are in
## the plan's event table. Private events (deal, draw, burn, commit) carry the owning
## seat; public events carry PUBLIC. redacted_for() gives each seat its copy (R29).

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
}

## owner_seat of an event every seat may see in full.
const PUBLIC: int = -1
## What a redacted copy shows in place of each hidden card id.
const HIDDEN_CARD: int = -1
const KEY_CARD: String = "card"
const KEY_CARDS: String = "cards"

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
## COMMITTED `count` stays). Always a new object with a deep-copied payload: this event is
## never mutated, and mutating the copy cannot reach it.
func redacted_for(seat: int) -> MatchEvent:
	var copied: Dictionary = payload.duplicate(true)
	if is_private() and seat != owner_seat:
		if copied.has(KEY_CARD):
			copied[KEY_CARD] = HIDDEN_CARD
		if copied.has(KEY_CARDS):
			var hidden: Array = copied[KEY_CARDS]
			var masked: Array = []
			for _card: Variant in hidden:
				masked.append(HIDDEN_CARD)
			copied[KEY_CARDS] = masked
	return MatchEvent.new(kind, copied, owner_seat)
