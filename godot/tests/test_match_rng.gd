class_name TestMatchRng
extends GdUnitTestSuite
## R1, R2: MatchRng is the engine's only random stream and is fully seed-driven.

const FLIPS: int = 64


func _deck() -> Array[int]:
	var deck: Array[int] = []
	for i: int in range(MatchRules.DECK_SIZE):
		deck.append(i)
	return deck


func _shuffled(match_seed: int) -> Array[int]:
	var rng: MatchRng = MatchRng.new(match_seed)
	var deck: Array[int] = _deck()
	rng.shuffle_in_place(deck)
	return deck


func _flips(match_seed: int) -> Array[int]:
	var rng: MatchRng = MatchRng.new(match_seed)
	var out: Array[int] = []
	for i: int in range(FLIPS):
		out.append(rng.coin_flip())
	return out


func test_same_seed_gives_same_shuffle() -> void:
	assert_array(_shuffled(1)).is_equal(_shuffled(1))
	assert_array(_shuffled(9007199254740993)).is_equal(_shuffled(9007199254740993))


func test_different_seeds_give_different_shuffles() -> void:
	assert_array(_shuffled(1)).is_not_equal(_shuffled(2))


func test_shuffle_is_a_permutation() -> void:
	var deck: Array[int] = _shuffled(7)
	assert_int(deck.size()).is_equal(MatchRules.DECK_SIZE)
	deck.sort()
	assert_array(deck).is_equal(_deck())


func test_shuffle_of_short_arrays_is_safe() -> void:
	var rng: MatchRng = MatchRng.new(3)
	var empty: Array[int] = []
	rng.shuffle_in_place(empty)
	assert_int(empty.size()).is_equal(0)
	var single: Array[int] = [5]
	rng.shuffle_in_place(single)
	assert_int(single[0]).is_equal(5)


func test_same_seed_gives_same_coin_flips() -> void:
	assert_array(_flips(1)).is_equal(_flips(1))


func test_different_seeds_give_different_coin_flips() -> void:
	assert_array(_flips(1)).is_not_equal(_flips(2))


func test_coin_flip_is_zero_or_one() -> void:
	for flip: int in _flips(11):
		assert_bool(flip == 0 or flip == 1).is_true()


func test_state_restore_replays_the_stream() -> void:
	var rng: MatchRng = MatchRng.new(5)
	rng.coin_flip()
	var saved: int = rng.state
	var first: Array[int] = _deck()
	rng.shuffle_in_place(first)
	var after_first: int = rng.state
	rng.state = saved
	assert_int(rng.state).is_equal(saved)
	var second: Array[int] = _deck()
	rng.shuffle_in_place(second)
	assert_array(second).is_equal(first)
	assert_int(rng.state).is_equal(after_first)


func test_pick_index_stays_in_range() -> void:
	var rng: MatchRng = MatchRng.new(13)
	for i: int in range(50):
		var picked: int = rng.pick_index(4)
		assert_bool(picked >= 0 and picked < 4).is_true()
	assert_int(rng.pick_index(0)).is_equal(0)


func test_derive_seed_matches_reference_splitmix64() -> void:
	# Expected values from a reference splitmix64 run (Python, mod 2^64, read as
	# signed). derive_seed(0, []) is the canonical first output 0xE220A8397B1DCDAF.
	var none: Array[int] = []
	assert_int(MatchRng.derive_seed(0, none)).is_equal(-2152535657050944081)
	assert_int(MatchRng.derive_seed(1, none)).is_equal(-7995527694508729151)
	var p01: Array[int] = [0, 1]
	assert_int(MatchRng.derive_seed(1, p01)).is_equal(7806873273932414515)
	var p10: Array[int] = [1, 0]
	assert_int(MatchRng.derive_seed(1, p10)).is_equal(6301985355436268297)
	var p37: Array[int] = [3, 7]
	assert_int(MatchRng.derive_seed(42, p37)).is_equal(-6111499642997921453)
	var p2: Array[int] = [2]
	assert_int(MatchRng.derive_seed(-1, p2)).is_equal(5886236958684341581)
	var p11: Array[int] = [1, 1]
	assert_int(MatchRng.derive_seed(9007199254740993, p11)).is_equal(5063054290722598016)


func test_derive_seed_is_pure() -> void:
	var parts: Array[int] = [3, 7]
	var first: int = MatchRng.derive_seed(42, parts)
	var rng: MatchRng = MatchRng.new(42)
	rng.coin_flip()
	assert_int(MatchRng.derive_seed(42, parts)).is_equal(first)
	var unchanged: Array[int] = [3, 7]
	assert_array(parts).is_equal(unchanged)


func test_derive_seed_depends_on_seed_and_part_order() -> void:
	var p01: Array[int] = [0, 1]
	var p10: Array[int] = [1, 0]
	assert_int(MatchRng.derive_seed(1, p01)).is_not_equal(MatchRng.derive_seed(1, p10))
	assert_int(MatchRng.derive_seed(1, p01)).is_not_equal(MatchRng.derive_seed(2, p01))
