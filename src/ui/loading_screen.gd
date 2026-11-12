class_name LoadingScreen
extends Control
## The loading screen (`GameLauncher.start`): bright silhouettes in the abyss. The stage opens with the world map's violet wipe onto the void (the
## same void as the world's edge and the main menu, `loading_veil.gdshader`); along a thin glowing path of land Ellie and two companions walk in as
## pale silhouettes (real walk cycles from their sheets, the frame rate tied to the ground they cover, so no foot slides). When the world is ready
## (`complete()`) a void spider (a shadow creature: black body, violet rim, burning eyes) bursts in from the left, the group startles one after the
## other and sprints off (sprint cycles), the spider skitters after them; `finished` fires and `reveal_world()` closes the stage like the map closes.
## Cast and speeds: data/loading.json. Completion is explicitly gated by the launcher.
signal finished

const VEIL: Shader = preload("res://assets/shaders/loading_veil.gdshader")
const SILHOUETTE: Shader = preload("res://assets/shaders/silhouette.gdshader")
const ENTRANCE_END: float = 2.1 ## the chase may start once the cast has walked in
const RUN_LENGTH: float = 2.5 ## the spider crosses the stage
const CHASE_LENGTH: float = 2.8 ## then `finished`
const HORIZON: float = 212.0 ## the ground line the feet stand on (stage pixels)
const CAST_SCALE: float = 2.0
const SLOT_X: Array[float] = [446.0, 352.0, 258.0] ## Ellie leads, the companions follow
const STARTLE: Array[float] = [0.24, 0.12, 0.0] ## the rear one notices the spider first
const OPEN_SECONDS: float = 0.75
const CLOSE_SECONDS: float = 0.45
const HERO_BODY: Color = Color("d9c8ff") ## pale lilac light
const HERO_EDGE: Color = Color("fbf6ff")

var companions: Array[int] = [] ## indices into data/loading.json "cast" (1..3)
var age: float = 0.0
var chase: float = -1.0
var ready_to_leave: bool = false
var done: bool = false
var error_text: String = ""

var _cfg: Dictionary = {}
var _backing: ColorRect
var _back: ColorRect
var _back_material: ShaderMaterial
var _actors: Array[Dictionary] = []
var _spider_rig: SpiderRig
var _spider_picture: TextureRect
var _spider_camera: Camera2D
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
	var cast: Array = _cfg.get("cast", []) as Array
	for slot: int in 3:
		var index: int = 0 if slot == 0 else (companions[slot - 1] if slot - 1 < companions.size() else -1)
		if index >= 0 and index < cast.size():
			_add_actor(cast[index] as Dictionary, slot)
	_build_spider()
	update_visuals(0.0)


## The heroes are light (pale lilac, a whiter lit edge); the spider is a shadow creature (void-black body, violet rim, its eyes and veins burning).
func _silhouette(body: Color, rim: Color, rim_strength: float, glow: bool) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = SILHOUETTE
	material.set_shader_parameter("body", body)
	material.set_shader_parameter("rim", rim)
	material.set_shader_parameter("rim_strength", rim_strength)
	material.set_shader_parameter("keep_glow", glow)
	return material


## One walker: the real sheet, east-facing row, with its walk and sprint clips (from the rig file, or given in data/loading.json for Ellie).
func _add_actor(spec: Dictionary, slot: int) -> void:
	var texture: Texture2D = load(String(spec.get("sheet", ""))) as Texture2D
	if texture == null:
		return
	var frame: Array = spec.get("frame", []) as Array
	var feet: Array = spec.get("feet", []) as Array
	var walk: Array = spec.get("walk", []) as Array
	var run: Array = spec.get("run", []) as Array
	if spec.has("rig"):
		var rig: Dictionary = DataRegistry.table(String(spec.rig))
		frame = rig.get("frame", [48, 56]) as Array
		feet = rig.get("feet", [24, 51]) as Array
		var clips: Dictionary = rig.get("clips", {}) as Dictionary
		var w: Dictionary = clips.get("walk", clips.get("run", {})) as Dictionary
		var r: Dictionary = clips.get("run", clips.get("walk", {})) as Dictionary
		walk = [int(w.get("start", 0)), int(w.get("count", 1))]
		run = [int(r.get("start", 0)), int(r.get("count", 1))]
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.hframes = maxi(1, int(texture.get_width() / int(frame[0])))
	sprite.vframes = maxi(1, int(texture.get_height() / int(frame[1])))
	sprite.offset = -Vector2(float(feet[0]), float(feet[1]))
	sprite.scale = Vector2(CAST_SCALE, CAST_SCALE)
	sprite.material = _silhouette(HERO_BODY, HERO_EDGE, 0.55, false)
	sprite.visible = false
	add_child(sprite)
	_actors.append({"sprite": sprite, "slot": slot, "walk": walk, "run": run,
			"walk_stride": float(spec.get("walk_stride", 5.0)), "run_stride": float(spec.get("run_stride", 8.0))})


func _build_spider() -> void:
	# The exact gameplay rig and textures, without combat, collisions or networking; shown as a silhouette with burning eyes.
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(192, 128)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	_spider_rig = SpiderRig.new()
	_spider_rig.name = "LoadingVoidSpider"
	for part: String in ["Back", "Body", "Front", "Glow"]:
		var node: Node2D = Sprite2D.new() if part == "Body" else Node2D.new()
		node.name = part
		if part == "Body":
			var body: Sprite2D = node as Sprite2D
			body.texture = preload("res://assets/enemies/shadow_spider_body.png")
			body.hframes = 8
			var flash: ShaderMaterial = ShaderMaterial.new()
			flash.shader = preload("res://assets/shaders/hit_flash.gdshader")
			body.material = flash
		if part == "Glow":
			var glow: CanvasItemMaterial = CanvasItemMaterial.new()
			glow.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			glow.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
			node.material = glow
		_spider_rig.add_child(node)
	viewport.add_child(_spider_rig)
	_spider_rig.position = Vector2(96, 89)
	_spider_camera = Camera2D.new()
	_spider_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(_spider_camera)
	_spider_camera.position = _spider_rig.position + Vector2(0, -25)
	_spider_picture = TextureRect.new()
	_spider_picture.texture = viewport.get_texture()
	_spider_picture.size = Vector2(192, 128)
	_spider_picture.scale = Vector2(CAST_SCALE, CAST_SCALE)
	_spider_picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_spider_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spider_picture.material = _silhouette(Color("040208"), Color("8a4dff"), 1.0, true)
	_spider_picture.visible = false
	add_child(_spider_picture)
	_spider_rig.set_aim(Vector2.RIGHT)


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
	_travel += delta * float(_cfg.get("walk_speed", 46.0))
	update_visuals(delta)
	queue_redraw()


func _process(delta: float) -> void:
	advance(minf(delta, 0.05))


func _origin() -> Vector2:
	return ((size - Vector2(640.0, 360.0)) * 0.5).round()


## How far the walker in `slot` has come in from the left (stage x) and how far it has sprinted since the spider came.
func _entry_x(slot: int) -> float:
	var entry: float = clampf((age - 0.35 - float(slot) * 0.3) / 1.4, 0.0, 1.0)
	return lerpf(-70.0, SLOT_X[slot], 1.0 - pow(1.0 - entry, 3.0))


func _escape(slot: int) -> float:
	return maxf(0.0, chase - STARTLE[slot]) if chase >= 0.0 else 0.0


func _sprint_offset(e: float) -> float:
	var top: float = float(_cfg.get("sprint_speed", 210.0)) - float(_cfg.get("walk_speed", 46.0))
	var ramp: float = 0.3
	if e < ramp:
		return 0.5 * top / ramp * e * e
	return 0.5 * top * ramp + top * (e - ramp)


func update_visuals(delta: float) -> void:
	if _back_material == null:
		return
	var opening: float = _opening_override if _opening_override >= 0.0 else smoothstep(0.0, OPEN_SECONDS, age)
	_back_material.set_shader_parameter("time", age)
	_back_material.set_shader_parameter("travel", _travel)
	_back_material.set_shader_parameter("view_size", size)
	_back_material.set_shader_parameter("opening", opening)
	if _revealing:
		return
	var origin: Vector2 = _origin()
	var walk_speed: float = float(_cfg.get("walk_speed", 46.0))
	for actor: Dictionary in _actors:
		var sprite: Sprite2D = actor.sprite
		var slot: int = int(actor.slot)
		var x0: float = _entry_x(slot)
		var e: float = _escape(slot)
		var x: float = x0 + _sprint_offset(e)
		sprite.visible = age > 0.35 + float(slot) * 0.3 and x < 720.0
		var col: int = 0
		if e > 0.0:
			# the sprint: the ground under the feet is the camera's walk plus the run across the stage
			var run: Array = actor.run
			col = int(run[0]) + posmod(int((_sprint_offset(e) + walk_speed * e) / float(actor.run_stride)), int(run[1]))
		else:
			var walk: Array = actor.walk
			col = int(walk[0]) + posmod(int((_travel + x0 + 70.0) / float(actor.walk_stride)), int(walk[1]))
		sprite.frame = clampi(col, 0, sprite.hframes * sprite.vframes - 1) ## row 0 = facing east
		var hop: float = 0.0
		if e > 0.0 and e < 0.2:
			hop = roundf(sin(e / 0.2 * PI) * 5.0) ## startled
		sprite.position = (origin + Vector2(x, HORIZON - hop)).round()
	_spider_picture.visible = chase >= 0.0 and chase < RUN_LENGTH
	if _spider_picture.visible:
		var sx: float = -120.0 + float(_cfg.get("spider_speed", 330.0)) * chase
		_spider_picture.position = (origin + Vector2(sx, HORIZON - 7.0) - Vector2(96.0, 89.0) * CAST_SCALE).round()
		# Advance the planted-foot rig in its own travelling world. UI acceleration
		# must not stretch world-anchored legs across half the loading screen.
		var remaining: float = delta
		while remaining > 0.0:
			var step: float = minf(remaining, 1.0 / 60.0)
			_spider_rig.position.x += step * 200.0
			_spider_camera.position = _spider_rig.position + Vector2(0, -25)
			_spider_camera.force_update_scroll()
			_spider_rig.update_rig(step, Vector2(200, 0), 0.0)
			remaining -= step


func _draw() -> void:
	if _revealing:
		return
	draw_set_transform(_origin())
	var fade: float = smoothstep(0.3, 0.9, age)
	if chase >= 0.0:
		fade *= 1.0 - clampf(chase * 3.0, 0.0, 1.0)
	var caption: String = "LÄDT" + ".".repeat(1 + int(age * 2.0) % 3)
	var x: int = 320 - PixelText.width("LÄDT...") / 2
	var ink: Color = Color("cbaaff")
	if not error_text.is_empty():
		caption = error_text
		x = 320 - PixelText.width(caption) / 2
		ink = Color("ff7a7a")
		fade = 1.0
	if fade > 0.0:
		PixelText.draw(self, caption, Vector2i(x, int(HORIZON) + 22), Color(ink, fade), Color("040208", fade))
	draw_set_transform(Vector2.ZERO)


func reveal_world() -> void:
	_revealing = true
	_backing.hide()
	for actor: Dictionary in _actors:
		(actor.sprite as Sprite2D).hide()
	_spider_picture.hide()
	queue_redraw()
	var tween: Tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_method(_set_opening, 1.0, 0.0, CLOSE_SECONDS)
	await tween.finished
	hide()


func _set_opening(value: float) -> void:
	_opening_override = value
	update_visuals(0.0)
