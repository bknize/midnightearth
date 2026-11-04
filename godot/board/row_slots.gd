class_name RowSlots
extends RefCounted
## Pure slot arithmetic for a row (R43, R45, R47, P15). A slot is a card's final index on its
## row. No nodes, no scene access.


## How many staged cards sit before `id` in the row: the index the card has among the staged
## cards. `played` holds the ids already played (any value); a card not in `played` is staged.
## An id not in the row counts every staged card.
static func staged_before(row: Array[int], played: Dictionary, id: int) -> int:
	var count: int = 0
	for other: int in row:
		if other == id:
			return count
		if not played.has(other):
			count += 1
	return count


## The indices 0..count-1 ordered by their slot, lowest first, ties in index order. Inserting
## the cards in this order at their slots lands each at its final row index (R47). When the
## slots do not name every card, the order is the cards' own.
static func order_by_slot(slots: Array[int], count: int) -> Array[int]:
	var order: Array[int] = []
	for i: int in range(maxi(count, 0)):
		order.append(i)
	if slots.size() != order.size():
		return order
	for i: int in range(1, order.size()):
		var current: int = order[i]
		var j: int = i - 1
		while j >= 0 and slots[order[j]] > slots[current]:
			order[j + 1] = order[j]
			j -= 1
		order[j + 1] = current
	return order


## The index to insert a card at for a slot, in a row that now holds `size` cards.
static func insert_index(slot: int, size: int) -> int:
	return clampi(slot, 0, maxi(size, 0))
