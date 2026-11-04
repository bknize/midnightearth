class_name FixtureDecks
extends RefCounted
## The DC-05 fixture for the suites (DC-07 T02, plan P1, R4): the 20 fixture cards and the
## one-deck list `fixture`, played on both seats. Every suite written before DC-07 runs on
## it, so its instance ids still mean `seat * 20 + index into c01..c20`, and it does not
## depend on the shipped pool or deck list. Not a suite: builders only, nothing cached.
## DC-07 T06 adds the Ruin deck in memory (RUIN_TABLE, ruin_cards(), ruin_decks()), the
## fixture pool and list plus the plan's twenty Ruin rows, until T08 ships them.

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


## The fixture deck on both seats.
static func ids() -> Array[String]:
	var out: Array[String] = [DECK_ID, DECK_ID]
	return out


## A match on `match_seed` with the fixture deck on both seats over `pool` (the fixture
## pool, or a suite's edited copy of it holding the same ids).
static func engine(match_seed: int, pool: CardDb) -> MatchEngine:
	return MatchEngine.create(match_seed, pool, decks(), ids())


## The definitions of a fixture-vs-fixture match over `pool`, for the engine modules that
## take MatchCards (ScoreWalk, EffectResolver, LegalPlays, SeatView, GreedyBot).
static func defs(pool: CardDb) -> MatchCards:
	return MatchCards.build(pool, decks(), ids())


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
	var out: Array = []
	for raw: Variant in RUIN_TABLE:
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
	var out: Array = []
	for raw: Variant in RUIN_TABLE:
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
	listed.append(
		{"id": RUIN_DECK_ID, "name": "Ruin", "theme": RUIN_THEME, "cards": ruin_card_ids()}
	)
	return DeckList.from_json(JSON.stringify(root))


## The Ruin deck on both seats.
static func ruin_ids() -> Array[String]:
	var out: Array[String] = [RUIN_DECK_ID, RUIN_DECK_ID]
	return out


## The definitions of a Ruin-vs-Ruin match: instance id = seat * 20 + the R* index.
static func ruin_defs() -> MatchCards:
	return MatchCards.build(ruin_cards(), ruin_decks(), ruin_ids())


## A Ruin-vs-Ruin match on `match_seed` (not started).
static func ruin_engine(match_seed: int) -> MatchEngine:
	return MatchEngine.create(match_seed, ruin_cards(), ruin_decks(), ruin_ids())


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
