# gdlint: disable=max-public-methods
class_name TestCardDb
extends GdUnitTestSuite
## CardDb, CardDef and CardAbility, pool format 5 (DC-13 T02; cycle 9 plan P2, P3, spec R22,
## R60, R64). The shipped file loads the canon's 50 cards (30 evergreen, 10 Greed, 10 Ramp)
## with the numbers and texts of rules/cards-v2; each loader check fails by its name: a
## Bonus off the legal values, a Cost over 7 without `cost_on_turn`, an unknown moment or
## verb, a verb on a moment it may not sit on, an amount out of its range, a missing rules
## text, a duplicate id, an unknown tag and an old version. Loading never prints.

## The canon's rows (rules/cards-v2 section 2), as [id, name, tag, cost, power, bonus kind
## ("" none, "mult" or "add"), bonus hundredths, the verb of its one ability or ""].
const CANON: Array = [
	["ev01", "Mote", "evergreen", 1, 2, "", 0, ""],
	["ev02", "Wisp", "evergreen", 1, 1, "mult", 125, ""],
	["ev03", "Tuft", "evergreen", 1, 1, "", 0, "grow_self_power"],
	["ev04", "Pebble", "evergreen", 2, 3, "", 0, ""],
	["ev05", "Scout", "evergreen", 2, 2, "", 0, "draw"],
	["ev06", "Delve", "evergreen", 2, 2, "", 0, "delve"],
	["ev07", "Lookout", "evergreen", 2, 2, "", 0, "look_at_opposing"],
	["ev08", "Scapegoat", "evergreen", 2, 3, "", 0, "scapegoat"],
	["ev09", "Ward", "evergreen", 2, 2, "", 0, "ward_mute"],
	["ev10", "Mirror", "evergreen", 2, 0, "", 0, "copy_stats"],
	["ev11", "Nudge", "evergreen", 2, 3, "", 0, "move_self_right"],
	["ev12", "Cobble", "evergreen", 3, 4, "", 0, ""],
	["ev13", "Lyre", "evergreen", 3, 2, "mult", 150, ""],
	["ev14", "Pantry", "evergreen", 3, 2, "", 0, "hand_size_add"],
	["ev15", "Brace", "evergreen", 3, 4, "", 0, "anchored_self"],
	["ev16", "Loom", "evergreen", 3, 3, "", 0, "right_power"],
	["ev17", "Hearth", "evergreen", 4, 5, "", 0, ""],
	["ev18", "Rook", "evergreen", 4, 4, "add", 25, ""],
	["ev19", "Bolster", "evergreen", 4, 4, "", 0, "others_power"],
	["ev20", "Bastion", "evergreen", 4, 4, "", 0, "cannot_condemn_self"],
	["ev21", "Granite", "evergreen", 5, 6, "", 0, ""],
	["ev22", "Crest", "evergreen", 5, 4, "mult", 150, ""],
	["ev23", "Torch", "evergreen", 5, 4, "add", 50, ""],
	["ev24", "Basalt", "evergreen", 6, 7, "", 0, ""],
	["ev25", "Kiln", "evergreen", 6, 6, "mult", 125, ""],
	["ev26", "Orrery", "evergreen", 6, 3, "mult", 200, ""],
	["ev27", "Vault", "evergreen", 6, 5, "add", 50, ""],
	["ev28", "Obsidian", "evergreen", 7, 9, "", 0, ""],
	["ev29", "Monolith", "evergreen", 7, 6, "mult", 150, ""],
	["ev30", "Zenith", "evergreen", 7, 4, "add", 100, ""],
	["gr01", "Ember", "greed", 1, 4, "", 0, "discard_own"],
	["gr02", "Pip", "greed", 1, 3, "", 0, ""],
	["gr03", "Flare", "greed", 2, 5, "", 0, "condemn_self"],
	["gr04", "Skim", "greed", 2, 2, "mult", 125, ""],
	["gr05", "Cinder", "greed", 3, 7, "", 0, "discard_own"],
	["gr06", "Courier", "greed", 3, 3, "", 0, "draw"],
	["gr07", "Banner", "greed", 4, 3, "", 0, "plain_power"],
	["gr08", "Bounty", "greed", 5, 7, "", 0, "opponent_draw"],
	["gr09", "Gilt", "greed", 6, 4, "mult", 150, ""],
	["gr10", "Jackpot", "greed", 7, 10, "", 0, "discard_hand"],
	["ra01", "Whisper", "ramp", 1, 1, "", 0, "grow_self_power"],
	["ra02", "Sapling", "ramp", 2, 1, "mult", 125, "grow_self_mult_add"],
	["ra03", "Rain", "ramp", 2, 1, "", 0, "grow_hand_power"],
	["ra04", "Dynamo", "ramp", 2, 2, "", 0, "energy_grant"],
	["ra05", "Tinker", "ramp", 3, 3, "", 0, "cost_down_right"],
	["ra06", "Idler", "ramp", 3, 2, "", 0, "pass_power_add"],
	["ra07", "Lantern", "ramp", 4, 4, "", 0, "free_first_next_turn"],
	["ra08", "Graft", "ramp", 4, 3, "", 0, "grow_right_mult_times"],
	["ra09", "Layaway", "ramp", 5, 6, "", 0, "cost_down_self"],
	["ra10", "Colossus", "ramp", 12, 12, "", 0, "cost_on_turn"],
	["gy01", "Fuse", "graveyard", 2, 1, "", 0, "fuse"],
	["gy02", "Tithe", "graveyard", 2, 2, "", 0, "tithe_energy"],
	["gy03", "Reliquary", "graveyard", 3, 2, "mult", 125, "reliquary_mult"],
	["gy04", "Boneyard", "graveyard", 3, 2, "", 0, "pile_power"],
	["gy05", "Wraith", "graveyard", 3, 3, "", 0, "wraith_fade"],
	["gy06", "Glutton", "graveyard", 4, 2, "", 0, "condemn_other_gain"],
	["gy07", "Revive", "graveyard", 4, 3, "", 0, "revive"],
	["gy08", "Exhume", "graveyard", 4, 4, "", 0, "exhume"],
	["gy09", "Immolator", "graveyard", 5, 4, "", 0, "immolate"],
	["gy10", "Reset", "graveyard", 6, 5, "", 0, "reset_piles"],
	["ct01", "Eddy", "control", 2, 1, "add", 25, "moved_add"],
	["ct02", "Pin", "control", 2, 2, "", 0, "pin"],
	["ct03", "Shepherd", "control", 3, 3, "", 0, "swap_self"],
	["ct04", "Skip", "control", 3, 3, "", 0, "skip_next"],
	["ct05", "Fence", "control", 3, 3, "", 0, "fence"],
	["ct06", "Herald", "control", 4, 3, "", 0, "rightmost_mult"],
	["ct07", "Level", "control", 4, 4, "", 0, "level_power"],
	["ct08", "Shake", "control", 5, 5, "", 0, "shake"],
	["ct09", "Tempest", "control", 6, 5, "", 0, "reverse_opposing"],
	["ct10", "Cull", "control", 7, 7, "", 0, "cull"],
]
## Rules texts checked word for word against rules/cards-v2 (a sample over the moments).
const TEXTS: Dictionary[String, String] = {
	"ev03": "On score: this card gets Power +1 until it leaves your row.",
	"ev06":
	(
		"On reveal: look at the top three cards of your Deck, draw one of them and shuffle"
		+ " the other two into your Deck."
	),
	"ev08": "On squelch: end this card's Squelch and Condemn this card.",
	"gr07": "Ongoing: each of your cards that has no rules text has Power +4.",
	"ra02": "On score: this card's Mult gets +0.25 for the match, to a maximum of ×2.",
	"ra04": "On start: you have +1 Energy this Turn.",
	"ra06":
	(
		"On commit: if you Pass this Turn, this card gets Power +2 and Add +0.5 until end"
		+ " of turn."
	),
	"ra09": "On commit (while in your hand): this card costs 1 less for the match.",
	"ra10": "Ongoing (while in your hand): on Turn 7 this card's Cost is 7.",
	"gy02":
	(
		"On discard (a Condemned card of yours Discarded at turn end): you have +1 Energy"
		+ " next Turn for each such card, at most +3 per turn end."
	),
	"gy05": "Ongoing: your Condemned cards have Fade instead of Condemned when exit marks resolve.",
	"ct01": "On moved: this card's Add gets +0.25 until end of turn.",
	"ct06": "Ongoing: while this card is in the rightmost slot of your row, its Mult is ×1.5.",
	"ct10":
	(
		"On reveal: each seat chooses five cards on its row; Condemn every card on both rows"
		+ " that was not chosen."
	),
}

# --- Helpers --------------------------------------------------------------------------


## A well-formed card entry: a plain body.
func _plain() -> Dictionary:
	return {
		"id": "x01",
		"name": "Test",
		"tag": "evergreen",
		"cost": 2,
		"power": 3,
		"bonus": null,
		"abilities": [],
		"text": "",
	}


## A well-formed card entry with one ability {moment, verb, amount, text}.
func _with_ability(moment: String, verb: String, amount: int) -> Dictionary:
	var entry: Dictionary = _plain()
	var text: String = "Some text."
	entry["abilities"] = [{"moment": moment, "verb": verb, "amount": amount, "text": text}]
	entry["text"] = text
	return entry


func _pool_of(entries: Array, version: int = CardDb.FORMAT_VERSION) -> CardDb:
	return CardDb.from_json(JSON.stringify({"version": version, "cards": entries}))


func _assert_invalid(db: CardDb, prefix: String) -> void:
	assert_bool(db.is_valid()).override_failure_message(prefix).is_false()
	assert_str(db.load_error()).starts_with(prefix)
	assert_int(db.size()).is_equal(0)
	assert_object(db.card_at(0)).is_null()


func _assert_valid(db: CardDb) -> void:
	assert_bool(db.is_valid()).override_failure_message(db.load_error()).is_true()


# --- The shipped file -----------------------------------------------------------------


## DC-14 T13 adds Graveyard and Control (70 cards); T12's Combo and Disruption bring 90.
func test_the_shipped_file_loads_the_pool_by_tag() -> void:
	var db: CardDb = CardDb.load_default()
	_assert_valid(db)
	assert_int(db.size()).is_equal(70)
	assert_int(db.cards_tagged("evergreen").size()).is_equal(30)
	assert_int(db.cards_tagged("greed").size()).is_equal(10)
	assert_int(db.cards_tagged("ramp").size()).is_equal(10)
	assert_int(db.cards_tagged("graveyard").size()).is_equal(10)
	assert_int(db.cards_tagged("control").size()).is_equal(10)


## Every row of the canon: name, tag, Cost, Power, Bonus and the ability's verb; a plain
## body has no ability and no text, a card with an ability its text on card and ability.
func test_every_shipped_card_matches_the_canon() -> void:
	var db: CardDb = CardDb.load_default()
	_assert_valid(db)
	assert_int(db.size()).is_equal(CANON.size())
	for raw: Variant in CANON:
		var row: Array = raw
		var card_id: String = row[0]
		var def: CardDef = db.card_by_id(card_id)
		assert_object(def).override_failure_message(card_id).is_not_null()
		if def == null:
			continue
		var card_name: String = row[1]
		var tag: String = row[2]
		var cost: int = row[3]
		var power: int = row[4]
		assert_str(def.name).override_failure_message(card_id).is_equal(card_name)
		assert_str(def.tag).override_failure_message(card_id).is_equal(tag)
		assert_int(def.cost).override_failure_message(card_id).is_equal(cost)
		assert_int(def.power).override_failure_message(card_id).is_equal(power)
		_assert_bonus(def, row)
		_assert_ability(def, row)


func _assert_bonus(def: CardDef, row: Array) -> void:
	var kind: String = row[5]
	var amount: int = row[6]
	var expected: CardDef.BonusKind = CardDef.BonusKind.NONE
	if kind == "mult":
		expected = CardDef.BonusKind.MULT
	elif kind == "add":
		expected = CardDef.BonusKind.ADD
	assert_int(def.bonus_kind).override_failure_message(def.id).is_equal(expected)
	assert_int(def.bonus).override_failure_message(def.id).is_equal(amount)


func _assert_ability(def: CardDef, row: Array) -> void:
	var verb: String = row[7]
	if verb == "":
		assert_bool(def.is_plain()).override_failure_message(def.id).is_true()
		assert_str(def.text).override_failure_message(def.id).is_empty()
		return
	assert_int(def.abilities.size()).override_failure_message(def.id).is_equal(1)
	var ability: CardAbility = def.abilities[0]
	assert_str(ability.verb).override_failure_message(def.id).is_equal(verb)
	assert_bool(CardAbility.is_allowed_pair(ability.moment, verb)).is_true()
	assert_str(def.text).override_failure_message(def.id).is_not_empty()
	assert_str(ability.text).override_failure_message(def.id).is_equal(def.text)


func test_shipped_texts_and_amounts_match_the_canon() -> void:
	var db: CardDb = CardDb.load_default()
	_assert_valid(db)
	for card_id: String in TEXTS:
		var def: CardDef = db.card_by_id(card_id)
		assert_object(def).is_not_null()
		if def != null:
			assert_str(def.text).override_failure_message(card_id).is_equal(TEXTS[card_id])
	var sapling: CardAbility = db.card_by_id("ra02").abilities[0]
	assert_str(sapling.moment).is_equal("on_score")
	assert_int(sapling.amount).is_equal(25)
	assert_int(sapling.cap).is_equal(200)
	assert_str(sapling.scope).is_equal("match")
	var graft: CardAbility = db.card_by_id("ra08").abilities[0]
	assert_int(graft.amount).is_equal(120)
	assert_int(graft.cap).is_equal(250)
	var idler: CardAbility = db.card_by_id("ra06").abilities[0]
	assert_int(idler.amount).is_equal(2)
	assert_int(idler.amount_2).is_equal(50)
	var colossus: CardAbility = db.card_by_id("ra10").abilities[0]
	assert_str(colossus.zone).is_equal("hand")
	assert_int(colossus.amount).is_equal(7)
	assert_int(colossus.amount_2).is_equal(7)
	var layaway: CardAbility = db.card_by_id("ra09").abilities[0]
	assert_str(layaway.zone).is_equal("hand")
	assert_str(db.card_by_id("ev03").abilities[0].scope).is_equal("row")
	assert_str(db.card_by_id("ra01").abilities[0].scope).is_equal("match")
	assert_str(db.card_by_id("ev03").abilities[0].watch).is_equal("self")


func test_a_card_round_trips_through_to_dict() -> void:
	var db: CardDb = CardDb.load_default()
	_assert_valid(db)
	var entries: Array = []
	for def: CardDef in db.cards():
		entries.append(def.to_dict())
	var again: CardDb = _pool_of(entries)
	_assert_valid(again)
	assert_int(again.size()).is_equal(db.size())
	for index: int in range(db.size()):
		assert_dict(again.card_at(index).to_dict()).is_equal(db.card_at(index).to_dict())


# --- Bonus ---------------------------------------------------------------------------


func test_a_mult_of_130_fails_bonus_out_of_range() -> void:
	var entry: Dictionary = _plain()
	entry["bonus"] = {"mult": 130}
	_assert_invalid(_pool_of([entry]), CardDb.ERR_BONUS)
	assert_str(CardDb.ERR_BONUS).is_equal("bonus out of range")


func test_an_add_of_75_fails_bonus_out_of_range() -> void:
	var entry: Dictionary = _plain()
	entry["bonus"] = {"add": 75}
	_assert_invalid(_pool_of([entry]), CardDb.ERR_BONUS)


func test_every_legal_bonus_loads() -> void:
	for mult: int in MatchRules.MULT_VALUES:
		var entry: Dictionary = _plain()
		entry["bonus"] = {"mult": mult}
		var db: CardDb = _pool_of([entry])
		_assert_valid(db)
		assert_int(db.card_at(0).printed_mult()).is_equal(mult)
	for add: int in MatchRules.ADD_VALUES:
		var entry: Dictionary = _plain()
		entry["bonus"] = {"add": add}
		var db: CardDb = _pool_of([entry])
		_assert_valid(db)
		assert_int(db.card_at(0).printed_add()).is_equal(add)
		assert_int(db.card_at(0).printed_mult()).is_equal(MatchRules.BONUS_ONE)


func test_a_bonus_of_the_wrong_shape_fails() -> void:
	for bonus: Variant in [{"x": 125}, {"mult": 125, "add": 25}, 125, {"mult": 1.5}]:
		var entry: Dictionary = _plain()
		entry["bonus"] = bonus
		_assert_invalid(_pool_of([entry]), CardDb.ERR_SHAPE)


# --- Cost and Power -------------------------------------------------------------------


func test_cost_12_without_cost_on_turn_fails() -> void:
	var entry: Dictionary = _plain()
	entry["cost"] = 12
	_assert_invalid(_pool_of([entry]), CardDb.ERR_COST)
	for cost: int in [0, 8]:
		entry["cost"] = cost
		_assert_invalid(_pool_of([entry]), CardDb.ERR_COST)


func test_colossus_passes_with_cost_on_turn() -> void:
	var db: CardDb = CardDb.load_default()
	_assert_valid(db)
	var colossus: CardDef = db.card_by_id("ra10")
	assert_int(colossus.cost).is_equal(12)
	assert_bool(colossus.has_verb(CardAbility.COST_EXCEPTION_VERB)).is_true()
	var entry: Dictionary = colossus.to_dict()
	_assert_valid(_pool_of([entry]))


func test_power_may_be_negative_within_its_range() -> void:
	var entry: Dictionary = _plain()
	entry["power"] = -3
	_assert_valid(_pool_of([entry]))
	entry["power"] = CardDb.MIN_POWER - 1
	_assert_invalid(_pool_of([entry]), CardDb.ERR_POWER)
	entry["power"] = CardDb.MAX_POWER + 1
	_assert_invalid(_pool_of([entry]), CardDb.ERR_POWER)


# --- Abilities ------------------------------------------------------------------------


func test_an_unknown_moment_fails_by_name() -> void:
	_assert_invalid(_pool_of([_with_ability("on_tuesday", "draw", 1)]), CardDb.ERR_MOMENT)
	assert_str(CardDb.ERR_MOMENT).is_equal("unknown moment")


func test_an_unknown_verb_fails_by_name() -> void:
	_assert_invalid(_pool_of([_with_ability("on_reveal", "summon", 1)]), CardDb.ERR_VERB)
	# A v6 verb is no longer known (cycle 9 R63).
	_assert_invalid(_pool_of([_with_ability("on_reveal", "burst", 0)]), CardDb.ERR_VERB)
	assert_str(CardDb.ERR_VERB).is_equal("unknown verb")


func test_draw_on_ongoing_fails_by_name() -> void:
	_assert_invalid(_pool_of([_with_ability("ongoing", "draw", 1)]), CardDb.ERR_PAIR)
	assert_str(CardDb.ERR_PAIR).is_equal("verb not allowed on moment")


## Every verb of the milestone A table loads on each of its moments with an amount in range,
## and fails one past either end of each ranged amount.
func test_every_a_verb_loads_on_its_moments_and_checks_its_amounts() -> void:
	for verb: String in CardAbility.VERBS:
		var entry: Dictionary = CardAbility.VERBS[verb]
		var moments: Array = entry["moments"]
		for raw_moment: Variant in moments:
			var moment: String = raw_moment
			var ability: Dictionary = _ability_in_range(moment, verb)
			var card: Dictionary = _plain()
			card["abilities"] = [ability]
			card["text"] = "Some text."
			if verb == CardAbility.COST_EXCEPTION_VERB:
				card["cost"] = 12
			_assert_valid(_pool_of([card]))
		var first_moment: String = moments[0]
		for key: String in CardAbility.RANGED_KEYS:
			var bounds: Array[int] = CardAbility.range_of(verb, key)
			for wrong: int in [bounds[0] - 1, bounds[1] + 1]:
				var ability: Dictionary = _ability_in_range(first_moment, verb)
				ability[key] = wrong
				var card: Dictionary = _plain()
				card["abilities"] = [ability]
				card["text"] = "Some text."
				_assert_invalid(_pool_of([card]), CardDb.ERR_AMOUNT)


## An ability of `verb` on `moment` with every ranged amount at its low end.
func _ability_in_range(moment: String, verb: String) -> Dictionary:
	var ability: Dictionary = {"moment": moment, "verb": verb, "text": "Some text."}
	for key: String in CardAbility.RANGED_KEYS:
		var bounds: Array[int] = CardAbility.range_of(verb, key)
		if bounds[0] != 0 or bounds[1] != 0:
			ability[key] = bounds[0]
	return ability


func test_a_missing_text_with_an_ability_fails_by_name() -> void:
	var no_card_text: Dictionary = _with_ability("on_reveal", "draw", 1)
	no_card_text["text"] = ""
	_assert_invalid(_pool_of([no_card_text]), CardDb.ERR_TEXT)
	var absent: Dictionary = _with_ability("on_reveal", "draw", 1)
	absent.erase("text")
	_assert_invalid(_pool_of([absent]), CardDb.ERR_TEXT)
	var no_ability_text: Dictionary = _with_ability("on_reveal", "draw", 1)
	var abilities: Array = no_ability_text["abilities"]
	var ability: Dictionary = abilities[0]
	ability.erase("text")
	_assert_invalid(_pool_of([no_ability_text]), CardDb.ERR_TEXT)
	assert_str(CardDb.ERR_TEXT).is_equal("missing text")


func test_unknown_scope_watch_zone_and_bad_uses_fail_by_name() -> void:
	var cases: Array[Array] = [
		["scope", "forever", CardDb.ERR_SCOPE],
		["watch", "everyone", CardDb.ERR_WATCH],
		["zone", "deck", CardDb.ERR_ZONE],
		["uses", -1, CardDb.ERR_USES],
		["uses", 1.5, CardDb.ERR_USES],
	]
	for case: Array in cases:
		var entry: Dictionary = _with_ability("on_reveal", "draw", 1)
		var abilities: Array = entry["abilities"]
		var ability: Dictionary = abilities[0]
		var key: String = case[0]
		ability[key] = case[1]
		var prefix: String = case[2]
		_assert_invalid(_pool_of([entry]), prefix)


# --- File-level checks ----------------------------------------------------------------


func test_a_duplicate_id_fails_by_name() -> void:
	_assert_invalid(_pool_of([_plain(), _plain()]), CardDb.ERR_DUPLICATE)
	assert_str(CardDb.ERR_DUPLICATE).is_equal("duplicate id")


func test_version_4_fails_by_name() -> void:
	_assert_invalid(_pool_of([_plain()], 4), CardDb.ERR_VERSION)
	assert_str(CardDb.ERR_VERSION).is_equal("unsupported version")
	assert_int(CardDb.FORMAT_VERSION).is_equal(5)


func test_an_unknown_tag_fails_by_name() -> void:
	var entry: Dictionary = _plain()
	entry["tag"] = "Greed"
	_assert_invalid(_pool_of([entry]), CardDb.ERR_TAG)
	for tag: String in CardDef.TAGS:
		entry["tag"] = tag
		_assert_valid(_pool_of([entry]))


func test_a_missing_field_or_bad_json_fails() -> void:
	for key: String in ["id", "name", "tag", "cost", "power"]:
		var entry: Dictionary = _plain()
		entry.erase(key)
		_assert_invalid(_pool_of([entry]), CardDb.ERR_SHAPE)
	_assert_invalid(CardDb.from_json("{not json"), CardDb.ERR_JSON)
	_assert_invalid(CardDb.from_json("[]"), CardDb.ERR_SHAPE)
	_assert_invalid(CardDb.from_json('{"version": 5}'), CardDb.ERR_SHAPE)
	_assert_invalid(CardDb.load_from_path("res://no/such/cards.json"), CardDb.ERR_FILE)


## A plain body may leave out its bonus, abilities and text.
func test_optional_keys_take_their_defaults() -> void:
	var entry: Dictionary = {"id": "p", "name": "P", "tag": "evergreen", "cost": 1, "power": 1}
	var db: CardDb = _pool_of([entry])
	_assert_valid(db)
	var def: CardDef = db.card_at(0)
	assert_int(def.bonus_kind).is_equal(CardDef.BonusKind.NONE)
	assert_bool(def.is_plain()).is_true()
	assert_str(def.text).is_empty()


func test_lookups_by_id_and_index() -> void:
	var db: CardDb = CardDb.load_default()
	_assert_valid(db)
	assert_int(db.index_of("ev01")).is_equal(0)
	assert_bool(db.has_id("gr10")).is_true()
	assert_bool(db.has_id("r01")).is_false()
	assert_object(db.card_by_id("nope")).is_null()
	assert_object(db.card_at(-1)).is_null()
	assert_object(db.card_at(db.size())).is_null()
