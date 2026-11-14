extends Node
## Automated verification of Die Zenitwarte ("Das Zerbrochene Himmelswerk") in Region 34.

const WORLD: PackedScene = preload("res://src/world/world_level.tscn")

var _checks: int = 0
var _failures: int = 0


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("OBSERVATORY TEST FAILED: " + label)
		print("FAILED: ", label)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var world: WorldLevel = WORLD.instantiate() as WorldLevel
	if world == null:
		print("OBSERVATORY: 0 checks, 1 failures (world_level.tscn null)")
		get_tree().quit(1)
		return
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame
	world.finish_opening()

	var obs: DesertObservatory = world.desert_observatory
	_check(obs != null, "WorldLevel attaches DesertObservatory")
	if obs == null:
		print("OBSERVATORY: %d checks, %d failures" % [_checks, _failures])
		get_tree().quit(1)
		return

	_check(obs.is_in_group("desert_observatory"), "DesertObservatory in group desert_observatory")
	_check(obs.is_in_group("quest_actors"), "DesertObservatory in group quest_actors")
	_check(obs.is_in_group("resonance_obelisks"), "DesertObservatory in group resonance_obelisks")

	var marker: Dictionary = obs.map_marker()
	var rotunda_pos: Vector2 = obs._rotunda_pos
	var sundial_pos: Vector2 = obs._sundial_pos
	var gate_pos: Vector2 = obs._gate_pos
	var mirror_pos: Vector2 = obs._mirror_pos
	var altar_pos: Vector2 = obs._altar_pos
	var ocular_pos: Vector2 = obs._ocular_pos

	_check(String(marker.get("id", "")) == "zenitwarte" and (marker.get("position", Vector2.ZERO) as Vector2).distance_to(rotunda_pos) < 8.0, "zenitwarte map marker targets Summit Rotunda")

	# Quartz paved terrain surface check across plazas
	_check(Terrain.surface_at(rotunda_pos) == "quartz", "Terrain.surface_at returns quartz on Summit Astral Plaza")
	_check(Terrain.surface_at(sundial_pos) == "quartz", "Terrain.surface_at returns quartz on Sundial Court")
	_check(Terrain.surface_at(gate_pos) == "quartz", "Terrain.surface_at returns quartz on Ecliptic Gate Forecourt")

	# Shade & cooling check (Star-Mirror cooling mist + Rotunda shade)
	_check(DesertHeat.is_in_shade(get_tree(), mirror_pos), "DesertHeat cools at Sunken Star-Mirror Basin")
	_check(DesertHeat.is_in_shade(get_tree(), rotunda_pos + Vector2(20.0, 14.0)), "DesertHeat detects shade at Rotunda Vault canopy")

	# Crystal recharge aura (+35..45% near Prism Altar & Causeway)
	var rate_altar: float = DesertHeat.spell_recharge_rate(get_tree(), altar_pos + Vector2(24.0, 0.0))
	var rate_causeway: float = DesertHeat.spell_recharge_rate(get_tree(), obs._causeway_center)
	_check(rate_altar >= 1.35 and rate_causeway >= 1.35, "Crystal recharge aura boosts spell recharge near Prism Altar (%.2f) & Causeway (%.2f)" % [rate_altar, rate_causeway])

	# Sundial real-time Gnomon shadow shift & Zenith Noon Pulse
	TimeManager.unlock()
	TimeManager.locked = true
	TimeManager.time_of_day = 0.28
	obs._process(0.05)
	var tod_am: float = obs._sundial_overlay._tod
	TimeManager.time_of_day = 0.50
	obs._process(0.05)
	var pulsed_noon: bool = obs._noon_pulsed_day and obs._surge_timer > 0.0
	var any_conduit_pulsing: bool = false
	for c: DesertObservatory.ObservatoryConduit in obs._conduits:
		if is_instance_valid(c) and c.is_pulsing():
			any_conduit_pulsing = true
			break
	TimeManager.time_of_day = 0.72
	obs._process(0.05)
	var tod_pm: float = obs._sundial_overlay._tod
	_check(tod_am < 0.35 and tod_pm > 0.65, "Sundial tracks dawn-to-dusk solar time shifts (am=%.2f -> pm=%.2f)" % [tod_am, tod_pm])
	_check(pulsed_noon and any_conduit_pulsing, "Zenith Noon Pulse energizes conduits and flares Observatory at 0.50")

	# Physics collision & Y-sort regression guards for Rotunda interior, West buttress, East stairs, and Portal landing
	var space: PhysicsDirectSpaceState2D = world.get_world_2d().direct_space_state
	var point_query: Callable = func(wpos: Vector2) -> bool:
		var q: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
		q.position = wpos
		q.collision_mask = 1
		q.collide_with_bodies = true
		return not space.intersect_point(q, 1).is_empty()
	_check(bool(point_query.call(rotunda_pos + Vector2(0.0, -12.0))), "Rotunda interior behind doors is solidly collided")
	_check(bool(point_query.call(rotunda_pos + Vector2(-97.0, 9.0))), "West Astrolabe outward buttress cylinder is collided")
	_check(bool(point_query.call(rotunda_pos + Vector2(95.0, 11.0))), "East Flank curved staircase is collided")
	_check(not bool(point_query.call(rotunda_pos + Vector2(0.0, 18.0))), "Star-Portal upper stair landing remains walkable")

	# Conduits keep clear of Relief cliff blockers along all sampled waypoints
	var conduit_cliff_hits: int = 0
	for c: DesertObservatory.ObservatoryConduit in obs._conduits:
		for si: int in 25:
			var sample_local: Vector2 = c.sample_at(float(si) / 24.0)
			if world._relief.blocked_at(c.global_position + sample_local):
				conduit_cliff_hits += 1
	_check(obs._conduits.size() == 6 and conduit_cliff_hits == 0, "All 6 ObservatoryConduit channels stay clear of Relief cliff walls (hits=%d)" % conduit_cliff_hits)

	# Sealed Star-Portal Interactable shows SettlerBubble without switching scenes
	var player: Player = world._players.get_child(0) as Player
	var portal: Node = null
	for n: Node in obs._ysort_owned:
		if n.name == "ObsRotundaPortal":
			portal = n
			break
	if portal == null:
		portal = obs.get_node_or_null("ObsRotundaPortal")
	_check(portal != null and portal.has_method("interact"), "Sealed Star-Portal Interactable exists")
	if portal != null and player != null:
		_check((portal as Node2D).global_position.y < rotunda_pos.y + 13.0, "Star-Portal Y-sort pivot sits behind the top stair landing")
		portal.call("interact", player)
		await get_tree().process_frame
		var has_bubble: bool = false
		for ch: Node in portal.get_children():
			if ch is SettlerBubble:
				has_bubble = true
				break
		_check(has_bubble and is_instance_valid(world), "Portal interaction shows SettlerBubble exterior lore without leaving WorldLevel")

	# Polar Ocular Vista & MapDiscovery reveal
	var ocular: Node = null
	for n: Node in obs._ysort_owned:
		if n.name == "ObsPolarOcular":
			ocular = n
			break
	var discovery: MapDiscovery = get_tree().get_first_node_in_group("map_discovery") as MapDiscovery
	var hud: Node = player.get_node_or_null("Hud") if player != null else null
	_check(ocular != null and ocular.has_method("interact"), "Polar Ocular Interactable exists")
	if ocular != null and player != null:
		player.request_teleport(ocular_pos + Vector2(0.0, 12.0))
		await get_tree().process_frame
		ocular.call("interact", player)
		await get_tree().process_frame
		await get_tree().process_frame
		var vista_ok: bool = world._vista_focus_radius == 2 and obs._vista_discovered
		var hud_ok: bool = hud == null or bool(hud.get("vista_hide"))
		var disc_ok: bool = discovery != null
		_check(vista_ok and hud_ok and disc_ok, "Polar Ocular activates vista focus, fades HUD, and triggers MapDiscovery reveal")
		ocular.call("interact", player)
		await get_tree().process_frame

	# Arcane lightning strike surge
	obs._surge_timer = 0.0
	obs.on_arcane_lightning(rotunda_pos)
	_check(obs._surge_timer >= 6.0, "Arcane lightning strike triggers Observatory surge")

	# RoofPerch registration for desert_falcon in arid biome
	var desert_perches: int = 0
	for p_node: Node in get_tree().get_nodes_in_group("town_perches"):
		var perch: RoofPerch = p_node as RoofPerch
		if perch != null and BiomeBlend.arid_at(perch.global_position) >= 0.4:
			desert_perches += 1
	_check(desert_perches >= 2, "Observatory registers >= 2 RoofPerch points in Sonnenquarz-Öde (%d found)" % desert_perches)

	TimeManager.unlock()
	print("OBSERVATORY: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
