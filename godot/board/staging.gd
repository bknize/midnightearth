class_name Staging
extends RefCounted
## The player's staged cards for the turn (R12-R16, C9, C10). Pure bookkeeping: card ids
## in row order, each with the cost it was staged at, against the turn's energy. Row order
## is commit and reveal order. An empty staging is a pass.

var _energy: int = 0
var _row: Array[int] = []
var _costs: Dictionary = {}


## Clears the staged cards and sets the turn's energy.
func reset(energy: int) -> void:
	_energy = energy
	_row.clear()
	_costs.clear()


## True when a card of this cost fits in the energy left (R14).
func can_afford(cost: int) -> bool:
	return cost <= energy_left()


## Stages the card at the index, clamped to 0..size. Returns false, changing nothing,
## when the card is already staged or its cost exceeds the energy left.
func insert(card: int, cost: int, index: int) -> bool:
	if has(card) or not can_afford(cost):
		return false
	var err: int = _row.insert(clampi(index, 0, _row.size()), card)
	if err != OK:
		return false
	_costs[card] = cost
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
	_row.erase(card)
	var err: int = _row.insert(clampi(index, 0, _row.size()), card)
	if err != OK:
		push_error("Staging.move: insert failed with error %d" % err)


## The turn's energy minus the staged cards' total cost (R15).
func energy_left() -> int:
	var spent: int = 0
	for card: int in _row:
		var cost: int = _costs[card]
		spent += cost
	return _energy - spent


## A copy of the staged ids, in row order.
func cards() -> Array[int]:
	var copy: Array[int] = []
	copy.assign(_row)
	return copy


func has(card: int) -> bool:
	return _costs.has(card)


## The commit for this seat: the staged cards in row order; empty when nothing is staged,
## which is a pass (R16).
func to_action(seat: int) -> EngineAction:
	return EngineAction.commit(seat, cards())
