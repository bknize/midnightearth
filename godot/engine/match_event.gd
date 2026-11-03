class_name MatchEvent
extends RefCounted
## One thing that happened during start() or apply() (R4). Payload keys per kind are in
## the plan's event table. Private events (deal, draw, burn, commit) carry the owning
## seat; public events carry PUBLIC. Redaction for the opponent is T06's redacted_for().

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
