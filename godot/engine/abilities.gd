class_name Abilities
extends RefCounted
## The dispatch of card abilities (cycle 9 plan P3, P12; DC-13 T06). Pure: no nodes, no
## clock; the only randomness is the engine stream passed in (TriggerContext.rng).
##
## The trigger queue (TriggerQueue, T05) calls prepare() and resolve() per queued card
## ability. prepare() checks the verb's eligibility and either fizzles it (`no_target`),
## targets through TriggerContext.choose() (Q9: none fizzles, one is chosen at once, two or
## more open a prompt that pauses the drain), or leaves it to resolve(); resolve() applies
## the effect, reading every amount now (Q5) and waking what it causes through ctx.wake()
## (Q1). The milestone A verb table (plan P3):
## - Draws: `draw` (the Controller draws), `opponent_draw`; an empty Deck fires On empty
##   draw through TriggerContext.draw() (R18, Q11).
## - Discards: `discard_own` (a hand card the Controller chooses), `discard_hand` (every hand
##   card); each Discard goes to its Owner's Pile and wakes its own On discard Batch.
## - Exits and statuses: `condemn_self`, `scapegoat` (ends its own Squelch and Condemns
##   itself), `ward_mute` (a seat protection against Muted until end of turn).
## - Power: `grow_self_power` (scope `row` a Board change, `match` Memory, `turn` until end
##   of turn), `right_power`, `others_power`, `pass_power_add` (on a Pass: Power and an Add
##   until end of turn), `grow_hand_power` (Memory on every hand card, privately).
## - Mults: `grow_self_mult_add` (Sapling) and `grow_right_mult_times` (Graft), Memory capped
##   at the ability's `cap` (P7: Scoring.grown_mult); a card with no Mult cannot be grafted.
## - `copy_stats` (Mirror): a revealed opposing card's current Power and Bonuses become this
##   card's base until end of turn (CardState.copied_base).
## - `move_self_right` (Nudge): a ring shift (Movement), On moved for what moved.
## - Look-ats (R54, R59): `delve` (the top cards of the Deck, a private prompt over them in
##   zone OWN_DECK_TOP, the chosen one drawn, the others shuffled back in with the stream)
##   and `look_at_opposing` (Lookout: the card joins the looker's `looked`); both log each
##   look-at as a CARD_LOOKED private to the looking seat.
## - Energy and Cost: `energy_grant` (Budget this Turn, ENERGY_GRANTED), `cost_down_right`
##   and `cost_down_self` (Memory, floor 0 at the read, Scoring.effective_cost),
##   `free_first_next_turn` (Lantern: the seat's first card next Turn costs 0).
## - Ongoing verbs are read where they apply, never queued: `plain_power`
##   (Scoring.ongoing_power), `anchored_self` and `cannot_condemn_self` (Statuses),
##   `hand_size_add` (TurnFlow.hand_size), `cost_on_turn` (Scoring.effective_cost).
##
## A change "until end of turn" is a Board change logged in CardState.granted with `until`
## "turn": a Power one adds to `power_delta` and is logged with kind KIND_POWER so
## end_turn_changes() can take it back at turn end (resolution step 14), with the granted
## Adds and Mults of the Turn and Mirror's copied base. Every stat change sends
## STATS_CHANGED {card, power, mult, add, cost, permanent, cause}, private to the seat that
## holds the card while it is in a hand or Deck or face down on a row.
##
## Milestone B: the Combo and Disruption verbs (AbilitiesComboDisruption.handles()) go to
## that module's prepare() and resolve() before any verb here (DC-14 T12).
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
## CardState.granted kind of a Power change until end of turn (also in `power_delta`).
const KIND_POWER: String = "power"
## Ability scopes (CardAbility.SCOPES).
const SCOPE_TURN: String = "turn"
const SCOPE_ROW: String = "row"
const SCOPE_MATCH: String = "match"
const MOMENT_DISCARD: String = "on_discard"
## CARD_LOOKED `zone` of a Delve look-at (a Lookout's has none: the opposing row).
const LOOKED_DECK_TOP: String = "own_deck_top"
## ctx.data key: how many cards a Delve looked at.
const DATA_COUNT: String = "count"

const VERB_DRAW: String = "draw"
const VERB_OPPONENT_DRAW: String = "opponent_draw"
const VERB_DISCARD_OWN: String = "discard_own"
const VERB_DISCARD_HAND: String = "discard_hand"
const VERB_CONDEMN_SELF: String = "condemn_self"
const VERB_GROW_SELF_POWER: String = "grow_self_power"
const VERB_GROW_SELF_MULT_ADD: String = "grow_self_mult_add"
const VERB_GROW_RIGHT_MULT_TIMES: String = "grow_right_mult_times"
const VERB_GROW_HAND_POWER: String = "grow_hand_power"
const VERB_RIGHT_POWER: String = "right_power"
const VERB_OTHERS_POWER: String = "others_power"
const VERB_COPY_STATS: String = "copy_stats"
const VERB_MOVE_SELF_RIGHT: String = "move_self_right"
const VERB_WARD_MUTE: String = "ward_mute"
const VERB_SCAPEGOAT: String = "scapegoat"
const VERB_DELVE: String = "delve"
const VERB_LOOK: String = "look_at_opposing"
const VERB_ENERGY_GRANT: String = "energy_grant"
const VERB_COST_DOWN_RIGHT: String = "cost_down_right"
const VERB_COST_DOWN_SELF: String = "cost_down_self"
const VERB_PASS_POWER_ADD: String = "pass_power_add"
const VERB_FREE_FIRST: String = "free_first_next_turn"
## Verbs that need nothing checked before they resolve.
const ALWAYS_READY: Array[String] = [
	VERB_DRAW,
	VERB_OPPONENT_DRAW,
	VERB_GROW_SELF_POWER,
	VERB_GROW_SELF_MULT_ADD,
	VERB_WARD_MUTE,
	VERB_ENERGY_GRANT,
	VERB_COST_DOWN_SELF,
	VERB_FREE_FIRST,
]

# --- Lookups ----------------------------------------------------------------------------


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


## The T02 stub for one card and moment outside the queue, kept for its callers: one public
## TRIGGER_FIZZLED {seat, card, crew: "", verb, reason: REASON_NO_TARGET} per ability on
## that moment, in printed order; empty for a card with none and for a Muted card. The
## match itself fires abilities only through the trigger queue (prepare(), resolve()).
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


# --- The queue's protocol ---------------------------------------------------------------


## The trigger queue's entry point (the VerbHandler protocol): `ctx`'s card ability came up
## (its card is not Muted: the queue read that at the pop). Fizzles it `no_target` when it
## has no eligible target, targets through ctx.choose() (Q9), or leaves it to resolve().
## An Ongoing verb is never queued; one that comes up anyway fizzles.
static func prepare(ctx: TriggerContext) -> void:
	if ctx.card < 0 or ctx.ability == null or ctx.state == null:
		ctx.fizzle(REASON_NO_TARGET)
		return
	if AbilitiesComboDisruption.handles(ctx.verb):
		AbilitiesComboDisruption.prepare(ctx)  # Combo and Disruption (DC-14 T12).
		return
	if ALWAYS_READY.has(ctx.verb):
		return
	match ctx.verb:
		VERB_DISCARD_OWN:
			_prepare_discard_own(ctx)
		VERB_DISCARD_HAND, VERB_GROW_HAND_POWER:
			_need(ctx, not ctx.state.seats[ctx.seat].hand.is_empty())
		VERB_CONDEMN_SELF, VERB_SCAPEGOAT:
			_need(ctx, Statuses.row_seat(ctx.state, ctx.card) >= 0)
		VERB_RIGHT_POWER, VERB_COST_DOWN_RIGHT:
			_need(ctx, right_of(ctx.state, ctx.card) >= 0)
		VERB_GROW_RIGHT_MULT_TIMES:
			_need(ctx, has_mult(ctx.state, ctx.cards, right_of(ctx.state, ctx.card)))
		VERB_OTHERS_POWER:
			_need(ctx, not _others_revealed(ctx.state, ctx.seat, ctx.card).is_empty())
		VERB_PASS_POWER_ADD:
			_need(ctx, _passed(ctx.state, ctx.seat))
		VERB_MOVE_SELF_RIGHT:
			_need(ctx, _can_shift(ctx))
		VERB_COPY_STATS:
			_target_opposing(ctx, true)
		VERB_LOOK:
			_target_opposing(ctx, false)
		VERB_DELVE:
			_prepare_delve(ctx)
		_:
			ctx.fizzle(REASON_NO_TARGET)


## `ctx`'s card ability resolves (after prepare() left it, or after its prompt's answer in
## ctx.indices; never after a decline): the verb applies, every amount read now (Q5).
static func resolve(ctx: TriggerContext) -> void:
	if ctx.state == null or ctx.ability == null:
		return
	if AbilitiesComboDisruption.handles(ctx.verb):
		AbilitiesComboDisruption.resolve(ctx)  # Combo and Disruption (DC-14 T12).
		return
	match ctx.verb:
		VERB_DRAW:
			_draw_for(ctx, ctx.seat)
		VERB_OPPONENT_DRAW:
			_draw_for(ctx, 1 - ctx.seat)
		VERB_DISCARD_OWN:
			_discard_chosen(ctx)
		VERB_DISCARD_HAND:
			_discard_hand(ctx)
		VERB_CONDEMN_SELF:
			_condemn(ctx, ctx.card)
		VERB_SCAPEGOAT:
			_scapegoat(ctx)
		VERB_WARD_MUTE:
			var cease: Dictionary = Statuses.cessation(Statuses.CEASE_TURN)
			Statuses.protect_seat(ctx.state, ctx.seat, Statuses.MUTED, cease)
		_:
			_resolve_stats(ctx)


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


## Answers an open prompt of `state` that no drain is paused on with the positions
## `indices` of `zone` (a single choice is one position): the prompt closes with
## choice_made(). Every ability prompt pauses the queue (TriggerQueue.answer) and the
## discard-down is TurnFlow's, so this is reached only by a hand-made prompt. Empty when
## none is open.
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


## Turn end (resolution step 14, with the statuses; TurnFlow.end_statuses): every Board
## change "until end of turn" ends, cards in ascending id (the Power logged as KIND_POWER
## leaves `power_delta`, the Turn's granted Adds and Mults go, Mirror's copied base goes);
## then Lantern's free first card moves on: the one granted for the next Turn becomes the
## seat's, and one not used this Turn ends.
static func end_turn_changes(state: MatchState) -> void:
	var ids: Array[int] = []
	ids.assign(state.card_states.keys())
	ids.sort()
	for card: int in ids:
		_end_turn_changes_of(state.card_states[card])
	var energy: MatchState.EnergyState = state.energy
	for seat: int in range(energy.free_first.size()):
		energy.free_first[seat] = energy.free_first_next[seat]
		energy.free_first_next[seat] = false


# --- Reads ------------------------------------------------------------------------------


## The card in the slot to the right of `card` on its row, or -1 (none, or not on a row).
static func right_of(state: MatchState, card: int) -> int:
	var seat: int = Statuses.row_seat(state, card)
	if seat < 0:
		return -1
	var row: Array[int] = state.seats[seat].board
	var slot: int = row.find(card)
	return row[slot + 1] if slot + 1 < row.size() else -1


## Whether `card` has a Mult to grow (Graft): a printed Mult, or one its Memory grew.
static func has_mult(state: MatchState, cards: MatchCards, card: int) -> bool:
	var def: CardDef = cards.def_of(card) if cards != null and card >= 0 else null
	if def == null:
		return false
	if def.bonus_kind == CardDef.BonusKind.MULT:
		return true
	var kept: CardMemory = state.memory_of(card)
	return kept != null and kept.grows_mult()


# --- Preparing --------------------------------------------------------------------------


## Fizzles `ctx` `no_target` unless `ready`.
static func _need(ctx: TriggerContext, ready: bool) -> void:
	if not ready:
		ctx.fizzle(REASON_NO_TARGET)


## Ember, Cinder: the Controller chooses `amount` cards of its hand (one: a single choice).
static func _prepare_discard_own(ctx: TriggerContext) -> void:
	var options: Array[int] = _positions(ctx.state.seats[ctx.seat].hand.size())
	var count: int = mini(maxi(ctx.ability.amount, 1), options.size())
	if count > 1:
		if ctx.choose(Choice.Zone.OWN_HAND, options, true, count, count):
			pass  # The whole hand: taken at once.
	elif ctx.choose(Choice.Zone.OWN_HAND, options):
		pass  # One card: chosen at once.


## Mirror (`revealed` true) over the revealed opposing cards, Lookout over the face-down
## ones (Q9).
static func _target_opposing(ctx: TriggerContext, revealed: bool) -> void:
	var other: MatchState.SeatPiles = ctx.state.seats[1 - ctx.seat]
	var options: Array[int] = []
	for slot: int in range(other.board.size()):
		if other.is_revealed(other.board[slot]) == revealed:
			options.append(slot)
	if ctx.choose(Choice.Zone.OPPONENT_BOARD, options):
		pass  # One card: chosen at once.


## Delve: looks at the top `amount` cards of the Controller's Deck (fewer when the Deck is
## shorter; an empty Deck fizzles), one CARD_LOOKED each, private, then the choice over them
## (zone OWN_DECK_TOP, Q9).
static func _prepare_delve(ctx: TriggerContext) -> void:
	var deck: Array[int] = ctx.state.seats[ctx.seat].deck
	var count: int = mini(maxi(ctx.ability.amount, 1), deck.size())
	if count == 0:
		ctx.fizzle(REASON_NO_TARGET)
		return
	ctx.data[DATA_COUNT] = count
	for index: int in range(count):
		var looked: Dictionary = {
			"seat": ctx.seat,
			"card": deck[index],
			"slot": index,
			"from_seat": ctx.seat,
			"zone": LOOKED_DECK_TOP,
		}
		ctx.emit(MatchEvent.Kind.CARD_LOOKED, looked, ctx.seat)
	if ctx.choose(Choice.Zone.OWN_DECK_TOP, _positions(count)):
		pass  # One card: chosen at once.


## Nudge can move: it is on a row of two or more cards and not Anchored.
static func _can_shift(ctx: TriggerContext) -> bool:
	var seat: int = Statuses.row_seat(ctx.state, ctx.card)
	if seat < 0 or ctx.state.seats[seat].board.size() < 2:
		return false
	return not Statuses.is_anchored(ctx.state, ctx.cards, ctx.card)


## Whether `seat`'s Commit this Turn was a Pass (Idler, P14).
static func _passed(state: MatchState, seat: int) -> bool:
	return seat >= 0 and seat < state.committed_count.size() and state.committed_count[seat] == 0


# --- Resolving --------------------------------------------------------------------------


## The stat verbs (Power, Mults, Cost, Energy, copies, looks, the shift, the free first).
static func _resolve_stats(ctx: TriggerContext) -> void:
	match ctx.verb:
		VERB_GROW_SELF_POWER:
			_grow_power(ctx, ctx.card, ctx.ability.scope)
		VERB_RIGHT_POWER:
			_grow_power(ctx, right_of(ctx.state, ctx.card), SCOPE_TURN)
		VERB_OTHERS_POWER:
			for other: int in _others_revealed(ctx.state, ctx.seat, ctx.card):
				_grow_power(ctx, other, SCOPE_TURN)
		VERB_GROW_HAND_POWER:
			var hand: Array[int] = []
			hand.assign(ctx.state.seats[ctx.seat].hand)
			for held: int in hand:
				_grow_power(ctx, held, SCOPE_MATCH)
		VERB_PASS_POWER_ADD:
			_pass_bonus(ctx)
		VERB_GROW_SELF_MULT_ADD:
			_grow_mult(ctx, ctx.card, true)
		VERB_GROW_RIGHT_MULT_TIMES:
			_grow_mult(ctx, right_of(ctx.state, ctx.card), false)
		VERB_COST_DOWN_RIGHT:
			_cost_down(ctx, right_of(ctx.state, ctx.card))
		VERB_COST_DOWN_SELF:
			_cost_down(ctx, ctx.card)
		_:
			_resolve_other(ctx)


## The verbs that change no stat of a card on a row by amount: copies, looks, the shift,
## Energy and the free first card.
static func _resolve_other(ctx: TriggerContext) -> void:
	match ctx.verb:
		VERB_COPY_STATS:
			_copy_stats(ctx)
		VERB_LOOK:
			_look(ctx)
		VERB_DELVE:
			_delve(ctx)
		VERB_MOVE_SELF_RIGHT:
			for _step: int in range(maxi(ctx.ability.amount, 1)):
				var moved: Array[int] = Movement.shift(
					ctx.state, ctx.cards, ctx.card, Movement.RIGHT, ctx.verb, ctx.sink
				)
				ctx.wake_moved(moved)
		VERB_ENERGY_GRANT:
			var amount: int = ctx.ability.amount
			ctx.state.energy.grants[ctx.seat] += amount
			var granted: Dictionary = {"seat": ctx.seat, "amount": amount, "source": ctx.card}
			ctx.emit(MatchEvent.Kind.ENERGY_GRANTED, granted)
		VERB_FREE_FIRST:
			ctx.state.energy.free_first_next[ctx.seat] = true


## `amount` draws for `seat` (TriggerContext.draw: an empty Deck wakes On empty draw).
static func _draw_for(ctx: TriggerContext, seat: int) -> void:
	if seat < 0 or seat >= ctx.state.seats.size():
		return
	for _draw: int in range(maxi(ctx.ability.amount, 1)):
		if ctx.draw(seat) < 0:
			pass  # Empty: DRAW_EMPTY, its On empty draw Batch queued (Q11).


## Ember, Cinder: the chosen hand cards, each Discarded with its own On discard Batch.
static func _discard_chosen(ctx: TriggerContext) -> void:
	var chosen: Array[int] = []
	for at: int in range(ctx.indices.size()):
		chosen.append(ctx.chosen_card(at))
	for card: int in chosen:
		_discard(ctx, card)


## Jackpot: every hand card, in hand order, each Discarded with its own On discard Batch.
static func _discard_hand(ctx: TriggerContext) -> void:
	var hand: Array[int] = []
	hand.assign(ctx.state.seats[ctx.seat].hand)
	for card: int in hand:
		_discard(ctx, card)


## `card` leaves the Controller's hand for its Owner's Pile as a Discard (CARD_DISCARDED,
## public) and its On discard Batch is queued (Q1).
static func _discard(ctx: TriggerContext, card: int) -> void:
	var piles: MatchState.SeatPiles = ctx.state.seats[ctx.seat]
	if card < 0 or not piles.hand.has(card):
		return
	piles.hand.erase(card)
	TurnFlow.to_pile(
		ctx.state, ctx.cards, ctx.sink, card, TurnFlow.FROM_HAND, TurnFlow.REASON_DISCARD
	)
	var subjects: Array[int] = [card]
	ctx.wake(MOMENT_DISCARD, subjects)


## Marks `card` Condemned (a protection may block it: Bastion).
static func _condemn(ctx: TriggerContext, card: int) -> void:
	if Statuses.mark_exit(ctx.state, ctx.cards, card, Statuses.CONDEMNED, ctx.sink):
		pass  # Condemned: it still Scores this Walk and leaves at turn end (Q10).


## Scapegoat: its own Squelch ends (board-scoped or permanent alike), then it is Condemned.
static func _scapegoat(ctx: TriggerContext) -> void:
	if Statuses.end(ctx.state, ctx.card, Statuses.SQUELCHED, ctx.verb, ctx.sink):
		pass  # The Squelch is gone: it Scores this Walk.
	_condemn(ctx, ctx.card)


## Power +amount on `card` for `scope`: `match` Memory, `row` a Board change, `turn` a Board
## change until end of turn (KIND_POWER).
static func _grow_power(ctx: TriggerContext, card: int, scope: String) -> void:
	if card < 0:
		return
	var amount: int = ctx.ability.amount
	if scope == SCOPE_MATCH:
		ctx.state.memory_for(card).power += amount
	elif scope == SCOPE_TURN:
		_turn_power(ctx.state, card, amount)
	else:
		ctx.state.card_state_for(card).power_delta += amount
	_stats_changed(ctx, card, scope == SCOPE_MATCH)


## Idler on a Pass: Power +amount and Add +amount_2 until end of turn.
static func _pass_bonus(ctx: TriggerContext) -> void:
	_turn_power(ctx.state, ctx.card, ctx.ability.amount)
	ctx.state.card_state_for(ctx.card).grant(CardState.KIND_ADD, ctx.ability.amount_2, SCOPE_TURN)
	_stats_changed(ctx, ctx.card, false)


## A Power change of `amount` on `card` until end of turn (end_turn_changes takes it back).
static func _turn_power(state: MatchState, card: int, amount: int) -> void:
	var held: CardState = state.card_state_for(card)
	held.power_delta += amount
	held.grant(KIND_POWER, amount, SCOPE_TURN)


## Sapling (`additive`): Mult +amount for the match; Graft: Mult ×amount for the match. Each
## is Memory capped at the ability's `cap` (P7); a Mult already at its cap does not grow.
static func _grow_mult(ctx: TriggerContext, card: int, additive: bool) -> void:
	var def: CardDef = ctx.cards.def_of(card) if card >= 0 else null
	if def == null:
		return
	var kept: CardMemory = ctx.state.memory_for(card)
	var cap: int = ctx.ability.cap
	var now: int = Scoring.grown_mult(
		def.printed_mult(), kept.mult_add_steps, kept.mult_times_steps, kept.mult_cap
	)
	if cap > 0 and now >= cap:
		return
	if additive:
		kept.mult_add_steps += ctx.ability.amount
	else:
		kept.mult_times_steps.append(ctx.ability.amount)
	kept.mult_cap = maxi(kept.mult_cap, cap)
	_stats_changed(ctx, card, true)


## Tinker, Layaway: Cost -amount for the match (Memory); an effective Cost never goes below
## MatchRules.MIN_COST (Scoring.effective_cost).
static func _cost_down(ctx: TriggerContext, card: int) -> void:
	if card < 0:
		return
	ctx.state.memory_for(card).cost_delta -= ctx.ability.amount
	_stats_changed(ctx, card, true)


## Mirror: the chosen revealed opposing card's current Power and Bonuses (Q5) become this
## card's base until end of turn.
static func _copy_stats(ctx: TriggerContext) -> void:
	var target: int = ctx.chosen_card()
	var other: MatchState.SeatPiles = ctx.state.seats[1 - ctx.seat]
	if target < 0 or not other.board.has(target) or not other.is_revealed(target):
		return
	var read: Scoring.Stats = Scoring.stats(target, ctx.state, ctx.cards)
	var adds: Array = []
	adds.assign(read.adds)
	var mults: Array = []
	mults.assign(read.mults)
	var base: Dictionary = {"power": read.power, "adds": adds, "mults": mults}
	ctx.state.card_state_for(ctx.card).copied_base = base
	_stats_changed(ctx, ctx.card, false)


## Lookout: the chosen face-down opposing card joins the Controller's `looked` (until it is
## revealed or leaves the row), CARD_LOOKED {seat, card, slot, from_seat} private.
static func _look(ctx: TriggerContext) -> void:
	var target: int = ctx.chosen_card()
	var other: MatchState.SeatPiles = ctx.state.seats[1 - ctx.seat]
	if target < 0 or not other.board.has(target) or other.is_revealed(target):
		return
	ctx.state.seats[ctx.seat].looked[target] = true
	var looked: Dictionary = {
		"seat": ctx.seat, "card": target, "slot": other.board.find(target), "from_seat": 1 - ctx.seat
	}
	ctx.emit(MatchEvent.Kind.CARD_LOOKED, looked, ctx.seat)


## Delve: the chosen one of the looked-at top cards goes to the hand (CARD_DRAWN, private);
## each other one is shuffled back into the Deck at a random position drawn from the stream
## (glossary "shuffle into"), in top order.
static func _delve(ctx: TriggerContext) -> void:
	var piles: MatchState.SeatPiles = ctx.state.seats[ctx.seat]
	var looked: int = ctx.data.get(DATA_COUNT, 0)
	var count: int = mini(looked, piles.deck.size())
	var pick: int = ctx.indices[0] if not ctx.indices.is_empty() else 0
	if count == 0 or pick < 0 or pick >= count:
		return
	var top: Array[int] = piles.deck.slice(0, count)
	for _taken: int in range(count):
		piles.deck.remove_at(0)
	var drawn: int = top[pick]
	piles.hand.append(drawn)
	ctx.emit(MatchEvent.Kind.CARD_DRAWN, {"seat": ctx.seat, "card": drawn}, ctx.seat)
	for card: int in top:
		if card == drawn:
			continue
		var at: int = piles.deck.size()
		if ctx.rng != null:
			at = ctx.rng.pick_index(piles.deck.size() + 1)
		if piles.deck.insert(at, card) != OK:
			piles.deck.append(card)


# --- Helpers ----------------------------------------------------------------------------


## Positions 0 .. count - 1.
static func _positions(count: int) -> Array[int]:
	var out: Array[int] = []
	for index: int in range(count):
		out.append(index)
	return out


## The other revealed cards on `seat`'s row (not `card`), in slot order (Bolster).
static func _others_revealed(state: MatchState, seat: int, card: int) -> Array[int]:
	var out: Array[int] = []
	var piles: MatchState.SeatPiles = state.seats[seat]
	for other: int in piles.board:
		if other != card and piles.is_revealed(other):
			out.append(other)
	return out


## STATS_CHANGED {card, power, mult, add, cost, permanent, cause} for `card` now, private
## to the seat holding it while it is hidden (hidden_holder()).
static func _stats_changed(ctx: TriggerContext, card: int, permanent: bool) -> void:
	var read: Scoring.Stats = Scoring.stats(card, ctx.state, ctx.cards)
	var changed: Dictionary = {
		"card": card,
		"power": read.power,
		"mult": read.mult(),
		"add": read.add(),
		"cost": maxi(Scoring.effective_cost(card, ctx.state, ctx.cards), 0),
		"permanent": permanent,
		"cause": ctx.verb,
	}
	ctx.emit(MatchEvent.Kind.STATS_CHANGED, changed, hidden_holder(ctx.state, card))


## The seat `card` is hidden for (its hand or Deck, its face-down slot on a row, or the
## first committer's pending Commit), or MatchEvent.PUBLIC when every seat may see it.
static func hidden_holder(state: MatchState, card: int) -> int:
	if state.pending.has(card):
		return state.first_seat
	for seat: int in range(state.seats.size()):
		var piles: MatchState.SeatPiles = state.seats[seat]
		var face_down: bool = piles.board.has(card) and not piles.is_revealed(card)
		if face_down or piles.hand.has(card) or piles.deck.has(card):
			return seat
	return MatchEvent.PUBLIC


## Ends `held`'s Board changes "until end of turn" (end_turn_changes).
static func _end_turn_changes_of(held: CardState) -> void:
	var kept: Array[Dictionary] = []
	for entry: Dictionary in held.granted:
		var until: String = entry.get(CardState.KEY_UNTIL, "")
		if until != SCOPE_TURN:
			kept.append(entry)
			continue
		var kind: String = entry.get(CardState.KEY_KIND, "")
		if kind == KIND_POWER:
			var value: int = entry.get(CardState.KEY_VALUE, 0)
			held.power_delta -= value
	held.granted = kept
	held.copied_base = {}
