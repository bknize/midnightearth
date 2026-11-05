class_name MatchCards
extends RefCounted
## The card definitions of one match, indexed by instance id (R8, plan P3).
##
## Instance ids stay `origin * DECK_SIZE + index`: `origin` is the seat whose deck the card
## came from, `index` its position in that deck's card list. build() resolves the
## 2 * DECK_SIZE definitions once through each seat's deck, so def_of() is an array read and
## an instance keeps its definition whichever seat controls it. Both seats may name the
## same deck. A failed build holds no definitions and reports why through build_error().
##
## Since DC-11 T08 (cycle 8 R42, plan P12) it also holds each seat's three Crew, resolved
## from its deck's `crew` list through the Crew pool: crew_for(seat) in deck order (slot
## 0..2). Crew are not cards: they have no instance id.

var _defs: Array[CardDef] = []
var _deck_ids: Array[String] = []
var _error: String = ""
## The CardEffect.Verb and CardEffect.Trigger values some definition of the match carries,
## as sets, filled once by build() so the hot paths can skip work no card can need
## (has_verb, has_trigger; NSC-97). Empty after a failed build.
var _verbs: Dictionary[int, bool] = {}
var _triggers: Dictionary[int, bool] = {}
## Each seat's Crew in slot order, seat 0's MatchRules.CREW_SIZE then seat 1's (R42).
var _crew: Array[CrewDef] = []


## Resolves the definitions of a match where seat s plays the deck `deck_ids[s]` of
## `decks`, its cards from `cards`. Fails (build_error() not empty, no definitions) when
## the pool, the Crew pool or the list is invalid, a deck fails DeckList.validate(),
## `deck_ids` does not name one deck per seat, or an id is not in the list.
static func build(cards: CardDb, decks: DeckList, ids: Array[String], crew: CrewPool) -> MatchCards:
	var out: MatchCards = MatchCards.new()
	if cards == null or decks == null or crew == null:
		out._error = "no card pool, deck list or crew pool"
		return out
	var problem: String = decks.validate(cards, crew)
	if problem != "":
		out._error = problem
		return out
	if ids.size() != 2:
		out._error = "expected 2 deck ids, got %d" % ids.size()
		return out
	var defs: Array[CardDef] = []
	var seat_crew: Array[CrewDef] = []
	for deck_id: String in ids:
		if not decks.has_deck(deck_id):
			out._error = "unknown deck: %s" % deck_id
			return out
		for card_id: String in decks.card_ids(deck_id):
			defs.append(cards.card_by_id(card_id))
		for crew_id: String in decks.crew_ids(deck_id):
			seat_crew.append(crew.crew_of(crew_id))
	out._defs = defs
	out._crew = seat_crew
	out._deck_ids.assign(ids)
	for def: CardDef in defs:
		if def != null and def.effect != null:
			out._verbs[def.effect.verb] = true
			out._triggers[def.effect.trigger] = true
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
	@warning_ignore("integer_division")
	return instance / MatchRules.DECK_SIZE


## Whether any definition of the match carries an effect with `verb` (a CardEffect.Verb),
## on either seat's deck. False after a failed build. Fixed at build(): the definitions of
## a match never change.
func has_verb(verb: int) -> bool:
	return _verbs.has(verb)


## Whether any definition of the match carries an effect with `trigger` (a
## CardEffect.Trigger), on either seat's deck. False after a failed build.
func has_trigger(trigger: int) -> bool:
	return _triggers.has(trigger)


## `seat`'s Crew in slot order (cycle 8 R42, plan P12): MatchRules.CREW_SIZE definitions,
## or none for a seat out of range or after a failed build. A new array each call.
func crew_for(seat: int) -> Array[CrewDef]:
	var out: Array[CrewDef] = []
	if seat < 0 or (seat + 1) * MatchRules.CREW_SIZE > _crew.size():
		return out
	out.assign(_crew.slice(seat * MatchRules.CREW_SIZE, (seat + 1) * MatchRules.CREW_SIZE))
	return out


## `seat`'s Crew ids in slot order, as plain data (MATCH_STARTED `crew`, SeatView.crew);
## empty like crew_for().
func crew_ids(seat: int) -> Array:
	var out: Array = []
	for def: CrewDef in crew_for(seat):
		out.append(def.id)
	return out


## The deck ids per seat, as built.
func deck_ids() -> Array[String]:
	var out: Array[String] = []
	out.assign(_deck_ids)
	return out
