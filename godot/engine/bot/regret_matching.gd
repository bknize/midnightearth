class_name RegretMatching
extends RefCounted
## A small zero-sum matrix game solved by regret matching (cycle 7 R51, plan P13), and the
## draw from its mixed strategy.
##
## solve() takes the row player's payoffs (rows: the matrix bot's own candidates, columns:
## the opponent's hypotheses; the row player maximises, the column player minimises) and
## runs `iterations` rounds of simultaneous regret matching: each player plays its
## positive-regret proportions (uniform when no regret is positive), both cumulative regret
## tables are updated against the other's mix, and the row player's mixes are summed. The
## result is the average row strategy, which approaches an equilibrium strategy as the
## iterations grow. The arithmetic is IEEE double in a fixed order, and the answer a
## PackedFloat32Array.
##
## Floats stay here (D4): sample_index() turns the strategy into whole-number weights
## (each probability times SCALE, rounded) and draws one rng.pick_index over their sum, so
## only an index reaches the bot and the log, and every platform draws alike.
##
## Static and pure: no state, no output, every draw from the generator passed in.

## The strategy's whole-number resolution in sample_index(): a probability of 1 weighs SCALE.
const SCALE: int = 10000


## The average row strategy of `payoff` (rows × columns, row player maximising) after
## `iterations` rounds (see the class comment); one probability per row, summing to 1.
## Uniform when there is one row, no column, a ragged matrix or no iteration; empty for no
## rows.
static func solve(payoff: Array[PackedInt32Array], iterations: int) -> PackedFloat32Array:
	var rows: int = payoff.size()
	var cols: int = payoff[0].size() if rows > 0 else 0
	var cells: Array[float] = []
	for row: PackedInt32Array in payoff:
		if row.size() != cols:
			return _uniform(rows)
		for cell: int in row:
			cells.append(float(cell))
	var flat: PackedFloat64Array = PackedFloat64Array(cells)
	if rows < 2 or cols < 1 or iterations < 1:
		return _uniform(rows)
	var regret_r: PackedFloat64Array = _zeros(rows)
	var regret_c: PackedFloat64Array = _zeros(cols)
	var sum_r: PackedFloat64Array = _zeros(rows)
	var sigma_r: PackedFloat64Array = _zeros(rows)
	var sigma_c: PackedFloat64Array = _zeros(cols)
	var u_r: PackedFloat64Array = _zeros(rows)
	var u_c: PackedFloat64Array = _zeros(cols)
	for _round: int in range(iterations):
		_matched(regret_r, sigma_r)
		_matched(regret_c, sigma_c)
		u_c.fill(0.0)
		var value: float = 0.0
		for i: int in range(rows):
			var weight: float = sigma_r[i]
			var base: int = i * cols
			var total: float = 0.0
			for j: int in range(cols):
				var cell: float = flat[base + j]
				total += cell * sigma_c[j]
				u_c[j] += weight * cell
			u_r[i] = total
			value += weight * total
		for i: int in range(rows):
			regret_r[i] += u_r[i] - value
			sum_r[i] += sigma_r[i]
		for j: int in range(cols):
			regret_c[j] += value - u_c[j]
	var average: Array[float] = []
	for i: int in range(rows):
		average.append(sum_r[i] / float(iterations))
	return PackedFloat32Array(average)


## One index of `strategy`, drawn by `rng` with probability its whole-number weight
## (weights()) over their sum: one pick_index over the sum, the index the first whose
## running sum exceeds the draw. Uniform (one pick_index over the size) when every weight
## is 0; -1, with no draw, for an empty strategy.
static func sample_index(strategy: PackedFloat32Array, rng: MatchRng) -> int:
	if strategy.is_empty():
		return -1
	var table: PackedInt32Array = weights(strategy)
	var total: int = 0
	for weight: int in table:
		total += weight
	if total <= 0:
		return rng.pick_index(table.size())
	var draw: int = rng.pick_index(total)
	var running: int = 0
	for index: int in range(table.size()):
		running += table[index]
		if draw < running:
			return index
	return table.size() - 1


## `strategy` as whole-number weights: each probability times SCALE, rounded, never below 0.
static func weights(strategy: PackedFloat32Array) -> PackedInt32Array:
	var out: Array[int] = []
	for probability: float in strategy:
		out.append(maxi(roundi(probability * SCALE), 0))
	return PackedInt32Array(out)


## Fills `sigma` with `regret`'s positive parts normalised to 1, or uniform when none is
## positive.
static func _matched(regret: PackedFloat64Array, sigma: PackedFloat64Array) -> void:
	var size: int = regret.size()
	var positive: float = 0.0
	for index: int in range(size):
		positive += maxf(regret[index], 0.0)
	for index: int in range(size):
		if positive > 0.0:
			sigma[index] = maxf(regret[index], 0.0) / positive
		else:
			sigma[index] = 1.0 / float(size)


## `count` probabilities of 1 / count; empty for none.
static func _uniform(count: int) -> PackedFloat32Array:
	var out: Array[float] = []
	for _index: int in range(maxi(count, 0)):
		out.append(1.0 / float(count))
	return PackedFloat32Array(out)


## `count` zeros (none for a count below 1).
static func _zeros(count: int) -> PackedFloat64Array:
	var out: Array[float] = []
	for _index: int in range(count):
		out.append(0.0)
	return PackedFloat64Array(out)
