extends Node
## Visual verification capture scene for the Dungeon System, Steinsetzer-Prüfungstafel UI,
## Die Gezeitenkammern von Sturmhafen, Vorgath Boss Fight (with x5 BossBar + golden Stagger bar
## + ice-blue Counter flash), and DungeonResultWindow.
## Run (with renderer, NOT --headless): Godot --path . res://tools/preview_dungeon_all.tscn

const OUT_DIR: String = "C:/Users/levin/.gemini/antigravity/brain/3eeb3557-038c-4dd5-968e-547fc8e9c728/scratch/previews"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	NetworkManager.host_singleplayer()
	call_deferred("_capture_sequence")


func _snap(filename: String, frames: int = 8) -> void:
	for _i: int in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = OUT_DIR.path_join(filename)
	img.save_png(path)
	print("PREVIEW CAPTURED: ", path)


func _capture_sequence() -> void:
	RenderingServer.set_default_clear_color(Color("0a0d18"))

	var dm: DungeonManager = DungeonManager.new()
	dm.instant_transitions = true
	add_child(dm)

	var player: Player = preload("res://src/entities/player/player.tscn").instantiate() as Player
	player.name = "1"
	player.global_position = Vector2(0.0, 0.0)
	add_child(player)
	await get_tree().process_frame

	player.progress.award(0, Levels.xp_at(6))
	player.progress.request_claim(6)
	player.dungeons.debug_refill(4, 4, 88)
	player.dungeons.mark_discovered("suedkap_gezeitenkammern")
	player.dungeons.apply_victory("suedkap_gezeitenkammern", false, 342.0, 3, 1, 1480.0, 1, 0)

	## 1. DungeonWindow Tab 1 (PRÜFUNGEN) at physical gate
	var dwin: DungeonWindow = player._hud.get_node_or_null("DungeonWindow") as DungeonWindow
	if dwin != null:
		dwin.open_window("suedkap_gezeitenkammern", true)
		await _snap("01_pruefungstafel_pruefungen.png", 10)
		## 2. DungeonWindow Tab 2 (ECHOTAUSCH)
		dwin._tab = 1
		dwin.queue_redraw()
		await _snap("02_pruefungstafel_echotausch.png", 8)
		dwin.close_window()

	## 3. Mount Dungeon #1 (Die Gezeitenkammern von Sturmhafen) & capture Westliches Wrackbecken
	dm.request_enter_solo("suedkap_gezeitenkammern", true)
	for _i: int in 6:
		await get_tree().process_frame
	var scene: SuedkapGezeitenkammern = dm.active_scene_for_peer(1) as SuedkapGezeitenkammern
	var cam: Camera2D = player.get("_camera") as Camera2D
	if scene != null:
		player.global_position = scene.global_position + Vector2(-470.0, 238.0)
		if cam != null:
			cam.reset_smoothing()
		await _snap("03_gezeitenkammern_wrackbecken.png", 12)

		## 4. Boss Arena with Vorgath mid-Counter + golden Stagger Bar + x5 BossBar + 3 Bollards!
		scene.floodgate_open = true
		scene._start_boss_fight()
		player.global_position = scene.global_position + Vector2(0.0, -138.0)
		scene.vorgath.global_position = scene.global_position + Vector2(0.0, -215.0)
		scene.vorgath.facing = Vector2.DOWN
		scene.vorgath.health.current = scene.vorgath.health.max_health * 0.62
		scene.vorgath.health.changed.emit(scene.vorgath.health.current, scene.vorgath.health.max_health)
		scene.vorgath.counter.open_window(Vector2.DOWN, 4.0)
		scene.vorgath.stagger.begin_check(110.0, 10.0, 1)
		scene.vorgath.stagger.apply_stagger(44.0, 1)
		var bbar: BossBar = player._hud.get_node_or_null("BossBar") as BossBar
		if bbar != null:
			bbar.set("_grow", 1.0)
			bbar.set("_dirty", true)
			bbar.queue_redraw()
		if cam != null:
			cam.offset = Vector2(0.0, -40.0)
			cam.reset_smoothing()
		await _snap("04_vorgath_boss_fight.png", 14)
		if cam != null:
			cam.offset = Vector2.ZERO

	## 5. DungeonResultWindow Victory summary (Coop MVP showcase!)
	var resw: DungeonResultWindow = player._hud.get_node_or_null("DungeonResultWindow") as DungeonResultWindow
	if resw != null:
		resw._on_victory({
			"dungeon_id": "suedkap_gezeitenkammern",
			"name": "DIE GEZEITENKAMMERN VON STURMHAFEN",
			"zone_name": "SÜDKAP",
			"clear_sec": 318.4,
			"new_best_time": true,
			"first_clear": true,
			"used_resonance": true,
			"doubled_by_rest": true,
			"sparks_left": 3,
			"max_sparks": 3,
			"bonus_part_broken": true,
			"xp": 540,
			"copper": 210,
			"echo_granted": 16,
			"echo_capped": false,
			"items": [
				{"id": "harbor_guard_sword", "count": 1},
				{"id": "tide_bracelet", "count": 1},
				{"id": "iron_ingot", "count": 6},
				{"id": "lake_glimmer", "count": 2},
			],
			"first_clear_items": [
				{"id": "anchor_pendant", "count": 1},
				{"id": "iron_plate", "count": 2},
			],
			"party_stats": [
				{"peer_id": 1, "name": "Ellie", "damage": 1460.0, "counters": 3, "staggers": 1, "hits_taken": 0},
				{"peer_id": 2, "name": "Kael", "damage": 1090.0, "counters": 1, "staggers": 2, "hits_taken": 2},
			],
			"mvp_titles": {1: ["KLINGE DER MOLE"], 2: ["TAUMELBRECHER"]},
		})
		await _snap("05_dungeon_result_screen.png", 10)

	print("PREVIEW ALL DONE")
	get_tree().quit(0)
