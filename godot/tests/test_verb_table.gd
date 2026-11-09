class_name TestVerbTable
extends GdUnitTestSuite
## VerbTable (NSC-185): the table reads CardAbility and CrewDef share, and the amount and
## uses checks with each pool's error strings byte for byte.

const TABLE: Dictionary[String, Dictionary] = {
	"many": {"moments": ["on_score", "on_reveal"], "amount": [1, 3]},
	"one": {"moment": "ongoing"},
}
const KEYS: Array[String] = ["amount", "cap"]


func test_is_allowed_pair_reads_either_shape_of_entry() -> void:
	assert_bool(VerbTable.is_allowed_pair(TABLE, "on_reveal", "many")).is_true()
	assert_bool(VerbTable.is_allowed_pair(TABLE, "ongoing", "many")).is_false()
	assert_bool(VerbTable.is_allowed_pair(TABLE, "ongoing", "one")).is_true()
	assert_bool(VerbTable.is_allowed_pair(TABLE, "on_score", "one")).is_false()
	assert_bool(VerbTable.is_allowed_pair(TABLE, "ongoing", "unknown")).is_false()


func test_range_of_is_zero_for_no_such_amount() -> void:
	var none: Array[int] = [0, 0]
	var some: Array[int] = [1, 3]
	assert_array(VerbTable.range_of(TABLE, "many", "amount")).is_equal(some)
	assert_array(VerbTable.range_of(TABLE, "many", "cap")).is_equal(none)
	assert_array(VerbTable.range_of(TABLE, "unknown", "amount")).is_equal(none)


func test_is_uses_takes_a_whole_number_from_zero() -> void:
	assert_bool(VerbTable.is_uses(0)).is_true()
	assert_bool(VerbTable.is_uses(2.0)).is_true()
	assert_bool(VerbTable.is_uses(-1)).is_false()
	assert_bool(VerbTable.is_uses(1.5)).is_false()
	assert_bool(VerbTable.is_uses("1")).is_false()
	assert_bool(VerbTable.is_uses(null)).is_false()


func test_amount_problem_passes_absent_and_in_range() -> void:
	assert_str(VerbTable.amount_problem({}, TABLE, "one", KEYS, "%s %s", "")).is_empty()
	var good: Dictionary = {"amount": 3}
	assert_str(VerbTable.amount_problem(good, TABLE, "many", KEYS, "%s %s", "")).is_empty()


## The card pool's messages (CardAbility.problem_of), whole.
func test_a_card_ability_keeps_its_amount_and_uses_messages() -> void:
	var ability: Dictionary = {"moment": "on_reveal", "verb": "draw", "text": "T", "amount": 9}
	assert_str(CardAbility.problem_of(ability)).is_equal(
		'amount out of range: "draw" amount 9 (allowed 1..3)'
	)
	ability["amount"] = 1.5
	assert_str(CardAbility.problem_of(ability)).is_equal(
		"amount out of range: amount 1.5 is not a whole number"
	)
	ability["amount"] = 1
	ability["uses"] = -1
	assert_str(CardAbility.problem_of(ability)).is_equal("bad uses: -1 (a whole number >= 0)")


## The Crew pool's messages (CrewPool), whole.
func test_a_crew_keeps_its_amount_and_uses_messages() -> void:
	var crew: Dictionary = {
		"id": "c",
		"name": "C",
		"tag": CardDef.TAGS[0],
		"moment": "on_score",
		"verb": "captain_leftmost",
		"amount": 9,
		"text": "T",
	}
	assert_str(_crew_error(crew)).is_equal(
		'amount out of range: crew 0 "captain_leftmost" amount 9 (allowed 1..5)'
	)
	crew["amount"] = 1.5
	assert_str(_crew_error(crew)).is_equal("amount out of range: crew 0 has amount 1.5")
	crew["amount"] = 1
	crew["uses"] = "x"
	assert_str(_crew_error(crew)).is_equal('bad uses: crew 0 has uses "x"')


func _crew_error(crew: Dictionary) -> String:
	var text: String = JSON.stringify({"version": CrewPool.FORMAT_VERSION, "crew": [crew]})
	return CrewPool.from_json(text).load_error()
