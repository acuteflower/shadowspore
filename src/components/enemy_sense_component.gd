class_name EnemySenseComponent
extends Node
## Reusable 3-channel V2 sensory brain (`T2`) for host-authoritative predators:
## 1. Directional 8-Eye Vision Cone (`fov_deg` sharp frontal sight + `peripheral_scale` flank motion detection).
## 2. Substrate Biotremor (`MovementRules.surface_noise_scale` coupling: gravel/stone/puddle amplify tremors,
##    plush woodland `moss` muffles footsteps; `AgileTraversal` landings & sword swings emit tremor rings).
## 3. Remembered Trail Evidence (`known_pos`, `memory_left` — never cheats hidden player live positions!).
## 4. Narrative "Ellie = Shadowspore" Spore-Kinship Hesitation (`HESITATE` once per calm outer encounter).

enum TriggerKind { NONE = 0, VISION = 1, TREMOR = 2, TETHER = 3 }

var known_pos: Vector2 = Vector2.ZERO
var memory_left: float = 0.0
var last_trigger: int = TriggerKind.NONE

var _owner_body: Node2D
var _cfg: Dictionary = {}
var _sight_range: float = 170.0
var _lose_range: float = 260.0
var _hesitated_peers: Dictionary = {} ## player_instance_id -> bool (once per calm encounter)
var _prev_air: Dictionary = {} ## player_instance_id -> float (detects AgileTraversal landing impact!)


func configure(owner_body: Node2D, enemy_def: Dictionary) -> void:
	_owner_body = owner_body
	_sight_range = float(enemy_def.get("sight_range", 170.0))
	_lose_range = float(enemy_def.get("lose_range", 260.0))
	_cfg = enemy_def.get("senses", {}) as Dictionary
	if owner_body != null:
		known_pos = owner_body.global_position


func tick_memory(delta: float) -> void:
	if memory_left > 0.0:
		memory_left = maxf(0.0, memory_left - delta)


func remember(world_pos: Vector2, trigger: int = TriggerKind.VISION, duration_override: float = -1.0) -> void:
	known_pos = world_pos
	last_trigger = trigger
	var mem_dur: float = duration_override if duration_override > 0.0 else float(_cfg.get("memory_seconds", 8.0))
	memory_left = maxf(memory_left, mem_dur)


func clear_memory() -> void:
	memory_left = 0.0
	last_trigger = TriggerKind.NONE


func reset_calm() -> void:
	_hesitated_peers.clear()


## Evaluates whether `player` triggers a brief "Ellie = Shadowspore" kinship hesitation (`0.45 s` curious head-tilt)
## before Valdrics Sun-Quartz sears the spider's senses into aggression!
func consume_hesitation(player: Player, origin: Vector2) -> bool:
	if player == null:
		return false
	var pid: int = player.get_instance_id()
	if _hesitated_peers.has(pid):
		return false
	_hesitated_peers[pid] = true
	var min_r: float = float(_cfg.get("hesitate_min_range", 102.0))
	var dist: float = origin.distance_to(player.global_position)
	var calm_approach: bool = (player.attack == null or not player.attack.is_swinging()) and dist >= min_r
	return calm_approach


## Scans all living, unveiled players using both 8-eye directional vision and substrate biotremor physics.
## `clear_ray_fn`: `Callable(from: Vector2, to: Vector2) -> bool`
## `cliff_peek_fn`: `Callable(to: Vector2) -> bool`
## Returns `{"player": Player, "trigger": int, "pos": Vector2}` (player is null if nothing sensed).
func scan(heading: float, clear_ray_fn: Callable, cliff_peek_fn: Callable, shade_stealth_mult: float = 1.0) -> Dictionary:
	if _owner_body == null:
		return {"player": null, "trigger": TriggerKind.NONE, "pos": Vector2.ZERO}

	var origin: Vector2 = _owner_body.global_position
	var half_fov: float = deg_to_rad(float(_cfg.get("fov_deg", 124.0))) * 0.5
	var periph_scale: float = float(_cfg.get("peripheral_scale", 0.56))
	var tr_walk: float = float(_cfg.get("tremor_walk", 132.0))
	var tr_sprint: float = float(_cfg.get("tremor_sprint", 215.0))
	var tr_sneak: float = float(_cfg.get("tremor_sneak", 32.0))
	var tr_land: float = float(_cfg.get("tremor_land", 185.0))
	var tr_swing: float = float(_cfg.get("tremor_swing", 160.0))

	var best_player: Player = null
	var best_dist: float = INF
	var best_trigger: int = TriggerKind.NONE
	var best_pos: Vector2 = Vector2.ZERO

	for player: Player in Player.all:
		if not is_instance_valid(player) or player.health.current <= 0.0 or player.veiled():
			continue
		var ppos: Vector2 = player.global_position
		var dist: float = origin.distance_to(ppos)
		var pid: int = player.get_instance_id()

		# Track AgileTraversal airborne -> ground landing shock!
		var prev_h: float = float(_prev_air.get(pid, 0.0))
		var cur_h: float = player.air_height
		_prev_air[pid] = cur_h
		var just_landed: bool = prev_h > 2.2 and cur_h <= 0.5

		# 1. Directional 8-Eye Vision Cone:
		#    - Frontal AME (`<= half_fov`): 100% range
		#    - Lateral ALE/PLE (`half_fov .. 125°`): peripheral motion range (`periph_scale`)
		#    - Rear Opisthosoma Blind Spot (`> 125°`): blocked by its own abdomen -> relies purely on Biotremor!
		var stealth_mult: float = player.stealth.detection_multiplier() * player.stealth.alarm_scale() * shade_stealth_mult
		var ang_diff: float = absf(angle_difference(heading, (ppos - origin).angle()))
		var cone_mult: float = 1.0 if ang_diff <= half_fov else (periph_scale if ang_diff <= deg_to_rad(125.0) else 0.0)
		var effective_sight: float = _sight_range * stealth_mult * cone_mult
		if dist <= effective_sight:
			var has_los: bool = bool(clear_ray_fn.call(origin, ppos)) or bool(cliff_peek_fn.call(ppos))
			if has_los and dist < best_dist:
				best_player = player
				best_dist = dist
				best_trigger = TriggerKind.VISION
				best_pos = ppos
				continue

		# 2. Substrate Biotremor (8 tarsus vibration receptors coupled to MovementRules.surface_noise_scale!)
		var surf_id: String = Terrain.surface_at(ppos)
		var surf_acoustics: float = MovementRules.surface_noise_scale(surf_id)
		var spd: float = player.velocity.length()
		var tremor_reach: float = 0.0
		if just_landed:
			tremor_reach = tr_land * surf_acoustics
		elif player.attack != null and player.attack.is_swinging():
			tremor_reach = tr_swing * surf_acoustics
		elif spd > 8.0 and cur_h <= 1.5:
			if player.stealth != null and player.stealth.sneaking:
				tremor_reach = tr_sneak * surf_acoustics
			elif player.sprinting or spd > 96.0:
				tremor_reach = tr_sprint * surf_acoustics
			else:
				tremor_reach = tr_walk * surf_acoustics * clampf(spd / 72.0, 0.55, 1.15)

		# Solid walls/rocks dampen substrate tremors slightly (`0.72x`) unless clear line
		if tremor_reach > 1.0:
			var clear_line: bool = bool(clear_ray_fn.call(origin, ppos))
			if not clear_line:
				tremor_reach *= 0.72
			if dist <= tremor_reach and dist < best_dist:
				best_player = player
				best_dist = dist
				best_trigger = TriggerKind.TREMOR
				best_pos = ppos

	if best_player != null:
		remember(best_pos, best_trigger)
	return {"player": best_player, "trigger": best_trigger, "pos": best_pos}
