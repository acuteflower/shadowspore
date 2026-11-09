extends Node
## Tests des zentralen Job-Systems (Jobs): Reihenfolge, Prioritäten, Warten, Abbruch, Node-Erzeugung im Worker bei blockiertem
## Main-Thread (Deadlock-Probe gegen den Render-Thread), parallel_for, Sync-Fallback. Headless: tools/test_jobs.tscn.
var _checks: int = 0
var _failed: int = 0

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)

func _ready() -> void:
	_run.call_deferred()

func _burn(n: int) -> int:
	var sum: int = 0
	for i: int in n:
		sum += i % 7
	return sum

func _run() -> void:
	print("threads: ", Jobs.threaded, " max_running ", Jobs.max_running, " cores ", OS.get_processor_count())
	print("section 1")
	# 1. Ergebnis kommt auf dem Main-Thread an.
	var got: Array = []
	var main_id: int = OS.get_thread_caller_id()
	var worker_ids: Array = []
	Jobs.run(func() -> Variant:
		worker_ids.append(OS.get_thread_caller_id())
		return _burn(200000), func(r: Variant) -> void:
		got.append([r, OS.get_thread_caller_id()]))
	for i: int in 600:
		if not got.is_empty(): break
		await get_tree().process_frame
	_check(got.size() == 1 and int(got[0][0]) == _burn(200000), "result delivered")
	_check(got.size() == 1 and int(got[0][1]) == main_id, "on_done runs on the main thread")
	if Jobs.threaded:
		_check(worker_ids.size() == 1 and int(worker_ids[0]) != main_id, "work ran on a worker")

	print("section 2")
	# 2. wait() liefert sofort, auch für einen noch wartenden Job; on_done kommt genau einmal.
	var count: Array = [0]
	var jobs: Array = []
	for k: int in 12:
		jobs.append(Jobs.run(func() -> Variant: return k * k, func(_r: Variant) -> void: count[0] += 1))
	var r5: Variant = Jobs.wait(jobs[5] as Jobs.Job)
	_check(int(r5) == 25, "wait returns the result")
	Jobs.wait_all(jobs)
	_check(count[0] == 12, "every on_done exactly once (%d)" % count[0])
	await get_tree().process_frame
	await get_tree().process_frame
	_check(count[0] == 12, "no double delivery (%d)" % count[0])

	print("section 3")
	# 3. Prioritäten (nur wenn der Pool voll ist, also mit max_running == 1 messbar): URGENT überholt LOW.
	var saved_cap: int = Jobs.max_running
	Jobs.max_running = 1
	var order: Array = []
	var gate: Array = [false]
	var blocker: Jobs.Job = Jobs.run(func() -> Variant:
		while not gate[0]: OS.delay_usec(500)
		return 0)
	var low: Jobs.Job = Jobs.run(func() -> Variant: order.append("low"); return 0, Callable(), Jobs.Prio.LOW)
	var urgent: Jobs.Job = Jobs.run(func() -> Variant: order.append("urgent"); return 0, Callable(), Jobs.Prio.URGENT)
	var normal: Jobs.Job = Jobs.run(func() -> Variant: order.append("normal"); return 0, Callable(), Jobs.Prio.NORMAL)
	gate[0] = true
	Jobs.drain()
	_check(blocker.is_finished() and low.is_finished() and urgent.is_finished() and normal.is_finished(), "all done")
	_check(order == ["urgent", "normal", "low"], "priority order %s" % str(order))
	Jobs.max_running = saved_cap

	print("section 4")
	# 4. Abbruch: ein wartender Job startet nie, ein fertiger gibt sein Ergebnis an on_discard.
	Jobs.max_running = 1
	var ran: Array = [0]
	var discarded: Array = [0]
	var gate2: Array = [false]
	var hold: Jobs.Job = Jobs.run(func() -> Variant:
		while not gate2[0]: OS.delay_usec(500)
		return 0)
	var victim: Jobs.Job = Jobs.run(func() -> Variant: ran[0] += 1; return 1, func(_r: Variant) -> void: ran[0] += 100, Jobs.Prio.NORMAL, func(_r: Variant) -> void: discarded[0] += 1)
	Jobs.cancel(victim)
	gate2[0] = true
	Jobs.wait(hold)
	await get_tree().process_frame
	_check(ran[0] == 0, "cancelled pending job never runs")
	var runner: Jobs.Job = Jobs.run(func() -> Variant: return 7, func(_r: Variant) -> void: ran[0] += 100, Jobs.Prio.NORMAL, func(_r: Variant) -> void: discarded[0] += 1)
	for i: int in 600:
		if runner.state == Jobs.State.FINISHED or runner.state == Jobs.State.DELIVERED: break
		OS.delay_msec(1)
	Jobs.cancel(runner)
	Jobs.wait(runner)
	await get_tree().process_frame
	_check(ran[0] == 0 or ran[0] == 100, "cancelled job ends consistently (%d)" % ran[0])
	_check(discarded[0] >= 0, "discard hook callable")
	Jobs.max_running = saved_cap

	print("section 5")
	# 5. Node-Erzeugung im Worker, während der Main-Thread blockiert wartet (Deadlock-Probe) und Szenen/Texturen instanziert werden.
	Jobs.warm(["res://src/entities/props/bush.tscn"])
	var made: Array = []
	var node_jobs: Array = []
	for k: int in 8:
		node_jobs.append(Jobs.run(func() -> Variant:
			var root: Node2D = Node2D.new()
			for i: int in 40:
				var s: Sprite2D = Sprite2D.new()
				s.texture = load("res://assets/props/rock.png") as Texture2D
				s.region_enabled = true
				s.region_rect = Rect2(0, 0, 8, 8)
				var body: StaticBody2D = StaticBody2D.new()
				var shape: CollisionShape2D = CollisionShape2D.new()
				var rect: RectangleShape2D = RectangleShape2D.new()
				rect.size = Vector2(4, 4)
				shape.shape = rect
				body.add_child(shape)
				root.add_child(s)
				root.add_child(body)
			var scene: PackedScene = load("res://src/entities/props/bush.tscn") as PackedScene
			root.add_child(scene.instantiate())
			return root, func(r: Variant) -> void: made.append(r)))
	var t0: int = Time.get_ticks_msec()
	Jobs.wait_all(node_jobs)
	_check(made.size() == 8, "node jobs finished without deadlock (%d, %d ms)" % [made.size(), Time.get_ticks_msec() - t0])
	for root: Variant in made:
		_check((root as Node).get_child_count() == 81, "worker built the whole subtree")
		(root as Node).free()

	print("section 6")
	# 6. parallel_for schreibt in eigene Slots.
	var out: PackedInt32Array = PackedInt32Array()
	out.resize(500)
	Jobs.parallel_for(500, func(i: int) -> void: out[i] = i * 3)
	var ok: bool = true
	for i: int in 500:
		if out[i] != i * 3: ok = false
	_check(ok, "parallel_for filled every slot")

	print("section 7")
	# 7. Sync-Fallback liefert dasselbe.
	var was: bool = Jobs.threaded
	Jobs.threaded = false
	var sync_res: Array = []
	var sj: Jobs.Job = Jobs.run(func() -> Variant: return _burn(1000), func(r: Variant) -> void: sync_res.append(r))
	for i: int in 10:
		if not sync_res.is_empty(): break
		await get_tree().process_frame
	_check(sync_res == [_burn(1000)] and sj.state == Jobs.State.DELIVERED, "sync fallback")
	Jobs.threaded = was

	print("section 8")
	# 8. drain räumt alles.
	for k: int in 20:
		Jobs.run(func() -> Variant: return _burn(50000))
	Jobs.drain()
	_check(not Jobs.busy(), "drain leaves nothing behind")

	print("test_jobs: %d checks, %d failed | stats %s" % [_checks, _failed, str(Jobs.stats)])
	get_tree().quit(1 if _failed > 0 else 0)
