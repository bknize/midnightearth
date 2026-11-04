# gdlint: disable=max-public-methods
class_name TestCardDb
extends GdUnitTestSuite
## CardDb, CardDef and CardEffect: R1 (load each card with flat, bonus and at most one
## effect), R2 (validation), R3 (the plan's 20-card table, C14), card data format 2.

## The plan's card table (C14), in file order c01..c20.
const COSTS: Array[int] = [1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 6, 6, 7, 7]
const FLATS: Array[int] = [1, 2, 1, 3, 1, 1, 2, 4, 3, 3, 3, 4, 2, 6, 5, 5, 6, 8, 7, 7]
const BONUSES: Array[int] = [0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 2, 0, 0, 1, 0, 0, 0, 2]
## The effect cards of the table, by file index: [trigger, verb, amount, text].
const EFFECTS: Dictionary[int, Array] = {
	0: [CardEffect.Trigger.ON_REVEAL, CardEffect.Verb.DRAW, 1, "Draw a card."],
	4:
	[
		CardEffect.Trigger.ONGOING,
		CardEffect.Verb.CARRY_ENERGY,
		0,
		"Your unspent energy carries to your next turn.",
	],
	5:
	[
		CardEffect.Trigger.ON_SCORE,
		CardEffect.Verb.FLAT_UP_ON_SCORE,
		1,
		"Each time this scores, it gains +1 flat.",
	],
	8:
	[
		CardEffect.Trigger.ON_REVEAL,
		CardEffect.Verb.DRAW_THEN_DISCARD,
		2,
		"Draw 2 cards, then discard 1.",
	],
	9:
	[
		CardEffect.Trigger.ON_REVEAL,
		CardEffect.Verb.FREE_FIRST_NEXT_TURN,
		0,
		"The first card you play next turn costs 0.",
	],
	11:
	[
		CardEffect.Trigger.ON_REVEAL,
		CardEffect.Verb.SWAP_PLACES,
		0,
		"Swap places with a card on your board.",
	],
	12:
	[
		CardEffect.Trigger.ON_REVEAL,
		CardEffect.Verb.SWITCH_STATS,
		0,
		"Switch a card's flat and bonus.",
	],
	14:
	[
		CardEffect.Trigger.ON_REVEAL,
		CardEffect.Verb.OPPONENT_NEXT_BONUS_ZERO,
		0,
		"Your opponent's next revealed card has 0 bonus.",
	],
	16:
	[
		CardEffect.Trigger.ON_REVEAL,
		CardEffect.Verb.RETURN_AT_TURN_END,
		0,
		"Return another card to its owner's hand at the end of this turn.",
	],
	18:
	[
		CardEffect.Trigger.ON_REVEAL,
		CardEffect.Verb.DESTROY_RANDOM_OPPONENT,
		0,
		"Destroy a random card on your opponent's board.",
	],
}
## Every JSON name, in enum order (the plan's card table spellings).
const TRIGGER_JSON: Array[String] = ["on_reveal", "on_opponent_reveal", "on_score", "ongoing"]
const VERB_JSON: Array[String] = [
	"draw",
	"draw_then_discard",
	"free_first_next_turn",
	"swap_places",
	"switch_stats",
	"opponent_next_bonus_zero",
	"return_at_turn_end",
	"destroy_random_opponent",
	"flat_up",
	"carry_energy",
]


func _effect_dict(i: int) -> Variant:
	if not EFFECTS.has(i):
		return null
	var row: Array = EFFECTS[i]
	var trigger: int = row[0]
	var verb: int = row[1]
	return {
		"trigger": TRIGGER_JSON[trigger],
		"verb": VERB_JSON[verb],
		"amount": row[2],
		"text": row[3],
	}


func _table() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in range(COSTS.size()):
		(
			out
			. append(
				{
					"id": "c%02d" % (i + 1),
					"name": "Placeholder %02d" % (i + 1),
					"cost": COSTS[i],
					"flat": FLATS[i],
					"bonus": BONUSES[i],
					"effect": _effect_dict(i),
				}
			)
		)
	return out


func _json(cards: Array[Dictionary], version: int = 2) -> String:
	return JSON.stringify({"version": version, "cards": cards})


## The table with card `index`'s effect replaced by `effect`.
func _with_effect(index: int, effect: Variant) -> String:
	var cards: Array[Dictionary] = _table()
	cards[index]["effect"] = effect
	return _json(cards)


func _assert_fails_with(text: String, prefix: String) -> void:
	var db: CardDb = CardDb.from_json(text)
	assert_bool(db.is_valid()).is_false()
	assert_str(db.load_error()).starts_with(prefix)
	assert_int(db.size()).is_equal(0)
	assert_object(db.card_at(0)).is_null()


# --- R1, R3: the default file ---------------------------------------------------------


func test_default_file_loads_valid() -> void:
	var db: CardDb = CardDb.load_default()
	assert_bool(db.is_valid()).is_true()
	assert_str(db.load_error()).is_empty()
	assert_int(db.size()).is_equal(CardDb.CARD_COUNT)


func test_default_file_matches_plan_table() -> void:
	var db: CardDb = CardDb.load_default()
	var total_cost: int = 0
	var total_flat: int = 0
	var total_bonus: int = 0
	for i: int in range(COSTS.size()):
		var def: CardDef = db.card_at(i)
		assert_object(def).is_not_null()
		assert_str(def.id).is_equal("c%02d" % (i + 1))
		assert_str(def.name).is_equal("Placeholder %02d" % (i + 1))
		assert_int(def.cost).is_equal(COSTS[i])
		assert_int(def.flat).is_equal(FLATS[i])
		assert_int(def.bonus).is_equal(BONUSES[i])
		total_cost += def.cost
		total_flat += def.flat
		total_bonus += def.bonus
	assert_int(total_cost).is_equal(69)
	assert_int(total_flat).is_equal(74)
	assert_int(total_bonus).is_equal(8)


func test_default_file_effects_match_plan_table() -> void:
	var db: CardDb = CardDb.load_default()
	var effect_cards: int = 0
	for i: int in range(COSTS.size()):
		var def: CardDef = db.card_at(i)
		if not EFFECTS.has(i):
			continue
		effect_cards += 1
		var row: Array = EFFECTS[i]
		var trigger: int = row[0]
		var verb: int = row[1]
		var amount: int = row[2]
		var text: String = row[3]
		assert_object(def.effect).is_not_null()
		assert_int(def.effect.trigger).is_equal(trigger)
		assert_int(def.effect.verb).is_equal(verb)
		assert_int(def.effect.amount).is_equal(amount)
		assert_str(def.effect.text).is_equal(text)
	assert_int(effect_cards).is_equal(10)


func test_vanilla_cards_have_a_null_effect() -> void:
	var db: CardDb = CardDb.load_default()
	var vanilla: int = 0
	for i: int in range(COSTS.size()):
		if EFFECTS.has(i):
			continue
		vanilla += 1
		var def: CardDef = db.card_at(i)
		assert_object(def.effect).is_null()
		assert_that(def.to_dict()["effect"]).is_null()
	assert_int(vanilla).is_equal(10)


func test_default_file_cost_mix() -> void:
	var db: CardDb = CardDb.load_default()
	var counts: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
	for def: CardDef in db.cards():
		counts[def.cost] += 1
	var expected: Array[int] = [0, 4, 4, 3, 3, 2, 2, 2]
	assert_array(counts).is_equal(expected)


func test_lookup_by_index_and_id() -> void:
	var db: CardDb = CardDb.load_default()
	assert_int(db.index_of("c11")).is_equal(10)
	assert_int(db.card_by_id("c11").flat).is_equal(3)
	assert_int(db.card_by_id("c11").bonus).is_equal(1)
	assert_str(db.card_at(19).id).is_equal("c20")
	assert_int(db.card_by_id("c20").cost).is_equal(7)
	assert_int(db.index_of("c99")).is_equal(-1)
	assert_object(db.card_by_id("c99")).is_null()
	assert_object(db.card_at(-1)).is_null()
	assert_object(db.card_at(20)).is_null()
	# cards() hands out a copy.
	var copy: Array[CardDef] = db.cards()
	copy.clear()
	assert_int(db.size()).is_equal(20)


func test_in_memory_table_loads_valid() -> void:
	var db: CardDb = CardDb.from_json(_json(_table()))
	assert_bool(db.is_valid()).is_true()
	assert_str(db.load_error()).is_empty()
	assert_int(db.size()).is_equal(20)
	assert_int(db.card_at(0).effect.verb).is_equal(CardEffect.Verb.DRAW)
	assert_object(db.card_at(1).effect).is_null()


func test_card_def_to_dict_round_trips_the_entry() -> void:
	var db: CardDb = CardDb.load_default()
	var table: Array[Dictionary] = _table()
	for i: int in range(table.size()):
		assert_dict(db.card_at(i).to_dict()).is_equal(table[i])


# --- CardEffect: every trigger and verb name round-trips ------------------------------


func test_every_trigger_name_round_trips() -> void:
	assert_int(CardEffect.TRIGGER_NAMES.size()).is_equal(CardEffect.Trigger.size())
	for value: int in CardEffect.Trigger.values():
		var json_name: String = CardEffect.trigger_name(value)
		assert_str(json_name).is_equal(TRIGGER_JSON[value])
		assert_int(CardEffect.trigger_from_name(json_name)).is_equal(value)
		var effect: CardEffect = CardEffect.from_dict(
			{"trigger": json_name, "verb": "draw", "amount": 1, "text": "t"}
		)
		assert_object(effect).is_not_null()
		assert_int(effect.trigger).is_equal(value)
		assert_dict(effect.to_dict()).is_equal(
			{"trigger": json_name, "verb": "draw", "amount": 1, "text": "t"}
		)


func test_every_verb_name_round_trips() -> void:
	assert_int(CardEffect.VERB_NAMES.size()).is_equal(CardEffect.Verb.size())
	assert_int(CardEffect.Verb.size()).is_equal(10)
	for value: int in CardEffect.Verb.values():
		var json_name: String = CardEffect.verb_name(value)
		assert_str(json_name).is_equal(VERB_JSON[value])
		assert_int(CardEffect.verb_from_name(json_name)).is_equal(value)
		var source: Dictionary = {
			"trigger": "on_reveal", "verb": json_name, "amount": 2, "text": "Some text."
		}
		var effect: CardEffect = CardEffect.from_dict(source)
		assert_object(effect).is_not_null()
		assert_int(effect.verb).is_equal(value)
		assert_int(effect.amount).is_equal(2)
		assert_str(effect.text).is_equal("Some text.")
		assert_dict(effect.to_dict()).is_equal(source)
		# And through a whole card file: card 0 carries the verb.
		var db: CardDb = CardDb.from_json(_with_effect(0, source))
		assert_bool(db.is_valid()).is_true()
		assert_int(db.card_at(0).effect.verb).is_equal(value)


func test_unknown_names_map_to_minus_one() -> void:
	assert_int(CardEffect.trigger_from_name("on_draw")).is_equal(-1)
	assert_int(CardEffect.trigger_from_name("ON_REVEAL")).is_equal(-1)
	assert_int(CardEffect.verb_from_name("explode")).is_equal(-1)
	assert_int(CardEffect.verb_from_name("")).is_equal(-1)
	assert_str(CardEffect.trigger_name(-1)).is_empty()
	assert_str(CardEffect.trigger_name(CardEffect.Trigger.size())).is_empty()
	assert_str(CardEffect.verb_name(CardEffect.Verb.size())).is_empty()
	(
		assert_object(
			CardEffect.from_dict(
				{"trigger": "on_reveal", "verb": "explode", "amount": 0, "text": ""}
			)
		)
		. is_null()
	)
	assert_object(CardEffect.from_dict({"trigger": "on_reveal", "verb": "draw"})).is_null()


# --- R2: each validation failure -----------------------------------------------------


func test_wrong_count_fails() -> void:
	var too_few: Array[Dictionary] = _table()
	too_few.remove_at(19)
	_assert_fails_with(_json(too_few), CardDb.ERR_COUNT)

	var too_many: Array[Dictionary] = _table()
	var extra: Dictionary = too_many[0].duplicate()
	extra["id"] = "c21"
	too_many.append(extra)
	_assert_fails_with(_json(too_many), CardDb.ERR_COUNT)

	var none: Array[Dictionary] = []
	_assert_fails_with(_json(none), CardDb.ERR_COUNT)


func test_wrong_cost_mix_fails() -> void:
	# c20 becomes a cost-1 card with a legal flat: five 1s and one 7.
	var shifted: Array[Dictionary] = _table()
	shifted[19]["cost"] = 1
	shifted[19]["flat"] = 2
	_assert_fails_with(_json(shifted), CardDb.ERR_COST_MIX)

	# A cost outside 1..7, with a flat inside its own range.
	var out_of_range: Array[Dictionary] = _table()
	out_of_range[19]["cost"] = 8
	out_of_range[19]["flat"] = 9
	_assert_fails_with(_json(out_of_range), CardDb.ERR_COST_MIX)

	var zero_cost: Array[Dictionary] = _table()
	zero_cost[0]["cost"] = 0
	zero_cost[0]["flat"] = 1
	_assert_fails_with(_json(zero_cost), CardDb.ERR_COST_MIX)


func test_duplicate_id_fails() -> void:
	var cards: Array[Dictionary] = _table()
	cards[1]["id"] = "c01"
	_assert_fails_with(_json(cards), CardDb.ERR_DUPLICATE)


func test_flat_out_of_range_fails() -> void:
	var above: Array[Dictionary] = _table()
	above[0]["flat"] = 4  # cost 1 allows 0..3
	_assert_fails_with(_json(above), CardDb.ERR_FLAT)

	var above_high: Array[Dictionary] = _table()
	above_high[19]["flat"] = 10  # cost 7 allows 0..9
	_assert_fails_with(_json(above_high), CardDb.ERR_FLAT)

	var negative: Array[Dictionary] = _table()
	negative[5]["flat"] = -1
	_assert_fails_with(_json(negative), CardDb.ERR_FLAT)

	# Both edges are legal: c01 (cost 1) at 0 and c20 (cost 7) at 9.
	var edges: Array[Dictionary] = _table()
	edges[0]["flat"] = 0
	edges[19]["flat"] = 9
	assert_bool(CardDb.from_json(_json(edges)).is_valid()).is_true()


func test_bonus_out_of_range_fails() -> void:
	var above: Array[Dictionary] = _table()
	above[1]["bonus"] = MatchRules.MAX_BONUS + 1
	_assert_fails_with(_json(above), CardDb.ERR_BONUS)

	var negative: Array[Dictionary] = _table()
	negative[1]["bonus"] = -1
	_assert_fails_with(_json(negative), CardDb.ERR_BONUS)

	# Both edges are legal: 0 and MatchRules.MAX_BONUS (2).
	assert_int(MatchRules.MAX_BONUS).is_equal(2)
	var edges: Array[Dictionary] = _table()
	edges[1]["bonus"] = 0
	edges[2]["bonus"] = MatchRules.MAX_BONUS
	assert_bool(CardDb.from_json(_json(edges)).is_valid()).is_true()


func test_unknown_trigger_fails() -> void:
	_assert_fails_with(
		_with_effect(0, {"trigger": "on_draw", "verb": "draw", "amount": 1, "text": "x"}),
		CardDb.ERR_TRIGGER
	)
	# Names are case-sensitive snake_case.
	_assert_fails_with(
		_with_effect(0, {"trigger": "ON_REVEAL", "verb": "draw", "amount": 1, "text": "x"}),
		CardDb.ERR_TRIGGER
	)


func test_unknown_verb_fails() -> void:
	_assert_fails_with(
		_with_effect(1, {"trigger": "on_reveal", "verb": "explode", "amount": 0, "text": "x"}),
		CardDb.ERR_VERB
	)
	# The enum's own spelling is not the JSON name.
	_assert_fails_with(
		_with_effect(
			5, {"trigger": "on_score", "verb": "flat_up_on_score", "amount": 1, "text": ""}
		),
		CardDb.ERR_VERB
	)


func test_bad_effect_shape_fails() -> void:
	# Not an object or null.
	_assert_fails_with(_with_effect(0, "draw"), CardDb.ERR_SHAPE)
	_assert_fails_with(_with_effect(0, 1), CardDb.ERR_SHAPE)
	_assert_fails_with(_with_effect(0, []), CardDb.ERR_SHAPE)
	# A missing key.
	_assert_fails_with(
		_with_effect(0, {"trigger": "on_reveal", "verb": "draw", "amount": 1}), CardDb.ERR_SHAPE
	)
	_assert_fails_with(
		_with_effect(0, {"verb": "draw", "amount": 1, "text": "x"}), CardDb.ERR_SHAPE
	)
	# Wrong types or a negative or fractional amount.
	_assert_fails_with(
		_with_effect(0, {"trigger": 0, "verb": "draw", "amount": 1, "text": "x"}), CardDb.ERR_SHAPE
	)
	_assert_fails_with(
		_with_effect(0, {"trigger": "on_reveal", "verb": "draw", "amount": "1", "text": "x"}),
		CardDb.ERR_SHAPE
	)
	_assert_fails_with(
		_with_effect(0, {"trigger": "on_reveal", "verb": "draw", "amount": -1, "text": "x"}),
		CardDb.ERR_SHAPE
	)
	_assert_fails_with(
		_with_effect(0, {"trigger": "on_reveal", "verb": "draw", "amount": 1.5, "text": "x"}),
		CardDb.ERR_SHAPE
	)
	_assert_fails_with(
		_with_effect(0, {"trigger": "on_reveal", "verb": "draw", "amount": 1, "text": 3}),
		CardDb.ERR_SHAPE
	)


func test_bad_json_fails() -> void:
	_assert_fails_with('{"version": 2, "cards": [', CardDb.ERR_JSON)
	_assert_fails_with("not json at all", CardDb.ERR_JSON)
	_assert_fails_with("", CardDb.ERR_JSON)


func test_wrong_top_level_shape_fails() -> void:
	_assert_fails_with("[1, 2, 3]", CardDb.ERR_SHAPE)
	_assert_fails_with('{"version": 2}', CardDb.ERR_SHAPE)
	_assert_fails_with('{"cards": []}', CardDb.ERR_SHAPE)
	_assert_fails_with('{"version": 2, "cards": {}}', CardDb.ERR_SHAPE)


func test_bad_card_entry_fails() -> void:
	for key: String in ["id", "name", "cost", "flat", "bonus", "effect"]:
		var missing: Array[Dictionary] = _table()
		missing[3].erase(key)
		_assert_fails_with(_json(missing), CardDb.ERR_SHAPE)

	var string_cost: Array[Dictionary] = _table()
	string_cost[3]["cost"] = "1"
	_assert_fails_with(_json(string_cost), CardDb.ERR_SHAPE)

	var fractional_flat: Array[Dictionary] = _table()
	fractional_flat[3]["flat"] = 2.5
	_assert_fails_with(_json(fractional_flat), CardDb.ERR_SHAPE)

	var string_bonus: Array[Dictionary] = _table()
	string_bonus[3]["bonus"] = "0"
	_assert_fails_with(_json(string_bonus), CardDb.ERR_SHAPE)

	var empty_id: Array[Dictionary] = _table()
	empty_id[3]["id"] = ""
	_assert_fails_with(_json(empty_id), CardDb.ERR_SHAPE)

	# A format-1 entry (power, no flat, bonus or effect) is a shape failure in format 2.
	var format_one: Array[Dictionary] = _table()
	format_one[3] = {"id": "c04", "name": "Placeholder 04", "cost": 1, "power": 3}
	_assert_fails_with(_json(format_one), CardDb.ERR_SHAPE)

	_assert_fails_with('{"version": 2, "cards": [7]}', CardDb.ERR_SHAPE)


func test_unsupported_version_fails() -> void:
	_assert_fails_with(_json(_table(), 1), CardDb.ERR_VERSION)
	_assert_fails_with(_json(_table(), 3), CardDb.ERR_VERSION)


func test_missing_file_fails() -> void:
	var db: CardDb = CardDb.load_from_path("res://engine/data/no_such_file.json")
	assert_bool(db.is_valid()).is_false()
	assert_str(db.load_error()).starts_with(CardDb.ERR_FILE)
	assert_int(db.size()).is_equal(0)


func test_a_failed_load_refuses_to_start_a_match() -> void:
	var cards: Array[Dictionary] = _table()
	cards[0]["bonus"] = MatchRules.MAX_BONUS + 1
	var db: CardDb = CardDb.from_json(_json(cards))
	assert_bool(db.is_valid()).is_false()
	var engine: MatchEngine = MatchEngine.create(1, db)
	var started: ApplyResult = engine.start()
	assert_bool(started.ok).is_false()
	assert_int(started.error).is_equal(EngineError.Code.CARD_DATA_INVALID)


# --- Silent failure: nothing printed, pushed or asserted ------------------------------


func test_failures_log_no_errors() -> void:
	var too_few: Array[Dictionary] = _table()
	too_few.remove_at(0)
	var dup_ids: Array[Dictionary] = _table()
	dup_ids[1]["id"] = "c01"
	var texts: Array[String] = [
		'{"version": 2, "cards": [',
		"",
		"[1, 2, 3]",
		_json(too_few),
		_json(dup_ids),
		_json(_table(), 1),
		_with_effect(0, {"trigger": "on_reveal", "verb": "explode", "amount": 0, "text": ""}),
		_with_effect(0, {"trigger": "never", "verb": "draw", "amount": 0, "text": ""}),
		_with_effect(0, "not an effect"),
	]
	for text: String in texts:
		await assert_error(func() -> void: CardDb.from_json(text)).is_success()
	await (
		assert_error(func() -> void: CardDb.load_from_path("res://engine/data/no_such_file.json"))
		. is_success()
	)


func test_default_load_logs_no_errors() -> void:
	await assert_error(func() -> void: CardDb.load_default()).is_success()
