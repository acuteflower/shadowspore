class_name TitleLogo
extends Control
## The SHADOWSPORE title logo with its idle life. A stack of layers made by tools/art_title_logo.py (assets/ui/logo/): two orb sheets under the
## letters (the watching eye inside SHADOW's O, the town's lamp inside SPORE's O), the letters, the plants (sway in whole pixels), the self-lit
## pixels (void veins beat, roots breathe, the spore flower swells), additive halos and a few stateless particles (spores, void motes, drips).
## Everything is a pure function of the logo's own clock: it runs in real time, so it keeps moving while the game is paused or slowed, and
## `set_time(t)` freezes it for tests and captures. Tuning lives in data/title.json, geometry in data/title_logo_layout.json.
## 440 x 240 art pixels; put it at an integer position.
## A logo is fully built by default. `play_build()` plays the build-up (about 6 s: a spore pulses, a crack splits the ground, the letters land pixel by
## pixel (SPORE falls and stacks up from its foot, SHADOW slides in sideways row by row) over a dotted blueprint, the plants grow, a blow and a cloud
## of dust, the two O's ignite, the light runs through the veins, then the idle life fades in). `skip_build()` jumps to the end.

signal impact ## the blow when the last letter has landed (the owner may shake the camera)
signal built ## the build-up is over, the idle life runs
signal exited ## the exit is over: the logo is gone (and hidden)

const DIR: String = "res://assets/ui/logo/"
const SEQUENCE_ORB: int = 40

var _layout: Dictionary = {}
var _cfg: Dictionary = {}
var _manual: bool = false
var _manual_time: float = 0.0
var _t0_usec: int = 0

var _orb_void: Sprite2D
var _orb_life: Sprite2D
var _base: Sprite2D
var _plants: Sprite2D
var _glow: Sprite2D
var _halo_void: Sprite2D
var _halo_life: Sprite2D
var _halo_lamp: Sprite2D
var _particles: Node2D
var _mat_base: ShaderMaterial
var _mat_plants: ShaderMaterial
var _mat_glow: ShaderMaterial
var _mat_halos: Array[ShaderMaterial] = []

var _building: bool = false
var _build_start: float = 0.0
var _impact_fired: bool = false
var _exiting: bool = false
var _exit_start: float = 0.0
var _exit_len: float = 1.8
var _idle: float = 1.0
var _spore_pos: Vector2 = Vector2.ZERO

var _eye_seq: Array[int] = []
var _glitch_frames: Array[int] = []
var _flicker: Array[float] = []


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS ## the logo keeps living while the game is paused
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _ready() -> void:
	_layout = DataRegistry.table("title_logo_layout")
	_cfg = DataRegistry.table("title")
	var size_a: Array = _layout.get("size", [440, 240]) as Array
	custom_minimum_size = Vector2(float(size_a[0]), float(size_a[1]))
	size = custom_minimum_size
	for v: Variant in (_cfg.get("eye", {}) as Dictionary).get("sequence", [0]) as Array:
		_eye_seq.append(int(v))
	for v: Variant in (_cfg.get("eye", {}) as Dictionary).get("glitch_frames", [2]) as Array:
		_glitch_frames.append(int(v))
	for v: Variant in (_cfg.get("lamp", {}) as Dictionary).get("flicker", [1.0]) as Array:
		_flicker.append(float(v))
	_t0_usec = Time.get_ticks_usec()
	_build()
	_find_spore()
	_update(clock())


## Time of the logo's own clock in seconds: real time unless `set_time` froze it.
func clock() -> float:
	if _manual:
		return _manual_time
	return float(Time.get_ticks_usec() - _t0_usec) / 1000000.0


## Starts the build-up now (the logo is empty until the first spore appears).
func play_build() -> void:
	visible = true
	_exiting = false
	_building = true
	_build_start = clock()
	_impact_fired = false
	if is_inside_tree():
		_update(clock())


func skip_build() -> void:
	if _building:
		_building = false
		_update(clock())
		built.emit()


func is_building() -> bool:
	return _building


func is_exiting() -> bool:
	return _exiting


## The exit: the build-up played backwards and faster (the pixels rise and slide away, the plants shrink, the light withdraws, the crack closes and a last
## spore pulses), then the logo hides itself and `exited` fires.
func play_exit(duration: float = 1.8) -> void:
	_building = false
	_exiting = true
	_exit_start = clock()
	_exit_len = maxf(duration, 0.1)
	if is_inside_tree():
		_update(clock())


## Seconds since `play_build` (a very large number when the logo is simply built).
func build_time() -> float:
	if _exiting:
		return lerpf(build_total() - 0.01, 0.0, clampf((clock() - _exit_start) / _exit_len, 0.0, 1.0))
	return clock() - _build_start if _building else 1.0e9


func build_total() -> float:
	return float((_cfg.get("build", {}) as Dictionary).get("total", 6.2))


## Everything the build-up changes at build time `bt`, as a pure function (the defaults are the finished logo).
func build_params(bt: float) -> Dictionary:
	var out: Dictionary = {"build_on": 0.0, "build_t": 2.0, "blueprint": 0.0, "flash": 0.0, "crack_reach": 9999.0, "front": 9999.0, "grow": 2.0,
			"void_on": true, "life_on": true, "void_halo": 1.0, "life_halo": 1.0, "lamp_boost": 1.0, "idle": 1.0, "spore": 0.0, "done": true}
	var b: Dictionary = _cfg.get("build", {}) as Dictionary
	if bt >= float(b.get("total", 6.2)):
		return out
	out["done"] = false
	out["build_on"] = 1.0
	var letters: Array = b.get("letters", [1.8, 4.4]) as Array
	var fall: float = float(b.get("fall_span", 0.09))
	out["build_t"] = clampf((bt - float(letters[0])) / (float(letters[1]) - float(letters[0])), 0.0, 1.0) * (1.0 + fall) if bt >= float(letters[0]) else -1.0
	var bp: Array = b.get("blueprint", [1.5, 2.0]) as Array
	out["blueprint"] = clampf((bt - float(bp[0])) / (float(bp[1]) - float(bp[0])), 0.0, 1.0) * 0.9
	var crack: Array = b.get("crack", [0.8, 1.8]) as Array
	var cu: float = clampf((bt - float(crack[0])) / (float(crack[1]) - float(crack[0])), 0.0, 1.0)
	out["crack_reach"] = -1.0 if bt < float(crack[0]) else cu * cu * (3.0 - 2.0 * cu) * float(b.get("crack_half", 250.0))
	var pl: Array = b.get("plants", [3.6, 4.7]) as Array
	out["grow"] = -1.0 if bt < float(pl[0]) else clampf((bt - float(pl[0])) / (float(pl[1]) - float(pl[0])), 0.0, 1.0)
	var fr: Array = b.get("front", [4.8, 5.8]) as Array
	out["front"] = -20.0 if bt < float(fr[0]) else lerpf(-10.0, 470.0, clampf((bt - float(fr[0])) / (float(fr[1]) - float(fr[0])), 0.0, 1.0))
	var hit: float = float(b.get("impact", 4.5))
	out["flash"] = exp(-(bt - hit) * 9.0) if bt >= hit else 0.0
	var iv: float = float(b.get("ignite_void", 4.7))
	var il: float = float(b.get("ignite_life", 4.95))
	var void_pattern: Array[int] = [1, 0, 1, 0, 0, 1]
	var life_pattern: Array[int] = [1, 0, 1, 1, 0, 1]
	out["void_on"] = bt >= iv and (bt >= iv + 0.36 or void_pattern[int((bt - iv) / 0.06)] == 1)
	out["life_on"] = bt >= il and (bt >= il + 0.36 or life_pattern[int((bt - il) / 0.06)] == 1)
	out["void_halo"] = clampf((bt - iv) / 0.9, 0.0, 1.0) if out["void_on"] else 0.0
	out["life_halo"] = clampf((bt - il) / 0.9, 0.0, 1.0) if out["life_on"] else 0.0
	out["lamp_boost"] = 1.0 + 1.4 * exp(-(bt - il) * 4.0) if bt >= il else 1.0
	var idle: Array = b.get("idle_in", [5.6, 6.2]) as Array
	out["idle"] = smoothstep(float(idle[0]), float(idle[1]), bt)
	out["spore"] = 0.0 if bt >= float(letters[0]) else beat(bt * 1.1) * 0.8 + 0.2
	return out


func set_time(t: float) -> void:
	_manual = true
	_manual_time = t
	if is_inside_tree():
		_update(t)


func release_time() -> void:
	_t0_usec = Time.get_ticks_usec() - int(_manual_time * 1000000.0)
	_manual = false


# ----------------------------------------------------------------- pure functions of the clock (tested)
static func _h(n: float, seed_value: float = 0.0) -> float:
	return fposmod(sin(n * 12.9898 + seed_value * 78.233) * 43758.5453, 1.0)


## Progress 0..1 of the event of the time bucket that contains `t` (one per `every` seconds, at a hashed moment, lasting `length`), or -1 when none is on.
static func event_progress(t: float, every: float, length: float, seed_value: float) -> float:
	var n: float = floorf(t / every)
	var start: float = n * every + _h(n, seed_value) * (every - length)
	var u: float = (t - start) / length
	return u if u >= 0.0 and u <= 1.0 else -1.0


static func event_index(t: float, every: float) -> int:
	return int(floorf(t / every))


## The heartbeat of the shadow: a quick double bump (lub-dub) then rest; the same shape as in title_glow.gdshader.
static func beat(t: float) -> float:
	var x: float = fposmod(t, 1.0)
	var a: float = exp(-pow((x - 0.08) / 0.05, 2.0))
	var b: float = exp(-pow((x - 0.24) / 0.06, 2.0)) * 0.75
	return clampf(a + b, 0.0, 1.0)


func wind_at(t: float) -> float:
	var w: Dictionary = _cfg.get("wind", {}) as Dictionary
	return float(w.get("base", 0.25)) + float(w.get("swing", 0.45)) * sin(t * TAU / float(w.get("period", 9.0))) + float(w.get("gust", 0.25)) * sin(t * 0.9 + 1.3)


## Frame of the watching eye: a calm slow sequence, now and then a short burst of glitch frames.
func eye_frame_at(t: float) -> int:
	var e: Dictionary = _cfg.get("eye", {}) as Dictionary
	var u: float = event_progress(t, float(e.get("glitch_every", 9.0)), float(e.get("glitch_len", 0.18)), 3.0)
	if u >= 0.0 and not _glitch_frames.is_empty():
		return _glitch_frames[mini(int(u * float(_glitch_frames.size())), _glitch_frames.size() - 1)]
	var step: float = float(e.get("step", 0.6))
	return _eye_seq[posmod(int(floorf(t / step)), _eye_seq.size())]


## Frame of the lamp (flame tongues, the pulse running up the vein): about 7 a second with an uneven rhythm.
func lamp_frame_at(t: float) -> int:
	var l: Dictionary = _cfg.get("lamp", {}) as Dictionary
	return posmod(int(floorf(t * float(l.get("fps", 7.0)) + float(l.get("wobble", 0.6)) * sin(t * 1.3))), maxi(1, int(_layout.get("frames", 8))))


## x of the glint band along the diagonal, or a value far off the picture when none is on.
func glint_at(t: float) -> float:
	var g: Dictionary = _cfg.get("glint", {}) as Dictionary
	var u: float = event_progress(t, float(g.get("every", 12.0)), float(g.get("length", 2.6)), 7.0)
	if u < 0.0:
		return -1000.0
	return lerpf(float(g.get("from", 100.0)), float(g.get("to", 520.0)), u)


## Rows of SHADOW that slip sideways for a moment: Vector3(first row, row count, shift in px) in logo pixels; rows = 0 when none is on.
func glitch_at(t: float) -> Vector3:
	var g: Dictionary = _cfg.get("glitch", {}) as Dictionary
	var u: float = event_progress(t, float(g.get("every", 7.0)), float(g.get("length", 0.14)), 11.0)
	if u < 0.0:
		return Vector3.ZERO
	var n: float = float(event_index(t, float(g.get("every", 7.0))))
	var origin: Array = _layout.get("origin_of_word", [0, 0]) as Array
	var rows: Array = g.get("rows", [1, 3]) as Array
	var shifts: Array = g.get("shift", [2, 3]) as Array
	var top: float = float(origin[1]) + float(g.get("top", 4))
	var span: float = float((_layout.get("seam_y", [124, 129]) as Array)[0]) - top - float(g.get("bottom", 2))
	var y: float = floorf(top + _h(n, 1.7) * span)
	var count: float = floorf(lerpf(float(rows[0]), float(rows[1]) + 0.99, _h(n, 2.9)))
	var sh: float = floorf(lerpf(float(shifts[0]), float(shifts[1]) + 0.99, _h(n, 4.1))) * (1.0 if _h(n, 5.3) > 0.5 else -1.0)
	return Vector3(y, count, sh)


# ----------------------------------------------------------------- building
func _tex(file: String) -> Texture2D:
	return load(DIR + file) as Texture2D


func _sprite(tex: Texture2D, pos: Vector2, mat: Material) -> Sprite2D:
	var s: Sprite2D = Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.position = pos
	s.material = mat
	add_child(s)
	return s


func _shader_material(file: String) -> ShaderMaterial:
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = load("res://assets/shaders/" + file) as Shader
	return m


func _build() -> void:
	var orbs: Dictionary = _layout.get("orbs", {}) as Dictionary
	_orb_void = _make_orb(_tex("title_orb_void.png"), orbs.get("void", {}) as Dictionary)
	_orb_life = _make_orb(_tex("title_orb_life.png"), orbs.get("life", {}) as Dictionary)
	_mat_base = _shader_material("title_base.gdshader")
	_mat_base.set_shader_parameter("order_map", _tex("title_order.png"))
	_mat_base.set_shader_parameter("fall_span", float((_cfg.get("build", {}) as Dictionary).get("fall_span", 0.09)))
	_base = _sprite(_tex("title_base.png"), Vector2.ZERO, _mat_base)
	var sway: Texture2D = _tex("title_plants_sway.png")
	_mat_plants = _shader_material("title_plants.gdshader")
	_mat_plants.set_shader_parameter("sway_map", sway)
	_plants = _sprite(_tex("title_plants.png"), Vector2.ZERO, _mat_plants)
	_mat_glow = _shader_material("title_glow.gdshader")
	_mat_glow.set_shader_parameter("sway_map", sway)
	_mat_glow.set_shader_parameter("glow_map", _tex("title_glow_map.png"))
	_glow = _sprite(_tex("title_glow.png"), Vector2.ZERO, _mat_glow)
	var plant_cfg: Dictionary = _cfg.get("plants", {}) as Dictionary
	for m: ShaderMaterial in [_mat_plants, _mat_glow]:
		m.set_shader_parameter("sway_amount", float(plant_cfg.get("amount", 2.2)))
		m.set_shader_parameter("sway_flutter", float(plant_cfg.get("flutter", 0.55)))
		m.set_shader_parameter("sway_speed", float(plant_cfg.get("speed", 2.1)))
	var glow_cfg: Dictionary = _cfg.get("glow", {}) as Dictionary
	_mat_glow.set_shader_parameter("intensity", float(glow_cfg.get("intensity", 1.0)))
	_mat_glow.set_shader_parameter("beat_rate", float(glow_cfg.get("beat_rate", 0.8)))
	var g: Dictionary = _cfg.get("glint", {}) as Dictionary
	_mat_base.set_shader_parameter("glint_width", float(g.get("width", 9.0)))
	_mat_base.set_shader_parameter("glint_strength", float(g.get("strength", 0.16)))
	for file: String in ["title_halo_void.png", "title_halo_life.png", "title_halo_lamp.png"]:
		var hm: ShaderMaterial = _shader_material("title_halo.gdshader")
		_mat_halos.append(hm)
		var hs: Sprite2D = _sprite(_tex(file), Vector2.ZERO, hm)
		match file:
			"title_halo_void.png":
				_halo_void = hs
			"title_halo_life.png":
				_halo_life = hs
			_:
				_halo_lamp = hs
	_particles = Node2D.new()
	var pm: CanvasItemMaterial = CanvasItemMaterial.new()
	pm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	pm.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_particles.material = pm
	add_child(_particles)
	_particles.draw.connect(_draw_particles)


func _find_spore() -> void:
	var origin: Array = _layout.get("origin_of_word", [0, 0]) as Array
	var word: Array = _layout.get("word", [0, 0]) as Array
	var cx: int = int(float(origin[0]) + float(word[0]) / 2.0)
	var glow: Image = _tex("title_glow.png").get_image()
	var gmap: Image = _tex("title_glow_map.png").get_image()
	_spore_pos = Vector2(float(cx), float(_layout.get("crack_y", 190)))
	for dx: int in [0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6, -6]:
		var found: bool = false
		for y: int in glow.get_height():
			if glow.get_pixel(cx + dx, y).a > 0.0 and int(roundf(gmap.get_pixel(cx + dx, y).g * 255.0 / 32.0)) == 5:
				_spore_pos = Vector2(float(cx + dx), float(y))
				found = true
				break
		if found:
			break
	_mat_glow.set_shader_parameter("center_x", _spore_pos.x)


func _make_orb(tex: Texture2D, orb: Dictionary) -> Sprite2D:
	var c: Array = orb.get("center", [0, 0]) as Array
	var half: float = float(_layout.get("orb_frame", SEQUENCE_ORB)) / 2.0
	var pos: Vector2 = Vector2(roundf(float(c[0]) - half + 0.5), roundf(float(c[1]) - half + 0.5))
	var s: Sprite2D = _sprite(tex, pos, Unlit.material())
	s.hframes = int(_layout.get("frames", 8))
	return s


# ----------------------------------------------------------------- every frame
func _process(_delta: float) -> void:
	if not visible and not _exiting:
		return
	if not is_visible_in_tree():
		return
	_update(clock())


func _update(t: float) -> void:
	var bt: float = build_time()
	var bp: Dictionary = build_params(bt)
	if _building and bool(bp["done"]):
		_building = false
		built.emit()
	if _building and not _impact_fired and bt >= float((_cfg.get("build", {}) as Dictionary).get("impact", 4.5)):
		_impact_fired = true
		impact.emit()
	if _exiting:
		bp["flash"] = 0.0
	var done: bool = bool(bp["done"])
	_idle = float(bp["idle"])
	var wind: float = wind_at(t)
	for m: ShaderMaterial in [_mat_plants, _mat_glow]:
		m.set_shader_parameter("sway_time", t)
		m.set_shader_parameter("sway_wind", wind)
		m.set_shader_parameter("grow", float(bp["grow"]))
	_mat_glow.set_shader_parameter("time", t)
	_mat_glow.set_shader_parameter("crack_reach", float(bp["crack_reach"]))
	_mat_glow.set_shader_parameter("front", float(bp["front"]))
	_mat_base.set_shader_parameter("build_on", float(bp["build_on"]))
	_mat_base.set_shader_parameter("build_t", float(bp["build_t"]))
	_mat_base.set_shader_parameter("blueprint", float(bp["blueprint"]))
	_mat_base.set_shader_parameter("flash", float(bp["flash"]))
	var gl: Vector3 = glitch_at(t) if done else Vector3.ZERO
	_mat_base.set_shader_parameter("glint_pos", glint_at(t) if done else -1000.0)
	_mat_base.set_shader_parameter("glitch", Vector4(gl.x, gl.y, gl.z, float((_layout.get("seam_y", [124, 129]) as Array)[0])))
	_orb_void.visible = bool(bp["void_on"])
	_orb_life.visible = bool(bp["life_on"])
	_orb_void.frame = eye_frame_at(t)
	var lf: int = lamp_frame_at(t)
	_orb_life.frame = lf
	var h: Dictionary = _cfg.get("halo", {}) as Dictionary
	var rate: float = float((_cfg.get("glow", {}) as Dictionary).get("beat_rate", 0.8))
	_mat_halos[0].set_shader_parameter("strength", float(bp["void_halo"]) * float(h.get("void", 0.8)) * (1.0 - float(h.get("void_beat", 0.3)) + float(h.get("void_beat", 0.3)) * 1.4 * beat(t * rate)))
	_mat_halos[1].set_shader_parameter("strength", float(bp["life_halo"]) * float(h.get("life", 0.8)) * (1.0 + float(h.get("life_breath", 0.15)) * sin(t * 1.5)))
	_mat_halos[2].set_shader_parameter("strength", float(bp["life_halo"]) * float(bp["lamp_boost"]) * float(h.get("lamp", 0.8)) * (_flicker[lf % _flicker.size()] if not _flicker.is_empty() else 1.0))
	_particles.queue_redraw()
	if _exiting and clock() - _exit_start >= _exit_len:
		_exiting = false
		visible = false
		exited.emit()


# ----------------------------------------------------------------- particles (stateless: position and fade are functions of the clock)
func _dot(p: Vector2, color: Color, alpha: float, scale: float = -1.0) -> void:
	var a: float = floorf(clampf(alpha * (_idle if scale < 0.0 else scale), 0.0, 1.0) * 3.0 + 0.5) / 3.0
	if a <= 0.0:
		return
	_particles.draw_rect(Rect2(p.floor(), Vector2.ONE), Color(color.r, color.g, color.b, a))


func _draw_build_fx(bt: float, dust: bool = true) -> void:
	var b: Dictionary = _cfg.get("build", {}) as Dictionary
	var spore: float = float(build_params(bt)["spore"])
	if spore > 0.0 and bt >= 0.0:
		_dot(_spore_pos, Color("ffd8f4"), spore, 1.0)
		if spore > 0.7:
			for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
				_dot(_spore_pos + d, Color("ff4fd8"), (spore - 0.5) * 1.4, 1.0)
	var hit: float = float(b.get("impact", 4.5))
	var age: float = bt - hit
	if dust and age >= 0.0 and age < 1.1:
		var ground: float = float(_layout.get("ground_y", 183))
		var cx: float = _spore_pos.x
		for i: int in 56:
			var fi: float = float(i)
			var dir: float = 1.0 if i % 2 == 0 else -1.0
			var speed: float = 70.0 + 110.0 * _h(fi, 31.0)
			var x: float = cx + dir * speed * (1.0 - exp(-age * 3.2)) / 3.2 * (0.55 + 0.45 * _h(fi, 32.0))
			var y: float = ground - 1.0 - sin(minf(age / 1.1, 1.0) * PI) * (2.0 + 6.0 * _h(fi, 33.0))
			var col: Color = Color("b9a6e8") if _h(fi, 34.0) < 0.6 else Color("6ae0d2")
			_dot(Vector2(x, y), col, (1.0 - age / 1.1) * 0.9, 1.0)


func _draw_particles() -> void:
	var t: float = clock()
	if _building or _exiting:
		_draw_build_fx(build_time(), _building)
	var wind: float = wind_at(t)
	var sp: Dictionary = _cfg.get("spores", {}) as Dictionary
	var sources: Array = _layout.get("spore_sources", []) as Array
	var bloom: Array = _layout.get("bloom", [0, 0]) as Array
	var life_r: Array = sp.get("life", [4.5, 7.5]) as Array
	var rise_r: Array = sp.get("rise", [6.0, 12.0]) as Array
	var gold_every: int = int(sp.get("gold_every", 4))
	for i: int in int(sp.get("count", 16)):
		var fi: float = float(i)
		var life: float = lerpf(float(life_r[0]), float(life_r[1]), _h(fi, 1.0))
		var off: float = _h(fi, 2.0) * life
		var cyc: float = floorf((t + off) / life)
		var age: float = fposmod(t + off, life)
		var u: float = age / life
		var src: Vector2 = Vector2(float(bloom[0]), float(bloom[1]))
		if _h(fi + cyc * 3.1, 3.0) > float(sp.get("bloom_share", 0.55)) and sources.size() > 1:
			var k: int = 1 + int(_h(fi + cyc * 5.7, 4.0) * float(sources.size() - 1))
			var s: Array = sources[mini(k, sources.size() - 1)] as Array
			src = Vector2(float(s[0]), float(s[1]) - 4.0)
		var rise: float = lerpf(float(rise_r[0]), float(rise_r[1]), _h(fi + cyc, 5.0))
		var pos: Vector2 = src + Vector2((_h(fi + cyc * 2.3, 6.0) - 0.5) * 8.0 + sin(age * 1.4 + _h(fi, 7.0) * TAU) * (2.0 + age * 1.1) + wind * age * 2.5, -age * rise)
		var col: Color = Color("fff0b0") if gold_every > 0 and i % gold_every == 0 else Color("d0fff8")
		_dot(pos, col, pow(sin(PI * u), 0.7))
	var mo: Dictionary = _cfg.get("motes", {}) as Dictionary
	var vs: Array = _layout.get("void_sources", []) as Array
	var mlife: Array = mo.get("life", [3.0, 6.0]) as Array
	var mrise: Array = mo.get("rise", [5.0, 10.0]) as Array
	for i: int in int(mo.get("count", 18)):
		if vs.is_empty():
			break
		var fi: float = float(i)
		var life: float = lerpf(float(mlife[0]), float(mlife[1]), _h(fi, 11.0))
		var off: float = _h(fi, 12.0) * life
		var cyc: float = floorf((t + off) / life)
		var age: float = fposmod(t + off, life)
		var u: float = age / life
		var s: Array = vs[i % vs.size()] as Array
		var x: float = float(s[0]) + (_h(fi + cyc * 1.9, 13.0) - 0.5) * 2.0 * float(mo.get("spread", 44.0))
		var rise: float = lerpf(float(mrise[0]), float(mrise[1]), _h(fi + cyc, 14.0))
		var pos: Vector2 = Vector2(x + sin(age * 2.1 + fi) * 1.6, float(s[1]) - 1.0 - age * rise)
		var magenta: bool = _h(fi + cyc * 4.1, 15.0) < float(mo.get("magenta_share", 0.12))
		var flick: float = 0.65 + 0.35 * sin(age * 9.0 + fi * 2.0)
		_dot(pos, Color("ff4fd8") if magenta else Color("8a4dff"), pow(sin(PI * u), 0.8) * flick * (0.9 if magenta else 0.7))
	var dr: Dictionary = _cfg.get("drips", {}) as Dictionary
	var cols: Array = _layout.get("drip_columns", []) as Array
	var seam: Array = _layout.get("seam_y", [124, 129]) as Array
	var every: Array = dr.get("every", [2.6, 4.4]) as Array
	var fall: float = float(dr.get("fall", 9.0))
	var fall_t: float = float(dr.get("fall_time", 0.9))
	for i: int in int(dr.get("count", 6)):
		if cols.is_empty():
			break
		var fi: float = float(i)
		var period: float = lerpf(float(every[0]), float(every[1]), _h(fi, 21.0))
		var off: float = _h(fi, 22.0) * period
		var cyc: float = floorf((t + off) / period)
		var age: float = fposmod(t + off, period)
		var x: float = float(cols[int(_h(fi + cyc * 3.3, 23.0) * float(cols.size())) % cols.size()])
		var y0: float = float(seam[0]) + 4.0
		if age < fall_t:
			var q: float = age / fall_t
			_dot(Vector2(x, y0 + q * q * fall), Color("b06bff"), 1.0)
			_dot(Vector2(x, y0 + q * q * fall - 1.0), Color("8a4dff"), 0.6)
		elif age < fall_t + 0.3:
			var s2: float = 1.0 - (age - fall_t) / 0.3
			_dot(Vector2(x - 1.0, y0 + fall), Color("8a4dff"), s2)
			_dot(Vector2(x + 1.0, y0 + fall), Color("8a4dff"), s2)
