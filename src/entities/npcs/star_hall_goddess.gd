class_name StarHallGoddess
extends Interactable
## Caelia ("Die Wächterin"), the starlight goddess seated on the northern throne of the Star Hall.
## Reads her spritesheet and rig from `data/goddess_rig.json` (`assets/characters/goddess.png` + `goddess_glow.png`).
## Handles facing toward Ellie, clip transitions (sit_idle / sit_talk / sit_bless), and starting her dialogue.

const RIG_PATH: String = "res://data/goddess_rig.json"
const SHEET_TEX: Texture2D = preload("res://assets/characters/goddess.png")
const GLOW_TEX: Texture2D = preload("res://assets/characters/goddess_glow.png")
const REACH: float = 52.0

var _fw: int = 96
var _fh: int = 112
var _foot: Vector2 = Vector2(48.0, 94.0)
var _clips: Dictionary = {}
var _row_by_facing: Dictionary = {"S": 0, "SE": 1, "SW": 2}
var _sprite: Sprite2D
var _glow: Sprite2D
var _clip: String = "sit_idle"
var _clip_t: float = 0.0
var _talking: bool = false
var _bless_left: float = 0.0
var _row: int = 0
var _aura_light: PointLight2D


func _ready() -> void:
	name = "StarHallGoddess"
	add_to_group("quest_actors")
	_load_rig()
	var off: Vector2 = -_foot
	_sprite = Sprite2D.new()
	_sprite.name = "Body"
	_sprite.texture = SHEET_TEX
	_sprite.centered = false
	_sprite.offset = off
	_sprite.region_enabled = true
	add_child(_sprite)

	_glow = Sprite2D.new()
	_glow.name = "Glow"
	_glow.texture = GLOW_TEX
	_glow.centered = false
	_glow.offset = off
	_glow.region_enabled = true
	_glow.material = Unlit.material()
	add_child(_glow)

	_aura_light = PointLight2D.new()
	_aura_light.position = Vector2(0.0, -34.0)
	_aura_light.color = Color("d8f8ff")
	_aura_light.energy = 0.22
	LightTexture.apply(_aura_light, 148, 0.72, 0)
	add_child(_aura_light)
	_apply_frame(0)


func _load_rig() -> void:
	if not FileAccess.file_exists(RIG_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RIG_PATH))
	if not (parsed is Dictionary):
		return
	var rig: Dictionary = parsed as Dictionary
	var fs: Array = rig.get("frame_size", [96, 112]) as Array
	if fs.size() >= 2:
		_fw = int(fs[0])
		_fh = int(fs[1])
	var ft: Array = rig.get("feet", [48, 94]) as Array
	if ft.size() >= 2:
		_foot = Vector2(float(ft[0]), float(ft[1]))
	if rig.has("clips") and rig["clips"] is Dictionary:
		_clips = rig["clips"] as Dictionary
	if rig.has("row_by_facing") and rig["row_by_facing"] is Dictionary:
		_row_by_facing = rig["row_by_facing"] as Dictionary


func prompt() -> String:
	var sys: GoddessSystem = GoddessSystem.of(get_tree())
	if sys != null and sys.is_busy():
		return ""
	return "SPRECHEN"


func reach_distance(from: Vector2) -> float:
	return from.distance_to(global_position) - REACH


func prompt_position() -> Vector2:
	return Vector2(0.0, -76.0)


func interact(player: Player) -> void:
	var sys: GoddessSystem = GoddessSystem.of(get_tree())
	if sys != null:
		sys.talk_to_goddess(player, self)


func set_talking(on: bool) -> void:
	_talking = on
	if on and _bless_left <= 0.0:
		_set_clip("sit_talk")
	elif not on and _bless_left <= 0.0:
		_set_clip("sit_idle")


func play_bless() -> void:
	var cfg: Dictionary = _clips.get("sit_bless", {}) as Dictionary
	var count: int = maxi(1, int(cfg.get("count", 8)))
	var fps: float = maxf(1.0, float(cfg.get("fps", 8.0)))
	_bless_left = float(count) / fps + 0.15
	_set_clip("sit_bless")


func _set_clip(clip_name: String) -> void:
	if _clip == clip_name:
		return
	_clip = clip_name
	_clip_t = 0.0


func _process(delta: float) -> void:
	_clip_t += delta
	if _bless_left > 0.0:
		_bless_left = maxf(_bless_left - delta, 0.0)
		if _bless_left <= 0.0:
			_clip = "sit_talk" if _talking else "sit_idle"
			_clip_t = 0.0

	_update_facing()

	var cfg: Dictionary = _clips.get(_clip, {"start": 0, "count": 6, "fps": 6, "loop": true}) as Dictionary
	var start: int = int(cfg.get("start", 0))
	var count: int = maxi(1, int(cfg.get("count", 6)))
	var fps: float = maxf(1.0, float(cfg.get("fps", 6.0)))
	var loops: bool = bool(cfg.get("loop", true))
	var idx: int = int(_clip_t * fps)
	idx = idx % count if loops else mini(idx, count - 1)
	_apply_frame(start + idx)

	if _aura_light != null:
		var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.0028)
		_aura_light.energy = (0.44 if _bless_left > 0.0 else 0.16) + 0.06 * pulse


func _update_facing() -> void:
	var nearest: Player = null
	var best_d: float = 220.0
	for p: Player in Player.all:
		if not is_instance_valid(p):
			continue
		var d: float = p.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			nearest = p
	var facing_key: String = "S"
	if nearest != null:
		var dx: float = nearest.global_position.x - global_position.x
		if dx > 28.0:
			facing_key = "SE"
		elif dx < -28.0:
			facing_key = "SW"
	_row = int(_row_by_facing.get(facing_key, 0))


func _apply_frame(col: int) -> void:
	var r: Rect2 = Rect2(float(col * _fw), float(_row * _fh), float(_fw), float(_fh))
	if _sprite != null:
		_sprite.region_rect = r
	if _glow != null:
		_glow.region_rect = r
