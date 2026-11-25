extends Node2D
## DAS STERNENAUGE (Windkap): Aufbau, Kollision, Erwachen und Bildaufnahmen.
## Headless-Prüfung:
##   Godot --headless --path . --fixed-fps 60 res://tools/test_sternenauge.tscn
## Bilder (mit Fenster):
##   Godot --path . --fixed-fps 60 res://tools/test_sternenauge.tscn -- --capture-dir="C:/abs/ordner"

const WORLD_SCENE: PackedScene = preload("res://src/world/v2/zone_world.tscn")

var _checks: int = 0
var _fails: int = 0
var _capture_dir: String = ""


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			_capture_dir = arg.trim_prefix("--capture-dir=").strip_edges()
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		push_error("TIMEOUT in test_sternenauge")
		get_tree().quit(1))
	_run.call_deferred()


func _chk(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("FAIL: " + msg)
	print("[PASS] " if cond else "[FAIL] ", msg)


func _frames(n: int) -> void:
	for _i: int in n:
		await get_tree().process_frame


func _run() -> void:
	NetworkManager.host_singleplayer()
	await _frames(2)
	var world: ZoneWorld = WORLD_SCENE.instantiate() as ZoneWorld
	world.loading_in_steps = false
	add_child(world)
	await _frames(12)

	var stage: ZoneStage = world._director.stage(&"windkap") if world._director != null else null
	var player: Player = SaveGame._local_player(get_tree())
	_chk(stage != null and player != null, "Windkap stage and player ready")
	if stage == null or player == null:
		get_tree().quit(1)
		return

	var eye: Sternenauge = stage.props_root.get_node_or_null("WindkapLighthouse") as Sternenauge
	_chk(eye != null, "Sternenauge replaces the old lighthouse on the cape")
	if eye == null:
		get_tree().quit(1)
		return
	_chk(eye.is_in_group("windkap_lighthouse"), "Sternenauge keeps the lighthouse group (night safety, tablet)")
	_chk(not eye.awakened, "Sternenauge starts dormant on a fresh world")

	# Collision: walking north into the base must stop south of the ellipse.
	player.global_position = eye.global_position + Vector2(0.0, 90.0)
	await _frames(4)
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var q: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
	q.position = eye.global_position + Vector2(0.0, 10.0)
	q.collision_mask = 1
	_chk(not space.intersect_point(q).is_empty(), "Rock base blocks movement (world layer)")
	q.position = eye.global_position + Vector2(0.0, 80.0)
	var free_front: bool = true
	for hit: Dictionary in space.intersect_point(q):
		if hit.get("collider") != null and (hit.get("collider") as Node).get_parent() == eye:
			free_front = false
	_chk(free_front, "Stairs area in front of the crypt door stays walkable")

	var lens: Vector2 = eye.lens_global_position()
	_chk(lens.y < eye.global_position.y - 180.0, "Lens sits high above the base (%.0f px)" % (eye.global_position.y - lens.y))

	# No plaza decal any more (removed on request), steles and a clear sanctum (no boulders or old ruins)
	_chk(stage.surfaces.find_child("StonePlaza", true, false) == null, "No stone plaza decal around the statue")
	var stairs: Vector2 = eye.global_position + Vector2(0.0, 34.0)
	_chk(stage.surfaces.surface_at(stairs) == "ancient_stone", "Stairs keep a grass-free stone footprint (got '%s')" % stage.surfaces.surface_at(stairs))
	var steles: int = 0
	var rocks_on_plaza: int = 0
	var old_ruins: int = 0
	for ch: Node in stage.props_root.get_children():
		if ch is SternenaugeStele:
			steles += 1
		elif ch is LivingRock and stage.in_sanctum((ch as Node2D).global_position):
			rocks_on_plaza += 1
		elif ch is SanctuaryRuin and stage.in_sanctum((ch as Node2D).global_position, 60.0):
			old_ruins += 1
	_chk(steles == 4, "Four rune steles stand around the statue (%d)" % steles)
	_chk(rocks_on_plaza == 0, "No boulders in the sanctum (%d)" % rocks_on_plaza)
	_chk(old_ruins == 0, "Old lighthouse companion ruins are gone (%d)" % old_ruins)
	var vista: VistaPoint = stage.props_root.get_node_or_null("Vista_windkap_seeblick") as VistaPoint
	_chk(vista != null and vista.variant == 3, "Kapkanzel uses the Sternenauge bench (variant 3)")
	_chk(stage.props_root.get_node_or_null("WindkapMapTablet") != null, "Steinsetzer-Pult stands by the statue")

	var cam: Camera2D = player.get("_camera") as Camera2D
	await _shot(player, cam, eye, "01_day_wild.png", 0.42, Vector2(0.0, 120.0), 0.75)
	await _shot(player, cam, eye, "02_night_wild.png", 0.95, Vector2(0.0, 120.0), 0.75)

	eye.set_awakened(true)
	await _frames(20)
	await _capture("03_awakening.png")
	await _frames(170)
	_chk(eye.awakened and eye._blend >= 0.99, "Awakening blends fully into the lit state")
	await _shot(player, cam, eye, "04_night_awake.png", 0.95, Vector2(0.0, 120.0), 0.75)
	await _shot(player, cam, eye, "05_night_awake_wide.png", 0.95, Vector2(-120.0, 40.0), 0.5)
	await _shot(player, cam, eye, "06_day_awake.png", 0.42, Vector2(0.0, 120.0), 0.75)
	await _shot(player, cam, eye, "07_player_close.png", 0.42, Vector2(44.0, 76.0), 1.0)
	await _shot(player, cam, eye, "08_day_south.png", 0.42, Vector2(0.0, 175.0), 0.75)
	await _shot(player, cam, eye, "09_tablet.png", 0.42, Vector2(70.0, 90.0), 1.0)
	await _shot(player, cam, eye, "10_bench.png", 0.42, Vector2(-120.0, 100.0), 1.0)

	await _crypt(player, eye)
	await _arrival(world, player)

	print("STERNENAUGE: %d checks, %d failures" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _shot(player: Player, cam: Camera2D, eye: Sternenauge, file: String, t: float, stand: Vector2, zoom: float) -> void:
	TimeManager.lock_at(t)
	player.global_position = eye.global_position + stand
	if cam != null:
		cam.zoom = Vector2(zoom, zoom)
		cam.offset = Vector2(0.0, -110.0 * (1.0 if zoom < 0.9 else 0.6))
		cam.reset_smoothing()
	await _frames(24)
	await _capture(file)


func _capture(file: String) -> void:
	if _capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img != null and not img.is_empty():
		img.save_png(_capture_dir.path_join(file))
		print("CAPTURED ", file)


## The crypt under the statue: door outside, room built, walls and the shaft block, stair leads back out.
func _crypt(player: Player, eye: Sternenauge) -> void:
	var interiors: Interiors = get_tree().get_first_node_in_group("interiors") as Interiors
	var room: Interior = interiors.interior(Sternenauge.CRYPT) if interiors != null else null
	_chk(room != null, "Crypt interior is built (sternenauge_krypta)")
	_chk(eye.doorway != null and eye.doorway.interior_id == Sternenauge.CRYPT, "Statue has a crypt door")
	if room == null or eye.doorway == null:
		return
	TimeManager.lock_at(0.42)
	player.global_position = eye.doorway.global_position + Vector2(0.0, 6.0)
	await _frames(6)
	interiors.use_door(player, eye.doorway)
	await get_tree().create_timer(2.5).timeout
	_chk(interiors.interior_at(player.global_position) == room, "Crypt door takes her into the crypt")
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var q: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
	q.collision_mask = 1
	q.position = room.room_to_global(Vector2(334.0, 262.0))
	_chk(not space.intersect_point(q).is_empty(), "The open shaft blocks (no walking into the pit)")
	q.position = room.room_to_global(Vector2(450.0, 250.0))
	_chk(space.intersect_point(q).is_empty(), "Crypt floor is walkable")
	player.global_position = room.room_to_global(Vector2(250.0, 300.0))
	await _frames(30)
	await _capture("12_crypt_day.png")
	TimeManager.lock_at(0.95)
	await _frames(30)
	await _capture("13_crypt_night.png")
	TimeManager.lock_at(0.42)
	player.global_position = room.room_to_global(Vector2(116.0, 296.0))
	await _frames(6)
	interiors.use_door(player, room.door)
	await get_tree().create_timer(2.5).timeout
	_chk(not Interiors.is_pocket(player.global_position) and player.global_position.distance_to(eye.exit_position) < 24.0, "Stair leads back out in front of the statue")


## A new game: text cards on black, she climbs out of the canal shaft in the crypt, control returns beside the pit.
func _arrival(world: ZoneWorld, player: Player) -> void:
	var interiors: Interiors = get_tree().get_first_node_in_group("interiors") as Interiors
	var room: Interior = interiors.interior(Sternenauge.CRYPT)
	TimeManager.lock_at(0.42)
	world.start_intro()
	await _frames(2)
	var scene: CryptArrival = world.get_node_or_null("CryptArrival") as CryptArrival
	_chk(scene != null and player.intro == scene, "New game starts the crypt arrival (player held by the scene)")
	_chk(interiors.interior_at(player.global_position) == room, "Arrival places her in the crypt")
	if scene == null:
		return
	var cam: Camera2D = player.get("_camera") as Camera2D
	if cam != null:
		cam.zoom = Vector2.ONE
		cam.offset = Vector2.ZERO
	await get_tree().create_timer(1.4).timeout
	await _capture("14_arrival_card.png")
	await get_tree().create_timer(7.5).timeout
	await _capture("15_arrival_rise.png")
	print("arrival pos a ", player.global_position - room.room_to_global(Vector2.ZERO))
	await get_tree().create_timer(0.6).timeout
	await _capture("15b_arrival_rim.png")
	await get_tree().create_timer(0.7).timeout
	await _capture("16_arrival_crawl.png")
	print("arrival pos b ", player.global_position - room.room_to_global(Vector2.ZERO))
	await get_tree().create_timer(1.6).timeout
	await _capture("16b_arrival_lie.png")
	await get_tree().create_timer(4.0).timeout
	_chk(player.intro == null and not is_instance_valid(scene), "Arrival ends and hands control back")
	var spot: Vector2 = player.global_position - room.room_to_global(Vector2.ZERO)
	_chk(interiors.interior_at(player.global_position) == room and not Rect2(286.0, 234.0, 96.0, 58.0).has_point(spot), "She stands on the crypt floor beside the shaft (%.0f, %.0f)" % [spot.x, spot.y])
	await _frames(60)
	await _capture("17_arrival_done.png")
