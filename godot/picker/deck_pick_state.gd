class_name DeckPickState
extends RefCounted
## The picker's pure state (R39-R41, plan P15): one pick per column, "You" (0) and "Bot" (1).
## A pick replaces the column's previous one, and Start is allowed only once both columns
## hold a deck the list offers.

const COLUMNS: int = 2

var _available: Array[String] = []
var _picks: Array[String] = ["", ""]


## `available` are the deck ids on offer; `preselected` is one id per column, and an id that
## is not on offer (or "") leaves that column without a pick.
func setup(available: Array[String], preselected: Array[String]) -> void:
	_available = available.duplicate()
	_picks = ["", ""]
	for column: int in range(mini(COLUMNS, preselected.size())):
		pick(column, preselected[column])


## Picks `deck_id` for `column`, replacing its previous pick. Returns false, changing
## nothing, for an unknown column or a deck that is not on offer.
func pick(column: int, deck_id: String) -> bool:
	if column < 0 or column >= COLUMNS or not _available.has(deck_id):
		return false
	_picks[column] = deck_id
	return true


## The column's picked deck id, "" when none.
func picked_id(column: int) -> String:
	if column < 0 or column >= COLUMNS:
		return ""
	return _picks[column]


## Whether Start may be pressed: both columns hold a pick.
func can_start() -> bool:
	return _picks[0] != "" and _picks[1] != ""


## The two picks, You then Bot ("" for a column with none).
func deck_ids() -> Array[String]:
	return _picks.duplicate()
