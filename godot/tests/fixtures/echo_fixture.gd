class_name EchoFixture
extends RefCounted
## The Echo deck built in memory from the cycle 8 plan's Echo table (DC-09 T03) until T04
## ships it: the DC-05 fixture pool plus the twenty Echo rows (pool format 4, so Messenger's
## `uses` 1 is carried), and the fixture deck list plus the deck `echo`, played on both
## seats. Instance id = seat * DECK_SIZE + the E* index. Builders only, nothing cached.

const DECK_ID: String = "echo"
const THEME: String = "Replay your reveals: returns, flips and cards that remember."
const E01_WHISPER: int = 0
const E02_SPARK: int = 1
const E03_FLICKER: int = 2
const E04_GLINT: int = 3
const E05_ECHO: int = 4
const E06_REFRAIN: int = 5
const E07_RIPPLE: int = 6
const E08_MESSENGER: int = 7
const E09_TINKER: int = 8
const E10_RECALL: int = 9
const E11_CHIME: int = 10
const E12_BANISH: int = 11
const E13_LANTERN: int = 12
const E14_MIRAGE: int = 13
const E15_RELAY: int = 14
const E16_SIGNAL: int = 15
const E17_REVERB: int = 16
const E18_RESONANCE: int = 17
const E19_ENCORE: int = 18
const E20_ETERNITY: int = 19
## The plan's Echo table in FixtureDecks.RUIN_TABLE's row format, plus an optional eleventh
## column: the effect's `uses` (format 4).
const TABLE: Array = [
	[
		"e01",
		"Whisper",
		1,
		1,
		"",
		0,
		"on_reveal",
		"grow_self_flat",
		1,
		"Whenever this reveals, +1 flat for the match."
	],
	["e02", "Spark", 1, 2, "", 0, "", "", 0, ""],
	[
		"e03",
		"Flicker",
		1,
		1,
		"x",
		125,
		"on_reveal",
		"return_self_at_turn_end",
		0,
		"Returns to your hand at the end of the turn."
	],
	["e04", "Glint", 1, 3, "", 0, "", "", 0, ""],
	[
		"e05",
		"Echo",
		2,
		2,
		"",
		0,
		"ongoing",
		"unreveal_at_turn_end",
		0,
		"At the end of the turn, this card flips face down."
	],
	[
		"e06",
		"Refrain",
		2,
		1,
		"",
		0,
		"on_ally_reveal",
		"ally_reveal_flat",
		1,
		"Whenever another card of yours reveals, +1 flat this round."
	],
	["e07", "Ripple", 2, 3, "x", 125, "", "", 0, ""],
	[
		"e08",
		"Messenger",
		2,
		2,
		"",
		0,
		"on_reveal",
		"draw_once",
		2,
		"The first time this reveals each match, draw 2.",
		1
	],
	[
		"e09",
		"Tinker",
		3,
		3,
		"",
		0,
		"on_reveal",
		"cost_down_right",
		1,
		"The card to the right of this one costs 1 less for the match."
	],
	[
		"e10",
		"Recall",
		3,
		2,
		"",
		0,
		"on_reveal",
		"return_own_at_turn_end",
		0,
		"Another card of yours returns to your hand at the end of the turn."
	],
	["e11", "Chime", 3, 4, "x", 125, "", "", 0, ""],
	[
		"e12",
		"Banish",
		4,
		3,
		"",
		0,
		"on_reveal",
		"return_opponent_at_turn_end",
		0,
		"An enemy card returns to its owner's hand at the end of the turn."
	],
	[
		"e13",
		"Lantern",
		4,
		4,
		"",
		0,
		"on_reveal",
		"free_first_next_turn",
		0,
		"Next turn, your first card is free."
	],
	["e14", "Mirage", 4, 5, "x", 125, "", "", 0, ""],
	[
		"e15",
		"Relay",
		5,
		3,
		"",
		0,
		"on_ally_reveal",
		"draw",
		1,
		"Whenever another card of yours reveals, draw a card."
	],
	["e16", "Signal", 5, 5, "x", 150, "", "", 0, ""],
	[
		"e17",
		"Reverb",
		6,
		5,
		"",
		0,
		"on_reveal",
		"cost_down_self",
		2,
		"This card costs 2 less for the match."
	],
	["e18", "Resonance", 6, 3, "plus", 1, "", "", 0, ""],
	[
		"e19",
		"Encore",
		7,
		10,
		"",
		0,
		"on_reveal",
		"return_self_at_turn_end",
		0,
		"Returns to your hand at the end of the turn."
	],
	["e20", "Eternity", 7, 7, "x", 200, "", "", 0, ""],
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


## The fixture pool with the twenty Echo cards added (in-memory JSON); null if the file is
## unread.
static func cards() -> CardDb:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FixtureDecks.CARDS_PATH))
	if not parsed is Dictionary:
		return null
	var root: Dictionary = parsed
	var listed: Array = root["cards"]
	listed.append_array(entries())
	return CardDb.from_json(JSON.stringify(root))


## The fixture deck list with the Echo deck added (in-memory JSON); null if the file is
## unread.
static func decks() -> DeckList:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FixtureDecks.DECKS_PATH))
	if not parsed is Dictionary:
		return null
	var root: Dictionary = parsed
	var listed: Array = root["decks"]
	var echo: Dictionary = {
		"id": DECK_ID,
		"name": "Echo",
		"theme": THEME,
		"cards": FixtureDecks.table_ids(TABLE),
		"crew": ["shade", "lookout", "quartermaster"],  # The plan's Echo Crew (P12).
	}
	listed.append(echo)
	return DeckList.from_json(JSON.stringify(root))


## The Echo deck on both seats.
static func ids() -> Array[String]:
	var out: Array[String] = [DECK_ID, DECK_ID]
	return out


## The definitions of an Echo-vs-Echo match: instance id = seat * 20 + the E* index.
static func defs() -> MatchCards:
	return MatchCards.build(cards(), decks(), ids(), FixtureDecks.crew())


## An Echo-vs-Echo match on `match_seed` (not started).
static func engine(match_seed: int) -> MatchEngine:
	return MatchEngine.create(match_seed, cards(), decks(), ids(), FixtureDecks.crew())
