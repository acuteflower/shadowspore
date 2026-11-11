extends Node2D
## Look study of the magic (docs/magie_konzept.md): Ellie with the Hexenulmenstab casts Bannlicht (Sternstein + Brennglas-Krone) next to a training
## dummy, then Wurzelgrund (Sternstein + Wildwuchs-Krone) towards it, on a patch of meadow. Saves frames of the cast, the open spell, the
## standing spell and its end. Offline, no save access.
##   Godot --rendering-driver opengl3 --path . tools/preview_magic.tscn -- --dir=/abs/folder [--tier=N] [--new]
## --new: Glutschwarm on three dummies, Nebelschleier on herself, Leerenschlund among the dummies instead; --gems: the same with their gems.
const PLAYER: PackedScene = preload("res://src/entities/player/player.tscn")
const DUMMY: PackedScene = preload("res://src/entities/enemies/training_dummy.tscn")

var _dir: String = ""
var _tier: int = 5
var _new: bool = false
var _fork: bool = false ## --fork: the Bleichgabel, both prongs and a GABELSCHLAG
var _gems: bool = false ## --gems: the new spells with their gems (Zunder, Dunst, Hunger) of the same tier


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			_dir = arg.trim_prefix("--dir=")
		elif arg.begins_with("--tier="):
			_tier = clampi(arg.trim_prefix("--tier=").to_int(), 1, 5)
		elif arg == "--new":
			_new = true
		elif arg == "--fork":
			_fork = true
		elif arg == "--gems":
			_new = true
			_gems = true
	y_sort_enabled = true
	var ground: Node2D = Node2D.new() ## the meadow lies below everything, like the world's ground layers (z -10)
	ground.z_index = -10
	ground.draw.connect(_draw_ground.bind(ground))
	add_child(ground)
	_run.call_deferred()


func _draw_ground(on: Node2D) -> void:
	on.draw_rect(Rect2(-400, -300, 800, 600), Color("3b6136"))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	for i: int in 900: ## a few blades and darker tufts so the light has something to fall on
		var at: Vector2 = Vector2(rng.randf_range(-400, 400), rng.randf_range(-300, 300)).round()
		on.draw_rect(Rect2(at, Vector2(1, 2)), Color("2e4f2c") if i % 3 else Color("5a8a46"))


func _shot(label: String) -> void:
	if _dir == "":
		return
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png("%s/magic_%s.png" % [_dir, label])
	print("saved ", label)


func _wait(seconds: float) -> void:
	var until: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _run() -> void:
	if _fork:
		await _run_fork()
		get_tree().quit()
		return
	if _new:
		await _run_new()
		get_tree().quit()
		return
	var player: Player = PLAYER.instantiate() as Player
	player.name = "1"
	add_child(player)
	await get_tree().process_frame
	var dummy: Node2D = DUMMY.instantiate() as Node2D
	dummy.position = Vector2(26, 10)
	add_child(dummy)
	var inv: InventoryComponent = player.inventory
	inv.clear_all()
	inv.slots[0] = {"id": "staff_hag_elm", "count": 1, "sp": "crystal_banish_%d" % _tier, "gm": "gem_lens_%d" % _tier}
	inv.select(0)
	inv.request("select", [0, 0])
	player.facing = Vector2(1, 0.3).normalized()
	await _wait(0.6)
	player.spells.debug_recharge()
	await _wait(0.3)
	await _shot("0_staff")
	player.facing = Vector2(-0.3, -1.0).normalized() ## from behind: the staff and its stones must sort behind her
	await _wait(0.4)
	await _shot("0b_staff_back")
	player.facing = Vector2(1, 0.3).normalized()
	await _wait(0.2)
	player.spells.try_cast(Vector2(40, 10))
	await _wait(0.22)
	await _shot("1_light_raise")
	await _wait(0.2)
	await _shot("2_light_strike")
	await _wait(0.25)
	await _shot("3_light_open")
	await _wait(1.6)
	await _shot("4_light_burning")
	await _wait(float(SpellRules.params("crystal_banish_%d" % _tier, "gem_lens_%d" % _tier)["seconds"]) - 1.4)
	await _shot("5_light_end")
	await _wait(1.4)
	inv.slots[0] = {"id": "staff_hag_elm", "count": 1, "sp": "crystal_roots_%d" % _tier, "gm": "gem_wild_%d" % _tier}
	inv.request("select", [0, 0])
	await _wait(0.2)
	player.spells.debug_recharge()
	player.health.set_health(player.health.max_health * 0.4)
	await _wait(0.3)
	player.spells.try_cast(Vector2(30, 20))
	await _wait(0.3)
	await _shot("6_root_draw")
	await _wait(0.3)
	await _shot("7_root_seed")
	await _wait(0.35)
	await _shot("8_root_burst")
	player.position = Vector2(26, 26)
	await _wait(1.6)
	await _shot("9_root_grown")
	await _wait(float(SpellRules.params("crystal_roots_%d" % _tier, "gem_wild_%d" % _tier)["seconds"]) - 2.0)
	await _shot("10_root_bloom")
	await _wait(0.5)
	await _shot("11_root_wither")
	get_tree().quit()


func _run_new() -> void:
	add_to_group("world")
	var player: Player = PLAYER.instantiate() as Player
	player.name = "1"
	add_child(player)
	await get_tree().process_frame
	var dummies: Array[Node2D] = []
	for at: Vector2 in [Vector2(70, -16), Vector2(84, 22), Vector2(46, 40)]:
		var dummy: Node2D = DUMMY.instantiate() as Node2D
		dummy.position = at
		add_child(dummy)
		dummies.append(dummy)
	var inv: InventoryComponent = player.inventory
	inv.clear_all()
	inv.slots[0] = {"id": "staff_hag_elm", "count": 1, "sp": "crystal_embers_%d" % _tier, "gm": ("gem_tinder_%d" % _tier) if _gems else ""}
	inv.select(0)
	inv.request("select", [0, 0])
	player.facing = Vector2(1, 0.3).normalized()
	await _wait(0.6)
	player.spells.debug_recharge()
	await _wait(0.3)
	await _shot("n0_ember_aim")
	player.spells.try_cast(Vector2(70, -16))
	await _wait(0.2)
	await _shot("n1_ember_coil")
	await _wait(0.15)
	await _shot("n2_ember_fan")
	await _wait(0.12)
	await _shot("n3_ember_fly")
	await _wait(0.12)
	await _shot("n4_ember_fly2")
	await _wait(0.4)
	await _shot("n5_ember_burning")
	player.spells.debug_recharge()
	await _wait(0.2)
	player.spells.try_cast(Vector2(70, -16))
	await _wait(0.75)
	await _shot("n5b_ember_rekindle")
	await _wait(2.0)
	inv.slots[0] = {"id": "staff_hag_elm", "count": 1, "sp": "crystal_veil_%d" % _tier, "gm": ("gem_haze_%d" % _tier) if _gems else ""}
	inv.request("select", [0, 0])
	await _wait(0.3)
	player.spells.debug_recharge()
	player.spells.try_cast(player.position + Vector2(0, -18))
	await _wait(0.3)
	await _shot("n6_veil_cast")
	await _wait(0.2)
	await _shot("n7_veil_stream")
	await _wait(0.5)
	await _shot("n8_veiled")
	player.position = Vector2(-30, 10)
	await _wait(0.8)
	await _shot("n9_veil_ghost")
	await _wait(1.0)
	await _shot("n9b_veil_cloud")
	await _wait(5.0)
	player.position = Vector2(0, 0)
	inv.slots[0] = {"id": "staff_hag_elm", "count": 1, "sp": "crystal_maw_%d" % _tier, "gm": ("gem_hunger_%d" % _tier) if _gems else ""}
	inv.request("select", [0, 0])
	await _wait(0.3)
	player.spells.debug_recharge()
	player.spells.try_cast(Vector2(66, 12))
	await _wait(0.3)
	await _shot("n10_maw_rear")
	await _wait(0.25)
	await _shot("n11_maw_strike")
	await _wait(0.5)
	await _shot("n12_maw_open")
	await _wait(1.2)
	await _shot("n13_maw_pull")
	await _wait(float(SpellRules.params("crystal_maw_%d" % _tier, ("gem_hunger_%d" % _tier) if _gems else "")["seconds"]) - 1.6)
	await _shot("n14_maw_snap")
	await _wait(0.2)
	await _shot("n15_maw_ring")
	await _wait(0.3)
	await _shot("n16_maw_close")
	await _wait(0.25)
	await _shot("n17_maw_second")


func _run_fork() -> void:
	add_to_group("world")
	var player: Player = PLAYER.instantiate() as Player
	player.name = "1"
	add_child(player)
	await get_tree().process_frame
	for at: Vector2 in [Vector2(60, -10), Vector2(74, 18)]:
		var dummy: Node2D = DUMMY.instantiate() as Node2D
		dummy.position = at
		add_child(dummy)
	var inv: InventoryComponent = player.inventory
	inv.clear_all()
	inv.slots[0] = {"id": "staff_bone_fork", "count": 1, "sp": "crystal_embers_%d" % _tier, "gm": "gem_tinder_%d" % _tier, "sp2": "crystal_maw_%d" % _tier, "gm2": "gem_hunger_%d" % _tier}
	inv.select(0)
	inv.request("select", [0, 0])
	for facing: Vector2 in [Vector2(1, 0.3), Vector2(0.2, 1.0), Vector2(-1, 0.2), Vector2(-0.3, -1.0)]:
		player.facing = facing.normalized()
		await _wait(0.5)
		player.spells.debug_recharge()
		await _wait(0.3)
		await _shot("f0_fork_%d_%d" % [roundi(facing.x * 10), roundi(facing.y * 10)])
	player.facing = Vector2(1, 0.3).normalized()
	inv.slots[0] = {"id": "staff_bone_fork", "count": 1, "sp": "crystal_banish_%d" % _tier, "sp2": "crystal_banish_%d" % _tier}
	inv.request("select", [0, 0])
	await _wait(0.6)
	player.spells.debug_recharge()
	await _wait(0.4)
	await _shot("f1_harmony")
	inv.slots[0] = {"id": "staff_bone_fork", "count": 1, "sp": "crystal_embers_%d" % _tier, "gm": "gem_tinder_%d" % _tier, "sp2": "crystal_maw_%d" % _tier, "gm2": "gem_hunger_%d" % _tier}
	inv.request("select", [0, 0])
	await _wait(0.6)
	player.spells.debug_recharge()
	player.spells.try_cast(Vector2(60, -10), 0)
	await _wait(1.0)
	player.spells.try_cast(Vector2(66, 6), 1)
	await _wait(0.5)
	await _shot("f2_fork_strike")
	await _wait(0.12)
	await _shot("f3_fork_strike2")
	await _wait(2.6)
	await _shot("f4_struck_maw")
