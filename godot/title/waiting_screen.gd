class_name WaitingScreen
extends Control
## The host's waiting screen (cycle 12 spec R10): the room code in large type, "Waiting for
## opponent…", the server address in use, and Cancel. Main wires it in T09.

## Emitted by Cancel.
signal cancelled

const WAITING_TEXT: String = "Waiting for opponent…"

@onready var _code_label: Label = %CodeLabel
@onready var _waiting_label: Label = %WaitingLabel
@onready var _server_label: Label = %ServerLabel
@onready var _cancel_button: Button = %CancelButton


func _ready() -> void:
	_waiting_label.text = WAITING_TEXT
	var err: int = _cancel_button.pressed.connect(_on_cancel_pressed)
	if err != OK:
		push_warning("WaitingScreen: could not connect Cancel")


## Shows `code` and the server address in use.
func setup(code: String, server_address: String) -> void:
	_code_label.text = code
	_server_label.text = server_address


## The shown room code, for node queries.
func code_text() -> String:
	return _code_label.text


func _on_cancel_pressed() -> void:
	cancelled.emit()
