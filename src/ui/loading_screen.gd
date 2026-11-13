class_name LoadingScreen
extends Control
## The loading screen (`GameLauncher.start`): delicate 1x bright silhouettes crossing a floating ridge
## in the abyss (`loading_veil.gdshader`). Ellie, two randomly chosen companions, a guiding turquoise
## wisp and a soaring corvid emerge onto the luminous path while voidblooms, moonbells, glowferns and
## crystals drift past. When the world is ready (`complete()`), a waystone goddess statue materializes
## ahead in bright silhouette; the guiding wisp darts into her heart, waking her crystal crown and a
## dithered pillar of light (`waystone_beam.gdshader`), and the travellers walk into the sanctuary
## light, dissolving into rising starlight motes before `reveal_world()` opens onto the world.
signal finished

const VEIL: Shader = preload("res://assets/shaders/loading_veil.gdshader")
const SILHOUETTE: Shader = preload("res://assets/shaders/silhouette.gdshader")
const BEAM_SHADER: Shader = preload("res://assets/shaders/waystone_beam.gdshader")
const STATUE_CLEAN: Texture2D = preload("res://assets/props/waystone/statue_clean.png")
const STATUE_GLOW: Texture2D = preload("res://assets/props/waystone/statue_glow.png")
const STATUE_WAVE: Texture2D = preload("res://assets/props/waystone/statue_wave.png")

const ENTRANCE_END: float = 1.85 ## earliest moment the sanctuary finale may begin
const CHASE_LENGTH: float = 2.50 ## duration of waystone awakening & passage into light
const CAMERA_SETTLE: float = 0.72 ## camera decelerates gently to rest at the sanctuary
const HORIZON: float = 208.0 ## stage y where boots touch the ridge
const WAYSTONE_FINAL_X: float = 434.0 ## stage x where the waystone settles
const DISSOLVE_FROM_X: float = 404.0 ## stage x where walkers begin dissolving into light
const DISSOLVE_TO_X: float = 428.0 ## stage x where dissolution completes
const SLOT_X: Array[float] = [340.0, 294.0, 248.0] ## Ellie leads, two companions follow at 1x scale
const OPEN_SECONDS: float = 0.75
const CLOSE_SECONDS: float = 0.45

const HERO_SHADE: Color = Color("ad94ed")
const HERO_BODY: Color = Color("dcd0ff")
const HERO_BRIGHT: Color = Color("f4eeff")
const HERO_EDGE: Color = Color("fffdf8")

const PROP_SHADE: Color = Color("6b50b8")
const PROP_BODY: Color = Color("9c82e0")
const PROP_BRIGHT: Color = Color("cbb8fa")
const PROP_EDGE: Color = Color("ebe0ff")

const TEAL_SPARK: Color = Color("78f4e6")
const TEAL_CORE: Color = Color("e4fffb")
const LILAC_SPARK: Color = Color("d8c8ff")
const GOLD_SPARK: Color = Color("fff0b0")

const SCENERY_SPAN: float = 440.0
const SCENERY_LEFT: float = 100.0
const SCENERY_SLOTS: Array[Dictionary] = [
	{"offset": 18.0, "kind": 0, "variant": 1, "z": 1, "dy": 0.0},
	{"offset": 78.0, "kind": 3, "variant": 2, "z": 1, "dy": 1.0},
	{"offset": 134.0, "kind": 1, "variant": 2, "z": 1, "dy": 0.0},
	{"offset": 198.0, "kind": 2, "variant": 1, "z": 1, "dy": 0.0},
	{"offset": 256.0, "kind": 3, "variant": 6, "z": 5, "dy": 1.0},
	{"offset": 318.0, "kind": 0, "variant": 4, "z": 1, "dy": 0.0},
	{"offset": 382.0, "kind": 1, "variant": 4, "z": 1, "dy": 0.0},
]

var companions: Array[int] = [] ## indices into data/loading.json "cast" (1..3)
var age: float = 0.0
var chase: float = -1.0 ## < 0 while wandering, 0..CHASE_LENGTH during the waystone finale
var ready_to_leave: bool = false
var done: bool = false
var error_text: String = ""

var _cfg: Dictionary = {}
var _backing: ColorRect
var _back: ColorRect
var _back_material: ShaderMaterial
var _stage: Node2D
var _actors: Array[Dictionary] = []
var _scenery: Array[Dictionary] = []
var _bird: Sprite2D
var _bird_mat: ShaderMaterial
var _bird_cfg: Dictionary = {}
var _waystone: Sprite2D
var _waystone_mat: ShaderMaterial
var _beam: ColorRect
var _beam_mat: ShaderMaterial
var _fx: Node2D
var _travel: float = 0.0
var _revealing: bool = false
var _opening_override: float = -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_cfg = DataRegistry.table("loading")
	if companions.is_empty():
		var pool: Array[int] = [1, 2, 3]
		pool.shuffle()
		companions.assign(pool.slice(0, 2))

	_backing = ColorRect.new()
	_backing.color = Color("040208")
	_backing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backing.show_behind_parent = true
	add_child(_backing)

	_back = ColorRect.new()
	_back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_material = ShaderMaterial.new()
	_back_material.shader = VEIL
	_back_material.set_shader_parameter("horizon", HORIZON)
	_back.material = _back_material
	_back.show_behind_parent = true
	add_child(_back)

	_stage = Node2D.new()
	_stage.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_stage)

	_build_scenery()
	_build_waystone()
	_build_cast()
	_build_bird()

	_fx = Node2D.new()
	_fx.z_index = 7
	_fx.material = Unlit.material()
	_fx.draw.connect(_draw_fx)
	_stage.add_child(_fx)

	update_visuals(0.0)


func _silhouette_material(shade: Color, body: Color, bright: Color, rim: Color, rim_strength: float, sculpt: float) -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = SILHOUETTE
	mat.set_shader_parameter("shade", shade)
	mat.set_shader_parameter("body", body)
	mat.set_shader_parameter("bright", bright)
	mat.set_shader_parameter("rim", rim)
	mat.set_shader_parameter("rim_strength", rim_strength)
	mat.set_shader_parameter("sculpt", sculpt)
	return mat


func _build_cast() -> void:
	var sheet_path: String = String(_cfg.get("cast_sheet", "res://assets/ui/loading_cast.png"))
	var tex: Texture2D = load(sheet_path) as Texture2D
	if tex == null:
		return
	var cols: int = int(_cfg.get("cols", 12))
	var rows: int = int(_cfg.get("rows", 5))
	var feet: Array = _cfg.get("feet", [32, 61]) as Array
	var cast: Array = _cfg.get("cast", []) as Array
	for slot: int in 3:
		var index: int = 0 if slot == 0 else (companions[slot - 1] if slot - 1 < companions.size() else -1)
		if index < 0 or index >= cast.size():
			continue
		var spec: Dictionary = cast[index] as Dictionary
		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture = tex
		sprite.centered = false
		sprite.hframes = cols
		sprite.vframes = rows
		sprite.offset = -Vector2(float(feet[0]), float(feet[1]))
		sprite.z_index = 4
		var mat: ShaderMaterial = _silhouette_material(HERO_SHADE, HERO_BODY, HERO_BRIGHT, HERO_EDGE, 0.92, 0.85)
		sprite.material = mat
		sprite.visible = false
		_stage.add_child(sprite)
		_actors.append({
			"sprite": sprite,
			"mat": mat,
			"slot": slot,
			"row": int(spec.get("row", 0)),
			"count": maxi(1, int(spec.get("count", 6))),
			"stride": float(spec.get("walk_stride", 4.7)),
			"x": SLOT_X[slot],
			"dissolve": 0.0,
		})


func _build_bird() -> void:
	var sheet_path: String = String(_cfg.get("cast_sheet", "res://assets/ui/loading_cast.png"))
	var tex: Texture2D = load(sheet_path) as Texture2D
	if tex == null:
		return
	_bird_cfg = _cfg.get("bird", {}) as Dictionary
	var center: Array = _bird_cfg.get("center", [32, 32]) as Array
	_bird = Sprite2D.new()
	_bird.texture = tex
	_bird.centered = false
	_bird.hframes = int(_cfg.get("cols", 12))
	_bird.vframes = int(_cfg.get("rows", 5))
	_bird.offset = -Vector2(float(center[0]), float(center[1]))
	_bird.z_index = 6
	_bird_mat = _silhouette_material(Color("b9a4f4"), Color("e5dcff"), Color("f8f4ff"), Color("ffffff"), 0.95, 0.8)
	_bird.material = _bird_mat
	_bird.visible = false
	_stage.add_child(_bird)


func _build_scenery() -> void:
	var specs: Array = _cfg.get("scenery", []) as Array
	if specs.is_empty():
		return
	for entry: Dictionary in SCENERY_SLOTS:
		var kind_idx: int = posmod(int(entry.get("kind", 0)), specs.size())
		var spec: Dictionary = specs[kind_idx] as Dictionary
		var tex: Texture2D = load(String(spec.get("sheet", ""))) as Texture2D
		if tex == null:
			continue
		var feet: Array = spec.get("feet", [20, 30]) as Array
		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture = tex
		sprite.centered = false
		sprite.hframes = maxi(1, int(spec.get("hframes", 5)))
		sprite.vframes = maxi(1, int(spec.get("vframes", 1)))
		sprite.frame = posmod(int(entry.get("variant", 0)), sprite.hframes)
		sprite.offset = -Vector2(float(feet[0]), float(feet[1]))
		sprite.z_index = int(entry.get("z", 1))
		var is_fore: bool = sprite.z_index >= 5
		var mat: ShaderMaterial = _silhouette_material(
			PROP_SHADE.darkened(0.16) if is_fore else PROP_SHADE,
			PROP_BODY.darkened(0.10) if is_fore else PROP_BODY,
			PROP_BRIGHT,
			PROP_EDGE,
			0.78,
			0.8
		)
		var glow_path: String = String(spec.get("glow", ""))
		if not glow_path.is_empty() and ResourceLoader.exists(glow_path):
			mat.set_shader_parameter("glow_tex", load(glow_path) as Texture2D)
			mat.set_shader_parameter("glow_amount", float(spec.get("glow_amount", 0.8)))
			mat.set_shader_parameter("glow_tint", Color(String(spec.get("glow_tint", "#78f4e6"))))
		sprite.material = mat
		_stage.add_child(sprite)
		_scenery.append({
			"sprite": sprite,
			"mat": mat,
			"offset": float(entry.get("offset", 0.0)),
			"dy": float(entry.get("dy", 0.0)),
			"sway": float(spec.get("sway", 0.0)),
		})


func _build_waystone() -> void:
	_beam = ColorRect.new()
	_beam.size = Vector2(36.0, 132.0)
	_beam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_beam.z_index = 2
	_beam_mat = ShaderMaterial.new()
	_beam_mat.shader = BEAM_SHADER
	_beam_mat.set_shader_parameter("rect_size", _beam.size)
	_beam_mat.set_shader_parameter("tone_low", Color("78f4e6"))
	_beam_mat.set_shader_parameter("tone_high", Color("b99bff"))
	_beam_mat.set_shader_parameter("strength", 0.0)
	_beam.material = _beam_mat
	_beam.visible = false
	_stage.add_child(_beam)

	_waystone = Sprite2D.new()
	_waystone.texture = STATUE_CLEAN
	_waystone.centered = false
	_waystone.offset = Vector2(-52.0, -94.0)
	_waystone.z_index = 3
	_waystone_mat = _silhouette_material(Color("937ce0"), Color("d0c2fb"), Color("f0eaff"), Color("ffffff"), 0.95, 0.9)
	_waystone_mat.set_shader_parameter("glow_tex", STATUE_GLOW)
	_waystone_mat.set_shader_parameter("wave_tex", STATUE_WAVE)
	_waystone_mat.set_shader_parameter("glow_tint", TEAL_SPARK)
	_waystone_mat.set_shader_parameter("glow_amount", 0.0)
	_waystone_mat.set_shader_parameter("wave_progress", 0.0)
	_waystone.material = _waystone_mat
	_waystone.visible = false
	_stage.add_child(_waystone)


func complete() -> void:
	ready_to_leave = true


func advance(delta: float) -> void:
	if done:
		return
	age += delta
	if chase >= 0.0:
		chase += delta
		if chase >= CHASE_LENGTH:
			done = true
			finished.emit()
	elif ready_to_leave and age >= ENTRANCE_END:
		chase = 0.0
	_travel += delta * float(_cfg.get("walk_speed", 36.0))
	update_visuals(delta)
	queue_redraw()


func _process(delta: float) -> void:
	advance(minf(delta, 0.05))


func _origin() -> Vector2:
	return ((size - Vector2(640.0, 360.0)) * 0.5).round()


func _settle_offset(c: float) -> float:
	if c <= 0.0:
		return 0.0
	var v0: float = float(_cfg.get("walk_speed", 36.0))
	var u: float = clampf(c / CAMERA_SETTLE, 0.0, 1.0)
	return v0 * CAMERA_SETTLE * (1.0 - pow(1.0 - u, 3.0)) / 3.0


func _ground_scroll() -> float:
	if chase < 0.0:
		return _travel
	var v0: float = float(_cfg.get("walk_speed", 36.0))
	return (_travel - v0 * chase) + _settle_offset(chase)


func _waystone_x() -> float:
	if chase < 0.0:
		return WAYSTONE_FINAL_X + 24.0
	return WAYSTONE_FINAL_X + (_settle_offset(CAMERA_SETTLE) - _settle_offset(chase))


func _entry_x(slot: int) -> float:
	var entry: float = clampf((age - 0.18 - float(slot) * 0.24) / 1.35, 0.0, 1.0)
	var start_x: float = SLOT_X[slot] - 78.0
	return lerpf(start_x, SLOT_X[slot], 1.0 - pow(1.0 - entry, 3.0))


func _approach_extra(c: float) -> float:
	if c <= 0.25:
		return 0.0
	var v0: float = float(_cfg.get("walk_speed", 36.0))
	var top: float = maxf(0.0, float(_cfg.get("approach_speed", 104.0)) - v0)
	var tau: float = c - 0.25
	var ramp: float = 0.40
	if tau < ramp:
		return 0.5 * top / ramp * tau * tau
	return 0.5 * top * ramp + top * (tau - ramp)


func _ridge_appear(x: float) -> float:
	return smoothstep(126.0, 174.0, x) * (1.0 - smoothstep(476.0, 524.0, x))


func update_visuals(_delta: float) -> void:
	if _back_material == null:
		return
	var opening: float = _opening_override if _opening_override >= 0.0 else smoothstep(0.0, OPEN_SECONDS, age)
	var scroll: float = _ground_scroll()
	var wx: float = _waystone_x()
	var sanc_glow: float = smoothstep(0.18, 0.85, chase) if chase >= 0.0 else 0.0
	_back_material.set_shader_parameter("time", age)
	_back_material.set_shader_parameter("travel", scroll)
	_back_material.set_shader_parameter("view_size", size)
	_back_material.set_shader_parameter("opening", opening)
	_back_material.set_shader_parameter("sanctuary_x", roundf(wx))
	_back_material.set_shader_parameter("sanctuary_glow", sanc_glow)

	_stage.position = _origin()
	if _revealing:
		return

	var v0: float = float(_cfg.get("walk_speed", 36.0))
	var cols: int = int(_cfg.get("cols", 12))

	# Scenery along the luminous ridge
	for prop: Dictionary in _scenery:
		var psprite: Sprite2D = prop.sprite
		var pmat: ShaderMaterial = prop.mat
		var px: float = SCENERY_LEFT + fposmod(float(prop.offset) - scroll, SCENERY_SPAN)
		var vis: float = _ridge_appear(px) * smoothstep(0.15, 0.75, age)
		if chase >= 0.0:
			vis *= smoothstep(14.0, 38.0, absf(px - wx))
		psprite.visible = vis > 0.04
		if psprite.visible:
			var sway_px: float = roundf(sin(age * 1.9 + float(prop.offset) * 0.09) * 0.75) * float(prop.sway)
			psprite.position = Vector2(roundf(px + sway_px), HORIZON + float(prop.dy))
			pmat.set_shader_parameter("appear", clampf(vis, 0.0, 1.0))

	# Waystone sanctuary awakening during finale
	_waystone.visible = chase >= 0.0
	_beam.visible = chase >= 0.24
	if chase >= 0.0:
		var appear_w: float = smoothstep(0.0, 0.42, chase)
		var wave_p: float = smoothstep(0.24, 0.92, chase) * 1.18
		var glow_w: float = smoothstep(0.20, 0.55, chase) * (1.0 + 0.25 * sin(chase * 7.0))
		_waystone.position = Vector2(roundf(wx), HORIZON)
		_waystone_mat.set_shader_parameter("appear", appear_w)
		_waystone_mat.set_shader_parameter("wave_progress", wave_p)
		_waystone_mat.set_shader_parameter("glow_amount", glow_w)
		var beam_strength: float = smoothstep(0.28, 0.85, chase) * (0.85 + 0.15 * sin(age * 4.2))
		_beam.position = Vector2(roundf(wx - _beam.size.x * 0.5), HORIZON - 76.0 - _beam.size.y)
		_beam_mat.set_shader_parameter("strength", beam_strength)
		_beam_mat.set_shader_parameter("time", age)

	# Walkers: Ellie & two companions
	for actor: Dictionary in _actors:
		var sprite: Sprite2D = actor.sprite
		var mat: ShaderMaterial = actor.mat
		var slot: int = int(actor.slot)
		var start_time: float = 0.18 + float(slot) * 0.24
		var x0: float = _entry_x(slot)
		var extra: float = _approach_extra(chase) if chase >= 0.0 else 0.0
		var x: float = x0 + (v0 * chase + extra - _settle_offset(chase) if chase >= 0.0 else 0.0)
		var enter_alpha: float = smoothstep(start_time, start_time + 0.42, age) * smoothstep(134.0, 178.0, x)
		var dis: float = smoothstep(DISSOLVE_FROM_X, DISSOLVE_TO_X, x) if chase >= 0.0 else 0.0
		actor.x = x
		actor.dissolve = dis
		sprite.visible = enter_alpha > 0.04 and dis < 0.99
		if sprite.visible:
			var foot_dist: float = _travel + x0 + extra
			var count: int = int(actor.count)
			var col: int = posmod(int(floorf(foot_dist / float(actor.stride))), count)
			sprite.frame = int(actor.row) * cols + col
			sprite.position = Vector2(roundf(x), HORIZON)
			mat.set_shader_parameter("appear", enter_alpha)
			mat.set_shader_parameter("dissolve", dis)

	# Companion corvid soaring ahead
	if _bird != null:
		var bird_in: float = smoothstep(0.22, 1.45, age)
		var bx: float = lerpf(150.0, 392.0, 1.0 - pow(1.0 - bird_in, 2.6)) + sin(age * 1.25) * 14.0
		var by: float = lerpf(HORIZON - 66.0, HORIZON - 46.0, bird_in) + sin(age * 2.05 + 0.7) * 5.0
		var bird_dis: float = 0.0
		var gliding: bool = fposmod(age + 0.4, 2.6) > 1.65
		if chase >= 0.0:
			var swoop: float = smoothstep(0.0, 1.35, chase)
			bx = lerpf(bx, wx + 6.0, swoop) + sin(chase * 5.2) * 6.0 * swoop
			by = lerpf(by, HORIZON - 108.0, pow(swoop, 1.25))
			bird_dis = smoothstep(0.85, 1.45, chase)
			gliding = false
		var bird_appear: float = smoothstep(0.22, 0.65, age) * smoothstep(138.0, 180.0, bx)
		_bird.visible = bird_appear > 0.04 and bird_dis < 0.99
		if _bird.visible:
			var brow: int = int(_bird_cfg.get("row", 4))
			var flap: Array = _bird_cfg.get("flap", [0, 8]) as Array
			var glide: Array = _bird_cfg.get("glide", [8, 4]) as Array
			var fps: float = float(_bird_cfg.get("flap_fps", 8.2))
			var bcol: int = int(glide[0]) + posmod(int(age * 4.0), int(glide[1])) if gliding else int(flap[0]) + posmod(int(age * fps), int(flap[1]))
			_bird.frame = brow * cols + bcol
			_bird.position = Vector2(roundf(bx), roundf(by))
			_bird_mat.set_shader_parameter("appear", bird_appear)
			_bird_mat.set_shader_parameter("dissolve", bird_dis)

	_fx.queue_redraw()


func _draw_fx() -> void:
	if _revealing:
		return
	var scroll: float = _ground_scroll()
	var wx: float = roundf(_waystone_x())

	# Ambient rising pixel spores along the ridge
	var ridge_fade: float = smoothstep(0.2, 0.8, age)
	for i: int in 14:
		var seed_f: float = float(i) * 19.37 + 3.1
		var rate: float = 0.16 + fposmod(seed_f * 0.07, 0.14)
		var life: float = fposmod(age * rate + seed_f * 0.13, 1.0)
		var base_x: float = 165.0 + fposmod(seed_f * 43.0 - scroll * 0.35, 310.0)
		var sx: int = roundi(base_x + sin(life * TAU + seed_f) * 3.0)
		var sy: int = roundi(HORIZON - 3.0 - life * (26.0 + fposmod(seed_f * 7.0, 22.0)))
		var alpha: float = sin(life * PI) * ridge_fade * _ridge_appear(float(sx))
		if alpha > 0.28:
			var col: Color = TEAL_SPARK if i % 3 == 0 else (GOLD_SPARK if i % 7 == 0 else LILAC_SPARK)
			_fx.draw_rect(Rect2(Vector2(sx, sy), Vector2.ONE), Color(col, minf(alpha, 0.9)))

	# Guiding wisp floating ahead of Ellie -> darts into the waystone heart to wake it
	if not _actors.is_empty():
		var ellie_x: float = float((_actors[0] as Dictionary).x)
		var wisp_in: float = smoothstep(0.25, 0.75, age)
		var wisp_pos: Vector2 = Vector2(
			ellie_x + 15.0 + sin(age * 2.7) * 3.0,
			HORIZON - 27.0 + sin(age * 3.4 + 1.1) * 3.5
		)
		var wisp_alpha: float = wisp_in
		if chase >= 0.0:
			var dart: float = smoothstep(0.0, 0.30, chase)
			var heart: Vector2 = Vector2(wx, HORIZON - 43.0)
			wisp_pos = wisp_pos.lerp(heart, dart) + Vector2(0.0, -sin(dart * PI) * 10.0)
			wisp_alpha *= 1.0 - smoothstep(0.26, 0.42, chase)
		if wisp_alpha > 0.05:
			var wp: Vector2 = wisp_pos.round()
			_fx.draw_rect(Rect2(wp - Vector2.ONE, Vector2(2.0, 2.0)), Color(TEAL_CORE, wisp_alpha))
			var halo_a: float = wisp_alpha * (0.55 + 0.35 * sin(age * 8.0))
			for off: Vector2 in [Vector2(-2, 0), Vector2(2, -1), Vector2(0, -2), Vector2(-1, 2)]:
				_fx.draw_rect(Rect2(wp + off, Vector2.ONE), Color(TEAL_SPARK, halo_a))
			for m: int in 3:
				var lag: float = float(m + 1) * 0.14
				var mp: Vector2 = Vector2(
					wp.x - float(m + 1) * 4.0,
					wp.y + sin((age - lag) * 4.2 + float(m)) * 2.0
				).round()
				_fx.draw_rect(Rect2(mp, Vector2.ONE), Color(TEAL_SPARK, wisp_alpha * (0.65 - float(m) * 0.18)))

	# Waystone awakening ground rune-ring & dissolving walker starlight sparks
	if chase >= 0.24:
		var ring_t: float = clampf((chase - 0.24) / 0.85, 0.0, 1.0)
		if ring_t < 1.0:
			var rx: float = lerpf(8.0, 56.0, 1.0 - pow(1.0 - ring_t, 2.2))
			var ry: float = rx * 0.16
			var ra: float = (1.0 - ring_t) * 0.9
			for k: int in 16:
				var ang: float = float(k) / 16.0 * TAU + chase * 0.6
				var rp: Vector2 = Vector2(wx + cos(ang) * rx, HORIZON + sin(ang) * ry).round()
				_fx.draw_rect(Rect2(rp, Vector2.ONE), Color(TEAL_CORE if k % 2 == 0 else TEAL_SPARK, ra))

		for actor: Dictionary in _actors:
			var dis: float = float(actor.dissolve)
			if dis > 0.02:
				var ax: float = minf(float(actor.x), wx - 4.0)
				var slot_seed: float = float(int(actor.slot)) * 13.7
				for s: int in 16:
					var sf: float = float(s) * 7.3 + slot_seed
					var st: float = clampf(dis * 1.45 - fposmod(sf * 0.09, 0.42), 0.0, 1.0)
					if st <= 0.0 or st >= 1.0:
						continue
					var px: float = lerpf(ax + (fposmod(sf * 3.1, 14.0) - 7.0), wx + sin(st * 5.0 + sf) * 7.0, st)
					var py: float = HORIZON - 5.0 - fposmod(sf * 5.7, 36.0) - st * (42.0 + fposmod(sf * 4.3, 34.0))
					var sa: float = sin(st * PI)
					var scol: Color = TEAL_CORE if s % 3 == 0 else (TEAL_SPARK if s % 2 == 0 else (GOLD_SPARK if s % 5 == 0 else LILAC_SPARK))
					_fx.draw_rect(Rect2(Vector2(roundf(px), roundf(py)), Vector2.ONE), Color(scol, sa))


func _draw() -> void:
	if _revealing:
		return
	draw_set_transform(_origin())
	var fade: float = smoothstep(0.35, 0.95, age)
	if chase >= 0.0:
		fade *= 1.0 - clampf(chase * 2.2, 0.0, 1.0)
	var caption: String = "LÄDT" + ".".repeat(1 + int(age * 2.0) % 3)
	var x: int = 320 - PixelText.width("LÄDT...") / 2
	var ink: Color = Color("cbb8ff")
	if not error_text.is_empty():
		caption = error_text
		x = 320 - PixelText.width(caption) / 2
		ink = Color("ff7a7a")
		fade = 1.0
	if fade > 0.01:
		PixelText.draw(self, caption, Vector2i(x, int(HORIZON) + 24), Color(ink, fade * 0.88), Color("040208", fade))
	draw_set_transform(Vector2.ZERO)


func reveal_world() -> void:
	_revealing = true
	_backing.hide()
	_stage.hide()
	queue_redraw()
	var tween: Tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_method(_set_opening, 1.0, 0.0, CLOSE_SECONDS)
	await tween.finished
	hide()


func _set_opening(value: float) -> void:
	_opening_override = value
	update_visuals(0.0)
