class_name DeckPickState
extends RefCounted
## The picker's pure state (R39-R41, plan P15): one pick per column, "You" (0) and "Bot" (1).
## A pick replaces the column's previous one, and Start is allowed only once both columns
## hold a deck the list offers.

## The default column count (PVE: You and Bot); PVP uses one (cycle 12 T08).
const COLUMNS: int = 2

var _available: Array[String] = []
var _picks: Array[String] = ["", ""]
var _columns: int = COLUMNS


## `available` are the deck ids on offer; `preselected` is one id per column, and an id that
## is not on offer (or "") leaves that column without a pick. `columns` (at least 1) is the
## number of picks the state holds.
func setup(available: Array[String], preselected: Array[String], columns: int = COLUMNS) -> void:
	_available = available.duplicate()
	_columns = maxi(columns, 1)
	_picks = []
	for _i: int in range(_columns):
		_picks.append("")
	for column: int in range(mini(_columns, preselected.size())):
		if not pick(column, preselected[column]):
			continue  # An unknown id leaves that column without a pick.


## Picks `deck_id` for `column`, replacing its previous pick. Returns false, changing
## nothing, for an unknown column or a deck that is not on offer.
func pick(column: int, deck_id: String) -> bool:
	if column < 0 or column >= _columns or not _available.has(deck_id):
		return false
	_picks[column] = deck_id
	return true


## The column's picked deck id, "" when none.
func picked_id(column: int) -> String:
	if column < 0 or column >= _columns:
		return ""
	return _picks[column]


## Whether Start may be pressed: every column holds a pick.
func can_start() -> bool:
	return not _picks.has("")


## The picks, one per column (You then Bot for two) ("" for a column with none).
func deck_ids() -> Array[String]:
	return _picks.duplicate()


## The number of columns.
func column_count() -> int:
	return _columns
