class_name TestDecks
extends GdUnitTestSuite
## The shipped decks (DC-07 T08; R4, C7, plan P1, P2 and the Ruin and Drift tables): the
## shipped pool holds exactly the forty Ruin and Drift cards and the shipped list exactly
## the decks `ruin` and `drift`, each of 20 distinct ids; their cost curves are
## 5-4-3-3-2-2-1 and 4-4-3-3-2-2-2 (cards at cost 1, 2, ... 7); every card's id, cost,
## flat, bonus and effect are the plan's, asserted by list (no parse of plan.md); every
## trigger and verb the pool carries is one the engine resolves. The DC-05 cards live only
## under tests/fixtures (R4), so neither file names them.
## Cycle 8 (DC-09 T04; R9, R10, plan Data model): the pool gains the forty Bloom and Echo
## cards and the list the decks `bloom` and `echo` (curves 4-4-3-3-2-2-2), every row, name,
## `uses` and rules text the plan's tables give.

const RUIN: String = "ruin"
const DRIFT: String = "drift"
const BLOOM: String = "bloom"
const ECHO: String = "echo"
## The shipped deck ids, in the list's order.
const SHIPPED: Array[String] = [RUIN, DRIFT, BLOOM, ECHO]
const RUIN_THEME: String = (
	"Burn your own cards for bodies above the curve and random enemy destroys."
)
const DRIFT_THEME: String = "Positional bonuses and moving cards on both rows."
const BLOOM_THEME: String = "Grow your cards for good: bonuses that stay for the match."
const ECHO_THEME: String = "Replay your reveals: returns, flips and cards that remember."
const RUIN_CURVE: Array[int] = [5, 4, 3, 3, 2, 2, 1]
const DRIFT_CURVE: Array[int] = [4, 4, 3, 3, 2, 2, 2]
const BLOOM_CURVE: Array[int] = [4, 4, 3, 3, 2, 2, 2]
const ECHO_CURVE: Array[int] = [4, 4, 3, 3, 2, 2, 2]

## The plan's Ruin table, one row per card in deck order: id, cost, flat, bonus ("" for
## none, "x125" for a ×1.25, "plus1" for a +1) and effect ("" for vanilla, else
## "trigger verb amount", then " uses<n>" when the effect is limited, format 4).
const RUIN_ROWS: Array[String] = [
	"r01 1 2 - -",
	"r02 1 1 x125 -",
	"r03 1 4 - on_reveal discard_own 1",
	"r04 1 0 x150 -",
	"r05 1 5 - on_reveal destroy_leftmost_own 0",
	"r06 2 1 - on_opponent_score burst 0",
	"r07 2 1 - on_opponent_reveal draw 1",
	"r08 2 2 - on_reveal recover_destroyed 0",
	"r09 2 3 x125 -",
	"r10 3 3 - on_reveal destroy_own_then_draw 2",
	"r11 3 7 - on_reveal discard_own 1",
	"r12 3 2 x150 -",
	"r13 4 3 x125 ongoing unreveal_instead 0",
	"r14 4 2 - on_reveal destroy_own_then_flat_up 0",
	"r15 4 5 x125 -",
	"r16 5 4 - on_reveal sacrifice_destroy 0",
	"r17 5 5 x150 -",
	"r18 6 6 - on_reveal destroy_random_opponent 0",
	"r19 6 4 plus1 -",
	"r20 7 11 - on_reveal destroy_leftmost_own 0",
]
## The plan's Drift table, in RUIN_ROWS' format.
const DRIFT_ROWS: Array[String] = [
	"d01 1 2 - -",
	"d02 1 1 x125 -",
	"d03 1 1 x125 on_reveal move_self_left 0",
	"d04 1 3 - -",
	"d05 2 1 - on_moved plus_on_moved 2",
	"d06 2 2 x125 on_reveal move_self_right 0",
	"d07 2 0 - on_reveal copy_stats 0",
	"d08 2 3 x125 -",
	"d09 3 3 - on_reveal swap_places 0",
	"d10 3 2 - ongoing neighbour_times 125",
	"d11 3 4 x125 -",
	"d12 4 3 - ongoing edge_left_times 150",
	"d13 4 4 - on_reveal move_opponent_left 0",
	"d14 4 5 x125 -",
	"d15 5 4 - on_reveal shift_own_left 0",
	"d16 5 5 x150 -",
	"d17 6 5 - on_reveal reverse_opponent_row 0",
	"d18 6 3 plus1 -",
	"d19 7 6 - on_reveal swap_opponent_right 0",
	"d20 7 7 x200 -",
]
## The plan's Bloom table (cycle 8), in RUIN_ROWS' format.
const BLOOM_ROWS: Array[String] = [
	"b01 1 1 - on_score grow_self_flat 1",
	"b02 1 2 - -",
	"b03 1 1 x125 -",
	"b04 1 3 - -",
	"b05 2 1 - on_score grow_self_times 25",
	"b06 2 2 - on_reveal grow_other_flat 1",
	"b07 2 3 x125 -",
	"b08 2 1 - on_reveal grow_hand_flat 1",
	"b09 3 2 - on_reveal grow_hand_one_times 25",
	"b10 3 4 x125 -",
	"b11 3 2 - on_reveal grow_row_flat 1",
	"b12 4 3 - on_score grow_self_plus 1",
	"b13 4 3 x150 -",
	"b14 4 5 - on_reveal draw 1",
	"b15 5 4 - on_score grow_self_times_once 50 uses1",
	"b16 5 5 x125 -",
	"b17 6 6 - on_reveal grow_hand_flat 2",
	"b18 6 4 plus1 -",
	"b19 7 7 x150 -",
	"b20 7 5 - on_reveal grow_row_times 25",
]
## The plan's Echo table (cycle 8), in RUIN_ROWS' format.
const ECHO_ROWS: Array[String] = [
	"e01 1 1 - on_reveal grow_self_flat 1",
	"e02 1 2 - -",
	"e03 1 1 x125 on_reveal return_self_at_turn_end 0",
	"e04 1 3 - -",
	"e05 2 2 - ongoing unreveal_at_turn_end 0",
	"e06 2 1 - on_ally_reveal ally_reveal_flat 1",
	"e07 2 3 x125 -",
	"e08 2 2 - on_reveal draw_once 2 uses1",
	"e09 3 3 - on_reveal cost_down_right 1",
	"e10 3 2 - on_reveal return_own_at_turn_end 0",
	"e11 3 4 x125 -",
	"e12 4 3 - on_reveal return_opponent_at_turn_end 0",
	"e13 4 4 - on_reveal free_first_next_turn 0",
	"e14 4 5 x125 -",
	"e15 5 3 - on_ally_reveal draw 1",
	"e16 5 5 x150 -",
	"e17 6 5 - on_reveal cost_down_self 2",
	"e18 6 3 plus1 -",
	"e19 7 10 - on_reveal return_self_at_turn_end 0",
	"e20 7 7 x200 -",
]
## The names, in deck order (the plan's tables).
const RUIN_NAMES: Array[String] = [
	"Scrap",
	"Tinder",
	"Ember",
	"Shard",
	"Tallow",
	"Fuse",
	"Rat",
	"Grave Robber",
	"Wick",
	"Butcher",
	"Cinder",
	"Pyre",
	"Phoenix",
	"Glutton",
	"Wreck",
	"Immolator",
	"Bonfire",
	"Reaper",
	"Ashen King",
	"Cataclysm",
]
const DRIFT_NAMES: Array[String] = [
	"Gust",
	"Sprite",
	"Scout",
	"Pebble",
	"Eddy",
	"Courier",
	"Mirror",
	"Tide",
	"Shepherd",
	"Lodestone",
	"Current",
	"Herald",
	"Hook",
	"Keel",
	"Undertow",
	"Beacon",
	"Tempest",
	"Vane",
	"Maelstrom",
	"Horizon",
]
const BLOOM_NAMES: Array[String] = [
	"Seed",
	"Sprout",
	"Acorn",
	"Moss",
	"Sapling",
	"Tiller",
	"Bramble",
	"Rain",
	"Vine",
	"Trunk",
	"Orchard",
	"Grove",
	"Elder",
	"Harvest",
	"Oak",
	"Canopy",
	"Redwood",
	"Bloom",
	"Ancient",
	"World Tree",
]
const ECHO_NAMES: Array[String] = [
	"Whisper",
	"Spark",
	"Flicker",
	"Glint",
	"Echo",
	"Refrain",
	"Ripple",
	"Messenger",
	"Tinker",
	"Recall",
	"Chime",
	"Banish",
	"Lantern",
	"Mirage",
	"Relay",
	"Signal",
	"Reverb",
	"Resonance",
	"Encore",
	"Eternity",
]
## The rules text of every Bloom and Echo effect card, by id (the plan's tables).
const NEW_TEXTS: Dictionary[String, String] = {
	"b01": "Whenever this scores, +1 flat for the match.",
	"b05": "Whenever this scores, ×+0.25 for the match.",
	"b06": "Another card of yours gets +1 flat for the match.",
	"b08": "Each card in your hand gets +1 flat for the match.",
	"b09": "A card in your hand gets ×+0.25 for the match.",
	"b11": "Each other card on your row gets +1 flat for the match.",
	"b12": "Whenever this scores, its +bonus grows by 1 for the match.",
	"b14": "Draw a card.",
	"b15": "Once per match, when this scores: ×+0.5 for the match.",
	"b17": "Each card in your hand gets +2 flat for the match.",
	"b20": "Each other card on your row gets ×+0.25 for the match.",
	"e01": "Whenever this reveals, +1 flat for the match.",
	"e03": "Returns to your hand at the end of the turn.",
	"e05": "At the end of the turn, this card flips face down.",
	"e06": "Whenever another card of yours reveals, +1 flat this round.",
	"e08": "The first time this reveals each match, draw 2.",
	"e09": "The card to the right of this one costs 1 less for the match.",
	"e10": "Another card of yours returns to your hand at the end of the turn.",
	"e12": "An enemy card returns to its owner's hand at the end of the turn.",
	"e13": "Next turn, your first card is free.",
	"e15": "Whenever another card of yours reveals, draw a card.",
	"e17": "This card costs 2 less for the match.",
	"e19": "Returns to your hand at the end of the turn.",
}
## The verbs the engine resolves (DC-07 P8): EffectResolver.apply and apply_choice dispatch
## them, ScoreWalk.effective reads the two ongoing ×-verbs and EffectResolver.destroy the
## un-reveal. SWITCH_STATS is gone (C20).
const HANDLED_VERBS: Array[String] = [
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
	# DC-09 T02: the Bloom grow verbs (cycle 8 P4), BloomEffects' via EffectResolver.
	"grow_self_flat",
	"grow_self_times",
	"grow_self_plus",
	"grow_self_times_once",
	"grow_other_flat",
	"grow_hand_flat",
	"grow_hand_one_times",
	"grow_row_flat",
	"grow_row_times",
	# DC-09 T03: the Echo verbs (cycle 8 P6), EchoEffects' via EffectResolver.
	"return_self_at_turn_end",
	"return_own_at_turn_end",
	"return_opponent_at_turn_end",
	"unreveal_at_turn_end",
	"cost_down_right",
	"cost_down_self",
	"draw_once",
	"ally_reveal_flat",
]
## The cycle 8 verbs known to the loader but not yet resolved: none since DC-09 T03 (the
## Bloom grow verbs moved to HANDLED_VERBS with T02, the Echo verbs with T03).
const PENDING_VERBS: Array[String] = []
## The engine sources that resolve a verb: each shipped verb's enum name appears in one.
const RESOLVER_SOURCES: Array[String] = [
	"res://engine/effect_resolver.gd",
	"res://engine/ruin_effects.gd",
	"res://engine/drift_effects.gd",
	"res://engine/bloom_effects.gd",
	"res://engine/echo_effects.gd",
	"res://engine/score_walk.gd",
]

var _cached_cards: CardDb = null
var _cached_decks: DeckList = null

# --- Helpers --------------------------------------------------------------------------


func _cards() -> CardDb:
	if _cached_cards == null:
		_cached_cards = CardDb.load_default()
	return _cached_cards


func _decks() -> DeckList:
	if _cached_decks == null:
		_cached_decks = DeckList.load_default()
	return _cached_decks


## The definitions of `deck_id`'s cards, in deck order (nulls for ids the pool lacks).
func _defs_of(deck_id: String) -> Array[CardDef]:
	var out: Array[CardDef] = []
	for card_id: String in _decks().card_ids(deck_id):
		out.append(_cards().card_by_id(card_id))
	return out


## A definition in a table row's format (see RUIN_ROWS).
func _row_of(def: CardDef) -> String:
	var bonus: String = "-"
	if def.bonus_kind == CardDef.BonusKind.TIMES:
		bonus = "x%d" % def.bonus
	elif def.bonus_kind == CardDef.BonusKind.PLUS:
		bonus = "plus%d" % def.bonus
	var effect: String = "-"
	if def.effect != null:
		effect = (
			"%s %s %d"
			% [
				CardEffect.trigger_name(def.effect.trigger),
				CardEffect.verb_name(def.effect.verb),
				def.effect.amount
			]
		)
		if def.effect.uses > 0:
			effect += " uses%d" % def.effect.uses
	return "%s %d %d %s %s" % [def.id, def.cost, def.flat, bonus, effect]


## Cards per cost 1..7 of `deck_id`.
func _curve(deck_id: String) -> Array[int]:
	var out: Array[int] = [0, 0, 0, 0, 0, 0, 0]
	for def: CardDef in _defs_of(deck_id):
		if def == null or def.cost < 1 or def.cost > out.size():
			fail("%s holds a card with no cost in 1..7" % deck_id)
			continue
		out[def.cost - 1] += 1
	return out


func _assert_deck(deck_id: String, deck_name: String, theme: String) -> void:
	var deck: Dictionary = _decks().deck(deck_id)
	var shown_id: String = deck.get("id", "")
	var shown_name: String = deck.get("name", "")
	var shown_theme: String = deck.get("theme", "")
	assert_str(shown_id).is_equal(deck_id)
	assert_str(shown_name).is_equal(deck_name)
	assert_str(shown_theme).is_equal(theme)
	var ids: Array[String] = _decks().card_ids(deck_id)
	assert_int(ids.size()).is_equal(MatchRules.DECK_SIZE)
	var distinct: Dictionary[String, bool] = {}
	for card_id: String in ids:
		distinct[card_id] = true
		assert_bool(_cards().has_id(card_id)).override_failure_message(card_id).is_true()
	assert_int(distinct.size()).is_equal(MatchRules.DECK_SIZE)


# --- Loading --------------------------------------------------------------------------


## Both shipped files load, the list validates against the pool, and it holds exactly
## `ruin`, `drift`, `bloom` and `echo` (cycle 8 R10), each 20 distinct ids of the pool,
## with the plan's names and themes.
func test_both_decks_load_with_twenty_distinct_ids() -> void:
	assert_bool(_cards().is_valid()).override_failure_message(_cards().load_error()).is_true()
	assert_bool(_decks().is_valid()).override_failure_message(_decks().load_error()).is_true()
	assert_str(_decks().validate(_cards())).is_empty()
	assert_array(_decks().ids()).is_equal(SHIPPED)
	_assert_deck(RUIN, "Ruin", RUIN_THEME)
	_assert_deck(DRIFT, "Drift", DRIFT_THEME)
	_assert_deck(BLOOM, "Bloom", BLOOM_THEME)
	_assert_deck(ECHO, "Echo", ECHO_THEME)
	# The four decks share no card, so the pool is exactly their eighty.
	var all_ids: Dictionary[String, bool] = {}
	for deck_id: String in SHIPPED:
		for card_id: String in _decks().card_ids(deck_id):
			all_ids[card_id] = true
	assert_int(all_ids.size()).is_equal(SHIPPED.size() * MatchRules.DECK_SIZE)
	assert_int(_cards().size()).is_equal(SHIPPED.size() * MatchRules.DECK_SIZE)


## R4, P1: the DC-05 cards and the `fixture` deck are test fixtures only.
func test_the_fixture_is_not_shipped() -> void:
	assert_bool(_decks().has_deck(FixtureDecks.DECK_ID)).is_false()
	for i: int in range(MatchRules.DECK_SIZE):
		var card_id: String = "c%02d" % (i + 1)
		assert_bool(_cards().has_id(card_id)).override_failure_message(card_id).is_false()


## Every deck can be played: a match on each of the sixteen pairings starts.
func test_every_pairing_starts() -> void:
	for first: String in SHIPPED:
		for second: String in SHIPPED:
			var pair: Array[String] = [first, second]
			var engine: MatchEngine = MatchEngine.create(1, _cards(), _decks(), pair)
			var result: ApplyResult = engine.start()
			assert_bool(result.ok).override_failure_message("%s/%s" % [first, second]).is_true()
			assert_array(engine.deck_ids()).is_equal(pair)


# --- The plan's tables ----------------------------------------------------------------


## The cost curves, as cards at cost 1, 2, ... 7.
func test_cost_curves() -> void:
	assert_array(_curve(RUIN)).is_equal(RUIN_CURVE)
	assert_array(_curve(DRIFT)).is_equal(DRIFT_CURVE)
	assert_array(_curve(BLOOM)).is_equal(BLOOM_CURVE)
	assert_array(_curve(ECHO)).is_equal(ECHO_CURVE)


## Every card's id, cost, flat, bonus and effect (with its `uses`), and its name, in deck
## order.
func test_ids_costs_bonuses_and_verbs_by_list() -> void:
	var tables: Dictionary[String, Array] = {
		RUIN: RUIN_ROWS, DRIFT: DRIFT_ROWS, BLOOM: BLOOM_ROWS, ECHO: ECHO_ROWS
	}
	var names: Dictionary[String, Array] = {
		RUIN: RUIN_NAMES, DRIFT: DRIFT_NAMES, BLOOM: BLOOM_NAMES, ECHO: ECHO_NAMES
	}
	for deck_id: String in tables.keys():
		var rows: Array = tables[deck_id]
		var deck_names: Array = names[deck_id]
		var defs: Array[CardDef] = _defs_of(deck_id)
		assert_int(defs.size()).is_equal(rows.size())
		for index: int in range(mini(defs.size(), rows.size())):
			var def: CardDef = defs[index]
			var row: String = rows[index]
			var expected_name: String = deck_names[index]
			assert_object(def).override_failure_message(row).is_not_null()
			if def == null:
				continue
			assert_str(_row_of(def)).is_equal(row)
			assert_str(def.name).is_equal(expected_name)
			# Rules text is present exactly when the card carries an effect.
			if def.effect != null:
				assert_str(def.effect.text).override_failure_message(row).is_not_empty()


## Cycle 8: every Bloom and Echo card's rules text is the plan's, word for word, and a
## vanilla card of those decks carries no effect.
func test_bloom_and_echo_texts_by_list() -> void:
	var seen: int = 0
	for deck_id: String in [BLOOM, ECHO]:
		for def: CardDef in _defs_of(deck_id):
			if def == null:
				fail("%s holds an id the pool lacks" % deck_id)
				continue
			var want: String = NEW_TEXTS.get(def.id, "")
			if want == "":
				assert_object(def.effect).override_failure_message(def.id).is_null()
				continue
			assert_object(def.effect).override_failure_message(def.id).is_not_null()
			if def.effect != null:
				assert_str(def.effect.text).override_failure_message(def.id).is_equal(want)
				seen += 1
	assert_int(seen).is_equal(NEW_TEXTS.size())


## The bonus mix of each deck (the plan's notes under the tables): Ruin ×1.25 on four, ×1.5
## on three, +1 on one; Drift ×1.25 on six, ×1.5 on one, ×2 on one, +1 on one; Bloom ×1.25
## on four, ×1.5 on two, +1 on one; Echo ×1.25 on four, ×1.5 on one, ×2 on one, +1 on one.
## Twelve, eleven, eleven and twelve effect cards.
func test_bonus_and_effect_mix() -> void:
	var expected: Dictionary[String, Dictionary] = {
		RUIN: {"x125": 4, "x150": 3, "x200": 0, "plus1": 1, "effects": 12},
		DRIFT: {"x125": 6, "x150": 1, "x200": 1, "plus1": 1, "effects": 11},
		BLOOM: {"x125": 4, "x150": 2, "x200": 0, "plus1": 1, "effects": 11},
		ECHO: {"x125": 4, "x150": 1, "x200": 1, "plus1": 1, "effects": 12},
	}
	for deck_id: String in expected.keys():
		var counts: Dictionary[String, int] = {
			"x125": 0, "x150": 0, "x200": 0, "plus1": 0, "effects": 0
		}
		for def: CardDef in _defs_of(deck_id):
			if def == null:
				continue
			var key: String = ""
			if def.bonus_kind == CardDef.BonusKind.TIMES:
				key = "x%d" % def.bonus
			elif def.bonus_kind == CardDef.BonusKind.PLUS:
				key = "plus%d" % def.bonus
			if key != "":
				counts[key] = counts.get(key, 0) + 1
			if def.effect != null:
				counts["effects"] += 1
		var want: Dictionary = expected[deck_id]
		assert_int(counts.size()).override_failure_message(str(counts)).is_equal(want.size())
		for bucket: String in counts.keys():
			var have: int = counts[bucket]
			var wanted: int = want.get(bucket, -1)
			var label: String = "%s %s" % [deck_id, bucket]
			assert_int(have).override_failure_message(label).is_equal(wanted)


# --- Every verb is resolved -----------------------------------------------------------


## Every effect in the shipped pool has a known trigger and a verb the engine resolves: one
## of HANDLED_VERBS, whose enum name the resolver sources dispatch on.
func test_every_verb_in_the_pool_is_one_the_resolver_handles() -> void:
	var sources: String = ""
	for path: String in RESOLVER_SOURCES:
		var text: String = FileAccess.get_file_as_string(path)
		assert_str(text).override_failure_message(path).is_not_empty()
		sources += text
	var verb_keys: Array = CardEffect.Verb.keys()
	var effects: int = 0
	for def: CardDef in _cards().cards():
		if def.effect == null:
			continue
		effects += 1
		var verb: String = CardEffect.verb_name(def.effect.verb)
		var trigger: String = CardEffect.trigger_name(def.effect.trigger)
		assert_str(trigger).override_failure_message(def.id).is_not_empty()
		assert_bool(HANDLED_VERBS.has(verb)).override_failure_message(def.id).is_true()
		var key: String = verb_keys[def.effect.verb]
		var token: String = "CardEffect.Verb.%s" % key
		assert_bool(sources.contains(token)).override_failure_message(token).is_true()
	# Ruin 12 + Drift 11 + Bloom 11 + Echo 12.
	assert_int(effects).is_equal(46)
	# HANDLED_VERBS and the pending cycle 8 verbs are the engine's whole verb list (no
	# retired verb lingers in the enum).
	var all_names: Array[String] = []
	all_names.assign(CardEffect.VERB_NAMES)
	var known: Array[String] = []
	known.append_array(HANDLED_VERBS)
	known.append_array(PENDING_VERBS)
	assert_array(all_names).is_equal(known)
