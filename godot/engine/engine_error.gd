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
	## A set choice repeats an index or names one (or a zone) the multi-select prompt does
	## not offer (DC-07 R23, P7). A set answering a single-target prompt, like a single
	## choice answering a multi-select one, is NOT_ELIGIBLE (P7).
	BAD_SET,
	## create() named a deck id absent from the deck list, or not one id per seat; start()
	## fails with it (DC-07 P2).
	DECK_UNKNOWN,
}
