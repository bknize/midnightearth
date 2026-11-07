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
## end.
##
## Statuses (P8, P9, DC-13 T04; Statuses is their only writer): `statuses` maps a status
## (Statuses.MUTED, SQUELCHED or ANCHORED; Silenced is never stored, it is both halves
## present) to its cessation {kind: "turn" | "permanent" | "condition", condition, source};
## a "permanent" status lives in CardMemory.permanent_statuses instead, so it survives the
## row. `exit_mark` is "" or one of Statuses.CONDEMNED, FLEETING, FADE (at most one, R38).
## `protections` lists the statuses an effect has made the card unable to take ("cannot be
## X"); Ongoing protections (Bastion) and anchors (Brace) are read from the definition while
## the Ongoing is read, never stored (derived, plan Data model).

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
## Board-scoped statuses: status to cessation (see the class comment).
var statuses: Dictionary[String, Dictionary] = {}
## The exit mark, "" for none.
var exit_mark: String = ""
## Statuses the card cannot be given ("cannot be X"), from effects (each at most once).
var protections: Array[String] = []


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
	for status: String in statuses:
		var cessation: Dictionary = statuses[status]
		out.statuses[status] = cessation.duplicate(true)
	out.exit_mark = exit_mark
	out.protections.assign(protections)
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
		"statuses": _statuses_dict(),
		"exit_mark": exit_mark,
		"protections": MatchState.plain_strings(protections),
	}


## The statuses as plain, copied data.
func _statuses_dict() -> Dictionary:
	var out: Dictionary = {}
	for status: String in statuses:
		var cessation: Dictionary = statuses[status]
		out[status] = cessation.duplicate(true)
	return out

