class_name TestSeatView
extends GdUnitTestSuite
## SeatView under rules 7 (cycle 9 plan P15; spec R57, R58; DC-13 T03): both Piles in full
## and in Pile order for both seats (a Pile entry is public), the opponent's hand as a count
## only, both walking totals in ten-thousandths and both Scores, both Budgets and Hand
## sizes, row entries with {card, power, mult, add, revealed, cost, grown, uses_left,
## statuses, exit_mark} and a face-down opposing card hidden, the opposing face-down cards
## this seat looked at (`looked`) for it alone, the face-down Commit's count and slots, and
## the prompt in full for the prompted seat only. States are built on the shipped Greed deck
## for both seats (instance 4 * k .. 4 * k + 3 are gr0(k+1); seat 1 adds DECK_SIZE).

const SEED: int = 1
const PIP: int = 4
const SKIM: int = 12
const GILT: int = 32
const THEIRS: int = MatchRules.DECK_SIZE

var _cached_defs: MatchCards = null


func _defs() -> MatchCards:
	if _cached_defs == null:
		var ids: Array[String] = ["greed", "greed"]
		_cached_defs = MatchCards.build(
			CardDb.load_default(), DeckList.load_default(), ids, CrewPool.load_default()
		)
	return _cached_defs


## A mid-match state: hands, Decks, Piles, rows (seat 0's Skim face up, seat 1's Gilt face
## down), totals and Scores.
func _state() -> MatchState:
	var state: MatchState = MatchState.new(SEED)
	state.round_number = 2
	state.turn = 3
	state.first_seat = 0
	state.phase = MatchState.Phase.AWAIT_FIRST
	state.seats[0].hand.assign(Typed.ints([0, 1, 2]))
	state.seats[1].hand.assign(Typed.ints([THEIRS + 1, THEIRS + 2]))
	state.seats[0].deck.assign(Typed.ints([20, 21]))
	state.seats[1].deck.assign(Typed.ints([THEIRS + 20]))
	state.seats[0].pile.assign(Typed.ints([PIP, 8]))
	state.seats[1].pile.assign(Typed.ints([THEIRS + PIP, 5, THEIRS + 8]))
	state.seats[0].board.assign(Typed.ints([SKIM]))
	state.seats[0].revealed[SKIM] = true
	state.seats[1].board.assign(Typed.ints([THEIRS + GILT]))
	state.totals.assign([43750, -15000])
	state.scores.assign([4, -1])
	state.memory_for(THEIRS + PIP).power = 2
	return state


func _view(state: MatchState, seat: int) -> SeatView:
	return SeatView.build(state, seat, state.first_seat, _defs())


## Every card id `view` names outside `looked`.
func _named(view: SeatView) -> Array[int]:
	var out: Array[int] = []
	out.append_array(view.own_hand)
	out.append_array(view.own_pending)
	out.append_array(view.own_board)
	out.append_array(view.opponent_board)
	out.append_array(view.own_pile)
	out.append_array(view.opponent_pile)
	out.append_array(view.pile_entries.keys())
	for entry: Dictionary in view.own_row + view.opponent_row:
		var card: int = entry.get("card", MatchEvent.HIDDEN_CARD)
		out.append(card)
	return out


# --- Piles ------------------------------------------------------------------------------


## Both Piles are listed in full and in Pile order, the same for either seat, each card
## with an entry (its Memory shown: a Pile card is public, R58).
func test_both_piles_are_listed_in_full_for_both_seats() -> void:
	var state: MatchState = _state()
	for seat: int in range(2):
		var view: SeatView = _view(state, seat)
		assert_array(view.pile_of(0)).is_equal(Typed.ints([PIP, 8]))
		assert_array(view.pile_of(1)).is_equal(Typed.ints([THEIRS + PIP, 5, THEIRS + 8]))
		assert_array(view.own_pile).is_equal(state.seats[seat].pile)
		assert_array(view.opponent_pile).is_equal(state.seats[1 - seat].pile)
		var keys: Array = view.pile_entries.keys()
		keys.sort()
		assert_array(keys).is_equal([PIP, 5, 8, THEIRS + PIP, THEIRS + 8])
		var grown: Dictionary = view.pile_entries[THEIRS + PIP]
		assert_int(grown.get("power", 0)).is_equal(3 + 2)
		var plain: Dictionary = view.to_dict()
		assert_bool(plain.has("own_destroyed")).is_false()
		assert_array(plain["own_pile"]).is_equal(MatchState.plain(state.seats[seat].pile))


# --- Hidden information -----------------------------------------------------------------


## The opponent's hand is a count only: no id of it anywhere in the view; the opponent's
## Deck is a count too.
func test_the_opponents_hand_is_a_count_only() -> void:
	var state: MatchState = _state()
	var view: SeatView = _view(state, 0)
	assert_int(view.opponent_hand_count).is_equal(2)
	assert_array(view.own_hand).is_equal(Typed.ints([0, 1, 2]))
	assert_array(view.deck_counts).is_equal(Typed.ints([2, 1]))
	var named: Array[int] = _named(view)
	for card: int in state.seats[1].hand + state.seats[1].deck + state.seats[0].deck:
		assert_bool(named.has(card)).override_failure_message("names %d" % card).is_false()
	var plain: Dictionary = view.to_dict()
	assert_bool(plain.has("seed")).is_false()
	assert_bool(plain.has("opponent_hand")).is_false()
	# Own hand entries carry the v2 stats.
	assert_dict(view.own_hand_row[0]).is_equal(
		{"card": 0, "cost": 1, "power": 4, "mult": 100, "add": 0, "grown": false, "uses_left": -1}
	)


## A face-down opposing row card shows no id and no stats; one this seat looked at is named
## in its `looked` (slot to card) and nowhere else, and the other seat's view has no
## `looked` entry for it.
func test_a_face_down_card_is_hidden_unless_looked_at() -> void:
	var state: MatchState = _state()
	var view: SeatView = _view(state, 0)
	assert_array(view.opponent_board).is_equal(Typed.ints([MatchEvent.HIDDEN_CARD]))
	var hidden: Dictionary = view.opponent_row[0]
	assert_dict(hidden).is_equal(
		{
			"card": MatchEvent.HIDDEN_CARD,
			"power": 0,
			"mult": MatchRules.BONUS_ONE,
			"add": 0,
			"cost": 0,
			"grown": false,
			"uses_left": -1,
			"revealed": false,
			"statuses": [],
			"exit_mark": "",
		}
	)
	assert_bool(view.looked.is_empty()).is_true()
	state.seats[0].looked[THEIRS + GILT] = true
	var looker: SeatView = _view(state, 0)
	assert_dict(looker.looked).is_equal({0: THEIRS + GILT})
	assert_array(looker.opponent_board).is_equal(Typed.ints([MatchEvent.HIDDEN_CARD]))
	var owner: SeatView = _view(state, 1)
	assert_bool(owner.looked.is_empty()).is_true()
	# The owner sees its own face-down card in full.
	var own: Dictionary = owner.own_row[0]
	assert_int(own.get("card", -1)).is_equal(THEIRS + GILT)
	assert_int(own.get("mult", 0)).is_equal(150)
	assert_bool(own.get("revealed", true)).is_false()
	# Revealed, the card is public and leaves `looked`.
	state.seats[1].revealed[THEIRS + GILT] = true
	assert_bool(_view(state, 0).looked.is_empty()).is_true()


## A revealed row card shows its Power, Mult and Add, no statuses and no exit mark before
## DC-13 T04.
func test_a_revealed_entry_shows_power_mult_add_statuses_and_exit_mark() -> void:
	var view: SeatView = _view(_state(), 1)
	assert_dict(view.opponent_row[0]).is_equal(
		{
			"card": SKIM,
			"power": 2,
			"mult": 125,
			"add": 0,
			"cost": 2,
			"grown": false,
			"uses_left": -1,
			"revealed": true,
			"statuses": [],
			"exit_mark": "",
		}
	)


# --- Totals, Scores, Budgets, Hand sizes ------------------------------------------------


## Both walking totals in ten-thousandths and both Scores, the same for either seat; both
## Budgets (Turn + grants) and both Hand sizes.
func test_totals_are_in_ten_thousandths_with_scores_budgets_and_hand_sizes() -> void:
	var state: MatchState = _state()
	state.energy.grants[1] = 1
	for seat: int in range(2):
		var view: SeatView = _view(state, seat)
		assert_array(view.totals).is_equal(Typed.ints([43750, -15000]))
		assert_array(view.scores).is_equal(Typed.ints([4, -1]))
		# Turn 3 + grants, + 1 from the Greed deck's Engineer (DC-13 T07).
		assert_array(view.budgets).is_equal(Typed.ints([4, 5]))
		assert_int(view.energy).is_equal(4 + seat)
		assert_array(view.hand_sizes).is_equal(
			Typed.ints([MatchRules.HAND_SIZE, MatchRules.HAND_SIZE])
		)
		var plain: Dictionary = view.to_dict()
		assert_array(plain["totals"]).is_equal([43750, -15000])
		assert_bool(plain.has("mults")).is_false()


# --- The face-down Commit and the prompt -----------------------------------------------


## The first Commit is the first seat's own in full and the other seat's as a count and
## slots only.
func test_the_face_down_commit_is_a_count_and_slots_for_the_other_seat() -> void:
	var state: MatchState = _state()
	state.phase = MatchState.Phase.AWAIT_SECOND
	state.pending.assign(Typed.ints([1, 2]))
	state.pending_slots.assign(Typed.ints([0, 2]))
	var own: SeatView = _view(state, 0)
	assert_array(own.own_pending).is_equal(Typed.ints([1, 2]))
	assert_int(own.opponent_pending_count).is_equal(0)
	var other: SeatView = _view(state, 1)
	assert_array(other.own_pending).is_empty()
	assert_int(other.opponent_pending_count).is_equal(2)
	assert_array(other.opponent_pending_slots).is_equal(Typed.ints([0, 2]))
	for card: int in [1, 2]:
		assert_bool(_named(other).has(card)).is_false()


## The prompt is the prompted seat's in full (zone by name, `exact`, `step`) and only
## {open, seat} for the other.
func test_the_prompt_is_full_for_the_prompted_seat_only() -> void:
	var state: MatchState = _state()
	state.phase = MatchState.Phase.AWAIT_CHOICE
	state.prompt = {
		"seat": 0,
		"card": -1,
		"crew": "",
		"verb": TurnFlow.VERB_DISCARD_DOWN,
		"zone": "own_hand",
		"options": [0, 1, 2],
		"multi": true,
		"exact": 1,
		"min": 1,
		"optional": false,
		"resume": Choice.RESUME_COMMIT,
		"step": TurnFlow.STEP_FIRST_DISCARD,
	}
	var asked: SeatView = SeatView.build(state, 0, 0, _defs())
	assert_dict(asked.prompt).is_equal(
		{
			"open": true,
			"seat": 0,
			"card": -1,
			"crew": "",
			"verb": TurnFlow.VERB_DISCARD_DOWN,
			"text": "Discard 1",
			"zone": "own_hand",
			"options": [0, 1, 2],
			"multi": true,
			"exact": 1,
			"min": 1,
			"max": Choice.NO_MAX,
			"optional": false,
			"resume": Choice.RESUME_COMMIT,
			"step": TurnFlow.STEP_FIRST_DISCARD,
		}
	)
	assert_int(Choice.zone_of(asked.prompt)).is_equal(Choice.Zone.OWN_HAND)
	var other: SeatView = SeatView.build(state, 1, 0, _defs())
	assert_dict(other.prompt).is_equal({"open": true, "seat": 0})


## Every array is a copy: mutating a view never touches the state.
func test_a_view_holds_copies() -> void:
	var state: MatchState = _state()
	var view: SeatView = _view(state, 0)
	view.own_pile.append(99)
	view.opponent_pile.clear()
	view.totals[0] = 0
	view.own_hand.clear()
	assert_array(state.seats[0].pile).is_equal(Typed.ints([PIP, 8]))
	assert_int(state.seats[1].pile.size()).is_equal(3)
	assert_int(state.totals[0]).is_equal(43750)
	assert_int(state.seats[0].hand.size()).is_equal(3)
