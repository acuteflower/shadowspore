extends Node
## Hallgrat, stage 1 (docs/stadt_westen_konzept.md 14): the ground plan and the Westweg in the real world level. Checks the milestones (count,
## numbers, flat level-0 ground, solid, readable), the road's baked pieces (all there, path/stone underfoot along the whole road, paved at the
## gate), the town's map marker, the developer plan and the teleports. With `--dir=/abs/folder` it also captures the fork, the open road, the
## last milestone at night, the gate with the plan and the forum with the plan.
## `Godot [--headless | --rendering-driver opengl3] --path . --fixed-fps 60 tools/test_hallgrat.tscn [-- --dir=/abs/folder]` -> `HALLGRAT OK`

var _ok: bool = true
var _dir: String = ""
var _checks: int = 0


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_ok = false
		print("HALLGRAT FAILED: ", what)


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			_dir = arg.trim_prefix("--dir=")
	_run.call_deferred()


func _shot(name_id: String) -> void:
	if _dir == "" or DisplayServer.get_name() == "headless":
		return
	var hero: Player = Player.all[0] if not Player.all.is_empty() else null
	var own: Camera2D = hero.get_node_or_null("Camera2D") as Camera2D if hero != null else null
	if own != null and not own.is_current():
		own.make_current()
		await _frames(30)
	var path: String = _dir.path_join("hallgrat_%s.png" % name_id)
	get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURED ", path)


func _go(player: Player, to: Vector2, settle: int = 150) -> void:
	player.global_position = to
	player.velocity = Vector2.ZERO
	await _frames(settle)


func _run() -> void:
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await _frames(2)
	var player: Player = world._players.get_child(0) as Player
	await _frames(30)
	player.health.god_mode = true
	TimeManager.unlock()
	TimeManager.set_time(0.45)
	var hud: CanvasLayer = get_tree().get_first_node_in_group("hud") as CanvasLayer
	if hud != null and _dir != "":
		hud.visible = false
	var data: Dictionary = DataRegistry.table("hallgrat")
	var town: Hallgrat = world.hallgrat
	_check(town != null and town.is_in_group("hallgrat"), "the world has a Hallgrat node")
	if town == null:
		_finish()
		return
	await _stone_style(data)
	# milestones
	var specs: Array = data.get("milestones", []) as Array
	_check(specs.size() >= 12, "the Westweg has its milestones (%d)" % specs.size())
	_check(town.milestones.size() == specs.size(), "every milestone is built (%d of %d)" % [town.milestones.size(), specs.size()])
	var last: Milestone = null
	var numbers: Array[int] = []
	for stone: Milestone in town.milestones:
		numbers.append(stone.number)
		_check(stone.number % Milestone.STEP == 0 and stone.number >= Milestone.FIRST and (stone.number - Milestone.FIRST) / Milestone.STEP < Milestone.ART.get_width() / Milestone.FRAME.x,
			"milestone %d has its own frame" % stone.number)
		_check(Terrain.relief == null or is_equal_approx(Terrain.relief.level_at(stone.global_position), 0.0), "milestone %d stands on level 0" % stone.number)
		_check(not stone.prompt().is_empty(), "milestone %d can be read" % stone.number)
		if stone.number == 50:
			last = stone
	numbers.sort()
	_check(numbers.size() > 0 and numbers[0] == 50, "the last milestone before the gate says 50")
	for i: int in range(1, numbers.size()):
		_check(numbers[i] - numbers[i - 1] == 50, "the milestones count down in fifties (%d after %d)" % [numbers[i], numbers[i - 1]])
	_check(last != null and last.lit() and last.tone() == 1, "the last stone's crystal is alive and carries a note")
	# the road: its baked pieces and the ground underfoot
	var road: Dictionary = data.get("westweg", {}) as Dictionary
	var pieces: Array = road.get("paths", []) as Array
	var decals: int = 0
	for node: Node in world.get_children():
		if node is GroundDecal and String((node as GroundDecal).texture.resource_path).contains("/westweg_"):
			decals += 1
	_check(pieces.size() >= 6 and decals == pieces.size(), "every piece of the Westweg is laid (%d of %d)" % [decals, pieces.size()])
	var ground: Dictionary = DataRegistry.table("ground")
	var spec: Dictionary = {}
	for p: Dictionary in ground.get("paths", []) as Array:
		if String(p.id) == "westweg_1":
			spec = p
	var start: Array = DataRegistry.table("world_map").get("start", [0, 0]) as Array
	var centre: Vector2 = Vector2(float(start[0]), float(start[1])) * 16.0 + Vector2(8, 8)
	var pts: Array = spec.get("points", []) as Array
	var off: int = 0
	for i: int in range(3, pts.size() - 1):
		var p_curr: Vector2 = Vector2(float((pts[i] as Array)[0]), float((pts[i] as Array)[1]))
		var p_prev: Vector2 = Vector2(float((pts[i - 1] as Array)[0]), float((pts[i - 1] as Array)[1]))
		var p_next: Vector2 = Vector2(float((pts[i + 1] as Array)[0]), float((pts[i + 1] as Array)[1]))
		var tangent: Vector2 = (p_next - p_prev).normalized()
		var normal: Vector2 = Vector2(-tangent.y, tangent.x)
		var at: Vector2 = centre + p_curr
		var s_mid: String = Terrain.surface_at(at)
		var s_left: String = Terrain.surface_at(at + normal * 6.5)
		var s_right: String = Terrain.surface_at(at - normal * 6.5)
		var mid_ok: bool = (s_mid == "path" or s_mid == "stone")
		var ruts_ok: bool = (s_left == "path" or s_left == "stone") and (s_right == "path" or s_right == "stone")
		if not mid_ok and not ruts_ok:
			off += 1
	_check(pts.size() > 20 and off <= 2, "the road is path or paving underfoot along its whole length (%d of %d points off)" % [off, pts.size()])
	var end: Vector2 = centre + Vector2(float((pts[pts.size() - 2] as Array)[0]), float((pts[pts.size() - 2] as Array)[1]))
	_check(Terrain.surface_at(end) == "stone", "the old road is paved at the gate (%s)" % Terrain.surface_at(end))
	# stage 3a: the paved squares and streets
	var paving: Array = data.get("paving", []) as Array
	var laid: int = 0
	var door_lanes: int = 0
	for node: Node in world.get_children():
		if node is GroundDecal and String((node as GroundDecal).texture.resource_path).contains("/hallgrat_"):
			if String((node as GroundDecal).texture.resource_path).contains("/hallgrat_zugang_"):
				door_lanes += 1
			else:
				laid += 1
	_check(paving.size() >= 6 and laid == paving.size(), "every square and street of Hallgrat is paved (%d of %d)" % [laid, paving.size()])
	_check(door_lanes == (data.get("door_paths", []) as Array).size() and door_lanes > 20, "every door has its lane to the streets (%d)" % door_lanes)
	var forum_ring: Vector2 = Vector2(142, 355) * 16.0 + Vector2(8, 8)
	_check(Terrain.surface_at(forum_ring + Vector2(118, 0)) == "stone", "the forum's ring is stone underfoot")
	_check(Terrain.surface_at(Vector2(197, 345) * 16.0 + Vector2(8, 8)) == "stone", "the market is stone underfoot")
	var statue: WaystoneStatue = world.get_node_or_null("Waystone_glaskamm_wachterin") as WaystoneStatue
	_check(statue != null and statue.paved and not statue._ground.visible, "the Wächterin stands on the forum's dais, not in her wild bed")
	_check(Terrain.surface_at(forum_ring + Vector2(30, 6)) == "stone", "the dais under the statue is stone underfoot")
	# stage 3b: houses, halls, gatehouses, the stables and the forum market
	var placed: Array = data.get("placed", []) as Array
	var stalls: int = 0
	for bspec: Dictionary in placed:
		stalls += 1 if String(bspec.type).begins_with("stand_") else 0
	_check(town.buildings.size() == placed.size() and placed.size() >= 40 and stalls >= 8, "every building and market stall stands (%d, %d stalls)" % [town.buildings.size(), stalls])
	var off_level: int = 0
	for house: HallgratBuilding in town.buildings:
		if house._sprite == null:
			off_level += 1
	_check(off_level == 0, "every building has its picture (%d without)" % off_level)
	var stable_found: bool = false
	for house: HallgratBuilding in town.buildings:
		stable_found = stable_found or house.type_id == "stall"
	_check(stable_found, "the stables stand in the Fuß")
	# stage 3d: the life of the streets (tools/place_hallgrat_deco.py)
	var deco_specs: Array = data.get("deco", []) as Array
	var bare: int = 0
	var lanterns: int = 0
	for thing: HallgratBuilding in town.deco:
		bare += 1 if thing._sprite == null else 0
		lanterns += 1 if thing.type_id == "deko_laterne" else 0
	_check(town.deco.size() == deco_specs.size() and deco_specs.size() >= 50 and bare == 0, "the street furniture stands (%d things, %d without a picture)" % [town.deco.size(), bare])
	var wall_specs: Array = DataRegistry.table("hallgrat_art").get("wall_pieces", []) as Array
	var walls_bare: int = 0
	for piece: HallgratBuilding in town.low_walls:
		walls_bare += 1 if piece._sprite == null else 0
	_check(lanterns >= 5 and town.low_walls.size() == wall_specs.size() and wall_specs.size() >= 40 and walls_bare == 0,
			"lantern posts and low walls line the ways (%d lanterns, %d wall pieces of %d runs)" % [lanterns, town.low_walls.size(), (data.get("wall_runs", []) as Array).size()])
	var greens: Array[Dictionary] = town.extra_props()
	var known: int = 0
	for green: Dictionary in greens:
		known += 1 if DataRegistry.table("plants").has(String(green.kind)) else 0
	_check(greens.size() >= 300 and known == greens.size(), "trees, bushes and flowers grow on the town's free grass (%d)" % greens.size())
	# stage 3c: the town wall (once the west wall), the guide stones, the bell
	_check(town.leitsteine.size() == (data.get("leitsteine", []) as Array).size() and town.leitsteine.size() >= 12, "every guide stone stands (%d)" % town.leitsteine.size())
	var types: Dictionary = DataRegistry.table("hallgrat_art").get("types", {}) as Dictionary
	var town_wall: int = 0
	var towers: int = 0
	var unsolid: int = 0
	for piece: HallgratBuilding in town.low_walls:
		var info: Dictionary = types.get(piece.type_id, {}) as Dictionary
		if info.has("towers"):
			town_wall += 1
			towers += (info.towers as Array).size()
		var shapes: int = 0
		for child: Node in piece.get_children():
			if child is StaticBody2D:
				shapes += child.get_child_count()
		unsolid += 1 if shapes == 0 else 0
	_check(town_wall >= 40 and towers >= 20, "the town wall runs round the terraces' brink (%d pieces, %d towers)" % [town_wall, towers])
	_check(unsolid == 0, "every piece of wall stops a walker (%d without a collider)" % unsolid)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var probe: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
	var blocked: int = 0
	var probed: int = 0
	for piece: HallgratBuilding in town.low_walls:
		var chain: Array = (types.get(piece.type_id, {}) as Dictionary).get("chain", []) as Array
		if chain.size() < 2 or probed >= 30:
			continue
		var a: Array = chain[chain.size() / 2] as Array
		probe.position = piece.global_position + Vector2(float(a[0]), float(a[1]) - 1.0)
		probe.collide_with_bodies = true
		probed += 1
		blocked += 1 if not piece.get_world_2d().direct_space_state.intersect_point(probe, 4).is_empty() else 0
	_check(probed > 0 and blocked == probed, "the walls' lines are solid in the physics world (%d of %d probes)" % [blocked, probed])
	_check(town.bell_at.is_finite(), "the moon tower carries the dusk bell")
	var struck: HallgratLeitstein = town.leitsteine[0]
	struck.interact(player)
	_check(struck._struck < 0.1 and struck.prompt() == "ANSCHLAGEN", "a guide stone can be struck")
	var runs: Array = DataRegistry.table("ground_baked").get("hallgrat_clear", []) as Array
	_check(runs.size() > 50, "the paved tiles are kept free of generated props (%d runs)" % runs.size())
	# the map and the plan
	var marker: Dictionary = town.map_marker()
	_check(String(marker.get("id", "")) == "hallgrat" and (marker.position as Vector2).distance_to(Vector2(142, 355) * 16.0 + Vector2(8, 8)) < 1.0, "the map marks the town at its forum")
	_check(DataRegistry.table("map_markers").has("hallgrat"), "the town has a map style")
	town.show_plan(true)
	await _frames(2)
	_check(town.plan_shown() and town.plan.get_parent() == world, "the developer plan is drawn into the world")
	# a walk: the fork, a stretch of open road, the last stone at night, the gate, the forum
	var fork: Vector2 = town.fork_point()
	_check(fork.is_finite(), "the Westweg knows its fork")
	town.show_plan(false)
	await _go(player, fork + Vector2(-60, 10))
	await _shot("fork")
	var far: Milestone = null
	for stone: Milestone in town.milestones:
		if stone.number == 400:
			far = stone
	if far != null:
		await _go(player, far.global_position + Vector2(-30, 24))
		_check(player.global_position.distance_to(far.global_position + Vector2(-30, 24)) < 20.0, "she can stand beside the milestone 400 (not pushed away)")
		far.interact(player)
		await _frames(30)
		await _shot("road")
	if last != null:
		TimeManager.set_time(0.92)
		await _go(player, last.global_position + Vector2(24, 26), 120)
		last.interact(player)
		await _frames(40)
		await _shot("last_night")
		TimeManager.set_time(0.45)
	if _dir != "": ## stage 2: the stone look of the town (day, and the glowing rock at night)
		for spot: Array in [["gate", Vector2(191, 346)], ["steige", Vector2(171, 359)], ["forum", Vector2(150, 360)], ["westwall", Vector2(113, 352)],
				["verloren", Vector2(127, 334)], ["glasbruch", Vector2(166, 327)], ["stall", Vector2(219, 378)], ["markt_forum", Vector2(142, 362)],
				["deko", Vector2(178, 351)], ["deko_fuss", Vector2(206, 372)], ["deko_staffeln", Vector2(160, 375)]]:
			await _go(player, (spot[1] as Vector2) * 16.0 + Vector2(8, 8), 150)
			await _shot(String(spot[0]))
		TimeManager.set_time(0.93)
		await _go(player, Vector2(166, 327) * 16.0 + Vector2(8, 8), 90)
		await _shot("glasbruch_night")
		await _go(player, Vector2(113, 352) * 16.0 + Vector2(8, 8), 120)
		await _shot("westwall_night")
		await _go(player, Vector2(178, 351) * 16.0 + Vector2(8, 8), 120)
		await _shot("deko_night")
		TimeManager.set_time(0.45)
	town.show_plan(true)
	await _go(player, town.gate_point(), 180)
	_check(Terrain.relief == null or is_equal_approx(Terrain.relief.level_at(player.global_position), 0.0), "the gate's foot is on the market level")
	await _shot("gate_plan")
	await _go(player, town.forum + Vector2(40, 30), 180)
	_check(Terrain.relief == null or Terrain.relief.level_at(player.global_position) > 2.5, "the forum lies on the summit (level 3)")
	await _shot("forum_plan")
	_finish()


## Stage 2: the town's stone look is only a restyle of the loaded relief. Outside the style areas every byte equals the plain bake (with the
## shared meadow look), inside only the style nibble changes and rock steps turn into stairs; heights, geometry and collision never move.
func _stone_style(data: Dictionary) -> void:
	Relief.town_styles = false
	var plain: Relief = Relief.new()
	Relief.town_styles = true
	var town: Relief = Relief.new()
	var a: PackedByteArray = plain._bytes
	var b: PackedByteArray = town._bytes
	_check(a.size() == b.size(), "both reliefs have the same size")
	var polys: Array[PackedVector2Array] = []
	for d: Dictionary in data.districts as Array:
		var poly: PackedVector2Array = PackedVector2Array()
		for at: Array in d.poly as Array:
			poly.append(Vector2(float(at[0]), float(at[1])))
		polys.append(poly)
	var outside: int = 0
	var moved: int = 0
	var bad_kind: int = 0
	var changed: int = 0
	var side: int = plain._side
	for i: int in range(0, a.size(), 4):
		if a[i] != b[i] or a[i + 2] != b[i + 2] or a[i + 3] != b[i + 3]:
			moved += 1
		if a[i + 1] == b[i + 1]:
			continue
		changed += 1
		var cell: Vector2 = Vector2((i / 4) % side + 0.5, (i / 4) / side + 0.5)
		var inside: bool = false
		for poly: PackedVector2Array in polys:
			inside = inside or Geometry2D.is_point_in_polygon(cell, poly)
		if not inside:
			outside += 1
		var ka: int = a[i + 1] & 15
		var kb: int = b[i + 1] & 15
		if ka != kb and not (ka == Relief.STEPS and kb == Relief.STAIRS):
			bad_kind += 1
	_check(moved == 0, "no height, geometry or biome byte moves (%d)" % moved)
	_check(changed > 2000 and changed == town.town_cells, "the town's tiles are restyled (%d)" % changed)
	_check(outside == 0, "nothing outside the town's districts changes (%d tiles)" % outside)
	_check(bad_kind == 0, "only rock steps become stairs (%d other kind changes)" % bad_kind)
	_check(plain._block == town._block and plain._field == town._field, "collision and the level field are the bake's")
	_check(town.kind(186, 342) == Relief.STAIRS and town.style(186, 342) == 2, "the east gate is a cut stair of masonry")
	_check(town.kind(164, 354) == Relief.STAIRS and town.kind(178, 355) == Relief.STAIRS, "the Steige climbs on stairs to the forum")
	_check(town.style(142, 355) == 2 and town.style(112, 345) == 2, "the summit and the west wall are masonry")
	_check(town.style(175, 305) == 3 and town.has_glow_style(Rect2i(160, 296, 30, 25)), "the Glasbruch's rock carries crystal veins")
	_check(town.style(125, 320) == 4, "the void eats the lost quarter")
	_check(town.kind(119, 330) == Relief.STAIRS and town.style(119, 330) == 2, "the stair down onto the west wall is masonry, not the lost quarter's")
	_check(town.style(300, 500) == plain.style(300, 500) and town.kind(130, 420) == plain.kind(130, 420), "the land around stays as it was")
	await get_tree().process_frame


func _finish() -> void:
	print("HALLGRAT %s (%d checks)" % ["OK" if _ok else "FAILED", _checks])
	get_tree().quit(0 if _ok else 1)
