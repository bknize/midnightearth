class_name EngineError
extends RefCounted
## The fixed list of failure codes an action can return (R26, C2).
##
## Values are stable: they appear in results and tests, so append new codes at the end.
## A choice of the wrong shape for its prompt is NOT_ELIGIBLE, never BAD_SET (DC-07 P7).

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
	## A choice names a zone or position that is not eligible (R31), or has the wrong shape
	## for the open prompt: a set (CHOOSE_SET) sent to a single-target prompt, or a single
	## choice (CHOOSE) sent to a multi-select one (DC-07 P7).
	NOT_ELIGIBLE,
	## A set choice to an open multi-select prompt repeats an index, or names an index (or a
	## zone) that prompt does not offer (DC-07 R23, P7). Only for a repeated or non-offered
	## index: a set sent to a single-target prompt, like a CHOOSE on a multi-select one, is
	## NOT_ELIGIBLE (P7).
	BAD_SET,
	## create() named a deck id absent from the deck list, or not one id per seat; start()
	## fails with it (DC-07 P2).
	DECK_UNKNOWN,
	## A decline (EngineAction.DECLINE) arrived on an open prompt that is not optional
	## (cycle 8 R53, plan P10).
	NOT_OPTIONAL,
}


## The name of `code` (the Code key, e.g. "WRONG_SEAT"), for the server's `rejected`
## message (cycle 12 plan P3); "" for a code out of range.
static func name_of(code: int) -> String:
	var names: Array = Code.keys()
	if code < 0 or code >= names.size():
		return ""
	var found: String = names[code]
	return found
