class_name FinisherRules
extends RefCounted
## Shadowspore 2.0 — Pure Data-Driven Rules & Spatial Resolver for the V2 Finisher System (`T1`, `T2`, `T4`).
## Evaluates weapon compatibility (`sword_1h`, `sword_rift`, `sword_starlight`),
## the core trigger condition ("Target is Boss OR Ellie is not in combat with any other living enemy"),
## and 8-sector elliptical pair-positioning with wall & deep-water safety checks.

const TABLE_NAME: String = "finishers"
const WORLD_MASK: int = 1 ## Physics Layer 1 (`world`)


static func settings() -> Dictionary:
	return DataRegistry.table(TABLE_NAME).get("settings", {}) as Dictionary


static func move_config(move_id: String) -> Dictionary:
	var moves: Dictionary = DataRegistry.table(TABLE_NAME).get("moves", {}) as Dictionary
	return moves.get(move_id, {}) as Dictionary


static func weapon_supports_finisher(stack: Dictionary) -> bool:
	if stack.is_empty():
		return false
	var def: Dictionary = Items.definition(stack)
	if def.is_empty() or String(def.get("tool", "")) in ["rod", "staff", "can", "hoe", "pickaxe", "axe"]:
		return false
	var wclass: String = String(def.get("weapon_class", ""))
	var allowed: Array = settings().get("weapon_classes", ["sword_1h", "sword_rift", "sword_starlight"]) as Array
	for item: Variant in allowed:
		if String(item) == wclass:
			return true
	return false


static func enemy_def_of(target: Node2D) -> Dictionary:
	if target == null or not is_instance_valid(target):
		return {}
	if target.has_meta("finisher_boss_override") and bool(target.get_meta("finisher_boss_override")):
		var base_id: String = String(target.get("enemy_id")) if target.get("enemy_id") != null else "shadow_spider"
		var copy_def: Dictionary = DataRegistry.get_entry("enemies", base_id).duplicate()
		copy_def["boss"] = true
		return copy_def
	var eid: Variant = target.get("enemy_id")
	if eid is String and String(eid) != "":
		return DataRegistry.get_entry("enemies", String(eid))
	return {}


static func is_target_boss(target: Node2D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target.has_meta("finisher_boss_override") and bool(target.get_meta("finisher_boss_override")):
		return true
	var edef: Dictionary = enemy_def_of(target)
	if bool(edef.get("boss", false)):
		return true
	var loot: Dictionary = edef.get("loot", {}) as Dictionary
	return loot.has("chest")


static func pick_move_for_target(target: Node2D) -> String:
	if target == null or not is_instance_valid(target):
		return ""
	if not target.has_method("begin_finisher_impale"):
		return ""
	var edef: Dictionary = enemy_def_of(target)
	var group_id: String = String(edef.get("finisher_group", ""))
	if group_id == "" and target is ShadowSpider:
		group_id = "arachnid"
	if group_id == "":
		return ""
	var groups: Dictionary = DataRegistry.table(TABLE_NAME).get("groups", {}) as Dictionary
	var pool: Array = groups.get(group_id, []) as Array
	if pool.is_empty():
		return ""
	return String(pool[0])


## True when NO OTHER living enemy (excluding `dying_targets` killed by this swing) is currently
## engaged with `player` OR within `solo_threat_radius` on the same floor (`T2`).
static func is_last_engaged_threat(player: Player, dying_targets: Array[Node2D]) -> bool:
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return false
	var tree: SceneTree = player.get_tree()
	if tree == null:
		return false
	var threat_r: float = float(settings().get("solo_threat_radius", 165.0))
	var threat_r2: float = threat_r * threat_r
	var p_floor: int = _floor_at(tree, player.global_position)

	for node: Node in tree.get_nodes_in_group("predators"):
		var enemy: Node2D = node as Node2D
		if enemy == null or not is_instance_valid(enemy) or not enemy.is_inside_tree():
			continue
		if dying_targets.has(enemy):
			continue
		if enemy.has_method("is_being_finished") and bool(enemy.call("is_being_finished")):
			continue
		var hp: HealthComponent = enemy.get_node_or_null("HealthComponent") as HealthComponent
		if hp != null and hp.current <= 0.0:
			continue
		# Check if this enemy is actively targeting `player` in combat!
		var cur_target: Variant = enemy.get("_target")
		if cur_target == player:
			return false
		# Also block if another hostile predator is nearby on the same floor (unless passive/hidden far away)
		var d2: float = enemy.global_position.distance_squared_to(player.global_position)
		if d2 <= threat_r2:
			var e_floor: int = _floor_at(tree, enemy.global_position)
			if e_floor == p_floor:
				return false
	return true


## True when `player` is in a state that allows starting a finisher at all (alive, free, on foot, not in another special move).
static func player_can_finish(p: Player) -> bool:
	if p == null or not is_instance_valid(p) or p.finisher == null or p.finisher.active():
		return false
	if not p.is_inside_tree() or not p.is_physics_processing():
		return false
	if p.health.current <= 0.0 or p.intro != null or p.story_lock or p.fainting or p.stumbling:
		return false
	if p.swim > 0 or p.climb.active() or p.carry_stone != 0 or (p.agile != null and p.agile.active()):
		return false
	return true


## Host, Finisher V2 "Kern entblößt" (docs/finisher_v2_konzept.md): could a nearby player finish `target` right now?
## 0 = no; 1 = the next sword blow is lethal anyway (the hurtbox then guarantees it, `ShadowSpider.evaluate_hurtbox_hit`); 2 = only E (EXPOSED).
static func ready_kind_for(target: Node2D, health: HealthComponent, exposed: bool) -> int:
	if target == null or health == null or health.current <= 0.0 or not target.is_inside_tree():
		return 0
	if target.has_method("can_accept_finisher") and not bool(target.call("can_accept_finisher")):
		return 0
	if pick_move_for_target(target) == "":
		return 0
	var radius: float = float(settings().get("ready_scan_radius", 120.0))
	var best: int = 0
	for node: Node in target.get_tree().get_nodes_in_group("players"):
		var p: Player = node as Player
		if p == null or not is_instance_valid(p) or p.global_position.distance_to(target.global_position) > radius:
			continue
		if not player_can_finish(p) or p.inventory == null:
			continue
		var stack: Dictionary = p.inventory.active_stack()
		if not weapon_supports_finisher(stack):
			continue
		if not is_target_boss(target) and not is_last_engaged_threat(p, [target]):
			continue
		if health.current <= Items.stat(stack, "damage", 1.0):
			return 1
		if exposed:
			best = 2
	return best


static func _floor_at(tree: SceneTree, pos: Vector2) -> int:
	for world: Node in tree.get_nodes_in_group("world"):
		if world.has_method("navigation_floor"):
			return int(world.call("navigation_floor", pos))
	return 0


static func _is_deep_water_at(tree: SceneTree, pos: Vector2) -> bool:
	for patch: Node in Terrain.patches:
		if patch != null and patch.has_method("is_deep") and bool(patch.call("is_deep", pos)):
			return true
	var surf_id: String = Terrain.surface_at(pos)
	if surf_id == "deep_water":
		return true
	var _unused: SceneTree = tree
	return false


static func _point_clear_for_body(body: CharacterBody2D, goal_pos: Vector2) -> bool:
	if body == null or not body.is_inside_tree():
		return false
	if _is_deep_water_at(body.get_tree(), goal_pos):
		return false
	var xform: Transform2D = body.global_transform
	xform.origin = goal_pos
	return not body.test_move(xform, Vector2.ZERO)


## Computes the 8-sector aligned `(stand_pos, target_pos, sector, dir)` so Ellie's downward plunge
## lands dead-center in the target's carapace without clipping either actor into walls or deep water (`T4`).
static func resolve_pair_positions(player: Player, target: Node2D, move_cfg: Dictionary) -> Dictionary:
	var fail: Dictionary = {"valid": false}
	if player == null or target == null or not player.is_inside_tree() or not target.is_inside_tree():
		return fail
	var tree: SceneTree = player.get_tree()
	if _floor_at(tree, player.global_position) != _floor_at(tree, target.global_position):
		return fail
	if _is_deep_water_at(tree, target.global_position):
		return fail

	var to_target: Vector2 = target.global_position - player.global_position
	if to_target.length_squared() < 0.5:
		to_target = player.facing if player.facing.length_squared() > 0.01 else Vector2.RIGHT
	var base_sector: int = posmod(roundi(to_target.angle() / (PI / 4.0)), 8)

	var scale_mult: float = 1.0
	var rig_node: Node = target.get_node_or_null("Rig")
	if rig_node != null and rig_node.get("_body_scale_mult") != null:
		scale_mult = clampf(float(rig_node.get("_body_scale_mult")), 0.85, 1.6)

	var rx: float = float(move_cfg.get("stand_rx", 14.5)) * lerpf(1.0, scale_mult, 0.5)
	var ry: float = float(move_cfg.get("stand_ry", 10.5)) * lerpf(1.0, scale_mult, 0.5)
	var target_body: CharacterBody2D = target as CharacterBody2D

	# Try exact facing sector first, then +/- 45 deg neighbors if a rock/pillar/tree blocks the exact angle!
	for cand_sec: int in [base_sector, posmod(base_sector + 1, 8), posmod(base_sector + 7, 8)]:
		var dir: Vector2 = Vector2.from_angle(float(cand_sec) * (PI / 4.0))
		var stand_offset: Vector2 = Vector2(dir.x * rx, dir.y * ry)
		var t_pos: Vector2 = target.global_position
		var p_pos: Vector2 = (t_pos - stand_offset).round()

		if _point_clear_for_body(player, p_pos) and _line_clear(player, player.global_position, p_pos):
			return {
				"valid": true,
				"sector": cand_sec,
				"dir": dir,
				"stand_pos": p_pos,
				"target_pos": t_pos.round(),
			}

		for pull_px: float in [6.0, 10.0, 14.0]:
			var alt_t: Vector2 = (target.global_position + dir * pull_px).round()
			var alt_p: Vector2 = (alt_t - stand_offset).round()
			if (target_body == null or _point_clear_for_body(target_body, alt_t)) and _point_clear_for_body(player, alt_p):
				return {
					"valid": true,
					"sector": cand_sec,
					"dir": dir,
					"stand_pos": alt_p,
					"target_pos": alt_t,
				}
			var alt_t2: Vector2 = (target.global_position - dir * pull_px).round()
			var alt_p2: Vector2 = (alt_t2 - stand_offset).round()
			if (target_body == null or _point_clear_for_body(target_body, alt_t2)) and _point_clear_for_body(player, alt_p2):
				return {
					"valid": true,
					"sector": cand_sec,
					"dir": dir,
					"stand_pos": alt_p2,
					"target_pos": alt_t2,
				}

	return fail


static func _line_clear(player: Player, a: Vector2, b: Vector2) -> bool:
	if a.distance_squared_to(b) < 4.0:
		return true
	var space: PhysicsDirectSpaceState2D = player.get_world_2d().direct_space_state
	var q: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(a, b, WORLD_MASK)
	q.exclude = [player.get_rid()]
	return space.intersect_ray(q).is_empty()
