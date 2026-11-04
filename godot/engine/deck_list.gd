class_name DeckList
extends RefCounted
## Loads the deck list (R2, R3, R6, plan P2):
## {"version": 1, "decks": [{"id", "name", "theme", "cards": [20 card ids]}, ...]}.
##
## Loading checks the shape and that deck ids are unique; validate() checks each deck
## against a card pool: exactly MatchRules.DECK_SIZE ids, no id twice, every id in the
## pool (no cost mix, C3). seeded_pick() draws a seat's deck from the match seed with its
## own derived stream (MatchRng.derive_seed(seed, [DECK_TAG, seat])), so the pairing never
## touches the engine stream and the same seed always pairs the same decks (C15).
##
## Like CardDb, loading never prints, asserts or pushes an error: failures are reported
## through load_error(), and a failed list holds no decks.

const DEFAULT_PATH: String = "res://engine/data/decks.json"
const FORMAT_VERSION: int = 1

const KEY_ID: String = "id"
const KEY_NAME: String = "name"
const KEY_THEME: String = "theme"
const KEY_CARDS: String = "cards"

# Error prefixes, stable so tests and callers can match on them.
const ERR_FILE: String = "deck list file"
const ERR_JSON: String = "bad JSON"
const ERR_SHAPE: String = "bad shape"
const ERR_VERSION: String = "unsupported version"
const ERR_DUPLICATE_DECK: String = "duplicate deck id"
const ERR_POOL: String = "card pool invalid"
const ERR_COUNT: String = "wrong deck size"
const ERR_REPEAT: String = "repeated card id"
const ERR_UNKNOWN: String = "unknown card id"

## The decks in file order: {id, name, theme, cards: Array[String]}.
var _decks: Array[Dictionary] = []
var _index_by_id: Dictionary[String, int] = {}
var _error: String = ""


## Loads res://engine/data/decks.json.
static func load_default() -> DeckList:
	return load_from_path(DEFAULT_PATH)


## Loads a deck list from any path. Missing or unreadable files fail silently.
static func load_from_path(path: String) -> DeckList:
	if not FileAccess.file_exists(path):
		return _failed("%s not found: %s" % [ERR_FILE, path])
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failed("%s unreadable: %s" % [ERR_FILE, path])
	var text: String = file.get_as_text()
	file.close()
	return from_json(text)


## Loads a deck list from JSON text (used by tests with in-memory data).
static func from_json(text: String) -> DeckList:
	var json: JSON = JSON.new()
	var parse_err: Error = json.parse(text)
	if parse_err != OK:
		return _failed(
			"%s at line %d: %s" % [ERR_JSON, json.get_error_line(), json.get_error_message()]
		)
	var data: Variant = json.data
	if not data is Dictionary:
		return _failed("%s: top level is not an object" % ERR_SHAPE)
	var root: Dictionary = data
	var version_problem: String = _version_problem(root)
	if version_problem != "":
		return _failed(version_problem)
	if not root.has("decks") or not root["decks"] is Array:
		return _failed("%s: missing decks array" % ERR_SHAPE)
	var entries: Array = root["decks"]
	var out: DeckList = DeckList.new()
	for i: int in range(entries.size()):
		var deck: Dictionary = _parse_deck(entries[i])
		if deck.is_empty():
			return _failed(
				(
					"%s: deck %d needs non-empty string id and name, a string theme %s"
					% [ERR_SHAPE, i, "and a cards array of strings"]
				)
			)
		var deck_id: String = deck[KEY_ID]
		if out._index_by_id.has(deck_id):
			return _failed("%s: %s" % [ERR_DUPLICATE_DECK, deck_id])
		out._index_by_id[deck_id] = out._decks.size()
		out._decks.append(deck)
	return out


func is_valid() -> bool:
	return _error == ""


## Empty when the load succeeded.
func load_error() -> String:
	return _error


## Number of decks (0 when the load failed).
func size() -> int:
	return _decks.size()


## Every deck id, in file order.
func ids() -> Array[String]:
	var out: Array[String] = []
	for deck: Dictionary in _decks:
		var deck_id: String = deck[KEY_ID]
		out.append(deck_id)
	return out


## Whether the list holds a deck with this id.
func has_deck(deck_id: String) -> bool:
	return _index_by_id.has(deck_id)


## A copy of the deck with this id, {id, name, theme, cards: Array[String]}, or an empty
## Dictionary when absent.
func deck(deck_id: String) -> Dictionary:
	if not _index_by_id.has(deck_id):
		return {}
	var found: Dictionary = _decks[_index_by_id[deck_id]]
	return found.duplicate(true)


## The card ids of the deck with this id, in deck order; empty when absent.
func card_ids(deck_id: String) -> Array[String]:
	var out: Array[String] = []
	if not _index_by_id.has(deck_id):
		return out
	var found: Dictionary = _decks[_index_by_id[deck_id]]
	var listed: Array = found[KEY_CARDS]
	out.assign(listed)
	return out


## "" when the list loaded and every deck holds exactly MatchRules.DECK_SIZE distinct ids
## that `cards` holds (R2, R3); otherwise the first problem found.
func validate(cards: CardDb) -> String:
	if not is_valid():
		return _error
	if cards == null or not cards.is_valid():
		return "%s: the decks cannot be checked against it" % ERR_POOL
	for deck_entry: Dictionary in _decks:
		var problem: String = _deck_problem(deck_entry, cards)
		if problem != "":
			return problem
	return ""


## The deck a seat takes when none is named (R6, C15): a uniform pick over ids() from a
## stream seeded with MatchRng.derive_seed(match_seed, [DECK_TAG, seat]). "" when the list
## is empty. Pure: the same seed and seat always give the same id.
func seeded_pick(match_seed: int, seat: int) -> String:
	if _decks.is_empty():
		return ""
	var parts: Array[int] = [MatchRules.DECK_TAG, seat]
	var rng: MatchRng = MatchRng.new(MatchRng.derive_seed(match_seed, parts))
	var deck_entry: Dictionary = _decks[rng.pick_index(_decks.size())]
	var deck_id: String = deck_entry[KEY_ID]
	return deck_id


static func _failed(message: String) -> DeckList:
	var out: DeckList = DeckList.new()
	out._error = message
	return out


## An error message when `root` has no whole version or not FORMAT_VERSION, else "".
static func _version_problem(root: Dictionary) -> String:
	if not root.has("version"):
		return "%s: missing or non-integer version" % ERR_SHAPE
	var raw: Variant = root["version"]
	var version: int = -1
	if raw is int:
		version = raw
	elif raw is float:
		var number: float = raw
		if not is_finite(number) or number != floorf(number):
			return "%s: missing or non-integer version" % ERR_SHAPE
		version = int(number)
	else:
		return "%s: missing or non-integer version" % ERR_SHAPE
	if version != FORMAT_VERSION:
		return "%s: %d (expected %d)" % [ERR_VERSION, version, FORMAT_VERSION]
	return ""


## One deck entry as {id, name, theme, cards: Array[String]}, or an empty Dictionary when
## its shape is wrong. Sizes, repeats and pool membership are validate()'s.
static func _parse_deck(entry: Variant) -> Dictionary:
	if not entry is Dictionary:
		return {}
	var d: Dictionary = entry
	for key: String in [KEY_ID, KEY_NAME, KEY_THEME, KEY_CARDS]:
		if not d.has(key):
			return {}
	if not (d[KEY_ID] is String and d[KEY_NAME] is String and d[KEY_THEME] is String):
		return {}
	if not d[KEY_CARDS] is Array:
		return {}
	var deck_id: String = d[KEY_ID]
	var deck_name: String = d[KEY_NAME]
	var theme: String = d[KEY_THEME]
	if deck_id == "" or deck_name == "":
		return {}
	var raw_cards: Array = d[KEY_CARDS]
	var card_list: Array[String] = []
	for raw: Variant in raw_cards:
		if not raw is String:
			return {}
		var card_id: String = raw
		card_list.append(card_id)
	return {KEY_ID: deck_id, KEY_NAME: deck_name, KEY_THEME: theme, KEY_CARDS: card_list}


## The first problem of one parsed deck against `cards`, or "".
static func _deck_problem(deck_entry: Dictionary, cards: CardDb) -> String:
	var deck_id: String = deck_entry[KEY_ID]
	var listed: Array[String] = []
	var raw_cards: Array = deck_entry[KEY_CARDS]
	listed.assign(raw_cards)
	if listed.size() != MatchRules.DECK_SIZE:
		return (
			"%s: %s has %d cards (expected %d)"
			% [ERR_COUNT, deck_id, listed.size(), MatchRules.DECK_SIZE]
		)
	var seen: Dictionary[String, bool] = {}
	for card_id: String in listed:
		if seen.has(card_id):
			return "%s: %s lists %s twice" % [ERR_REPEAT, deck_id, card_id]
		seen[card_id] = true
		if not cards.has_id(card_id):
			return "%s: %s lists %s, absent from the pool" % [ERR_UNKNOWN, deck_id, card_id]
	return ""
