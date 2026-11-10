class_name TestBoardCardGlow
extends GdUnitTestSuite
## B-19: a glowing card's face text draws after its glow, and a selected card glows a
## different colour from an eligible one. Also the LOOK mark (DC-14 T15).

const CARD_SCENE: PackedScene = preload("res://board/board_card.tscn")


func _card() -> BoardCard:
	var card: BoardCard = CARD_SCENE.instantiate() as BoardCard
	auto_free(card)
	add_child(card)
	return card


func _source() -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.45, 0.18)
	return mat


func _glow_material(card: BoardCard) -> StandardMaterial3D:
	var glow: MeshInstance3D = card.get_node("Glow") as MeshInstance3D
	return glow.material_override as StandardMaterial3D


func test_the_face_text_draws_after_the_glow() -> void:
	var card: BoardCard = _card()
	card.set_glow(_source(), 0.4)
	var name_label: Label3D = card.get_node("CardMesh/NameLabel") as Label3D
	var text_label: Label3D = card.get_node("CardMesh/TextLabel") as Label3D
	var glow_priority: int = _glow_material(card).render_priority
	assert_int(name_label.render_priority).is_greater(glow_priority)
	assert_int(text_label.render_priority).is_greater(glow_priority)
	card.clear_glow()
	assert_int(name_label.render_priority).is_equal(0)


func test_a_selected_card_glows_a_different_colour_and_stronger() -> void:
	var card: BoardCard = _card()
	card.set_glow(_source(), PromptHost.GLOW_ALPHA)
	var eligible: Color = _glow_material(card).albedo_color
	card.set_selected(true)
	card.set_glow(_source(), PromptHost.SELECTED_GLOW_ALPHA)
	var chosen: Color = _glow_material(card).albedo_color
	assert_bool(chosen.is_equal_approx(eligible)).is_false()
	assert_float(chosen.a).is_greater(eligible.a)
	assert_float(chosen.g - chosen.r).is_greater(0.3)
	card.set_selected(false)
	card.set_glow(_source(), PromptHost.GLOW_ALPHA)
	assert_bool(_glow_material(card).albedo_color.is_equal_approx(eligible)).is_true()


func test_the_look_mark_shows_and_clears() -> void:
	var card: BoardCard = _card()
	assert_bool(card.has_look_mark()).is_false()
	card.set_look_mark(true)
	assert_bool(card.has_look_mark()).is_true()
	card.clear_def()
	assert_bool(card.has_look_mark()).is_false()
