class_name TestAbilitiesVerbs
extends GdUnitTestSuite
## The verb coverage of Abilities' dispatch (NSC-185): every verb of CardAbility.VERBS is
## listed here exactly once by what takes it; every queued verb has exactly one handler and
## no Ongoing verb is queued. A new verb fails until it is listed and its module handles it,
## where before it loaded fine and silently fizzled.

const OWN_VERBS: Array[String] = [
	"draw",
	"opponent_draw",
	"discard_own",
	"discard_hand",
	"condemn_self",
	"grow_self_power",
	"grow_self_mult_add",
	"grow_right_mult_times",
	"grow_hand_power",
	"right_power",
	"others_power",
	"copy_stats",
	"move_self_right",
	"ward_mute",
	"scapegoat",
	"delve",
	"look_at_opposing",
	"energy_grant",
	"cost_down_right",
	"cost_down_self",
	"pass_power_add",
	"free_first_next_turn",
]
const COMBO_DISRUPTION_VERBS: Array[String] = [
	"wick",
	"fade_other_own",
	"fleeting_chosen",
	"scrap",
	"copy_self_to_hand",
	"scores_twice",
	"retrigger_reveals",
	"reverb",
	"finale",
	"mute_opposing",
	"squelch_opposing",
	"create_dross",
	"move_to_opposing",
	"hex_choose",
	"mute_chosen",
	"mute_random_opposing",
	"gag",
	"quorum",
	"silence_opposing",
]
const GRAVEYARD_CONTROL_VERBS: Array[String] = [
	"fuse",
	"tithe_energy",
	"reliquary_mult",
	"condemn_other_gain",
	"revive",
	"exhume",
	"immolate",
	"reset_piles",
	"moved_add",
	"pin",
	"swap_self",
	"skip_next",
	"shake",
	"reverse_opposing",
	"cull",
]
const ONGOING_VERBS: Array[String] = [
	"plain_power",
	"anchored_self",
	"cannot_condemn_self",
	"hand_size_add",
	"cost_on_turn",
	"stasis",
	"dross_walk_end",
	"pile_power",
	"wraith_fade",
	"fence",
	"rightmost_mult",
	"level_power",
]


## Which modules handle `verb`: every name, so a verb in two lists shows as two.
func _handlers_of(verb: String) -> Array[String]:
	var out: Array[String] = []
	if Abilities.handles(verb):
		out.append("own")
	if AbilitiesComboDisruption.handles(verb):
		out.append("combo_disruption")
	if AbilitiesGraveyardControl.handles(verb):
		out.append("graveyard_control")
	return out


## Asserts each of `verbs` is handled by exactly `expected` and sits on no Ongoing moment.
func _assert_queued(verbs: Array[String], expected: String) -> void:
	var one: Array[String] = [expected]
	for verb: String in verbs:
		var label: String = "%s handled by %s" % [verb, str(_handlers_of(verb))]
		assert_array(_handlers_of(verb)).override_failure_message(label).is_equal(one)
		var entry: Dictionary = CardAbility.VERBS[verb]
		var moments: Array = entry["moments"]
		var ongoing: bool = moments.has(CardAbility.MOMENT_ONGOING)
		assert_bool(ongoing).override_failure_message(verb).is_false()


## The lists hold every verb of CardAbility.VERBS exactly once and nothing else.
func test_the_lists_name_every_card_verb_exactly_once() -> void:
	var listed: Array[String] = []
	listed.append_array(OWN_VERBS)
	listed.append_array(COMBO_DISRUPTION_VERBS)
	listed.append_array(GRAVEYARD_CONTROL_VERBS)
	listed.append_array(ONGOING_VERBS)
	assert_int(listed.size()).is_equal(CardAbility.VERBS.size())
	for verb: String in CardAbility.VERBS:
		assert_int(listed.count(verb)).override_failure_message(verb).is_equal(1)


## Every queued verb has exactly one handler, the module it is listed under.
func test_every_queued_verb_has_exactly_one_handler() -> void:
	_assert_queued(OWN_VERBS, "own")
	_assert_queued(COMBO_DISRUPTION_VERBS, "combo_disruption")
	_assert_queued(GRAVEYARD_CONTROL_VERBS, "graveyard_control")
	for verb: String in Abilities.ALWAYS_READY:
		assert_bool(OWN_VERBS.has(verb)).override_failure_message(verb).is_true()


## No Ongoing verb is queued: each sits on the Ongoing moment alone and has no handler.
func test_no_ongoing_verb_is_queued() -> void:
	for verb: String in ONGOING_VERBS:
		var entry: Dictionary = CardAbility.VERBS[verb]
		var moments: Array = entry["moments"]
		assert_array(moments).override_failure_message(verb).is_equal([CardAbility.MOMENT_ONGOING])
		assert_array(_handlers_of(verb)).override_failure_message(verb).is_empty()


## A verb with no handler that comes up anyway (an Ongoing one, an unknown one) fizzles
## `no_target`; resolved regardless it does nothing.
func test_a_verb_with_no_handler_fizzles_and_resolves_to_nothing() -> void:
	var verbs: Array[String] = ["no_such_verb"]
	verbs.append_array(ONGOING_VERBS)
	var row: Array[int] = [0]
	for verb: String in verbs:
		var rec: StubAbilities.Recorder = StubAbilities.recorder()
		var ctx: TriggerContext = TriggerContext.new()
		ctx.state = StubAbilities.table(row, true)
		ctx.sink = rec.record
		ctx.seat = 0
		ctx.card = 0
		ctx.verb = verb
		ctx.ability = CardAbility.new()
		ctx.ability.verb = verb
		Abilities.prepare(ctx)
		assert_str(ctx.fizzle_reason).override_failure_message(verb).is_equal(
			Abilities.REASON_NO_TARGET
		)
		Abilities.resolve(ctx)
		assert_array(rec.events).override_failure_message(verb).is_empty()
