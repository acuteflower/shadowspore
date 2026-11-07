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
var _leaving: Array[Dictionary] = [] ## shadows swimming off: a fish that turned away, was scared or got loose
var _state_seen: int = -1
var _state_age: float = 0.0
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
			_texts.append({"pos": pos, "text": String(messages[reason]), "age": 0.0, "bad": reason in ["snapped", "escaped", "unhooked", "torn"]})
		_leave(pos, data, 1.6 if reason in ["escaped", "unhooked", "torn", "snapped"] else 1.0)
	elif kind == "leap":
		_leaps.append({"pos": pos, "row": ORDER.find(String(data.get("species", ""))), "age": 0.0})
	elif kind == "scared":
		_texts.append({"pos": pos, "text": String(messages["scared"]), "age": 0.0, "bad": false})
		_leave(pos, data, 1.8)
	elif kind == "refuse":
		_texts.append({"pos": pos, "text": String(messages["refused"]), "age": 0.0, "bad": false, "dim": true})
		_leave(pos, data, 0.7)


## A fish swims off where everybody can see it (instead of the shadow simply fading on the spot).
func _leave(pos: Vector2, data: Dictionary, hurry: float) -> void:
	var row: int = ORDER.find(String(data.get("species", "")))
	var dir: Vector2 = data.get("dir", Vector2.ZERO) as Vector2
	if row < 0 or dir == Vector2.ZERO:
		return
	var start: Vector2 = pos
	if not _shadow_last.is_empty():
		start = (_shadow_last[0] as Rect2).get_center()
	_leaving.append({"pos": start, "dir": dir.normalized(), "row": row, "age": 0.0, "hurry": hurry, "bend": randf_range(-0.6, 0.6)})
	_shadow_alpha = 0.0
	_shadow_last = []


func _process(delta: float) -> void:
	_time += delta
	_tap_age += delta
	if _c.state != _state_seen:
		_state_seen = _c.state
		_state_age = 0.0
	_state_age += delta
	for i: int in range(_leaving.size() - 1, -1, -1):
		_leaving[i]["age"] = float(_leaving[i]["age"]) + delta
		if float(_leaving[i]["age"]) > 1.3:
			_leaving.remove_at(i)
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
	var active: bool = _c.state != FishingComponent.S.IDLE or not _texts.is_empty() or (_c.rod_active() and _c.is_multiplayer_authority()) or not _leaps.is_empty() or not _leaving.is_empty() or _shadow_alpha > 0.0
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
	var down: Vector2 = _c.current_at(_shown)
	var upstream: Vector2 = -down.normalized() if down.length() > 0.05 else (_shown - _c.approach_from).normalized()
	var hold: Vector2 = _shown - upstream * 7.0 ## fish stand head into the current, just below the drifting bait
	match s:
		FishingComponent.S.DRIFTING:
			## a curve out of the deep, a pause halfway to look, then the last careful glide into place below the float
			var k: float = 1.0 - clampf(_c.approach_time / maxf(_c.approach_total, 0.01), 0.0, 1.0)
			var eased: float = 0.55 * (1.0 - pow(1.0 - minf(k / 0.45, 1.0), 2.0)) + 0.45 * smoothstep(0.62, 1.0, k)
			var side: float = 1.0 if fmod(absf(_c.approach_from.x * 0.37 + _c.approach_from.y * 0.61), 2.0) < 1.0 else -1.0
			var bend: Vector2 = (_c.approach_from + hold) * 0.5 + (hold - _c.approach_from).orthogonal() * 0.35 * side
			at = _c.approach_from.lerp(bend, eased).lerp(bend.lerp(hold, eased), eased)
			var ahead: float = minf(eased + 0.05, 1.0)
			var next: Vector2 = _c.approach_from.lerp(bend, ahead).lerp(bend.lerp(hold, ahead), ahead)
			face = (next - at).normalized() if next.distance_to(at) > 0.01 else upstream
			face = face.slerp(upstream, smoothstep(0.8, 1.0, k)).normalized() ## it turns into the current to wait
			at += face.orthogonal() * sin(_time * 7.0) * 0.6 * (1.0 - k) ## a little tail beat
		FishingComponent.S.NIBBLE:
			var dart: float = 1.0 - clampf(_tap_age / 0.25, 0.0, 1.0) ## every tap: it darts up and mouths the bait
			at = hold.lerp(_shown, 0.7 * dart) + upstream.orthogonal() * sin(_time * 2.1) * 1.2
			face = upstream.slerp((_shown - hold).normalized(), 0.4 * dart).normalized()
		FishingComponent.S.BITE:
			## it takes the bait and turns away with it: the float goes under, the shadow heads off
			var turn: float = smoothstep(0.0, 0.35, _state_age)
			var off: Vector2 = upstream.orthogonal() * (1.0 if fmod(absf(_shown.x), 2.0) < 1.0 else -1.0)
			face = upstream.slerp(off, turn).normalized()
			at = _shown + off * 5.0 * turn - upstream * 2.0
		FishingComponent.S.DRILL:
			face = (_c.tip() - _shown).normalized() if _c.phase == "tire" else _c.heading
		_:
			return []
	var index: int = posmod(roundi(face.angle() / TAU * 16.0), 16)
	var frame: int = int(_time * 5.0) % 2
	var src: Rect2 = Rect2((index * 2 + frame) * 32, row * 32, 32, 32)
	return [Rect2((at - Vector2(16, 16)).round(), Vector2(32, 32)), src]


func _paint_shadow() -> void:
	var near_tone: Color = Color(0.5, 0.74, 0.8, 0.58)
	for leave: Dictionary in _leaving: ## a fish leaving speeds off, bends away and sinks out of sight
		var age: float = float(leave["age"])
		var hurry: float = float(leave["hurry"])
		var dir: Vector2 = (leave["dir"] as Vector2).rotated(float(leave["bend"]) * smoothstep(0.0, 0.8, age))
		var travel: float = (18.0 * age + 26.0 * age * age) * hurry
		var at: Vector2 = (leave["pos"] as Vector2) + dir * travel
		var index: int = posmod(roundi(dir.angle() / TAU * 16.0), 16)
		var frame: int = int(_time * 12.0) % 2 ## a fast tail beat
		var src: Rect2 = Rect2((index * 2 + frame) * 32, int(leave["row"]) * 32, 32, 32)
		var tone: Color = near_tone
		tone.a *= 1.0 - smoothstep(0.2, 1.3, age)
		_shadow_layer.draw_texture_rect_region(SHADOWS, Rect2((at - Vector2(16, 16)).round(), Vector2(32, 32)), src, tone)
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
		var color: Color = Color("ff4a63") if bool(t["bad"]) else (DIM if bool(t.get("dim", false)) else Color("e9e3f7"))
		PixelText.draw(self, text, Vector2i(pos.round()), Color(color, clampf(2.0 - age * 1.4, 0.0, 1.0)), Color("1b1a2e"))
