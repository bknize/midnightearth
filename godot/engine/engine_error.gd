class_name EngineError
extends RefCounted
## The fixed list of failure codes an action can return (R26, C2).
##
## Values are stable: they appear in results and tests, so append new codes at the end.

enum Code {
	NONE,
	NOT_STARTED,
	MATCH_OVER,
	WRONG_SEAT,
	CARD_NOT_IN_HAND,
	DUPLICATE_CARD,
	OVER_BUDGET,
	MALFORMED,
	CARD_DATA_INVALID,
	## A commit's slots are out of range, repeated, out of order or miscounted (R6).
	BAD_SLOTS,
	## A choice arrived while no prompt is open (R31).
	NO_PROMPT,
	## A choice names a zone or position that is not eligible (R31).
	NOT_ELIGIBLE,
}
