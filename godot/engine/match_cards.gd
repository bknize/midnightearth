class_name MatchCards
extends RefCounted
## The card definitions of one match, indexed by instance id (cycle 9 plan P6, spec R69).
##
## Deck cards have the ids `origin * DECK_SIZE + index`: `origin` is the seat whose Deck the
## card came from (its Owner), `index` its position in that deck's card list, so the two
## Decks take 0 .. 2 * DECK_SIZE - 1. build() resolves those 2 * DECK_SIZE definitions once
## through each seat's deck, so def_of() is an array read and an instance keeps its
## definition whichever seat controls it. Both seats may name the same deck. Cards created
## in a match (milestone B: Dross, Twin's copies) take ids from CREATED_BASE up, never
## colliding with a Deck card; record_created() gives one its definition and Owner, and
## def_of() and origin_of() answer for it as for a Deck card (its verbs join has_verb()).
## This is the one record of the created cards (DC-20 T03, NSC-179): MatchState keeps only
## the next id to hand out, and MatchEngine.full_state() lists the record as `created`. A
## created card that expires (CardDef.expires_when_piled, rules 9) is dropped from it by
## forget_created(). A failed build holds no definitions and reports why through
## build_error().
##
## It also holds each seat's three Crew, resolved from its deck's `crew` list through the
## Crew pool: crew_for(seat) in deck order (slot 0..2). Crew are not cards: they have no
## instance id.

## The first instance id of a created card (plan P6): after both Decks' ids.
const CREATED_BASE: int = 2 * MatchRules.DECK_SIZE

var _defs: Array[CardDef] = []
var _deck_ids: Array[String] = []
var _error: String = ""
## Created cards by instance id (record_created): their definition and their Owner.
var _created: Dictionary[int, CardDef] = {}
var _created_owner: Dictionary[int, int] = {}
## The verb names some definition of the match carries, as a set, filled by build() and
## grown by record_created(), so a hot path can skip work no card can need (has_verb). Empty
## after a failed build.
var _verbs: Dictionary[String, bool] = {}
## Each seat's Crew in slot order, seat 0's MatchRules.CREW_SIZE then seat 1's.
var _crew: Array[CrewDef] = []
## Extra verbs the trigger queue asks before Abilities (DC-13 T05): none in a shipped match;
## the test fixtures set one for their stub verbs (set_verb_handler). The fixtures also swap
## a Deck instance's definition here (StubAbilities.replace_def, DC-20 T03: no engine
## method does that).
var _verb_handler: VerbHandler = null
## The pool the match was built from (DC-14 T12): created cards take their definition from
## it by id (pool_def: Dross). Null after a failed build.
var _pool: CardDb = null


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
	out._pool = cards
	out._deck_ids.assign(ids)
	for def: CardDef in defs:
		out._add_verbs(def)
	return out


func is_valid() -> bool:
	return _error == ""


## Empty when build() succeeded.
func build_error() -> String:
	return _error


## Number of Deck instances (2 * MatchRules.DECK_SIZE, or 0 after a failed build); created
## cards are not counted.
func size() -> int:
	return _defs.size()


## The definition of instance `instance` (a Deck card or a recorded created card), or null.
func def_of(instance: int) -> CardDef:
	if instance >= CREATED_BASE:
		if _created.has(instance):
			return _created[instance]
		return null  # Never created, or expired (forget_created).
	if instance < 0 or instance >= _defs.size():
		return null
	return _defs[instance]


## The Owner of `instance`: the seat whose Deck it came from, or for a created card the
## seat it was created for; -1 when out of range or not recorded.
func origin_of(instance: int) -> int:
	if instance >= CREATED_BASE:
		if _created_owner.has(instance):
			return _created_owner[instance]
		return -1
	if instance < 0 or instance >= _defs.size():
		return -1
	@warning_ignore("integer_division")
	return instance / MatchRules.DECK_SIZE


## Whether `instance` is in the created range (CREATED_BASE and up).
static func is_created(instance: int) -> bool:
	return instance >= CREATED_BASE


## Records the created card `instance` (CREATED_BASE or above, not yet recorded) with its
## definition and Owner (plan P6), and adds its verbs to has_verb(). False, changing
## nothing, when the id is outside the created range, already recorded, `def` is null or
## `owner` is not a seat.
##
## Shared state (DC-14 T17): this writes `_created` and `_verbs` on a MatchCards that every
## MatchState.duplicate() copy of the match shares. Created ids are allocated only from
## MatchState.next_created_id (AbilitiesComboDisruption.create), which each copy carries, so
## a copy replaying the same actions asks for the same id with the same definition and the
## repeat is refused harmlessly. Two copies that diverge and then both create would hand one
## id two definitions; the first recorded wins here. The engine never runs diverging copies
## (no preview since C10, so one live state per match); a test that copies a state must not
## create cards on both. The training copies (MatchEngine.from_state) take a copy() of their
## own, so their rollouts never write here. A verb added here stays in has_verb() for the
## match, which only makes a hot path do work it could skip.
func record_created(instance: int, def: CardDef, owner: int) -> bool:
	if instance < CREATED_BASE or _created.has(instance) or def == null:
		return false
	if owner < 0 or owner > 1:
		return false
	_created[instance] = def
	_created_owner[instance] = owner
	_add_verbs(def)
	return true


## Drops the created card `instance` from the record (rules 9, cycle 14 R10: an
## `until_piled` card sent to a Pile leaves the Match), so def_of() is null and origin_of()
## -1 from now on. False, changing nothing, when it is not a recorded created card. Its verbs
## stay in has_verb() (that only makes a hot path do work it could skip). Shared like
## record_created(): the engine never runs diverging MatchState copies on one MatchCards.
func forget_created(instance: int) -> bool:
	if not _created.has(instance):
		return false
	var dropped: bool = _created.erase(instance) and _created_owner.erase(instance)
	return dropped



## An independent copy for a training copy of the match (MatchEngine.from_state, cycle 11
## plan P5): its own created-card records and verb set, so cards created in the copy are
## never recorded on this one. Definitions, Crew, the pool and the verb table are shared
## (never written after build()).
func copy() -> MatchCards:
	var out: MatchCards = MatchCards.new()
	out._defs.assign(_defs)
	out._deck_ids.assign(_deck_ids)
	out._error = _error
	out._created.assign(_created)
	out._created_owner.assign(_created_owner)
	out._verbs.assign(_verbs)
	out._crew.assign(_crew)
	out._verb_handler = _verb_handler
	out._pool = _pool
	return out


## The pool's definition with the id `card_id` (a created-only card such as Dross, or any
## other), or null when unknown or after a failed build.
func pool_def(card_id: String) -> CardDef:
	if _pool == null:
		return null
	return _pool.card_by_id(card_id)


## The ids of every card of the pool the match was built from, in CardDb (file) order, a
## created-only card included (BotFeatures' card indicators); empty after a failed build.
func pool_ids() -> Array[String]:
	var out: Array[String] = []
	if _pool == null:
		return out
	for def: CardDef in _pool.cards():
		out.append(def.id)
	return out


## pool_ids().size() without building the ids; 0 after a failed build.
func pool_size() -> int:
	if _pool == null:
		return 0
	return _pool.size()


## Names the pool `cards` was built from, shared by every copy(): its instance id, 0 for a
## null `cards` or after a failed build. Two MatchCards with one key share pool_ids().
static func pool_key(cards: MatchCards) -> int:
	if cards == null or cards._pool == null:
		return 0
	return cards._pool.get_instance_id()


## The pool position of `card_id` (CardDb.index_of), or -1 when unknown or after a failed
## build.
func pool_index(card_id: String) -> int:
	if _pool == null:
		return -1
	return _pool.index_of(card_id)


## Whether any definition of the match carries an ability with the verb `verb`, on either
## seat's deck or a created card's (record_created). False after a failed build.
func has_verb(verb: String) -> bool:
	return _verbs.has(verb)


## The extra verb table of this match (VerbHandler), or null: the shipped game has none.
func verb_handler() -> VerbHandler:
	return _verb_handler


## Installs `handler` as this match's extra verb table (the test fixtures' stub verbs).
func set_verb_handler(handler: VerbHandler) -> void:
	_verb_handler = handler


## `seat`'s Crew in slot order: MatchRules.CREW_SIZE definitions, or none for a seat out of
## range or after a failed build. A new array each call.
func crew_for(seat: int) -> Array[CrewDef]:
	var out: Array[CrewDef] = []
	if seat < 0 or (seat + 1) * MatchRules.CREW_SIZE > _crew.size():
		return out
	out.assign(_crew.slice(seat * MatchRules.CREW_SIZE, (seat + 1) * MatchRules.CREW_SIZE))
	return out


## `seat`'s Crew in slot `slot`, or null when out of range (no copy of the list is made).
func crew_def(seat: int, slot: int) -> CrewDef:
	if seat < 0 or slot < 0 or slot >= MatchRules.CREW_SIZE:
		return null
	var at: int = seat * MatchRules.CREW_SIZE + slot
	if at >= _crew.size():
		return null
	return _crew[at]


## The slot of `seat`'s Crew with the id `crew_id`, or -1 when it holds none (a deck names
## three different Crew, so the id is the slot's).
func crew_slot(seat: int, crew_id: String) -> int:
	for slot: int in range(MatchRules.CREW_SIZE):
		var def: CrewDef = crew_def(seat, slot)
		if def != null and def.id == crew_id:
			return slot
	return -1


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


## Records the verbs of `def`'s abilities for has_verb(); nothing for a null `def`.
func _add_verbs(def: CardDef) -> void:
	if def == null:
		return
	for ability: CardAbility in def.abilities:
		_verbs[ability.verb] = true
