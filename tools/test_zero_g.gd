extends Node
## Automated headless verification for Caelia's Interstellar Sanctuary, Fluid Zero-G movement physics,
## Ellie's 8-direction floating sprite sheet, and redesigned 8-direction floating Caelia v2.

var _ok: bool = true


func _check(label: String, cond: bool) -> void:
	if not cond:
		_ok = false
		print("FAILED: ", label)
	else:
		print("PASS: ", label)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# 1. Pure ZeroGRules physics & data-driven contract
	var cfg: Dictionary = ZeroGRules.config()
	_check("data/zero_g.json loaded via DataRegistry", not cfg.is_empty() and cfg.has("motion") and cfg.has("horizon"))
	var cosmos_surf: Dictionary = Terrain.surface_data("cosmos")
	_check("data/terrain.json defines cosmos zero_g surface", bool(cosmos_surf.get("zero_g", false)) and bool(cosmos_surf.get("no_shadow", false)))

	# 1a. Smooth acceleration & cruise
	var vel: Vector2 = Vector2.ZERO
	var st: int = ZeroGRules.State.IDLE
	for _i: int in 36:
		var r: Dictionary = ZeroGRules.step_motion(vel, Vector2.RIGHT, false, false, Vector2.ZERO, 1.0 / 60.0, false)
		vel = r["velocity"] as Vector2
		st = int(r["state"])
	_check("cruise accelerates smoothly near 82 px/s", vel.x > 74.0 and vel.x < 86.0 and st == ZeroGRules.State.DRIFT)

	# 1b. Weightless inertia coasting when releasing keys (does NOT snap to 0 like ground!)
	var coast_v: Vector2 = vel
	for _i: int in 20:
		var r2: Dictionary = ZeroGRules.step_motion(coast_v, Vector2.ZERO, false, false, Vector2.ZERO, 1.0 / 60.0, false)
		coast_v = r2["velocity"] as Vector2
	_check("weightless coasting preserves graceful inertia after 0.33s", coast_v.x > 48.0 and coast_v.x < vel.x)

	# 1c. Shift Boost-Glide impulse & high top speed
	var glide_v: Vector2 = Vector2(40.0, 0.0)
	var boost_fired: bool = false
	var glide_st: int = ZeroGRules.State.IDLE
	for i: int in 40:
		var r3: Dictionary = ZeroGRules.step_motion(glide_v, Vector2.RIGHT, true, false, Vector2.ZERO, 1.0 / 60.0, i == 0)
		glide_v = r3["velocity"] as Vector2
		glide_st = int(r3["state"])
		if bool(r3["boost_fired"]):
			boost_fired = true
	_check("boost-glide fires push-off impulse & reaches high glide speed", boost_fired and glide_v.x > 145.0 and glide_st == ZeroGRules.State.GLIDE)

	# 1d. Counter-thrust braking detection & faster reversal
	var brake_res: Dictionary = ZeroGRules.step_motion(Vector2(120.0, 0.0), Vector2.LEFT, false, false, Vector2.ZERO, 1.0 / 60.0, false)
	_check("counter-thrust triggers BRAKE state and decelerates strongly", int(brake_res["state"]) == ZeroGRules.State.BRAKE and (brake_res["velocity"] as Vector2).x < 114.0)

	# 1e. Ctrl Hover-Brake stops much faster than passive coasting
	var hb_v: Vector2 = Vector2(100.0, 0.0)
	var passive_v: Vector2 = Vector2(100.0, 0.0)
	for _i: int in 20:
		hb_v = ZeroGRules.step_motion(hb_v, Vector2.ZERO, false, true, Vector2.ZERO, 1.0 / 60.0, false)["velocity"] as Vector2
		passive_v = ZeroGRules.step_motion(passive_v, Vector2.ZERO, false, false, Vector2.ZERO, 1.0 / 60.0, false)["velocity"] as Vector2
	_check("hover-brake decelerates far faster than passive drift", hb_v.x < passive_v.x * 0.38)

	# 1f. Soft Veil Horizon curves outward flight smoothly back inward without hard wall
	var edge_pos: Vector2 = Vector2(960.0, 0.0)
	var edge_vel: Vector2 = Vector2(95.0, 20.0)
	var peak_h: float = 0.0
	for _i: int in 90:
		var hr: Dictionary = ZeroGRules.step_motion(edge_vel, Vector2.ZERO, false, false, edge_pos, 1.0 / 60.0, false)
		edge_vel = hr["velocity"] as Vector2
		edge_pos += edge_vel * (1.0 / 60.0)
		peak_h = maxf(peak_h, float(hr["horizon"]))
	_check("soft veil horizon pulls outward drift smoothly back inward", peak_h > 0.65 and edge_vel.x < -10.0 and edge_pos.length() < 1040.0)

	# 2. Art sheets & rigs contract (Ellie zero-G + Caelia v2 8-dir)
	var ellie_tex: Texture2D = load("res://assets/characters/player_float.png") as Texture2D
	var ellie_blood: Texture2D = load("res://assets/characters/player_float_blood.png") as Texture2D
	_check("player_float.png & blood map match 56x8 of 64x64", ellie_tex != null and ellie_blood != null and Vector2i(ellie_tex.get_size()) == Vector2i(56 * 64, 8 * 64) and Vector2i(ellie_blood.get_size()) == Vector2i(56 * 64, 8 * 64))

	var god_tex: Texture2D = load("res://assets/characters/goddess.png") as Texture2D
	var god_glow: Texture2D = load("res://assets/characters/goddess_glow.png") as Texture2D
	_check("goddess.png & glow match 28x8 of 128x144 (8 directions)", god_tex != null and god_glow != null and Vector2i(god_tex.get_size()) == Vector2i(28 * 128, 8 * 144) and Vector2i(god_glow.get_size()) == Vector2i(28 * 128, 8 * 144))

	# 3. Live ZoneWorld + StarHallRoom + Player Zero-G & Caelia 360-degree tracking
	var world: ZoneWorld = load("res://src/world/v2/zone_world.tscn").instantiate() as ZoneWorld
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame

	var player: Player = world._players.get_child(0) as Player
	var interiors: Interiors = get_tree().get_first_node_in_group("interiors") as Interiors
	var hall: Interior = interiors.interior("starhall")
	var room: StarHallRoom = hall.get_node_or_null("StarHallRoom") as StarHallRoom

	_check("starhall sits in dedicated cosmos pocket band", Interiors.in_cosmos_band(hall.global_position) and hall.size == Vector2(2200.0, 2200.0))
	_check("starhall surface is cosmos", interiors.surface_at(interiors.starhall_position()) == "cosmos")
	_check("starhall has dust parallax and floating goddess/return rift", room != null and room.dust != null and room.goddess != null and room.return_seal != null)

	player.request_teleport(interiors.starhall_position())
	interiors.apply_view(player)
	for _i: int in 4:
		await get_tree().physics_frame
	await get_tree().process_frame
	_check("player enters zero-G automatically in interstellar space", player.in_zero_g())
	_check("player switches to FLOAT_SHEET_ID (21) with zero ground dust", player._sheet == Player.FLOAT_SHEET_ID and not player._run_dust.emitting)

	# Orbit Ellie north of Caelia -> Caelia smoothly turns from S (2) to N (6) across 8 directions
	player.global_position = room.goddess.global_position + Vector2(0.0, -90.0)
	for _i: int in 45:
		room.goddess._process(0.05)
	_check("Caelia smoothly turns 180 deg to face Ellie north (sector 6)", room.goddess.current_sector() == 6)

	# Orbit Ellie east of Caelia -> Caelia turns smoothly to E (0)
	player.global_position = room.goddess.global_position + Vector2(95.0, 0.0)
	for _i: int in 30:
		room.goddess._process(0.05)
	_check("Caelia smoothly turns to face Ellie east (sector 0)", room.goddess.current_sector() == 0)

	# Leave interstellar space -> zero-G cleanly disengages
	player.request_teleport(Vector2(840.0 * 16.0, 660.0 * 16.0))
	interiors.apply_view(player)
	for _i: int in 4:
		await get_tree().physics_frame
	_check("leaving space disables zero-G cleanly", not player.in_zero_g() and player.zero_g_state == ZeroGRules.State.NONE)

	print("ZERO_G: ", "ok" if _ok else "FAILED")
	get_tree().quit(0 if _ok else 1)
