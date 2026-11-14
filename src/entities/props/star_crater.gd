class_name StarCrater
extends Interactable
## Glowing nocturnal meteorite crater dropped by `NightWonders` during a Starfall event (`docs/wiesenbiom_ausbau_konzept.md` Stufe 6).
## Sprite: `star_crater.png` + `star_crater_glow.png` (`192x48`, `3 cols x 1 row` of `64x48`, ground anchor `(32, 28)` -> `offset = (0, -4)`):
##  - `state_mode == 0`: Warm glowing night meteorite core — press E to harvest warm `star_shard` ore.
##  - `state_mode == 1`: Harvested crater hollow.
##  - `state_mode == 2`: Cooled dawn stone (faded out at sunrise if left unharvested).

const CRATER_TEX: String = "res://assets/props/star_crater.png"
const CRATER_GLOW: String = "res://assets/props/star_crater_glow.png"

var crater_id: int = 0
var wonders: NightWonders
var state_mode: int = 0

var _body: Sprite2D
var _glow: Sprite2D
var _light: NightLight
var _fx: Node2D
var _embers: Array[Dictionary] = []
var _time: float = 0.0
var _impact_age: float = 0.0


func setup(owner_wonders: NightWonders, cid: int, pos_px: Vector2, initial_state: int = 0) -> void:
	wonders = owner_wonders
	crater_id = cid
	position = pos_px.round()
	state_mode = clampi(initial_state, 0, 2)


func _ready() -> void:
	add_to_group("flora_glow")
	_build_visuals()
	_build_collider()
	_init_embers()
	_apply_visual_state()


func _build_visuals() -> void:
	var off: Vector2 = Vector2(0.0, -4.0) ## ground anchor (32, 28) in 64x48 frame -> -(28 - 24)
	if ResourceLoader.exists(CRATER_TEX):
		_body = Sprite2D.new()
		_body.texture = load(CRATER_TEX) as Texture2D
		_body.hframes = 3
		_body.frame = state_mode
		_body.offset = off
		add_child(_body)
	if ResourceLoader.exists(CRATER_GLOW):
		_glow = Sprite2D.new()
		_glow.texture = load(CRATER_GLOW) as Texture2D
		_glow.hframes = 3
		_glow.frame = state_mode
		_glow.offset = off
		_glow.material = Unlit.material()
		add_child(_glow)

	_light = NightLight.new()
	_light.position = Vector2(0.0, -6.0)
	_light.radius = 76
	_light.base_energy = 0.72
	_light.pulse = 0.16
	_light.glow_color = Color("ffb86c")
	add_child(_light)

	_fx = Node2D.new()
	_fx.z_index = 2
	_fx.material = Unlit.material()
	_fx.draw.connect(_draw_fx)
	add_child(_fx)


func _build_collider() -> void:
	var sb: StaticBody2D = StaticBody2D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var shape_node: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(24.0, 10.0)
	shape_node.shape = rect
	shape_node.position = Vector2(0.0, -2.0)
	sb.add_child(shape_node)
	add_child(sb)


func _init_embers() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = crater_id * 9187 + 443
	for i: int in 14:
		_embers.append({
			"x": rng.randf_range(-10.0, 10.0),
			"phase": rng.randf(),
			"speed": rng.randf_range(0.32, 0.58),
			"height": rng.randf_range(16.0, 30.0),
			"drift": rng.randf_range(-3.0, 3.0),
			"gold": (i % 3) != 0,
		})


func set_state_mode(new_mode: int) -> void:
	state_mode = clampi(new_mode, 0, 2)
	_apply_visual_state()


func cool_at_dawn() -> void:
	if state_mode == 0:
		set_state_mode(2)


func _apply_visual_state() -> void:
	var warm: bool = state_mode == 0
	if _body != null:
		_body.frame = state_mode
	if _glow != null:
		_glow.frame = state_mode
		_glow.visible = warm
	if _light != null:
		_light.base_energy = 0.72 if warm else 0.0
		_light.visible = warm
		_light.budgeted = warm
		if not warm:
			_light.energy = 0.0
	if not warm and _prompt_node != null:
		_prompt_node.show_text("", "")


func _process(delta: float) -> void:
	_time += delta
	_impact_age += delta
	var warm: bool = state_mode == 0
	if _glow != null and warm:
		var pulse: float = 0.80 + 0.20 * sin(_time * 2.8)
		_glow.modulate.a = clampf(lerpf(0.35, 1.0, TimeManager.night_amount()) * pulse, 0.0, 1.0)
	if _fx != null:
		if warm or _impact_age < 2.6:
			_fx.visible = true
			_fx.queue_redraw()
		elif _fx.visible:
			_fx.visible = false


func _draw_fx() -> void:
	if _impact_age < 2.5 and state_mode == 0:
		var k: float = clampf(_impact_age / 2.5, 0.0, 1.0)
		var r: float = lerpf(8.0, 42.0, k)
		var a: float = (1.0 - k) * 0.65
		var pts: PackedVector2Array = PackedVector2Array()
		for s: int in 25:
			var ang: float = float(s) / 24.0 * TAU
			pts.append(Vector2(cos(ang) * r, sin(ang) * r * 0.56 - 4.0))
		_fx.draw_polyline(pts, Color(1.0, 0.78, 0.42, a), 1.5)

	if state_mode != 0:
		return
	for e: Dictionary in _embers:
		var life: float = fposmod(_time * float(e.speed) + float(e.phase), 1.0)
		var sway: float = sin(_time * 2.4 + float(e.phase) * TAU) * float(e.drift)
		var pt: Vector2 = Vector2(float(e.x) + sway, -4.0 - life * float(e.height)).round()
		var alpha: float = (1.0 - life) * sin(life * PI) * 0.92
		var col: Color = Color(1.0, 0.84, 0.48, alpha) if bool(e.gold) else Color(0.76, 0.56, 1.0, alpha)
		_fx.draw_rect(Rect2(pt, Vector2(1.0, 1.0)), col)


func prompt() -> String:
	return "WARMES STERNERZ BERGEN" if state_mode == 0 else ""


func reach_distance(from: Vector2) -> float:
	return maxf(0.0, from.distance_to(global_position) - 24.0)


func prompt_position() -> Vector2:
	return Vector2(0.0, -28.0)


func interact(player: Player) -> void:
	if state_mode != 0 or player == null or player.is_busy() or wonders == null:
		return
	var aim: Vector2 = global_position - player.global_position
	var dir: Vector2 = aim.normalized() if aim.length_squared() > 1.0 else Vector2.DOWN
	player.begin_pick(dir, func() -> void:
		if is_instance_valid(wonders):
			wonders.request_harvest_crater(crater_id))
