class_name FixtureDecks
extends RefCounted
## The suites' fixture (DC-13 T02, cycle 9 plan P2, P5): an in-memory pool of 40 plain bodies
## f01..f40 (format 5, no abilities, so no fixture card ever fires or prompts) and the
## one-deck list `fixture` (v3) listing them once each in order, played on both seats. So an
## instance id is still `seat * DECK_SIZE + index` with `index` the pool position: seat 1's
## f01 is DECK_SIZE. f01..f20 carry the DC-05 fixture's costs and flats as Cost and Power
## (c01..c20, its ×-bonuses as Mults; a +-bonus has no v2 form and is dropped), f21..f40
## repeat them, so a cost search behaves as it did. Its Crew are the shipped pool's
## (CREW), live since DC-13 T07: Engineer adds 1 to the Budget from Turn 3, Tallyman doubles
## a seat's 5th Score of a Walk, Void grants on an empty draw. Not a suite: builders only,
## nothing cached.

const DECK_ID: String = "fixture"
## The fixture deck's three Crew, from the shipped Crew pool.
const CREW: Array[String] = ["tallyman", "void", "engineer"]
## f01..f20 as [cost, power, mult or 0]; f21..f40 repeat the rows.
const TABLE: Array = [
	[1, 1, 0],
	[1, 2, 0],
	[1, 1, 125],
	[1, 3, 0],
	[2, 1, 0],
	[2, 1, 0],
	[2, 2, 125],
	[2, 4, 0],
	[3, 3, 0],
	[3, 3, 0],
	[3, 3, 125],
	[4, 4, 0],
	[4, 5, 0],
	[4, 6, 0],
	[5, 5, 0],
	[5, 5, 125],
	[6, 6, 0],
	[6, 8, 0],
	[7, 7, 0],
	[7, 7, 150],
]


## The fixture pool (format 5, in memory).
static func cards() -> CardDb:
	var entries: Array = []
	for index: int in range(MatchRules.DECK_SIZE):
		var row: Array = TABLE[index % TABLE.size()]
		var mult: int = row[2]
		var bonus: Variant = null
		if mult > 0:
			bonus = {"mult": mult}
		entries.append(
			{
				"id": card_id(index),
				"name": "Fixture %d" % (index + 1),
				"tag": "evergreen",
				"cost": row[0],
				"power": row[1],
				"bonus": bonus,
				"abilities": [],
				"text": "",
			}
		)
	return CardDb.from_json(JSON.stringify({"version": CardDb.FORMAT_VERSION, "cards": entries}))


## The id of the fixture card at pool position `index` (0-based): "f01".."f40".
static func card_id(index: int) -> String:
	return "f%02d" % (index + 1)


## The fixture deck list: the single deck `fixture`, f01..f40 in order, with CREW.
static func decks() -> DeckList:
	var listed: Array = []
	for index: int in range(MatchRules.DECK_SIZE):
		listed.append(card_id(index))
	var crew_ids: Array = []
	crew_ids.assign(CREW)
	var deck: Dictionary = {
		"id": DECK_ID,
		"name": "Fixture",
		"tag": "evergreen",
		"theme": "Forty plain bodies with the DC-05 costs, for the suites.",
		"cards": listed,
		"crew": crew_ids,
	}
	return DeckList.from_json(
		JSON.stringify({"version": DeckList.FORMAT_VERSION, "decks": [deck]})
	)


## The shipped Crew pool the fixture deck names its Crew from.
static func crew() -> CrewPool:
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
## take MatchCards (ScoreWalk, LegalPlays, SeatView, RandomBot).
static func defs(pool: CardDb) -> MatchCards:
	return MatchCards.build(pool, decks(), ids(), crew())


## Puts `own` on seat 0's row and `theirs` on seat 1's (taking them from wherever they are),
## then both seats pass (each discard-down answered by discard_answer()), so the walk scores
## the two rows. False when an action is rejected.
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
			piles.pile.erase(card)
		piles.board.assign(row)
	var none: Array[int] = []
	var commits: int = 0
	while commits < MatchEngine.SEATS or not engine.open_prompt().is_empty():
		var action: EngineAction = discard_answer(engine)
		if action == null:
			action = EngineAction.commit(engine.awaited_seat(), none)
			commits += 1
		if not engine.apply(action).ok:
			return false
	return true


## The answer to an open discard-down (rules 7, DC-13 T03): its first `exact` hand positions;
## null when no prompt is open. Every fixture card is a plain body, so it is the only prompt.
static func discard_answer(engine: MatchEngine) -> EngineAction:
	var prompt: Dictionary = engine.open_prompt()
	if prompt.is_empty():
		return null
	var seat: int = prompt.get("seat", -1)
	var picked: Array[int] = []
	picked.assign(Choice.options_of(prompt).slice(0, Choice.exact_of(prompt)))
	return EngineAction.choose_set(seat, Choice.zone_of(prompt), picked)
