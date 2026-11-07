extends Node
## Captures the first phase of the fight with Mornath in the real arena (needs graphics:
##   Godot --rendering-driver opengl3 --path . --fixed-fps 60 tools/preview_boss_fight.tscn -- --dir=/abs/folder [--acts=barrier,rain,shot,line,chase,blast,break] [--every=15] [--skip-intro]
## Plays the acts one after the other (forced, in that order) and saves a picture every `every` frames (60 = a second) of each. The player cannot die.
## Offline: no save is read or written.
var _dir: String = ""
var _acts: Array[String] = ["barrier", "rain", "shot", "line", "chase", "blast", "break"]
var _every: int = 15
var _boss: SkyCleaver
var _fight: MornathFight
var _player: Player
var _origin: Vector2
var _at: Vector2 = Vector2(30, -50)
var _then: Vector2 = Vector2.INF ## after the opening the player goes here (outside the line of fire, still within the reset radius)


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			_dir = arg.trim_prefix("--dir=")
		elif arg.begins_with("--acts="):
			_acts = []
			for a: String in arg.trim_prefix("--acts=").split(","):
				_acts.append(a)
		elif arg.begins_with("--at="):
			var parts: PackedStringArray = arg.trim_prefix("--at=").split(",")
			_at = Vector2(float(parts[0]), float(parts[1]))
		elif arg.begins_with("--then="):
			var q: PackedStringArray = arg.trim_prefix("--then=").split(",")
			_then = Vector2(float(q[0]), float(q[1]))
		elif arg.begins_with("--every="):
			_every = maxi(0, int(arg.trim_prefix("--every=")))
	_run.call_deferred()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [_dir, name])


func _wait_idle() -> void:
	while _fight.mode != MornathFight.Mode.IDLE or _boss.state != SkyCleaver.State.PERCHED:
		await get_tree().physics_frame
	_fight._gap = 99.0


## Script time of a frame in ms (process + physics) and the draw calls of the frame.
func _sample(stats: Dictionary) -> void:
	var ms: float = (Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	var calls: float = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	stats["n"] = int(stats["n"]) + 1
	stats["ms"] = float(stats["ms"]) + ms
	stats["ms_max"] = maxf(float(stats["ms_max"]), ms)
	stats["calls"] = float(stats["calls"]) + calls
	stats["calls_max"] = maxf(float(stats["calls_max"]), calls)


func _report(prefix: String, stats: Dictionary) -> void:
	var n: float = maxf(float(stats["n"]), 1.0)
	print("PERF %-10s script avg %.2f ms  max %.2f ms | draw calls avg %.0f  max %.0f | %d frames" % [prefix, float(stats["ms"]) / n, float(stats["ms_max"]), float(stats["calls"]) / n, float(stats["calls_max"]), int(stats["n"])])


## Saves pictures every `_every` frames while `until` is false (at most `limit` frames) and measures the cost of the frames.
func _film(prefix: String, until: Callable, limit: int) -> void:
	var stats: Dictionary = {"n": 0, "ms": 0.0, "ms_max": 0.0, "calls": 0.0, "calls_max": 0.0}
	var n: int = 0
	var frames: int = 0
	_boss.rig.stat_update_us = 0
	_boss.rig.stat_draw_us = 0
	_boss.field.stat_us = 0
	_fight.stat_us = 0
	while frames < limit:
		await get_tree().process_frame
		frames += 1
		_sample(stats)
		if _every > 0 and frames % _every == 1:
			await _shot("%s_%02d" % [prefix, n])
			n += 1
		if until.call():
			break
	_report(prefix, stats)
	var f: float = maxf(float(frames), 1.0)
	print("     parts per frame: rig update %.2f ms, rig draw %.2f ms, feather field %.2f ms, fight %.2f ms" % [_boss.rig.stat_update_us / 1000.0 / f, _boss.rig.stat_draw_us / 1000.0 / f, _boss.field.stat_us / 1000.0 / f, _fight.stat_us / 1000.0 / f])


func _until_barrier() -> void:
	while not _fight.barrier_done or _fight.mode != MornathFight.Mode.IDLE:
		await get_tree().physics_frame


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_dir)
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	for i: int in 3:
		await get_tree().process_frame
	_player = world._players.get_child(0) as Player
	var spec: Dictionary = (DataRegistry.table("ground").get("arenas", []) as Array)[0] as Dictionary
	var tile: Array = spec.tile as Array
	_origin = Vector2(float(tile[0]), float(tile[1])) * 16.0 + Vector2(8, 8)
	_player.health.floor_value = 1.0
	_player.global_position = _origin + Vector2(20, 240)
	for i: int in 120:
		await get_tree().process_frame
	_player.global_position = _origin + _at
	while _boss == null:
		await get_tree().physics_frame
		if not get_tree().get_nodes_in_group("bosses").is_empty():
			_boss = get_tree().get_nodes_in_group("bosses")[0] as SkyCleaver
	_fight = _boss.fight
	_fight._gap = 99.0
	print("boss is there, waiting for the opening (intro runs)")
	while _boss._intro != null or _fight.mode == MornathFight.Mode.WAIT:
		await get_tree().physics_frame
	if _then.is_finite():
		await _until_barrier()
		_player.global_position = _origin + _then
	var idle_stats: Dictionary = {"n": 0, "ms": 0.0, "ms_max": 0.0, "calls": 0.0, "calls_max": 0.0}
	for i: int in 120:
		await get_tree().process_frame
		_sample(idle_stats)
	_report("idle", idle_stats)
	for act: String in _acts:
		if act != "barrier":
			await _wait_idle()
		else:
			while _fight.mode != MornathFight.Mode.ACTING and not _fight.barrier_done:
				await get_tree().physics_frame
		print("act ", act)
		match act:
			"barrier":
				if not _fight.barrier_done:
					await _film("barrier", func() -> bool: return _fight.barrier_done, 60 * 8)
				else:
					await _shot("barrier_done")
			"rain":
				_fight._rpc_act.rpc(MornathFight.Act.RAIN, 7, Vector2.ZERO, Vector2.ZERO, 0, 1.0)
				await _film("rain", func() -> bool: return _fight.mode == MornathFight.Mode.IDLE, 60 * 14)
			"shot":
				_fight._last_target = int(_player.name)
				_fight._rpc_act.rpc(MornathFight.Act.SHOT, 3, _player.global_position, Vector2.ZERO, int(_player.name), 1.0)
				await _film("shot", func() -> bool: return _fight.mode == MornathFight.Mode.IDLE, 60 * 6)
			"line":
				_fight._last_target = int(_player.name)
				_fight._rpc_act.rpc(MornathFight.Act.LINE, 4, _player.global_position, Vector2.ZERO, int(_player.name), 1.0)
				await _film("line", func() -> bool: return _fight.mode == MornathFight.Mode.IDLE, 60 * 6)
			"chase":
				_fight._last_target = int(_player.name)
				_fight._rpc_act.rpc(MornathFight.Act.CHASE, 5, Vector2.ZERO, Vector2.ZERO, int(_player.name), 1.0)
				await _film("chase", func() -> bool: return _fight.mode == MornathFight.Mode.IDLE and _boss.state == SkyCleaver.State.PERCHED, 60 * 22)
			"blast":
				_player.global_position = _boss.global_position + Vector2(0, 30)
				_fight._rpc_act.rpc(MornathFight.Act.BLAST, 6, Vector2.ZERO, Vector2.ZERO, 0, 1.0)
				await _film("blast", func() -> bool: return _fight.mode == MornathFight.Mode.IDLE, 60 * 5)
			"break":
				_boss._health.take_damage(100000.0, _player.global_position, 0.0, 0)
				await _film("break_a", func() -> bool: return _fight.mode == MornathFight.Mode.REST, 60 * 10)
				var pillar: ArenaPillar = _boss.pillar(1)
				_player.global_position = pillar.global_position + Vector2(0, 26)
				var hits: int = 0
				while not pillar.broken and hits < 40:
					pillar.take_hit(9.0, _player.global_position)
					hits += 1
					for i: int in 8:
						await get_tree().process_frame
					if hits % 3 == 0:
						await _shot("break_b_%02d" % hits)
				await _film("break_c", func() -> bool: return _fight.mode == MornathFight.Mode.DOWNED, 60 * 4)
				await get_tree().create_timer(0.8).timeout
				await _shot("downed")
				_boss._hurtbox.take_hit(5.0, _player.global_position, 0.0, 0)
				await _film("finisher", func() -> bool: return _fight.mode == MornathFight.Mode.IDLE and _boss.state == SkyCleaver.State.PERCHED, 60 * 22) ## includes the transition into phase 2
			"pincer":
				_fight._last_target = int(_player.name)
				_fight._rpc_act.rpc(MornathFight.Act.PINCER, 8, _player.global_position, Vector2.ZERO, int(_player.name), 1.0)
				await _film("pincer", func() -> bool: return _fight.mode == MornathFight.Mode.IDLE, 60 * 8)
			"hands":
				_fight._rpc_act.rpc(MornathFight.Act.HANDS, 9, Vector2.ZERO, Vector2.ZERO, 0, 1.0)
				await _film("hands", func() -> bool: return _fight.mode == MornathFight.Mode.IDLE, 60 * 8)
			"cage":
				_fight._last_target = int(_player.name)
				_fight._rpc_act.rpc(MornathFight.Act.CAGE, 10, _player.global_position, Vector2.ZERO, int(_player.name), 1.0)
				await _film("cage", func() -> bool: return _fight.mode == MornathFight.Mode.IDLE, 60 * 8)
			"rain2":
				_fight._rpc_act.rpc(MornathFight.Act.RAIN, 11, Vector2.ZERO, Vector2.ZERO, 0, 1.0)
				await _film("rain2", func() -> bool: return _fight.mode == MornathFight.Mode.IDLE, 60 * 14)
			"judge":
				_boss._health.take_damage(100000.0, _player.global_position, 0.0, 0)
				await _film("judge", func() -> bool: return _fight.mode == MornathFight.Mode.JUDGEMENT, 60 * 14)
				await _film("judge_run", func() -> bool: return _fight.judge_elapsed() > 12.0, 60 * 14)
	print("health ", _boss.health_now(), " phase ", _fight.phase)
	get_tree().quit(0)
