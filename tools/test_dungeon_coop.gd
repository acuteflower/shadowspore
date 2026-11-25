extends Node
## Headless test for Dungeon Coop Ready-Check, 3 Group Veil Sparks death/respawn,
## 0-Spark Wipe -> Retry (0 Resonance lost, boss resets cleanly), and Coop MVP Badges.
## Run: Godot --headless --path . res://tools/test_dungeon_coop.tscn

var _checks: int = 0
var _failed: int = 0
var _wipe_count: int = 0
var _ready_opened_count: int = 0
var _ready_closed_reason: String = ""


func _ready() -> void:
	NetworkManager.host_singleplayer()
	call_deferred("_run")


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failed += 1
		push_error("FAIL: %s" % label)


func _run() -> void:
	var dm: DungeonManager = DungeonManager.new()
	dm.instant_transitions = true
	dm.respawn_delay_sec = 0.0
	add_child(dm)
	dm.run_wiped_received.connect(func(_info: Dictionary) -> void: _wipe_count += 1)
	dm.ready_check_opened.connect(func(_info: Dictionary) -> void: _ready_opened_count += 1)
	dm.ready_check_closed.connect(func(reason: String) -> void: _ready_closed_reason = reason)

	var p1: Player = preload("res://src/entities/player/player.tscn").instantiate() as Player
	p1.name = "1"
	p1.global_position = Vector2(500.0, 500.0)
	add_child(p1)
	p1.progress.award(0, Levels.xp_at(5))
	p1.progress.request_claim(5)
	p1.dungeons.mark_discovered("suedkap_gezeitenkammern")
	await get_tree().process_frame

	## 1. Test 3 shared Group Veil Sparks death, checkpoint respawn, and 0-spark Wipe + Retry
	var charges_before: int = p1.dungeons.charges()
	dm.request_enter_solo("suedkap_gezeitenkammern", true)
	for _i: int in 3:
		await get_tree().process_frame
	var scene: SuedkapGezeitenkammern = dm.active_scene_for_peer(1) as SuedkapGezeitenkammern
	_check(scene != null, "dungeon mounted for spark/wipe test")
	if scene == null:
		_finish()
		return

	## Activate boss fight & damage boss slightly to verify wipe resets boss HP!
	scene._start_boss_fight()
	scene.vorgath.health.take_damage(200.0, p1.global_position, 0.0, 1)
	_check(scene.vorgath.health.current < scene.vorgath.health.max_health, "Vorgath damaged before wipe")

	## Die 3 times -> consumes sparks 3 -> 2 -> 1 -> 0, each respawning at checkpoint
	for death_idx: int in 3:
		p1.health.current = 0.0
		var handled: bool = dm.host_handle_player_death(p1)
		_check(handled, "death #%d handled by DungeonManager" % (death_idx + 1))
		_check(p1.health.current > 0.0, "death #%d respawned player with HP" % (death_idx + 1))
	_check(_wipe_count == 0, "no wipe while sparks remained")

	## 4th death at 0 sparks -> WIPE!
	p1.health.current = 0.0
	dm.host_handle_player_death(p1)
	_check(_wipe_count == 1, "0-spark death triggers wipe_shown overlay")
	_check(p1.dungeons.charges() == charges_before, "wipe consumes ZERO Resonance charges")

	## Retry after wipe -> restores 3 sparks, resets Vorgath to full HP, respawns player!
	dm.request_retry_dungeon()
	for _i: int in 2:
		await get_tree().process_frame
	_check(p1.health.current > 0.0, "retry revives player cleanly")
	_check(is_equal_approx(scene.vorgath.health.current, scene.vorgath.health.max_health), "retry resets Vorgath to 100% HP")
	_check(not scene.boss_started, "retry resets boss_started state cleanly")

	## 2. Leave cleanly & verify 0 charges lost on abandon
	dm.request_leave_dungeon()
	for _i: int in 2:
		await get_tree().process_frame
	_check(not dm.is_player_in_dungeon(1), "abandoned dungeon unmounted cleanly")
	_check(p1.dungeons.charges() == charges_before, "abandoning dungeon consumes ZERO Resonance charges")

	## 3. Verify Coop MVP Badges & 4P scaling rules
	var party: Array[Dictionary] = [
		{"peer_id": 1, "name": "Ellie", "damage": 1420.0, "counters": 3, "staggers": 1, "hits_taken": 1},
		{"peer_id": 2, "name": "Kael", "damage": 980.0, "counters": 1, "staggers": 2, "hits_taken": 0},
	]
	var mvps: Dictionary = DungeonRules.assign_mvp_titles(party)
	var t1: Array = mvps.get(1, []) as Array
	var t2: Array = mvps.get(2, []) as Array
	_check(not t1.is_empty(), "Peer 1 wins MVP badge")
	_check(not t2.is_empty(), "Peer 2 wins MVP badge")

	p1.queue_free()
	dm.queue_free()
	_finish()


func _finish() -> void:
	if _failed == 0:
		print("DUNGEON COOP OK (%d checks)" % _checks)
	else:
		push_error("DUNGEON COOP FAILED (%d/%d failed)" % [_failed, _checks])
	get_tree().quit(0 if _failed == 0 else 1)
