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
## (Q1). The milestone A (evergreen, Greed, Ramp) verb table (plan P3); the milestone B
## verbs live in AbilitiesComboDisruption and AbilitiesGraveyardControl:
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
## Limited uses (rules 9, cycle 14 R6, R7, plan P4): an ability whose `uses` is above 0 is
## counted each time it resolves (count_use()) in the scope its `scope` names: `turn` and
## `row` as a KIND_USED Board change (CardState.granted, until that scope, so it ends at turn
## end or when the card leaves its row), `match` or none as the Memory's `uses_left` (which
## follows the card through every zone). Once none is left in that scope, prepare() fizzles
## it `spent` (TRIGGER_FIZZLED) instead of firing. `uses` 0 or absent is unlimited and never
## counts, so no shipped card changes behaviour. card_uses_left() reads what is left.
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
## TRIGGER_FIZZLED `reason` of one random Condemn pick (Fuse, Immolator) that landed on a
## card a protection keeps from the Condemned mark (Bastion; rules 9, cycle 14 R3).
const REASON_PROTECTED: String = "protected"
## TRIGGER_FIZZLED `reason` of one random Condemn pick that landed on a card already holding
## the Condemned mark (rules 9, cycle 14 R3).
const REASON_ALREADY_MARKED: String = "already_marked"
const KEY_SEAT: String = "seat"
const KEY_CARD: String = "card"
const KEY_VERB: String = "verb"
## CardState.granted kind of a Power change until end of turn (also in `power_delta`).
const KIND_POWER: String = "power"
## CardState.granted kind of one counted use of a limited ability (scope `turn` or `row`).
const KIND_USED: String = "used"  # AbilitiesGraveyardControl.KIND_USED (Tithe, Reliquary).
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


# --- The queue's protocol ---------------------------------------------------------------


## The trigger queue's entry point (the VerbHandler protocol): `ctx`'s card ability came up
## (its card is not Muted: the queue read that at the pop). Fizzles it `no_target` when it
## has no eligible target, targets through ctx.choose() (Q9), or leaves it to resolve().
## An Ongoing verb is never queued; one that comes up anyway fizzles.
static func prepare(ctx: TriggerContext) -> void:
	if ctx.card < 0 or ctx.ability == null or ctx.state == null:
		ctx.fizzle(REASON_NO_TARGET)
		return
	if uses_spent(ctx):
		ctx.fizzle(REASON_SPENT)  # Limited uses, none left in its scope (R6).
		return
	if AbilitiesComboDisruption.handles(ctx.verb):
		AbilitiesComboDisruption.prepare(ctx)  # Combo and Disruption (DC-14 T12).
		return
	if ALWAYS_READY.has(ctx.verb):
		return
	if AbilitiesGraveyardControl.handles(ctx.verb):
		AbilitiesGraveyardControl.prepare(ctx)  # DC-14 T13: Graveyard and Control.
		return
	match ctx.verb:
		VERB_DISCARD_OWN:
			_prepare_discard_own(ctx)
		VERB_DISCARD_HAND, VERB_GROW_HAND_POWER:
			need(ctx, not ctx.state.seats[ctx.seat].hand.is_empty())
		VERB_CONDEMN_SELF, VERB_SCAPEGOAT:
			need(ctx, Statuses.row_seat(ctx.state, ctx.card) >= 0)
		VERB_RIGHT_POWER, VERB_COST_DOWN_RIGHT:
			need(ctx, right_of(ctx.state, ctx.card) >= 0)
		VERB_GROW_RIGHT_MULT_TIMES:
			need(ctx, has_mult(ctx.state, ctx.cards, right_of(ctx.state, ctx.card)))
		VERB_OTHERS_POWER:
			need(ctx, not _others_revealed(ctx.state, ctx.seat, ctx.card).is_empty())
		VERB_PASS_POWER_ADD:
			need(ctx, _passed(ctx.state, ctx.seat))
		VERB_MOVE_SELF_RIGHT:
			need(ctx, _can_shift(ctx))
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
	count_use(ctx)
	if AbilitiesComboDisruption.handles(ctx.verb):
		AbilitiesComboDisruption.resolve(ctx)  # Combo and Disruption (DC-14 T12).
		return
	if AbilitiesGraveyardControl.handles(ctx.verb):
		AbilitiesGraveyardControl.resolve(ctx)  # DC-14 T13: Graveyard and Control.
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
	if _unseen_by(state, seat, target):
		# DC-14 T13: a face-down opposing card is chosen by its slot (Pin's both rows); the
		# chooser does not learn it by choosing it.
		target = MatchEvent.HIDDEN_CARD
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


## The uses `card`'s limited `ability` has left in its scope (R6): -1 for an unlimited one
## (`uses` 0); for `turn` or `row` its `uses` less the KIND_USED Board changes of that scope;
## else (`match` or none) the Memory's `uses_left`, its `uses` until first counted.
static func card_uses_left(state: MatchState, card: int, ability: CardAbility) -> int:
	if ability == null or ability.uses <= 0:
		return -1
	if ability.scope == SCOPE_TURN or ability.scope == SCOPE_ROW:
		return maxi(ability.uses - _used_in(state, card, ability.scope), 0)
	var kept: CardMemory = state.memory_of(card)
	if kept == null or kept.uses_left < 0:
		return ability.uses
	return kept.uses_left


## Whether `ctx`'s card ability is limited and has no use left in its scope (R6, R7).
static func uses_spent(ctx: TriggerContext) -> bool:
	if ctx.ability == null or ctx.ability.uses <= 0 or ctx.card < 0:
		return false
	return card_uses_left(ctx.state, ctx.card, ctx.ability) == 0


## Counts one use of `ctx`'s limited card ability as it resolves (R6): a KIND_USED Board
## change until its scope (`turn`, `row`), else one off the Memory's `uses_left`. An
## unlimited ability (`uses` 0) counts nothing.
static func count_use(ctx: TriggerContext) -> void:
	if ctx.ability == null or ctx.ability.uses <= 0 or ctx.card < 0:
		return
	var scope: String = ctx.ability.scope
	if scope == SCOPE_TURN or scope == SCOPE_ROW:
		ctx.state.card_state_for(ctx.card).grant(KIND_USED, 1, scope)
		return
	var left: int = card_uses_left(ctx.state, ctx.card, ctx.ability)
	ctx.state.memory_for(ctx.card).uses_left = maxi(left - 1, 0)


## The uses counted by the KIND_USED Board changes of `card` held until `scope`.
static func _used_in(state: MatchState, card: int, scope: String) -> int:
	var held: CardState = state.card_state(card)
	if held == null:
		return 0
	var count: int = 0
	for entry: Dictionary in held.granted:
		var kind: String = entry.get(CardState.KEY_KIND, "")
		var until: String = entry.get(CardState.KEY_UNTIL, "")
		if kind == KIND_USED and until == scope:
			var value: int = entry.get(CardState.KEY_VALUE, 0)
			count += value
	return count


# --- Preparing --------------------------------------------------------------------------


## Fizzles `ctx` `no_target` unless `ready`.
static func need(ctx: TriggerContext, ready: bool) -> void:
	if not ready:
		ctx.fizzle(REASON_NO_TARGET)


## Ember, Cinder: the Controller chooses `amount` cards of its hand (one: a single choice).
static func _prepare_discard_own(ctx: TriggerContext) -> void:
	var options: Array[int] = positions(ctx.state.seats[ctx.seat].hand.size())
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
	if ctx.choose(Choice.Zone.OWN_DECK_TOP, positions(count)):
		pass  # One card: chosen at once.


## Nudge can move: it is on a row of two or more cards and not Anchored.
static func _can_shift(ctx: TriggerContext) -> bool:
	var seat: int = Statuses.row_seat(ctx.state, ctx.card)
	if seat < 0 or ctx.state.seats[seat].board.size() < 2:
		return false
	return not Statuses.is_anchored(ctx.state, ctx.cards, ctx.card)


## Whether `card` is face down on the row of the seat other than `seat`, and `seat` has not
## looked at it.
static func _unseen_by(state: MatchState, seat: int, card: int) -> bool:
	if card < 0 or seat < 0 or seat >= state.seats.size():
		return false
	var other: MatchState.SeatPiles = state.seats[1 - seat]
	if not other.board.has(card) or other.is_revealed(card):
		return false
	return not state.seats[seat].looked.has(card)


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
	for card: int in ctx.chosen_cards():
		discard(ctx, card)


## Jackpot: every hand card, in hand order, each Discarded with its own On discard Batch.
static func _discard_hand(ctx: TriggerContext) -> void:
	var hand: Array[int] = []
	hand.assign(ctx.state.seats[ctx.seat].hand)
	for card: int in hand:
		discard(ctx, card)


## `card` leaves the Controller's hand for its Owner's Pile as a Discard (CARD_DISCARDED,
## public) and its On discard Batch is queued (Q1).
static func discard(ctx: TriggerContext, card: int) -> void:
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
		turn_power(ctx.state, card, amount)
	else:
		ctx.state.card_state_for(card).power_delta += amount
	stats_changed(ctx, card, scope == SCOPE_MATCH)


## Idler on a Pass: Power +amount and Add +amount_2 until end of turn.
static func _pass_bonus(ctx: TriggerContext) -> void:
	turn_power(ctx.state, ctx.card, ctx.ability.amount)
	ctx.state.card_state_for(ctx.card).grant(CardState.KIND_ADD, ctx.ability.amount_2, SCOPE_TURN)
	stats_changed(ctx, ctx.card, false)


## A Power change of `amount` on `card` until end of turn (end_turn_changes takes it back).
static func turn_power(state: MatchState, card: int, amount: int) -> void:
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
	stats_changed(ctx, card, true)


## Tinker, Layaway: Cost -amount for the match (Memory); an effective Cost never goes below
## MatchRules.MIN_COST (Scoring.effective_cost).
static func _cost_down(ctx: TriggerContext, card: int) -> void:
	if card < 0:
		return
	ctx.state.memory_for(card).cost_delta -= ctx.ability.amount
	stats_changed(ctx, card, true)


## Mirror: the chosen revealed opposing card's current Power and Bonuses (Q5) become this
## card's base until end of turn.
static func _copy_stats(ctx: TriggerContext) -> void:
	var target: int = ctx.chosen_card()
	var other: MatchState.SeatPiles = ctx.state.seats[1 - ctx.seat]
	if target < 0 or not other.board.has(target) or not other.is_revealed(target):
		return
	var read: Scoring.Stats = Scoring.stats(target, ctx.state, ctx.cards)
	var base: Dictionary = {
		"power": read.power, "adds": MatchState.plain(read.adds), "mults": MatchState.plain(read.mults)
	}
	ctx.state.card_state_for(ctx.card).copied_base = base
	stats_changed(ctx, ctx.card, false)


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
		insert_at_random(piles.deck, card, ctx.rng)


# --- Helpers ----------------------------------------------------------------------------


## Positions 0 .. count - 1.
static func positions(count: int) -> Array[int]:
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
## to the seat holding it while it is hidden (hidden_holder(), a pending Commit's card to the
## first committer only, R15). `cause` is the change's source: the ability's verb by default
## (""), a Crew's id for a Crew's change (R14, CrewAbilities).
static func stats_changed(
	ctx: TriggerContext, card: int, permanent: bool, cause: String = ""
) -> void:
	var read: Scoring.Stats = Scoring.stats(card, ctx.state, ctx.cards)
	var changed: Dictionary = {
		"card": card,
		"power": read.power,
		"mult": read.mult(),
		"add": read.add(),
		"cost": maxi(Scoring.effective_cost(card, ctx.state, ctx.cards), 0),
		"permanent": permanent,
		"cause": cause if cause != "" else ctx.verb,
	}
	ctx.emit(MatchEvent.Kind.STATS_CHANGED, changed, hidden_holder(ctx.state, card))


## The seat `card` is hidden for (its hand or Deck, its face-down slot on a row, or the
## first committer's pending Commit), or MatchEvent.PUBLIC when every seat may see it.
static func hidden_holder(state: MatchState, card: int) -> int:
	if state.pending.has(card):
		return state.first_seat
	for seat: int in range(state.seats.size()):
		var piles: MatchState.SeatPiles = state.seats[seat]
		if piles.board.has(card):
			return MatchEvent.PUBLIC if piles.is_revealed(card) else seat
		if piles.hand.has(card) or piles.deck.has(card):
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


## Puts `card` into `deck` at a random position drawn from `rng` (glossary "shuffle into":
## one pick_index over size + 1); at the bottom with no stream.
static func insert_at_random(deck: Array[int], card: int, rng: MatchRng) -> void:
	var at: int = deck.size()
	if rng != null:
		at = rng.pick_index(deck.size() + 1)
	if deck.insert(at, card) != OK:
		deck.append(card)
