class_name StarHallGoddess
extends Interactable
## Redesigned Caelia ("Die Wächterin"), freely floating in open interstellar space
## (docs/caelia_interstellar_konzept.md).
##   - Reads her 8-direction floating sprite & unlit glow sheets from `data/goddess_rig.json`
##     (`assets/characters/goddess.png` + `goddess_glow.png`, 128x144 frames, center anchor (64, 78)).
##   - Gracefully tracks nearby players across all 8 real directions (E..NE) with smooth turn cadence
##     as Ellie orbits around her in zero gravity.
##   - Breathes on a calm Lissajous zero-G float curve and drifts softly a few pixels toward Ellie
##     when she approaches, while orbiting Waystone Starlight Nodes grow around her astrolabe crown.

const RIG_PATH: String = "res://data/goddess_rig.json"
const SHEET_TEX: Texture2D = preload("res://assets/characters/goddess.png")
const GLOW_TEX: Texture2D = preload("res://assets/characters/goddess_glow.png")
const REACH: float = 64.0
const TURN_STEP_SECONDS: float = 0.14
const FACING_NAMES: Array[String] = ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]

var _fw: int = 128
var _fh: int = 144
var _anchor: Vector2 = Vector2(64.0, 78.0)
var _clips: Dictionary = {}
var _row_by_facing: Dictionary = {"E": 0, "SE": 1, "S": 2, "SW": 3, "W": 4, "NW": 5, "N": 6, "NE": 7}

var _visual: Node2D
var _sprite: Sprite2D
var _glow: Sprite2D
var _orbit_fx: Node2D
var _aura_light: PointLight2D

var _clip: String = "float_idle"
var _clip_t: float = 0.0
var _talking: bool = false
var _bless_left: float = 0.0
var _sector: int = 2 ## 2 = S default
var _turn_cd: float = 0.0
var _time: float = 0.0
var _approach_offset: Vector2 = Vector2.ZERO
var _awake_nodes: int = 1
var _waystones_bound: bool = false


func _ready() -> void:
	name = "StarHallGoddess"
	add_to_group("quest_actors")
	_load_rig()

	_visual = Node2D.new()
	_visual.name = "FloatVisual"
	add_child(_visual)

	var off: Vector2 = -_anchor
	_sprite = Sprite2D.new()
	_sprite.name = "Body"
	_sprite.texture = SHEET_TEX
	_sprite.centered = false
	_sprite.offset = off
	_sprite.region_enabled = true
	_visual.add_child(_sprite)

	_glow = Sprite2D.new()
	_glow.name = "Glow"
	_glow.texture = GLOW_TEX
	_glow.centered = false
	_glow.offset = off
	_glow.region_enabled = true
	_glow.material = Unlit.material()
	_visual.add_child(_glow)

	_orbit_fx = Node2D.new()
	_orbit_fx.name = "AstrolabeNodes"
	_orbit_fx.material = Unlit.material()
	_orbit_fx.z_index = 2
	_orbit_fx.draw.connect(_draw_orbit_nodes)
	_visual.add_child(_orbit_fx)

	_aura_light = PointLight2D.new()
	_aura_light.position = Vector2(0.0, -14.0)
	_aura_light.color = Color("d8f8ff")
	_aura_light.energy = 0.16
	LightTexture.apply(_aura_light, 200, 0.84, 0)
	_visual.add_child(_aura_light)

	_refresh_awake_nodes()
	_apply_frame(0)


func _load_rig() -> void:
	if not FileAccess.file_exists(RIG_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RIG_PATH))
	if not (parsed is Dictionary):
		return
	var rig: Dictionary = parsed as Dictionary
	var fs: Array = rig.get("frame_size", [128, 144]) as Array
	if fs.size() >= 2:
		_fw = int(fs[0])
		_fh = int(fs[1])
	var ft: Array = rig.get("feet", [64, 78]) as Array
	if ft.size() >= 2:
		_anchor = Vector2(float(ft[0]), float(ft[1]))
	if rig.has("clips") and rig["clips"] is Dictionary:
		_clips = rig["clips"] as Dictionary
	if rig.has("row_by_facing") and rig["row_by_facing"] is Dictionary:
		_row_by_facing = rig["row_by_facing"] as Dictionary
	_sector = int(rig.get("default_row", 2))


func prompt() -> String:
	var sys: GoddessSystem = GoddessSystem.of(get_tree())
	if sys != null and sys.is_busy():
		return ""
	for p: Player in Player.all:
		if is_instance_valid(p) and p.is_multiplayer_authority():
			if sys != null and sys.has_light_step_player(p):
				return "STERNENGABEN"
			break
	return "SPRECHEN"


func reach_distance(from: Vector2) -> float:
	return from.distance_to(global_position) - REACH


func prompt_position() -> Vector2:
	return Vector2(0.0, -68.0)


func interact(player: Player) -> void:
	var sys: GoddessSystem = GoddessSystem.of(get_tree())
	if sys != null:
		sys.talk_to_goddess(player, self)


func actor_position(id: String) -> Vector2:
	if id != "caelia":
		return Vector2.INF
	return GoddessSystem.starhall_world_anchor(get_tree(), global_position)


func set_talking(on: bool) -> void:
	_talking = on
	if on and _bless_left <= 0.0:
		_set_clip("float_talk")
	elif not on and _bless_left <= 0.0:
		_set_clip("float_idle")


func play_bless() -> void:
	var cfg: Dictionary = _clips.get("float_bless", {}) as Dictionary
	var count: int = maxi(1, int(cfg.get("count", 12)))
	var fps: float = maxf(1.0, float(cfg.get("fps", 8.0)))
	_bless_left = float(count) / fps + 0.15
	_set_clip("float_bless")


func current_sector() -> int:
	return _sector


func _set_clip(clip_name: String) -> void:
	if _clip == clip_name:
		return
	_clip = clip_name
	_clip_t = 0.0


func _refresh_awake_nodes() -> void:
	var ws: Waystones = Waystones.of(get_tree())
	_awake_nodes = clampi(ws.awake_count() if ws != null else 1, 1, 8)


func _process(delta: float) -> void:
	_time += delta
	_clip_t += delta

	if not _waystones_bound:
		var ws: Waystones = Waystones.of(get_tree())
		if ws != null:
			_waystones_bound = true
			if not ws.awakened.is_connected(_on_waystone_awakened):
				ws.awakened.connect(_on_waystone_awakened)
			_refresh_awake_nodes()

	if _bless_left > 0.0:
		_bless_left = maxf(_bless_left - delta, 0.0)
		if _bless_left <= 0.0:
			_clip = "float_talk" if _talking else "float_idle"
			_clip_t = 0.0

	_update_facing_and_drift(delta)

	var cfg: Dictionary = _clips.get(_clip, {"start": 0, "count": 8, "fps": 6, "loop": true}) as Dictionary
	var start: int = int(cfg.get("start", 0))
	var count: int = maxi(1, int(cfg.get("count", 8)))
	var fps: float = maxf(1.0, float(cfg.get("fps", 6.0)))
	var loops: bool = bool(cfg.get("loop", true))
	var idx: int = int(_clip_t * fps)
	idx = idx % count if loops else mini(idx, count - 1)
	_apply_frame(start + idx)

	# Serene weightless Lissajous floating motion + subtle emotional lean toward Ellie
	var bob: Vector2 = Vector2(sin(_time * 0.58) * 1.6, sin(_time * 1.05) * 4.2)
	if _visual != null:
		_visual.position = (bob + _approach_offset).round()

	if _glow != null:
		var glow_pulse: float = 0.90 + 0.10 * sin(_time * 2.1)
		_glow.modulate.a = 1.0 if _bless_left > 0.0 else glow_pulse

	if _aura_light != null:
		var pulse: float = 0.5 + 0.5 * sin(_time * 2.4)
		_aura_light.energy = (0.26 if _bless_left > 0.0 else 0.14) + 0.04 * pulse

	if _orbit_fx != null:
		_orbit_fx.queue_redraw()


func _update_facing_and_drift(delta: float) -> void:
	_turn_cd = maxf(_turn_cd - delta, 0.0)
	var nearest: Player = null
	var best_d: float = 420.0
	for p: Player in Player.all:
		if not is_instance_valid(p):
			continue
		var d: float = p.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			nearest = p

	var want_sector: int = 2 # Default facing South toward the arrival rift
	var approach_goal: Vector2 = Vector2.ZERO
	if nearest != null:
		var to_p: Vector2 = nearest.global_position - global_position
		if to_p.length_squared() > 16.0:
			var ang: float = to_p.angle() / (PI / 4.0)
			if absf(wrapf(ang - float(_sector), -4.0, 4.0)) > 0.55:
				want_sector = posmod(roundi(ang), 8)
			else:
				want_sector = _sector
			# Gently drift 9 px toward Ellie when she hovers within greeting distance
			if best_d < 220.0 and best_d > 42.0:
				var pull_k: float = smoothstep(220.0, 68.0, best_d)
				approach_goal = to_p.normalized() * (9.5 * pull_k)

	if want_sector != _sector and _turn_cd <= 0.0:
		var diff: int = posmod(want_sector - _sector + 4, 8) - 4
		_sector = posmod(_sector + (1 if diff > 0 else -1), 8)
		_turn_cd = TURN_STEP_SECONDS

	_approach_offset = _approach_offset.lerp(approach_goal, 1.0 - exp(-2.0 * delta))


func _apply_frame(col: int) -> void:
	var key: String = FACING_NAMES[clampi(_sector, 0, FACING_NAMES.size() - 1)]
	var row_i: int = int(_row_by_facing.get(key, _sector))
	var r: Rect2 = Rect2(float(col * _fw), float(row_i * _fh), float(_fw), float(_fh))
	if _sprite != null:
		_sprite.region_rect = r
	if _glow != null:
		_glow.region_rect = r


func _draw_orbit_nodes() -> void:
	# Dynamic starlight motes orbiting Caelia's astrolabe crown — one bright node per awakened Waystone!
	var center: Vector2 = Vector2(0.0, -36.0)
	var bless_boost: float = 1.0 if _bless_left > 0.0 else 0.0
	var count: int = _awake_nodes
	for i: int in count:
		var ang: float = _time * (0.62 + 0.14 * bless_boost) + float(i) * (TAU / float(maxi(count, 1)))
		var rx: float = (29.0 + 5.0 * bless_boost) * cos(ang)
		var ry: float = (13.0 + 3.0 * bless_boost) * sin(ang)
		var tilt: float = -0.26
		var p: Vector2 = center + Vector2(roundf(rx * cos(tilt) - ry * sin(tilt)), roundf(rx * sin(tilt) + ry * cos(tilt)))
		var front: bool = sin(ang) >= 0.0
		var col: Color = Color("fff4c2") if (i % 2 == 0) else Color("c8fff8")
		var rim: Color = Color("e6c468") if (i % 2 == 0) else Color("58ece0")
		var alpha: float = (0.95 if front else 0.50) * (0.85 + 0.15 * sin(_time * 2.8 + float(i)))
		_orbit_fx.draw_rect(Rect2(p, Vector2(1.0, 1.0)), Color(col.r, col.g, col.b, alpha))
		if front or bless_boost > 0.0:
			var ra: float = alpha * 0.55
			_orbit_fx.draw_rect(Rect2(p + Vector2(-1.0, 0.0), Vector2(1.0, 1.0)), Color(rim.r, rim.g, rim.b, ra))
			_orbit_fx.draw_rect(Rect2(p + Vector2(1.0, 0.0), Vector2(1.0, 1.0)), Color(rim.r, rim.g, rim.b, ra))
			_orbit_fx.draw_rect(Rect2(p + Vector2(0.0, -1.0), Vector2(1.0, 1.0)), Color(rim.r, rim.g, rim.b, ra))
			_orbit_fx.draw_rect(Rect2(p + Vector2(0.0, 1.0), Vector2(1.0, 1.0)), Color(rim.r, rim.g, rim.b, ra))


func _on_waystone_awakened(_id: String) -> void:
	_refresh_awake_nodes()
