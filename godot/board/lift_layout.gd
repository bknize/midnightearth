class_name LiftLayout
extends RefCounted
## Pure screen layout of the prompt reader (B-11, DC-06 plan P16): how big the lifted card
## stands and where the action button sits under it. All rects are in viewport pixels. The
## card is centred; with a button to place, the card shrinks until a button-high band under it
## fits inside the safe area, so the button never overlaps the card.

## The action button's size and the gap between the card and the button.
const BUTTON_SIZE: Vector2 = Vector2(200.0, 64.0)
const GAP: float = 12.0
## A lifted card stands no smaller than this share of the view height.
const MIN_FILL: float = 0.4
## The card's width over its height.
const CARD_ASPECT: float = 2.5 / 3.5


## The share of the view height the lifted card fills (height over view height). `base` is the
## fill with no button; `safe` is the safe area in viewport pixels.
static func fill_for(view: Vector2, safe: Rect2, base: float, with_button: bool) -> float:
	if not with_button or view.y <= 0.0:
		return base
	var room: float = safe.end.y - BUTTON_SIZE.y - GAP - view.y / 2.0
	var fit: float = 2.0 * room / view.y
	return clampf(minf(base, fit), MIN_FILL, base)


## The lifted card's rect on screen at `fill`.
static func card_rect(view: Vector2, fill: float) -> Rect2:
	var height: float = view.y * fill
	var size: Vector2 = Vector2(height * CARD_ASPECT, height)
	return Rect2((view - size) / 2.0, size)


## The action button's rect: centred under the card, and kept inside `safe`.
static func button_rect(view: Vector2, safe: Rect2, fill: float) -> Rect2:
	var card: Rect2 = card_rect(view, fill)
	var x: float = card.get_center().x - BUTTON_SIZE.x / 2.0
	var y: float = card.end.y + GAP
	x = clampf(x, safe.position.x, maxf(safe.position.x, safe.end.x - BUTTON_SIZE.x))
	y = minf(y, safe.end.y - BUTTON_SIZE.y)
	return Rect2(Vector2(x, y), BUTTON_SIZE)


## The safe area inside a viewport of `view` pixels, from the display's insets. `screen` is the
## display's size and `safe` its safe rect, both in the display's own pixels; with no display
## information the whole view is safe.
static func safe_rect(view: Vector2, screen: Vector2i, safe: Rect2i) -> Rect2:
	var whole: Rect2 = Rect2(Vector2.ZERO, view)
	if screen.x <= 0 or screen.y <= 0 or safe.size.x <= 0 or safe.size.y <= 0:
		return whole
	var scale: Vector2 = Vector2(view.x / float(screen.x), view.y / float(screen.y))
	var left: float = float(safe.position.x) * scale.x
	var top: float = float(safe.position.y) * scale.y
	var right: float = float(screen.x - safe.end.x) * scale.x
	var bottom: float = float(screen.y - safe.end.y) * scale.y
	var inset: Rect2 = Rect2(left, top, view.x - left - right, view.y - top - bottom)
	return whole.intersection(inset)
