class_name CaravanView
extends Node2D
## The caravan's wagon and its ox (docs/haendler_konzept.md 2.2, 2.3, 8.2, 8.3). Art from `py -3 tools/art_caravan.py` (assets/town/caravan/, data/caravan_art.json):
## the wagon rolls in eight facings (the wheels turn with the distance driven), parked it unfolds into the stall (counter down, awning out: frames of
## `wagon_stand.png` follow the phase), shut and lit at night; the ox walks ahead of it on the route, grazes and swishes while the stall is open and lies
## down at night. The goods of the visit lie on the counter as their icons (a sold-out row leaves a gap). Everything follows `CaravanManager.phase` and the
## clock, so every peer shows the same. Solid only while it stands and nobody is inside its footprint. Without the art a plain placeholder is drawn.

const ART: String = "res://assets/town/caravan/"
const SINP: float = 0.4384 ## sin(26 deg): how the renderer squashes ground depth (art_hero3d.PITCH)
const CANVAS: Color = Color("3d5a8a")
const WOOD: Color = Color("5e3f52")

var caravan: CaravanManager
var _body: StaticBody2D
var _shape: CollisionShape2D
var _dir: Vector2 = Vector2.RIGHT
var _time: float = 0.0
var _meta: Dictionary = {}
var _roll: Texture2D
var _stand: Texture2D
var _roll_glow: Texture2D
var _stand_glow: Texture2D
var _wagon: Sprite2D
var _wagon_glow: Sprite2D
var _ox: Node2D
var _ox_sprite: Sprite2D
var _ox_glow: Sprite2D
var _goods: Node2D
var _lantern: NightLight
var _ox_lantern: NightLight
var _driven: float = 0.0
var _last_pos: Vector2 = Vector2.INF
var _icons: Array[Texture2D] = [] ## kept referenced (`draw_texture` needs it)
const AUDIO: String = "res://assets/audio/caravan/"
var _wheels: AudioStreamPlayer2D
var _bell_clock: float = 0.0
var _ox_clock: float = 6.0
var _last_fold: float = 0.0
var _last_state: String = "away"
var _perches: Array[RoofPerch] = []


func setup(owner_caravan: CaravanManager) -> void:
	caravan = owner_caravan
	visible = false
	_meta = DataRegistry.table("caravan_art")
	_body = StaticBody2D.new()
	_body.collision_layer = 1
	_body.collision_mask = 0
	_shape = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(78.0, 18.0)
	_shape.shape = rect
	_shape.position = Vector2(0.0, -8.0)
	_shape.disabled = true
	_body.add_child(_shape)
	add_child(_body)
	if ResourceLoader.exists(ART + "wagon_roll.png") and not _meta.is_empty():
		_roll = load(ART + "wagon_roll.png") as Texture2D
		_stand = load(ART + "wagon_stand.png") as Texture2D
		_roll_glow = load(ART + "wagon_roll_glow.png") as Texture2D
		_stand_glow = load(ART + "wagon_stand_glow.png") as Texture2D
		_wagon = _sprite(self, _roll, (_meta.wagon as Dictionary))
		_wagon_glow = _sprite(_wagon, _roll_glow, (_meta.wagon as Dictionary))
		_wagon_glow.position = Vector2.ZERO
		_wagon_glow.offset = Vector2.ZERO
		_wagon_glow.centered = false
		_wagon_glow.material = Unlit.material()
		_ox = Node2D.new()
		_ox.name = "Ox"
		_ox.visible = false
		caravan.add_child.call_deferred(_ox)
		_ox_sprite = _sprite(_ox, load(ART + "ox.png") as Texture2D, (_meta.ox as Dictionary))
		_ox_sprite.hframes = int((_meta.ox as Dictionary).frames)
		_ox_sprite.vframes = 8
		_ox_glow = _sprite(_ox_sprite, load(ART + "ox_glow.png") as Texture2D, (_meta.ox as Dictionary))
		_ox_glow.hframes = _ox_sprite.hframes
		_ox_glow.vframes = 8
		_ox_glow.position = Vector2.ZERO
		_ox_glow.material = Unlit.material()
		_ox.draw.connect(_draw_ox_shadow)
		_ox_lantern = _light(_ox, Vector2(0.0, -24.0), 26, 0.5)
	_goods = Node2D.new()
	_goods.name = "Goods"
	_goods.draw.connect(_draw_goods)
	add_child(_goods)
	_lantern = _light(self, Vector2.ZERO, 40, 0.75)
	_wheels = AudioStreamPlayer2D.new()
	_wheels.stream = load(AUDIO + "wheels.wav") as AudioStream if ResourceLoader.exists(AUDIO + "wheels.wav") else null
	_wheels.volume_db = -14.0
	_wheels.max_distance = 420.0
	_wheels.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	_wheels.finished.connect(func() -> void:
		if visible and _moving():
			_wheels.play())
	add_child(_wheels)
	for spot: Vector2 in [Vector2(-18.0, 1.0), Vector2(14.0, 1.0)]: ## crows may land on the canvas while the wagon stands (`RoofPerch`, `TownCritters`)
		var perch: RoofPerch = RoofPerch.new()
		perch.host = self
		perch.perch_height = 46.0
		perch.position = spot
		add_child(perch)
		_perches.append(perch)


## `RoofPerch` asks its host: birds land on the canvas only while the wagon stands.
func is_done() -> bool:
	return caravan != null and CaravanRules.parked(caravan.state())


## A positional one-off sound of the caravan.
func _sound(name_id: String, db: float, at: Vector2 = Vector2.ZERO, reach: float = 300.0) -> void:
	var path: String = AUDIO + name_id + ".wav"
	if not ResourceLoader.exists(path) or not is_inside_tree():
		return
	var p: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	p.stream = load(path) as AudioStream
	p.volume_db = db
	p.max_distance = reach
	p.pitch_scale = randf_range(0.95, 1.05)
	p.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	p.position = at
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## The sounds that follow the phase: the wheels while it drives, the bell as it comes in and leaves, the ox now and then, the stall's flap, cloth and
## chain while it unfolds or folds up.
func _sounds(s: String, delta: float) -> void:
	var moving: bool = _moving()
	if _wheels.stream != null:
		if moving and not _wheels.playing:
			_wheels.play()
		elif not moving and _wheels.playing:
			_wheels.stop()
	var k: float = float(caravan.phase.get("k", 0.0))
	if (s == "coming" and k > 0.7) or (s == "going" and k < 0.25) or (s == "setup" and _last_state == "coming"):
		_bell_clock -= delta
		if _bell_clock <= 0.0:
			_bell_clock = randf_range(2.2, 3.4)
			_sound("bell_a" if randf() < 0.5 else "bell_b", -10.0, Vector2(10.0, -30.0), 900.0)
	if CaravanRules.parked(s) and s not in ["night"]:
		_ox_clock -= delta
		if _ox_clock <= 0.0:
			_ox_clock = randf_range(9.0, 22.0)
			_sound("ox_snort" if randf() < 0.75 else "ox_low", -12.0, _ox.global_position - global_position if _ox != null else Vector2.ZERO, 260.0)
	elif moving:
		_ox_clock -= delta
		if _ox_clock <= 0.0:
			_ox_clock = randf_range(0.55, 0.8)
			_sound("ox_bells", -20.0, _ox.global_position - global_position if _ox != null else Vector2.ZERO, 260.0)
	var f: float = fold()
	if s in ["setup", "teardown"]:
		if (_last_fold < 0.15) != (f < 0.15):
			_sound("cloth", -12.0)
		if (_last_fold < 0.55) != (f < 0.55):
			_sound("flap", -9.0)
		if (_last_fold < 0.9) != (f < 0.9):
			_sound("chain", -14.0)
	_last_fold = f
	_last_state = s


func _sprite(parent: Node, tex: Texture2D, spec: Dictionary) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = tex
	sprite.centered = false
	var feet: Array = spec.get("feet", [0, 0]) as Array
	sprite.offset = Vector2(-float(feet[0]), -float(feet[1]))
	parent.add_child(sprite)
	return sprite


func _light(parent: Node, at: Vector2, radius: int, energy: float) -> NightLight:
	var light: NightLight = NightLight.new()
	light.radius = radius
	light.base_energy = energy
	light.glow_color = Color("ffc870")
	light.pulse = 0.2
	light.position = at
	parent.add_child(light)
	return light


## Called by the caravan every frame.
func follow() -> void:
	var delta: float = get_process_delta_time()
	_time += delta
	var s: String = caravan.state()
	visible = CaravanRules.present(s)
	if _ox != null:
		_ox.visible = visible
	if not visible:
		_shape.set_deferred("disabled", true)
		_last_pos = Vector2.INF
		if _wheels.playing:
			_wheels.stop()
		_last_state = s
		return
	var pose: Dictionary = caravan.wagon_pose()
	position = pose.pos as Vector2
	_dir = pose.dir as Vector2
	if _last_pos.is_finite():
		_driven += position.distance_to(_last_pos)
	_last_pos = position
	var solid: bool = CaravanRules.parked(s) and not _someone_inside()
	if _shape.disabled == solid:
		_shape.set_deferred("disabled", not solid)
	_show(s)
	_sounds(s, delta)
	_goods.queue_redraw()
	queue_redraw()


func _someone_inside() -> bool:
	var area: Rect2 = Rect2(global_position + Vector2(-42.0, -22.0), Vector2(84.0, 26.0))
	for node: Node in get_tree().get_nodes_in_group("players"):
		if area.has_point((node as Node2D).global_position):
			return true
	return false


## How far the counter is folded down (0 shut .. 1 open).
func fold() -> float:
	var s: String = caravan.state()
	var k: float = float(caravan.phase.get("k", 0.0))
	match s:
		"setup":
			return smoothstep(0.25, 0.75, k)
		"open":
			return 1.0
		"teardown":
			return 1.0 - smoothstep(0.1, 0.6, k)
	return 0.0


func _moving() -> bool:
	return caravan.state() in ["coming", "going"]


## The parked wagon's sheet row: 0 facing east, 1 facing west (the counter side always faces the viewer).
func _stand_row() -> int:
	return 0 if _dir.x >= 0.0 else 1


func _show(s: String) -> void:
	var lit: bool = s in ["open", "night", "storm", "setup", "teardown"]
	_lantern.visible = lit
	_lantern.base_energy = 0.3 if caravan.town.fear_on else 0.75 ## the dark is near: Jorun turns the wick down
	if _ox_lantern != null:
		_ox_lantern.visible = true
	if _wagon == null:
		return
	var wagon: Dictionary = _meta.wagon as Dictionary
	if _moving():
		_wagon.texture = _roll
		_wagon.hframes = int(wagon.roll_frames)
		_wagon.vframes = 8
		_wagon.frame = Adventurer.sector_of(_dir) * _wagon.hframes + int(_driven / 3.0) % _wagon.hframes
		_wagon_glow.texture = _roll_glow
	else:
		_wagon.texture = _stand
		_wagon.hframes = int(wagon.stand_frames)
		_wagon.vframes = 2
		var col: int = int(wagon.night_frame) if s in ["night", "storm"] else roundi(fold() * float(int(wagon.open_frame)))
		_wagon.frame = _stand_row() * _wagon.hframes + col
		_wagon_glow.texture = _stand_glow
	_wagon_glow.hframes = _wagon.hframes
	_wagon_glow.vframes = _wagon.vframes
	_wagon_glow.frame = _wagon.frame
	_wagon_glow.offset = _wagon.offset
	_wagon_glow.modulate.a = clampf(0.35 + TimeManager.night_amount(), 0.0, 1.0)
	var lantern: Array = wagon.get("lantern", [0, 0]) as Array
	_lantern.position = Vector2(float(lantern[0]) * (1.0 if _stand_row() == 0 or _moving() else -1.0), float(lantern[1]))
	_place_ox(s)


func _place_ox(s: String) -> void:
	if _ox == null or not _ox.is_inside_tree():
		return
	var ahead: float = float((_meta.wagon as Dictionary).get("ox_ahead", 44.0))
	var d: Vector2 = _dir.normalized() if _dir.length() > 0.01 else Vector2.RIGHT
	_ox.global_position = global_position + Vector2(d.x, d.y * SINP) * ahead
	var spec: Dictionary = _meta.ox as Dictionary
	var clips: Dictionary = spec.clips as Dictionary
	var clip: String = "idle"
	if _moving():
		clip = "walk"
	elif s in ["night", "storm"] and not caravan.town.fear_on: ## the dark near the town: the ox gets up and stands uneasy
		clip = "lie"
	elif fposmod(_time, 23.0) > 13.0:
		clip = "graze"
	var c: Dictionary = clips.get(clip, clips.idle) as Dictionary
	var n: int = maxi(int(c.count), 1)
	var f: int = int(_time * float(c.fps)) % n if clip != "walk" else int(_driven / 4.0) % n
	_ox_sprite.frame = Adventurer.sector_of(d) * int(spec.frames) + int(c.start) + f
	_ox_glow.frame = _ox_sprite.frame
	_ox_glow.visible = clip != "lie"
	_ox.queue_redraw()


func _draw() -> void:
	var side: bool = absf(_dir.x) >= absf(_dir.y) * 0.8
	_ellipse(Vector2(0, 0), Vector2(44, 8) if side else Vector2(22, 13), Color(0, 0, 0, 0.26))
	if _wagon == null:
		_placeholder()


func _draw_ox_shadow() -> void:
	var side: bool = absf(_dir.x) >= absf(_dir.y) * 0.8
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in 20:
		pts.append(Vector2.from_angle(TAU * float(i) / 20.0) * (Vector2(18, 4) if side else Vector2(9, 6)))
	_ox.draw_colored_polygon(pts, Color(0, 0, 0, 0.24))


## The goods of the visit on the counter: one icon per WAREN row that still has pieces (data/caravan_art.json `display`, from the art script).
func _draw_goods() -> void:
	_icons.clear()
	if _moving() or fold() < 0.95 or caravan.state() != "open":
		return
	var spots: Array = []
	if _wagon != null:
		spots = ((_meta.wagon as Dictionary).get("display", []) as Array)[_stand_row()] as Array
	else:
		for k: int in 8:
			spots.append([-24 + (k % 5) * 10, -14 + (k / 5) * 10])
	var slot: int = 0
	for row: Dictionary in caravan._list("buy"):
		if slot >= spots.size():
			break
		var at: Array = spots[slot] as Array
		slot += 1
		if caravan.left(String(row.item)) <= 0:
			continue
		var tex: Texture2D = Items.icon({"id": String(row.item)})
		if tex == null:
			continue
		_icons.append(tex)
		_goods.draw_texture_rect(tex, Rect2(Vector2(float(at[0]) - 4.0, float(at[1]) - 7.0), Vector2(8, 8)), false)


## Without the art: a plain covered wagon.
func _placeholder() -> void:
	draw_rect(Rect2(-30, -16, 60, 8), WOOD)
	var arch: PackedVector2Array = PackedVector2Array()
	for i: int in 13:
		var t: float = float(i) / 12.0
		arch.append(Vector2(lerpf(-28.0, 28.0, t), -16.0 - sin(t * PI) * 20.0 - 6.0))
	arch.append(Vector2(28, -16))
	arch.append(Vector2(-28, -16))
	draw_colored_polygon(arch, CANVAS)
	for x: float in [-20.0, 20.0]:
		draw_circle(Vector2(x, -6.0), 6.0, Color("3b2738"))


func _ellipse(at: Vector2, radius: Vector2, color: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in 20:
		pts.append(at + Vector2.from_angle(TAU * float(i) / 20.0) * radius)
	draw_colored_polygon(pts, color)
