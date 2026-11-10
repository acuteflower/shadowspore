class_name FallenLog
extends Node2D
## Baked 3/4-view trunk; no collecting. Ground footprint and Y anchor follow its
## rendered facing. Perches expose the real top of the log to existing birds.
## Sliced into y-sorted horizontal bands so actors sort cleanly in front of and
## behind diagonal/slanted trunks along their entire length.
const TEXTURE: Texture2D = preload("res://assets/props/fallen_logs.png")
const GLOW: Texture2D = preload("res://assets/props/fallen_logs_glow.png")
const BONE_TEXTURE: Texture2D = preload("res://assets/props/fallen_logs_bone.png") ## frames 24-47: the same trunks as dead Bleichbaum wood (the Hexenwald)
const BONE_GLOW: Texture2D = preload("res://assets/props/fallen_logs_bone_glow.png")
const FRAMES: int = 24 ## per sheet
const FRAME_W: int = 112
const FRAME_H: int = 80
const BAND_H: int = 1

static var _bands_cache: Dictionary = {}

const HARVEST_LAYER: int = 1 << 4 ## physics layer 5, the one weapons hit (data/harvest.json "fallen_log": the axe chops it)

var frame: int = 0
var _spec: Dictionary
var perch_point: Vector2
var perch_height: float = 9.0
var _shadow: Node2D
var key: String = "" ## "l:x,y" of the log: its harvest state is kept under this key (WorldLevel)
var level: WorldLevel ## who keeps the state; null in the workbenches
var gone: bool = false ## chopped up: hidden for good, perches are given up
var _body: StaticBody2D
var _harvest: HarvestHurtbox
var _fade: Tween
var _shake: Tween

func setup(at: Vector2, index: int, world: WorldLevel = null) -> void:
	position = at
	frame = index
	level = world
	key = "l:%d,%d" % [roundi(at.x), roundi(at.y)]
	_spec = (DataRegistry.table("fallen_logs").frames as Array)[index % FRAMES]

static func _get_or_create_bands(idx: int) -> Array[Dictionary]:
	if _bands_cache.has(idx):
		return _bands_cache[idx] as Array[Dictionary]
	var result: Array[Dictionary] = []
	var col: int = idx % 8
	var row: int = (idx % FRAMES) / 8
	var img: Image = (BONE_TEXTURE if idx >= FRAMES else TEXTURE).get_image()
	var glow_img: Image = (BONE_GLOW if idx >= FRAMES else GLOW).get_image()
	for y: int in range(0, FRAME_H, BAND_H):
		var h: int = mini(BAND_H, FRAME_H - y)
		var has_pixels: bool = false
		var has_glow: bool = false
		for py: int in range(y, y + h):
			for px: int in FRAME_W:
				var c: Color = img.get_pixel(col * FRAME_W + px, row * FRAME_H + py)
				if c.a > 0.01:
					has_pixels = true
					var gc: Color = glow_img.get_pixel(col * FRAME_W + px, row * FRAME_H + py)
					if gc.a > 0.01:
						has_glow = true
						break
			if has_pixels and has_glow:
				break
		if not has_pixels:
			continue
		result.append({"y": y, "h": h, "glow": has_glow})
	_bands_cache[idx] = result
	return result

func _ready() -> void:
	add_to_group("fallen_logs")
	if _spec.is_empty():
		return
	y_sort_enabled = true
	var anchor: Array = _spec.anchor
	var anchor_vec: Vector2 = Vector2(float(anchor[0]), float(anchor[1]))
	var a: Vector2 = Vector2(float(_spec.a[0]), float(_spec.a[1]))
	var b: Vector2 = Vector2(float(_spec.b[0]), float(_spec.b[1]))

	_shadow = Node2D.new()
	_shadow.name = "Shadow"
	_shadow.z_index = -1
	_shadow.draw.connect(_draw_shadow)
	add_child(_shadow)
	_shadow.queue_redraw()

	var col: int = frame % 8
	var row: int = (frame % FRAMES) / 8
	var bones: bool = frame >= FRAMES
	var bands: Array[Dictionary] = _get_or_create_bands(frame)
	for band_info: Dictionary in bands:
		var y: int = int(band_info.y)
		var h: int = int(band_info.h)
		var band_bottom: float = float(y + h) - anchor_vec.y
		var band: Node2D = Node2D.new()
		band.name = "Band_%d" % y
		band.position = Vector2(0.0, band_bottom)

		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture = BONE_TEXTURE if bones else TEXTURE
		sprite.region_enabled = true
		sprite.region_rect = Rect2(col * FRAME_W, row * FRAME_H + y, FRAME_W, h)
		sprite.centered = false
		sprite.position = Vector2(-anchor_vec.x, -float(h))
		band.add_child(sprite)

		if bool(band_info.glow):
			var emission: Sprite2D = Sprite2D.new()
			emission.texture = BONE_GLOW if bones else GLOW
			emission.region_enabled = true
			emission.region_rect = sprite.region_rect
			emission.centered = false
			emission.material = Unlit.material()
			emission.modulate.a = 0.45
			emission.position = Vector2.ZERO
			sprite.add_child(emission)

		add_child(band)

	var body: StaticBody2D = StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape: CollisionShape2D = CollisionShape2D.new()
	var capsule: CapsuleShape2D = CapsuleShape2D.new()
	capsule.radius = float(_spec.radius)
	capsule.height = a.distance_to(b) + capsule.radius * 2.0
	shape.shape = capsule
	shape.position = (a + b) * 0.5
	shape.rotation = (b - a).angle() + PI * 0.5
	body.add_child(shape)
	add_child(body)
	_body = body

	# the axe finds the trunk through a slightly wider capsule along the same line (physics layer 5)
	_harvest = HarvestHurtbox.new()
	_harvest.name = "Harvest"
	_harvest.harvest_target = self
	_harvest.collision_layer = HARVEST_LAYER
	_harvest.collision_mask = 0
	var reach: CollisionShape2D = CollisionShape2D.new()
	var grip: CapsuleShape2D = CapsuleShape2D.new()
	grip.radius = capsule.radius + 3.0
	grip.height = a.distance_to(b) + grip.radius * 2.0
	reach.shape = grip
	reach.position = shape.position
	reach.rotation = shape.rotation
	_harvest.add_child(reach)
	add_child(_harvest)

	perch_point = global_position + (a + b) * 0.5

func _draw_shadow() -> void:
	if _spec.is_empty() or _shadow == null:
		return
	var a: Vector2 = Vector2(float(_spec.a[0]), float(_spec.a[1]))
	var b: Vector2 = Vector2(float(_spec.b[0]), float(_spec.b[1]))
	_shadow.draw_line(a, b, Color(0.025, 0.018, 0.04, 0.25), 10.0)

## Harvest rules (data/harvest.json "fallen_log", the Hexenwald's bleached trunks "fallen_bone_log"): the axe chops it up, then it is gone
## for good (logs do not grow back).
func spec() -> Dictionary:
	return DataRegistry.table("harvest").get("fallen_bone_log" if frame >= FRAMES else "fallen_log", {}) as Dictionary


func is_depleted() -> bool:
	return gone


## Host: the hurtbox was hit (WorldLevel decides what that means).
func harvest_hit(source: int) -> void:
	if level != null:
		level.harvest_field_hit(self, source)


## Everyone: the host's state for this log. Chopped logs sink out of sight and stop being perches; `fx` "hit" /
## "rustle" only shake the trunk.
func apply_harvest(state: Dictionary, fx: String, _at: Vector2) -> void:
	gone = bool(state.get("f", 0))
	if gone:
		if _body != null: _body.collision_layer = 0
		if _harvest != null: _harvest.collision_layer = 0
		if _fade != null: _fade.kill()
		_fade = create_tween()
		_fade.tween_property(self, "modulate:a", 0.0, 0.8)
		_fade.tween_callback(func() -> void: visible = false)
		return
	if fx == "hit" or fx == "rustle":
		_jiggle(1.0 if fx == "hit" else 0.35)


func _jiggle(strength: float) -> void:
	if _shake != null:
		_shake.kill()
	rotation = 0.0
	_shake = create_tween()
	_shake.tween_property(self, "rotation", 0.035 * strength, 0.05)
	_shake.tween_property(self, "rotation", -0.02 * strength, 0.09)
	_shake.tween_property(self, "rotation", 0.0, 0.2).set_trans(Tween.TRANS_SINE)

func _draw() -> void:
	pass
