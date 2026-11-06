class_name Adventurer
extends Node2D
## The adventurer of the wine-red order who saves Ellie (art: tools/art_adventurer.py -> assets/characters/adventurer.png, 8 rows = facing sectors
## like the heroine, clips in data/adventurer_rig.json: idle, run, slash_a/b/c, land). A cutscene actor: `play(clip, direction)` picks the clip and
## the facing, `strike` fires when a slash reaches its peak (frame 2). The sword's edge, the visor slit and the runes are a second, unlit sheet
## (`adventurer_glow.png`). `lit` puts a halo behind him (the backlit silhouette), `trail` leaves violet afterimages while he dashes.
## Runs on real time (unscaled), so slow motion does not slow his animation.

signal strike
signal clip_done

const SHEET: Texture2D = preload("res://assets/characters/adventurer.png")
const GLOW: Texture2D = preload("res://assets/characters/adventurer_glow.png")
const STRIKE_FRAME: int = 2
const MINE_STRIKE: int = 6 ## the frame of the `mine` loop where the pick bites
const HAMMER_STRIKE: int = 3 ## the frame of the `hammer` loop where the mallet hits the nail

var trail: bool = false
var lift: float = 0.0: ## px above the ground (the dive); the shadow stays down
	set(value):
		lift = value
		if _sprite != null:
			_sprite.offset.y = _base_offset - lift
			_glow.offset.y = _base_offset - lift
			_halo.position.y = -34.0 - lift
			queue_redraw()
var _base_offset: float = 0.0
var _held: int = -1 ## a frozen frame of the clip (-1 = the clip runs)
var _step_clock: float = 0.0
var walk_speed_scale: float = 1.0 ## scene-controlled cadence for walking clips
var lit: float = 0.0: ## 0..1 backlight
	set(value):
		lit = value
		if _halo != null:
			_halo.modulate.a = lit
			_light.base_energy = 1.3 * lit
var _rig: Dictionary
var _sprite: Sprite2D
var _glow: Sprite2D
var _halo: Sprite2D
var _light: NightLight
var _clip: Dictionary = {}
var _clip_name: String = ""
var _clip_time: float = 0.0
var _sector: int = 2
var _trail_clock: float = 0.0
var _fired: bool = false
var _time: float = 0.0


func _ready() -> void:
	_rig = DataRegistry.table("adventurer_rig")
	y_sort_enabled = false
	_halo = Sprite2D.new() ## a soft white-violet glow behind the figure
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, Color(0.86, 0.8, 1.0, 0.85))
	gradient.add_point(0.35, Color(0.62, 0.5, 1.0, 0.35))
	gradient.set_color(2, Color(0.4, 0.3, 0.9, 0.0))
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 192
	texture.height = 192
	_halo.texture = texture
	_halo.position = Vector2(0, -34)
	var add: CanvasItemMaterial = CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_halo.material = add
	_halo.z_index = -1
	_halo.modulate.a = 0.0
	add_child(_halo)
	_sprite = _make_sprite(SHEET)
	_glow = _make_sprite(GLOW)
	lift = lift
	_glow.material = Unlit.material()
	_light = NightLight.new()
	_light.position = Vector2(0, -26)
	_light.radius = 110
	_light.base_energy = 0.0
	_light.glow_color = Color("c8b8ff")
	add_child(_light)
	play("idle", Vector2.DOWN)


func _make_sprite(texture: Texture2D) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = texture
	sprite.hframes = int(_rig.get("frames", 1))
	sprite.vframes = 8
	var frame: Array = _rig.get("frame", [84, 80]) as Array
	var feet: Array = _rig.get("feet", [42, 66]) as Array
	_base_offset = float(frame[1]) * 0.5 - float(feet[1]) ## the feet sit on the node
	sprite.offset = Vector2(0, _base_offset)
	add_child(sprite)
	return sprite


## The sector (0 east, 1 south-east, 2 south, ... like Player._sector) that looks along `direction`.
static func sector_of(direction: Vector2) -> int:
	return posmod(roundi(direction.angle() / (PI / 4.0)), 8)


func play(clip: String, direction: Vector2) -> void:
	_clip_name = clip
	walk_speed_scale = 1.0
	_clip = (_rig.get("clips", {}) as Dictionary).get(clip, {}) as Dictionary
	_clip_time = 0.0
	_fired = false
	_held = -1
	if direction != Vector2.ZERO:
		_sector = sector_of(direction)
	_show()


## Shows one frame of a clip and holds it (the dive is steered by the cutscene).
func pose(clip: String, index: int, direction: Vector2) -> void:
	play(clip, direction)
	_held = index
	_show()


func face(direction: Vector2) -> void:
	if direction != Vector2.ZERO:
		_sector = sector_of(direction)
		_show()


func _frame_index() -> int:
	if _held >= 0:
		return _held
	var count: int = int(_clip.get("count", 1))
	var f: int = int(_clip_time * float(_clip.get("fps", 8)))
	return (f % count) if bool(_clip.get("loop", false)) else mini(f, count - 1)


func _show() -> void:
	var frame: int = int(_clip.get("start", 0)) + _frame_index()
	var index: int = _sector * int(_rig.get("frames", 1)) + frame
	_sprite.frame = index
	_glow.frame = index


func _process(delta: float) -> void:
	delta /= maxf(Engine.time_scale, 0.02) ## real time
	_time += delta
	_clip_time += delta * (walk_speed_scale if _clip_name in ["walk", "walk_mug", "carry_beam"] else 1.0)
	var local: int = int(_clip_time * float(_clip.get("fps", 8)))
	if _held < 0 and not _fired and _clip_name.begins_with("slash") and local >= STRIKE_FRAME:
		_fired = true
		strike.emit()
	if _held < 0 and (_clip_name == "mine" or _clip_name == "hammer"): ## a loop: the pick bites / the mallet hits once per round
		var in_round: int = local % int(_clip.get("count", 1))
		var at_frame: int = MINE_STRIKE if _clip_name == "mine" else HAMMER_STRIKE
		if in_round == at_frame and not _fired:
			_fired = true
			strike.emit()
		elif in_round != at_frame:
			_fired = false
	if _held < 0 and not bool(_clip.get("loop", false)) and local >= int(_clip.get("count", 1)) and _clip_name != "":
		var done: String = _clip_name
		_clip_name = ""
		if done != "land":
			clip_done.emit()
	_show()
	_glow.modulate.a = 0.85 + 0.15 * sin(_time * 7.0)
	if trail:
		_trail_clock -= delta
		if _trail_clock <= 0.0:
			_trail_clock = 0.03
			_afterimage()
		_step_clock -= delta
		if _step_clock <= 0.0 and lift <= 0.0 and _clip_name == "run":
			_step_clock = 0.08
			ShockRing.burst(get_parent(), global_position, 12.0, 0.25) ## dust at his heels


func _draw() -> void: ## the ground shadow stays on the ground while he is in the air
	var squash: float = clampf(1.0 - lift / 300.0, 0.4, 1.0)
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in 25:
		pts.append(Vector2.from_angle(TAU * i / 24.0) * Vector2(12.0 * squash, 3.4 * squash))
	draw_colored_polygon(pts, Color(0, 0, 0, 0.28 * squash))


func _afterimage() -> void:
	var ghost: Sprite2D = Sprite2D.new()
	ghost.texture = _glow.texture
	ghost.hframes = _glow.hframes
	ghost.vframes = _glow.vframes
	ghost.frame = _sprite.frame
	ghost.offset = _sprite.offset
	ghost.global_position = global_position
	ghost.z_index = 4
	ghost.material = Unlit.material()
	ghost.modulate = Color(0.75, 0.6, 1.0, 0.55)
	get_parent().add_child(ghost)
	var tween: Tween = ghost.create_tween().set_ignore_time_scale(true)
	tween.tween_property(ghost, "modulate:a", 0.0, 0.22)
	tween.tween_callback(ghost.queue_free)
