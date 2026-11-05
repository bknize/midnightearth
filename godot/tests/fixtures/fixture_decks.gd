class_name FixtureDecks
extends RefCounted
## The DC-05 fixture for the suites (DC-07 T02, plan P1, R4): the 20 fixture cards and the
## one-deck list `fixture`, played on both seats. Every suite written before DC-07 runs on
## it, so its instance ids still mean `seat * 20 + index into c01..c20`, and it does not
## depend on the shipped pool or deck list. Not a suite: builders only, nothing cached.
## DC-07 T06 adds the Ruin deck in memory (RUIN_TABLE, ruin_cards(), ruin_decks()), the
## fixture pool and list plus the plan's twenty Ruin rows, until T08 ships them.
## DC-07 T07 adds the Drift deck the same way (DRIFT_TABLE, drift_cards(), drift_decks(),
## drift_defs(), drift_engine()); its pool holds the fixture, Ruin and Drift cards.

const CARDS_PATH: String = "res://tests/fixtures/dc05_cards.json"
const DECKS_PATH: String = "res://tests/fixtures/dc05_decks.json"
const DECK_ID: String = "fixture"
## The fixture card the multi-select suites give sacrifice_destroy in memory (DC-07 T05):
## c02 (cost 1, flat 2, vanilla in the file).
const C02_SACRIFICE: int = 1
const SACRIFICE_TEXT: String = (
	"Destroy any number of your cards: destroy that many enemy cards at random."
)
## The Ruin deck built in memory from the plan's Ruin table (DC-07 T06) until T08 ships it:
## its id, and the definition index (= instance index) of each card in the deck's list.
const RUIN_DECK_ID: String = "ruin"
const RUIN_THEME: String = (
	"Burn your own cards for bodies above the curve and random enemy destroys."
)
const R01_SCRAP: int = 0
const R02_TINDER: int = 1
const R03_EMBER: int = 2
const R04_SHARD: int = 3
const R05_TALLOW: int = 4
const R06_FUSE: int = 5
const R07_RAT: int = 6
const R08_GRAVE_ROBBER: int = 7
const R09_WICK: int = 8
const R10_BUTCHER: int = 9
const R11_CINDER: int = 10
const R12_PYRE: int = 11
const R13_PHOENIX: int = 12
const R14_GLUTTON: int = 13
const R15_WRECK: int = 14
const R16_IMMOLATOR: int = 15
const R17_BONFIRE: int = 16
const R18_REAPER: int = 17
const R19_ASHEN_KING: int = 18
const R20_CATACLYSM: int = 19
## The Drift deck built in memory from the plan's Drift table (DC-07 T07) until T08 ships it:
## its id, and the definition index (= instance index) of each card in the deck's list.
const DRIFT_DECK_ID: String = "drift"
const DRIFT_THEME: String = "Positional bonuses and moving cards on both rows."
const D01_GUST: int = 0
const D02_SPRITE: int = 1
const D03_SCOUT: int = 2
const D04_PEBBLE: int = 3
const D05_EDDY: int = 4
const D06_COURIER: int = 5
const D07_MIRROR: int = 6
const D08_TIDE: int = 7
const D09_SHEPHERD: int = 8
const D10_LODESTONE: int = 9
const D11_CURRENT: int = 10
const D12_HERALD: int = 11
const D13_HOOK: int = 12
const D14_KEEL: int = 13
const D15_UNDERTOW: int = 14
const D16_BEACON: int = 15
const D17_TEMPEST: int = 16
const D18_VANE: int = 17
const D19_MAELSTROM: int = 18
const D20_HORIZON: int = 19
## The plan's Drift table, in RUIN_TABLE's row format.
const DRIFT_TABLE: Array = [
	["d01", "Gust", 1, 2, "", 0, "", "", 0, ""],
	["d02", "Sprite", 1, 1, "x", 125, "", "", 0, ""],
	[
		"d03",
		"Scout",
		1,
		1,
		"x",
		125,
		"on_reveal",
		"move_self_left",
		0,
		"Move to the far left of your row."
	],
	["d04", "Pebble", 1, 3, "", 0, "", "", 0, ""],
	[
		"d05",
		"Eddy",
		2,
		1,
		"",
		0,
		"on_moved",
		"plus_on_moved",
		2,
		"When this card is moved, +2 until the walk ends."
	],
	[
		"d06",
		"Courier",
		2,
		2,
		"x",
		125,
		"on_reveal",
		"move_self_right",
		0,
		"Move to the far right of your row."
	],
	[
		"d07",
		"Mirror",
		2,
		0,
		"",
		0,
		"on_reveal",
		"copy_stats",
		0,
		"Copy an enemy card's current flat and bonus."
	],
	["d08", "Tide", 2, 3, "x", 125, "", "", 0, ""],
	[
		"d09",
		"Shepherd",
		3,
		3,
		"",
		0,
		"on_reveal",
		"swap_places",
		0,
		"Swap places with a card on your row."
	],
	[
		"d10",
		"Lodestone",
		3,
		2,
		"",
		0,
		"ongoing",
		"neighbour_times",
		125,
		"The cards on either side of this one get ×1.25."
	],
	["d11", "Current", 3, 4, "x", 125, "", "", 0, ""],
	[
		"d12",
		"Herald",
		4,
		3,
		"",
		0,
		"ongoing",
		"edge_left_times",
		150,
		"While this card is on the far left of your row, it has ×1.5."
	],
	[
		"d13",
		"Hook",
		4,
		4,
		"",
		0,
		"on_reveal",
		"move_opponent_left",
		0,
		"Move an enemy card to the far left of its row."
	],
	["d14", "Keel", 4, 5, "x", 125, "", "", 0, ""],
	[
		"d15",
		"Undertow",
		5,
		4,
		"",
		0,
		"on_reveal",
		"shift_own_left",
		0,
		"Move each of your other cards one slot left; the leftmost goes to the far right."
	],
	["d16", "Beacon", 5, 5, "x", 150, "", "", 0, ""],
	[
		"d17",
		"Tempest",
		6,
		5,
		"",
		0,
		"on_reveal",
		"reverse_opponent_row",
		0,
		"Reverse the order of the enemy row."
	],
	["d18", "Vane", 6, 3, "plus", 1, "", "", 0, ""],
	[
		"d19",
		"Maelstrom",
		7,
		6,
		"",
		0,
		"on_reveal",
		"swap_opponent_right",
		0,
		"Swap an enemy card with the card to its right."
	],
	["d20", "Horizon", 7, 7, "x", 200, "", "", 0, ""],
]
## The plan's Ruin table, one row per card in deck order: [id, name, cost, flat, bonus key
## ("x", "plus" or "" for none), bonus amount, trigger ("" for vanilla), verb, amount, text].
const RUIN_TABLE: Array = [
	["r01", "Scrap", 1, 2, "", 0, "", "", 0, ""],
	["r02", "Tinder", 1, 1, "x", 125, "", "", 0, ""],
	["r03", "Ember", 1, 4, "", 0, "on_reveal", "discard_own", 1, "Discard a card from your hand."],
	["r04", "Shard", 1, 0, "x", 150, "", "", 0, ""],
	[
		"r05",
		"Tallow",
		1,
		5,
		"",
		0,
		"on_reveal",
		"destroy_leftmost_own",
		0,
		"Destroy your leftmost other card."
	],
	[
		"r06",
		"Fuse",
		2,
		1,
		"",
		0,
		"on_opponent_score",
		"burst",
		0,
		"Whenever an enemy card scores, +1 flat. At 5 flat, destroy this and a random enemy card."
	],
	[
		"r07",
		"Rat",
		2,
		1,
		"",
		0,
		"on_opponent_reveal",
		"draw",
		1,
		"Whenever an enemy card reveals, draw a card."
	],
	[
		"r08",
		"Grave Robber",
		2,
		2,
		"",
		0,
		"on_reveal",
		"recover_destroyed",
		0,
		"Put a destroyed card into your hand."
	],
	["r09", "Wick", 2, 3, "x", 125, "", "", 0, ""],
	[
		"r10",
		"Butcher",
		3,
		3,
		"",
		0,
		"on_reveal",
		"destroy_own_then_draw",
		2,
		"Destroy another card of yours: draw 2."
	],
	["r11", "Cinder", 3, 7, "", 0, "on_reveal", "discard_own", 1, "Discard a card from your hand."],
	["r12", "Pyre", 3, 2, "x", 150, "", "", 0, ""],
	[
		"r13",
		"Phoenix",
		4,
		3,
		"x",
		125,
		"ongoing",
		"unreveal_instead",
		0,
		"If this card would be destroyed, un-reveal it instead."
	],
	[
		"r14",
		"Glutton",
		4,
		2,
		"",
		0,
		"on_reveal",
		"destroy_own_then_flat_up",
		0,
		"Destroy another card of yours: gain its flat."
	],
	["r15", "Wreck", 4, 5, "x", 125, "", "", 0, ""],
	[
		"r16",
		"Immolator",
		5,
		4,
		"",
		0,
		"on_reveal",
		"sacrifice_destroy",
		0,
		"Destroy any number of your cards: destroy that many enemy cards at random."
	],
	["r17", "Bonfire", 5, 5, "x", 150, "", "", 0, ""],
	[
		"r18",
		"Reaper",
		6,
		6,
		"",
		0,
		"on_reveal",
		"destroy_random_opponent",
		0,
		"Destroy a random enemy card."
	],
	["r19", "Ashen King", 6, 4, "plus", 1, "", "", 0, ""],
	[
		"r20",
		"Cataclysm",
		7,
		11,
		"",
		0,
		"on_reveal",
		"destroy_leftmost_own",
		0,
		"Destroy your leftmost other card."
	],
]


## The fixture pool (format 3).
static func cards() -> CardDb:
	return CardDb.load_from_path(CARDS_PATH)


## The fixture deck list: the single deck `fixture`, c01..c20 in order.
static func decks() -> DeckList:
	return DeckList.load_from_path(DECKS_PATH)


## The Crew pool the fixture decks name their Crew from (DC-11 T08, cycle 8 P12): the
## shipped pool, the only one there is until a frozen Crew fixture lands. The fixture deck
## lists navigator, gardener and lookout; the in-memory Ruin and Drift decks the plan's.
## Its Crew do not fire (CrewPool.fires cleared, DC-11 T10): the suites built on it were
## pinned before the Crew, and their matches and replays keep those pins. The Crew still
## stand in MATCH_STARTED, the views and crew_uses. test_crew_effects.gd builds on
## live_crew() instead.
static func crew() -> CrewPool:
	var pool: CrewPool = CrewPool.load_default()
	pool.fires = false
	return pool


## The shipped Crew pool with its Crew firing (DC-11 T10), for the suites that test them.
static func live_crew() -> CrewPool:
	return CrewPool.load_default()


## The fixture deck on both seats.
static func ids() -> Array[String]:
	var out: Array[String] = [DECK_ID, DECK_ID]
	return out


## A match on `match_seed` with the fixture deck on both seats over `pool` (the fixture
## pool, or a suite's edited copy of it holding the same ids).
static func engine(match_seed: int, pool: CardDb) -> MatchEngine:
	return MatchEngine.create(match_seed, pool, decks(), ids(), crew())


## The definitions of a fixture-vs-fixture match over `pool`, for the engine modules that
## take MatchCards (ScoreWalk, EffectResolver, LegalPlays, SeatView, GreedyBot).
static func defs(pool: CardDb) -> MatchCards:
	return MatchCards.build(pool, decks(), ids(), crew())


## The fixture pool with definition `index` given the effect {trigger, verb, amount 0,
## text} (in-memory JSON), for a verb no fixture card carries; null if the file is unread.
static func cards_with_effect(index: int, trigger: String, verb: String, text: String) -> CardDb:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CARDS_PATH))
	if not parsed is Dictionary:
		return null
	var root: Dictionary = parsed
	var entries: Array = root["cards"]
	var entry: Dictionary = entries[index]
	entry["effect"] = {"trigger": trigger, "verb": verb, "amount": 0, "text": text}
	return CardDb.from_json(JSON.stringify(root))


## The fixture pool with c02 carrying an on-reveal sacrifice_destroy (DC-07 T05, P12).
static func sacrifice_cards() -> CardDb:
	return cards_with_effect(C02_SACRIFICE, "on_reveal", "sacrifice_destroy", SACRIFICE_TEXT)


## RUIN_TABLE as format-3 pool entries, in deck order (DC-07 T06; T08 ships the same rows).
static func ruin_entries() -> Array:
	return table_entries(RUIN_TABLE)


## A table in RUIN_TABLE's row format as format-3 pool entries, in deck order.
static func table_entries(table: Array) -> Array:
	var out: Array = []
	for raw: Variant in table:
		var row: Array = raw
		var bonus_key: String = row[4]
		var bonus: Variant = null
		if bonus_key != "":
			bonus = {bonus_key: row[5]}
		var trigger: String = row[6]
		var effect: Variant = null
		if trigger != "":
			effect = {"trigger": trigger, "verb": row[7], "amount": row[8], "text": row[9]}
		var entry: Dictionary = {
			"id": row[0],
			"name": row[1],
			"cost": row[2],
			"flat": row[3],
			"bonus": bonus,
			"effect": effect,
		}
		out.append(entry)
	return out


## The ids of RUIN_TABLE, in deck order.
static func ruin_card_ids() -> Array:
	return table_ids(RUIN_TABLE)


## The ids of a table in RUIN_TABLE's row format, in deck order.
static func table_ids(table: Array) -> Array:
	var out: Array = []
	for raw: Variant in table:
		var row: Array = raw
		out.append(row[0])
	return out


## The fixture pool with the twenty Ruin cards added (in-memory JSON); null if the file is
## unread.
static func ruin_cards() -> CardDb:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CARDS_PATH))
	if not parsed is Dictionary:
		return null
	var root: Dictionary = parsed
	var entries: Array = root["cards"]
	entries.append_array(ruin_entries())
	return CardDb.from_json(JSON.stringify(root))


## The fixture deck list with the Ruin deck added (in-memory JSON); null if the file is
## unread.
static func ruin_decks() -> DeckList:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DECKS_PATH))
	if not parsed is Dictionary:
		return null
	var root: Dictionary = parsed
	var listed: Array = root["decks"]
	listed.append(ruin_deck())
	return DeckList.from_json(JSON.stringify(root))


## The in-memory Ruin deck entry, with the plan's three Crew (cycle 8 P12).
static func ruin_deck() -> Dictionary:
	return {
		"id": RUIN_DECK_ID,
		"name": "Ruin",
		"theme": RUIN_THEME,
		"cards": ruin_card_ids(),
		"crew": ["salvager", "veil", "quartermaster"],
	}


## The Ruin deck on both seats.
static func ruin_ids() -> Array[String]:
	var out: Array[String] = [RUIN_DECK_ID, RUIN_DECK_ID]
	return out


## The definitions of a Ruin-vs-Ruin match: instance id = seat * 20 + the R* index.
static func ruin_defs() -> MatchCards:
	return MatchCards.build(ruin_cards(), ruin_decks(), ruin_ids(), crew())


## A Ruin-vs-Ruin match on `match_seed` (not started).
static func ruin_engine(match_seed: int) -> MatchEngine:
	return MatchEngine.create(match_seed, ruin_cards(), ruin_decks(), ruin_ids(), crew())


## Sets both rows of the started `engine` by hand (`own` for seat 0, `theirs` for seat 1;
## instance ids, face down), taking each card out of its seat's deck, hand and burn pile
## (the suites' table shortcut, as test_destroyed_piles.gd), then both seats pass: the walk
## runs to its end or to its first prompt. False when a pass is rejected.
static func play_table(engine: MatchEngine, own: Array[int], theirs: Array[int]) -> bool:
	for seat: int in range(MatchEngine.SEATS):
		var row: Array[int] = []
		if seat == 0:
			row.assign(own)
		else:
			row.assign(theirs)
		var piles: MatchState.SeatPiles = engine._state.seats[seat]
		for card: int in row:
			piles.deck.erase(card)
			piles.hand.erase(card)
			piles.burned.erase(card)
		piles.board.assign(row)
	var none: Array[int] = []
	for _step: int in range(MatchEngine.SEATS):
		if not engine.apply(EngineAction.commit(engine.awaited_seat(), none)).ok:
			return false
	return true


## The fixture pool with the twenty Ruin and twenty Drift cards added (in-memory JSON); null
## if the file is unread.
static func drift_cards() -> CardDb:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CARDS_PATH))
	if not parsed is Dictionary:
		return null
	var root: Dictionary = parsed
	var entries: Array = root["cards"]
	entries.append_array(ruin_entries())
	entries.append_array(table_entries(DRIFT_TABLE))
	return CardDb.from_json(JSON.stringify(root))


## The fixture deck list with the Ruin and Drift decks added (in-memory JSON); null if the
## file is unread.
static func drift_decks() -> DeckList:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DECKS_PATH))
	if not parsed is Dictionary:
		return null
	var root: Dictionary = parsed
	var listed: Array = root["decks"]
	listed.append(ruin_deck())
	var drift: Dictionary = {
		"id": DRIFT_DECK_ID,
		"name": "Drift",
		"theme": DRIFT_THEME,
		"cards": table_ids(DRIFT_TABLE),
		"crew": ["navigator", "veil", "tallyman"],
	}
	listed.append(drift)
	return DeckList.from_json(JSON.stringify(root))


## The Drift deck on both seats.
static func drift_ids() -> Array[String]:
	var out: Array[String] = [DRIFT_DECK_ID, DRIFT_DECK_ID]
	return out


## The definitions of a Drift-vs-Drift match: instance id = seat * 20 + the D* index.
static func drift_defs() -> MatchCards:
	return MatchCards.build(drift_cards(), drift_decks(), drift_ids(), crew())


## A Drift-vs-Drift match on `match_seed` (not started).
static func drift_engine(match_seed: int) -> MatchEngine:
	return MatchEngine.create(match_seed, drift_cards(), drift_decks(), drift_ids(), crew())
