class_name StubCrew
extends RefCounted
## A stand-in for the Crew abilities (DC-11 T09; cycle 8 R54, plan P11), which land with T10
## (CrewEffects). Installed as a MatchEngine's TurnStart.fire, it is called for every
## TURN_START Crew in first-committer order and opens a prompt over its seat's hand
## (OWN_HAND, every position) for each Crew whose slot is in `slots` on turn `turn` of
## every round; it does nothing else. Each call is recorded as [seat, slot].
##
## engine() plays the shipped Echo deck on both seats: its Crew are Shade (slot 0, turn
## start, optional), Lookout (slot 1, not turn start) and Quartermaster (slot 2, turn
## start, not optional), so slot 0 gives an optional prompt and slot 2 one that is not.
## replay() is ActionLog.replay with the stub installed, since a log names no stub.

const DECK_ID: String = "echo"
const SHADE_SLOT: int = 0
const QUARTERMASTER_SLOT: int = 2

## The turn of each round on which the listed slots prompt.
var turn: int = 1
## The Crew slots that prompt on `turn` (of either seat).
var slots: Array[int] = [SHADE_SLOT]
## Every call, in order: [seat, slot].
var calls: Array[Array] = []


func _init(p_turn: int = 1, p_slots: Array[int] = [SHADE_SLOT]) -> void:
	turn = p_turn
	slots.assign(p_slots)


## TurnStart.fire's shape (see the class comment).
func fire(
	state: MatchState, _cards: MatchCards, _rng: MatchRng, seat: int, slot: int
) -> EffectResolver.Outcome:
	calls.append([seat, slot])
	var outcome: EffectResolver.Outcome = EffectResolver.Outcome.new()
	var hand: Array[int] = state.seats[seat].hand
	if state.turn != turn or not slots.has(slot) or hand.is_empty():
		return outcome
	var options: Array = []
	for index: int in range(hand.size()):
		options.append(index)
	outcome.prompt = {Choice.KEY_ZONE: Choice.Zone.OWN_HAND, Choice.KEY_OPTIONS: options}
	return outcome


## The deck ids of engine(): Echo on both seats.
static func ids() -> Array[String]:
	var out: Array[String] = [DECK_ID, DECK_ID]
	return out


## A match on `match_seed` over the shipped pool, deck list and Crew pool, Echo on both
## seats, with this stub as its turn-start firing. Not started.
func engine(match_seed: int) -> MatchEngine:
	var out: MatchEngine = MatchEngine.create(
		match_seed, CardDb.load_default(), DeckList.load_default(), ids(), CrewPool.load_default()
	)
	out._turn_start.fire = fire
	return out


## Replays `the_log` as ActionLog.replay() does (versions, then every action in order), on a
## shipped-data engine with this stub installed; null when the log fails a check, the start
## or any action.
func replay(the_log: ActionLog) -> MatchEngine:
	if the_log == null or the_log.format_version != MatchRules.LOG_FORMAT:
		return null
	if the_log.rules_version != MatchRules.RULES_VERSION:
		return null
	var out: MatchEngine = MatchEngine.create(
		the_log.match_seed,
		CardDb.load_default(),
		DeckList.load_default(),
		the_log.deck_ids,
		CrewPool.load_default()
	)
	out._turn_start.fire = fire
	if not out.start().ok:
		return null
	for action: EngineAction in the_log.actions:
		if not out.apply(action).ok:
			return null
	return out
