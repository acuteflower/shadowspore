class_name SanctuaryRuin
extends Interactable
## Y-sorted 3/4 Standing Sanctuary Ruin Companion Prop (`Ancient Stones 2.0`):
##   - `sanctuary_waymarker` (cells 0..1): tilted runic milestone stele with moss cap & nocturnal rune glow
##   - `fallen_column_drum`  (cells 2..3): fluted limestone column drum overgrown with creeping ivy
##   - `sanctuary_parapet`   (cells 4..5): coursed ashlar shrine parapet wall with overhanging coping cap
##   - `ancient_dew_basin`   (cells 6..7): carved sanctuary basin that fills with shimmering `star_dew_drop`
##     during morning dew (`05:00..09:30`), rain (`WeatherManager`), or overnight until scooped with `[E]`!

const RUIN_TEX_PATH: String = "res://assets/props/sanctuary_ruins.png"
const RUIN_GLOW_PATH: String = "res://assets/props/sanctuary_ruins_glow.png"
const LIT_SHADER: Shader = preload("res://assets/shaders/ground_prop_lit.gdshader")
const CELL_SIZE: Vector2 = Vector2(48.0, 40.0)
const FOOT_PIVOT: Vector2 = Vector2(-24.0, -34.0)

const SPECS: Dictionary = {
	"sanctuary_waymarker": {"cells": [0, 1], "col_size": Vector2(12.0, 6.0), "radius": 9.0, "glow": true, "basin": false},
	"fallen_column_drum": {"cells": [2, 3], "col_size": Vector2(22.0, 8.0), "radius": 13.0, "glow": false, "basin": false},
	"sanctuary_parapet": {"cells": [4, 5], "col_size": Vector2(30.0, 8.0), "radius": 16.0, "glow": false, "basin": false},
	"ancient_dew_basin": {"cells": [6, 7], "col_size": Vector2(20.0, 8.0), "radius": 13.0, "glow": true, "basin": true},
}

static var _shared_lit_mat: ShaderMaterial

@export var ruin_kind: String = "sanctuary_waymarker"
@export var variant: int = 0
@export var flip_ruin: bool = false

var scooped_today: bool = false
var _last_day: int = -1
var _dew_filled: bool = false
var _sprite: Sprite2D
var _glow: Sprite2D
var _body: StaticBody2D
var _droplets: Array[Dictionary] = []


static func _lit_material() -> ShaderMaterial:
	if _shared_lit_mat == null:
		_shared_lit_mat = ShaderMaterial.new()
		_shared_lit_mat.shader = LIT_SHADER
	return _shared_lit_mat


func setup_ruin(kind: String, world_pos: Vector2, var_idx: int = 0, flipped: bool = false) -> void:
	ruin_kind = kind if SPECS.has(kind) else "sanctuary_waymarker"
	variant = maxi(0, var_idx)
	flip_ruin = flipped
	position = world_pos.round()


func _ready() -> void:
	var spec: Dictionary = SPECS.get(ruin_kind, SPECS["sanctuary_waymarker"]) as Dictionary
	var cells: Array = spec["cells"] as Array
	var cell_idx: int = int(cells[variant % cells.size()])

	_sprite = Sprite2D.new()
	_sprite.name = "RuinSprite"
	_sprite.texture = load(RUIN_TEX_PATH) as Texture2D
	_sprite.region_enabled = true
	_sprite.region_rect = Rect2(float(cell_idx) * CELL_SIZE.x, 0.0, CELL_SIZE.x, CELL_SIZE.y)
	_sprite.centered = false
	_sprite.offset = FOOT_PIVOT
	_sprite.flip_h = flip_ruin
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.material = _lit_material()
	add_child(_sprite)

	if bool(spec["glow"]):
		_glow = Sprite2D.new()
		_glow.name = "RuinGlow"
		_glow.texture = load(RUIN_GLOW_PATH) as Texture2D
		_glow.region_enabled = true
		_glow.region_rect = _sprite.region_rect
		_glow.centered = false
		_glow.offset = FOOT_PIVOT
		_glow.flip_h = flip_ruin
		_glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_glow.material = Unlit.material()
		_glow.visible = false
		add_child(_glow)

	# Compact foot collision on World Layer 1 so entities walk cleanly around the ruin base!
	_body = StaticBody2D.new()
	_body.name = "FootBody"
	_body.collision_layer = 1
	_body.collision_mask = 0
	var col: CollisionShape2D = CollisionShape2D.new()
	var rect_shape: RectangleShape2D = RectangleShape2D.new()
	rect_shape.size = spec["col_size"] as Vector2
	col.shape = rect_shape
	col.position = Vector2(0.0, -3.0)
	_body.add_child(col)
	add_child(_body)

	_sync_visuals(true)


func _process(delta: float) -> void:
	_sync_visuals(false)
	if not _droplets.is_empty():
		var i: int = _droplets.size() - 1
		while i >= 0:
			var d: Dictionary = _droplets[i]
			var age: float = float(d["age"]) + delta
			if age >= float(d["life"]):
				_droplets.remove_at(i)
			else:
				d["age"] = age
				d["pos"] = (d["pos"] as Vector2) + (d["vel"] as Vector2) * delta
				d["z"] = maxf(0.0, float(d["z"]) + float(d["vz"]) * delta)
				d["vz"] = float(d["vz"]) - 95.0 * delta
			i -= 1
		queue_redraw()


func _draw() -> void:
	for d: Dictionary in _droplets:
		var p: Vector2 = Vector2(roundf((d["pos"] as Vector2).x), roundf((d["pos"] as Vector2).y - float(d["z"])))
		var alpha: float = clampf(1.0 - float(d["age"]) / float(d["life"]), 0.0, 1.0)
		var c: Color = d["col"] as Color
		c.a = alpha
		draw_rect(Rect2(p, Vector2(2.0, 1.0)), c)


func _is_basin() -> bool:
	var spec: Dictionary = SPECS.get(ruin_kind, SPECS["sanctuary_waymarker"]) as Dictionary
	return bool(spec["basin"])


func _compute_dew_available() -> bool:
	if not _is_basin() or scooped_today:
		return false
	var tod: float = TimeManager.time_of_day
	var morning_or_night: bool = (tod >= 0.18 and tod <= 0.44) or TimeManager.night_amount() > 0.25
	var wet_weather: bool = WeatherManager.current != null and (WeatherManager.current.rain > 0.08 or WeatherManager.current.ground_wet > 0.22)
	return morning_or_night or wet_weather


func _sync_visuals(force: bool) -> void:
	if TimeManager.day != _last_day:
		_last_day = TimeManager.day
		scooped_today = false

	if _is_basin():
		var filled: bool = _compute_dew_available()
		if force or filled != _dew_filled:
			_dew_filled = filled
			var c_idx: int = 7 if filled else 6
			var r: Rect2 = Rect2(float(c_idx) * CELL_SIZE.x, 0.0, CELL_SIZE.x, CELL_SIZE.y)
			if _sprite != null:
				_sprite.region_rect = r
			if _glow != null:
				_glow.region_rect = r
			if _prompt_node != null and _prompt_node.visible:
				set_focused(true)

	if _glow != null:
		var night: float = TimeManager.night_amount()
		if _is_basin() and _dew_filled:
			_glow.visible = true
			var shimmer: float = 0.68 + 0.24 * sin(Time.get_ticks_msec() * 0.0024 + position.x * 0.1)
			_glow.modulate.a = lerpf(0.28, 0.85, night) * shimmer
		else:
			_glow.visible = night > 0.04
			if _glow.visible:
				var pulse: float = 0.74 + 0.26 * sin(Time.get_ticks_msec() * 0.0019 + position.x * 0.05)
				_glow.modulate.a = smoothstep(0.04, 0.85, night) * pulse


func is_depleted() -> bool:
	return not _is_basin() or not _dew_filled


func spec() -> Dictionary:
	if _is_basin():
		return {"pickup": {"item": "star_dew_drop", "prompt": "TAUSCHALE SCHÖPFEN"}}
	return {}


func reach_distance(from: Vector2) -> float:
	var spec: Dictionary = SPECS.get(ruin_kind, SPECS["sanctuary_waymarker"]) as Dictionary
	return maxf(0.0, global_position.distance_to(from) - float(spec["radius"]))


func prompt_position() -> Vector2:
	return Vector2(0.0, -28.0)


func prompt() -> String:
	if not _is_basin():
		return ""
	if _dew_filled:
		return "TAUSCHALE SCHÖPFEN"
	return ""


func interact(player: Player) -> void:
	if not _is_basin() or not _dew_filled or player == null:
		return
	var toward: Vector2 = (global_position - player.global_position).normalized()
	player.begin_pick(toward if toward.length_squared() > 0.01 else Vector2.UP, func() -> void:
		_rpc_scoop_dew.rpc_id(1, player.get_multiplayer_authority())
	)


@rpc("any_peer", "call_local", "reliable")
func _rpc_scoop_dew(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if not _compute_dew_available():
		return
	scooped_today = true
	for p: Player in Player.all:
		if is_instance_valid(p) and p.get_multiplayer_authority() == peer_id and p.inventory != null:
			p.inventory.give("star_dew_drop", 2)
			break
	_rpc_apply_scooped.rpc(true)


@rpc("authority", "call_local", "reliable")
func _rpc_apply_scooped(scooped: bool) -> void:
	scooped_today = scooped
	_sync_visuals(true)
	if scooped:
		for i: int in 9:
			var ang: float = randf() * TAU
			var spd: float = randf_range(12.0, 28.0)
			_droplets.append({
				"pos": Vector2(randf_range(-5.0, 5.0), -13.0),
				"vel": Vector2(cos(ang), sin(ang) * 0.55) * spd,
				"z": 2.0,
				"vz": randf_range(26.0, 48.0),
				"age": 0.0,
				"life": randf_range(0.32, 0.55),
				"col": Color("d0fff8") if (i % 2 == 0) else Color("3cc0c6"),
			})
		Sfx.at(self, "pluck", global_position, -4.0, 0.08)
		queue_redraw()
