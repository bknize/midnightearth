class_name PvpTable
extends RefCounted
## A MatchRoom with two fake clients on a fake clock (cycle 12 T03): the suites call the
## room as the server would and every Outbound goes through NetCodec.encode() and decode(),
## so what the suites read is what a socket would carry. Each seat plays the random bot from
## the last view it received, so the room is driven by its own messages alone.

const HOST_CONN: int = 101
const JOIN_CONN: int = 202
## 2026-11-07T21:45:12Z in Unix milliseconds.
const T0_MS: int = 1794087912000
const HOST_ID: Dictionary = {"name": "Ana", "install_id": "install-ana", "kind": "human"}
const JOIN_ID: Dictionary = {"name": "bot:random", "install_id": "install-bot", "kind": "bot"}
const MAX_ACTIONS: int = 2000

var room: MatchRoom = null
var maker: EngineMaker = null
## The connection each seat holds now (a suite updates it on a rejoin).
var conns: Array[int] = [HOST_CONN, JOIN_CONN]
var now_ms: int = T0_MS
## Every message sent, in order.
var sent: Array[Sent] = []
## Each seat's last view and every event dict it received in `started` and `events`.
var views: Array[SeatView] = [null, null]
var events: Array[Array] = [[], []]
## Kinds of messages NetCodec refused to encode or decode.
var unencodable: Array[String] = []
var bots: Array[BotPlayer] = []


## A table whose room builds its engine on `match_seed` from the shipped data.
static func create(match_seed: int) -> PvpTable:
	var table: PvpTable = PvpTable.new()
	table.maker = EngineMaker.new()
	table.maker.match_seed = match_seed
	table.room = MatchRoom.create("K7QX", table.maker.make, T0_MS)
	table.room.stamp = "r7-0123456789abcdef"
	table.room.build = "test-build"
	return table


func host(deck: String = "greed") -> Array[Sent]:
	return take(room.host(HOST_CONN, HOST_ID, deck, now_ms))


func join(deck: String = "ramp") -> Array[Sent]:
	return take(room.join(JOIN_CONN, JOIN_ID, deck, now_ms))


## Hosted and joined: the match is running.
func start() -> void:
	host()
	join()


func act(seat: int, action: EngineAction) -> Array[Sent]:
	return take(room.act(conns[seat], action, now_ms))


## Records `out` (encoded and decoded) and returns its entries.
func take(out: Array[MatchRoom.Outbound]) -> Array[Sent]:
	var taken: Array[Sent] = []
	for outbound: MatchRoom.Outbound in out:
		var entry: Sent = Sent.new()
		entry.conn = outbound.connection_id
		entry.text = NetCodec.encode(outbound.message)
		entry.message = NetCodec.decode(entry.text)
		var kind: String = outbound.message.get(NetProtocol.KEY_T, "?")
		if entry.text == "" or entry.message.is_empty():
			unencodable.append(kind)
		entry.kind = kind
		_keep(entry)
		sent.append(entry)
		taken.append(entry)
	return taken


## The seat awaited according to the views the seats received; -1 when none.
func awaited_seat() -> int:
	for seat: int in range(MatchEngine.SEATS):
		if views[seat] != null and views[seat].is_awaited():
			return seat
	return -1


## The bot's action for `seat` from its last view.
func bot_action(seat: int) -> EngineAction:
	if bots.is_empty():
		var engine: MatchEngine = maker.engine
		for bot_seat: int in range(MatchEngine.SEATS):
			var bot_seed: int = BotRegistry.seed_for(maker.match_seed, bot_seat)
			bots.append(BotRegistry.make("random", bot_seed, engine.match_cards()))
	return bots[seat].choose(views[seat], null)


## Plays the awaited seat's bot action; false when no seat is awaited or the room
## answered it with anything but `events`.
func play_one() -> bool:
	var seat: int = awaited_seat()
	if seat < 0:
		return false
	for entry: Sent in act(seat, bot_action(seat)):
		if entry.kind != NetProtocol.T_EVENTS:
			return false
	return true


## Plays bot actions until no seat is awaited (the match ended) or MAX_ACTIONS; the count.
func play_to_end() -> int:
	var played: int = 0
	while played < MAX_ACTIONS and play_one():
		played += 1
	return played


## Every message sent to `conn`, in order.
func to_conn(conn: int) -> Array[Sent]:
	var out: Array[Sent] = []
	for entry: Sent in sent:
		if entry.conn == conn:
			out.append(entry)
	return out


func _keep(entry: Sent) -> void:
	var seat: int = conns.find(entry.conn)
	if seat < 0 or entry.message.is_empty():
		return
	if entry.kind == NetProtocol.T_STARTED or entry.kind == NetProtocol.T_EVENTS:
		var listed: Variant = entry.message.get(NetProtocol.KEY_EVENTS, [])
		if listed is Array:
			var dicts: Array = listed
			events[seat].append_array(dicts)
	var view: SeatView = NetCodec.view_of(entry.message)
	if view != null:
		views[seat] = view


## One message to one connection: its JSON text and what NetCodec decoded from it.
class Sent:
	extends RefCounted

	var conn: int = -1
	var kind: String = ""
	var text: String = ""
	var message: Dictionary = {}


## The room's engine factory over the shipped data on a fixed seed; it keeps the engine it
## built so a suite can read the full state (never sent anywhere).
class EngineMaker:
	extends RefCounted

	var match_seed: int = 1
	var engine: MatchEngine = null

	func make(deck_ids: Array[String]) -> MatchEngine:
		engine = MatchEngine.create(
			match_seed,
			CardDb.load_default(),
			DeckList.load_default(),
			deck_ids,
			CrewPool.load_default()
		)
		return engine
