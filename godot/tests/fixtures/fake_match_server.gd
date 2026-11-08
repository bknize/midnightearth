class_name FakeMatchServer
extends RefCounted
## The match server reduced to one seat's wire (cycle 12 T06, shared since T09): a real
## engine, the other seat played by a random bot, and only `seat`'s redacted events and view
## sent through a FakeNetClient. Used by test_remote_match_source.gd and test_bot_client.gd.

const OPPONENT: String = "Ana"

var engine: MatchEngine = null
var client: FakeNetClient = null
var seat: int = 0
var history: Array[MatchEvent] = []
var other_bot: BotPlayer = null
## False once a message failed to encode (the suites assert it stays true).
var wire_ok: bool = true


func send(message: Dictionary) -> void:
	var text: String = NetCodec.encode(message)
	if text == "":
		wire_ok = false
		return
	client.receive_text(text)


func welcome() -> void:
	send(
		{
			NetProtocol.KEY_T: NetProtocol.T_WELCOME,
			NetProtocol.KEY_PROTOCOL: NetProtocol.VERSION,
			NetProtocol.KEY_STAMP: BotStamp.current(),
		}
	)


func start() -> void:
	var result: ApplyResult = engine.start()
	var events: Array[MatchEvent] = result.events_for(seat)
	history.append_array(events)
	var decks: Array[String] = engine.deck_ids()
	send(
		{
			NetProtocol.KEY_T: NetProtocol.T_STARTED,
			NetProtocol.KEY_SEAT: seat,
			NetProtocol.KEY_OPPONENT:
			{NetProtocol.KEY_NAME: OPPONENT, NetProtocol.KEY_DECK: decks[1 - seat]},
			NetProtocol.KEY_DECKS: decks,
			NetProtocol.KEY_VIEW: engine.view_for(seat).to_dict(),
			NetProtocol.KEY_EVENTS: plain(events),
		}
	)


## Applies `action` with its seat forced to `from` (R34); sends `events` or `rejected`.
func apply(action: EngineAction, from: int) -> ApplyResult:
	var forced: EngineAction = action.copy()
	forced.seat = from
	var result: ApplyResult = engine.apply(forced)
	if not result.ok:
		if from == seat:
			send(
				{
					NetProtocol.KEY_T: NetProtocol.T_REJECTED,
					NetProtocol.KEY_ERROR: EngineError.name_of(result.error),
					NetProtocol.KEY_ACTION: forced.to_dict(),
				}
			)
		return result
	var events: Array[MatchEvent] = result.events_for(seat)
	history.append_array(events)
	send(
		{
			NetProtocol.KEY_T: NetProtocol.T_EVENTS,
			NetProtocol.KEY_EVENTS: plain(events),
			NetProtocol.KEY_VIEW: engine.view_for(seat).to_dict(),
		}
	)
	return result


## The other seat's bot moves once.
func play_other() -> ApplyResult:
	var other: int = 1 - seat
	return apply(other_bot.choose(engine.view_for(other), engine), other)


## The act the client sent last, as an action; null when the last message was not one.
func take_act() -> EngineAction:
	var last: Dictionary = client.last_sent()
	var kind: String = last.get(NetProtocol.KEY_T, "")
	if kind != NetProtocol.T_ACT:
		return null
	return NetCodec.action_of(last)


func resync() -> void:
	send(
		{
			NetProtocol.KEY_T: NetProtocol.T_RESYNC,
			NetProtocol.KEY_EVENTS: plain(history),
			NetProtocol.KEY_VIEW: engine.view_for(seat).to_dict(),
		}
	)


static func plain(events: Array[MatchEvent]) -> Array:
	var out: Array = []
	for event: MatchEvent in events:
		out.append(event.to_dict())
	return out
