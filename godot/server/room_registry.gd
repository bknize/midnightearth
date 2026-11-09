class_name RoomRegistry
extends RefCounted
## The live rooms by code (cycle 12 plan P4, P10; spec R12, R13, R38, R39). Pure: no node,
## no clock; the caller passes `now_ms` (Unix ms, UTC) and injects the RandomNumberGenerator
## that draws room codes and, with the shipped engine factory, match seeds (P11: `randi() &
## 0x7FFFFFFF`, never 0). At most MAX_ROOMS live rooms; a closed room leaves the registry
## at the next create_room() or tick() and its code is free again. take_closed() hands the
## server every room that left, so it can write its last log and unbind its connections.

const MAX_ROOMS: int = 8
const SEED_MASK: int = 0x7FFFFFFF
## R27: this many wrong room codes from one address within MISS_WINDOW_MS start a cooling
## period of COOLING_MS, in which that address's join attempts are refused.
const MAX_MISSES: int = 5
const MISS_WINDOW_MS: int = 60000
const COOLING_MS: int = 60000

## Written into each new room (MatchRoom.stamp, build, the windows, allowed_decks).
var stamp: String = ""
var build: String = ""
var expiry_ms: int = MatchRoom.ROOM_EXPIRY_MS
var reconnect_window_ms: int = MatchRoom.RECONNECT_WINDOW_MS
var linger_ms: int = MatchRoom.FINISHED_LINGER_MS
var allowed_decks: Array[String] = []

var _rng: RandomNumberGenerator = null
## func(deck_ids: Array[String]) -> MatchEngine, given to every room.
var _engine_factory: Callable = Callable()
## The shipped factory's object. A Callable does not keep its object alive, so the
## registry holds it; without this the factory was freed when create() returned and every
## room failed at its start.
var _shipped: ShippedEngines = null
var _rooms: Dictionary[String, MatchRoom] = {}
var _closed: Array[MatchRoom] = []
## Per address: when its recent wrong codes were typed (ms, oldest first).
var _misses: Dictionary[String, Array] = {}
## Per address: when its cooling period ends (ms).
var _cooling_until: Dictionary[String, int] = {}


## A registry drawing codes from `rng`. `engine_factory` builds each room's engine; when
## it is not valid the registry plays the shipped pool, deck list and Crew pool on a seed
## drawn from `rng`, and allows only the shipped deck ids.
static func create(
	rng: RandomNumberGenerator, engine_factory: Callable = Callable()
) -> RoomRegistry:
	var registry: RoomRegistry = RoomRegistry.new()
	registry._rng = rng
	if engine_factory.is_valid():
		registry._engine_factory = engine_factory
	else:
		registry._shipped = ShippedEngines.load_with(rng)
		registry._engine_factory = registry._shipped.make
		registry.allowed_decks = registry._shipped.deck_ids()
	return registry


## A new WAITING room under a fresh code, created at `now_ms`; null when MAX_ROOMS rooms
## are live (the server refuses `server_full`, R38) or no free code was drawn.
func create_room(now_ms: int) -> MatchRoom:
	_sweep()
	if _rooms.size() >= MAX_ROOMS:
		return null
	var code: String = RoomCodes.fresh(_rng, _rooms)
	if code == "":
		return null
	var room: MatchRoom = MatchRoom.create(code, _engine_factory, now_ms)
	room.stamp = stamp
	room.build = build
	room.expiry_ms = expiry_ms
	room.reconnect_window_ms = reconnect_window_ms
	room.linger_ms = linger_ms
	room.allowed_decks.assign(allowed_decks)
	_rooms[code] = room
	return room


## The live room under `typed_code`, whatever its letter case (R12); null when none.
func room_of(typed_code: String) -> MatchRoom:
	var code: String = RoomCodes.normalized(typed_code)
	if not _rooms.has(code):
		return null
	var room: MatchRoom = _rooms[code]
	if room.is_closed():
		return null
	return room


## Every room's timers at `now_ms` (MatchRoom.tick), their messages in room order; rooms
## closed by now leave the registry.
func tick(now_ms: int) -> Array[MatchRoom.Outbound]:
	var out: Array[MatchRoom.Outbound] = []
	for code: String in _rooms:
		var room: MatchRoom = _rooms[code]
		out.append_array(room.tick(now_ms))
	_sweep()
	_forget_old_misses(now_ms)
	return out


## Whether `address` is cooling off at `now_ms` after too many wrong room codes (R27): its
## join attempts are refused whatever the code.
func is_cooling(address: String, now_ms: int) -> bool:
	if not _cooling_until.has(address):
		return false
	return now_ms < _cooling_until[address]


## Records a wrong room code from `address` at `now_ms`; true when this miss is the one that
## starts its cooling period (MAX_MISSES within MISS_WINDOW_MS).
func note_miss(address: String, now_ms: int) -> bool:
	var times: Array[int] = []
	var earlier: Array[int] = []
	if _misses.has(address):
		earlier.assign(_misses[address])
	for at: int in earlier:
		if now_ms - at < MISS_WINDOW_MS:
			times.append(at)
	times.append(now_ms)
	if times.size() >= MAX_MISSES:
		if not _misses.erase(address):
			push_warning("RoomRegistry: no misses of %s to clear" % address)
		_cooling_until[address] = now_ms + COOLING_MS
		return true
	_misses[address] = times
	return false


## The rooms that left the registry since the last call, in order.
func take_closed() -> Array[MatchRoom]:
	var out: Array[MatchRoom] = []
	out.assign(_closed)
	_closed.clear()
	return out


## Forgets the rooms that left the registry (a take_closed() whose result is not wanted).
func clear_closed() -> void:
	_closed.clear()


## Live rooms (closed ones not yet swept excluded).
func room_count() -> int:
	var count: int = 0
	for code: String in _rooms:
		if not _rooms[code].is_closed():
			count += 1
	return count


## The codes of the live rooms.
func codes() -> Array[String]:
	var out: Array[String] = []
	for code: String in _rooms:
		if not _rooms[code].is_closed():
			out.append(code)
	return out


## Drops the misses older than the window and the cooling periods that have ended, so a
## scan from many addresses does not grow the tables for ever.
func _forget_old_misses(now_ms: int) -> void:
	if _misses.is_empty() and _cooling_until.is_empty():
		return
	var stale: Array[String] = []
	for address: String in _misses:
		var times: Array = _misses[address]
		var newest: int = times[times.size() - 1]
		if now_ms - newest >= MISS_WINDOW_MS:
			stale.append(address)
	for address: String in stale:
		if not _misses.erase(address):
			push_warning("RoomRegistry: misses of %s already gone" % address)
	var ended: Array[String] = []
	for address: String in _cooling_until:
		if now_ms >= _cooling_until[address]:
			ended.append(address)
	for address: String in ended:
		if not _cooling_until.erase(address):
			push_warning("RoomRegistry: cooling of %s already gone" % address)


## Moves every closed room out of the registry, freeing its code.
func _sweep() -> void:
	var gone: Array[String] = []
	for code: String in _rooms:
		if _rooms[code].is_closed():
			gone.append(code)
	for code: String in gone:
		_closed.append(_rooms[code])
		if not _rooms.erase(code):
			push_warning("RoomRegistry: room %s already gone" % code)


## The shipped data and a seed source: the default engine factory. Its own object, so the
## rooms' Callable does not hold the registry (no reference cycle).
class ShippedEngines:
	extends RefCounted

	var _rng: RandomNumberGenerator = null
	var _cards: CardDb = null
	var _decks: DeckList = null
	var _crew: CrewPool = null

	static func load_with(rng: RandomNumberGenerator) -> ShippedEngines:
		var out: ShippedEngines = ShippedEngines.new()
		out._rng = rng
		out._cards = CardDb.load_default()
		out._decks = DeckList.load_default()
		out._crew = CrewPool.load_default()
		return out

	## A match on `deck_ids` (seat 0's first) on a fresh seed, not started.
	func make(deck_ids: Array[String]) -> MatchEngine:
		return MatchEngine.create(next_seed(), _cards, _decks, deck_ids, _crew)

	## `randi() & SEED_MASK`, redrawn while 0 (P11).
	func next_seed() -> int:
		var drawn: int = 0
		while drawn == 0:
			drawn = _rng.randi() & RoomRegistry.SEED_MASK
		return drawn

	func deck_ids() -> Array[String]:
		if _decks == null or not _decks.is_valid():
			var none: Array[String] = []
			return none
		return _decks.ids()
