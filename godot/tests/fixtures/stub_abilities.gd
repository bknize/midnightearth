class_name StubAbilities
extends RefCounted
## Stub verbs for the rules no milestone A card exercises (cycle 9 plan, "Milestone A verb
## table"; DC-13 T04): each applies its rule straight through Statuses or Movement with the
## verb's name as the cause, and returns what the rule returns, so a suite can read what a
## trigger would wake (Statuses.Applied.wakes_squelch for On squelch, the moved cards for
## On moved). DC-13 T05 adds the queue stubs as a verb table (StubVerbs, installed with
## MatchCards.set_verb_handler) and the builders that put them on cards (ability(),
## card_def(), give(), engine()). Not a suite: builders only, nothing cached.
##
## The stub match plays the deck `stubs` on both seats: ten shipped cards, four copies each,
## so seat `s`'s card of pool position `index` is `s * DECK_SIZE + index` (constants below
## for seat 0: add MatchRules.DECK_SIZE for seat 1).

const DECK_ID: String = "stubs"
## The deck's ids, four copies each, in this order.
const IDS: Array[String] = [
	"ev01", "ev02", "ev04", "ev05", "ev08", "ev11", "ev15", "ev20", "gr03", "gr06"
]
## Seat 0's first instance of each (copies follow: MOTE, MOTE + 1 ... MOTE + 3).
const MOTE: int = 0  # Power 2, plain
const WISP: int = 4  # Power 1, Mult x1.25, plain
const PEBBLE: int = 8  # Power 3, plain
const SCOUT: int = 12  # On reveal: draw a card
const SCAPEGOAT: int = 16  # On squelch
const NUDGE: int = 20  # On reveal: move this card one slot right
const BRACE: int = 24  # Ongoing: this card is Anchored
const BASTION: int = 28  # Ongoing: this card cannot be Condemned
const FLARE: int = 32  # On reveal: Condemn this card
const COURIER: int = 36  # On score: draw a card
const VERB_MUTE: String = "stub_mute"
const VERB_SQUELCH: String = "stub_squelch"
const VERB_SILENCE: String = "stub_silence"
const VERB_CONDEMN: String = "stub_condemn"
const VERB_FLEETING: String = "stub_fleeting"
const VERB_FADE: String = "stub_fade"
const VERB_SHIFT_OTHERS_LEFT: String = "stub_shift_others_left"
const VERB_SWAP: String = "stub_swap"
const VERB_REVERSE: String = "stub_reverse"
## The stub deck's Crew (none fires on a reveal, a Score or a Commit).
const CREW: Array[String] = ["tallyman", "void", "engineer"]
## Ramp's Crew: Navigator (slot 0) and Captain (slot 1) sit on On score.
const RAMP_CREW: Array[String] = ["navigator", "captain", "dredger"]
## The queue stubs (DC-13 T05), handled by StubVerbs (install with MatchCards.
## set_verb_handler): see StubVerbs for each.
const VERB_RECORD: String = "stub_record"
const VERB_WAKE_MOVED: String = "stub_wake_moved"
const VERB_CONDEMN_SLOT: String = "stub_condemn_slot"
const VERB_MUTE_SLOT: String = "stub_mute_slot"
const VERB_RETRIGGER: String = "stub_retrigger"
const VERB_SCORES_TWICE: String = "stub_scores_twice"
const VERB_FEED: String = "stub_condemn_random_and_rescore"
const VERB_DISCARD_PICK: String = "stub_discard_pick"
const VERB_CHOOSE_HAND: String = "stub_choose_hand"
const VERB_REFILL: String = "stub_refill"
const MOMENT_MOVED: String = "on_moved"
const MOMENT_SCORE: String = "on_score"


## The definitions of a stubs-vs-stubs match over the shipped pool, each seat with the
## Crew `crew` (default CREW).
static func defs(crew: Array[String] = CREW) -> MatchCards:
	var ids: Array[String] = [DECK_ID, DECK_ID]
	return MatchCards.build(CardDb.load_default(), deck_list(crew), ids, CrewPool.load_default())


## The one-deck list holding the deck `stubs` with the Crew `crew`.
static func deck_list(crew: Array[String] = CREW) -> DeckList:
	var listed: Array = []
	for id: String in IDS:
		for _copy: int in range(MatchRules.MAX_COPIES):
			listed.append(id)
	var crew_ids: Array = []
	crew_ids.assign(crew)
	var deck: Dictionary = {
		"id": DECK_ID,
		"name": "Stubs",
		"tag": "evergreen",
		"theme": "Shipped cards for the status, exit and movement suites.",
		"cards": listed,
		"crew": crew_ids,
	}
	return DeckList.from_json(JSON.stringify({"version": DeckList.FORMAT_VERSION, "decks": [deck]}))


## A stubs-vs-stubs engine on `match_seed` (not started), its Crew CREW.
static func engine(match_seed: int) -> MatchEngine:
	var ids: Array[String] = [DECK_ID, DECK_ID]
	return MatchEngine.create(
		match_seed, CardDb.load_default(), deck_list(), ids, CrewPool.load_default()
	)


## One ability for a stub card (DC-13 T05): `verb` on `moment` with its brackets.
static func ability(
	moment: String, verb: String, amount: int = 0, watch: String = "self", zone: String = "row"
) -> CardAbility:
	var out: CardAbility = CardAbility.new()
	out.moment = moment
	out.verb = verb
	out.amount = amount
	out.watch = watch
	out.zone = zone
	out.text = "%s: %s" % [moment, verb]
	return out


## A stub card (Cost `cost`, Power `power`, no Bonus) carrying `abilities`.
static func card_def(
	name: String, abilities: Array[CardAbility], power: int = 1, cost: int = 1
) -> CardDef:
	var text: String = "Stub %s" % name
	return CardDef.new(
		name.to_lower(), name, "evergreen", cost, power, CardDef.BonusKind.NONE, 0, abilities, text
	)


## Gives the instances `instances` of `cards` the definition `def` (replace_def()); true
## when every one took it.
static func give(cards: MatchCards, instances: Array[int], def: CardDef) -> bool:
	var ok: bool = true
	for instance: int in instances:
		ok = replace_def(cards, instance, def) and ok
	return ok


## Fixtures only (DC-20 T03, NSC-179: the engine has no such method): replaces the
## definition of the Deck instance `instance` of `cards` with `def` (a card carrying a stub
## verb) and adds its verbs to has_verb(). False, changing nothing, for an id outside the
## Decks or a null `def`. The deck lists and every other instance keep theirs.
static func replace_def(cards: MatchCards, instance: int, def: CardDef) -> bool:
	if def == null or instance < 0 or instance >= cards.size():
		return false
	cards._defs[instance] = def
	cards._add_verbs(def)
	return true


## A fresh state whose `seat` row is `row` (face up when `revealed`), first seat 0.
static func table(row: Array[int], revealed: bool, seat: int = 0) -> MatchState:
	var state: MatchState = MatchState.new(1)
	put_row(state, seat, row, revealed)
	return state


## Sets `seat`'s row of `state` to `row`, each card face up when `revealed`.
static func put_row(state: MatchState, seat: int, row: Array[int], revealed: bool) -> void:
	var piles: MatchState.SeatPiles = state.seats[seat]
	piles.board.assign(row)
	for card: int in row:
		if revealed:
			piles.revealed[card] = true


## Mutes `card` with `cessation` (default: until end of turn).
static func stub_mute(
	state: MatchState, cards: MatchCards, card: int, sink: Callable, cessation: Dictionary = {}
) -> Statuses.Applied:
	return Statuses.apply(state, cards, card, Statuses.MUTED, _cease(cessation), VERB_MUTE, sink)


## Squelches `card` with `cessation` (default: until end of turn).
static func stub_squelch(
	state: MatchState, cards: MatchCards, card: int, sink: Callable, cessation: Dictionary = {}
) -> Statuses.Applied:
	var cease: Dictionary = _cease(cessation)
	return Statuses.apply(state, cards, card, Statuses.SQUELCHED, cease, VERB_SQUELCH, sink)


## Silences `card` (both halves) with `cessation` (default: until end of turn).
static func stub_silence(
	state: MatchState, cards: MatchCards, card: int, sink: Callable, cessation: Dictionary = {}
) -> Statuses.Applied:
	var cease: Dictionary = _cease(cessation)
	return Statuses.apply(state, cards, card, Statuses.SILENCED, cease, VERB_SILENCE, sink)


## Condemns `card`; true when the mark landed.
static func stub_condemn(
	state: MatchState, cards: MatchCards, card: int, sink: Callable
) -> bool:
	return Statuses.mark_exit(state, cards, card, Statuses.CONDEMNED, sink)


## Gives `card` Fleeting; true when the mark landed.
static func stub_fleeting(
	state: MatchState, cards: MatchCards, card: int, sink: Callable
) -> bool:
	return Statuses.mark_exit(state, cards, card, Statuses.FLEETING, sink)


## Gives `card` Fade; true when the mark landed.
static func stub_fade(state: MatchState, cards: MatchCards, card: int, sink: Callable) -> bool:
	return Statuses.mark_exit(state, cards, card, Statuses.FADE, sink)


## "Your other cards each move one slot left": every card of `seat`'s row but `source` (-1
## for none) steps left at once; returns the On moved cards.
static func stub_shift_others_left(
	state: MatchState, cards: MatchCards, seat: int, source: int, sink: Callable
) -> Array[int]:
	var movers: Array[int] = []
	for card: int in state.seats[seat].board:
		if card != source:
			movers.append(card)
	return Movement.step_left_set(state, cards, seat, movers, VERB_SHIFT_OTHERS_LEFT, sink)


## Swaps `a` and `b`; returns the On moved cards (empty when it fizzles).
static func stub_swap(
	state: MatchState, cards: MatchCards, a: int, b: int, sink: Callable
) -> Array[int]:
	return Movement.swap(state, cards, a, b, VERB_SWAP, sink)


## Reverses `seat`'s row; returns the On moved cards.
static func stub_reverse(
	state: MatchState, cards: MatchCards, seat: int, sink: Callable
) -> Array[int]:
	return Movement.reverse(state, cards, seat, VERB_REVERSE, sink)


## A new event recorder: pass `recorder.record` as a sink.
static func recorder() -> Recorder:
	return Recorder.new()


## `cessation`, or "until end of turn" when empty.
static func _cease(cessation: Dictionary) -> Dictionary:
	if cessation.is_empty():
		return Statuses.cessation(Statuses.CEASE_TURN)
	return cessation


## Records what a module sends to its sink.
class Recorder:
	extends RefCounted

	var events: Array[MatchEvent] = []

	func record(kind: int, payload: Dictionary, owner: int = MatchEvent.PUBLIC) -> void:
		events.append(MatchEvent.new(kind, payload, owner))

	## The recorded events of `kind`, in order.
	func of_kind(kind: int) -> Array[MatchEvent]:
		var out: Array[MatchEvent] = []
		for event: MatchEvent in events:
			if event.kind == kind:
				out.append(event)
		return out

	## The `card` of each recorded event of `kind`, in order.
	func cards_of(kind: int) -> Array[int]:
		var out: Array[int] = []
		for event: MatchEvent in of_kind(kind):
			var card: int = event.payload.get("card", -1)
			out.append(card)
		return out


## The queue stub verbs (DC-13 T05), as the match's extra verb table (VerbHandler). Each
## appends a line to `trace` when it resolves, so a suite can read what ran and in what
## order:
## - stub_record: does nothing ("fire <card> batch <id>");
## - stub_wake_moved: wakes On moved for its own card, then traces "done <queued entries>"
##   (the woken Batch is appended only after it returns, Q1);
## - stub_condemn_slot / stub_mute_slot: Condemns / Mutes (until end of turn) the card in
##   its own row's slot `amount`;
## - stub_retrigger: its seat's other On reveals resolve twice this Turn (Q6);
## - stub_scores_twice: every later score stage runs twice (Q7);
## - stub_condemn_random_and_rescore: Condemns a random card of the opposing row (engine
##   stream), Scores its own card again and wakes that Score's On score Batch;
## - stub_discard_pick: chooses a card of its Controller's hand (Q9), Discards it (On
##   discard wakes), then reads N, the Controller's Pile size, now (Q5): Power +N until it
##   leaves the row ("n <N>");
## - stub_choose_hand: chooses a card of its Controller's hand ("chose <card>");
## - stub_refill: moves its Controller's Pile, in order, onto the bottom of its Deck
##   ("refilled <Deck size>").
class StubVerbs:
	extends VerbHandler

	const VERBS: Array[String] = [
		VERB_RECORD,
		VERB_WAKE_MOVED,
		VERB_CONDEMN_SLOT,
		VERB_MUTE_SLOT,
		VERB_RETRIGGER,
		VERB_SCORES_TWICE,
		VERB_FEED,
		VERB_DISCARD_PICK,
		VERB_CHOOSE_HAND,
		VERB_REFILL,
	]

	var trace: Array[String] = []

	func handles(verb: String) -> bool:
		return VERBS.has(verb)

	func prepare(ctx: TriggerContext) -> void:
		if ctx.verb == VERB_DISCARD_PICK or ctx.verb == VERB_CHOOSE_HAND:
			var options: Array[int] = []
			for index: int in range(ctx.state.seats[ctx.seat].hand.size()):
				options.append(index)
			if ctx.choose(Choice.Zone.OWN_HAND, options):
				pass  # One card: chosen at once.

	func resolve(ctx: TriggerContext) -> void:
		var row: Array[int] = ctx.state.seats[ctx.seat].board
		match ctx.verb:
			VERB_RECORD:
				var batch: int = ctx.entry.get("batch", -1)
				trace.append("fire %d batch %d" % [ctx.card, batch])
			VERB_WAKE_MOVED:
				var own: Array[int] = [ctx.card]
				ctx.wake(MOMENT_MOVED, own)
				trace.append("done %d" % ctx.state.queue.size())
			VERB_CONDEMN_SLOT:
				if Statuses.mark_exit(
					ctx.state, ctx.cards, row[ctx.ability.amount], Statuses.CONDEMNED, ctx.sink
				):
					trace.append("condemned %d" % row[ctx.ability.amount])
			VERB_MUTE_SLOT:
				var muted: Statuses.Applied = StubAbilities.stub_mute(
					ctx.state, ctx.cards, row[ctx.ability.amount], ctx.sink
				)
				trace.append("muted %d" % muted.landed.size())
			VERB_RETRIGGER:
				TriggerQueue.add_retrigger(ctx.state, ctx.seat, ctx.card)
			VERB_SCORES_TWICE:
				ctx.state.walk.scores_twice = true
			VERB_FEED:
				_feed(ctx)
			VERB_DISCARD_PICK:
				_discard_pick(ctx)
			VERB_CHOOSE_HAND:
				trace.append("chose %d" % ctx.chosen_card())
			VERB_REFILL:
				# The Deck's top is its first card, so the Pile goes under it.
				var piles: MatchState.SeatPiles = ctx.state.seats[ctx.seat]
				piles.deck.append_array(piles.pile)
				piles.pile.clear()
				trace.append("refilled %d" % piles.deck.size())

	func _feed(ctx: TriggerContext) -> void:
		var enemy: Array[int] = ctx.state.seats[1 - ctx.seat].board
		if not enemy.is_empty():
			var target: int = enemy[ctx.rng.pick_index(enemy.size())]
			if StubAbilities.stub_condemn(ctx.state, ctx.cards, target, ctx.sink):
				pass  # A second Condemn of the same card replaces nothing new.
		ScoreWalk.score(ctx.state, ctx.cards, ctx.sink, ctx.seat, ctx.card)
		var own: Array[int] = [ctx.card]
		ctx.wake(MOMENT_SCORE, own)

	func _discard_pick(ctx: TriggerContext) -> void:
		var picked: int = ctx.chosen_card()
		var piles: MatchState.SeatPiles = ctx.state.seats[ctx.seat]
		if picked < 0 or not piles.hand.has(picked):
			return
		piles.hand.erase(picked)
		TurnFlow.to_pile(
			ctx.state, ctx.cards, ctx.sink, picked, TurnFlow.FROM_HAND, TurnFlow.REASON_DISCARD
		)
		var discarded: Array[int] = [picked]
		ctx.wake("on_discard", discarded)
		var n: int = piles.pile.size()
		ctx.state.card_state_for(ctx.card).power_delta += n
		trace.append("n %d" % n)
