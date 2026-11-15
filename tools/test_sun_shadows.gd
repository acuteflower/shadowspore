extends Node
## SunShadows (docs/sonnenschatten.md): sun path, the shadow transform, caster choice and copy slots.

var _fails: int = 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		push_error("FAIL: " + what)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# the sun: west and long in the morning, north (up) and short at noon, east and long in the evening
	var morning: Vector2 = SunShadows.sun_cast(0.28)
	var noon: Vector2 = SunShadows.sun_cast(0.5)
	var evening: Vector2 = SunShadows.sun_cast(0.74)
	_check(morning.x < -0.5 and evening.x > 0.5, "morning west, evening east: %s %s" % [morning, evening])
	_check(absf(noon.x) < 0.05 and noon.y < 0.0, "noon points north: %s" % noon)
	_check(noon.length() < morning.length() and noon.length() < evening.length(), "noon is the shortest")
	_check(SunShadows.sun_cast(0.05) == SunShadows.sun_cast(SunShadows.DAWN), "before dawn the sun waits on the horizon")
	# the transform: the feet stay, a point h above them moves by cast * h, the width lies across the shadow
	var foot: Vector2 = Vector2(100, 200)
	var t: Transform2D = SunShadows.shear(foot, Vector2(0.0, -0.5))
	_check((t * foot).distance_to(foot) < 0.001, "feet stay put")
	_check((t * Vector2(100, 180)).distance_to(Vector2(100, 190)) < 0.001, "20 px up at noon = 10 px north")
	_check((t * Vector2(110, 200)).distance_to(Vector2(110, 200)) < 0.001, "noon: width stays along x")
	var side: Transform2D = SunShadows.shear(foot, Vector2(-1.0, 0.0))
	_check((side * Vector2(100, 190)).distance_to(Vector2(90, 200)) < 0.001, "morning: 10 px up = 10 px west")
	var across: Vector2 = side * Vector2(110, 200) - foot
	_check(absf(across.x) < 0.001 and absf(absf(across.y) - 10.0 * SunShadows.FORESHORTEN) < 0.001, "morning: the width turns north-south (foreshortened): %s" % across)
	# a world-free system: casters, slots and switching off
	var shadows: SunShadows = SunShadows.new()
	add_child(shadows)
	_check(SunShadows.current == shadows, "current is set")
	var camera: Camera2D = Camera2D.new()
	camera.position = Vector2(320, 180)
	add_child(camera)
	camera.make_current()
	var things: Array[Node2D] = []
	for i: int in 3:
		var thing: Node2D = Node2D.new()
		thing.position = Vector2(200 + i * 100, 200)
		var body: Sprite2D = Sprite2D.new()
		body.texture = PlaceholderTexture2D.new()
		(body.texture as PlaceholderTexture2D).size = Vector2(16, 32)
		thing.add_child(body)
		var glow: Sprite2D = Sprite2D.new()
		glow.name = "Glow"
		glow.texture = body.texture
		body.add_child(glow)
		add_child(thing)
		WaterReflections.watch(thing, i == 0)
		things.append(thing)
	await get_tree().process_frame
	_check(shadows._sprites_of(things[1]).size() == 1, "glow sprites cast no shadow")
	shadows.strength = 0.5
	shadows.cast = Vector2(-1.0, -0.3)
	shadows._rebuild()
	_check(shadows._active.size() == 3, "all three cast (%d)" % shadows._active.size())
	var runs: Dictionary = shadows._alloc.duplicate()
	shadows._rebuild()
	_check(shadows._alloc == runs, "a thing keeps its copy slots across choices")
	_check(shadows._slot_dirty.count(1) == 0, "nothing new: nothing forced to redraw")
	shadows._draw_pass()
	_check(shadows.drawn_items == 3 and shadows._last_on, "drawn and switched on (%d)" % shadows.drawn_items)
	WaterReflections.unwatch(things[2])
	things[2].queue_free()
	shadows._rebuild()
	_check(shadows._active.size() == 2 and shadows._alloc.size() == 2, "a gone thing frees its slots")
	var extra: Node2D = Node2D.new()
	extra.position = Vector2(260, 220)
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = PlaceholderTexture2D.new()
	extra.add_child(sprite)
	add_child(extra)
	WaterReflections.watch(extra)
	shadows._rebuild()
	_check(shadows._slot_dirty.count(1) == 1, "only the newcomer is drawn at once")
	var used: Dictionary = {}
	for id: Variant in shadows._alloc.keys():
		var run: Vector2i = shadows._alloc[id]
		for i: int in range(run.x, run.x + run.y):
			_check(not used.has(i), "slots never overlap")
			used[i] = true
	# wind: a picture swaying through sway_rows gets the same row slide, and its copy follows skew every frame
	var rag: Node2D = Node2D.new()
	rag.position = Vector2(330, 230)
	var cloth: Sprite2D = Sprite2D.new()
	cloth.texture = PlaceholderTexture2D.new()
	(cloth.texture as PlaceholderTexture2D).size = Vector2(12, 24)
	var sway: ShaderMaterial = ShaderMaterial.new()
	sway.shader = load("res://assets/shaders/sway_rows.gdshader") as Shader
	sway.set_shader_parameter("amount", 6.0)
	sway.set_shader_parameter("wind", 0.7)
	cloth.material = sway
	rag.add_child(cloth)
	add_child(rag)
	WaterReflections.watch(rag)
	shadows._rebuild()
	var at: int = shadows._active.find(rag)
	_check(at >= 0 and shadows._slot_sway[at] == 1, "a swaying picture is marked to follow the wind")
	shadows._draw_pass()
	var slot: int = shadows._slot_start[at]
	_check(shadows._item_mat[slot] != shadows._silhouette.get_rid(), "it draws with the row-slide silhouette")
	var copy: ShaderMaterial = (shadows._sil_mats[sway.get_instance_id()] as Dictionary)["mat"] as ShaderMaterial
	_check(copy.shader.resource_path.ends_with("shadow_silhouette_rows.gdshader") and is_equal_approx(float(copy.get_shader_parameter("amount")), 6.0), "its uniforms are copied")
	sway.set_shader_parameter("wind", -0.4)
	cloth.skew = 0.2
	shadows._frame = 0
	while (at + shadows._frame + 1) % SunShadows.ROUND == 0:
		shadows._frame += 1 ## the next pass is not this thing's full redraw
	shadows._draw_pass()
	_check(is_equal_approx(float(copy.get_shader_parameter("wind")), -0.4), "the wind follows every frame")
	_check(shadows.swayed_items >= 1, "between redraws the swaying copy is re-angled (%d)" % shadows.swayed_items)
	WaterReflections.unwatch(rag)
	# physics interpolation: a copy follows the drawn (interpolated) picture, never a teleport
	var runner: Node2D = Node2D.new()
	add_child(runner)
	runner.global_position = Vector2(100, 100)
	_check(WaterReflections.drawn_offset(runner) == Vector2.ZERO, "first sight: no lag")
	runner.global_position = Vector2(900, 100)
	_check(WaterReflections.drawn_offset(runner) == Vector2.ZERO, "a jump outside the physics step is not smeared")
	WaterReflections.unwatch(runner)
	runner.queue_free()
	GameSettings.set_value("sun_shadows", false)
	shadows.follow(false, 1.0, 0.0, 0.0, 1.0)
	shadows._rebuild()
	shadows._draw_pass()
	_check(not shadows._last_on and shadows._alloc.is_empty(), "setting off = no buffer")
	GameSettings.set_value("sun_shadows", true)
	shadows.follow(true, 1.0, 0.0, 0.0, 1.0)
	_check(shadows.strength == 0.0, "no shadows indoors")
	shadows.follow(false, 0.0, 0.0, 1.0, 1.0)
	_check(shadows.strength >= 0.0 and shadows.strength < 0.35, "the moon throws faint ones at most")
	for thing: Node2D in things:
		if is_instance_valid(thing):
			WaterReflections.unwatch(thing)
	WaterReflections.unwatch(extra)
	if _fails == 0:
		print("SUN SHADOWS OK")
	else:
		print("SUN SHADOWS FAILED: %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
