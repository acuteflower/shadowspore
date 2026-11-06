class_name FishingView
extends Node2D
## What the line, the float and the fish look like in the world (every peer draws it from the replicated state).
## Pixel lines, no smooth polylines. The tension is read ONLY from the colour of the line (plus a tremble),
## see docs/fishing.md.

const BOBBERS: Texture2D = preload("res://assets/fishing/bobbers.png")
const BOBBERS_GLOW: Texture2D = preload("res://assets/fishing/bobbers_glow.png")
const SHADOWS: Texture2D = preload("res://assets/fishing/fish_shadow.png")
const ORDER: Array[String] = ["silverling", "copper_loach", "moon_trout", "gold_carp", "glimmer_loach", "veil_eel", "abyss_pike"]
const POSE_ROW: Dictionary = {"cork": 0, "glimmer": 1, "obsidian": 2}
const TEAL: Color = Color("3cc0c6")
const BAD: Color = Color("c21f3b")
const DIM: Color = Color("8a84ad")

var _c: FishingComponent
var _p: Player
var _shown: Vector2 = Vector2.ZERO
var _time: float = 0.0
var _texts: Array[Dictionary] = []
var _tap_frame: int = 0
var _tap_age: float = 9.0
var _shadow_layer: Node2D ## world-lit (the fish is under water), the line and float above it are unlit: the readout must stay bright at night
var _shadow_args: Array = []
var _shadow_alpha: float = 0.0 ## the shadow rises out of the deep and sinks away again
var _shadow_last: Array = []
var _leaps: Array[Dictionary] = []
const SIDE: Texture2D = preload("res://assets/fishing/fish_side.png")


func bind(component: FishingComponent, player: Player) -> void:
	_c = component
	_p = player
	top_level = true
	z_as_relative = false
	z_index = 6
	global_position = Vector2.ZERO
	material = Unlit.material()
	_shadow_layer = Node2D.new()
	_shadow_layer.name = "Shadows"
	_shadow_layer.z_index = -1
	add_child(_shadow_layer)
	_shadow_layer.draw.connect(_paint_shadow)
	_c.fx.connect(_on_fx)


func _on_fx(kind: String, pos: Vector2, data: Dictionary) -> void:
	var messages: Dictionary = FishingRules.settings()["messages"] as Dictionary
	if kind == "tap":
		_tap_frame = 2 + int(data.get("side", 0))
		_tap_age = 0.0
	elif kind == "lost":
		var reason: String = String(data.get("reason", ""))
		if messages.has(reason):
			_texts.append({"pos": pos, "text": String(messages[reason]), "age": 0.0, "bad": reason in ["snapped", "escaped"]})
	elif kind == "leap":
		_leaps.append({"pos": pos, "row": ORDER.find(String(data.get("species", ""))), "age": 0.0})
	elif kind == "scared":
		_texts.append({"pos": pos, "text": String(messages["scared"]), "age": 0.0, "bad": false})


func _process(delta: float) -> void:
	_time += delta
	_tap_age += delta
	for i: int in range(_leaps.size() - 1, -1, -1):
		_leaps[i]["age"] = float(_leaps[i]["age"]) + delta
		if float(_leaps[i]["age"]) > 0.55:
			_leaps.remove_at(i)
	var rising: bool = _c.species != "" and _c.state != FishingComponent.S.IDLE
	_shadow_alpha = move_toward(_shadow_alpha, 1.0 if rising else 0.0, delta * (0.8 if rising else 2.5))
	for i: int in range(_texts.size() - 1, -1, -1):
		_texts[i]["age"] = float(_texts[i]["age"]) + delta
		if float(_texts[i]["age"]) > 1.4:
			_texts.remove_at(i)
	var active: bool = _c.state != FishingComponent.S.IDLE or not _texts.is_empty() or (_c.rod_active() and _c.is_multiplayer_authority()) or not _leaps.is_empty() or _shadow_alpha > 0.0
	if not active:
		return
	var goal: Vector2 = _c.bobber
	_shown = goal if _shown == Vector2.ZERO or _c.state == FishingComponent.S.CASTING else _shown.lerp(goal, 1.0 - exp(-14.0 * delta))
	queue_redraw()
	_shadow_layer.queue_redraw()


func _draw() -> void:
	var s: int = _c.state
	if s == FishingComponent.S.IDLE:
		if _c.rod_active() and _c.is_multiplayer_authority():
			_draw_aim()
		_draw_texts()
		return
	var from: Vector2 = _c.tip()
	var to: Vector2 = _shown
	if s == FishingComponent.S.CASTING:
		var k: float = clampf(_c.casting_time, 0.0, 1.0)
		to = from.lerp(_c.target, k)
		to.y -= sin(k * PI) * 22.0
	var tension: float = 0.0
	var tell: bool = false
	if s == FishingComponent.S.DRILL:
		tension = _c.tension
		tell = _c.tell
	elif s == FishingComponent.S.CASTING:
		tension = 0.45
	_shadow_args = _shadow_for(s)
	if s == FishingComponent.S.DRILL and to != from: ## the loaded rod tip dips toward the fish
		from += (to - from).normalized() * 2.5 * tension + Vector2(0.0, 1.5 * tension)
	_draw_line(from, to, tension, tell)
	if s != FishingComponent.S.DRILL and s != FishingComponent.S.BITE:
		_draw_bobber(to, s)
	if s == FishingComponent.S.BITE:
		_draw_bite(to)
	_draw_texts()


func _draw_aim() -> void:
	var at: Vector2 = _c.aim_point.round()
	var color: Color = Color("d0fff8") if _c.aim_valid else (Color("ff4a63") if _c.aim_reason == "land" else DIM)
	var breathe: float = 0.5 + 0.5 * sin(_time * 3.0)
	var rx: float = 8.0 + breathe
	var ry: float = rx * 0.5
	var steps: int = 40
	for k: int in steps:
		if k % 3 == 2:
			continue ## broken ring, dithered like the other ground markers
		var a: float = TAU * float(k) / float(steps)
		var p: Vector2 = at + Vector2(roundf(cos(a) * rx), roundf(sin(a) * ry))
		draw_rect(Rect2(p + Vector2(0, 1), Vector2.ONE), Color("0b1a26", 0.55))
		draw_rect(Rect2(p, Vector2.ONE), Color(color, 0.7 + 0.3 * breathe))
	draw_rect(Rect2(at + Vector2(0, 1), Vector2.ONE), Color("0b1a26", 0.55))
	draw_rect(Rect2(at, Vector2.ONE), color)


func _draw_line(from: Vector2, to: Vector2, tension: float, tell: bool) -> void:
	var color: Color = FishingRules.line_color(tension)
	var jitter: float = FishingRules.line_jitter(tension, tell)
	var length: float = from.distance_to(to)
	if length < 2.0:
		return
	var sag: float = lerpf(1.0, 14.0, 1.0 - clampf(tension / 0.55, 0.0, 1.0)) * minf(length / 80.0, 1.4)
	var mid: Vector2 = (from + to) * 0.5 + Vector2(0.0, sag)
	var normal: Vector2 = (to - from).normalized().orthogonal()
	var steps: int = maxi(8, int(length * 1.2)) ## a pixel at most between two samples: no gaps
	var last: Vector2 = Vector2(-9999, -9999)
	for i: int in steps + 1:
		var t: float = float(i) / float(steps)
		var point: Vector2 = from.lerp(mid, t).lerp(mid.lerp(to, t), t)
		if jitter > 0.0:
			point += normal * sin(_time * 70.0 + float(i) * 1.9) * jitter * sin(t * PI)
		point = point.round()
		if point == last:
			continue
		last = point
		draw_rect(Rect2(point + Vector2(0, 1), Vector2.ONE), Color("0b1a26", 0.4)) ## a thin shadow keeps it readable on the water
		draw_rect(Rect2(point, Vector2.ONE), color)


func _draw_bobber(at: Vector2, s: int) -> void:
	var pose: String = _c.cast_pose
	var row: int = int(POSE_ROW.get(pose, 0))
	var frame: int = 0
	if s == FishingComponent.S.DRIFTING:
		frame = 1 if sin(_time * 2.4 + at.x * 0.1) > 0.55 else 0
	elif s == FishingComponent.S.NIBBLE:
		frame = _tap_frame if _tap_age < 0.22 else 0
	var rect: Rect2 = Rect2((at - Vector2(6, 8)).round(), Vector2(12, 12))
	var src: Rect2 = Rect2(frame * 12, row * 12, 12, 12)
	var alpha: float = 0.3 if pose == "obsidian" else 1.0
	draw_texture_rect_region(BOBBERS, rect, src, Color(1, 1, 1, alpha))
	if pose == "glimmer":
		draw_texture_rect_region(BOBBERS_GLOW, rect, src, Color(1, 1, 1, lerpf(0.5, 1.0, TimeManager.night_amount())))


func _draw_bite(at: Vector2) -> void:
	var pulse: float = 0.5 + 0.5 * sin(_time * 18.0)
	var y: float = roundf(at.y - 20.0 - pulse * 2.0)
	PixelText.draw(self, "!", Vector2i(int(at.x) - 1, int(y)), Color("e6c468").lerp(Color("fff0b0"), pulse), Color("1b1a2e"))
	for k: int in 3:
		var a: float = _time * 5.0 + float(k) * 2.1
		draw_rect(Rect2((at + Vector2(cos(a) * 5.0, sin(a) * 2.5 - 1.0)).round(), Vector2.ONE), Color("d0fff8", 0.8))


func _shadow_for(s: int) -> Array:
	if _c.species == "":
		return []
	var row: int = ORDER.find(_c.species)
	if row < 0:
		return []
	var at: Vector2 = _shown
	var face: Vector2 = Vector2.RIGHT
	match s:
		FishingComponent.S.DRIFTING:
			var k: float = 1.0 - clampf(_c.approach_time / maxf(_c.approach_total, 0.01), 0.0, 1.0)
			var eased: float = 1.0 - pow(1.0 - k, 2.0)
			at = _c.approach_from.lerp(_shown, eased)
			face = (_shown - _c.approach_from).normalized()
		FishingComponent.S.NIBBLE, FishingComponent.S.BITE:
			var a: float = _time * 1.3
			at = _shown + Vector2(cos(a), sin(a) * 0.6) * 7.0
			face = Vector2(-sin(a), cos(a) * 0.6).normalized()
		FishingComponent.S.DRILL:
			face = (_c.tip() - _shown).normalized() if _c.phase == "tire" else _c.heading
		_:
			return []
	var index: int = posmod(roundi(face.angle() / TAU * 16.0), 16)
	var frame: int = int(_time * 5.0) % 2
	var src: Rect2 = Rect2((index * 2 + frame) * 32, row * 32, 32, 32)
	return [Rect2((at - Vector2(16, 16)).round(), Vector2(32, 32)), src]


func _paint_shadow() -> void:
	if not _shadow_args.is_empty():
		_shadow_last = _shadow_args
	if _shadow_last.is_empty() or _shadow_alpha <= 0.0:
		return
	var rise: float = smoothstep(0.0, 1.0, _shadow_alpha) ## from a faint pale blur in the deep to the dark shape near the surface
	var deep: Color = Color(0.42, 0.66, 0.74, 0.0)
	var near: Color = Color(0.5, 0.74, 0.8, 0.58)
	_shadow_layer.draw_texture_rect_region(SHADOWS, _shadow_last[0] as Rect2, _shadow_last[1] as Rect2, deep.lerp(near, rise))


func _draw_texts() -> void:
	for leap: Dictionary in _leaps:
		var k: float = float(leap["age"]) / 0.55
		var row: int = int(leap["row"])
		if row >= 0:
			var lift: float = sin(k * PI) * 18.0
			var at: Vector2 = (leap["pos"] as Vector2) + Vector2(-24.0 + k * 6.0, -12.0 - lift)
			draw_texture_rect_region(SIDE, Rect2(at.round(), Vector2(48, 24)), Rect2(0, row * 24, 48, 24), Color(1, 1, 1, clampf(2.0 - k * 2.0, 0.0, 1.0) if k > 0.5 else 1.0))
	for t: Dictionary in _texts:
		var age: float = float(t["age"])
		var text: String = String(t["text"])
		var pos: Vector2 = (t["pos"] as Vector2) + Vector2(-PixelText.width(text) * 0.5, -18.0 - age * 10.0)
		var color: Color = Color("ff4a63") if bool(t["bad"]) else Color("e9e3f7")
		PixelText.draw(self, text, Vector2i(pos.round()), Color(color, clampf(2.0 - age * 1.4, 0.0, 1.0)), Color("1b1a2e"))
