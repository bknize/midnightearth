class_name DeckPicker
extends Control
## The deck picker shown before a match (R39-R43, plan P15): a "You" column and a "Bot"
## column, one tile Button per deck showing its name and one-line theme, and Start. No
## card-list reader (C16). The pure pick state lives in DeckPickState.

## Emitted by Start with the two picked deck ids, You then Bot.
signal picked(deck_ids: Array[String])

const COLUMN_TITLES: Array[String] = ["You", "Bot"]
## A tile's minimum width; its text wraps rather than grow the column.
const TILE_MIN_WIDTH: float = 240.0

var _state: DeckPickState = DeckPickState.new()
var _columns_count: int = DeckPickState.COLUMNS
var _titles: Array[String] = COLUMN_TITLES
var _decks: DeckList = null
## Tile buttons by column, then in deck order.
var _tiles: Array[Array] = [[], []]

@onready var _columns: HBoxContainer = %Columns
@onready var _start_button: Button = %StartButton


func _ready() -> void:
	var err: int = _start_button.pressed.connect(_on_start_pressed)
	if err != OK:
		push_warning("DeckPicker: could not connect Start")


## Builds the tiles for `decks` and preselects `preselected` (You, Bot). Call once, with the
## picker in the tree. `columns` defaults to the two PVE columns; PVP passes one column, its
## title ("Your deck") and its start label ("Host" or "Join"). A missing title falls back to
## "Deck".
func setup(
	decks: DeckList,
	preselected: Array[String],
	columns: int = DeckPickState.COLUMNS,
	titles: Array[String] = COLUMN_TITLES,
	start_label: String = "Start"
) -> void:
	_decks = decks
	_columns_count = maxi(columns, 1)
	_titles = titles
	_start_button.text = start_label
	_state.setup(decks.ids(), preselected, _columns_count)
	for child: Node in _columns.get_children():
		child.queue_free()
	_tiles = []
	for _i: int in range(_columns_count):
		_tiles.append([])
	for column: int in range(_columns_count):
		_build_column(column)
	_refresh()


## The Start button, for node queries.
func start_button() -> Button:
	return _start_button


## The picks so far, You then Bot ("" for a column with none).
func current_picks() -> Array[String]:
	return _state.deck_ids()


func _build_column(column: int) -> void:
	var box: VBoxContainer = VBoxContainer.new()
	var column_title: String = _titles[column] if column < _titles.size() else "Deck"
	box.name = column_title
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	var title: Label = Label.new()
	title.text = column_title
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	box.add_child(title)
	for deck_id: String in _decks.ids():
		var entry: Dictionary = _decks.deck(deck_id)
		var deck_name: String = entry[DeckList.KEY_NAME]
		var theme_line: String = entry[DeckList.KEY_THEME]
		var tile: Button = Button.new()
		tile.name = deck_id
		tile.text = "%s\n%s" % [deck_name, theme_line]
		tile.toggle_mode = true
		# The theme line wraps inside the column instead of widening the picker past the
		# window (seen at T13: both columns ran off a 1280 px window).
		tile.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tile.custom_minimum_size = Vector2(TILE_MIN_WIDTH, 96)
		var err: int = tile.pressed.connect(_on_tile_pressed.bind(column, deck_id))
		if err != OK:
			push_warning("DeckPicker: could not connect tile %s" % deck_id)
		box.add_child(tile)
		_tiles[column].append(tile)
	_columns.add_child(box)


func _on_tile_pressed(column: int, deck_id: String) -> void:
	if not _state.pick(column, deck_id):
		push_warning("DeckPicker: refused pick %s for column %d" % [deck_id, column])
	_refresh()


## Marks each column's picked tile and enables Start.
func _refresh() -> void:
	var ids: Array[String] = _decks.ids()
	for column: int in range(_columns_count):
		var column_tiles: Array = _tiles[column]
		for i: int in range(column_tiles.size()):
			var tile: Button = column_tiles[i]
			tile.button_pressed = ids[i] == _state.picked_id(column)
	_start_button.disabled = not _state.can_start()


func _on_start_pressed() -> void:
	if _state.can_start():
		picked.emit(_state.deck_ids())
