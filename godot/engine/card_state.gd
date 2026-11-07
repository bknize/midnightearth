class_name CardState
extends RefCounted
## The Board changes of one card on a row (cycle 9 plan P8, spec R30): kept in
## MatchState.card_states by instance id and dropped whenever the card leaves its row
## (MatchState.take_from_row) or the Round ends. A card with no entry has every field at its
## default. Memory (CardMemory) is what survives the row.
##
## Scoring reads it (plan P7): `power_delta` adds to the Power; `granted` adds one Bonus per
## entry {kind: "add" or "mult", value: hundredths, until: "turn", "row" or "score"} after
## the printed and grown ones; `copied_base` (Mirror, Q5), when not empty, replaces the
## printed Power and Bonuses as {power, adds: [hundredths], mults: [hundredths]} until turn
## end. DC-13 T04 adds the statuses with their cessations, the exit mark and the
## protections (P8, P9).

const KIND_ADD: String = "add"
const KIND_MULT: String = "mult"
const KEY_KIND: String = "kind"
const KEY_VALUE: String = "value"
const KEY_UNTIL: String = "until"

## Power added as a Board change.
var power_delta: int = 0
## Granted Bonuses, in the order they were granted.
var granted: Array[Dictionary] = []
## The copied base, {} when none.
var copied_base: Dictionary = {}


## True when every field is at its default, so the entry changes nothing.
func is_default() -> bool:
	return power_delta == 0 and granted.is_empty() and copied_base.is_empty()


## Grants a Bonus of `kind` (KIND_ADD or KIND_MULT) worth `value` hundredths until `until`.
func grant(kind: String, value: int, until: String) -> void:
	granted.append({KEY_KIND: kind, KEY_VALUE: value, KEY_UNTIL: until})


## The granted values of `kind`, in grant order.
func granted_of(kind: String) -> Array[int]:
	var out: Array[int] = []
	for entry: Dictionary in granted:
		var entry_kind: String = entry.get(KEY_KIND, "")
		if entry_kind == kind:
			var value: int = entry.get(KEY_VALUE, 0)
			out.append(value)
	return out


## An independent copy.
func copy() -> CardState:
	var out: CardState = CardState.new()
	out.power_delta = power_delta
	for entry: Dictionary in granted:
		out.granted.append(entry.duplicate(true))
	out.copied_base = copied_base.duplicate(true)
	return out


## Plain data, for MatchState.to_dict() and comparisons.
func to_dict() -> Dictionary:
	var listed: Array = []
	for entry: Dictionary in granted:
		listed.append(entry.duplicate(true))
	return {
		"power_delta": power_delta,
		"granted": listed,
		"copied_base": copied_base.duplicate(true),
	}
