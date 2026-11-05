class_name BloomFixture
extends RefCounted
## The Bloom deck built in memory from the cycle 8 plan's Bloom table (DC-09 T02) until T04
## ships it: the DC-05 fixture pool plus the twenty Bloom rows (pool format 4, so Oak's
## `uses` 1 is carried), and the fixture deck list plus the deck `bloom`, played on both
## seats. Instance id = seat * DECK_SIZE + the B* index. Builders only, nothing cached.

const DECK_ID: String = "bloom"
const THEME: String = "Grow your cards for good: bonuses that stay for the match."
const B01_SEED: int = 0
const B02_SPROUT: int = 1
const B03_ACORN: int = 2
const B04_MOSS: int = 3
const B05_SAPLING: int = 4
const B06_TILLER: int = 5
const B07_BRAMBLE: int = 6
const B08_RAIN: int = 7
const B09_VINE: int = 8
const B10_TRUNK: int = 9
const B11_ORCHARD: int = 10
const B12_GROVE: int = 11
const B13_ELDER: int = 12
const B14_HARVEST: int = 13
const B15_OAK: int = 14
const B16_CANOPY: int = 15
const B17_REDWOOD: int = 16
const B18_BLOOM: int = 17
const B19_ANCIENT: int = 18
const B20_WORLD_TREE: int = 19
## The plan's Bloom table in FixtureDecks.RUIN_TABLE's row format, plus an optional eleventh
## column: the effect's `uses` (format 4).
const TABLE: Array = [
	[
		"b01",
		"Seed",
		1,
		1,
		"",
		0,
		"on_score",
		"grow_self_flat",
		1,
		"Whenever this scores, +1 flat for the match."
	],
	["b02", "Sprout", 1, 2, "", 0, "", "", 0, ""],
	["b03", "Acorn", 1, 1, "x", 125, "", "", 0, ""],
	["b04", "Moss", 1, 3, "", 0, "", "", 0, ""],
	[
		"b05",
		"Sapling",
		2,
		1,
		"",
		0,
		"on_score",
		"grow_self_times",
		25,
		"Whenever this scores, ×+0.25 for the match."
	],
	[
		"b06",
		"Tiller",
		2,
		2,
		"",
		0,
		"on_reveal",
		"grow_other_flat",
		1,
		"Another card of yours gets +1 flat for the match."
	],
	["b07", "Bramble", 2, 3, "x", 125, "", "", 0, ""],
	[
		"b08",
		"Rain",
		2,
		1,
		"",
		0,
		"on_reveal",
		"grow_hand_flat",
		1,
		"Each card in your hand gets +1 flat for the match."
	],
	[
		"b09",
		"Vine",
		3,
		2,
		"",
		0,
		"on_reveal",
		"grow_hand_one_times",
		25,
		"A card in your hand gets ×+0.25 for the match."
	],
	["b10", "Trunk", 3, 4, "x", 125, "", "", 0, ""],
	[
		"b11",
		"Orchard",
		3,
		2,
		"",
		0,
		"on_reveal",
		"grow_row_flat",
		1,
		"Each other card on your row gets +1 flat for the match."
	],
	[
		"b12",
		"Grove",
		4,
		3,
		"",
		0,
		"on_score",
		"grow_self_plus",
		1,
		"Whenever this scores, its +bonus grows by 1 for the match."
	],
	["b13", "Elder", 4, 3, "x", 150, "", "", 0, ""],
	["b14", "Harvest", 4, 5, "", 0, "on_reveal", "draw", 1, "Draw a card."],
	[
		"b15",
		"Oak",
		5,
		4,
		"",
		0,
		"on_score",
		"grow_self_times_once",
		50,
		"Once per match, when this scores: ×+0.5 for the match.",
		1
	],
	["b16", "Canopy", 5, 5, "x", 125, "", "", 0, ""],
	[
		"b17",
		"Redwood",
		6,
		6,
		"",
		0,
		"on_reveal",
		"grow_hand_flat",
		2,
		"Each card in your hand gets +2 flat for the match."
	],
	["b18", "Bloom", 6, 4, "plus", 1, "", "", 0, ""],
	["b19", "Ancient", 7, 7, "x", 150, "", "", 0, ""],
	[
		"b20",
		"World Tree",
		7,
		5,
		"",
		0,
		"on_reveal",
		"grow_row_times",
		25,
		"Each other card on your row gets ×+0.25 for the match."
	],
]
## The column of TABLE holding the optional uses.
const USES_COLUMN: int = 10


## TABLE as format-4 pool entries, in deck order: FixtureDecks.table_entries() plus `uses`
## on a row that names it.
static func entries() -> Array:
	var out: Array = FixtureDecks.table_entries(TABLE)
	for index: int in range(TABLE.size()):
		var row: Array = TABLE[index]
		if row.size() <= USES_COLUMN:
			continue
		var entry: Dictionary = out[index]
		var effect: Dictionary = entry["effect"]
		effect["uses"] = row[USES_COLUMN]
	return out


## The fixture pool with the twenty Bloom cards added (in-memory JSON); null if the file is
## unread.
static func cards() -> CardDb:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FixtureDecks.CARDS_PATH))
	if not parsed is Dictionary:
		return null
	var root: Dictionary = parsed
	var listed: Array = root["cards"]
	listed.append_array(entries())
	return CardDb.from_json(JSON.stringify(root))


## The fixture deck list with the Bloom deck added (in-memory JSON); null if the file is
## unread.
static func decks() -> DeckList:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FixtureDecks.DECKS_PATH))
	if not parsed is Dictionary:
		return null
	var root: Dictionary = parsed
	var listed: Array = root["decks"]
	var bloom: Dictionary = {
		"id": DECK_ID,
		"name": "Bloom",
		"theme": THEME,
		"cards": FixtureDecks.table_ids(TABLE),
		"crew": ["gardener", "tallyman", "quartermaster"],  # The plan's Bloom Crew (P12).
	}
	listed.append(bloom)
	return DeckList.from_json(JSON.stringify(root))


## The Bloom deck on both seats.
static func ids() -> Array[String]:
	var out: Array[String] = [DECK_ID, DECK_ID]
	return out


## The definitions of a Bloom-vs-Bloom match: instance id = seat * 20 + the B* index.
static func defs() -> MatchCards:
	return MatchCards.build(cards(), decks(), ids(), FixtureDecks.crew())


## A Bloom-vs-Bloom match on `match_seed` (not started).
static func engine(match_seed: int) -> MatchEngine:
	return MatchEngine.create(match_seed, cards(), decks(), ids(), FixtureDecks.crew())
