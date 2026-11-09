class_name RefineStyle
extends RefCounted
## The look of refinement (RefineRules, docs/refinement_konzept.md): one colour for each of the three tiers (steel +1..+5, teal +6..+10, gold +11..+15), the row of fifteen
## pearls with a gap after every five, and the little "+7" badge of a slot. Tooltip, slot and (later) Torben's window use it.

const STEEL: Color = Color("b9c6de")
const TEAL: Color = Color("7fe3da")
const GOLD: Color = Color("ffd98a")
const EMPTY: Color = Color("4a2d82")
const PEARL_STRIDE: int = 4
const GAP: int = 2


## The colour of a level: steel, teal, gold (level 0 and below: dim).
static func color(level: int) -> Color:
	if level <= 0:
		return UiStyle.TEXT_DIM
	return [STEEL, TEAL, GOLD][RefineRules.tier_index(level)] as Color


## Width in px of the pearl row.
static func pearls_width() -> int:
	var count: int = RefineRules.max_level()
	return count * PEARL_STRIDE - 1 + (count - 1) / RefineRules.TIER_SIZE * GAP


## The fifteen pearls: lit up to `level` (each in the colour of its own tier), empty up to the weapon's `cap`, beyond it only a tiny dim dot (that weapon cannot go further).
## At the last level the whole row breathes.
static func draw_pearls(canvas: CanvasItem, at: Vector2, level: int, cap: int, fade: float, time: float) -> void:
	for k: int in RefineRules.max_level():
		var x: float = at.x + k * PEARL_STRIDE + (k / RefineRules.TIER_SIZE) * GAP
		var spot: Vector2 = Vector2(x, at.y)
		if k < level:
			var tone: Color = color(k + 1)
			if level >= RefineRules.max_level():
				tone = tone.lightened(0.18 + 0.18 * sin(time * 3.0 - k * 0.45))
			canvas.draw_rect(Rect2(spot, Vector2(3, 3)), Color(tone, fade))
			canvas.draw_rect(Rect2(spot, Vector2.ONE), Color(VineStyle.PETAL, fade * 0.85))
		elif k < cap:
			canvas.draw_rect(Rect2(spot, Vector2(3, 3)), Color(EMPTY, fade * 0.85))
		else:
			canvas.draw_rect(Rect2(spot + Vector2.ONE, Vector2.ONE), Color(EMPTY, fade * 0.6))


## "+7" in the colour of the level, bottom right of a slot or icon.
static func draw_badge(canvas: CanvasItem, level: int, right: int, bottom: int) -> void:
	if level <= 0:
		return
	var label: String = "+%d" % level
	PixelText.draw(canvas, label, Vector2i(right - PixelText.width(label), bottom - PixelText.HEIGHT), color(level), UiStyle.OUTLINE)
