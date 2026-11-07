class_name Abilities
extends RefCounted
## The dispatch of card abilities (cycle 9 plan P3, P12). Pure: no nodes, no clock; the only
## randomness is the engine stream passed in.
##
## DC-13 T02 stub: every ability is a known name with no behaviour yet. fire() finds the
## abilities of a card that sit on a moment and fizzles each of them with the reason
## REASON_NO_TARGET, so the engine compiles and plays every card as a plain body (Power, a
## ×1 Bonus) until T05 adds the trigger queue and T06 the verbs. No ability opens a prompt
## yet, so answer() and decline() are reached only by a hand-made prompt; they close it.
##
## Prompt keys (plan P12) are shared with MatchState.prompt and SeatView.prompt: KEY_SEAT,
## KEY_CARD and KEY_VERB here, the zone, options and flags in Choice.

## EFFECT_FIZZLED `reason`: no eligible target.
const REASON_NO_TARGET: String = "no_target"
## EFFECT_FIZZLED `reason`: the ability's limited uses are spent.
const REASON_SPENT: String = "spent"
const KEY_SEAT: String = "seat"
const KEY_CARD: String = "card"
const KEY_VERB: String = "verb"


## The abilities of `card` (an instance id) whose moment is `moment`, in printed order;
## empty for a plain body or an unknown id.
static func on_moment(card: int, cards: MatchCards, moment: String) -> Array[CardAbility]:
	var out: Array[CardAbility] = []
	if cards == null or card < 0:
		return out
	var def: CardDef = cards.def_of(card)
	if def == null:
		return out
	for ability: CardAbility in def.abilities:
		if ability.moment == moment:
			out.append(ability)
	return out


## Fires `card`'s abilities on `moment` for its Controller `seat` (the T02 stub): one public
## EFFECT_FIZZLED {seat, card, verb, moment, reason: REASON_NO_TARGET} per ability on that
## moment, in printed order, and nothing else. Empty for a card with none.
static func fire(
	_state: MatchState, cards: MatchCards, _rng: MatchRng, seat: int, card: int, moment: String
) -> Array[MatchEvent]:
	var out: Array[MatchEvent] = []
	for ability: CardAbility in on_moment(card, cards, moment):
		var fizzled: Dictionary = {
			"seat": seat,
			"card": card,
			"verb": ability.verb,
			"moment": moment,
			"reason": REASON_NO_TARGET,
		}
		out.append(MatchEvent.new(MatchEvent.Kind.EFFECT_FIZZLED, fizzled))
	return out


## The rules text of the source of `prompt` (a card's text, or a Crew's), "" when unknown.
static func prompt_text(prompt: Dictionary, cards: MatchCards) -> String:
	if cards == null:
		return ""
	var crew_id: String = Choice.crew_of(prompt)
	var seat: int = prompt.get(KEY_SEAT, -1)
	if crew_id != "":
		var slot: int = cards.crew_slot(seat, crew_id)
		var crew: CrewDef = cards.crew_def(seat, slot)
		return crew.text if crew != null else ""
	var source: int = prompt.get(KEY_CARD, -1)
	var def: CardDef = cards.def_of(source)
	return def.text if def != null else ""


## Answers the open prompt of `state` with the positions `indices` of `zone` (a single
## choice is one position): the prompt closes with CHOICE_MADE {seat, card, zone, indices},
## private to the prompted seat. No T02 ability applies a choice. Empty when none is open.
static func answer(state: MatchState, zone: int, indices: Array[int]) -> Array[MatchEvent]:
	var out: Array[MatchEvent] = []
	var prompt: Dictionary = state.prompt
	state.prompt = {}
	if prompt.is_empty():
		return out
	var seat: int = prompt.get(KEY_SEAT, -1)
	var card: int = prompt.get(KEY_CARD, -1)
	var made: Dictionary = {
		"seat": seat,
		"card": card,
		"zone": Choice.zone_name(zone),
		"indices": MatchState.plain(indices),
	}
	out.append(MatchEvent.new(MatchEvent.Kind.CHOICE_MADE, made, seat))
	return out


## Declines the open optional prompt of `state` (plan P12): the prompt closes and its
## ability does not apply, CHOICE_DECLINED {seat, card, crew}, public. Empty when none is
## open.
static func decline(state: MatchState) -> Array[MatchEvent]:
	var out: Array[MatchEvent] = []
	var prompt: Dictionary = state.prompt
	state.prompt = {}
	if prompt.is_empty():
		return out
	var seat: int = prompt.get(KEY_SEAT, -1)
	var card: int = prompt.get(KEY_CARD, -1)
	var declined: Dictionary = {"seat": seat, "card": card, "crew": Choice.crew_of(prompt)}
	out.append(MatchEvent.new(MatchEvent.Kind.CHOICE_DECLINED, declined))
	return out
