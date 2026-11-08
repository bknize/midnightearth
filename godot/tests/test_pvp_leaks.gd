class_name TestPvpLeaks
extends FullMatchHarness
## The P15 leak scan over every PVP message (cycle 12 T03; plan P15, P19; spec R21, R33):
## ten random-bot matches played through a MatchRoom by two fake clients (PvpTable), each
## seat's bot reading only the views it was sent. Every message either seat receives is
## taken as its JSON text and as NetCodec decoded it, and checked:
## - the text names no seed: neither the match seed's digits nor a `seed` or `rng_state` key;
## - its events are exactly the seat's redaction of the step (ApplyResult.events_for) and
##   pass the harness's event scan (no card hidden from the seat before or after the step,
##   outside its public windows; neutral stats on a redacted STATS_CHANGED);
## - its view is the seat's own and passes the harness's view scans (no id from the
##   opponent's hand, Deck or face-down Commit, no face-down row card, the other seat's
##   prompt reduced, both Piles in full, `looked` only for looked-at cards);
## - a `resync` mid-match carries exactly the seat's scanned history.
## The hidden sets come from a twin engine on the same seed fed the same (seat-forced)
## actions; its full state is compared with the room's at the end.

const SEEDS: int = 10
const SEED_MASK: int = 0x7FFFFFFF
## Seeds this large have digits that cannot turn up in a message by chance.
const MIN_SEED: int = 100000000
const RESYNC_AT: int = 20
const RECONNECT_CONN: int = 404
const BANNED_KEYS: Array[String] = ["\"seed\"", "\"rng_state\""]


func test_ten_pvp_matches_send_no_seed_and_no_hidden_card() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	for index: int in range(SEEDS):
		rng.seed = index + 1
		var match_seed: int = 0
		while match_seed < MIN_SEED:
			match_seed = rng.randi() & SEED_MASK
		var decks: Array[String] = [DECKS[index % DECKS.size()], DECKS[(index + 1) % DECKS.size()]]
		_play_and_scan(match_seed, decks)


func _play_and_scan(match_seed: int, decks: Array[String]) -> void:
	var label: String = "seed %d (%s/%s): " % [match_seed, decks[0], decks[1]]
	var table: PvpTable = PvpTable.create(match_seed)
	var twin: MatchEngine = _named_engine(match_seed, decks)
	var run: FullMatchRun = FullMatchRun.new()
	run.match_seed = match_seed
	run.engine = twin
	var history: Array[Array] = [[], []]
	table.host(decks[0])
	var before: Dictionary = twin.full_state()
	var mark: int = table.sent.size()
	table.join(decks[1])
	var result: ApplyResult = twin.start()
	assert_bool(result.ok).override_failure_message(label + "twin start").is_true()
	_scan_step(run, table, before, result, mark, history)
	var resynced: bool = false
	while run.actions < MAX_ACTIONS:
		var seat: int = table.awaited_seat()
		if seat < 0:
			break
		if run.actions == RESYNC_AT and not resynced:
			resynced = true
			_scan_resync(run, table, history)
		var action: EngineAction = table.bot_action(seat)
		var forced: EngineAction = action.copy()
		forced.seat = seat
		before = twin.full_state()
		run.sets_before = run.sets_after
		run.sets_after = null
		mark = table.sent.size()
		table.act(seat, action)
		result = twin.apply(forced)
		if not result.ok:
			run.rejections.append("action %d rejected by the twin" % run.actions)
			break
		run.actions += 1
		_scan_step(run, table, before, result, mark, history)
	assert_bool(resynced).override_failure_message(label + "no resync").is_true()
	assert_array(table.unencodable).override_failure_message(label + "unencodable").is_empty()
	_assert_none(run.rejections, label + "rejected")
	_assert_none(run.leaks, label + "leaked")
	assert_bool(twin.is_over()).override_failure_message(label + "did not end").is_true()
	var room_state: Dictionary = table.maker.engine.full_state()
	var same: bool = room_state == twin.full_state()
	assert_bool(same).override_failure_message(label + "room and twin differ").is_true()
	assert_int(run.redacted_seen).override_failure_message(label + "none redacted").is_greater(0)
	assert_int(run.face_down_seen).is_greater(0)


## Every message the step sent (table.sent from `mark` on) against the twin's step.
func _scan_step(
	run: FullMatchRun,
	table: PvpTable,
	before: Dictionary,
	result: ApplyResult,
	mark: int,
	history: Array[Array]
) -> void:
	var after: Dictionary = run.engine.full_state()
	if run.sets_before == null:
		run.sets_before = _sets_of(before)
	run.sets_after = _sets_of(after)
	run.steps_scanned += 1
	var windows: FullMatchHarness.PublicWindows = _public_windows(before, after, result)
	var received: Array[int] = [0, 0]
	for at: int in range(mark, table.sent.size()):
		var entry: PvpTable.Sent = table.sent[at]
		var seat: int = table.conns.find(entry.conn)
		var where: String = "after action %d, %s to seat %d" % [run.actions, entry.kind, seat]
		_scan_text(run, entry, where)
		if seat < 0:
			run.leaks.append(where + ": sent to a connection with no seat")
			continue
		received[seat] += 1
		var expected: Array = _plain(result.events_for(seat))
		history[seat].append_array(expected)
		_scan_events(run, entry, seat, expected, windows, where)
		_scan_view(run, entry, seat, after, where)
	for seat: int in range(MatchEngine.SEATS):
		if received[seat] != 1:
			run.leaks.append(
				"after action %d: seat %d got %d messages" % [run.actions, seat, received[seat]]
			)


## The text carries no seed: not the match seed's digits, not a seed or RNG key.
func _scan_text(run: FullMatchRun, entry: PvpTable.Sent, where: String) -> void:
	if entry.text.contains(str(run.match_seed)):
		run.leaks.append(where + ": the text holds the match seed")
	for banned: String in BANNED_KEYS:
		if entry.text.contains(banned):
			run.leaks.append(where + ": the text holds " + banned)


## The message's events are exactly the seat's redaction and name no card hidden from it.
func _scan_events(
	run: FullMatchRun,
	entry: PvpTable.Sent,
	seat: int,
	expected: Array,
	windows: FullMatchHarness.PublicWindows,
	where: String
) -> void:
	var seen: Array[MatchEvent] = NetCodec.events_of(entry.message)
	if _text(_plain(seen)) != _text(expected):
		run.leaks.append(where + ": events differ from the seat's redaction")
	var opp: int = 1 - seat
	var hidden_during: Dictionary = run.sets_before.hidden[opp].duplicate()
	hidden_during.merge(run.sets_after.hidden[opp])
	var own_known: Dictionary = run.sets_before.own[seat].duplicate()
	own_known.merge(run.sets_after.own[seat])
	for at: int in range(seen.size()):
		var event: MatchEvent = seen[at]
		if event.is_private() and event.owner_seat == opp:
			run.redacted_seen += 1
			if FullMatchRun.is_memory_kind(event.kind):
				run.check_neutral_stats(event, where)
		if event.kind == MatchEvent.Kind.CARD_LOOKED and event.owner_seat == seat:
			continue
		for card: int in FullMatchRun.event_card_ids(event):
			if _public_at(windows, card, at):
				continue
			if hidden_during.has(card) and not own_known.has(card):
				var kind: String = MatchEvent.kind_name(event.kind)
				run.leaks.append(where + ": event %s names hidden card %d" % [kind, card])


## The message's view is the seat's own and shows nothing hidden from it.
func _scan_view(
	run: FullMatchRun, entry: PvpTable.Sent, seat: int, after: Dictionary, where: String
) -> void:
	var view: SeatView = NetCodec.view_of(entry.message)
	if view == null:
		run.leaks.append(where + ": no view")
		return
	if view.seat != seat:
		run.leaks.append(where + ": the view is seat %d's" % view.seat)
		return
	var hidden_now: Dictionary = run.sets_after.hidden[1 - seat]
	for card: int in _view_card_ids(view):
		if hidden_now.has(card):
			run.leaks.append(where + ": view names hidden card %d" % card)
	if view.opponent_pending_count > 0:
		run.face_down_seen += 1
	_scan_prompt(run, view, where)
	_scan_hidden_rows(run, view, where)
	_scan_piles(run, view, after, where)
	_scan_looked(run, view, after, where)


## Seat 1 drops and rejoins: its `resync` holds exactly its scanned history and a view
## that passes the view scans; the host hears `opponent lost` then `back`.
func _scan_resync(run: FullMatchRun, table: PvpTable, history: Array[Array]) -> void:
	var where: String = "resync at action %d" % run.actions
	var after: Dictionary = run.engine.full_state()
	var mark: int = table.sent.size()
	table.take(table.room.connection_lost(table.conns[1], table.now_ms))
	table.conns[1] = RECONNECT_CONN
	table.take(table.room.rejoin(RECONNECT_CONN, PvpTable.JOIN_ID, table.now_ms))
	var kinds: Array[String] = []
	for at: int in range(mark, table.sent.size()):
		var entry: PvpTable.Sent = table.sent[at]
		kinds.append(entry.kind)
		_scan_text(run, entry, where)
		if entry.kind != NetProtocol.T_RESYNC:
			continue
		if entry.conn != RECONNECT_CONN:
			run.leaks.append(where + ": resync sent to %d" % entry.conn)
		var sent_events: Array = entry.message.get(NetProtocol.KEY_EVENTS, [])
		if _text(sent_events) != _text(history[1]):
			run.leaks.append(where + ": resync history differs from the scanned history")
		_scan_view(run, entry, 1, after, where)
	var expected: Array[String] = [
		NetProtocol.T_OPPONENT, NetProtocol.T_OPPONENT, NetProtocol.T_RESYNC
	]
	if kinds != expected:
		run.leaks.append(where + ": sent %s" % [kinds])


func _plain(events: Array[MatchEvent]) -> Array:
	var out: Array = []
	for event: MatchEvent in events:
		out.append(event.to_dict())
	return out


## JSON text with sorted keys, so a to_dict() form and its decoded copy compare equal.
func _text(value: Variant) -> String:
	return JSON.stringify(value, "", true)
