class_name BoardGlow
extends RefCounted
## The drop-zone panels' looks (R12-R14), split out of Board: gold at rest, brighter on hover,
## red where the row would refuse the dragged card. Pure view code: it only sets a material.

enum Look { IDLE, HOVER, REFUSE }

const GOLD: Color = Color(1.0, 0.85, 0.45)
const RED: Color = Color(0.95, 0.25, 0.2)
const IDLE_ALPHA: float = 0.18
const HOVER_ALPHA: float = 0.35


## Shows the panel `glow` in `look`.
static func show(glow: MeshInstance3D, look: Look) -> void:
	var mat: StandardMaterial3D = glow.material_override as StandardMaterial3D
	var colour: Color = GOLD
	var alpha: float = IDLE_ALPHA
	if look == Look.HOVER:
		alpha = HOVER_ALPHA
	elif look == Look.REFUSE:
		colour = RED
		alpha = HOVER_ALPHA
	mat.albedo_color = Color(colour, alpha)
	glow.visible = true
