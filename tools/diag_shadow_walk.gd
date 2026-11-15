extends Node
## SunShadows walk check: Ellie walks through a wood; every frame the shadow buffer is compared with the previous one in
## WORLD space (the camera moves, the ground does not). Prints frames where many resting shadow pixels appear or vanish.
## `-- [--at=x,y] [--time=0.3] [--dir=/abs] [--frames=240] [--dirx=1 --diry=0]`. Offline, no save access.
const WORLD: PackedScene = preload("res://src/world/world_level.tscn")
class EmptyWorld:
	extends WorldLevel
	func _spawn_player(_id: int) -> void: pass
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	var tile: Vector2 = Vector2(470, 640)
	var time: float = 0.3
	var dir: String = ""
	var frames: int = 240
	var walk: Vector2 = Vector2(1, 0)
	var speed: float = 70.0
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--at="):
			var parts: PackedStringArray = arg.trim_prefix("--at=").split(",")
			tile = Vector2(float(parts[0]), float(parts[1]))
		if arg.begins_with("--time="): time = float(arg.trim_prefix("--time="))
		if arg.begins_with("--dir="): dir = arg.trim_prefix("--dir=")
		if arg.begins_with("--frames="): frames = int(arg.trim_prefix("--frames="))
		if arg.begins_with("--dirx="): walk.x = float(arg.trim_prefix("--dirx="))
		if arg.begins_with("--diry="): walk.y = float(arg.trim_prefix("--diry="))
		if arg.begins_with("--speed="): speed = float(arg.trim_prefix("--speed="))
	var real: bool = OS.get_cmdline_user_args().has("--real")
	var world: WorldLevel = WORLD.instantiate() as WorldLevel
	if not real:
		world.set_script(EmptyWorld)
	add_child(world)
	var at: Vector2 = tile * 16.0
	var cell: Vector2i = Vector2i((at / 512.0).floor())
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var c: Vector2i = cell + Vector2i(dx, dy)
			if not world._chunks.has(c): world._load_chunk(c)
	var hero: Node2D
	var player: Player = null
	if real:
		player = world._players.get_child(0) as Player
		player.request_teleport(at)
		for n: Node in player.get_children():
			if n.name == "OpeningGuide": n.set_process(false)
		player.quests.set_physics_process(false)
		player.health.current = player.health.max_health
		player.health.floor_value = player.health.max_health
		player.sync_wound_visuals()
		hero = player
	else:
		var cam: Camera2D = Camera2D.new() ## the view walks like her camera would (her own shadow is not checked here)
		cam.position = at
		cam.position_smoothing_enabled = true
		world.add_child(cam)
		cam.make_current()
		hero = cam
	TimeManager.unlock()
	TimeManager.locked = true
	TimeManager.time_of_day = time
	for i: int in 120: await get_tree().process_frame
	if player != null:
		print("intro ", player.intro, " story_lock ", player.story_lock)
		if player.intro != null:
			var node: Node = player.intro
			player.end_room_intro(at)
			node.queue_free()
		player.story_lock = false
		for i: int in 30: await get_tree().process_frame
	var shadows: SunShadows = SunShadows.current
	var prev: Dictionary = {}
	var prev_hero: Vector2 = hero.global_position
	var bad: int = 0
	var saved: int = 0
	var prev_img: Image = null
	var prev_origin: Vector2i = Vector2i.ZERO
	var prev_shown: PackedByteArray = []
	var toggles: PackedStringArray = []
	for f: int in frames:
		var pressed: Array[String] = []
		if walk.x > 0.0: pressed.append("move_right")
		if walk.x < 0.0: pressed.append("move_left")
		if walk.y > 0.0: pressed.append("move_down")
		if walk.y < 0.0: pressed.append("move_up")
		for a: String in pressed: Input.action_press(a)
		if player == null:
			hero.global_position += walk.normalized() * speed / 60.0
		await RenderingServer.frame_post_draw
		var shown: PackedByteArray = shadows._item_shown.duplicate()
		if not prev_shown.is_empty():
			for i: int in mini(shown.size(), prev_shown.size()):
				if shown[i] != prev_shown[i]:
					var who: Object = instance_from_id(shadows._owner[i]) if i < shadows._owner.size() and shadows._owner[i] != 0 else null
					var spr: Variant = shadows._slot_sprite[i] if i < shadows._slot_sprite.size() else null
					toggles.append("f%d slot %d %s owner %s sprite %s" % [f, i, "ON " if shown[i] == 1 else "OFF", (who as Node).name if who is Node else "-", (spr as Node).name if is_instance_valid(spr) else "-"])
		prev_shown = shown
		var img: Image = shadows._viewport.get_texture().get_image()
		var rect: Vector4 = shadows._overlay_material.get_shader_parameter("shadow_rect")
		var origin: Vector2i = Vector2i(roundi(rect.x), roundi(rect.y))
		var now: Dictionary = {}
		for y: int in range(0, img.get_height(), 1):
			for x: int in range(0, img.get_width(), 1):
				if img.get_pixel(x, y).a > 0.5:
					now[origin + Vector2i(x, y)] = true
		if not prev.is_empty():
			var hp: Vector2 = hero.global_position
			var gone: int = 0
			var came: int = 0
			var lo: Vector2i = origin + Vector2i(8, 8)
			var hi: Vector2i = origin + Vector2i(img.get_width() - 8, img.get_height() - 8)
			for p: Variant in prev:
				var q: Vector2i = p
				if q.x < lo.x or q.y < lo.y or q.x > hi.x or q.y > hi.y: continue
				if (Vector2(q) - hp).length() < 140.0 or (Vector2(q) - prev_hero).length() < 140.0: continue ## her own shadow moves
				if not now.has(q): gone += 1
			for p: Variant in now:
				var q: Vector2i = p
				if q.x < lo.x or q.y < lo.y or q.x > hi.x or q.y > hi.y: continue
				if (Vector2(q) - hp).length() < 140.0 or (Vector2(q) - prev_hero).length() < 140.0: continue
				if not prev.has(q): came += 1
			if came > 300:
				var sum: Vector2 = Vector2.ZERO
				var cnt: int = 0
				for p: Variant in now:
					var q: Vector2i = p
					if q.x < lo.x + 12 or q.y < lo.y + 12 or q.x > hi.x - 12 or q.y > hi.y - 12: continue
					if (Vector2(q) - hp).length() < 140.0: continue
					if not prev.has(q):
						sum += Vector2(q)
						cnt += 1
				if cnt > 0:
					var mid: Vector2 = sum / cnt
					print("  came centre ", mid, " (", cnt, ")")
					for k: int in shadows._active.size():
						var t: Node2D = shadows._active[k]
						if is_instance_valid(t) and t.global_position.distance_to(mid) < 160.0:
							var parts: Array[Sprite2D] = shadows._sprites_of(t)
							var vis: String = ""
							for sp: Sprite2D in parts:
								vis += "%s:%s/%s " % [sp.name, sp.is_visible_in_tree(), sp.texture.resource_path.get_file() if sp.texture != null else "-"]
							print("    %s %s at %s moving %d slots %d..%d %s" % [t.get_class(), t.name, t.global_position, shadows._slot_moving[k], shadows._slot_start[k], shadows._slot_start[k] + shadows._slot_cap[k], vis])
			if gone + came > 60:
				bad += 1
				print("frame %d: gone %d came %d origin %s active %d drawn %d hero %s" % [f, gone, came, origin, shadows._active.size(), shadows.drawn_items, hp])
				if not dir.is_empty() and came > 300 and saved < 3:
					saved += 1
					prev_img.save_png("%s/buf_%d_prev_%d_%d.png" % [dir, f, prev_origin.x, prev_origin.y])
					img.save_png("%s/buf_%d_now_%d_%d.png" % [dir, f, origin.x, origin.y])
					get_viewport().get_texture().get_image().save_png("%s/view_%d.png" % [dir, f])
		prev = now
		prev_img = img
		prev_origin = origin
		prev_hero = hero.global_position
	for a: String in ["move_right", "move_left", "move_up", "move_down"]: Input.action_release(a)
	for t: String in toggles: print(t)
	print("WALK DONE bad frames ", bad, " of ", frames, " hero moved to ", hero.global_position)
	get_tree().quit()
