class_name FishingHud
extends Control
## While a rod is in her hand: one slim leaf of bark paper above the hotbar vine that says what the mouse and keys do
## right now, each with its key cap (`VineStyle.key_cap`), and, while she is not fishing yet, the bait (Z) and the float
## (H). The leaf unfurls from the middle and eases to the width of what it says. No tension readout here: that is the
## colour of the line itself.

const GOLD: Color = Color("e6c468")
const TEXT: Color = Color("e8e4f4")
const DIM: Color = Color("8a84ad")
const INK: Color = Color("1b1a2e")
const HEIGHT: int = 18
const GAP: int = 12 ## between two groups
const RAISE: float = 30.0 ## the leaf's top above the hotbar's top
const BOBBERS: Texture2D = preload("res://assets/fishing/bobbers.png")
const POSE_ROW: Dictionary = {"cork": 0, "glimmer": 1, "obsidian": 2}

var _p: Player
var _c: FishingComponent
var _show: float = 0.0
var _time: float = 0.0
var _width: float = 0.0
var _key: String = ""
var _swap: float = 1.0 ## 0 -> 1 after the content changed: the new words fade in
var _flash_bait: float = 0.0
var _flash_pose: float = 0.0


func bind(player: Node) -> void:
	_p = player as Player
	_c = _p.fishing
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	var hotbar: Control = get_parent().get_node_or_null("Hotbar") as Control
	var want: bool = _c != null and _c.rod_active() and hotbar != null and hotbar.visible and not InputManager.ui_blocking
	_show = move_toward(_show, 1.0 if want else 0.0, delta * 5.0)
	visible = _show > 0.01
	if not visible:
		_width = 0.0
		return
	_time += delta
	_swap = minf(1.0, _swap + delta * 6.0)
	if _c.state == FishingComponent.S.IDLE:
		if InputManager.fish_bait_pressed():
			_flash_bait = 1.0
		if InputManager.fish_pose_pressed():
			_flash_pose = 1.0
	_flash_bait = maxf(0.0, _flash_bait - delta * 3.0)
	_flash_pose = maxf(0.0, _flash_pose - delta * 3.0)
	var groups: Array = _groups()
	var key: String = str(groups.map(func(g: Dictionary) -> String: return String(g.get("key", "")) + String(g.get("text", ""))))
	if key != _key:
		_key = key
		_swap = 0.0
	var target: float = float(_measure(groups))
	_width = lerpf(_width, target, 1.0 - exp(-22.0 * delta)) if _width > 0.0 else target
	if absf(_width - target) < 0.5:
		_width = target
	queue_redraw()


## What the leaf says now: groups of {key, text, icon, lit, warn}. A group without a key is plain words.
func _groups() -> Array:
	var press: String = VineStyle.key_name("action_primary", VineStyle.MOUSE_LEFT)
	var reel: String = VineStyle.key_name("action_secondary", VineStyle.MOUSE_RIGHT)
	var held: float = 1.0 if InputManager.fish_held() else 0.0
	var out: Array = []
	match _c.state:
		FishingComponent.S.IDLE:
			match _c.aim_reason:
				"stand": out.append({"text": "GEH ANS UFER", "dim": true})
				"near": out.append({"text": "ZU NAH AM UFER", "dim": true})
				"land": out.append({"text": "ZIEL: OFFENES WASSER", "dim": true})
				"busy": out.append({"text": "...", "dim": true})
				_: out.append({"key": press, "text": "WERFEN"})
			out.append({"key": VineStyle.key_name("fish_bait", "Z"), "text": _bait_label(), "icon": "bait", "lit": _flash_bait})
			out.append({"key": VineStyle.key_name("fish_pose", "H"), "text": String((FishingRules.poses()[_c.pose] as Dictionary)["name"]), "icon": "pose", "lit": _flash_pose})
		FishingComponent.S.CASTING:
			out.append({"text": "WURF ...", "dim": true})
		FishingComponent.S.DRIFTING:
			out.append({"key": press, "text": "ZUPFEN"})
			out.append({"key": press, "text": "HALTEN: SCHNUR GEBEN", "lit": held})
			out.append({"key": reel, "text": "EINHOLEN"})
		FishingComponent.S.NIBBLE:
			out.append({"text": "RUHIG ... ES KNABBERT", "dim": true})
		FishingComponent.S.BITE:
			out.append({"key": press, "text": "ANSCHLAGEN!", "lit": 0.6 + 0.4 * sin(_time * 18.0), "warn": true})
		FishingComponent.S.DRILL:
			var move: String = _move_keys()
			if _c.tell:
				out.append({"text": "ER ZIEHT GLEICH!", "warn": true})
				out.append({"key": move, "text": "NACHGEBEN", "warn": true})
			elif _c.phase == "flee":
				out.append({"key": move, "text": "ZUM FISCH: NACHGEBEN", "lit": 1.0 if InputManager.move_vector() != Vector2.ZERO else 0.0})
			else:
				out.append({"key": press, "text": "HALTEN: EINHOLEN", "lit": held})
	return out


func _move_keys() -> String:
	var keys: String = ""
	for action: String in ["move_up", "move_left", "move_down", "move_right"]:
		var name_text: String = VineStyle.key_name(action, "")
		keys += name_text if name_text.length() == 1 else ""
	return keys if keys.length() == 4 else "WASD"


func _bait_label() -> String:
	if _c.bait == "":
		return "OHNE KÖDER"
	var name_text: String = String((DataRegistry.table("fishing")["baits"] as Dictionary)[_c.bait]["name"])
	return "%s X%d" % [name_text, _p.inventory.count_item(_c.bait)]


func _group_width(g: Dictionary) -> int:
	var w: int = PixelText.width(String(g.get("text", "")))
	if g.has("key"):
		w += VineStyle.cap_width(String(g["key"])) + 4
	if g.has("icon"):
		w += 14
	return w


func _measure(groups: Array) -> int:
	var w: int = 18
	for i: int in groups.size():
		w += _group_width(groups[i] as Dictionary) + (GAP if i > 0 else 0)
	return w


func _draw() -> void:
	var hotbar: Control = get_parent().get_node_or_null("Hotbar") as Control
	var top: float = hotbar.get_global_rect().position.y - global_position.y if hotbar != null else size.y - 50.0
	var cx: float = roundf(size.x * 0.5)
	var a: float = smoothstep(0.0, 1.0, _show)
	var void_level: float = VineStyle.void_amount()
	var groups: Array = _groups()
	var warn: bool = groups.any(func(g: Dictionary) -> bool: return bool(g.get("warn", false)))
	var w: float = roundf(_width * (0.35 + 0.65 * a)) ## it unfurls from the middle
	var rect: Rect2 = Rect2(cx - roundf(w * 0.5), roundf(top - RAISE + (1.0 - a) * 4.0), w, HEIGHT)
	if warn:
		VineStyle.glow(self, rect.get_center(), rect.size.x * 0.45, GOLD, (0.35 + 0.2 * sin(_time * 9.0)) * a)
	_stems(rect, a, void_level)
	VineStyle.paper(self, rect, a, void_level, 41)
	VineStyle.leaf(self, rect.position + Vector2(2, 3), -1, -1, 3, Color(VineStyle.LEAF.lerp(VineStyle.LEAF_VOID, void_level), a), Color(VineStyle.LEAF_LIGHT.lerp(VineStyle.LEAF_VOID_LIGHT, void_level), a))
	VineStyle.leaf(self, Vector2(rect.end.x - 3, rect.position.y + 3), 1, -1, 3, Color(VineStyle.LEAF.lerp(VineStyle.LEAF_VOID, void_level), a), Color(VineStyle.LEAF_LIGHT.lerp(VineStyle.LEAF_VOID_LIGHT, void_level), a))
	if void_level > 0.3:
		VineStyle.tendril(self, Vector2(rect.end.x - 2, rect.end.y - 3), Vector2(0.8, 0.5).normalized(), int(2 + 4 * void_level), _time, 7)
	var fade: float = a * smoothstep(0.0, 1.0, _swap) * clampf(1.0 - absf(_width - float(_measure(groups))) / 16.0, 0.0, 1.0) ## the words wait until the leaf fits them
	var x: float = cx - roundf(float(_measure(groups)) * 0.5) + 9.0
	var mid: float = rect.position.y + HEIGHT * 0.5
	for i: int in groups.size():
		var g: Dictionary = groups[i]
		if i > 0: ## a petal between two groups
			var dot: Vector2 = Vector2(roundf(x + GAP * 0.5 - 1.0), roundf(mid))
			draw_rect(Rect2(dot, Vector2.ONE), Color(VineStyle.PETAL, 0.55 * fade))
			draw_rect(Rect2(dot + Vector2(-1, 0), Vector2.ONE), Color(VineStyle.LEAF_LIGHT, 0.3 * fade))
			draw_rect(Rect2(dot + Vector2(1, 0), Vector2.ONE), Color(VineStyle.LEAF_LIGHT, 0.3 * fade))
			x += GAP
		var tone: Color = GOLD if bool(g.get("warn", false)) else (DIM if bool(g.get("dim", false)) else TEXT)
		if g.has("key"):
			x += VineStyle.key_cap(self, Vector2(x, mid - VineStyle.CAP_HEIGHT * 0.5), String(g["key"]), fade, float(g.get("lit", 0.0)), void_level) + 4
		if String(g.get("icon", "")) == "bait":
			_bait_icon(Vector2(x - 2, mid - 8), fade)
			x += 14
		elif String(g.get("icon", "")) == "pose":
			var row: int = int(POSE_ROW.get(_c.pose, 0))
			draw_texture_rect_region(BOBBERS, Rect2(Vector2(x, roundf(mid) - 7), Vector2(12, 12)), Rect2(0, row * 12, 12, 12), Color(1, 1, 1, fade))
			x += 14
		var text: String = String(g.get("text", ""))
		PixelText.draw(self, text, Vector2i(int(x), int(roundf(mid)) - 4), Color(tone, fade), Color(INK, fade))
		x += PixelText.width(text)


func _bait_icon(at: Vector2, fade: float) -> void:
	if _c.bait == "":
		draw_rect(Rect2(at + Vector2(6, 6), Vector2(3, 3)), Color(DIM, 0.6 * fade)) ## a bare hook: just a small dull speck
		return
	var icon: Texture2D = Items.icon({"id": _c.bait, "count": 1})
	if icon != null:
		draw_texture_rect(icon, Rect2(at.round(), Vector2(16, 16)), false, Color(1, 1, 1, fade))


## Two thin stems hold the leaf up from the hotbar vine below, so it grows out of the HUD instead of floating.
func _stems(rect: Rect2, a: float, void_level: float) -> void:
	var bark: Color = VineStyle.BARK.lerp(VineStyle.BARK_VOID, void_level)
	var light: Color = VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, void_level)
	for side: float in [-1.0, 1.0]:
		var x0: float = rect.get_center().x + side * (rect.size.x * 0.5 - 10.0)
		for k: int in 9:
			var y: float = rect.end.y - 1.0 + k
			var x: float = roundf(x0 + side * sin(k * 0.45) * 1.5)
			draw_rect(Rect2(x - 1, y, 3, 1), Color(VineStyle.OUTLINE, a * (1.0 - k / 10.0)))
			draw_rect(Rect2(x, y, 1, 1), Color(light if k % 2 == 0 else bark, a * (1.0 - k / 10.0)))
