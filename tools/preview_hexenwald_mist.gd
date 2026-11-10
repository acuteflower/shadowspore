extends Node
## Look captures of the Hexenwald's mist and its hallucinations in the real world (docs/hexenwald_nebel_konzept.md).
## Godot --rendering-driver opengl3 --path . tools/preview_hexenwald_mist.tscn -- --dir=/abs/folder [--night] [--at=x,y]
## Writes mist.png (she just stands in it), windup.png (a phantom spider winds up, eyes, a false find, a lying vine), puff.png (it falls apart), clear.png (the earrings).
const WORLD: PackedScene = preload("res://src/world/world_level.tscn")
func _ready() -> void: _run.call_deferred()
func _shot(dir: String, name_: String) -> void:
	await RenderingServer.frame_post_draw
	if not dir.is_empty(): get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name_])
func _run() -> void:
	var dir: String = ""
	var tile: Vector2 = Vector2(826, 880)
	var night: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="): dir = arg.trim_prefix("--dir=")
		if arg == "--night": night = true
		if arg.begins_with("--at="):
			var parts: PackedStringArray = arg.trim_prefix("--at=").split(",")
			tile = Vector2(float(parts[0]), float(parts[1]))
	var world: WorldLevel = WORLD.instantiate() as WorldLevel
	add_child(world)
	var hero: Player = world._players.get_child(0) as Player
	hero.request_teleport(tile * 16.0)
	hero.get_node("OpeningGuide").set_process(false)
	hero.quests.set_physics_process(false)
	hero.quests.set_flag("hud_unlocked")
	hero.quests.set_flag("mist_hint_seen")
	hero.progress.claimed = 25
	hero.progress.apply_stats(false)
	hero.health.floor_value = hero.health.max_health
	hero.health.current = hero.health.max_health
	hero.sync_wound_visuals()
	TimeManager.unlock()
	TimeManager.locked = true
	TimeManager.time_of_day = 0.0 if night else 0.5
	for i: int in 200: await get_tree().process_frame
	await _shot(dir, "mist")
	var seen: Hallucinations = hero.get_node_or_null("Hallucinations") as Hallucinations
	if seen == null:
		push_error("no hallucinations: the effect is not on her")
		get_tree().quit(1)
		return
	seen.trug = 1.0
	for kind: String in seen._wait: seen._wait[kind] = 999.0
	seen._see_eyes(hero)
	seen._see_eyes(hero)
	seen._see_decoy(hero)
	seen._see_phantom(hero)
	var phantom: PhantomSpider = seen.phantom
	phantom.global_position = hero.global_position + Vector2(70, 18)
	for i: int in 600:
		await get_tree().process_frame
		if phantom.step == PhantomSpider.Step.WINDUP and phantom._time > 0.4: break
	seen._see_lie(hero)
	await get_tree().process_frame
	await _shot(dir, "windup")
	for i: int in 200:
		await get_tree().process_frame
		if not is_instance_valid(phantom) or phantom.step == PhantomSpider.Step.GONE: break
	for i: int in 9: await get_tree().process_frame
	await _shot(dir, "puff")
	hero.inventory.give("clarity_earrings", 1)
	for i: int in InventoryComponent.SIZE:
		if String((hero.inventory.slots[i] as Dictionary).get("id", "")) == "clarity_earrings": hero.inventory.request("equip", [i, ""])
	for i: int in 200: await get_tree().process_frame
	await _shot(dir, "clear")
	print("mist capture done, effect on her: ", hero.effects.has("hallucinated"))
	get_tree().quit()
