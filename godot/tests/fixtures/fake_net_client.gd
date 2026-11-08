class_name FakeNetClient
extends NetClient
## A NetClient with no socket (cycle 12 T06, shared since T09): records what a source opens,
## sends and closes; server text is fed through NetClient.receive_text, so every message
## crosses NetCodec both ways. Used by test_remote_match_source.gd and test_bot_client.gd.

var opened: Array[String] = []
var sent: Array[String] = []
var closes: int = 0
var up: bool = false


func open(address: String) -> void:
	opened.append(address)
	up = false


func is_open() -> bool:
	return up


func send(message: Dictionary) -> bool:
	if not up:
		return false
	var text: String = NetCodec.encode(message)
	if text == "":
		return false
	sent.append(text)
	return true


func close() -> void:
	closes += 1
	up = false


## The connection comes up.
func accept() -> void:
	up = true
	connected.emit()


## The connection fails or closes under the source.
func drop(reason: String) -> void:
	up = false
	dropped.emit(reason)


## The last message the source sent, decoded; {} when none.
func last_sent() -> Dictionary:
	if sent.is_empty():
		return {}
	return NetCodec.decode(sent[sent.size() - 1])


func last_kind() -> String:
	var last: Dictionary = last_sent()
	var kind: String = last.get(NetProtocol.KEY_T, "")
	return kind
