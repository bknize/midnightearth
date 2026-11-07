class_name Abilities
extends RefCounted
## The dispatch of card abilities (cycle 9 plan P3, P12). Pure: no nodes, no clock; the only
## randomness is the engine stream passed in.
##
## DC-13 T02 stub: every ability is a known name with no behaviour yet. The trigger queue
## (TriggerQueue, T05) calls prepare() and resolve() per queued ability; prepare() fizzles
## each with the reason REASON_NO_TARGET, so the engine plays every card as a plain body
## until T06 fills the verbs. fire() is the same stub for one card and moment, outside the
## queue. No ability opens a prompt yet (the discard-down is
## TurnFlow's), so answer() and decline() are reached only by a hand-made prompt; they close
## it.
##
## Prompt keys (plan P12) are shared with MatchState.prompt and SeatView.prompt: KEY_SEAT,
## KEY_CARD and KEY_VERB here, the zone, options and flags in Choice.

## TRIGGER_FIZZLED `reason`: no eligible target.
const REASON_NO_TARGET: String = "no_target"
## TRIGGER_FIZZLED `reason`: the ability's limited uses are spent.
const REASON_SPENT: String = "spent"
## TRIGGER_FIZZLED `reason`: the pulse's 50 resolutions are spent (Q4, T05).
const REASON_EXHAUSTED: String = "exhausted"
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
## TRIGGER_FIZZLED {seat, card, crew: "", verb, reason: REASON_NO_TARGET} per ability on
## that moment, in printed order, and nothing else. Empty for a card with none, and for a
## Muted or Silenced card, whose triggers do not fire (R33, Statuses.fires; T05 reads it at
## the queue's pop).
static func fire(
	state: MatchState, cards: MatchCards, _rng: MatchRng, seat: int, card: int, moment: String
) -> Array[MatchEvent]:
	var out: Array[MatchEvent] = []
	if state != null and not Statuses.fires(state, card):
		return out
	for ability: CardAbility in on_moment(card, cards, moment):
		var fizzled: Dictionary = {
			"seat": seat,
			"card": card,
			"crew": "",
			"verb": ability.verb,
			"reason": REASON_NO_TARGET,
		}
		out.append(MatchEvent.new(MatchEvent.Kind.TRIGGER_FIZZLED, fizzled))
	return out


## The trigger queue's entry point (DC-13 T05, the VerbHandler protocol): `ctx`'s card
## ability came up (its card is not Muted: the queue read that at the pop). The T02 stub
## fizzles it `no_target`; DC-13 T06 dispatches the verbs here, each fizzling, targeting
## through ctx.choose() (Q9) or leaving the trigger to resolve().
static func prepare(ctx: TriggerContext) -> void:
	ctx.fizzle(REASON_NO_TARGET)


## `ctx`'s card ability resolves (after prepare() left it, or after its prompt's answer in
## ctx.indices): the T02 stub does nothing; DC-13 T06 applies the verbs, reading every
## amount now (Q5) and waking what they cause through ctx.wake() (Q1).
static func resolve(_ctx: TriggerContext) -> void:
	return


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
## choice is one position): the prompt closes with choice_made(). No ability applies a
## choice before DC-13 T06 (the discard-down is TurnFlow's). Empty when none is open.
static func answer(state: MatchState, zone: int, indices: Array[int]) -> Array[MatchEvent]:
	var out: Array[MatchEvent] = []
	var prompt: Dictionary = state.prompt
	state.prompt = {}
	if prompt.is_empty():
		return out
	out.append(choice_made(state, prompt, zone, indices))
	return out


## CHOICE_MADE for an answer to `prompt` (plan event table): {seat, card, zone, index,
## target, indices}, `card` the source (-1 for a Crew or the discard-down), `zone` its name,
## `index` and `target` the one position and the card there (both -1 for a set answer, which
## lists its positions in `indices`). Private to the prompted seat: the other seat's copy
## hides `target`. Read `state` before the answer moves any card.
static func choice_made(
	state: MatchState, prompt: Dictionary, zone: int, indices: Array[int]
) -> MatchEvent:
	var seat: int = prompt.get(KEY_SEAT, -1)
	var card: int = prompt.get(KEY_CARD, -1)
	var index: int = -1
	if indices.size() == 1 and not Choice.is_multi_prompt(prompt):
		index = indices[0]
	var target: int = Choice.resolve(state, seat, zone, index) if index >= 0 else -1
	var made: Dictionary = {
		"seat": seat,
		"card": card,
		"zone": Choice.zone_name(zone),
		"index": index,
		"target": target,
		"indices": MatchState.plain(indices),
	}
	return MatchEvent.new(MatchEvent.Kind.CHOICE_MADE, made, seat)


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
