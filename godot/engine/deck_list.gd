class_name DeckList
extends RefCounted
## Loads the deck list, v3 (cycle 9 plan P5, spec R61, R64; canon R18, R58):
## {"version": 3, "decks": [{"id", "name", "tag", "theme", "cards": [40 card ids],
## "crew": [3 Crew ids]}, ...]}.
##
## Loading checks the shape and that deck ids are unique; validate() checks each deck
## against a card pool and a Crew pool: exactly MatchRules.DECK_SIZE card ids, every id in
## the pool and none of them created-only (Dross), at most MatchRules.MAX_COPIES copies of
## one id, and exactly MatchRules.CREW_SIZE different Crew ids, each in the Crew pool (a
## Crew may serve more than one deck). Version 3 adds `tag` and the 40-card Deck with
## copies; a version-2 list fails on its version. seeded_pick() draws a seat's deck from the
## match seed with its own derived stream (MatchRng.derive_seed(seed, [DECK_TAG, seat])), so the
## pairing never touches the engine stream and the same seed always pairs the same decks
## (C15).
##
## Like CardDb, loading never prints, asserts or pushes an error: failures are reported
## through load_error(), and a failed list holds no decks.

const DEFAULT_PATH: String = "res://engine/data/decks.json"
const FORMAT_VERSION: int = 3

const KEY_ID: String = "id"
const KEY_NAME: String = "name"
const KEY_TAG: String = "tag"
const KEY_THEME: String = "theme"
const KEY_CARDS: String = "cards"
const KEY_CREW: String = "crew"

# Error prefixes, stable so tests and callers can match on them.
const ERR_FILE: String = "deck list file"
const ERR_JSON: String = "bad JSON"
const ERR_SHAPE: String = "bad shape"
const ERR_VERSION: String = "unsupported version"
const ERR_DUPLICATE_DECK: String = "duplicate deck id"
const ERR_POOL: String = "card pool invalid"
const ERR_COUNT: String = "wrong deck size"
const ERR_COPIES: String = "too many copies"
const ERR_UNKNOWN: String = "unknown card id"
## A card the pool marks created-only (Dross, `"created": true`): only an ability makes it,
## so no deck may list it (DC-14 T14).
const ERR_CREATED: String = "created-only card"
## A missing or failed Crew pool, other than CREW_SIZE Crew, a Crew twice, a Crew the pool
## does not hold.
const ERR_CREW_POOL: String = "crew pool invalid"
const ERR_CREW_COUNT: String = "wrong crew size"
const ERR_CREW_REPEAT: String = "repeated crew id"
const ERR_CREW_UNKNOWN: String = "unknown crew id"

## The decks in file order: {id, name, tag, theme, cards: Array[String], crew:
## Array[String]}.
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
		var parsed: Dictionary = _parse_deck(entries[i])
		if parsed.is_empty():
			return _failed(
				(
					"%s: deck %d needs non-empty string id and name, a string tag and theme %s"
					% [ERR_SHAPE, i, "and cards and crew arrays of strings"]
				)
			)
		var deck_id: String = parsed[KEY_ID]
		if out._index_by_id.has(deck_id):
			return _failed("%s: %s" % [ERR_DUPLICATE_DECK, deck_id])
		out._index_by_id[deck_id] = out._decks.size()
		out._decks.append(parsed)
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
	for entry: Dictionary in _decks:
		var deck_id: String = entry[KEY_ID]
		out.append(deck_id)
	return out


## Whether the list holds a deck with this id.
func has_deck(deck_id: String) -> bool:
	return _index_by_id.has(deck_id)


## A copy of the deck with this id, {id, name, tag, theme, cards: Array[String],
## crew: Array[String]}, or an empty Dictionary when absent.
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


## The Crew ids of the deck with this id, in list order (its slots 0..2); empty when absent.
func crew_ids(deck_id: String) -> Array[String]:
	var out: Array[String] = []
	if not _index_by_id.has(deck_id):
		return out
	var found: Dictionary = _decks[_index_by_id[deck_id]]
	var listed: Array = found[KEY_CREW]
	out.assign(listed)
	return out


## "" when the list loaded and every deck holds exactly MatchRules.DECK_SIZE ids that
## `cards` holds, none more than MatchRules.MAX_COPIES times, and exactly
## MatchRules.CREW_SIZE different ids that `crew` holds (plan P5); otherwise the first
## problem found.
func validate(cards: CardDb, crew: CrewPool) -> String:
	if not is_valid():
		return _error
	if cards == null or not cards.is_valid():
		return "%s: the decks cannot be checked against it" % ERR_POOL
	if crew == null or not crew.is_valid():
		return "%s: the decks cannot be checked against it" % ERR_CREW_POOL
	for deck_entry: Dictionary in _decks:
		var problem: String = _deck_problem(deck_entry, cards)
		if problem == "":
			problem = _crew_problem(deck_entry, crew)
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
	if not EngineAction.is_whole_number(raw):
		return "%s: missing or non-integer version" % ERR_SHAPE
	var version: int = EngineAction.as_int(raw)
	if version != FORMAT_VERSION:
		return "%s: %d (expected %d)" % [ERR_VERSION, version, FORMAT_VERSION]
	return ""


## One deck entry as {id, name, tag, theme, cards: Array[String], crew: Array[String]}, or
## an empty Dictionary when its shape is wrong. Sizes, copies and pool membership are
## validate()'s.
static func _parse_deck(entry: Variant) -> Dictionary:
	if not entry is Dictionary:
		return {}
	var d: Dictionary = entry
	for key: String in [KEY_ID, KEY_NAME, KEY_TAG, KEY_THEME]:
		if not d.get(key) is String:
			return {}
	if not (d.has(KEY_CARDS) and d.has(KEY_CREW)):
		return {}
	var deck_id: String = d[KEY_ID]
	var deck_name: String = d[KEY_NAME]
	var tag: String = d[KEY_TAG]
	var theme: String = d[KEY_THEME]
	if deck_id == "" or deck_name == "":
		return {}
	var card_list: Array[String] = []
	var crew_list: Array[String] = []
	if not (_strings_into(d[KEY_CARDS], card_list) and _strings_into(d[KEY_CREW], crew_list)):
		return {}
	return {
		KEY_ID: deck_id,
		KEY_NAME: deck_name,
		KEY_TAG: tag,
		KEY_THEME: theme,
		KEY_CARDS: card_list,
		KEY_CREW: crew_list,
	}


## Appends `value`'s strings to `out`; false when `value` is not an array of strings.
static func _strings_into(value: Variant, out: Array[String]) -> bool:
	if not value is Array:
		return false
	var raw_list: Array = value
	for raw: Variant in raw_list:
		if not raw is String:
			return false
		var text: String = raw
		out.append(text)
	return true


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
	var copies: Dictionary[String, int] = {}
	for card_id: String in listed:
		if not cards.has_id(card_id):
			return "%s: %s lists %s, absent from the pool" % [ERR_UNKNOWN, deck_id, card_id]
		if cards.card_by_id(card_id).created:
			return "%s: %s lists %s, which only an ability creates" % [ERR_CREATED, deck_id, card_id]
		var count: int = copies.get(card_id, 0) + 1
		copies[card_id] = count
		if count > MatchRules.MAX_COPIES:
			return (
				"%s: %s lists %s more than %d times"
				% [ERR_COPIES, deck_id, card_id, MatchRules.MAX_COPIES]
			)
	return ""


## The first Crew problem of one parsed deck against `crew` (plan P5), or "".
static func _crew_problem(deck_entry: Dictionary, crew: CrewPool) -> String:
	var deck_id: String = deck_entry[KEY_ID]
	var listed: Array[String] = []
	var raw_crew: Array = deck_entry[KEY_CREW]
	listed.assign(raw_crew)
	if listed.size() != MatchRules.CREW_SIZE:
		return (
			"%s: %s has %d crew (expected %d)"
			% [ERR_CREW_COUNT, deck_id, listed.size(), MatchRules.CREW_SIZE]
		)
	var seen: Dictionary[String, bool] = {}
	for crew_id: String in listed:
		if seen.has(crew_id):
			return "%s: %s lists %s twice" % [ERR_CREW_REPEAT, deck_id, crew_id]
		seen[crew_id] = true
		if not crew.has_id(crew_id):
			return (
				"%s: %s lists %s, absent from the crew pool" % [ERR_CREW_UNKNOWN, deck_id, crew_id]
			)
	return ""
