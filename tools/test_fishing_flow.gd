extends Node
## Fishing end to end on one machine (host = owner): cast, drift, nibble, bite, strike, fight, landing; early and late strikes,
## bait, rod swap, invalid targets, the book. Uses the real river data and the real player; time is driven by hand.
const BOOK: String = "user://fish_book_test_only.json"
const DT: float = 1.0 / 60.0
var failures: int = 0
var checks: int = 0
var rivers: WorldRivers
var player: Player
var f: FishingComponent
var caught_signals: Array[Dictionary] = []
var fx_log: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)


func tick(seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		f._host_tick(DT)
		t += DT


func until(pred: Callable, limit: float) -> bool:
	var t: float = 0.0
	while t < limit:
		if pred.call():
			return true
		f._host_tick(DT)
		t += DT
	return pred.call()


## A standing point on the bank and a target in open water in front of it.
func find_spot() -> Dictionary:
	var data: Dictionary = DataRegistry.table("rivers_baked")
	for ford: Array in data["fords"]:
		var centre: Vector2 = Vector2(float(ford[0]), float(ford[1]))
		for a: int in 16:
			var dir: Vector2 = Vector2.from_angle(float(a) / 16.0 * TAU)
			for r: int in range(20, 160, 2):
				var stand: Vector2 = centre + dir * float(r)
				var x: float = rivers.field_at(stand).x
				if x >= 3.0 and x <= 9.0:
					for reach: int in range(36, 120, 6):
						var target: Vector2 = stand - dir * float(reach)
						if rivers.field_at(target).x <= -12.0 and rivers.field_at(target + Vector2(10, 0)).x <= -8.0:
							return {"stand": stand, "target": target}
					break
	return {}


func stand_at(spot: Dictionary) -> void:
	player.global_position = spot["stand"] as Vector2
	player.velocity = Vector2.ZERO


func select_rod() -> void:
	for i: int in InventoryComponent.HOTBAR_SIZE:
		if not player.inventory.slots[i].is_empty() and String(player.inventory.slots[i]["id"]) == "rod_basic":
			player.inventory.select(i)
	player._on_inventory_changed() ## the player node does this itself once its HUD is bound


func cast(spot: Dictionary, bait: String = "") -> void:
	f._host_request("cast", [spot["target"], bait, "cork"])


func fight_perfectly() -> void:
	var guard: float = 0.0
	while f.state == FishingComponent.S.DRILL and guard < 90.0:
		f._give = 1.0 if f.phase == "flee" else 0.0
		f._reel = f.phase == "tire" and not f.tell
		f._host_tick(DT)
		guard += DT


func _run() -> void:
	TimeManager.time_of_day = 0.5
	rivers = WorldRivers.new()
	add_child(rivers)
	player = (load("res://src/entities/player/player.tscn") as PackedScene).instantiate() as Player
	player.name = "1" ## a player node is named after its owner's peer id (that is its authority)
	add_child(player)
	await get_tree().physics_frame
	f = player.fishing
	check(f != null, "player owns a FishingComponent")
	f.set_physics_process(false)
	f.book = FishBook.new(BOOK)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BOOK))
	f.book = FishBook.new(BOOK)
	f.caught.connect(func(species: String, length: int, is_record: bool, prime: bool) -> void: caught_signals.append({"s": species, "l": length, "r": is_record, "p": prime}))
	f.fx.connect(func(kind: String, _pos: Vector2, _data: Dictionary) -> void: fx_log.append(kind))
	f._rng.seed = 12
	var spot: Dictionary = find_spot()
	check(not spot.is_empty(), "a bank with open water in front exists in the baked rivers")
	if spot.is_empty():
		_finish()
		return
	stand_at(spot)
	await get_tree().physics_frame
	check(f.stand_ok(), "the bank spot is a valid standing place")
	player.inventory.give("rod_basic", 1)
	select_rod()
	await get_tree().physics_frame
	check(f.rod_active(), "the rod is the item in her hand")
	check(not player.attack.can_attack(), "a rod cannot swing")
	check(player.attack.always_drawn, "a rod is never put away")

	# invalid casts
	f._host_request("cast", [spot["stand"], "", "cork"])
	check(f.state == FishingComponent.S.IDLE, "cannot cast onto the bank")
	f._host_request("cast", [(spot["stand"] as Vector2) + Vector2(900, 0), "", "cork"])
	check(f.state == FishingComponent.S.IDLE, "cannot cast out of reach")
	player.inventory.select(7)
	player._on_inventory_changed()
	await get_tree().physics_frame
	cast(spot)
	check(f.state == FishingComponent.S.IDLE, "cannot cast without the rod in hand")
	select_rod()
	await get_tree().physics_frame

	# body clips: the frame, the rig points and the rod pose follow the clip; walking cancels only the ready clip
	f.anim = "cast"
	f.anim_time = 0.2
	var body: Dictionary = f.body_frame(2, false)
	check(not body.is_empty() and int(body["frame"]) >= 2 * int(body["cols"]) and int(body["frame"]) < 3 * int(body["cols"]), "cast: a frame of view 2 (%s)" % [body.get("frame", -1)])
	check((body["rod"] as Vector3).is_finite() and (body["hand"] as Vector2).length() > 1.0, "cast: rod pose and hand point exist")
	f.anim = "ready"
	check(f.body_frame(0, true).is_empty() and not f.body_frame(0, false).is_empty(), "ready: walking leaves the clip, standing keeps it")
	f.anim = "flee"
	check(f.body_frame(5, true).is_empty() == false and f.animating(), "flee: locks her in place and plays while walking input is ignored")
	f.anim = ""
	check(f.body_frame(0, false).is_empty() and not f.animating(), "no clip, the normal sheets")
	var cast_clock_check: float = 0.0
	cast(spot)
	check(f.locks_movement(), "a cast holds her still")
	until(func() -> bool: return f.state == FishingComponent.S.DRIFTING, 2.0)
	f._host_request("reel", [])

	# a full catch
	cast(spot)
	check(f.state == FishingComponent.S.CASTING, "a valid cast starts")
	check(until(func() -> bool: return f.state == FishingComponent.S.DRIFTING, 2.0), "the float lands and drifts")
	check(fx_log.has("splash"), "the landing splashes")
	var start: Vector2 = f.bobber
	tick(3.0)
	check(f.bobber.distance_to(start) > 0.5 or f._flow(f.bobber).length() < 0.05, "the current carries the float")
	check(f._field(f.bobber).x < -3.0, "the float stays on the water")
	check(until(func() -> bool: return f.state == FishingComponent.S.NIBBLE or f.state == FishingComponent.S.BITE, 40.0), "a fish comes (%s)" % [f._bite_species])
	check(fx_log.has("approach"), "the shadow approached before the bite")
	check(f.species != "", "the species is known to the shadow")
	check(until(func() -> bool: return f.state == FishingComponent.S.BITE, 8.0), "the nibbles become a bite")
	check(fx_log.has("tap") and fx_log.has("bite"), "taps and bite effects fired")
	var id: String = f.species
	var item: String = String((FishingRules.species_table()[id] as Dictionary)["item"])
	f._host_request("strike", [])
	check(f.state == FishingComponent.S.DRILL, "a strike in the window hooks the fish")
	fight_perfectly()
	check(f.state == FishingComponent.S.IDLE, "the fight ends")
	check(player.inventory.count_item(item) == 1, "the landed fish is in the bag (%s)" % item)
	check(caught_signals.size() == 1 and bool(caught_signals[0]["r"]), "the owner gets the card, first catch is a record")
	check(f.book.known(id) and int((f.book.species[id] as Dictionary)["caught"]) == 1, "the book remembers it")
	var again: FishBook = FishBook.new(BOOK)
	check(again.known(id) and int((again.species[id] as Dictionary)["best"]) == int(caught_signals[0]["l"]), "the book is saved and reloads")

	# early and late strikes
	for mode: String in ["early", "late"]:
		fx_log.clear()
		cast(spot)
		check(until(func() -> bool: return f.state == FishingComponent.S.DRIFTING, 2.0), mode + ": drifting")
		check(until(func() -> bool: return f.state == FishingComponent.S.NIBBLE, 60.0), mode + ": nibbling")
		if mode == "early":
			f._host_request("strike", [])
		else:
			check(until(func() -> bool: return f.state == FishingComponent.S.BITE, 8.0), "late: bite")
			tick(2.0)
		check(f.state == FishingComponent.S.IDLE, mode + " strike loses the fish")
		check(fx_log.has("lost"), mode + ": the loss is shown")

	# strike while drifting is not a strike; reel in
	cast(spot)
	until(func() -> bool: return f.state == FishingComponent.S.DRIFTING, 2.0)
	f._host_request("strike", [])
	check(f.state == FishingComponent.S.DRIFTING, "a click during the drift is no strike")
	f._host_request("reel", [])
	check(f.state == FishingComponent.S.IDLE, "reeling in ends the cast")

	# bait is used up
	player.inventory.give("brook_mint", 2)
	cast(spot, "brook_mint")
	check(player.inventory.count_item("brook_mint") == 1, "a cast uses one bait")
	f._host_request("reel", [])

	# rod swap abandons the line
	cast(spot)
	until(func() -> bool: return f.state == FishingComponent.S.DRIFTING, 2.0)
	player.inventory.select(7)
	tick(0.1)
	check(f.state == FishingComponent.S.IDLE, "swapping the rod away ends the line")
	select_rod()
	await get_tree().physics_frame

	# walking away breaks the line
	cast(spot)
	until(func() -> bool: return f.state == FishingComponent.S.DRIFTING, 2.0)
	player.global_position += Vector2(-400, 0)
	tick(0.1)
	check(f.state == FishingComponent.S.IDLE, "walking far away ends the line")
	stand_at(spot)

	# damage drops the line
	cast(spot)
	until(func() -> bool: return f.state == FishingComponent.S.DRIFTING, 2.0)
	player.health.damaged.emit(1.0, Vector2.ZERO, 0.0)
	check(f.state == FishingComponent.S.IDLE, "being hurt drops the line")

	# the landing net: a friend under the fish makes it a prime catch and the line cannot break
	var helper: Player = (load("res://src/entities/player/player.tscn") as PackedScene).instantiate() as Player
	helper.name = "2"
	add_child(helper)
	await get_tree().physics_frame
	var before_count: int = 0
	cast(spot)
	check(until(func() -> bool: return f.state == FishingComponent.S.BITE, 120.0), "net: a fish bites")
	var net_item: String = String((FishingRules.species_table()[f.species] as Dictionary)["item"])
	before_count = player.inventory.count_item(net_item)
	f._host_request("strike", [])
	check(f.state == FishingComponent.S.DRILL, "net: hooked")
	check(not f._host_net(player), "net: the angler cannot net their own fish")
	check(not f._host_net(null), "net: no helper, no net")
	f._drill["dist"] = 120.0
	f.dist = 120.0
	helper.global_position = f.bobber
	check(not f._host_net(helper), "net: the fish is still far from the bank")
	f._drill["dist"] = 40.0
	f.dist = 40.0
	helper.global_position = f.bobber + Vector2(300, 0)
	check(not f._host_net(helper), "net: a helper far away cannot reach it")
	helper.global_position = f.bobber + Vector2(6, 0)
	check(f._host_net(helper), "net: a friend in reach holds the net")
	check(f.netted and not f._host_net(helper), "net: it is netted once")
	var peak: float = 0.0
	var guard: float = 0.0
	while f.state == FishingComponent.S.DRILL and guard < 30.0:
		f._give = 0.0
		f._reel = true ## the worst play: yanking, the net still protects the line
		f._host_tick(DT)
		peak = maxf(peak, f.tension)
		guard += DT
	check(f.state == FishingComponent.S.IDLE and peak <= 0.81, "net: the line never exceeds the cap while netted (peak %.2f)" % peak)
	check(player.inventory.count_item(net_item) == before_count + 2, "net: a prime catch gives two fish")
	check(not caught_signals.is_empty() and bool(caught_signals[caught_signals.size() - 1]["p"]), "net: the card says prime")
	check(not f.netted or f.state == FishingComponent.S.IDLE, "net: state resets")
	helper.queue_free()

	# the dev kit and the teleport to a bank (pause menu, ENTWICKLER -> ANGELN)
	var bank: Vector2 = FishingComponent.nearest_bank(get_tree(), spot["stand"] as Vector2 + Vector2(400, 400))
	check(bank != Vector2.INF and rivers.field_at(bank).x >= 3.0 and rivers.field_at(bank).x <= 9.0, "dev: the nearest bank is a real bank")
	var hud: Node = player.get("_hud") as Node
	check(hud != null and hud.has_node("PauseMenu"), "dev: the pause menu exists")
	if hud != null and hud.has_node("PauseMenu"):
		var berries_before: int = player.inventory.count_item("dusk_berry")
		var splinters_before: int = player.inventory.count_item("void_splinter")
		hud.get_node("PauseMenu")._run_action("fish_kit")
		check(player.inventory.count_item("dusk_berry") == berries_before + 10 and player.inventory.count_item("void_splinter") == splinters_before + 3, "dev: the kit adds the baits")
		check(player.inventory.count_item("rod_basic") == 1, "dev: the kit never gives a second rod")
		check(String(player.inventory.active_stack().get("id", "")) == "rod_basic", "dev: the kit selects the rod")

	# the fight happens IN the water: every species, three ways of playing, a few places along the rivers
	var worst_jump: float = 0.0
	var off_water: int = 0
	var fights: int = 0
	var landed_n: int = 0
	var max_dist: float = 0.0
	var sharpest: float = 0.0
	var last_step: Vector2 = Vector2.ZERO
	var trace: Array = []
	for species_id: String in FishingRules.species_table():
		for mode: int in 3:
			f._host_end("", "")
			cast(spot)
			until(func() -> bool: return f.state == FishingComponent.S.DRIFTING, 2.0)
			f.species = species_id
			f._set_state(FishingComponent.S.BITE)
			f._window = 5.0
			f._host_request("strike", [])
			if f.state != FishingComponent.S.DRILL:
				continue
			fights += 1
			last_step = Vector2.ZERO
			var elapsed: float = 0.0
			while f.state == FishingComponent.S.DRILL and elapsed < 80.0:
				var fleeing: bool = f.phase == "flee"
				f._give = (1.0 if fleeing else 0.0) if mode == 0 else (0.0 if mode == 1 else 1.0)
				f._reel = (not fleeing and not f.tell) if mode == 0 else (mode == 1)
				var before: Vector2 = f.bobber
				f._host_tick(DT)
				if f.state == FishingComponent.S.DRILL:
					var moved: Vector2 = f.bobber - before
					sharpest = maxf(sharpest, (moved - last_step).length()) ## how much the velocity changes in one tick: no kinks
					last_step = moved
					if false:
						print("    t=%.1f phase=%s pos=%s dist=%.0f vel=%.1f reel=%s pulldir=%s cell=%s val=%s field=%.1f" % [elapsed, f.phase, f.bobber, f.dist, f._fvel.length(), f._reel, f._pull_dir(f.bobber), f._cell_of(f.bobber), f._pull[f._cell_of(f.bobber).y * 81 + f._cell_of(f.bobber).x], f._field(f.bobber).x])
					if mode == 0 and (species_id == "abyss_pike" or species_id == "moon_trout"):
						trace.append([species_id, f.bobber.x, f.bobber.y, f.feet().x, f.feet().y])
					worst_jump = maxf(worst_jump, f.bobber.distance_to(before))
					if f._field(f.bobber).x > -0.5:
						off_water += 1
					max_dist = maxf(max_dist, f.dist)
				elapsed += DT
			if f.state == FishingComponent.S.IDLE and elapsed < 80.0 and player.inventory.count_item(String((FishingRules.species_table()[species_id] as Dictionary)["item"])) > 0:
				landed_n += 1
	check(fights >= 18, "water fights: all hooked (%d)" % fights)
	check(off_water == 0, "water fights: the fish never leaves the water (%d ticks on land)" % off_water)
	check(worst_jump < 3.2, "water fights: no teleporting, at most %.2f px per tick" % worst_jump)
	check(max_dist < 260.0, "water fights: the fish stays within reach of the line (%.0f)" % max_dist)
	check(sharpest < 1.6, "water fights: no kinks, the step changes by at most %.2f px per tick" % sharpest)
	var dump: String = OS.get_environment("FISH_TRACE")
	if dump != "" and not trace.is_empty():
		var field: Array = []
		var c: Vector2 = Vector2((trace[0] as Array)[3], (trace[0] as Array)[4])
		for gy: int in range(-100, 101, 4):
			for gx: int in range(-160, 161, 4):
				field.append(rivers.field_at(c + Vector2(gx, gy)).x)
		var file: FileAccess = FileAccess.open(dump, FileAccess.WRITE)
		file.store_string(JSON.stringify({"c": [c.x, c.y], "trace": trace, "field": field}))
		file.close()
	print("water fights: %d fights, %d landed, fastest %.0f px/s, farthest %.0f px" % [fights, landed_n, worst_jump * 60.0, max_dist])
	f._host_end("", "")
	player.inventory.clear_all()
	player.inventory.give("rod_basic", 1)
	select_rod()

	# the full bag releases the fish
	cast(spot)
	until(func() -> bool: return f.state == FishingComponent.S.BITE, 80.0)
	var full_item: String = String((FishingRules.species_table()[f.species] as Dictionary)["item"])
	for i: int in InventoryComponent.SIZE:
		if player.inventory.slots[i].is_empty() or String(player.inventory.slots[i]["id"]) == full_item: ## fish stacks count as room too
			player.inventory.slots[i] = {"id": "stone", "count": 99}
	check(not player.inventory.has_room(full_item), "bag is full for the test")
	f._host_request("strike", [])
	check(f.state == FishingComponent.S.IDLE, "a full bag releases the fish instead of hooking it")

	# night turmoil reaches the director
	var director: NightDirector = NightDirector.new()
	var before: float = director.lure
	director.stir(2.0)
	check(director.lure > before, "turmoil raises the lure")
	director.free()

	_finish()


func _finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BOOK))
	print("Fishing flow: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
