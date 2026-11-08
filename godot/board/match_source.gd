class_name MatchSource
extends RefCounted
## What the board plays against (cycle 12 plan P5): a local engine with bots (MatchDriver) or
## a match server (RemoteMatchSource). The board never learns which. Abstract: every method
## has a typed body returning a default, and the base only warns.
##
## Everything the board shows comes from here in the local player's terms: `view()` is that
## seat's redacted view, `events_ready` carries that seat's redacted events, and
## `player_seat` says which engine seat the player holds. A submit answers through
## `events_ready` (accepted) or `action_rejected` (refused); a local source answers inside
## the call, a remote one later.

## Redacted events of an accepted action, or of the start, for `player_seat`.
signal events_ready(events: Array[MatchEvent])
## The source refused the player's last action; `code` is an EngineError.Code.
signal action_rejected(code: int)
## The link changed: `state` is one of the STATE_* names, `detail` the opponent's name or "".
signal connection_changed(state: String, detail: String)
## The match is closed from outside the rules: `reason` is one of the CLOSED_* names.
signal match_closed(reason: String)
## A reconnect's whole redacted history and the current view (a remote source only, P8:
## MatchDriver never emits it).
signal catch_up(events: Array[MatchEvent], view: SeatView)

## connection_changed states.
const STATE_RECONNECTING: String = "reconnecting"
const STATE_RESTORED: String = "restored"
const STATE_OPPONENT_LOST: String = "opponent_lost"
const STATE_OPPONENT_BACK: String = "opponent_back"
## match_closed reasons.
const CLOSED_ABANDONED: String = "abandoned"

## The engine seat the player holds (0 for a local match).
var player_seat: int = 0


## Starts the match; the opening events arrive through `events_ready`.
func start() -> void:
	push_warning("MatchSource.start: not implemented")


## Sends the player's action.
func submit(_action: EngineAction) -> void:
	push_warning("MatchSource.submit: not implemented")


## Answers the open prompt with option `index` of `zone` (a `Choice.Zone` value).
func submit_choice(_zone: int, _index: int) -> void:
	push_warning("MatchSource.submit_choice: not implemented")


## Answers the open multi-select prompt with the set `indices` of `zone`.
func submit_set(_zone: int, _indices: Array[int]) -> void:
	push_warning("MatchSource.submit_set: not implemented")


## Declines the open optional prompt.
func submit_decline() -> void:
	push_warning("MatchSource.submit_decline: not implemented")


## A local source plays its next due bot action (its events arrive through `events_ready`)
## and returns true; a remote source, or one with no bot due, returns false. The board calls
## it when its queue runs dry, so a bot's move is generated only after the last was shown.
func advance() -> bool:
	return false


## The player's redacted view; null before the match has started.
func view() -> SeatView:
	return null


## The player's open prompt (`{seat, card, verb, zone, options, multi, ...}`), or `{}`.
func open_prompt() -> Dictionary:
	return {}


## The match's card definitions by instance id.
func match_cards() -> MatchCards:
	return null


## The deck id each seat plays, indexed by engine seat.
func deck_ids() -> Array[String]:
	var none: Array[String] = []
	return none


func is_over() -> bool:
	return false


## Whether the player is the awaited seat.
func is_player_awaited() -> bool:
	return false


## The end-of-match line the board prints; "" until the match is over.
func result_line() -> String:
	return ""


## The name the HUD shows for the other side.
func opponent_name() -> String:
	return "Opponent"


## Whether the result panel offers Rematch and the pause menu Decks (a local match only).
func allows_rematch() -> bool:
	return false
