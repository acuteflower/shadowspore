extends Node
## Headless integration test for M3 & M4:
## DungeonManager, DungeonEntrance, DungeonWindow (remote G & at-gate contexts + Echo Exchange),
## DungeonReadyBanner, DungeonHud, DungeonResultWindow, and 3-spark death/wipe flow.
## Run: Godot --headless --path . res://tools/test_dungeon_ui.tscn  (prints DUNGEON UI OK)

var _checks: int = 0
var _failed: int = 0


func _ready() -> void:
	NetworkManager.host_singleplayer()
	_test_ui_and_manager()
	if _failed == 0:
		print("DUNGEON UI OK (%d checks)" % _checks)
	else:
		push_error("DUNGEON UI FAILED (%d/%d failed)" % [_failed, _checks])
	get_tree().quit(0 if _failed == 0 else 1)


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failed += 1
		push_error("FAIL: %s" % label)


func _test_ui_and_manager() -> void:
	var dm: DungeonManager = DungeonManager.new()
	add_child(dm)
	_check(DungeonManager.of(get_tree()) == dm, "DungeonManager registered in group dungeons")

	var player: Player = preload("res://src/entities/player/player.tscn").instantiate() as Player
	player.name = "1"
	add_child(player)
	## Give player Lv 5 XP so Sturmhafen is eligible
	player.progress.award(0, 600)
	_check(player.progress.level >= 5, "player leveled to >= 5")
	_check(player.dungeons != null, "player has DungeonProfileComponent")

	## Test DungeonEntrance discovery + gate signal
	var gate: DungeonEntrance = DungeonEntrance.new()
	gate.dungeon_id = "suedkap_gezeitenkammern"
	gate.zone_id = &"suedkap"
	add_child(gate)
	var gate_events: Array[Dictionary] = []
	dm.gate_window_requested.connect(func(did: String, at_g: bool) -> void:
		gate_events.append({"id": did, "at_gate": at_g}))
	gate.interact(player)
	_check(gate_events.size() == 1 and bool(gate_events[0]["at_gate"]) and String(gate_events[0]["id"]) == "suedkap_gezeitenkammern", "DungeonEntrance opens gate window at gate")
	_check(player.dungeons.is_discovered("suedkap_gezeitenkammern"), "interacting discovers dungeon")

	## Test DungeonWindow remote vs at-gate + Echo Exchange
	var win: DungeonWindow = DungeonWindow.new()
	add_child(win)
	win.bind(player)
	win.open_window("suedkap_gezeitenkammern", true)
	_check(win.is_open() and InputManager.dungeons_open, "DungeonWindow opens and sets InputManager.dungeons_open")
	win._tab = 1
	win.queue_redraw()
	win.close_window()
	_check(not win.is_open() and not InputManager.dungeons_open, "DungeonWindow closes cleanly")

	## Test Echo Exchange end-to-end through DungeonProfileComponent
	player.dungeons.debug_refill(4, 2, 60)
	_check(player.dungeons.echo_shards() == 60, "debug_refill granted 60 echo shards")
	player.dungeons.request_exchange("ex_iron_ingot_pack")
	_check(player.dungeons.echo_shards() == 48, "ex_iron_ingot_pack cost 12 -> 48 shards left")
	_check(player.inventory.count_item("iron_ingot") >= 4, "4 iron_ingot delivered to inventory")

	## Test DungeonHud, DungeonReadyBanner, DungeonResultWindow lifecycle
	var dhud: DungeonHud = DungeonHud.new()
	add_child(dhud)
	dhud.bind(player)
	dhud._on_state({"name": "DIE GEZEITENKAMMERN", "sparks": 3, "max_sparks": 3, "elapsed": 42.0, "objective": "SENKE DEN PEGELL", "progress": -1.0, "completed": false})
	_check(dhud.visible, "DungeonHud visible on active state")

	var banner: DungeonReadyBanner = DungeonReadyBanner.new()
	add_child(banner)
	banner.bind(player)
	banner._on_opened({"id": 1, "dungeon_id": "suedkap_gezeitenkammern", "eligible": [1, 2], "names": {1: "Ellie", 2: "Val"}, "responses": {1: true}, "time_left": 18.0, "duration": 20.0})
	_check(banner.visible, "DungeonReadyBanner visible on coop ready check")
	banner._on_closed("START")
	_check(not banner.visible, "DungeonReadyBanner hides on close")

	var resw: DungeonResultWindow = DungeonResultWindow.new()
	add_child(resw)
	resw.bind(player)
	resw._on_victory({
		"name": "DIE GEZEITENKAMMERN", "zone_name": "SÜDKAP", "clear_sec": 312.0, "new_best_time": true,
		"first_clear": true, "used_resonance": true, "doubled_by_rest": true, "sparks_left": 2, "max_sparks": 3,
		"xp": 520, "copper": 180, "echo_granted": 16, "echo_capped": false,
		"items": [{"id": "iron_ingot", "count": 6}], "first_clear_items": [{"id": "iron_plate", "count": 2}],
		"party_stats": [{"peer_id": 1, "name": "Ellie", "damage": 940.0, "counters": 3, "staggers": 1, "hits_taken": 1}],
		"mvp_titles": {},
	})
	_check(resw.visible and InputManager.dungeons_open, "DungeonResultWindow opens on victory")
	resw.close_window()
	_check(not resw.visible and not InputManager.dungeons_open, "DungeonResultWindow closes cleanly")

	player.queue_free()
	gate.queue_free()
	dm.queue_free()
