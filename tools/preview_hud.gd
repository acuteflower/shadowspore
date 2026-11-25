extends Node
## Look study of the whole HUD in the v2 main world (docs/hud_v2_konzept.md, step 1).
## `Godot --rendering-driver opengl3 --path . tools/preview_hud.tscn -- --dir=/abs/folder [--only=day,night,..] [--x2]`
## Saves hud_<scene>.png per scene: day, night, wounded (5 % health + burning + poison), folded (hotbar folded away),
## fishing (rod in hand), boss (a boss bar is tracked), arrival (first entry into the zone + a place with ENTDECKT),
## dusk. `--x2` also writes a 2x nearest-neighbour copy (`hud_<scene>_x2.png`) for reading the pixels. Offline, nothing is saved.

const HudTestWorld := preload("res://tools/hud_test_world.gd")
const SCENES: Array[String] = ["day", "night", "dusk", "wounded", "folded", "fishing", "boss", "arrival"]

var folder: String = ""
var only: PackedStringArray = PackedStringArray()
var big: bool = false
var player: Player
var hud: CanvasLayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			folder = arg.trim_prefix("--dir=")
		elif arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",", false)
		elif arg == "--x2":
			big = true
	_run.call_deferred()


func _run() -> void:
	player =await HudTestWorld.open(self)
	if player == null:
		push_error("PREVIEW HUD: the world did not load")
		get_tree().quit(1)
		return
	hud = player.get("_hud") as CanvasLayer
	GameCursor.visible = false
	_stock()
	for scene: String in SCENES:
		if not only.is_empty() and not only.has(scene):
			continue
		print("PREVIEW HUD: ", scene)
		await _reset()
		await call("_scene_" + scene)
		await _shot(scene)
	print("PREVIEW HUD OK")
	get_tree().quit()


## Tools, berries, money, xp and a tracked quest, so every vine has something to show.
func _stock() -> void:
	for id: String in ["sickle_basic", "pickaxe_basic", "axe_basic", "rod_basic"]:
		player.inventory.give(id, 1)
	player.inventory.give("dusk_berry", 4)
	player.progress.copper = 12645
	player.progress.changed.emit()
	if player.quests != null:
		player.quests.start("lumberjack")


## Neutral state before every scene: noon, full health, nothing on her, unfolded hotbar, no boss.
func _reset() -> void:
	TimeManager.set_time(0.45)
	player.health.floor_value = 0.0
	player.health.set_health(player.health.max_health)
	if player.effects != null:
		player.effects.clear_all()
	var boss: BossBar = hud.get_node_or_null("BossBar") as BossBar
	if boss != null and boss.is_fighting():
		boss.release()
	player.inventory.select(0)
	var bar: Hotbar = hud.get_node("Hotbar") as Hotbar
	bar.wake()
	await _wait(1.2)


func _scene_day() -> void:
	await _wait(0.8)


func _scene_night() -> void:
	TimeManager.set_time(0.92)
	await _wait(2.0)


func _scene_dusk() -> void:
	TimeManager.set_time(0.79)
	await _wait(2.0)


func _scene_wounded() -> void:
	player.health.floor_value = 1.0 ## burn and venom must not kill her: a death would start the goddess's StarHall rescue
	player.health.set_health(player.health.max_health * 0.05)
	if player.effects != null:
		player.effects.apply("burn", 8.0)
		player.effects.apply("shadow_venom", 12.0)
		player.effects.apply("well_rested", 60.0)
	await _wait(2.4)


func _scene_folded() -> void:
	var bar: Hotbar = hud.get_node("Hotbar") as Hotbar
	bar._quiet = Hotbar.FOLD_DELAY + 1.0
	await _wait(2.2)


func _scene_fishing() -> void:
	for i: int in InventoryComponent.HOTBAR_SIZE:
		var stack: Dictionary = player.inventory.slots[i] as Dictionary
		if String(stack.get("id", "")) == "rod_basic":
			player.inventory.select(i)
			break
	await _wait(1.6)


var _boss_health: HealthComponent


func _scene_boss() -> void:
	if _boss_health == null:
		_boss_health = HealthComponent.new()
		_boss_health.max_health = 900.0
		add_child(_boss_health)
	_boss_health.set_health(560.0)
	get_tree().call_group("boss_bar", "track", "MORNATH", _boss_health)
	await _wait(2.6)


func _scene_arrival() -> void:
	var director: ZoneDirector = (HudTestWorld.world_of(self).call("director") as ZoneDirector)
	if director == null or director.arrival == null:
		return
	var zone_id: StringName = director.player_zone.get(multiplayer.get_unique_id(), &"") as StringName
	if zone_id == &"":
		zone_id = director.atlas.zone_at(director.continent_id, player.global_position)
	(director.seen.zones as Dictionary).erase(String(zone_id))
	(director.seen.zones as Dictionary).erase(zone_id)
	director.arrival.call("_on_zone_changed", multiplayer.get_unique_id(), zone_id)
	var zone: Atlas.Zone = director.atlas.zone(zone_id)
	if zone != null and not zone.places.is_empty():
		director.arrival.set("_place", {"id": zone.places[0].id, "name": zone.places[0].name, "first": true, "age": 0.0})
	await _wait(3.2)


func _wait(seconds: float) -> void:
	var end: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame


func _shot(scene: String) -> void:
	if folder == "" or DisplayServer.get_name() == "headless": ## headless never draws a frame: frame_post_draw would never come
		return
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(folder.path_join("hud_%s.png" % scene))
	if big:
		var copy: Image = image.duplicate() as Image
		copy.resize(image.get_width() * 2, image.get_height() * 2, Image.INTERPOLATE_NEAREST)
		copy.save_png(folder.path_join("hud_%s_x2.png" % scene))
	print("saved hud_%s.png" % scene)
