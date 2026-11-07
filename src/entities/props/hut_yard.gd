class_name HutYard
extends Node2D
## What stands in the yard of a hut (art: tools/hut_yard.py -> assets/interior/hut/yard_*.png; data: data/ground.json huts[].yard.props; the trampled earth and the
## stepping stones are the ground decal `<hut>_yard` of tools/bake_ground.py). A child of the `Hut`, so it sorts with the world by each prop's feet.
## A prop is `{id, tex, pos [x, y] (feet, px from the hut's feet), feet (the row of the sprite that stands on pos), frames/frame, glow (true: `<tex>_glow.png`
## is drawn unlit on top, dim by day and alive at night), solid [w, h, ox, oy], layers, anim, light, sparks, smoke, sound}`:
##  - `layers`: more sprites hung on this one, each `{tex, glow, sway {pivot (row), dir, amount, flutter, cell}}`; a swaying layer's rows slide sideways in the wind
##    (`sway_rows.gdshader`: the garden's plants, the rags on the line)
##  - `anim`: a frame strip on top of the prop (the fire): `{tex, frames, fps, at [x, y], feet}`, unlit
##  - `light`: a warm `NightLight` that flickers (`{color, radius, squash, energy, at [x, y], flicker}`)
##  - `sparks`/`smoke`: embers rising from the fire and a thin thread of smoke; `sound`: a quiet positional loop (fire crackling)

const DIR: String = "res://assets/interior/hut/" ## the default folder of the art (the quarry sets its own)
const SWAY: Shader = preload("res://assets/shaders/sway_rows.gdshader")

var _time: float = 0.0
var _dir: String = DIR
var _anims: Array[Dictionary] = [] ## {sprite, frames, fps, phase}
var _swayers: Array[ShaderMaterial] = []
var _glows: Array[Sprite2D] = []
var _lights: Array[Dictionary] = [] ## {light, base, flicker, phase}
var _crackle: Array[AudioStreamPlayer2D] = []
var _body: StaticBody2D


func setup(specs: Array, dir: String = DIR) -> void:
	_dir = dir
	y_sort_enabled = true
	_body = StaticBody2D.new()
	_body.name = "Colliders"
	add_child(_body)
	for spec: Dictionary in specs:
		if spec.has("tex"):
			_prop(spec)


func body_rid() -> RID: ## the colliders of the props (a sight line ignores them)
	return _body.get_rid()


func _vec(raw: Variant) -> Vector2:
	var a: Array = raw as Array
	return Vector2(float(a[0]), float(a[1]))


func _texture(file: String) -> Texture2D:
	return load(file if file.begins_with("res://") else _dir + file) as Texture2D


## A sprite that stands with row `feet` on `pos`; `pivot` (a row) is where it hangs from instead, when it sways around another row than its feet.
func _standing(file: String, frames: int, frame: int, feet: float, at: Vector2, pivot: float = -1.0, rows: int = 1) -> Sprite2D:
	var texture: Texture2D = _texture(file)
	var row: float = feet if pivot < 0.0 else pivot
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = texture
	sprite.hframes = frames
	sprite.vframes = rows
	sprite.frame = frame
	sprite.offset = Vector2(0.0, texture.get_height() / rows / 2.0 - row)
	sprite.position = at + Vector2(0.0, row - feet)
	return sprite


func _glow_of(sprite: Sprite2D, file: String) -> void:
	var glow_file: String = file.replace(".png", "_glow.png")
	if not ResourceLoader.exists(glow_file if glow_file.begins_with("res://") else _dir + glow_file):
		return
	var glow: Sprite2D = Sprite2D.new()
	glow.texture = _texture(glow_file)
	glow.hframes = sprite.hframes
	glow.vframes = sprite.vframes
	glow.frame = sprite.frame
	glow.offset = sprite.offset
	if sprite.material is ShaderMaterial: ## it moves with the picture it belongs to
		var copy: ShaderMaterial = (sprite.material as ShaderMaterial).duplicate() as ShaderMaterial
		var shader: Shader = Shader.new()
		shader.code = SWAY.code.replace("shader_type canvas_item;", "shader_type canvas_item;\nrender_mode unshaded;")
		copy.shader = shader
		glow.material = copy
		_swayers.append(copy)
	else:
		glow.material = Unlit.material()
	sprite.add_child(glow)
	_glows.append(glow)


func _prop(spec: Dictionary) -> void:
	var file: String = String(spec.tex)
	var frames: int = int(spec.get("frames", 1))
	var at: Vector2 = _vec(spec.pos)
	var feet: float = float(spec.get("feet", 0))
	var rows: int = int(spec.get("rows", 1)) ## a sheet of several rows (the world's rocks: 8 rocks x 4 states): `row` picks one
	var sprite: Sprite2D = _standing(file, frames, int(spec.get("row", 0)) * frames + int(spec.get("frame", 0)), feet, at, -1.0, rows)
	sprite.name = String(spec.get("id", file))
	sprite.flip_h = bool(spec.get("flip", false))
	sprite.z_index = int(spec.get("z", 0)) ## flat things lying on the floor (the mine's puddles and bones) sit below everything that stands
	add_child(sprite)
	if bool(spec.get("glow", false)):
		_glow_of(sprite, file)
		if spec.has("pulse"): ## the glow breathes: [rate, depth] (the mine's crystals, pods and void cracks)
			var pulse: Array = spec.pulse as Array
			_glows[_glows.size() - 1].set_meta("pulse", [float(pulse[0]), float(pulse[1]), randf() * TAU])
	for layer: Dictionary in spec.get("layers", []) as Array:
		_layer(sprite, layer, feet)
	if spec.has("anim"):
		var a: Dictionary = spec.anim as Dictionary
		var strip: Sprite2D = _standing(String(a.tex), int(a.frames), 0, float(a.feet), _vec(a.get("at", [0, 0])) )
		strip.material = Unlit.material()
		sprite.add_child(strip)
		_anims.append({"sprite": strip, "frames": int(a.frames), "fps": float(a.fps), "phase": randf() * 6.0})
	if spec.has("light"):
		var l: Dictionary = spec.light as Dictionary
		var light: NightLight = NightLight.new()
		light.position = _vec(l.get("at", [0, 0]))
		light.radius = int(l.radius)
		light.squash = float(l.get("squash", 0.7))
		light.base_energy = float(l.energy)
		light.glow_color = Color(String(l.color))
		light.pulse = 0.25
		sprite.add_child(light)
		_lights.append({"light": light, "base": float(l.energy), "flicker": float(l.get("flicker", 0.0)), "phase": randf() * 6.0})
	if bool(spec.get("sparks", false)):
		_sparks(sprite)
	if bool(spec.get("smoke", false)):
		_smoke(sprite)
	if spec.has("sound"):
		var player: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		player.stream = load(String(spec.sound) if String(spec.sound).begins_with("res://") else "res://assets/audio/hut/" + String(spec.sound)) as AudioStream
		player.max_distance = 150.0
		player.volume_db = -20.0
		player.finished.connect(func() -> void: player.play())
		sprite.add_child(player)
		_crackle.append(player)
	if spec.has("solid"):
		var s: Array = spec.solid as Array
		var shape: CollisionShape2D = CollisionShape2D.new()
		var box: RectangleShape2D = RectangleShape2D.new()
		box.size = Vector2(float(s[0]), float(s[1]))
		shape.shape = box
		shape.position = at + Vector2(float(s[2]), float(s[3])) + box.size / 2.0
		_body.add_child(shape)


func _layer(parent: Sprite2D, layer: Dictionary, feet: float) -> void:
	var file: String = String(layer.tex)
	var sway: Dictionary = layer.get("sway", {}) as Dictionary
	var pivot: float = float(sway.get("pivot", feet))
	var sprite: Sprite2D = _standing(file, 1, 0, feet, Vector2.ZERO, pivot)
	if not sway.is_empty():
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = SWAY
		material.set_shader_parameter("pivot_row", pivot)
		material.set_shader_parameter("dir", float(sway.get("dir", 1.0)))
		material.set_shader_parameter("amount", float(sway.get("amount", 4.0)))
		material.set_shader_parameter("flutter", float(sway.get("flutter", 0.5)))
		material.set_shader_parameter("cell_w", float(sway.get("cell", 12.0)))
		material.set_shader_parameter("speed", float(sway.get("speed", 2.4)))
		sprite.material = material
		_swayers.append(material)
	parent.add_child(sprite)
	if bool(layer.get("glow", false)):
		_glow_of(sprite, file)


func _sparks(parent: Node2D) -> void:
	var sparks: CPUParticles2D = CPUParticles2D.new() ## embers lifted by the heat: a few orange specks rising and going out
	sparks.position = Vector2(0, -8)
	sparks.amount = 7
	sparks.lifetime = 1.7
	sparks.preprocess = 1.7
	sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 5.0
	sparks.direction = Vector2(0.2, -1.0)
	sparks.spread = 22.0
	sparks.gravity = Vector2(1.5, -6.0)
	sparks.initial_velocity_min = 10.0
	sparks.initial_velocity_max = 24.0
	sparks.scale_amount_min = 1.0
	sparks.scale_amount_max = 1.0
	var fade: Gradient = Gradient.new()
	fade.colors = PackedColorArray([Color(1.0, 0.78, 0.36, 1.0), Color(1.0, 0.45, 0.16, 0.8), Color(0.6, 0.2, 0.1, 0.0)])
	fade.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	sparks.color_ramp = fade
	sparks.material = Unlit.material()
	sparks.z_index = 2
	parent.add_child(sparks)


func _smoke(parent: Node2D) -> void:
	var smoke: CPUParticles2D = CPUParticles2D.new() ## a thin grey-violet thread, the same smoke as the chimney's
	smoke.position = Vector2(0, -12)
	smoke.z_index = 3
	smoke.amount = 9
	smoke.lifetime = 4.2
	smoke.preprocess = 4.2
	smoke.direction = Vector2(0.3, -1.0)
	smoke.spread = 12.0
	smoke.gravity = Vector2(3.0, -2.0)
	smoke.initial_velocity_min = 8.0
	smoke.initial_velocity_max = 13.0
	smoke.scale_amount_min = 1.4
	smoke.scale_amount_max = 3.0
	var fade: Gradient = Gradient.new()
	fade.colors = PackedColorArray([Color(0.62, 0.58, 0.7, 0.0), Color(0.62, 0.58, 0.7, 0.34), Color(0.46, 0.43, 0.56, 0.0)])
	fade.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	smoke.color_ramp = fade
	parent.add_child(smoke)


const ANIMATE_RANGE: float = 600.0 ## px: yards far from every player are not animated (`_time` keeps running)

func _near_player(radius: float) -> bool:
	for player: Player in Player.all:
		if is_instance_valid(player) and player.global_position.distance_squared_to(global_position) <= radius * radius: return true
	return false

func _process(delta: float) -> void:
	_time += delta
	if not Player.all.is_empty() and not _near_player(ANIMATE_RANGE): return
	var night: float = MineManager.night_at(self, TimeManager.night_amount())
	for entry: Dictionary in _anims:
		var sprite: Sprite2D = entry.sprite as Sprite2D
		sprite.frame = int((_time + float(entry.phase)) * float(entry.fps)) % int(entry.frames)
	for entry: Dictionary in _lights: ## the fire's light flickers (the NightLight itself only breathes slowly)
		var t: float = _time + float(entry.phase)
		(entry.light as NightLight).base_energy = float(entry.base) * (1.0 - float(entry.flicker) * (0.5 + 0.5 * sin(t * 11.0) * sin(t * 4.3 + 1.0)))
	var wind: float = WorldWind.sample(global_position).x
	for material: ShaderMaterial in _swayers:
		material.set_shader_parameter("wind", wind)
		material.set_shader_parameter("time", _time)
	for glow: Sprite2D in _glows:
		glow.modulate.a = lerpf(0.55, 1.0, night)
		if glow.has_meta("pulse"):
			var pulse: Array = glow.get_meta("pulse") as Array
			glow.modulate.a *= 1.0 - float(pulse[1]) * (0.5 + 0.5 * sin(_time * float(pulse[0]) + float(pulse[2])))
	for player: AudioStreamPlayer2D in _crackle:
		if not player.playing:
			player.play()
