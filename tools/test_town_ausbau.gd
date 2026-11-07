extends Node
## docs/town_ausbau.md: lamp posts (cold / lit / empty), benches to sit on, the chatter, the map, the fire circle, the night edge, wear of the ground. Run with `--fixed-fps 60`.

var _ok: bool = true
var _checks: int = 0
var _events: Array[String] = []


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_ok = false
		print("TOWN AUSBAU FAILED: ", what)


func _frames(n: int) -> void:
	for i: int in n:
		get_tree().paused = false ## (a story dialogue of the checkpoint town pauses the solo game)
		await get_tree().process_frame


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await _frames(2)
	var player: Player = world._players.get_child(0) as Player
	var town: TownManager = world.town()
	await _frames(60)
	world.debug_jump_town()
	await _frames(120)
	town.event.connect(func(kind: String, _data: Dictionary) -> void: _events.append(kind))
	await _lamps(town, player)
	await _seats(town, player)
	await _visuals(world, town, player)
	await _people(world, town, player)
	await _ground(world, town, player)
	print("TOWN AUSBAU: ", "ok" if _ok else "FAILED", " (%d checks)" % _checks)
	get_tree().quit()


func _lamps(town: TownManager, player: Player) -> void:
	var lamps: Array[int] = town.built_ids("lamp_post")
	_check(lamps.size() >= 2, "the checkpoint town has lamp posts")
	var id: int = lamps[0]
	_check(town.lamp_state(id) == "lit" and int(town.lamp_u(id).f) == 1000, "the checkpoint's lamps burn full")
	_check(town.lamp_state(town.built_ids("workshop")[0]) == "", "other pieces are no lamps")
	var before: int = town.lit_circles().size()
	var building: int = town.circles().size()
	town._rpc_lamp.rpc(id, 0, 0, false)
	await _frames(2)
	_check(town.lamp_state(id) == "cold" and town.lamp_prompt(id) == "ANZÜNDEN", "a cold lamp offers to be lit")
	_check(town.lit_circles().size() == before - 1, "a cold lamp carries no light at night (%d -> %d)" % [before, town.lit_circles().size()])
	_check(town.circles().size() == building, "but it still extends the ground the town may build on")
	var at: Vector2 = town.rect_of(id).get_center()
	var depth_cold: float = town.light_depth(at + Vector2(0.0, 100.0))
	player.request_teleport(at + Vector2(0.0, 14.0))
	await _frames(30)
	var caps: int = player.inventory.count_item("glow_cap")
	town.stock.erase("glow_cap")
	player.inventory.remove_item("glow_cap", caps)
	town.request_lamp(id)
	await _frames(5)
	_check(town.lamp_state(id) == "cold", "without a glow cap nothing is lit")
	player.inventory.add_item("glow_cap", 3)
	town.request_lamp(id)
	await _frames(5)
	_check(town.lamp_state(id) == "lit" and int(town.lamp_u(id).f) == 500, "one glow cap lights it half full (%d)" % int(town.lamp_u(id).f))
	_check(player.inventory.count_item("glow_cap") == 2, "and costs exactly one")
	_check(town.lit_circles().size() == before, "the lit lamp carries its light again")
	_check(town.light_depth(at + Vector2(0.0, 100.0)) >= depth_cold, "the light reaches further again")
	_check(town.lamp_prompt(id) == "NACHFÜLLEN", "half full offers a refill")
	town.request_lamp(id)
	await _frames(5)
	_check(int(town.lamp_u(id).f) == 1000 and player.inventory.count_item("glow_cap") == 1, "a refill tops it up")
	_check(town.lamp_prompt(id) == "", "a full lamp offers nothing")
	town.request_lamp(id)
	await _frames(5)
	_check(player.inventory.count_item("glow_cap") == 1, "a full lamp takes nothing")
	var view: TownStructure = town.view_of(id)
	if view != null:
		_check(view._lamp_k == 1.0 and view._light != null and view._light.visible, "a burning lamp shows its light")
	# burning down: only at night
	TimeManager.time_of_day = 0.5
	town._burn_lamps()
	await _frames(2)
	_check(int(town.lamp_u(id).f) == 1000, "by day nothing burns")
	TimeManager.time_of_day = 0.95
	var hours: int = 0
	while town.is_lamp_burning(id) and hours < 40:
		town._burn_lamps()
		hours += 1
		await _frames(1)
	_check(town.lamp_state(id) == "empty" and hours >= 22 and hours <= 25, "three nights of fuel (%d night hours)" % hours)
	_check(_events.has("lamp_out"), "a lamp that goes out is an event")
	_check(town.lit_circles().size() == before - 2, "empty lamps carry no light (%d of %d)" % [town.lit_circles().size(), before])
	_check(town.lamp_state(lamps[1]) == "empty", "the other lamp burnt down with it")
	if view != null:
		_check(is_equal_approx(view._lamp_k, 0.2), "an empty lamp keeps only embers")
	# save and load keep the state
	var saved: Dictionary = town.export_state()
	town.import_state(saved)
	await _frames(5)
	_check(town.lamp_state(id) == "empty" and town.lamp_state(lamps[1]) == "empty" and town.lit_circles().size() == before - 2, "the lamps' state survives a save")
	town._rpc_lamp.rpc(lamps[1], 700, 1, false)
	# an old save without state: burns, full
	(town.structures[lamps[1]] as Dictionary).erase("u")
	_check(town.lamp_state(lamps[1]) == "lit" and int(town.lamp_u(lamps[1]).f) == 1000, "a lamp from an old save burns full")
	TimeManager.time_of_day = 0.5


func _seats(town: TownManager, player: Player) -> void:
	var seats: Array[BenchSeat] = town.seat_nodes()
	_check(seats.size() == 2 * town.built_ids("bench").size() and seats.size() >= 2, "every bench has two seats (%d)" % seats.size())
	var seat: BenchSeat = seats[0]
	_check(seat.get_path() == NodePath(str(town.get_path()) + "/Seats/" + String(seat.name)), "seats sit under Town/Seats")
	player.request_teleport(seat.approach_position() + Vector2(0.0, 8.0))
	await _frames(40)
	_check(seat.prompt() == "HINSETZEN", "a free seat offers to sit")
	var rest: RestComponent = player.get_node("RestComponent") as RestComponent
	player.health.set_health(40.0)
	rest.request_sit(seat)
	var sat: bool = false
	for i: int in 400:
		await get_tree().process_frame
		if rest.state == RestComponent.State.IDLE:
			sat = true
			break
	_check(sat, "she sits down on the bench")
	_check(seat.occupied() and seat.prompt() == "", "the taken seat is closed (%s, %s)" % [seat.occupied(), seat.prompt()])
	_check(not seats[1].occupied(), "the other seat is free")
	_check(town.light_depth(seat.global_position) > 0.0, "the bench stands in the town's light")
	var health: float = player.health.current
	await _frames(200)
	_check(player.health.current > health + 0.5, "sitting in the light heals a little (%.1f -> %.1f)" % [health, player.health.current])
	rest.request_stand()
	for i: int in 300:
		await get_tree().process_frame
		if rest.state == RestComponent.State.FREE:
			break
	_check(rest.state == RestComponent.State.FREE and not player.story_lock, "she gets up again")
	player.health.set_health(100.0)


func _visuals(world: WorldLevel, town: TownManager, player: Player) -> void:
	# --- the banner post is in the catalogue and can stand
	_check(TownRules.in_category("living").has("banner_post"), "the banner post is a piece of the living category")
	var spec: Dictionary = TownRules.piece("banner_post")
	_check(ResourceLoader.exists(TownStructure.DIR + String(spec.get("preview", "")) + ".png") and (spec.parts as Array).size() == 1, "it has a preview and a swaying banner")
	var site: Vector2 = town._debug_site("banner_post", town.center + Vector2(-40, 150))
	_check(site != Vector2.INF, "there is room for a banner post")
	var id: int = town.next_id
	town.next_id += 1
	town._rpc_added.rpc(id, {"p": "banner_post", "x": site.x, "y": site.y, "f": 0, "g": 0}, [])
	town._rpc_done.rpc(id)
	player.request_teleport(site + Vector2(0, 40))
	await _frames(60)
	var post: TownStructure = town.view_of(id)
	_check(post != null and post.progress == TownManager.PROGRESS_FULL, "the banner post stands")
	if post != null:
		_check(post._sprite.is_in_group("flora_glow"), "fireflies gather at it at night")
		_check(post._parts.size() == 1, "its banner hangs as a part")
	_check(TownRules.piece("lamp_post").has("fuel") and (town.structures[id] as Dictionary).get("u", null) == null, "pieces without fuel have no lamp state")
	# --- the market flaps
	var store_id: int = town.built_ids("stockpile")[0]
	var shop_id: int = town.built_ids("workshop")[0]
	for target: int in [store_id, shop_id]:
		player.request_teleport(town.position_of(target) + Vector2(0, 300))
		await _frames(30)
		var view: TownStructure = town.view_of(target)
		_check(view != null and view._shutters.size() == 1, "a stall has a flap (%s)" % TownRules.piece(String(town.structures[target].p)).name)
		if view == null or view._shutters.is_empty():
			continue
		var sprite: Sprite2D = view._shutters[0].sprite as Sprite2D
		TimeManager.time_of_day = 0.5
		await _frames(60)
		_check(sprite.visible and sprite.frame == sprite.hframes - 1, "by day the flap is propped up (frame %d)" % sprite.frame)
		TimeManager.time_of_day = 0.95
		await _frames(90)
		_check(sprite.frame == 0, "at night with nobody near it is shut (frame %d, near %s, forced %.1f, night %.2f)" % [sprite.frame, view._shutter_near, view._shutter_forced, TimeManager.night_amount()])
		view.open_shutters()
		await _frames(60)
		_check(sprite.frame == sprite.hframes - 1, "asking for the stock raises it again")
		view._shutter_forced = 0.0
		await _frames(90)
		_check(sprite.frame == 0, "and it falls again when the 20 seconds are over")
		var zone: Rect2 = town.front_of(target).grow(30.0) if town.front_of(target).has_area() else town.rect_of(target).grow(34.0)
		player.request_teleport(zone.get_center())
		await _frames(60)
		_check(sprite.frame == sprite.hframes - 1, "somebody standing at the front keeps it up")
	TimeManager.time_of_day = 0.5
	# --- ageing and care
	player.request_teleport(town.position_of(shop_id) + Vector2(0, 60))
	await _frames(60)
	var shop: TownStructure = town.view_of(shop_id)
	var seen: Dictionary = {}
	if shop != null:
		shop._update_wear()
		for entry: Dictionary in shop._wear:
			seen[String(entry.sprite.texture.resource_path.get_file().get_basename())] = (entry.sprite as Sprite2D).visible
	_check(town.cared(shop_id) and bool(seen.get("workshop_flowers", false)) and not bool(seen.get("workshop_neglect", true)), "with Gustav at home the workshop has flowers, no cobwebs")
	_check(bool(seen.get("workshop_ivy_a", false)), "after six days it has its first ivy")
	town.residents.erase("gustav")
	_check(not town.cared(shop_id) and not town.cared(store_id), "without the settler, nobody looks after the workshop or the stockpile")
	if shop != null:
		shop._update_wear()
		seen.clear()
		for entry: Dictionary in shop._wear:
			seen[String(entry.sprite.texture.resource_path.get_file().get_basename())] = (entry.sprite as Sprite2D).visible
	_check(not bool(seen.get("workshop_flowers", true)) and bool(seen.get("workshop_neglect", false)), "unattended it gathers cobwebs and loses its flowers")
	town.residents["gustav"] = {"trust": 0, "talked": -1}
	# --- the hut grows with the town
	var hut: Hut = world._hut()
	_check(hut._banner_mat != null and hut._banner_left != null and hut._flags.size() == 2 and hut._ivy.size() == 2, "the renewed hut has its banners, flags and ivy ready")
	hut._refresh_town_look()
	var level: int = town.level()
	_check(hut._banner_left.visible == (level >= 2) and hut._flags[0].visible == (level >= 3) and hut._flags[1].visible == (level >= 4), "banners and flags follow the town level (%d)" % level)
	(town.structures[0] as Dictionary).b = TimeManager.day - 5
	hut._refresh_town_look()
	_check(hut._ivy[0].visible and not hut._ivy[1].visible, "after five days the first ivy")
	(town.structures[0] as Dictionary).b = TimeManager.day - 10
	hut._refresh_town_look()
	_check(hut._ivy[1].visible and not hut._ivy[0].visible, "after ten days the full ivy")


func _people(world: WorldLevel, town: TownManager, player: Player) -> void:
	var hut: Hut = world._hut()
	var valdric: Settler = town.settler_node("valdric")
	var gustav: Settler = town.settler_node("gustav")
	_check(valdric != null and gustav != null, "Valdric and Gustav live in the town")
	if valdric == null or gustav == null:
		return
	# --- chatter: reactions
	player.request_teleport(hut.global_position + Vector2(40, 40))
	TimeManager.time_of_day = 0.60
	await _frames(60)
	var chatter: SettlerChatter = town.chatter
	_check(chatter != null and chatter._cfg.has("topics"), "the town has its chatter director with data")
	chatter._busy = false
	chatter._react_msec = 0
	player.request_teleport(valdric.global_position + Vector2(20, 10))
	await _frames(30)
	town.emit_event("lamp_out", {"count": 1})
	var shown: bool = false
	for i: int in 400:
		await get_tree().process_frame
		for sid: String in town.settler_ids():
			var node: Settler = town.settler_node(sid)
			if node != null and node._bubble != null and node._bubble.is_showing():
				shown = true
		if shown:
			break
	_check(shown, "somebody near reacts to a lamp going out with a bubble")
	_check(Time.get_ticks_msec() < chatter._react_msec, "and the next reaction has to wait")
	await _frames(500)
	chatter._busy = false
	# --- chatter: the evening talk at the fire is one topic a day and comes at the same moment for everyone
	_check(is_equal_approx(SettlerChatter.unit(4, "meet"), SettlerChatter.unit(4, "meet")) and SettlerChatter.unit(4, "meet") != SettlerChatter.unit(5, "meet"), "the day's pick is a fixed function of the day")
	chatter._played.clear()
	TimeManager.time_of_day = 0.858
	player.request_teleport(hut.global_position + Vector2(60, 50))
	var talked: bool = false
	for i: int in 900:
		await get_tree().process_frame
		chatter._react_msec = 0
		if not chatter._played.is_empty():
			talked = true
		if talked and (valdric._bubble != null and valdric._bubble.is_showing() or gustav._bubble != null and gustav._bubble.is_showing()):
			break
	_check(talked, "in the evening the two talk at the fire (%s)" % str(chatter._played.keys()))
	_check(valdric._bubble != null and gustav._bubble != null, "both got a bubble")
	await _frames(700)
	# --- entering the town says its name once a day
	player.request_teleport(town.center + Vector2(0, 80))
	await _frames(30)
	town._inside = false
	town._entered_day = -1
	town._watch_territory(0.0)
	_check(town._banner != null and town._banner.is_showing() and town._entered_day == TimeManager.day, "the name comes when the town is entered")
	var shown_before: bool = town._banner.is_showing()
	town._inside = false
	town._banner._age = 99.0
	town._watch_territory(0.0)
	_check(not town._banner.is_showing() and shown_before, "but only once a day")
	# --- the evening circle at the fire
	TimeManager.time_of_day = 0.805
	await _frames(60)
	var seat: CampfireSeat = hut.get_node("Seat_east") as CampfireSeat
	if seat.occupied():
		seat = hut.get_node("Seat_south") as CampfireSeat
	player.quests.set_flag("fire_seated")
	player.request_teleport(seat.approach_position() + Vector2(0, 6))
	await _frames(40)
	_check(FireCircle.company(town, seat.seat_position()) >= 1, "Valdric is at the fire in the evening")
	player.health.set_health(50.0)
	FireCircle._next.clear()
	var rest: RestComponent = player.get_node("RestComponent") as RestComponent
	rest.request_sit(seat)
	for i: int in 400:
		await get_tree().process_frame
		if rest.state == RestComponent.State.IDLE:
			break
	_check(rest.state == RestComponent.State.IDLE, "she sits at the fire")
	await _frames(300)
	_check(not FireCircle._next.has(player.get_multiplayer_authority()), "before the quiet seconds are over there is no warmth")
	await _frames(300)
	_check(FireCircle._next.has(player.get_multiplayer_authority()), "after eight quiet seconds with company the warmth comes")
	await _frames(420)
	_check(player.health.current > 54.0, "and heals a little (%.1f)" % player.health.current)
	rest.request_stand()
	await _frames(200)
	# an alarm breaks the circle up
	town.set_alert(true, 0.0)
	await _frames(2)
	_check(not FireCircle.tick(town, player, seat.seat_position(), 99.0), "while the dark gathers there is no warmth")
	# --- the watch at the edge of the light
	var plan_pos: Vector2 = valdric.global_position
	town.set_alert(true, 0.6)
	await _frames(5)
	_check(town.alert_on and is_equal_approx(town.alert_angle, 0.6), "the alarm reaches the town")
	var held: bool = false
	for i: int in 1500:
		await get_tree().process_frame
		if valdric._alert_mode == 2:
			held = true
			break
	_check(held, "Valdric walks out and holds the edge")
	var depth: float = town.light_depth(valdric.global_position)
	_check(depth > 0.0 and depth < 60.0, "he stands inside the light, near its edge (%.0f px deep)" % depth)
	town.set_alert(false, 0.0)
	var back: bool = false
	for i: int in 1500:
		await get_tree().process_frame
		if valdric._alert_mode == 0:
			back = true
			break
	_check(back, "when it is over he goes back to his day")
	# --- sparks where a creature is turned back
	town._touch_msec = 0
	town.light_touch(town.center + Vector2(300, 0))
	var first: int = town._touch_msec
	town.light_touch(town.center + Vector2(300, 0))
	_check(first > 0 and town._touch_msec == first, "the sparks are limited to a few a second")
	# --- the map shows the town (opens without errors, glyph tables are whole)
	var map: MapWindow = player.get_node("Hud/MapWindow") as MapWindow
	for glyph: Variant in MapWindow.TOWN_GLYPHS.values():
		_check((glyph as Array).size() == 5 and ((glyph as Array)[0] as String).length() == 5, "map glyphs are 5 by 5")
	map._set_open(true)
	await _frames(120)
	map._set_open(false)
	TimeManager.time_of_day = 0.5


func _ground(world: WorldLevel, town: TownManager, player: Player) -> void:
	# pure rules first
	var fake: Dictionary = {0: {"p": "house", "x": 0.0, "y": 0.0, "f": 0, "g": 1000, "b": 10}, 1: {"p": "bench", "x": 300.0, "y": 0.0, "f": 0, "g": 1000, "b": 10}}
	var young: Dictionary = TownWear.compute(fake, [], 10)
	var grown: Dictionary = TownWear.compute(fake, [], 20)
	var bench_cell: Vector2i = TownWear.cell_of(Vector2(300.0, -5.0))
	_check(float(young.get(bench_cell, 0.0)) > 0.1 and float(grown.get(bench_cell, 0.0)) > float(young.get(bench_cell, 0.0)) * 2.0, "a new piece wears the ground in over the days (%.2f -> %.2f)" % [float(young.get(bench_cell, 0.0)), float(grown.get(bench_cell, 0.0))])
	_check(float(grown.get(TownWear.cell_of(Vector2(300.0, 400.0)), 0.0)) == 0.0, "far from everything the grass stays")
	_check(float(grown.get(TownWear.cell_of(Vector2(300.0, 30.0)), 0.0)) < float(grown.get(bench_cell, 0.0)), "the wear falls off away from the piece")
	var door: Vector2 = Vector2(0.0, 12.0) ## the free strip before the house's door
	_check(float(grown.get(TownWear.cell_of(door), 0.0)) > 0.5, "the ground before a door is trodden")
	var with_way: Dictionary = TownWear.compute(fake, [{"s": 1, "p": [[100.0, 100.0], [200.0, 100.0]], "d": 1, "e": 1}], 20)
	_check(float(with_way.get(TownWear.cell_of(Vector2(150.0, 100.0)), 0.0)) > 0.6, "a trampled way is worn")
	var unfinished: Dictionary = TownWear.compute({1: {"p": "bench", "x": 300.0, "y": 0.0, "f": 0, "g": 400, "b": 10}}, [], 20)
	_check(unfinished.is_empty(), "a building site wears nothing")
	var img: Image = TownWear.field_image(grown, Vector2(-1024.0, -1024.0))
	_check(img.get_width() == TownWear.SIZE and img.get_pixel(128 + 37, 128).r > 0.1, "the picture for the ground shader has the wear in the right cell")
	# the real town
	player.request_teleport(town.center + Vector2(0, 60))
	await _frames(120)
	town._update_wear()
	_check(not town.wear.is_empty(), "the town's ground is worn")
	var hut_front: Vector2 = town.door_of(0) + Vector2(0.0, 8.0)
	_check(town.wear_at(hut_front) > 0.3, "before the hut's door (%.2f)" % town.wear_at(hut_front))
	var origin: Vector2 = TownWear.origin_for(town.center)
	_check(town._wear_tex != null and origin.x < town.center.x and origin.x + TownWear.SIZE * TownWear.CELL > town.center.x and origin.y < town.center.y, "the ground shader's field lies round the town")
	# small plants: a worn cell hides them, a free one keeps them
	var md: MeadowDetails = MeadowDetails.new()
	add_child(md)
	var points: Array[Dictionary] = []
	for k: int in 40:
		points.append({"pos": hut_front + Vector2(float(k % 8) * 3.0 - 10.0, float(k / 8) * 3.0), "kind": 2, "tint": Color.WHITE, "phase": 0.0, "sway": 0.0})
	for k: int in 40:
		points.append({"pos": town.center + Vector2(900.0 + float(k) * 2.0, 900.0), "kind": 2, "tint": Color.WHITE, "phase": 0.0, "sway": 0.0})
	md.setup(points, Vector2.ZERO)
	md.apply_wear(town)
	var hidden_near: int = 0
	var hidden_far: int = 0
	for key: Variant in md._hidden:
		if int(key) < 40:
			hidden_near += 1
		else:
			hidden_far += 1
	_check(hidden_near >= 15 and hidden_far == 0, "plants on trodden ground are not drawn, the others are (%d of 40 near, %d far)" % [hidden_near, hidden_far])
	md.queue_free()
	# demolishing a building lets the grass come back
	var bench_ids: Array[int] = town.built_ids("bench")
	var bench_at: Vector2 = town.position_of(bench_ids[0])
	var before: float = town.wear_at(bench_at + Vector2(0.0, -4.0))
	town.structures.erase(bench_ids[0])
	town._wear_dirty = true
	town._update_wear()
	_check(before > 0.2 and town.wear_at(bench_at + Vector2(0.0, -4.0)) < before, "the ground round a demolished bench recovers (%.2f -> %.2f)" % [before, town.wear_at(bench_at + Vector2(0.0, -4.0))])
