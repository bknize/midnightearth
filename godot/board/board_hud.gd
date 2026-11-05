# gdlint: ignore=max-public-methods
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
signal decks_pressed
## The prompt reader's action button was pressed (R42).
signal action_pressed
## The multi-select prompt's confirm button was pressed (R48).
signal confirm_pressed
## The Skip button of an optional prompt was pressed (cycle 8 R63).
signal skip_pressed

const PIPS_PER_SEAT: int = 4
const PIP_ON: Color = Color(0.95, 0.78, 0.25, 1.0)
const PIP_OFF: Color = Color(0.2, 0.22, 0.3, 1.0)
const FLASH_COLOR: Color = Color(1.0, 0.25, 0.25, 1.0)
const FLASH_SECONDS: float = 0.45

var _energy_tween: Tween
## The prompt reader's button; built in code, present only while a prompt has a card lifted.
var _action_button: Button = null
## The multi-select confirm button, built in code; "Destroy N" while that prompt is open.
var _confirm_button: Button = null
## The confirm is out of sight while a card is lifted, so it never meets the action button.
var _confirm_suspended: bool = false
var _confirm_wanted: bool = false
## The Skip button of an optional prompt, built in code, where the confirm button sits.
var _skip_button: Button = null

var _score_labels: Array[Label] = []
var _destroyed_labels: Array[Label] = []
var _pip_rows: Array[HBoxContainer] = []
## The number each score label is heading for (what it shows once any count ends).
var _shown: Array[int] = [0, 0]
var _count_tweens: Array[Tween] = [null, null]

@onready var _score_label_0: Label = %ScoreLabel0
@onready var _score_label_1: Label = %ScoreLabel1
@onready var _destroyed_label_0: Label = %DestroyedLabel0
@onready var _destroyed_label_1: Label = %DestroyedLabel1
@onready var _pips_0: HBoxContainer = %Pips0
@onready var _pips_1: HBoxContainer = %Pips1
@onready var _round_label: Label = %RoundLabel
@onready var _turn_label: Label = %TurnLabel
@onready var _energy_label: Label = %EnergyLabel
@onready var _commit_button: Button = %CommitButton
@onready var _prompt_banner: PanelContainer = %PromptBanner
@onready var _prompt_text: Label = %PromptText
@onready var _pause_menu: Control = %PauseMenu
@onready var _result_panel: Control = %ResultPanel
@onready var _result_title: Label = %ResultTitle
@onready var _result_wins: Label = %ResultWins
@onready var _result_reason: Label = %ResultReason


func _ready() -> void:
	_score_labels.append(_score_label_0)
	_score_labels.append(_score_label_1)
	_destroyed_labels.append(_destroyed_label_0)
	_destroyed_labels.append(_destroyed_label_1)
	_pip_rows.append(_pips_0)
	_pip_rows.append(_pips_1)


func _show_score(seat: int, value: int) -> void:
	_shown[seat] = value
	_score_labels[seat].text = str(value)


func _set_score_text(value: float, seat: int) -> void:
	_score_labels[seat].text = str(roundi(value))


func _kill_count() -> void:
	for seat: int in range(_count_tweens.size()):
		var tween: Tween = _count_tweens[seat]
		if tween != null and tween.is_valid():
			tween.kill()
		_count_tweens[seat] = null


## The scores: the held totals, the previous turn's (R33). Stops any count in progress.
func set_scores(held: Array[int]) -> void:
	_kill_count()
	for seat: int in range(mini(held.size(), _score_labels.size())):
		_show_score(seat, held[seat])


## Steps `seat`'s score from the total on show to `total` over `seconds` (R34).
func count_to(seat: int, total: int, seconds: float) -> void:
	if seat < 0 or seat >= _score_labels.size():
		return
	if _count_tweens[seat] != null and _count_tweens[seat].is_valid():
		_count_tweens[seat].kill()
	var from: int = _shown[seat]
	_shown[seat] = total
	if seconds <= 0.0 or from == total:
		_score_labels[seat].text = str(total)
		return
	var tween: Tween = create_tween()
	var step: MethodTweener = tween.tween_method(
		_set_score_text.bind(seat), float(from), float(total), seconds
	)
	step = step.set_ease(Tween.EASE_OUT)
	_count_tweens[seat] = tween


## The screen position of `seat`'s score label (its centre), for the tally's fly-in.
func score_anchor(seat: int) -> Vector2:
	var label: Label = _score_labels[clampi(seat, 0, _score_labels.size() - 1)]
	return label.get_global_rect().get_center()


## The number on show for `seat`.
func shown_score(seat: int) -> int:
	return _shown[seat]


## The text of `seat`'s score label.
func score_label_text(seat: int) -> String:
	return _score_labels[seat].text


## Each side's destroyed-pile count (R46), seat 0 first.
func set_destroyed(counts: Array[int]) -> void:
	for seat: int in range(mini(counts.size(), _destroyed_labels.size())):
		_destroyed_labels[seat].text = "Destroyed %d" % counts[seat]


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


## The budget left of the turn's total (R49); `free_first` marks that the first card is free.
func set_energy(left: int, total: int, free_first: bool = false) -> void:
	_energy_label.text = "Energy %d / %d" % [left, total]
	if free_first:
		_energy_label.text += " - first card free"


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


## The prompt banner (R55): the open prompt's rules text, until hide_prompt().
func show_prompt(text: String) -> void:
	_prompt_text.text = text
	_prompt_banner.visible = true


func hide_prompt() -> void:
	_prompt_banner.visible = false
	_prompt_text.text = ""


## Shows the reader's action button (R40, R41), a plain Theme Button. `rect` is where it goes
## in viewport pixels, under the lifted card (CardLift.button_rect, NSC-85); an empty rect keeps
## it at the bottom centre.
func show_action(text: String, rect: Rect2 = Rect2()) -> void:
	if _action_button == null:
		_action_button = Button.new()
		_action_button.name = "ActionButton"
		_action_button.custom_minimum_size = Vector2(200.0, 64.0)
		var err: int = _action_button.pressed.connect(_on_action_button_pressed)
		if err != OK:
			push_warning("BoardHud: could not connect the action button")
		$Root.add_child(_action_button)
	if rect.size.x > 0.0:
		_action_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		_action_button.position = rect.position
		_action_button.size = rect.size
	else:
		_action_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		_action_button.offset_left = -100.0
		_action_button.offset_right = 100.0
		_action_button.offset_top = -110.0
		_action_button.offset_bottom = -46.0
	_action_button.text = text
	_action_button.visible = true


## Removes the action button from view (R47).
func hide_action() -> void:
	if _action_button != null:
		_action_button.visible = false


## Whether the action button is on show.
func action_visible() -> bool:
	return _action_button != null and _action_button.visible


## The action button's rect in viewport pixels, or an empty rect while it is not built.
func action_rect() -> Rect2:
	if _action_button == null:
		return Rect2()
	return _action_button.get_global_rect()


func _on_action_button_pressed() -> void:
	action_pressed.emit()


## Shows the multi-select confirm button with `text` ("Destroy 2"); calling it again updates
## the text (R48). A plain Theme Button above Commit.
func show_confirm(text: String) -> void:
	if _confirm_button == null:
		_confirm_button = Button.new()
		_confirm_button.name = "ConfirmButton"
		_confirm_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		_confirm_button.offset_left = -190.0
		_confirm_button.offset_right = -20.0
		_confirm_button.offset_top = -148.0
		_confirm_button.offset_bottom = -88.0
		var err: int = _confirm_button.pressed.connect(_on_confirm_button_pressed)
		if err != OK:
			push_warning("BoardHud: could not connect the confirm button")
		$Root.add_child(_confirm_button)
	_confirm_button.text = text
	_confirm_wanted = true
	_confirm_button.visible = not _confirm_suspended


func hide_confirm() -> void:
	_confirm_wanted = false
	_confirm_suspended = false
	if _confirm_button != null:
		_confirm_button.visible = false


## Hides the confirm button while a card is lifted, and brings it back after.
func set_confirm_suspended(suspended: bool) -> void:
	_confirm_suspended = suspended
	if _confirm_button != null:
		_confirm_button.visible = _confirm_wanted and not suspended


## The confirm button's text, or "" while there is none.
func confirm_text() -> String:
	return "" if _confirm_button == null else _confirm_button.text


func confirm_visible() -> bool:
	return _confirm_button != null and _confirm_button.visible


func _on_confirm_button_pressed() -> void:
	confirm_pressed.emit()


## Shows the optional prompt's Skip button (R63), a plain Theme Button at the confirm button's
## place; `above_confirm` lifts it one button higher when a multi-select confirm shares the
## spot.
func show_skip(above_confirm: bool = false) -> void:
	if _skip_button == null:
		_skip_button = Button.new()
		_skip_button.name = "SkipButton"
		_skip_button.text = "Skip"
		var err: int = _skip_button.pressed.connect(_on_skip_button_pressed)
		if err != OK:
			push_warning("BoardHud: could not connect the skip button")
		$Root.add_child(_skip_button)
	_skip_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	var lift: float = 68.0 if above_confirm else 0.0
	_skip_button.offset_left = -190.0
	_skip_button.offset_right = -20.0
	_skip_button.offset_top = -148.0 - lift
	_skip_button.offset_bottom = -88.0 - lift
	_skip_button.visible = true


func hide_skip() -> void:
	if _skip_button != null:
		_skip_button.visible = false


func skip_visible() -> bool:
	return _skip_button != null and _skip_button.visible


func _on_skip_button_pressed() -> void:
	skip_pressed.emit()


func show_pause(shown: bool) -> void:
	_pause_menu.visible = shown


## The end reason as a phrase for the result panel (R23).
static func reason_text(reason: String, winner: int, rounds: int) -> String:
	match reason:
		"wins":
			return "First to 4 round wins"
		"rounds":
			return "Most round wins after %d rounds" % rounds
		"sudden_death":
			return "Won in sudden death"
		"concede":
			return "You conceded" if winner == 1 else "Opponent conceded"
	push_warning("Unknown match end reason: %s" % reason)
	return reason


func show_result(winner: int, wins: Array[int], reason: String, rounds: int) -> void:
	if winner == 0:
		_result_title.text = "You win"
	elif winner == 1:
		_result_title.text = "Opponent wins"
	else:
		_result_title.text = "Draw"
	var you: int = wins[0] if wins.size() > 0 else 0
	var them: int = wins[1] if wins.size() > 1 else 0
	_result_wins.text = "Rounds won: You %d - %d Opponent" % [you, them]
	_result_reason.text = reason_text(reason, winner, rounds)
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


func _on_decks_button_pressed() -> void:
	decks_pressed.emit()
