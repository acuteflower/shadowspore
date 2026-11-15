extends Node
## Hallgrat's people, step 1 (docs/hallgrat_bewohner_konzept.md 11): the walking net (`HallgratWays`) and the daily plans (`HallgratPeople`).
## Checks that the net is built and the same twice, that every spot resolves onto it and every route of the plans exists, stays on free
## cells and only changes height on ramps, stairs and rock steps, that positions are a pure function of the clock and never jump, that the
## night keeps everyone in and the day out, and that the figures appear in the real world when the player comes into town.
## `Godot [--headless | --rendering-driver opengl3] --path . --fixed-fps 60 tools/test_hallgrat_people.tscn [-- --dir=/abs/folder]`
## -> `HALLGRAT PEOPLE OK`

var _ok: bool = true
var _checks: int = 0
var _dir: String = ""


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_ok = false
		print("HALLGRAT PEOPLE FAILED: ", what)


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			_dir = arg.trim_prefix("--dir=")
	_run.call_deferred()


func _run() -> void:
	var relief: Relief = Relief.new()
	Terrain.relief = relief
	var started: int = Time.get_ticks_msec()
	var people: HallgratPeople = HallgratPeople.new()
	people.setup()
	add_child(people)
	people.build_now()
	print("net and routes built in %d ms" % (Time.get_ticks_msec() - started))
	var w: HallgratWays = people.ways
	_check(w != null and w.cols > 100 and w.rows > 100, "the net covers the town")
	var open: int = 0
	for c: float in w.cost:
		if c > 0.0:
			open += 1
	_check(open > w.cost.size() / 5, "a fair share of the town is walkable (%d of %d)" % [open, w.cost.size()])

	# the same twice (every peer builds its own)
	var again: HallgratWays = HallgratWays.build(relief, DataRegistry.table("hallgrat"), DataRegistry.table("hallgrat_art"), DataRegistry.table("ground_baked"))
	_check(again.cost == w.cost, "the net is the same when built twice")

	# no square or garden of the town is walled off: every place is reachable from the east gate
	var start: Vector2i = w.cell_of(w.snap(Vector2(2988, 5470)))
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(w.cols * w.rows)
	var stack: Array[Vector2i] = [start]
	seen[start.y * w.cols + start.x] = 1
	while not stack.is_empty():
		var c0: Vector2i = stack.pop_back()
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = c0 + d
			if w.inside(nb) and seen[nb.y * w.cols + nb.x] == 0 and w.cost[nb.y * w.cols + nb.x] > 0.0:
				seen[nb.y * w.cols + nb.x] = 1
				stack.append(nb)
	var reached: int = 0
	for v: int in seen:
		reached += v
	_check(reached > open * 0.93, "almost all free ground hangs together (%d of %d cells)" % [reached, open])
	for place: Dictionary in DataRegistry.table("hallgrat").get("places", []) as Array:
		if not ["square", "yard", "gardens", "garden", "lane"].has(String(place.get("kind", ""))):
			continue
		var at: Vector2 = w.snap(HallgratPeople.spot_raw({"place": String(place.id)}))
		var cell: Vector2i = w.cell_of(at)
		_check(at.is_finite() and seen[cell.y * w.cols + cell.x] == 1, "the place %s is reachable from the east gate" % String(place.id))

	# spots and routes
	var level_changes: int = 0
	for id: String in people.plans:
		var plan: Dictionary = people.plans[id] as Dictionary
		for spot_id: String in plan.spots:
			var pos: Vector2 = ((plan.spots as Dictionary)[spot_id] as Dictionary).pos as Vector2
			_check(pos.is_finite() and w.open_at(pos), "%s: spot %s lies on the net" % [id, spot_id])
		var schedule: Array = plan.schedule as Array
		for k: int in schedule.size():
			var a: Vector2 = ((plan.spots as Dictionary)[String((schedule[(k - 1 + schedule.size()) % schedule.size()] as Array)[1])] as Dictionary).pos as Vector2
			var b: Vector2 = ((plan.spots as Dictionary)[String((schedule[k] as Array)[1])] as Dictionary).pos as Vector2
			var route: PackedVector2Array = w.route(a, b)
			_check(route.size() >= 1, "%s: a way to %s" % [id, String((schedule[k] as Array)[1])])
			if route.is_empty():
				continue
			_check(again.route(a, b) == route, "%s: the way to %s is the same on another net" % [id, String((schedule[k] as Array)[1])])
			var bad: int = 0
			var gap: float = 0.0
			var bad_level: int = 0
			for i: int in route.size():
				if not w.open_at(route[i]):
					bad += 1
				if i > 0:
					gap = maxf(gap, route[i - 1].distance_to(route[i]))
					var t0: Vector2i = Vector2i((route[i - 1] / 16.0).floor())
					var t1: Vector2i = Vector2i((route[i] / 16.0).floor())
					if relief.level(t0.x, t0.y) != relief.level(t1.x, t1.y):
						level_changes += 1
						if relief.kind(t0.x, t0.y) < Relief.RAMP and relief.kind(t1.x, t1.y) < Relief.RAMP:
							bad_level += 1
			_check(bad == 0, "%s: the way to %s stays on free cells (%d off)" % [id, String((schedule[k] as Array)[1]), bad])
			_check(gap <= HallgratWays.STEP + 0.5, "%s: the way to %s has no gaps (%.1f px)" % [id, String((schedule[k] as Array)[1]), gap])
			_check(bad_level == 0, "%s: the way to %s climbs only on ramps and stairs (%d)" % [id, String((schedule[k] as Array)[1]), bad_level])
	_check(level_changes > 0, "some ways climb between the town's levels")
	print("routes cached: %d, level changes walked: %d" % [w.cached_routes(), level_changes])

	# positions: a pure function of the clock, no jumps
	var dt: float = 1.0 / TimeManager.DAY_LENGTH_SEC
	for id: String in people.plans:
		var last: Dictionary = {}
		var worst: float = 0.0
		var walked: int = 0
		var t: float = 0.0
		while t < 1.0:
			var s: Dictionary = people.state_at(id, t)
			if bool(s.moving):
				walked += 1
			if not last.is_empty() and not bool(last.inside) and not bool(s.inside):
				worst = maxf(worst, (last.pos as Vector2).distance_to(s.pos as Vector2))
			last = s
			t += dt
		_check(worst < 120.0, "%s never jumps (largest step in a second %.1f px)" % [id, worst])
		_check(walked > 10, "%s walks during the day (%d s)" % [id, walked])
		_check(people.state_at(id, 0.437) == people.state_at(id, 0.437), "%s: the same time gives the same place" % id)
		var watch: bool = bool(((people.plans[id] as Dictionary).spec as Dictionary).get("night", false))
		_check(bool(people.state_at(id, 0.05).inside) != watch, "%s is %s in the deep night" % [id, "out on watch" if watch else "indoors"])
		_check(bool(people.state_at(id, 0.5).inside) == watch, "%s is %s at noon" % [id, "asleep" if watch else "out"])
	people.queue_free()

	# step 3: the townsfolk
	var extras: Dictionary = HallgratExtras.plans(DataRegistry.table("hallgrat_people"))
	_check(extras.size() == int((DataRegistry.table("hallgrat_people").extras as Dictionary).count), "the town has its %d townsfolk" % extras.size())
	_check(extras == HallgratExtras.plans(DataRegistry.table("hallgrat_people")), "the townsfolk are the same on every peer")
	var erig: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/hallgrat_extra_rig.json")) as Dictionary
	var eclips: Dictionary = erig.get("clips", {}) as Dictionary
	var roles_seen: Dictionary = {}
	var noon: Array[Vector2] = []
	for id: String in extras:
		var e: Dictionary = extras[id] as Dictionary
		roles_seen[String(e.role)] = true
		_check(ResourceLoader.exists("res://assets/characters/hallgrat_extra_%d.png" % int(e.kind)), "%s: the sheet of kind %d exists" % [id, int(e.kind)])
		for spot_id: String in (people.plans[id] as Dictionary).spots:
			_check(eclips.has(String((((people.plans[id] as Dictionary).spots as Dictionary)[spot_id] as Dictionary).clip)), "%s: the clip of %s is drawn" % [id, spot_id])
		var st: Dictionary = people.state_at(id, 0.5)
		if not bool(st.inside):
			noon.append(st.pos as Vector2)
	_check(roles_seen.size() >= 6, "the townsfolk have many roles (%d)" % roles_seen.size())
	var crowded: int = 0
	for a: int in noon.size():
		for b: int in range(a + 1, noon.size()):
			if noon[a].distance_to(noon[b]) < 6.0:
				crowded += 1
				print("  close at noon: ", noon[a], " ", noon[b])
	_check(crowded <= 2, "at noon the townsfolk do not stand in each other (%d pairs closer than 6 px)" % crowded)
	_check(noon.size() >= 16, "most townsfolk are out at noon (%d)" % noon.size())

	# step 4: the lamp round
	var lamps: Dictionary = HallgratPeople.lamp_times
	_check(lamps.size() >= 20, "Pim lights the street lanterns (%d of 24)" % lamps.size())
	var first: float = 1.0
	var last: float = 0.0
	for key: Vector2i in lamps:
		first = minf(first, float(lamps[key]))
		last = maxf(last, float(lamps[key]))
	_check(first >= 0.79 and last <= 0.93, "the round runs from the bell into the night (%.3f .. %.3f)" % [first, last])
	var some: Vector2 = Vector2(lamps.keys()[lamps.size() / 2] as Vector2i)
	var at_lit: float = float(lamps[Vector2i(some)])
	_check(not HallgratPeople.lamp_lit(some, at_lit - 0.004) and HallgratPeople.lamp_lit(some, at_lit + 0.004), "a lantern lights when Pim reaches it")
	_check(HallgratPeople.lamp_lit(some, 0.1) and not HallgratPeople.lamp_lit(some, 0.5), "it burns through the night and is out by day")
	var pim_at: Dictionary = people.state_at("pim", at_lit + 0.0005)
	_check((pim_at.pos as Vector2).distance_to(some) < 40.0, "Pim stands at the lantern when it lights (%.0f px)" % (pim_at.pos as Vector2).distance_to(some))
	# step 4: the evening at the inn
	var inn: Vector2 = HallgratPeople.spot_raw({"building": "gasthaus"})
	var evening: int = 0
	for id: String in people.plans:
		var st4: Dictionary = people.state_at(id, 0.86)
		if not bool(st4.inside) and (st4.pos as Vector2).distance_to(inn) < 110.0:
			evening += 1
	_check(evening >= 5, "the inn has its evening crowd (%d)" % evening)
	# step 4: meeting places
	var pairs: int = 0
	var t4: float = 0.3
	while t4 < 0.78:
		var views: Dictionary = {}
		for id: String in people.plans:
			views[id] = people.state_at(id, t4)
		people._meet(views, t4)
		for id: String in views:
			if (views[id] as Dictionary).has("partner"):
				pairs += 1
		t4 += 0.02
	_check(pairs > 10, "people meet and talk over the day (%d)" % pairs)
	# step 4: rain and storm
	var sheltered: int = 0
	var going_in: int = 0
	for id: String in people.plans:
		var st5: Dictionary = people.state_at(id, 0.5)
		var sp5: Dictionary = ((people.plans[id] as Dictionary).spots as Dictionary).get(String(st5.spot), {}) as Dictionary
		if bool(st5.moving) or bool(st5.inside) or not sp5.has("shelter"):
			continue
		people.set_weather(false, false)
		people._follow.erase(id)
		people._view(id, st5, 0.1)
		people.set_weather(true, false)
		var v5: Dictionary = {}
		var worst: float = 0.0
		var prev: Vector2 = st5.pos as Vector2
		for k: int in 900:
			v5 = people._view(id, st5, 0.1)
			worst = maxf(worst, (v5.pos as Vector2).distance_to(prev))
			prev = v5.pos as Vector2
		if (v5.pos as Vector2).distance_to(sp5.shelter as Vector2) < 1.0 and worst < 6.0:
			sheltered += 1
		people.set_weather(true, true)
		if bool(people._view(id, st5, 0.1).inside):
			going_in += 1
		people.set_weather(false, false)
		for k: int in 900:
			v5 = people._view(id, st5, 0.1)
		_check((v5.pos as Vector2).distance_to(st5.pos as Vector2) < 1.0, "%s walks back to its place after the rain" % id)
	_check(sheltered >= 8, "in the rain people walk smoothly under a roof (%d)" % sheltered)
	_check(going_in == sheltered, "in a storm they go in (%d of %d)" % [going_in, sheltered])
	people._follow.clear()

	# step 2: every core figure has its sheet, the clips its plan asks for and a person entry with chat (and, for three, a shop)
	for id: String in (DataRegistry.table("hallgrat_people").residents as Dictionary):
		var rig_path: String = "res://data/hallgrat_%s_rig.json" % id
		_check(FileAccess.file_exists(rig_path) and ResourceLoader.exists("res://assets/characters/hallgrat_%s.png" % id), "%s has a sheet and a rig" % id)
		var rig: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(rig_path)) as Dictionary if FileAccess.file_exists(rig_path) else {}
		var clips: Dictionary = rig.get("clips", {}) as Dictionary
		var tex: Texture2D = load("res://assets/characters/hallgrat_%s.png" % id) as Texture2D
		_check(tex != null and tex.get_width() == int(rig.get("frames", 0)) * 76 and tex.get_height() == 8 * 96, "%s: the sheet fits its rig" % id)
		for need: String in ["idle", "walk", "talk"]:
			_check(clips.has(need), "%s has the clip %s" % [id, need])
		for spot_id: String in (people.plans[id] as Dictionary).spots:
			var clip: String = String((((people.plans[id] as Dictionary).spots as Dictionary)[spot_id] as Dictionary).get("clip", "idle"))
			_check(clips.has(clip), "%s: the clip %s of spot %s is drawn" % [id, clip, spot_id])
		var who: Dictionary = DataRegistry.get_entry("settlers", id)
		_check(bool(who.get("away", false)) and not bool(who.get("enabled", true)), "%s is a person who lives elsewhere (away, not a town settler)" % id)
		_check(not (who.get("chat", {}) as Dictionary).is_empty(), "%s has chat lines" % id)
		if who.has("shop"):
			var shop: Dictionary = DataRegistry.get_entry("shops", String(who.shop))
			_check(not shop.is_empty(), "%s: the shop %s exists" % [id, String(who.shop)])
			for row: Variant in (shop.get("buy", []) as Array) + (shop.get("sell", []) as Array):
				var item: String = String((row as Dictionary).item)
				_check(not DataRegistry.get_entry("items", item).is_empty(), "%s: the shop's item %s exists" % [id, item])
	for shop_holder: String in ["tamsa", "hedda", "ilvane"]:
		_check(DataRegistry.get_entry("settlers", shop_holder).has("shop"), "%s keeps a shop" % shop_holder)

	await _world()
	print("HALLGRAT PEOPLE OK (%d checks)" % _checks if _ok else "HALLGRAT PEOPLE FAILED (%d checks)" % _checks)
	get_tree().quit(0 if _ok else 1)


## The real world: the figures appear when the player comes into town and stand where the plan says.
func _world() -> void:
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await _frames(2)
	var player: Player = world._players.get_child(0) as Player
	await _frames(30)
	player.health.god_mode = true
	TimeManager.unlock()
	TimeManager.set_time(0.47)
	var people: HallgratPeople = world.hallgrat.people
	_check(people != null, "Hallgrat has its people")
	_check(people.residents.is_empty(), "no figures far from the town")
	player.global_position = world.hallgrat.gate_point()
	var waited: int = 0
	while people.residents.is_empty() and waited < 1200:
		await _frames(10)
		waited += 10
	_check(not people.residents.is_empty(), "the figures appear in town (after %d frames)" % waited)
	for id: String in people.residents:
		var r: HallgratResident = people.residents[id] as HallgratResident
		var want: Dictionary = people.state_at(id, TimeManager.time_of_day)
		if bool(want.inside):
			_check(not r.visible, "%s is inside, as the plan says" % id)
		else:
			_check(r.visible and r.position.distance_to(want.pos as Vector2) < 4.0, "%s stands where the plan says" % id)
	var extra_count: int = 0
	for id: String in people.residents:
		if people.residents[id] is HallgratExtra:
			extra_count += 1
			var ex: HallgratExtra = people.residents[id] as HallgratExtra
			_check((ex.get_child(0) as Sprite2D).material is ShaderMaterial, "%s wears its own colours" % id)
	_check(extra_count == 24, "the townsfolk walk the town (%d)" % extra_count)
	# step 4: someone standing turns to look at the player who comes near
	var hedda: HallgratResident = people.residents.get("hedda") as HallgratResident
	if hedda != null:
		player.global_position = hedda.global_position + Vector2(-40, 0)
		await _frames(8)
		_check(hedda._sector == Adventurer.sector_of(player.global_position - hedda.global_position), "Hedda looks at the player beside her")
	# step 5: sounds
	var scfg: Dictionary = DataRegistry.table("hallgrat_people").get("sounds", {}) as Dictionary
	var folder: String = String(scfg.get("folder", ""))
	for entry: Dictionary in ((scfg.get("clips", {}) as Dictionary).values() + (scfg.get("voices", []) as Array)):
		for f: Variant in entry.get("files", []) as Array:
			_check(ResourceLoader.exists(folder + String(f) + ".wav"), "sound %s exists" % f)
	_check(ResourceLoader.exists(folder + "murmur.wav"), "the inn's murmur exists")
	var odrik: HallgratResident = people.residents.get("odrik") as HallgratResident
	if odrik != null:
		var before_s: int = HallgratResident.sounds_played
		player.global_position = odrik.global_position + Vector2(30, 0)
		odrik.moving = false
		odrik._talking = false
		odrik._last_frame = -1
		odrik._clip_time = 0.0
		for k: int in 120:
			odrik._clip = "chisel"
			odrik._sounds(1.0 / 60.0)
			odrik._clip_time += 1.0 / 60.0
		_check(HallgratResident.sounds_played - before_s >= 1, "Odrik's chisel rings on its strike frame (%d, %d playing)" % [HallgratResident.sounds_played - before_s, HallgratResident._playing])
		player.global_position = odrik.global_position + Vector2(2000, 0)
		before_s = HallgratResident.sounds_played
		odrik._clip_time = 0.0
		odrik._last_frame = -1
		for k: int in 120:
			odrik._sounds(1.0 / 60.0)
			odrik._clip_time += 1.0 / 60.0
		_check(HallgratResident.sounds_played == before_s, "nobody hears the chisel far away")
	# talking and trading (step 2)
	var town: TownManager = world.town()
	var tamsa: HallgratResident = people.residents.get("tamsa") as HallgratResident
	_check(tamsa != null and town.person_node("tamsa") == tamsa, "the town knows Tamsa as a person")
	if tamsa != null:
		player.global_position = tamsa.global_position + Vector2(0, 14)
		await _frames(6)
		_check(tamsa.prompt() == "ANSPRECHEN", "Tamsa: E = ANSPRECHEN on the first talk (%s)" % tamsa.prompt())
		_check(tamsa.chat_line() != "", "Tamsa has something to say")
		town.request_talk("tamsa")
		await _frames(4)
		_check(town.trust_of("tamsa") == 10 and town.has_met("tamsa"), "the first talk of a day builds trust (%d)" % town.trust_of("tamsa"))
		_check(tamsa.prompt() == "HANDELN", "Tamsa: then E = HANDELN (%s)" % tamsa.prompt())
		_check(town._near_role(player, "glass", 90.0), "her trade is valid next to her")
		town.request_talk("tamsa")
		await _frames(4)
		_check(town.trust_of("tamsa") == 10, "trust grows once a day")
		var tex: Texture2D = (tamsa.get_child(0) as Sprite2D).texture if tamsa.get_child_count() > 0 and tamsa.get_child(0) is Sprite2D else null
		_check(tex != null, "Tamsa is drawn from her sheet")
	if _dir != "" and DisplayServer.get_name() != "headless":
		for shot: Array in [["forum", world.hallgrat.forum + Vector2(0, 50), 0.5], ["market", world.hallgrat.gate_point() + Vector2(80, -20), 0.35]]:
			TimeManager.set_time(float(shot[2]))
			player.global_position = shot[1] as Vector2
			await _frames(120)
			var path: String = _dir.path_join("people_%s.png" % String(shot[0]))
			get_viewport().get_texture().get_image().save_png(path)
			print("CAPTURED ", path)
	player.global_position = Vector2(8000, 8000)
	await _frames(40)
	_check(people.residents.is_empty(), "the figures go when the player leaves")
	world.queue_free()
	await _frames(2)
