class_name Staging
extends RefCounted
## The player's staged cards for the turn (R12-R16, R43, R45, C9, C10, P15). Pure
## bookkeeping: card ids in row order, each with the cost it was staged at, against the
## seat's budget (turn plus carry). A card's slot is its index in the player's row: the
## `played` cards already on the row come first, then the staged cards in order (T10 will let
## staged cards sit between played ones). When the first card is free, the leftmost staged
## card (the lowest slot) costs 0. An empty staging is a pass.

var _energy: int = 0
var _played: int = 0
var _free_first: bool = false
var _row: Array[int] = []
var _costs: Dictionary = {}


## Clears the staged cards and sets the seat's budget for the turn, how many played cards
## already sit on the row, and whether the first new card is free.
func reset(energy: int, played: int = 0, free_first: bool = false) -> void:
	_energy = energy
	_played = maxi(played, 0)
	_free_first = free_first
	_row.clear()
	_costs.clear()


## True when a card of this cost, staged at the right end, fits in the energy left (R14).
func can_afford(cost: int) -> bool:
	if _free_first and _row.is_empty():
		return true
	return cost <= energy_left()


## Stages the card at the index, clamped to 0..size. Returns false, changing nothing,
## when the card is already staged or the staged cost (the leftmost card free when the first
## card is free) would exceed the budget.
func insert(card: int, cost: int, index: int) -> bool:
	if has(card):
		return false
	var wanted: Array[int] = []
	wanted.assign(_row)
	var err: int = wanted.insert(clampi(index, 0, wanted.size()), card)
	if err != OK:
		return false
	_costs[card] = cost
	if _energy - _spent(wanted) < 0:
		var undone: bool = _costs.erase(card)
		if not undone:
			push_error("Staging.insert: could not undo a refused card")
		return false
	_row.assign(wanted)
	return true


## Unstages the card; a no-op when it is not staged.
func remove(card: int) -> void:
	if _costs.erase(card):
		_row.erase(card)


## Moves a staged card so it sits at the index of the row once the card is taken out of
## it, clamped to 0..size-1. A no-op when the card is not staged.
func move(card: int, index: int) -> void:
	if not has(card):
		return
	var wanted: Array[int] = []
	wanted.assign(_row)
	wanted.erase(card)
	var err: int = wanted.insert(clampi(index, 0, wanted.size()), card)
	if err != OK:
		push_error("Staging.move: insert failed with error %d" % err)
		return
	# A new leftmost card changes which one is free; a move that would overspend is refused.
	if _energy - _spent(wanted) < 0:
		return
	_row.assign(wanted)


## The budget minus the staged cards' total cost, the leftmost one free when the first card
## is (R15, R49).
func energy_left() -> int:
	return _energy - _spent(_row)


## True when the first staged card costs 0 this turn.
func free_first() -> bool:
	return _free_first


## The cost a staged card is charged: 0 for the leftmost one when the first card is free.
func charged_cost(card: int) -> int:
	if not has(card):
		return 0
	if _free_first and _row[0] == card:
		return 0
	var cost: int = _costs[card]
	return cost


func _spent(row: Array[int]) -> int:
	var spent: int = 0
	for i: int in range(row.size()):
		var cost: int = _costs[row[i]]
		if i == 0 and _free_first:
			cost = 0
		spent += cost
	return spent


## A copy of the staged ids, in row order.
func cards() -> Array[int]:
	var copy: Array[int] = []
	copy.assign(_row)
	return copy


func has(card: int) -> bool:
	return _costs.has(card)


## The row slot of every staged card, in the order of `cards()` (R45): the played cards come
## first, so the slots follow the row indices.
func slots() -> Array[int]:
	var out: Array[int] = []
	for i: int in range(_row.size()):
		out.append(_played + i)
	return out


## The commit for this seat: the staged cards in row order with the slots they occupy;
## empty when nothing is staged, which is a pass (R16).
func to_action(seat: int) -> EngineAction:
	return EngineAction.commit(seat, cards(), slots())
