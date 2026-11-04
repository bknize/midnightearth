class_name MatchCards
extends RefCounted
## The card definitions of one match, indexed by instance id (R8, plan P3).
##
## Instance ids stay `origin * DECK_SIZE + index`: `origin` is the seat whose deck the card
## came from, `index` its position in that deck's card list. build() resolves the
## 2 * DECK_SIZE definitions once through each seat's deck, so def_of() is an array read and
## an instance keeps its definition whichever seat controls it. Both seats may name the
## same deck. A failed build holds no definitions and reports why through build_error().

var _defs: Array[CardDef] = []
var _deck_ids: Array[String] = []
var _error: String = ""


## Resolves the definitions of a match where seat s plays the deck `deck_ids[s]` of
## `decks`, its cards from `cards`. Fails (build_error() not empty, no definitions) when
## the pool or list is invalid, a deck fails DeckList.validate(), `deck_ids` does not name
## one deck per seat, or an id is not in the list.
static func build(cards: CardDb, decks: DeckList, deck_ids: Array[String]) -> MatchCards:
	var out: MatchCards = MatchCards.new()
	if cards == null or decks == null:
		out._error = "no card pool or deck list"
		return out
	var problem: String = decks.validate(cards)
	if problem != "":
		out._error = problem
		return out
	if deck_ids.size() != 2:
		out._error = "expected 2 deck ids, got %d" % deck_ids.size()
		return out
	var defs: Array[CardDef] = []
	for deck_id: String in deck_ids:
		if not decks.has_deck(deck_id):
			out._error = "unknown deck: %s" % deck_id
			return out
		for card_id: String in decks.card_ids(deck_id):
			defs.append(cards.card_by_id(card_id))
	out._defs = defs
	out._deck_ids.assign(deck_ids)
	return out


func is_valid() -> bool:
	return _error == ""


## Empty when build() succeeded.
func build_error() -> String:
	return _error


## Number of instances (2 * MatchRules.DECK_SIZE, or 0 after a failed build).
func size() -> int:
	return _defs.size()


## The definition of instance `instance`, or null when out of range.
func def_of(instance: int) -> CardDef:
	if instance < 0 or instance >= _defs.size():
		return null
	return _defs[instance]


## The seat whose deck `instance` came from, or -1 when out of range.
func origin_of(instance: int) -> int:
	if instance < 0 or instance >= _defs.size():
		return -1
	return instance / MatchRules.DECK_SIZE


## The deck ids per seat, as built.
func deck_ids() -> Array[String]:
	var out: Array[String] = []
	out.assign(_deck_ids)
	return out
