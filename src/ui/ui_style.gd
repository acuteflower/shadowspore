class_name UiStyle
extends RefCounted
## Shared look of the UI: dark violet panels with a cool teal accent (the scarf color).

const OUTLINE: Color = Color("1b1a2e")
const PANEL: Color = Color("2a2548")
const PANEL_DARK: Color = Color("1e1a36")
const RIM: Color = Color("4a4180")
const SLOT_BG: Color = Color("171329")
const TEXT: Color = Color("e8e4f4")
const TEXT_DIM: Color = Color("8a84ad")
const ACCENT: Color = Color("7fe3da")


## Framed panel: outline, rim, fill and a highlight line along the top.
static func draw_panel(canvas: CanvasItem, rect: Rect2) -> void:
	canvas.draw_rect(rect, OUTLINE)
	canvas.draw_rect(rect.grow(-1), RIM)
	canvas.draw_rect(rect.grow(-2), PANEL)
	canvas.draw_rect(Rect2(rect.position + Vector2(2, 2), Vector2(rect.size.x - 4, 1)), RIM.lightened(0.15))
