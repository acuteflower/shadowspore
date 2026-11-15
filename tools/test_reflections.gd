extends Node
## WaterReflections (docs/wasserspiegelung.md): registration, part collection, frame rects, mirror choice.

var _fails: int = 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		push_error("FAIL: " + what)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var mirror: WaterReflections = WaterReflections.new()
	add_child(mirror)
	_check(WaterReflections.current == mirror, "current is set")
	# a thing with a body, a glow child, a shadow and a ground decal
	var thing: Node2D = Node2D.new()
	thing.position = Vector2(100, 200)
	var body: Sprite2D = Sprite2D.new()
	body.name = "Sprite"
	body.texture = PlaceholderTexture2D.new()
	(body.texture as PlaceholderTexture2D).size = Vector2(64, 32)
	body.hframes = 4
	body.vframes = 2
	body.frame = 5
	body.offset = Vector2(0, -8)
	thing.add_child(body)
	var glow: Sprite2D = Sprite2D.new()
	glow.name = "Glow"
	glow.texture = body.texture
	body.add_child(glow)
	var shadow: Sprite2D = Sprite2D.new()
	shadow.name = "Shadow"
	shadow.texture = body.texture
	thing.add_child(shadow)
	var bed: Sprite2D = Sprite2D.new()
	bed.name = "Bed"
	bed.z_index = -2
	bed.texture = body.texture
	thing.add_child(bed)
	add_child(thing)
	WaterReflections.watch(thing, true)
	_check(WaterReflections._moving.has(thing), "moving thing registered")
	var parts: Array[Sprite2D] = mirror._sprites_of(thing)
	_check(parts.size() == 2 and parts[0] == body and parts[1] == glow, "parts = body + glow in draw order, no shadow/ground (%d)" % parts.size())
	var source: Rect2 = mirror._source(body)
	_check(source == Rect2(Vector2(16, 16), Vector2(16, 16)), "frame 5 of 4x2 = (16,16) 16x16: %s" % source)
	body.flip_h = true
	var dest: Rect2 = mirror._dest(body)
	_check(dest.size.x < 0.0 and dest.size.y == 16.0, "flip_h mirrors the destination: %s" % dest)
	body.flip_h = false
	_check(mirror._line_of(thing) == 200.0, "waterline = position without reflection_line()")
	_check(mirror._water_below(thing, Rect2()) == false, "no rivers = no water")
	# resting things are bucketed at the next rebuild
	var rock: Node2D = Node2D.new()
	rock.position = Vector2(600, 40)
	add_child(rock)
	WaterReflections.watch(rock)
	_check(WaterReflections._pending.has(rock), "resting thing waits for a bucket")
	mirror._rebuild()
	_check(WaterReflections._where.get(rock.get_instance_id()) == Vector2i(2, 0), "rock in bucket (2,0)")
	_check(mirror._active.is_empty() or WeatherManager.current != null, "nothing on water without rivers")
	WaterReflections.unwatch(rock)
	WaterReflections.unwatch(thing)
	_check(not WaterReflections._where.has(rock.get_instance_id()) and not WaterReflections._moving.has(thing), "unwatch forgets them")
	# the drawing pass hides everything while nothing is chosen
	mirror._on = false
	mirror._last_on = true
	mirror._draw_pass()
	_check(not mirror._last_on, "draw pass switches off")
	# GameSettings switch
	GameSettings.set_value("reflections", false)
	mirror._on = true
	mirror._rebuild()
	_check(not mirror._on, "setting off = no mirror")
	GameSettings.set_value("reflections", true)
	# players and props register through _notification
	var player: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
	player.name = "1"
	add_child(player)
	_check(WaterReflections._moving.has(player), "player registers itself")
	var before: int = WaterReflections._moving.size()
	_check(player.has_method("reflection_line") and player.reflection_painters().size() == 1, "player gives a waterline and the arm painter")
	player.queue_free()
	await get_tree().process_frame
	_check(WaterReflections._moving.size() == before - 1, "player unregisters on exit")
	if _fails == 0:
		print("REFLECTIONS OK")
	else:
		print("REFLECTIONS FAILED: %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
