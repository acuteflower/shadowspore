class_name FishingHud
extends Control
## The little vine tags above the hotbar while a rod is in her hand: bait (Z), float (H) and one line of what the
## mouse does right now. No tension readout here: that is the colour of the line itself.

const GOLD: Color = Color("e6c468")
const TEXT: Color = Color("e8e4f4")
const DIM: Color = Color("8a84ad")
const TEAL: Color = Color("7fe3da")
const INK: Color = Color("1b1a2e")

var _p: Player
var _c: FishingComponent
var _show: float = 0.0


func bind(player: Node) -> void:
	_p = player as Player
	_c = _p.fishing
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	var hotbar: Control = get_parent().get_node_or_null("Hotbar") as Control
	var want: bool = _c != null and _c.rod_active() and hotbar != null and hotbar.visible and not InputManager.ui_blocking
	_show = move_toward(_show, 1.0 if want else 0.0, delta * 6.0)
	visible = _show > 0.01
	if visible:
		queue_redraw()


func _hint() -> String:
	var texts: Dictionary = {}
	match _c.state:
		FishingComponent.S.IDLE:
			match _c.aim_reason:
				"stand": return "GEH AN DAS UFER"
				"near": return "ZU NAH AM UFER"
				"land": return "ZIEL: OFFENES WASSER"
				"": return "KLICK: WERFEN"
			return ""
		FishingComponent.S.CASTING:
			return ""
		FishingComponent.S.DRIFTING:
			return "KLICK: ZUPFEN   HALTEN: SCHNUR GEBEN   RECHTS: EINHOLEN"
		FishingComponent.S.NIBBLE:
			return "RUHIG..."
		FishingComponent.S.BITE:
			return "JETZT: KLICK!"
		FishingComponent.S.DRILL:
			if _c.tell:
				return "ER ZIEHT GLEICH! NACHGEBEN"
			return "NACHGEBEN: ZUM FISCH GEHEN" if _c.phase == "flee" else "EINHOLEN: KLICK HALTEN"
	return String(texts.get("", ""))


func _draw() -> void:
	var hotbar: Control = get_parent().get_node_or_null("Hotbar") as Control
	var top: float = hotbar.get_global_rect().position.y if hotbar != null else size.y - 50.0
	var cx: float = roundf(size.x * 0.5)
	var a: float = _show
	var hint: String = _hint()
	if hint != "":
		var hw: int = PixelText.width(hint)
		var danger: bool = _c.state == FishingComponent.S.BITE or (_c.state == FishingComponent.S.DRILL and _c.tell)
		PixelText.draw(self, hint, Vector2i(int(cx) - hw / 2, int(top) - 52), Color(GOLD if danger else TEXT, a), Color(INK, a))
	if _c.state != FishingComponent.S.IDLE:
		return
	_tag(Rect2(cx - 150.0, top - 36.0, 84, 20), "Z", _bait_label(), a, true)
	_tag(Rect2(cx + 66.0, top - 36.0, 84, 20), "H", _pose_label(), a, false)


func _bait_label() -> String:
	if _c.bait == "":
		return "OHNE KÖDER"
	var name_text: String = String((DataRegistry.table("fishing")["baits"] as Dictionary)[_c.bait]["name"])
	return "%s X%d" % [name_text.left(8), _p.inventory.count_item(_c.bait)]


func _pose_label() -> String:
	return "POSE: " + String((FishingRules.poses()[_c.pose] as Dictionary)["name"])


func _tag(rect: Rect2, key: String, label: String, a: float, with_icon: bool) -> void:
	VineStyle.paper(self, rect, a, 0.0, key.unicode_at(0))
	var x: int = int(rect.position.x) + 6
	var y: int = int(rect.position.y) + 7
	draw_rect(Rect2(x, y - 2, 9, 9), Color("2a2548", a))
	draw_rect(Rect2(x, y - 2, 9, 1), Color("4a4180", a))
	PixelText.draw(self, key, Vector2i(x + 3, y), Color(TEAL, a))
	var text_x: int = x + 14
	if with_icon and _c.bait != "":
		var icon: Texture2D = Items.icon({"id": _c.bait, "count": 1})
		if icon != null:
			draw_texture_rect(icon, Rect2(x + 12, int(rect.position.y) + 2, 16, 16), false, Color(1, 1, 1, a))
			text_x = x + 30
	PixelText.draw(self, label.left(int((rect.size.x - (text_x - rect.position.x) - 4) / 4)), Vector2i(text_x, y), Color(TEXT, a))
