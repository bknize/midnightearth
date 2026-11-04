class_name CardSpot
extends RefCounted
## Where a card sits on the table: an absolute seat, a hand or a row, and an index in it.
## Pure data; RowTargets builds these and the board looks the card up.

var seat: int = -1
var in_hand: bool = false
var slot: int = -1


func _init(new_seat: int = -1, new_in_hand: bool = false, new_slot: int = -1) -> void:
	seat = new_seat
	in_hand = new_in_hand
	slot = new_slot


func is_valid() -> bool:
	return seat >= 0 and slot >= 0
