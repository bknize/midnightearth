class_name MatchEvent
extends RefCounted
## One thing that happened during start() or apply() (R4), rules version 7: the kinds and
## payload keys of the cycle 9 plan's event table (v7), rebuilt at DC-13 T03, so the board
## binds to every kind even where a later task first emits it (statuses and exits T04, the
## trigger queue T05, abilities T06, Crew T07).
##
## Private events carry the owning seat; public ones carry PUBLIC. Private (plan P15):
## CARD_DEALT, CARD_DRAWN, COMMITTED (its `cards`), CARD_LOOKED, CHOICE_MADE (its `target`),
## STATS_CHANGED on a hidden card (neutral stats), CARD_MOVED of a face-down card and
## TRIGGER_FIRED / TRIGGER_FIZZLED of a card firing from its Deck (DC-13 T05). A card
## firing from its hand is public and says so with `from_hand: true` (C14, the telegraph). A
## Pile entry is public (CARD_DISCARDED), so is every reveal and Score.
## redacted_for() gives each seat its copy (R29): a private CHOICE_MADE hides only its
## `target`; every other private event hides its `card` and `cards`, and a private
## STATS_CHANGED also shows neutral stats (STATS_HIDDEN), since a hidden card's effective
## Power, Bonus and Cost would name it through the public deck lists, and a private
## EXIT_RESOLVED also blanks `mark` and `instead_of` (EXIT_HIDDEN): the other seat learns
## only that the face-down card at `seat`/`slot` had an exit, and where it went (`to`).
##
## Payloads (plan event table; a few kinds carry extra keys, named below, that today's board
## still reads):
## - MATCH_STARTED {decks, crew}; ROUND_STARTED {round, sudden_death}
## - CARD_DEALT, CARD_DRAWN {seat, card}; DRAW_EMPTY {seat}; PILE_SHUFFLED_IN {seat, count}
## - TURN_STARTED {round, turn, first_seat, budgets, free_first} (`free_first` per seat,
##   Lantern's free first card, rules 9 R16); ENERGY_GRANTED {seat, amount, source}
##   (+ `next_turn: true` for a grant that lands next Turn, Tithe)
## - COMMITTED {seat, cards, slots, cost, pass} (+ `count`, the card count)
## - PROMPT_OPENED the prompt (MatchState.prompt) plus `text`; CHOICE_MADE {seat, card,
##   zone, index, target} (+ `indices` for a set answer); CHOICE_DECLINED {seat, card, crew}
## - CARD_DISCARDED {owner, card, from: hand|row, reason: discard|discard_down|condemned|
##   round_end, pile_index}
## - WALK_STARTED {first_seat}; CARD_REVEALED {seat, card, slot, power, mult, add,
##   statuses}; CARD_SCORED {seat, card, slot, power, bonus_value, total, pass};
##   WALK_ENDED {totals, scores, dross} (`dross` the Dross counted in each seat's hand)
## - TRIGGER_FIRED {seat, card, crew, moment, verb, resolution}; TRIGGER_FIZZLED {seat,
##   card, crew, verb, reason: no_target|exhausted|spent|protected|already_marked}; both add
##   `from_hand: true` for a card firing from its hand. `protected` and `already_marked`
##   name one missed random Condemn pick of a trigger that fired (Fuse, Immolator, rules 9)
## - STATS_CHANGED {card, power, mult, add, cost, permanent, cause}; STATUS_SET {card,
##   status, cessation, cause}; STATUS_ENDED {card, status, cause}; EXIT_MARKED {card, mark,
##   replaced}; EXIT_RESOLVED {card, mark, owner, to: pile|hand|face_down, seat, slot}
##   (+ `instead_of`, the mark an "instead" replaced, Wraith); `seat` is the row's and
##   `slot` the card's index there before it left
## - CARD_MOVED {card, seat, from, to, cause}; CARD_UNREVEALED {seat, card, slot};
##   CARD_RETURNED {owner, card, seat, slot} (the row it left, as on its EXIT_RESOLVED);
##   CARD_LOOKED {seat, card, slot, from_seat}
## - CREW_FIRED {seat, slot, crew, moment, verb, uses_left} (rules 9, R13: sent by
##   CrewAbilities.fire after a Crew's verb resolves, `uses_left` -1 when unlimited)
## - TURN_ENDED {scores, winner, wins} (+ `round`, `turn`); ROUND_ENDED {winner, wins}
##   (+ `round`, `scores`, `turn_wins`); CONCEDED {seat}; MATCH_ENDED {winner, reason, wins,
##   rounds_played}
## - Milestone B (DC-14, pinned by the orchestrator before wave 1; all public):
##   CARD_CREATED {seat, card, def, owner, to: hand|row, slot} (Litter's Dross into the
##   opponent's hand, Twin's copy; `seat` holds it, `slot` -1 for a hand);
##   CARD_PLACED {seat, card, from: pile, slot} (Revive: a Pile card put on a row);
##   CONTROL_CHANGED {card, owner, controller, from_seat, slot} (Saboteur: the card moves to
##   the controller's row at `slot`; the Owner is kept)
## - Rules 9 (DC-20 T03, C13, public): DROSS_EXPIRED {owner, card, from:
##   hand|row|pile|deck|pending, reason: round_end} (a Dross card of lifetime `round` leaves
##   the Match at the end of the Round, after ROUND_ENDED, one per card in ascending id;
##   TurnFlow.expire_dross)

enum Kind {
	MATCH_STARTED,
	ROUND_STARTED,
	CARD_DEALT,
	CARD_DRAWN,
	DRAW_EMPTY,
	PILE_SHUFFLED_IN,
	TURN_STARTED,
	ENERGY_GRANTED,
	COMMITTED,
	PROMPT_OPENED,
	CHOICE_MADE,
	CHOICE_DECLINED,
	CARD_DISCARDED,
	WALK_STARTED,
	CARD_REVEALED,
	CARD_SCORED,
	WALK_ENDED,
	TRIGGER_FIRED,
	TRIGGER_FIZZLED,
	STATS_CHANGED,
	STATUS_SET,
	STATUS_ENDED,
	EXIT_MARKED,
	EXIT_RESOLVED,
	CARD_MOVED,
	CARD_UNREVEALED,
	CARD_RETURNED,
	CARD_LOOKED,
	CREW_FIRED,
	TURN_ENDED,
	ROUND_ENDED,
	CONCEDED,
	MATCH_ENDED,
	CARD_CREATED,
	CARD_PLACED,
	CONTROL_CHANGED,
	DROSS_EXPIRED,
}

## owner_seat of an event every seat may see in full.
const PUBLIC: int = -1
## What a redacted copy shows in place of each hidden card id.
const HIDDEN_CARD: int = -1
const KEY_CARD: String = "card"
const KEY_CARDS: String = "cards"
const KEY_TARGET: String = "target"
## TRIGGER_FIRED / TRIGGER_FIZZLED: true when the card fired from its hand (public, C14).
const KEY_FROM_HAND: String = "from_hand"
## What the other seat's copy of a private STATS_CHANGED shows in place of the hidden card's
## stats and Memory flag (R58): Power 0, no Bonus (×1, +0), Cost 0, not permanent. `card`
## is hidden too and `cause` stays.
const STATS_HIDDEN: Dictionary = {
	"power": 0, "mult": MatchRules.BONUS_ONE, "add": 0, "cost": 0, "permanent": false
}
## What the other seat's copy of a private EXIT_RESOLVED (a face-down card's exit) shows in
## place of its mark (DC-14 T17): a Fade or Fleeting mark would tell what the card was.
const EXIT_HIDDEN: Dictionary = {"mark": "", "instead_of": ""}

var kind: int = Kind.MATCH_STARTED
var payload: Dictionary = {}
var owner_seat: int = PUBLIC


func _init(
	p_kind: int = Kind.MATCH_STARTED, p_payload: Dictionary = {}, p_owner: int = PUBLIC
) -> void:
	kind = p_kind
	payload = p_payload
	owner_seat = p_owner


func is_private() -> bool:
	return owner_seat != PUBLIC


## The event name of `kind` (the Kind key), "" when out of range.
static func kind_name(p_kind: int) -> String:
	var names: Array = Kind.keys()
	if p_kind < 0 or p_kind >= names.size():
		return ""
	var name: String = names[p_kind]
	return name


## A plain, deep-copied form for comparisons and logging.
func to_dict() -> Dictionary:
	return {"kind": kind, "owner": owner_seat, "payload": payload.duplicate(true)}


## The event that to_dict() (or its JSON form, whose numbers are floats) describes: whole
## floats read as ints, at any depth of the payload. Null when `d` lacks `kind`, `owner`
## or `payload`, when `kind` is not a Kind, when `owner` is not PUBLIC, 0 or 1, or when
## `payload` is not a Dictionary (cycle 12 plan P3). Never errors.
static func from_dict(d: Dictionary) -> MatchEvent:
	var kind_raw: Variant = d.get("kind")
	var owner_raw: Variant = d.get("owner")
	var payload_raw: Variant = d.get("payload")
	if not (EngineAction.is_whole_number(kind_raw) and EngineAction.is_whole_number(owner_raw)):
		return null
	if not payload_raw is Dictionary:
		return null
	var parsed_kind: int = EngineAction.as_int(kind_raw)
	var parsed_owner: int = EngineAction.as_int(owner_raw)
	if kind_name(parsed_kind) == "" or parsed_owner < PUBLIC or parsed_owner > 1:
		return null
	var parsed_payload: Dictionary = whole_numbers(payload_raw)
	return MatchEvent.new(parsed_kind, parsed_payload, parsed_owner)


## A deep copy of `value` with every whole float (as JSON parses numbers) turned back into
## an int, inside Arrays and Dictionary values at any depth; keys are kept as they are.
## Shared with SeatView.from_dict().
static func whole_numbers(value: Variant) -> Variant:
	if value is float:
		if EngineAction.is_whole_number(value):
			return EngineAction.as_int(value)
		return value
	if value is Array:
		var items: Array = value
		var out: Array = []
		for item: Variant in items:
			out.append(whole_numbers(item))
		return out
	if value is Dictionary:
		var entries: Dictionary = value
		var copied: Dictionary = {}
		for key: Variant in entries:
			copied[key] = whole_numbers(entries[key])
		return copied
	return value


## The copy of this event that `seat` may see (R29). Public events and the owner's own
## private events come back unchanged; for anyone else a private event keeps its kind,
## owner and `seat`, and every card id under `card` or `cards` becomes HIDDEN_CARD (the
## COMMITTED `count` stays, and so do `seat` and `slot`); a private STATS_CHANGED also takes
## STATS_HIDDEN's values for its stats and a private EXIT_RESOLVED EXIT_HIDDEN's for its
## mark; a private CHOICE_MADE keeps `card` and hides `target`. Always a new object with a
## deep-copied payload.
func redacted_for(seat: int) -> MatchEvent:
	var copied: Dictionary = payload.duplicate(true)
	if is_private() and seat != owner_seat and kind == Kind.CHOICE_MADE:
		# The chosen card is the secret; the source card is revealed on its row (R34).
		copied[KEY_TARGET] = HIDDEN_CARD
	elif is_private() and seat != owner_seat:
		if copied.has(KEY_CARD):
			copied[KEY_CARD] = HIDDEN_CARD
		if copied.has(KEY_CARDS):
			var hidden: Array = copied[KEY_CARDS]
			var masked: Array = []
			for _card: Variant in hidden:
				masked.append(HIDDEN_CARD)
			copied[KEY_CARDS] = masked
		if kind == Kind.STATS_CHANGED:
			# The stats of a hidden card would name it (R58): neutral values.
			copied.merge(STATS_HIDDEN, true)
		elif kind == Kind.EXIT_RESOLVED:
			# A hidden card's mark would name it (a Fade, DC-14 T17): blank; seat, slot stay.
			copied.merge(EXIT_HIDDEN, true)
	return MatchEvent.new(kind, copied, owner_seat)
