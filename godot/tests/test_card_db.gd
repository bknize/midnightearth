# gdlint: disable=max-public-methods
class_name TestCardDb
extends GdUnitTestSuite
## CardDb, CardDef and CardEffect, card pool format 4 (DC-07 T01; R1, R3, plan P1, P8;
## cycle 8 DC-09 T01, R9, R11, plan P1): a card has a flat, at most one bonus (×1.25 / ×1.5
## / ×2 in hundredths or +1 / +2) and at most one effect, which may carry a `uses` count;
## the loader checks unique ids, cost 1..7, flat 0..cost+4, the bonus values, the trigger
## and verb names, a whole `uses`, grow amounts in MatchRules.GROW_STEPS and each verb on a
## trigger it may use, with no card count and no cost mix. The DC-05 fixture
## (tests/fixtures/dc05_cards.json) is the 20 DC-05 cards converted (C5, C20), format 4.

const FIXTURE_CARDS: String = "res://tests/fixtures/dc05_cards.json"
## The fixture table, in file order c01..c20 (c13 vanilla flat 5 since C20).
const COSTS: Array[int] = [1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 6, 6, 7, 7]
const FLATS: Array[int] = [1, 2, 1, 3, 1, 1, 2, 4, 3, 3, 3, 4, 5, 6, 5, 5, 6, 8, 7, 7]
## The ×-bonus in hundredths, 0 for none (DC-05 bonus 1 → ×1.25, 2 → ×1.5; c13 none).
const TIMES: Array[int] = [0, 0, 125, 0, 0, 0, 125, 0, 0, 0, 125, 0, 0, 0, 0, 125, 0, 0, 0, 150]
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
	14:
	[
		CardEffect.Trigger.ON_REVEAL,
		CardEffect.Verb.OPPONENT_NEXT_NO_BONUS,
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
## Every JSON name, in enum order (plan P8).
const TRIGGER_JSON: Array[String] = [
	"on_reveal",
	"on_opponent_reveal",
	"on_score",
	"ongoing",
	"on_opponent_score",
	"on_moved",
	"on_ally_reveal",
]
const VERB_JSON: Array[String] = [
	"draw",
	"draw_then_discard",
	"free_first_next_turn",
	"swap_places",
	"opponent_next_no_bonus",
	"return_at_turn_end",
	"destroy_random_opponent",
	"flat_up",
	"carry_energy",
	"discard_own",
	"destroy_leftmost_own",
	"destroy_own_then_draw",
	"destroy_own_then_flat_up",
	"sacrifice_destroy",
	"burst",
	"unreveal_instead",
	"recover_destroyed",
	"move_self_left",
	"move_self_right",
	"copy_stats",
	"neighbour_times",
	"edge_left_times",
	"move_opponent_left",
	"shift_own_left",
	"reverse_opponent_row",
	"swap_opponent_right",
	"plus_on_moved",
	"grow_self_flat",
	"grow_self_times",
	"grow_self_plus",
	"grow_self_times_once",
	"grow_other_flat",
	"grow_hand_flat",
	"grow_hand_one_times",
	"grow_row_flat",
	"grow_row_times",
	"return_self_at_turn_end",
	"return_own_at_turn_end",
	"return_opponent_at_turn_end",
	"unreveal_at_turn_end",
	"cost_down_right",
	"cost_down_self",
	"draw_once",
	"ally_reveal_flat",
]


func _fixture() -> CardDb:
	return CardDb.load_from_path(FIXTURE_CARDS)


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


func _bonus_dict(i: int) -> Variant:
	if TIMES[i] == 0:
		return null
	return {"x": TIMES[i]}


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
					"bonus": _bonus_dict(i),
					"effect": _effect_dict(i),
				}
			)
		)
	return out


func _json(cards: Array[Dictionary], version: int = 4) -> String:
	return JSON.stringify({"version": version, "cards": cards})


## The table with card `index`'s effect replaced by `effect`.
func _with_effect(index: int, effect: Variant) -> String:
	var cards: Array[Dictionary] = _table()
	cards[index]["effect"] = effect
	return _json(cards)


## The table with card `index`'s bonus replaced by `bonus`.
func _with_bonus(index: int, bonus: Variant) -> String:
	var cards: Array[Dictionary] = _table()
	cards[index]["bonus"] = bonus
	return _json(cards)


func _assert_fails_with(text: String, prefix: String) -> void:
	var db: CardDb = CardDb.from_json(text)
	assert_bool(db.is_valid()).override_failure_message(db.load_error()).is_false()
	assert_str(db.load_error()).starts_with(prefix)
	assert_int(db.size()).is_equal(0)
	assert_object(db.card_at(0)).is_null()


func _assert_loads(text: String) -> void:
	var db: CardDb = CardDb.from_json(text)
	assert_bool(db.is_valid()).override_failure_message(db.load_error()).is_true()


# --- The fixture and the shipped pool -------------------------------------------------


func test_the_fixture_loads_with_20_cards_and_c13_vanilla() -> void:
	var db: CardDb = _fixture()
	assert_bool(db.is_valid()).override_failure_message(db.load_error()).is_true()
	assert_str(db.load_error()).is_empty()
	assert_int(db.size()).is_equal(20)
	var c13: CardDef = db.card_by_id("c13")
	assert_object(c13).is_not_null()
	assert_object(c13.effect).is_null()
	assert_int(c13.cost).is_equal(4)
	assert_int(c13.flat).is_equal(5)
	assert_int(c13.bonus_kind).is_equal(CardDef.BonusKind.NONE)
	assert_int(c13.bonus).is_equal(0)


func test_the_shipped_pool_loads_valid() -> void:
	var db: CardDb = CardDb.load_default()
	assert_bool(db.is_valid()).override_failure_message(db.load_error()).is_true()
	assert_int(db.size()).is_greater(0)


func test_the_fixture_matches_the_table() -> void:
	var db: CardDb = _fixture()
	var total_cost: int = 0
	var total_flat: int = 0
	for i: int in range(COSTS.size()):
		var def: CardDef = db.card_at(i)
		assert_object(def).is_not_null()
		assert_str(def.id).is_equal("c%02d" % (i + 1))
		assert_str(def.name).is_equal("Placeholder %02d" % (i + 1))
		assert_int(def.cost).is_equal(COSTS[i])
		assert_int(def.flat).is_equal(FLATS[i])
		if TIMES[i] == 0:
			assert_int(def.bonus_kind).is_equal(CardDef.BonusKind.NONE)
		else:
			assert_int(def.bonus_kind).is_equal(CardDef.BonusKind.TIMES)
		assert_int(def.bonus).is_equal(TIMES[i])
		total_cost += def.cost
		total_flat += def.flat
	assert_int(total_cost).is_equal(69)
	assert_int(total_flat).is_equal(77)


func test_the_fixture_effects_match_the_table() -> void:
	var db: CardDb = _fixture()
	var effect_cards: int = 0
	for i: int in range(COSTS.size()):
		var def: CardDef = db.card_at(i)
		if not EFFECTS.has(i):
			assert_object(def.effect).is_null()
			assert_that(def.to_dict()["effect"]).is_null()
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
	assert_int(effect_cards).is_equal(9)


func test_lookup_by_index_and_id() -> void:
	var db: CardDb = _fixture()
	assert_int(db.index_of("c11")).is_equal(10)
	assert_bool(db.has_id("c11")).is_true()
	assert_int(db.card_by_id("c11").flat).is_equal(3)
	assert_int(db.card_by_id("c11").bonus).is_equal(125)
	assert_str(db.card_at(19).id).is_equal("c20")
	assert_int(db.card_by_id("c20").bonus).is_equal(150)
	assert_int(db.index_of("c99")).is_equal(-1)
	assert_bool(db.has_id("c99")).is_false()
	assert_object(db.card_by_id("c99")).is_null()
	assert_object(db.card_at(-1)).is_null()
	assert_object(db.card_at(20)).is_null()
	# cards() hands out a copy.
	var copy: Array[CardDef] = db.cards()
	copy.clear()
	assert_int(db.size()).is_equal(20)


func test_in_memory_table_loads_valid() -> void:
	var db: CardDb = CardDb.from_json(_json(_table()))
	assert_bool(db.is_valid()).override_failure_message(db.load_error()).is_true()
	assert_int(db.size()).is_equal(20)
	assert_int(db.card_at(0).effect.verb).is_equal(CardEffect.Verb.DRAW)
	assert_object(db.card_at(1).effect).is_null()


func test_card_def_to_dict_round_trips_the_entry() -> void:
	var db: CardDb = _fixture()
	var table: Array[Dictionary] = _table()
	for i: int in range(table.size()):
		assert_dict(db.card_at(i).to_dict()).is_equal(table[i])


# --- Bonus kinds (R1, C6) -------------------------------------------------------------


func test_every_legal_bonus_loads_with_its_kind() -> void:
	var cases: Array[Dictionary] = [
		{"bonus": {"x": 125}, "kind": CardDef.BonusKind.TIMES, "value": 125},
		{"bonus": {"x": 150}, "kind": CardDef.BonusKind.TIMES, "value": 150},
		{"bonus": {"x": 200}, "kind": CardDef.BonusKind.TIMES, "value": 200},
		{"bonus": {"plus": 1}, "kind": CardDef.BonusKind.PLUS, "value": 1},
		{"bonus": {"plus": 2}, "kind": CardDef.BonusKind.PLUS, "value": 2},
		{"bonus": null, "kind": CardDef.BonusKind.NONE, "value": 0},
	]
	for case: Dictionary in cases:
		var db: CardDb = CardDb.from_json(_with_bonus(1, case["bonus"]))
		var where: String = "%s: %s" % [case, db.load_error()]
		assert_bool(db.is_valid()).override_failure_message(where).is_true()
		var def: CardDef = db.card_at(1)
		var kind: int = case["kind"]
		var value: int = case["value"]
		assert_int(def.bonus_kind).override_failure_message(where).is_equal(kind)
		assert_int(def.bonus).override_failure_message(where).is_equal(value)
		assert_that(def.to_dict()["bonus"]).is_equal(case["bonus"])


func test_a_bonus_outside_the_values_fails() -> void:
	_assert_fails_with(_with_bonus(1, {"x": 130}), CardDb.ERR_BONUS)
	_assert_fails_with(_with_bonus(1, {"plus": 3}), CardDb.ERR_BONUS)
	_assert_fails_with(_with_bonus(1, {"x": 100}), CardDb.ERR_BONUS)
	_assert_fails_with(_with_bonus(1, {"x": 1}), CardDb.ERR_BONUS)
	_assert_fails_with(_with_bonus(1, {"plus": 0}), CardDb.ERR_BONUS)
	_assert_fails_with(_with_bonus(1, {"plus": -1}), CardDb.ERR_BONUS)
	_assert_fails_with(_with_bonus(1, {"plus": 125}), CardDb.ERR_BONUS)


func test_a_malformed_bonus_fails_as_shape() -> void:
	# A DC-05 integer bonus is not format 3.
	_assert_fails_with(_with_bonus(1, 0), CardDb.ERR_SHAPE)
	_assert_fails_with(_with_bonus(1, 1), CardDb.ERR_SHAPE)
	_assert_fails_with(_with_bonus(1, "x"), CardDb.ERR_SHAPE)
	_assert_fails_with(_with_bonus(1, []), CardDb.ERR_SHAPE)
	_assert_fails_with(_with_bonus(1, {}), CardDb.ERR_SHAPE)
	_assert_fails_with(_with_bonus(1, {"y": 125}), CardDb.ERR_SHAPE)
	_assert_fails_with(_with_bonus(1, {"x": 125, "plus": 1}), CardDb.ERR_SHAPE)
	_assert_fails_with(_with_bonus(1, {"x": 1.25}), CardDb.ERR_SHAPE)
	_assert_fails_with(_with_bonus(1, {"x": "125"}), CardDb.ERR_SHAPE)


# --- CardEffect: every trigger and verb name round-trips ------------------------------


## A trigger `verb` may use (cycle 8 R11): the first CardEffect.ALLOWED_TRIGGERS lists for
## it, else on_reveal.
func _legal_trigger(verb: int) -> String:
	if CardEffect.ALLOWED_TRIGGERS.has(verb):
		var allowed: Array = CardEffect.ALLOWED_TRIGGERS[verb]
		var first: int = allowed[0]
		return CardEffect.trigger_name(first)
	return "on_reveal"


## An amount `verb` may name (cycle 8 R5, R11): 2, or for a grow verb the largest step of
## its stat in MatchRules.GROW_STEPS.
func _legal_amount(verb: int) -> int:
	if not CardEffect.GROW_STAT.has(verb):
		return 2
	var stat: String = CardEffect.GROW_STAT[verb]
	var steps: Array = MatchRules.GROW_STEPS[stat]
	var last: int = steps[steps.size() - 1]
	return last


func test_every_trigger_name_round_trips() -> void:
	assert_int(CardEffect.TRIGGER_NAMES.size()).is_equal(CardEffect.Trigger.size())
	assert_int(CardEffect.Trigger.size()).is_equal(7)
	for value: int in CardEffect.Trigger.values():
		var json_name: String = CardEffect.trigger_name(value)
		assert_str(json_name).is_equal(TRIGGER_JSON[value])
		assert_int(CardEffect.trigger_from_name(json_name)).is_equal(value)
		var source: Dictionary = {"trigger": json_name, "verb": "draw", "amount": 1, "text": "t"}
		var effect: CardEffect = CardEffect.from_dict(source)
		assert_object(effect).is_not_null()
		assert_int(effect.trigger).is_equal(value)
		assert_dict(effect.to_dict()).is_equal(source)
		# And through a whole card file: card 0 carries the trigger.
		var db: CardDb = CardDb.from_json(_with_effect(0, source))
		assert_bool(db.is_valid()).override_failure_message(db.load_error()).is_true()
		assert_int(db.card_at(0).effect.trigger).is_equal(value)


func test_every_verb_name_round_trips() -> void:
	assert_int(CardEffect.VERB_NAMES.size()).is_equal(CardEffect.Verb.size())
	# Nine DC-05 verbs (the switch retired), the eighteen Ruin and Drift verbs (P8) and the
	# seventeen Bloom and Echo verbs (cycle 8 P4, P6).
	assert_int(CardEffect.Verb.size()).is_equal(44)
	for value: int in CardEffect.Verb.values():
		var json_name: String = CardEffect.verb_name(value)
		assert_str(json_name).is_equal(VERB_JSON[value])
		assert_int(CardEffect.verb_from_name(json_name)).is_equal(value)
		var amount: int = _legal_amount(value)
		var source: Dictionary = {
			"trigger": _legal_trigger(value), "verb": json_name, "amount": amount, "text": "Some."
		}
		var effect: CardEffect = CardEffect.from_dict(source)
		assert_object(effect).is_not_null()
		assert_int(effect.verb).is_equal(value)
		assert_int(effect.amount).is_equal(amount)
		assert_str(effect.text).is_equal("Some.")
		assert_dict(effect.to_dict()).is_equal(source)
		var db: CardDb = CardDb.from_json(_with_effect(0, source))
		assert_bool(db.is_valid()).override_failure_message(db.load_error()).is_true()
		assert_int(db.card_at(0).effect.verb).is_equal(value)


func test_the_new_plan_effects_load() -> void:
	var burst: Dictionary = {
		"trigger": "on_opponent_score", "verb": "burst", "amount": 0, "text": "Burst."
	}
	var moved: Dictionary = {
		"trigger": "on_moved", "verb": "plus_on_moved", "amount": 2, "text": "Moved."
	}
	var lodestone: Dictionary = {
		"trigger": "ongoing", "verb": "neighbour_times", "amount": 125, "text": "Lodestone."
	}
	var cards: Array[Dictionary] = _table()
	cards[0]["effect"] = burst
	cards[1]["effect"] = moved
	cards[2]["effect"] = lodestone
	var db: CardDb = CardDb.from_json(_json(cards))
	assert_bool(db.is_valid()).override_failure_message(db.load_error()).is_true()
	assert_int(db.card_at(0).effect.trigger).is_equal(CardEffect.Trigger.ON_OPPONENT_SCORE)
	assert_int(db.card_at(0).effect.verb).is_equal(CardEffect.Verb.BURST)
	assert_int(db.card_at(1).effect.trigger).is_equal(CardEffect.Trigger.ON_MOVED)
	assert_int(db.card_at(1).effect.verb).is_equal(CardEffect.Verb.PLUS_ON_MOVED)
	assert_int(db.card_at(2).effect.amount).is_equal(125)


func test_retired_and_renamed_verbs() -> void:
	# C20: the switch is gone; R14: the DC-05 bonus-0 verb has its DC-07 name.
	assert_int(CardEffect.verb_from_name("switch_stats")).is_equal(-1)
	assert_int(CardEffect.verb_from_name("opponent_next_bonus_zero")).is_equal(-1)
	assert_int(CardEffect.verb_from_name("opponent_next_no_bonus")).is_equal(
		CardEffect.Verb.OPPONENT_NEXT_NO_BONUS
	)
	_assert_fails_with(
		_with_effect(12, {"trigger": "on_reveal", "verb": "switch_stats", "amount": 0, "text": ""}),
		CardDb.ERR_VERB
	)
	_assert_fails_with(
		_with_effect(
			14,
			{"trigger": "on_reveal", "verb": "opponent_next_bonus_zero", "amount": 0, "text": ""}
		),
		CardDb.ERR_VERB
	)


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


# --- R3: the pool checks --------------------------------------------------------------


func test_a_pool_has_no_card_count_and_no_cost_mix() -> void:
	var too_few: Array[Dictionary] = _table()
	too_few.remove_at(19)
	_assert_loads(_json(too_few))

	var too_many: Array[Dictionary] = _table()
	var extra: Dictionary = too_many[0].duplicate()
	extra["id"] = "c21"
	too_many.append(extra)
	_assert_loads(_json(too_many))

	# c20 becomes a cost-1 card: five 1s and one 7, no longer the Phase 3 mix.
	var shifted: Array[Dictionary] = _table()
	shifted[19]["cost"] = 1
	shifted[19]["flat"] = 2
	_assert_loads(_json(shifted))


func test_cost_out_of_range_fails() -> void:
	var above: Array[Dictionary] = _table()
	above[19]["cost"] = 8
	above[19]["flat"] = 9
	_assert_fails_with(_json(above), CardDb.ERR_COST)

	var zero: Array[Dictionary] = _table()
	zero[0]["cost"] = 0
	zero[0]["flat"] = 1
	_assert_fails_with(_json(zero), CardDb.ERR_COST)

	# Both edges are legal.
	var edges: Array[Dictionary] = _table()
	edges[0]["cost"] = 1
	edges[19]["cost"] = 7
	_assert_loads(_json(edges))


func test_duplicate_id_fails() -> void:
	var cards: Array[Dictionary] = _table()
	cards[1]["id"] = "c01"
	_assert_fails_with(_json(cards), CardDb.ERR_DUPLICATE)


func test_flat_cost_plus_5_fails_and_cost_plus_4_passes() -> void:
	assert_int(MatchRules.MAX_FLAT_OVER_COST).is_equal(4)
	var above: Array[Dictionary] = _table()
	above[0]["flat"] = 6  # cost 1 allows 0..5
	_assert_fails_with(_json(above), CardDb.ERR_FLAT)

	var above_high: Array[Dictionary] = _table()
	above_high[19]["flat"] = 12  # cost 7 allows 0..11
	_assert_fails_with(_json(above_high), CardDb.ERR_FLAT)

	var negative: Array[Dictionary] = _table()
	negative[5]["flat"] = -1
	_assert_fails_with(_json(negative), CardDb.ERR_FLAT)

	# Both edges are legal: c01 (cost 1) at 0 and 5, c20 (cost 7) at 11.
	var edges: Array[Dictionary] = _table()
	edges[0]["flat"] = 5
	edges[1]["flat"] = 0
	edges[19]["flat"] = 11
	_assert_loads(_json(edges))


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


# --- Cycle 8 R9, R11 (DC-09 T01): uses, grow steps and verb/trigger pairs ----------------


func _effect(trigger: String, verb: String, amount: Variant) -> Dictionary:
	return {"trigger": trigger, "verb": verb, "amount": amount, "text": "x"}


## `uses` is optional; a whole number >= 0 loads (0 is unlimited) and round-trips, anything
## else fails with the uses error (1.5, -1, a string).
func test_uses_must_be_a_whole_number() -> void:
	var limited: Dictionary = _effect("on_score", "grow_self_times_once", 50)
	limited["uses"] = 1
	var db: CardDb = CardDb.from_json(_with_effect(0, limited))
	assert_bool(db.is_valid()).override_failure_message(db.load_error()).is_true()
	assert_int(db.card_at(0).effect.uses).is_equal(1)
	assert_dict(db.card_at(0).effect.to_dict()).is_equal(limited)
	var unlimited: Dictionary = _effect("on_reveal", "draw", 1)
	unlimited["uses"] = 0
	var zero: CardDb = CardDb.from_json(_with_effect(0, unlimited))
	assert_bool(zero.is_valid()).override_failure_message(zero.load_error()).is_true()
	assert_int(zero.card_at(0).effect.uses).is_equal(0)
	# An unlimited effect writes no `uses` key, so a format-3 effect reads the same.
	assert_bool(zero.card_at(0).effect.to_dict().has("uses")).is_false()
	assert_int(_fixture().card_at(0).effect.uses).is_equal(0)
	for bad: Variant in [1.5, -1, "1", null]:
		var effect: Dictionary = _effect("on_reveal", "draw_once", 2)
		effect["uses"] = bad
		_assert_fails_with(_with_effect(0, effect), CardDb.ERR_USES)
		assert_object(CardEffect.from_dict(effect)).is_null()


## A grow verb names one of MatchRules.GROW_STEPS for its stat: grow_self_times 25 and 50
## load, 30 fails; the flat, plus and cost steps likewise.
func test_grow_amounts_are_the_fixed_steps() -> void:
	var expected: Dictionary = {"flat": [1, 2], "times": [25, 50], "plus": [1], "cost": [1, 2]}
	assert_int(MatchRules.GROW_STEPS.size()).is_equal(expected.size())
	for stat: String in expected:
		var steps: Array = MatchRules.GROW_STEPS[stat]
		assert_array(steps).override_failure_message(stat).is_equal(expected[stat])
	_assert_loads(_with_effect(0, _effect("on_score", "grow_self_times", 25)))
	_assert_loads(_with_effect(0, _effect("on_score", "grow_self_times", 50)))
	_assert_fails_with(_with_effect(0, _effect("on_score", "grow_self_times", 30)), CardDb.ERR_GROW)
	_assert_loads(_with_effect(0, _effect("on_reveal", "grow_hand_flat", 2)))
	_assert_fails_with(_with_effect(0, _effect("on_reveal", "grow_hand_flat", 3)), CardDb.ERR_GROW)
	_assert_fails_with(_with_effect(0, _effect("on_score", "grow_self_plus", 2)), CardDb.ERR_GROW)
	_assert_loads(_with_effect(0, _effect("on_reveal", "cost_down_self", 2)))
	_assert_fails_with(_with_effect(0, _effect("on_reveal", "cost_down_right", 0)), CardDb.ERR_GROW)
	# A verb outside the grow family keeps any amount (Messenger draws 2, Refrain +1).
	_assert_loads(_with_effect(0, _effect("on_reveal", "draw_once", 3)))
	_assert_loads(_with_effect(0, _effect("on_ally_reveal", "ally_reveal_flat", 5)))


## Each verb only on the triggers the plan allows: unreveal_at_turn_end is ongoing only,
## grow_self_times on on_score or on_reveal, on_ally_reveal takes ally_reveal_flat or draw.
func test_a_verb_on_a_trigger_it_may_not_use_fails() -> void:
	_assert_fails_with(
		_with_effect(0, _effect("on_reveal", "unreveal_at_turn_end", 0)), CardDb.ERR_PAIR
	)
	_assert_loads(_with_effect(0, _effect("ongoing", "unreveal_at_turn_end", 0)))
	_assert_loads(_with_effect(0, _effect("on_reveal", "grow_self_times", 25)))
	_assert_fails_with(_with_effect(0, _effect("ongoing", "grow_self_times", 25)), CardDb.ERR_PAIR)
	_assert_fails_with(
		_with_effect(0, _effect("on_reveal", "ally_reveal_flat", 1)), CardDb.ERR_PAIR
	)
	_assert_loads(_with_effect(0, _effect("on_ally_reveal", "draw", 1)))
	_assert_fails_with(_with_effect(0, _effect("on_ally_reveal", "burst", 0)), CardDb.ERR_PAIR)
	# The verbs of earlier cycles keep every other trigger they had.
	_assert_loads(_with_effect(0, _effect("on_opponent_reveal", "draw", 1)))
	(
		assert_bool(
			CardEffect.is_allowed_pair(
				CardEffect.Trigger.ON_SCORE, CardEffect.Verb.FLAT_UP_ON_SCORE
			)
		)
		. is_true()
	)


## The shipped pool and the fixture are format 4 (the fixture's cards unchanged); a
## format-3 file fails with the version error.
func test_format_3_fails_with_the_version_error() -> void:
	assert_int(CardDb.FORMAT_VERSION).is_equal(4)
	_assert_fails_with(_json(_table(), 3), CardDb.ERR_VERSION)
	_assert_loads(_json(_table(), 4))
	for path: String in [FIXTURE_CARDS, CardDb.DEFAULT_PATH]:
		var db: CardDb = CardDb.load_from_path(path)
		assert_bool(db.is_valid()).override_failure_message(path + db.load_error()).is_true()
		var text: String = FileAccess.get_file_as_string(path)
		assert_bool(text.contains('"version": 4')).override_failure_message(path).is_true()


## A failed R11 check refuses to start a match (CARD_DATA_INVALID).
func test_an_r11_failure_refuses_to_start_a_match() -> void:
	var db: CardDb = CardDb.from_json(_with_effect(0, _effect("on_score", "grow_self_times", 30)))
	assert_bool(db.is_valid()).is_false()
	var started: ApplyResult = FixtureDecks.engine(1, db).start()
	assert_bool(started.ok).is_false()
	assert_int(started.error).is_equal(EngineError.Code.CARD_DATA_INVALID)


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
	_assert_fails_with('{"version": 4, "cards": [', CardDb.ERR_JSON)
	_assert_fails_with("not json at all", CardDb.ERR_JSON)
	_assert_fails_with("", CardDb.ERR_JSON)


func test_wrong_top_level_shape_fails() -> void:
	_assert_fails_with("[1, 2, 3]", CardDb.ERR_SHAPE)
	_assert_fails_with('{"version": 4}', CardDb.ERR_SHAPE)
	_assert_fails_with('{"cards": []}', CardDb.ERR_SHAPE)
	_assert_fails_with('{"version": 4, "cards": {}}', CardDb.ERR_SHAPE)


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

	var empty_id: Array[Dictionary] = _table()
	empty_id[3]["id"] = ""
	_assert_fails_with(_json(empty_id), CardDb.ERR_SHAPE)

	# A format-1 entry (power, no flat, bonus or effect) is a shape failure.
	var format_one: Array[Dictionary] = _table()
	format_one[3] = {"id": "c04", "name": "Placeholder 04", "cost": 1, "power": 3}
	_assert_fails_with(_json(format_one), CardDb.ERR_SHAPE)

	_assert_fails_with('{"version": 4, "cards": [7]}', CardDb.ERR_SHAPE)


## A format-2 file (the DC-05 card data) fails on its version before any entry is read.
func test_a_format_2_file_fails_with_the_version_error() -> void:
	var format_two: Array[Dictionary] = _table()
	for entry: Dictionary in format_two:
		entry["bonus"] = 0
	_assert_fails_with(_json(format_two, 2), CardDb.ERR_VERSION)
	_assert_fails_with(_json(_table(), 2), CardDb.ERR_VERSION)
	_assert_fails_with(_json(_table(), 1), CardDb.ERR_VERSION)
	_assert_fails_with(_json(_table(), 3), CardDb.ERR_VERSION)
	_assert_fails_with(_json(_table(), 5), CardDb.ERR_VERSION)
	assert_int(CardDb.FORMAT_VERSION).is_equal(4)


func test_missing_file_fails() -> void:
	var db: CardDb = CardDb.load_from_path("res://engine/data/no_such_file.json")
	assert_bool(db.is_valid()).is_false()
	assert_str(db.load_error()).starts_with(CardDb.ERR_FILE)
	assert_int(db.size()).is_equal(0)


## The failed pool under the fixture deck list (DC-07 T02): start() refuses it.
func test_a_failed_load_refuses_to_start_a_match() -> void:
	var db: CardDb = CardDb.from_json(_with_bonus(0, {"x": 130}))
	assert_bool(db.is_valid()).is_false()
	var engine: MatchEngine = FixtureDecks.engine(1, db)
	var started: ApplyResult = engine.start()
	assert_bool(started.ok).is_false()
	assert_int(started.error).is_equal(EngineError.Code.CARD_DATA_INVALID)


# --- MatchRules: the DC-07 constants --------------------------------------------------


func test_match_rules_constants() -> void:
	assert_int(MatchRules.MULT_ONE).is_equal(100)
	var times: Array[int] = [125, 150, 200]
	var plus: Array[int] = [1, 2]
	assert_array(MatchRules.TIMES_VALUES).is_equal(times)
	assert_array(MatchRules.PLUS_VALUES).is_equal(plus)
	assert_int(MatchRules.MAX_FLAT_OVER_COST).is_equal(4)
	assert_int(MatchRules.BURST_FLAT).is_equal(5)
	assert_int(MatchRules.DECK_TAG).is_equal(0x646B)


# --- Silent failure: nothing printed, pushed or asserted ------------------------------


func test_failures_log_no_errors() -> void:
	var dup_ids: Array[Dictionary] = _table()
	dup_ids[1]["id"] = "c01"
	var texts: Array[String] = [
		'{"version": 4, "cards": [',
		"",
		"[1, 2, 3]",
		_json(dup_ids),
		_json(_table(), 2),
		_with_bonus(0, {"x": 130}),
		_with_bonus(0, {"plus": 3}),
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
	await assert_error(func() -> void: CardDb.load_from_path(FIXTURE_CARDS)).is_success()
