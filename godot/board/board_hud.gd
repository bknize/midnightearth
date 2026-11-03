class_name BoardHud
extends CanvasLayer
## The board's 2D overlay (R10, R14, R16, R40, R42, R43). Pure view: setters in, button
## signals out. No engine calls, and no Escape handling (the board owns that). Button
## signals are wired in board_hud.tscn. The HUD must be in the tree before any setter runs.

signal commit_pressed
signal pause_pressed
signal concede_pressed
signal resume_pressed
signal rematch_pressed

const PIPS_PER_SEAT: int = 4
const PIP_ON: Color = Color(0.95, 0.78, 0.25, 1.0)
const PIP_OFF: Color = Color(0.2, 0.22, 0.3, 1.0)
const FLASH_COLOR: Color = Color(1.0, 0.25, 0.25, 1.0)
const FLASH_SECONDS: float = 0.45

var _energy_tween: Tween

var _score_labels: Array[Label] = []
var _pip_rows: Array[HBoxContainer] = []

@onready var _score_label_0: Label = %ScoreLabel0
@onready var _score_label_1: Label = %ScoreLabel1
@onready var _pips_0: HBoxContainer = %Pips0
@onready var _pips_1: HBoxContainer = %Pips1
@onready var _round_label: Label = %RoundLabel
@onready var _turn_label: Label = %TurnLabel
@onready var _energy_label: Label = %EnergyLabel
@onready var _commit_button: Button = %CommitButton
@onready var _pause_menu: Control = %PauseMenu
@onready var _result_panel: Control = %ResultPanel
@onready var _result_title: Label = %ResultTitle
@onready var _result_wins: Label = %ResultWins
@onready var _result_reason: Label = %ResultReason


func _ready() -> void:
	_score_labels.append(_score_label_0)
	_score_labels.append(_score_label_1)
	_pip_rows.append(_pips_0)
	_pip_rows.append(_pips_1)


func set_scores(scores: Array[int]) -> void:
	for seat: int in range(mini(scores.size(), _score_labels.size())):
		_score_labels[seat].text = str(scores[seat])


func set_wins(wins: Array[int]) -> void:
	for seat: int in range(mini(wins.size(), _pip_rows.size())):
		var row: HBoxContainer = _pip_rows[seat]
		for i: int in range(mini(PIPS_PER_SEAT, row.get_child_count())):
			var pip: ColorRect = row.get_child(i) as ColorRect
			pip.color = PIP_ON if i < wins[seat] else PIP_OFF


func set_round_turn(round_number: int, turn: int, sudden_death: bool) -> void:
	_round_label.text = "Round %d" % round_number
	if sudden_death:
		_turn_label.text = "Turn %d - Sudden death" % turn
	else:
		_turn_label.text = "Turn %d" % turn


func set_energy(left: int, total: int) -> void:
	_energy_label.text = "Energy %d / %d" % [left, total]


func flash_energy() -> void:
	if _energy_tween != null and _energy_tween.is_valid():
		_energy_tween.kill()
	_energy_label.modulate = FLASH_COLOR
	_energy_tween = create_tween()
	var step: PropertyTweener = _energy_tween.tween_property(
		_energy_label, "modulate", Color.WHITE, FLASH_SECONDS
	)
	step = step.set_ease(Tween.EASE_OUT)


func set_commit_label(has_staged: bool) -> void:
	_commit_button.text = "Commit" if has_staged else "Pass"


func set_commit_enabled(enabled: bool) -> void:
	_commit_button.disabled = not enabled


func show_pause(shown: bool) -> void:
	_pause_menu.visible = shown


func show_result(winner: int, wins: Array[int], reason: String) -> void:
	if winner == 0:
		_result_title.text = "You win"
	elif winner == 1:
		_result_title.text = "Opponent wins"
	else:
		_result_title.text = "Draw"
	var you: int = wins[0] if wins.size() > 0 else 0
	var them: int = wins[1] if wins.size() > 1 else 0
	_result_wins.text = "Rounds won: You %d - %d Opponent" % [you, them]
	_result_reason.text = reason
	_result_panel.visible = true


func hide_result() -> void:
	_result_panel.visible = false


func _on_commit_button_pressed() -> void:
	commit_pressed.emit()


func _on_pause_button_pressed() -> void:
	pause_pressed.emit()


func _on_resume_button_pressed() -> void:
	resume_pressed.emit()


func _on_concede_button_pressed() -> void:
	concede_pressed.emit()


func _on_rematch_button_pressed() -> void:
	rematch_pressed.emit()
