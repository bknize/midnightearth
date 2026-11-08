class_name TitleScreen
extends Control
## The title screen (cycle 12 spec R1 to R7): name, server address and room code fields, the
## consent line, and Play vs Bot / Host / Join. The identity is saved as the fields change.
## It only raises signals; Main owns the flow.

signal play_bot_pressed
signal host_pressed
## The typed room code, stripped and upper-cased, never empty.
signal join_pressed(code: String)

const CONSENT_LINE: String = "PVP matches are recorded to improve the game."
const NEED_CODE_MESSAGE: String = "Type a room code to join."

var _identity: Identity = null

@onready var _name_field: LineEdit = %NameField
@onready var _server_field: LineEdit = %ServerField
@onready var _code_field: LineEdit = %CodeField
@onready var _message: Label = %Message
@onready var _consent: Label = %Consent
@onready var _bot_button: Button = %BotButton
@onready var _host_button: Button = %HostButton
@onready var _join_button: Button = %JoinButton


func _ready() -> void:
	_consent.text = CONSENT_LINE
	_connect_signals()


## Fills the fields from `identity`. `server_override` (from `--server=`) replaces the saved
## address for this run when not empty. Call once, with the screen in the tree.
func setup(identity: Identity, server_override: String = "") -> void:
	_identity = identity
	_name_field.text = identity.name
	_server_field.text = server_override if server_override != "" else identity.server


## Shows a line under the buttons (a refusal or a connection failure); "" clears it.
func show_message(text: String) -> void:
	_message.text = text


## The typed room code, stripped and upper-cased ("" when empty).
func room_code() -> String:
	return _code_field.text.strip_edges().to_upper()


## The address in the server field, stripped.
func server_address() -> String:
	return _server_field.text.strip_edges()


## The name field's current text after the trim rule.
func player_name() -> String:
	return Identity.normalize_name(_name_field.text)


func _connect_signals() -> void:
	var errors: Array[int] = [
		_name_field.text_changed.connect(_on_name_changed),
		_server_field.text_changed.connect(_on_server_changed),
		_bot_button.pressed.connect(_on_bot_pressed),
		_host_button.pressed.connect(_on_host_pressed),
		_join_button.pressed.connect(_on_join_pressed),
	]
	if errors.has(ERR_INVALID_PARAMETER) or errors.has(ERR_UNAVAILABLE):
		push_warning("TitleScreen: could not connect a control")


func _on_name_changed(_text: String) -> void:
	_save()


func _on_server_changed(_text: String) -> void:
	_save()


## Stores the fields in the identity. The name field keeps what the player typed; the stored
## name is the trimmed one (R3).
func _save() -> void:
	if _identity == null:
		return
	var stored_name: String = _identity.set_name(_name_field.text)
	var stored_server: String = _identity.set_server(_server_field.text)
	if stored_name == "" or stored_server == "":
		return
	_identity.save()


func _on_bot_pressed() -> void:
	_save()
	play_bot_pressed.emit()


func _on_host_pressed() -> void:
	_save()
	host_pressed.emit()


func _on_join_pressed() -> void:
	_save()
	var code: String = room_code()
	if code == "":
		show_message(NEED_CODE_MESSAGE)
		return
	join_pressed.emit(code)
