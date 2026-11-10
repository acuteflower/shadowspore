class_name TownStructure
extends Interactable
## The picture of one placed piece (state: `TownManager.structures[id]`). It stands with its feet on `position`; a site (progress < 1000) shows only the
## part of the piece that has risen so far, inside a rope frame of corner posts, and is hammered on while someone stands near; a finished piece glows
## and lights the night (art: tools/art_town.py -> assets/town/<texture>.png, `_glow` unlit, `_pad` the trodden ground under big pieces).
## The stockpile also answers E.

const DIR: String = "res://assets/town/"
const HAMMERS: Array[String] = ["res://assets/audio/hut/hammer_a.wav", "res://assets/audio/hut/hammer_b.wav", "res://assets/audio/hut/hammer_c.wav"]
const POST: Color = Color("6b5a74")
const ROPE: Color = Color("a89477")
const SITE: Color = Color("78f4e6")
const GLOW_BY_DAY: float = 0.3
const BUILD: Shader = preload("res://assets/shaders/build_pixels.gdshader")
const BUILD_GLOW: Shader = preload("res://assets/shaders/build_pixels_glow.gdshader")
const SWAY_UNLIT: Shader = preload("res://assets/shaders/sway_unlit.gdshader")

var manager: TownManager
var id: int = -1
var piece: String = ""
var progress: int = 0
var _spec: Dictionary = {}
var _frame: Vector2 = Vector2.ZERO
var _feet: float = 0.0
var _flipped: bool = false
var _sprite: Sprite2D
var _glow: Sprite2D
var _pad: Sprite2D
var _light: NightLight
var _light_base: float = 0.0
var _flicker: float = 0.0
var _body: StaticBody2D
var _hammer_clock: float = 0.0
var _last_gain_msec: int = -10000
var _time: float = 0.0
var _flash: float = 0.0
var _smoke: CPUParticles2D
var _active: float = 1.0 ## 0..1: is somebody working here (the forge glows and smokes then, otherwise it only keeps embers)
var _active_check: float = 0.0
var _shown: float = 1.0 ## the build as it is drawn, 0..1 (eased towards the real progress)
var _layers: Array[Dictionary] = [] ## pictures that are put together pixel by pixel: {sprite, lit, glow, ghost}
var _glows: Array[Sprite2D] = [] ## every unlit sheet (the base's and the parts'), dim by day, bright at night
var _anims: Array[Dictionary] = [] ## {sprite, frames, fps} the sheets that play
var _parts: Array[Dictionary] = [] ## {sprite, from}: separate pictures hung on the piece (the lamp post's lantern)
var _motes: CPUParticles2D
var _spill: Sprite2D ## the light a lamp or the forge throws on the floor and round itself: an additive picture (data `spill`), breathing with the light
var _spill_forge: bool = false
var _sparks: CPUParticles2D ## tiny sparks over the forge's mouth while somebody works (data `sparks`)
var _wear: Array[Dictionary] = [] ## {sprite, days}: what the piece collects with the days it stands (data `wear`)
var _wear_check: float = 0.0
var _wear_loaded: bool = false
var _built_look: bool = false ## the build shaders are gone, the piece is whole
var _shutters: Array[Dictionary] = [] ## {sprite, frames, t 0 shut .. 1 propped open}: the market-stall flaps (data `shutters`)
var _shutter_forced: float = 0.0 ## seconds the flap stays up although it is night (somebody asked for the stock)
var _shutter_check: float = 0.0
var _shutter_near: bool = false
var _lamp_k: float = 1.0 ## a lamp post: 1 burning, 0.2 only embers (empty), 0 cold; every other piece 1


func setup(owner_manager: TownManager, structure_id: int) -> void:
	manager = owner_manager
	id = structure_id
	var data: Dictionary = manager.structures[id] as Dictionary
	piece = String(data.p)
	_spec = TownRules.piece(piece)
	position = Vector2(float(data.x), float(data.y))
	_flipped = int(data.get("f", 0)) == 1
	progress = int(data.g)
	var texture_name: String = String(_spec.get("texture", piece))
	var frame: Array = _spec.get("frame", [16, 16]) as Array
	_frame = Vector2(float(frame[0]), float(frame[1]))
	_feet = float(_spec.get("feet", frame[1]))
	var foot: Array = _spec.get("foot", [16, 16]) as Array
	if bool(_spec.get("pad", false)) and ResourceLoader.exists(DIR + texture_name + "_pad.png"):
		_pad = Sprite2D.new()
		_pad.texture = load(DIR + texture_name + "_pad.png") as Texture2D
		_pad.position = Vector2(0.0, -float(foot[1]) / 2.0)
		_pad.z_index = -9
		_pad.show_behind_parent = false
		add_child(_pad)
	_sprite = Sprite2D.new()
	_sprite.texture = _load_picture(texture_name)
	_sprite.centered = false
	_sprite.flip_h = _flipped
	if bool(_spec.get("walk", false)):
		_sprite.z_index = -9
	add_child(_sprite)
	_sprite.position = Vector2(-_frame.x / 2.0, -_feet)
	if bool(_spec.get("glow", false)) and ResourceLoader.exists(DIR + texture_name + "_glow.png"):
		_glow = _make_glow(_sprite, DIR + texture_name + "_glow.png", _spec.get("anim", {}) as Dictionary)
	for raw: Variant in _spec.get("parts", []) as Array:
		_make_part(raw as Dictionary)
	if not bool(_spec.get("walk", false)):
		_body = StaticBody2D.new()
		var shape: CollisionShape2D = CollisionShape2D.new()
		var box: RectangleShape2D = RectangleShape2D.new()
		box.size = Vector2(float(foot[0]) - 2.0, float(foot[1]) - 2.0)
		shape.shape = box
		shape.position = Vector2(0.0, -float(foot[1]) / 2.0)
		_body.add_child(shape)
		add_child(_body)
	if _spec.has("light"):
		var spec: Dictionary = _spec.light as Dictionary
		_light = NightLight.new()
		var at: Array = spec.get("at", [0, -20]) as Array
		_light.position = Vector2(float(at[0]), float(at[1]))
		_light.radius = int(spec.radius)
		_light.squash = 0.8
		_light.base_energy = float(spec.energy)
		_light.glow_color = Color(String(spec.color))
		_light.pulse = 0.2
		_light_base = float(spec.energy)
		_flicker = float(spec.get("flicker", 0.0))
		add_child(_light)
	if _spec.has("smoke"):
		_make_smoke()
	if _spec.has("motes"):
		_make_motes()
	if _spec.has("spill"):
		_make_spill()
	if _spec.has("sparks"):
		_make_sparks()
	_make_wear()
	_make_shutters()
	_make_perches()
	if bool(_spec.get("fireflies", false)):
		_sprite.add_to_group("flora_glow") ## the night's fireflies gather here
	var window: Array = _spec.get("window", [0.0, 1.0]) as Array
	_shown = float(progress) / float(TownManager.PROGRESS_FULL)
	_add_layer(_sprite, float(window[0]), float(window[1]), false)
	for part: Dictionary in _parts:
		_add_layer(part.sprite as Sprite2D, float(part.from), float(part.to), part.sway != null)
	if String(_spec.get("role", "")) == "board":
		_make_board_notes()
	add_to_group("night_lights")
	_update_lamp_k()
	_apply_progress()
	set_night(TimeManager.night_amount())


## The quest board shows its notices on the panel (`BoardNotes`: the paper, and the story notices' seals unlit on top).
func _make_board_notes() -> void:
	if manager.board == null:
		return
	for lit: bool in [false, true]:
		var notes: BoardNotes = BoardNotes.new()
		notes.name = "SealNotes" if lit else "Notes"
		notes.board = manager.board
		notes.structure = self
		notes.unlit = lit
		add_child(notes)


func is_flipped() -> bool:
	return _flipped


## The picture of the piece (a field paints its own ground, `FarmField`).
func _load_picture(texture_name: String) -> Texture2D:
	return load(DIR + texture_name + ".png") as Texture2D


## An unlit sheet over `parent` (the piece's emissive pixels): `anim` {frames, fps} makes it a loop of frames side by side; 
func _make_glow(parent: Sprite2D, path: String, anim: Dictionary) -> Sprite2D:
	var glow: Sprite2D = Sprite2D.new()
	glow.texture = load(path) as Texture2D
	glow.centered = false
	glow.flip_h = _flipped
	glow.hframes = int(anim.get("frames", 1))
	glow.material = Unlit.material()
	parent.add_child(glow)
	_glows.append(glow)
	if glow.hframes > 1:
		_anims.append({"sprite": glow, "frames": glow.hframes, "fps": float(anim.get("fps", 6.0))})
	return glow


## A separate picture hung on the piece (data `parts`: texture, frame, `at` = its top-left in the piece's frame, `window` = which part of the build makes it, optional `sway`
## {pivot row, amount, flutter} and an unlit `glow` sheet {frames, fps}); `fireflies` makes the night's fireflies gather there.
func _make_part(spec: Dictionary) -> void:
	var frame: Array = spec.get("frame", [16, 16]) as Array
	var at: Array = spec.get("at", [0, 0]) as Array
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = load(DIR + String(spec.texture) + ".png") as Texture2D
	sprite.centered = false
	sprite.flip_h = _flipped
	sprite.position = Vector2(float(at[0]) if not _flipped else _frame.x - float(at[0]) - float(frame[0]), float(at[1]))
	_sprite.add_child(sprite)
	var sway: Variant = spec.get("sway")
	var window: Array = spec.get("window", [0.0, 1.0]) as Array
	_parts.append({"sprite": sprite, "from": float(window[0]), "to": float(window[1]), "sway": sway})
	if spec.has("glow"):
		var glow: Sprite2D = _make_glow(sprite, DIR + String(spec.texture) + "_glow.png", spec.glow as Dictionary)
		if sway != null:
			var mat: ShaderMaterial = ShaderMaterial.new()
			mat.shader = SWAY_UNLIT
			mat.set_shader_parameter("pivot_row", float((sway as Dictionary).get("pivot", 0.0)))
			mat.set_shader_parameter("amount", float((sway as Dictionary).get("amount", 3.0)))
			mat.set_shader_parameter("flutter", float((sway as Dictionary).get("flutter", 0.4)))
			glow.material = mat
			(_parts[_parts.size() - 1] as Dictionary)["glow_mat"] = mat
	if bool(spec.get("fireflies", false)):
		sprite.add_to_group("flora_glow")


## The build look of one picture: its pixels fall into place (`build_pixels.gdshader`), the rest shows as a dotted blueprint.
func _add_layer(sprite: Sprite2D, from: float, to: float, sway: bool) -> void:
	var lit: ShaderMaterial = ShaderMaterial.new()
	lit.shader = BUILD
	var glow: ShaderMaterial = ShaderMaterial.new()
	glow.shader = BUILD_GLOW
	var part_spec: Dictionary = {}
	for part: Dictionary in _parts:
		if part.sprite == sprite and part.sway != null:
			part_spec = part.sway as Dictionary
	for material: ShaderMaterial in [lit, glow]:
		material.set_shader_parameter("seed", float(id * 37 + _layers.size() * 11))
		material.set_shader_parameter("window_from", from)
		material.set_shader_parameter("window_to", to)
		if sway:
			material.set_shader_parameter("sway_pivot", float(part_spec.get("pivot", 0.0)))
			material.set_shader_parameter("sway_amount", float(part_spec.get("amount", 3.0)))
			material.set_shader_parameter("sway_flutter", float(part_spec.get("flutter", 0.4)))
	var ghost: Sprite2D = Sprite2D.new()
	ghost.texture = sprite.texture
	ghost.centered = false
	ghost.flip_h = sprite.flip_h
	ghost.material = glow
	ghost.z_index = 1
	sprite.add_child(ghost)
	sprite.material = lit
	_layers.append({"sprite": sprite, "lit": lit, "glow": glow, "ghost": ghost, "sway": sway})


## Tiny motes of light rising from the lantern at night (data `motes` {at, color}); only while the piece is whole and it is dark.
func _make_motes() -> void:
	var spec: Dictionary = _spec.motes as Dictionary
	var at: Array = spec.get("at", [0, -40]) as Array
	_motes = CPUParticles2D.new()
	_motes.position = Vector2(float(at[0]) * (-1.0 if _flipped else 1.0), float(at[1]))
	_motes.z_index = 4
	_motes.material = Unlit.material()
	_motes.amount = 6
	_motes.lifetime = 3.2
	_motes.preprocess = 3.2
	_motes.direction = Vector2(0.2, -1.0)
	_motes.spread = 25.0
	_motes.gravity = Vector2.ZERO
	_motes.initial_velocity_min = 3.0
	_motes.initial_velocity_max = 7.0
	_motes.scale_amount_min = 0.9
	_motes.scale_amount_max = 1.2
	_motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_motes.emission_sphere_radius = 4.0
	var tone: Color = Color(String(spec.get("color", "78f4e6")))
	var fade: Gradient = Gradient.new()
	fade.colors = PackedColorArray([Color(tone, 0.0), Color(tone, 0.9), Color(tone, 0.0)])
	fade.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	_motes.color_ramp = fade
	_motes.emitting = false
	add_child(_motes)


## A thread of smoke from the chimney like the hut's, leaning with the wind; it only rises while the home's settler is about (see `_resident_about`).
func _make_smoke() -> void:
	_smoke = CPUParticles2D.new()
	var at: Array = (_spec.smoke as Dictionary).get("at", [0, -60]) as Array
	_smoke.position = Vector2(float(at[0]), float(at[1]))
	_smoke.z_index = 4
	_smoke.amount = 22
	_smoke.lifetime = 4.5
	_smoke.preprocess = 4.5
	_smoke.direction = Vector2(0.3, -1.0)
	_smoke.spread = 12.0
	_smoke.initial_velocity_min = 7.0
	_smoke.initial_velocity_max = 13.0
	_smoke.scale_amount_min = 2.0
	_smoke.scale_amount_max = 4.5
	var fade: Gradient = Gradient.new()
	fade.colors = PackedColorArray([Color(0.8, 0.76, 0.86, 0.0), Color(0.8, 0.76, 0.86, 0.7), Color(0.6, 0.57, 0.7, 0.0)])
	fade.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	_smoke.color_ramp = fade
	_smoke.emitting = false
	add_child(_smoke)


## The light picture (data `spill` {texture, forge, base}): a child of the piece's picture, so it lines up, mirrors with it and is built together with it.
func _make_spill() -> void:
	var spec: Dictionary = _spec.spill as Dictionary
	_spill = Sprite2D.new()
	_spill.texture = load(DIR + String(spec.texture) + ".png") as Texture2D
	_spill.centered = false
	_spill.flip_h = _flipped
	_spill_forge = bool(spec.get("forge", false))
	var add: CanvasItemMaterial = CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_spill.material = add
	_spill.visible = false
	_spill.modulate.a = 0.0
	_sprite.add_child(_spill)


## Sparks over the forge's mouth (data `sparks` {at, color}): a few orange specks that fly up in short arcs and die out, only while somebody works there.
func _make_sparks() -> void:
	var spec: Dictionary = _spec.sparks as Dictionary
	var at: Array = spec.get("at", [0, -10]) as Array
	_sparks = CPUParticles2D.new()
	_sparks.position = Vector2(float(at[0]) * (-1.0 if _flipped else 1.0), float(at[1]))
	_sparks.z_index = 4
	_sparks.material = Unlit.material()
	_sparks.amount = 7
	_sparks.lifetime = 1.1
	_sparks.preprocess = 1.1
	_sparks.direction = Vector2(0.0, -1.0)
	_sparks.spread = 38.0
	_sparks.gravity = Vector2(0.0, 18.0)
	_sparks.initial_velocity_min = 10.0
	_sparks.initial_velocity_max = 26.0
	_sparks.scale_amount_min = 0.8
	_sparks.scale_amount_max = 1.1
	var tone: Color = Color(String(spec.get("color", "ffb25a")))
	var fade: Gradient = Gradient.new()
	fade.colors = PackedColorArray([Color(1.0, 0.92, 0.6, 0.0), Color(tone, 1.0), Color(0.9, 0.3, 0.1, 0.0)])
	fade.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	_sparks.color_ramp = fade
	_sparks.emitting = false
	add_child(_sparks)


## The overlays of `wear` {texture, days}: hidden until the piece is whole and has stood for that many days (see `age_days`).
func _make_wear() -> void:
	for raw: Variant in _spec.get("wear", []) as Array:
		var entry: Dictionary = raw as Dictionary
		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture = load(DIR + String(entry.texture) + ".png") as Texture2D
		sprite.centered = false
		sprite.flip_h = _flipped
		sprite.visible = false
		_sprite.add_child(sprite)
		_wear.append({"sprite": sprite, "days": int(entry.days), "track": String(entry.get("track", "age"))})


## The market-stall flaps (data `shutters` [{texture, frame, at, frames}]): a strip of frames from shut (0) to propped up as an awning (last). They are picture only.
func _make_shutters() -> void:
	for raw: Variant in _spec.get("shutters", []) as Array:
		var spec: Dictionary = raw as Dictionary
		var frame: Array = spec.get("frame", [16, 16]) as Array
		var at: Array = spec.get("at", [0, 0]) as Array
		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture = load(DIR + String(spec.texture) + ".png") as Texture2D
		sprite.centered = false
		sprite.hframes = int(spec.get("frames", 5))
		sprite.flip_h = _flipped
		sprite.position = Vector2(float(at[0]) if not _flipped else _frame.x - float(at[0]) - float(frame[0]), float(at[1]))
		sprite.visible = false
		sprite.z_index = 1
		_sprite.add_child(sprite)
		var night: bool = TimeManager.night_amount() > 0.5
		_shutters.append({"sprite": sprite, "frames": sprite.hframes, "t": 0.0 if night else 1.0})


## Day: the flap is up. Night: it is down, unless somebody stands at the front or has asked for the stock (the flap rises for 20 s). Only the picture; nothing is blocked.
func open_shutters() -> void:
	_shutter_forced = 20.0


func _update_shutters(delta: float) -> void:
	if _shutters.is_empty() or not manager.structures.has(id): ## (a piece that is being taken down is no longer in the state)
		return
	var done: bool = progress >= TownManager.PROGRESS_FULL
	_shutter_forced = maxf(_shutter_forced - delta, 0.0)
	_shutter_check -= delta
	if _shutter_check <= 0.0:
		_shutter_check = 0.3
		_shutter_near = false
		var zone: Rect2 = manager.front_of(id).grow(30.0) if manager.front_of(id).has_area() else manager.rect_of(id).grow(34.0)
		for node: Node in get_tree().get_nodes_in_group("players"):
			if zone.has_point((node as Node2D).global_position):
				_shutter_near = true
		for sid: String in manager.settler_ids():
			var settler: Settler = manager.settler_node(sid)
			if settler != null and settler.visible and zone.has_point(settler.global_position):
				_shutter_near = true
	var open: bool = TimeManager.night_amount() <= 0.5 or _shutter_forced > 0.0 or _shutter_near
	for entry: Dictionary in _shutters:
		var sprite: Sprite2D = entry.sprite as Sprite2D
		sprite.visible = done
		var before: float = float(entry.t)
		var now: float = move_toward(before, 1.0 if open else 0.0, delta / 0.6)
		entry.t = now
		sprite.frame = clampi(roundi(now * float(int(entry.frames) - 1)), 0, int(entry.frames) - 1)
		if done and _time > 1.0 and ((before <= 0.0 and now > 0.0) or (before >= 1.0 and now < 1.0)):
			_shutter_sound(now > before)


func _shutter_sound(opening: bool) -> void:
	var path: String = "res://assets/audio/town/shutter_%s.wav" % ("open" if opening else "close")
	if not ResourceLoader.exists(path):
		return
	var player: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	player.stream = load(path) as AudioStream
	player.volume_db = -8.0
	player.max_distance = 340.0
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


## Where birds may land on this piece (data `perches`).
func _make_perches() -> void:
	for raw: Variant in _spec.get("perches", []) as Array:
		var entry: Array = raw as Array
		var perch: RoofPerch = RoofPerch.new()
		perch.host = self
		perch.perch_height = float(entry[2])
		perch.position = Vector2(float(entry[0]) * (-1.0 if _flipped else 1.0), float(entry[1]))
		add_child(perch)


func is_done() -> bool:
	return progress >= TownManager.PROGRESS_FULL


## Days since this piece was finished (0 on the day it was built).
func age_days() -> int:
	var data: Dictionary = manager.structures.get(id, {}) as Dictionary
	return TimeManager.day - int(data.get("b", TimeManager.day))


## Shows the wear that has had time to gather. When a new stage arrives while it is being watched it settles in with a puff of dust; at load it is simply there.
func _update_wear() -> void:
	var done: bool = progress >= TownManager.PROGRESS_FULL
	var age: int = age_days()
	for entry: Dictionary in _wear:
		var sprite: Sprite2D = entry.sprite as Sprite2D
		var wanted: bool = done and age >= int(entry.days)
		match String(entry.get("track", "age")):
			"care":
				wanted = wanted and manager.cared(id)
			"neglect":
				wanted = wanted and not manager.cared(id)
		if wanted and not sprite.visible:
			sprite.visible = true
			if _wear_loaded:
				sprite.modulate.a = 0.0
				create_tween().tween_property(sprite, "modulate:a", 1.0, 1.2)
				_burst(6, Color(0.72, 0.64, 0.58, 0.6), 18.0)
		elif not wanted and sprite.visible:
			sprite.visible = false
	_wear_loaded = true


## Is the settler who lives here up and about (at the bench or the fire, not asleep)?
func _resident_about() -> bool:
	for sid: String in manager.settler_ids():
		if String(manager.settler_spec(sid).get("home", "")) == piece:
			var node: Settler = manager.settler_node(sid)
			if node != null and node.visible:
				return true
	return false


func _apply_progress() -> void:
	var fraction: float = clampf(float(progress) / float(TownManager.PROGRESS_FULL), 0.0, 1.0)
	var done: bool = progress >= TownManager.PROGRESS_FULL
	for glow: Sprite2D in _glows:
		glow.visible = done
	for part: Dictionary in _parts:
		(part.sprite as Sprite2D).visible = fraction > float(part.from)
	if _light != null:
		_light.visible = done and _lamp_k > 0.0
	if _spill != null:
		_spill.visible = done
	set_night(TimeManager.night_amount())
	queue_redraw()


func set_progress(value: int, done: bool = false) -> void:
	if value > progress:
		_last_gain_msec = Time.get_ticks_msec()
	progress = value
	_apply_progress()
	if done:
		_finish_fx()


func set_night(amount: float) -> void:
	amount = MineManager.night_at(self, amount)
	for glow: Sprite2D in _glows:
		glow.modulate.a = lerpf(GLOW_BY_DAY, 1.0, amount) * _lamp_k
	if _motes != null:
		_motes.emitting = amount > 0.4 and progress >= TownManager.PROGRESS_FULL and _lamp_k > 0.5


## A lamp post shows its flame by its state (cold / lit / empty, `TownManager.lamp_state`): the lantern's glow, the vein of light and the pool of light follow `_lamp_k`.
func _update_lamp_k() -> void:
	match manager.lamp_state(id):
		"cold":
			_lamp_k = 0.0
		"empty":
			_lamp_k = 0.2
		_:
			_lamp_k = 1.0


## The state of the lamp changed (host told everyone): `spark` = somebody just lit or fed it.
func refresh_lamp(spark: bool) -> void:
	_update_lamp_k()
	_apply_progress()
	if spark:
		_burst(18, Color(1.0, 0.86, 0.5, 0.9), 58.0)
		if ResourceLoader.exists("res://assets/audio/town/lamp_light.wav"):
			var player: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
			player.stream = load("res://assets/audio/town/lamp_light.wav") as AudioStream
			player.volume_db = -6.0
			player.max_distance = 360.0
			add_child(player)
			player.finished.connect(player.queue_free)
			player.play()


## Taken down (or the town was reloaded): a little dust, then gone.
func dismantle() -> void:
	_burst(14, Color(0.72, 0.64, 0.58, 0.8), 34.0)
	if _body != null:
		_body.queue_free()
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.35)
	tween.tween_callback(queue_free)


func _finish_fx() -> void:
	_burst(22, Color(0.9, 0.82, 0.7, 0.85), 46.0)
	_flash = 1.0
	_sprite.scale = Vector2(1.0, 1.0)
	var tween: Tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_sprite.position.y -= 3.0
	tween.tween_property(_sprite, "position:y", _sprite.position.y + 3.0, 0.3)
	var player: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	player.stream = load("res://assets/audio/hut/beam_drop.wav") as AudioStream
	player.volume_db = -8.0
	player.max_distance = 360.0
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _burst(amount: int, color: Color, speed: float) -> void:
	var puff: CPUParticles2D = CPUParticles2D.new()
	puff.one_shot = true
	puff.emitting = true
	puff.amount = amount
	puff.lifetime = 0.8
	puff.explosiveness = 0.95
	puff.direction = Vector2.UP
	puff.spread = 80.0
	puff.gravity = Vector2(0, 40)
	puff.initial_velocity_min = speed * 0.4
	puff.initial_velocity_max = speed
	puff.scale_amount_min = 1.0
	puff.scale_amount_max = 2.0
	puff.color = color
	var foot: Array = _spec.get("foot", [16, 16]) as Array
	puff.position = Vector2(0.0, -float(foot[1]) * 0.5)
	puff.z_index = 3
	add_child(puff)
	get_tree().create_timer(1.4).timeout.connect(puff.queue_free)


func _process(delta: float) -> void:
	_time += delta
	_update_build(delta)
	for anim: Dictionary in _anims:
		(anim.sprite as Sprite2D).frame = (int(_time * float(anim.fps)) + id) % int(anim.frames)
	if _smoke != null or _spec.has("light"):
		_active_check -= delta
		if _active_check <= 0.0:
			_active_check = 0.5
			_active = 1.0 if progress >= TownManager.PROGRESS_FULL and (_resident_about() or not _spec.has("smoke")) else 0.0
	if _smoke != null:
		var puffing: bool = _active > 0.5 and progress >= TownManager.PROGRESS_FULL
		if puffing and not _smoke.emitting:
			_smoke.restart() ## preprocess: the thread is already there, not growing from nothing
		_smoke.emitting = puffing
		_smoke.gravity = Vector2(WorldWind.sample(global_position).x * 6.0 + 2.0, -1.5)
	_update_shutters(delta)
	_wear_check -= delta
	if _wear_check <= 0.0:
		_wear_check = 1.0
		_update_wear()
	if _spill != null and _spill.visible:
		var night: float = TimeManager.night_amount()
		var level: float = lerpf(0.4, 1.0, _active) if _spill_forge else 1.0
		var flick: float = 0.86 + 0.07 * sin(_time * 7.3 + float(id)) + 0.05 * sin(_time * 12.1) + 0.03 * sin(_time * 3.1)
		_spill.modulate.a = lerpf(0.1, 1.0, night) * level * flick * float((_spec.spill as Dictionary).get("base", 1.0))
	if _sparks != null:
		var burning: bool = _active > 0.5 and progress >= TownManager.PROGRESS_FULL
		if burning and not _sparks.emitting:
			_sparks.restart()
		_sparks.emitting = burning
	if _light != null and _flicker > 0.0 and _light.visible:
		var level: float = lerpf(0.4, 1.0, _active) if _spec.has("smoke") else 1.0 ## the forge sinks to embers when nobody tends it
		_light.base_energy = _light_base * level * _lamp_k * (1.0 - _flicker * (0.5 + 0.5 * sin(_time * 11.0 + float(id)) * sin(_time * 4.3 + 1.0)))
	if progress < TownManager.PROGRESS_FULL:
		queue_redraw()
		if Time.get_ticks_msec() - _last_gain_msec < 700:
			_hammer_clock -= delta
			if _hammer_clock <= 0.0:
				_hammer_clock = 0.9
				_hammer()
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 2.0, 0.0)
		_sprite.modulate = Color.WHITE.lerp(Color(1.5, 1.4, 1.2), _flash)


## The drawn build follows the real progress smoothly (it arrives in steps); the wind sways the hanging parts; once whole, the build shaders go.
func _update_build(delta: float) -> void:
	if _built_look:
		_sway_parts()
		return
	var target: float = float(progress) / float(TownManager.PROGRESS_FULL)
	_shown = lerpf(_shown, target, 1.0 - exp(-(9.0 if target >= 1.0 else 5.0) * delta))
	if target >= 1.0 and _shown > 0.997:
		_shown = 1.0
	for layer: Dictionary in _layers:
		for material: ShaderMaterial in [layer.lit, layer.glow]:
			material.set_shader_parameter("progress", _shown)
			material.set_shader_parameter("time", _time)
	_sway_parts()
	if _shown >= 1.0 and progress >= TownManager.PROGRESS_FULL:
		_built_look = true
		for layer: Dictionary in _layers:
			(layer.ghost as Sprite2D).queue_free()
			if not bool(layer.sway):
				(layer.sprite as Sprite2D).material = null


func _sway_parts() -> void:
	var wind: float = WorldWind.sample(global_position).x
	for layer: Dictionary in _layers:
		if bool(layer.sway):
			var lit: ShaderMaterial = layer.lit as ShaderMaterial
			lit.set_shader_parameter("sway_wind", wind)
			lit.set_shader_parameter("time", _time)
			lit.set_shader_parameter("progress", _shown)
	for part: Dictionary in _parts:
		if part.has("glow_mat"):
			var swing: ShaderMaterial = part.glow_mat as ShaderMaterial
			swing.set_shader_parameter("wind", wind)
			swing.set_shader_parameter("time", _time)


func _hammer() -> void:
	var player: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	player.stream = load(HAMMERS[randi() % HAMMERS.size()]) as AudioStream
	player.volume_db = -10.0
	player.max_distance = 320.0
	player.pitch_scale = randf_range(0.92, 1.08)
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
	_burst(5, Color(0.8, 0.72, 0.6, 0.7), 24.0)


## The rope frame of a site: corner posts, a rope between them and a thin line that fills along the front edge as the piece rises.
func _draw() -> void:
	if progress >= TownManager.PROGRESS_FULL or _spec.is_empty():
		return
	var foot: Array = _spec.get("foot", [16, 16]) as Array
	var w: float = float(foot[0])
	var h: float = float(foot[1])
	var left: float = -w / 2.0
	var top: float = -h
	var post: float = 9.0 + minf(w, 40.0) * 0.1
	for corner: Vector2 in [Vector2(left, top), Vector2(-left, top), Vector2(left, 0.0), Vector2(-left, 0.0)]:
		draw_line(corner, corner + Vector2(0.0, -post), POST, 1.0)
		draw_rect(Rect2(corner + Vector2(-1.0, -post - 1.0), Vector2(3.0, 2.0)), POST)
	for pair: Array in [[Vector2(left, top), Vector2(-left, top)], [Vector2(left, 0.0), Vector2(-left, 0.0)], [Vector2(left, top), Vector2(left, 0.0)], [Vector2(-left, top), Vector2(-left, 0.0)]]:
		draw_line((pair[0] as Vector2) + Vector2(0.0, -post), (pair[1] as Vector2) + Vector2(0.0, -post), ROPE, 1.0)
	var fraction: float = float(progress) / float(TownManager.PROGRESS_FULL)
	draw_line(Vector2(left, 1.5), Vector2(left + w, 1.5), Color(SITE, 0.25), 1.0)
	draw_line(Vector2(left, 1.5), Vector2(left + w * fraction, 1.5), SITE, 1.0)
	var dash: float = 4.0
	var offset: float = fmod(_time * 6.0, dash * 2.0)
	var x: float = left - offset
	while x < -left:
		if x + dash > left:
			draw_line(Vector2(maxf(x, left), top), Vector2(minf(x + dash, -left), top), Color(SITE, 0.55), 1.0)
		x += dash * 2.0


# ---------- use ----------

func prompt() -> String:
	if progress < TownManager.PROGRESS_FULL or InputManager.ui_blocking:
		return ""
	if _spec.has("fuel"):
		return manager.lamp_prompt(id)
	match String(_spec.get("role", "")):
		"stock":
			return "LAGER ÖFFNEN"
		"board":
			return "AUSHANG LESEN"
	return ""


func reach_distance(from: Vector2) -> float:
	var rect: Rect2 = TownRules.foot_rect(piece, position.x, position.y)
	var nearest: Vector2 = Vector2(clampf(from.x, rect.position.x, rect.end.x), clampf(from.y, rect.position.y, rect.end.y))
	return from.distance_to(nearest)


func prompt_position() -> Vector2:
	return Vector2(0.0, -_feet - 4.0)


func interact(player: Player) -> void:
	if _spec.has("fuel"):
		if prompt() != "" and player.is_multiplayer_authority():
			manager.request_lamp(id)
		return
	if String(_spec.get("role", "")) == "stock":
		open_shutters()
		StockWindow.open(get_tree(), player, manager, global_position + Vector2(0.0, -20.0))
	elif String(_spec.get("role", "")) == "board":
		QuestBoardWindow.open(get_tree(), player, manager, global_position + Vector2(0.0, -20.0))
