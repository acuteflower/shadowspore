extends Node2D
## Finisher V2 capture (docs/finisher_v2_konzept.md): one "Abgrund-Pfähler" on a lone spider, saved at the key moments.
## Run (windowed): Godot --path . res://tools/preview_finisher.tscn -- --dir=C:/abs/out [--dir2x] [--flick]
## Saves finisher_0_ready.png (core beating), _1_apex, _2_plunge, _3_press, _4_rip, _5_break, _6_settle, _7_scar.

const SPIDER_SCENE: PackedScene = preload("res://src/entities/enemies/shadow_spider.tscn")
const PLAYER_SCENE: PackedScene = preload("res://src/entities/player/player.tscn")

var _dir: String = ""
var _flick: bool = false


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			_dir = arg.substr(6)
		elif arg == "--flick":
			_flick = true
	if _dir == "":
		_dir = OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(_dir)
	_run.call_deferred()


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(_dir.path_join(file_name))
	print("saved ", _dir.path_join(file_name))


func _run() -> void:
	var ground: ColorRect = ColorRect.new()
	ground.color = Color("2f624e")
	ground.position = Vector2(-400.0, -300.0)
	ground.size = Vector2(800.0, 600.0)
	ground.z_index = -10
	add_child(ground)
	var surfaces: GroundSurfaces = GroundSurfaces.new()
	add_child(surfaces)
	surfaces.setup(Rect2(-256.0, -256.0, 512.0, 512.0), 2.0)
	surfaces.commit()
	var grass: LivingGrass = LivingGrass.new()
	add_child(grass)
	grass.setup_rect(Rect2(-180.0, -140.0, 360.0, 280.0), 2027, true, surfaces)

	var enemies: Node2D = Node2D.new()
	enemies.name = "Enemies"
	enemies.y_sort_enabled = true
	add_child(enemies)

	var player: Player = PLAYER_SCENE.instantiate() as Player
	player.name = "1"
	add_child(player)
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.inventory.equipment["main_hand"] = {"id": "sword_basic", "count": 1}
	player.inventory.slots[0] = {}
	player.inventory.select(0)
	player.inventory.changed.emit()
	player.health.max_health = 500.0
	player.health.current = 500.0
	if player.quests != null and _flick:
		player.quests.set_flag(String(FinisherRules.settings().get("flick_flag", "rescued")))
	player.global_position = Vector2(-22.0, 0.0)
	player.facing = Vector2.RIGHT

	var spider: ShadowSpider = SPIDER_SCENE.instantiate() as ShadowSpider
	spider.position = Vector2(6.0, 0.0)
	enemies.add_child(spider)
	spider.set_physics_process(false)
	await get_tree().create_timer(0.6).timeout
	spider._health.current = 1.0
	spider.heading = PI
	spider._rpc_finisher_ready(1)
	await get_tree().create_timer(0.5).timeout
	await _shot("finisher_0_ready.png")

	player.attack.attack(Vector2.RIGHT)
	var plan: Array = [["apex", 0.22], ["plunge", 0.36], ["press", 0.64], ["rip", 0.82], ["break", 0.98], ["settle", 1.14]]
	var idx: int = 0
	var guard: float = 0.0
	while idx < plan.size() and guard < 6.0:
		await get_tree().process_frame
		guard += get_process_delta_time()
		if player.finisher.active() and player.finisher.elapsed() >= float((plan[idx] as Array)[1]):
			await _shot("finisher_%d_%s.png" % [idx + 1, String((plan[idx] as Array)[0])])
			idx += 1
	await get_tree().create_timer(1.2).timeout
	await _shot("finisher_7_scar.png")
	get_tree().quit(0)
