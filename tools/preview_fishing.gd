extends Node
## Look study: the real world's river, the real player with a rod. Saves one screenshot per moment.
## Godot --rendering-driver opengl3 --path . tools/preview_fishing.tscn -- --dir=/abs/folder [--night]
const WORLD: PackedScene = preload("res://src/world/world_level.tscn")
const DT: float = 1.0 / 60.0
class EmptyWorld:
	extends WorldLevel
	func _spawn_player(_id: int) -> void: pass
var f: FishingComponent
var player: Player
var out: String = ""


func _ready() -> void:
	_run.call_deferred()


func shot(name: String) -> void:
	for i: int in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/fishing_%s.png" % [out, name])


func find_spot(rivers: WorldRivers) -> Dictionary:
	var data: Dictionary = DataRegistry.table("rivers_baked")
	for ford: Array in data["fords"]:
		var centre: Vector2 = Vector2(float(ford[0]), float(ford[1]))
		for a: int in 16:
			var dir: Vector2 = Vector2.from_angle(float(a) / 16.0 * TAU)
			for r: int in range(20, 160, 2):
				var stand: Vector2 = centre + dir * float(r)
				var x: float = rivers.field_at(stand).x
				if x >= 3.0 and x <= 9.0:
					for reach: int in range(60, 120, 6):
						var target: Vector2 = stand - dir * float(reach)
						if rivers.field_at(target).x <= -14.0 and rivers.field_at(target + Vector2(10, 0)).x <= -10.0:
							return {"stand": stand, "target": target}
					break
	return {}


func tick(seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		f._host_tick(DT)
		t += DT


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			out = arg.trim_prefix("--dir=")
	var night: bool = OS.get_cmdline_user_args().has("--night")
	var world: WorldLevel = WORLD.instantiate() as WorldLevel
	world.set_script(EmptyWorld)
	add_child(world)
	world.set_process(false)
	TimeManager.unlock()
	TimeManager.time_of_day = 0.0 if night else 0.55
	var spot: Dictionary = find_spot(world._rivers)
	var cell: Vector2i = Vector2i(((spot["stand"] as Vector2) / 512.0).floor())
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			if not world._chunks.has(cell + Vector2i(dx, dy)):
				world._load_chunk(cell + Vector2i(dx, dy))
	player = load("res://src/entities/player/player.tscn").instantiate() as Player
	player.name = "1"
	player.position = spot["stand"] as Vector2
	world.get_node("Players").add_child(player)
	await get_tree().process_frame
	(player.get_node("Camera2D") as Camera2D).zoom = Vector2(2, 2)
	if player.quests != null:
		player.quests.set_flag("hud_unlocked")
	player.health.heal_full()
	player.bandaged = true
	for i: int in 20:
		await get_tree().process_frame
	f = player.fishing
	f.set_physics_process(false)
	f.book = FishBook.new("user://fish_book_preview_only.json")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://fish_book_preview_only.json"))
	f.book = FishBook.new("user://fish_book_preview_only.json")
	f._rng.seed = 4
	player.inventory.give("rod_basic", 1)
	player.inventory.give("dusk_berry", 4)
	player.inventory.give("glow_cap", 3)
	for i: int in InventoryComponent.HOTBAR_SIZE:
		if not player.inventory.slots[i].is_empty() and String(player.inventory.slots[i]["id"]) == "rod_basic":
			player.inventory.select(i)
	player._on_inventory_changed()
	for i: int in 30:
		await get_tree().process_frame
	player.facing = ((spot["target"] as Vector2) - (spot["stand"] as Vector2)).normalized()
	f.aim_point = spot["target"] as Vector2
	f.aim_valid = true
	f.bait = "dusk_berry"
	f.pose = "cork"
	await shot("1_aim")
	f.aim_valid = false
	f.aim_reason = "land"
	await shot("1b_aim_invalid")
	f._host_request("cast", [spot["target"], "dusk_berry", "cork"])
	tick(0.22)
	await shot("2_cast_flight")
	tick(0.5)
	tick(2.0)
	await shot("3_drift")
	var guard: float = 0.0
	while f.state == FishingComponent.S.DRIFTING and guard < 60.0:
		f._host_tick(DT)
		guard += DT
		if f._bite_t > 2.2:
			f._bite_t = 2.2
		if f._approaching and f.approach_time < 1.0:
			break
	await shot("4_shadow_approach")
	while f.state != FishingComponent.S.NIBBLE and guard < 80.0:
		f._host_tick(DT)
		guard += DT
	await shot("5_nibble")
	while f.state != FishingComponent.S.BITE and guard < 90.0:
		f._host_tick(DT)
		guard += DT
	await shot("6_bite")
	f._host_request("strike", [])
	if OS.get_cmdline_user_args().has("--fight"): ## a fight in steps of 0.45 s, played well: the path of the fish along the river
		for n: int in 14:
			if f.state != FishingComponent.S.DRILL:
				break
			for k: int in 27:
				f._give = 1.0 if f.phase == "flee" else 0.0
				f._reel = f.phase == "tire" and not f.tell
				f._host_tick(DT)
			await shot("fight_%02d" % n)
		return
	f.set_process(false)
	f._give = 1.0
	tick(0.4)
	for pair: Array in [[0.1, "7a_slack"], [0.5, "7b_good"], [0.95, "7c_danger"]]:
		f.tension = float(pair[0])
		f.tell = pair[1] == "7c_danger"
		await shot(String(pair[1]))
	f._host_end("", "")
	player.fishing._rpc_fx("lost", f.bobber, {"reason": "snapped"})
	await shot("8_snapped_text")
	f.book.record("moon_trout", 31, 2)
	f.book.record("silverling", 17, 2)
	f.book.record("moon_trout", 41, 3)
	var card: FishCard = player.get_node("FishCard") as FishCard
	card.show_catch("moon_trout", 41, true)
	for i: int in 40:
		await get_tree().process_frame
	await shot("9_card")
	var hud: Node = player.get("_hud") as Node
	if hud != null and hud.has_node("RiverBook"):
		(hud.get_node("RiverBook") as RiverBook).open_book()
		for i: int in 20:
			await get_tree().process_frame
		await shot("10_book")
		(hud.get_node("RiverBook") as RiverBook).close()
	# body clips: one capture per moment, two views
	f.set_process(false)
	var moments: Array = [["ready", 0.1], ["cast", 0.1], ["cast", 0.25], ["cast", 0.33], ["cast", 0.42], ["cast", 0.55], ["strike", 0.1], ["flee", 0.0], ["flee", 0.2], ["brace", 0.1], ["reel", 0.1], ["reel", 0.3], ["land", 0.25], ["land", 0.5], ["snap", 0.12], ["sag", 0.3]]
	var views: Array = [Vector2.RIGHT, Vector2.DOWN, ((spot["target"] as Vector2) - (spot["stand"] as Vector2)).normalized()]
	for v: int in views.size():
		for m: Array in moments:
			player.facing = views[v] as Vector2
			f.anim = String(m[0])
			f.anim_time = float(m[1])
			for i: int in 6:
				await get_tree().process_frame
			await shot("anim_%d_%s_%03d" % [v, String(m[0]), int(float(m[1]) * 100)])
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://fish_book_preview_only.json"))
	print("Fishing preview done: ", out)
	get_tree().quit()
