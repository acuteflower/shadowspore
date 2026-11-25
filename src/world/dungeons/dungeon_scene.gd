class_name DungeonScene
extends Node2D
## Base class for every standalone `.tscn` Dungeon scene (docs/dungeon_konzept.md Section 6.2).
## Mounted inside `PocketSpace.Lane.DUNGEON` under `DungeonManager`, so each dungeon keeps
## 100% custom visuals, lighting, shaders, props, mechanics, and enemy choreography while
## preserving `ZoneWorld`, coop Option B, and `ZoneCoop` visibility isolation.

signal objective_updated(text: String, progress: float)

@export var dungeon_id: String = ""
@export var ambient: Color = Color(0.32, 0.44, 0.56, 1.0)
@export var bounds_local: Rect2 = Rect2(0.0, 0.0, 2368.0, 1856.0)
@export var start_spawn_local: Vector2 = Vector2(224.0, 320.0)
@export var boss_title: String = ""

var manager: Node = null ## DungeonManager
var slot_index: int = -1
var run_seed: int = 0
var player_count: int = 1
var active_peers: PackedInt32Array = PackedInt32Array()
var checkpoint_local: Vector2 = Vector2.ZERO
var objective_text: String = ""
var progress_ratio: float = -1.0 ## >= 0 draws a 0..100% progress bar (swarm); -1 shows objective text only
var bonus_part_broken: bool = false
var completed: bool = false

var _spawned_enemies: Array[Node] = []
var _exit_seal: Node2D = null


func setup_instance(p_manager: Node, p_slot: int, p_seed: int, p_peers: PackedInt32Array) -> void:
	manager = p_manager
	slot_index = p_slot
	run_seed = p_seed
	active_peers = p_peers
	player_count = maxi(p_peers.size(), 1)
	checkpoint_local = start_spawn_local


func start_run() -> void:
	pass


func on_boss_reset() -> void:
	pass


func surface_at_local(_local_pos: Vector2) -> String:
	return "stone"


func navigation_floor_local(local_pos: Vector2) -> bool:
	return bounds_local.has_point(local_pos)


func world_bounds() -> Rect2:
	return Rect2(global_position + bounds_local.position, bounds_local.size)


func checkpoint_world() -> Vector2:
	return global_position + checkpoint_local


func start_spawn_world(peer_index: int = 0) -> Vector2:
	var spread: Array[Vector2] = [Vector2(0, 0), Vector2(-24, 14), Vector2(24, 14), Vector2(0, 28)]
	return global_position + start_spawn_local + spread[clampi(peer_index, 0, spread.size() - 1)]


func set_checkpoint(local_pos: Vector2) -> void:
	checkpoint_local = local_pos


func set_objective(text: String, ratio: float = -1.0) -> void:
	objective_text = text
	progress_ratio = ratio
	objective_updated.emit(text, ratio)
	if manager != null and manager.has_method("host_update_objective") and multiplayer.is_server():
		manager.call("host_update_objective", slot_index, text, ratio)


## Host-only: spawns an enemy into the world's `Enemies` container (so `MultiplayerSpawner`
## and `ZoneCoop` automatically replicate it ONLY to peers inside this dungeon slot!).
func spawn_dungeon_enemy(scene_path: String, local_pos: Vector2, hp_mult: float = 1.0, dmg_mult: float = 1.0) -> Node2D:
	if not multiplayer.is_server() or not ResourceLoader.exists(scene_path):
		return null
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		return null
	var enemy: Node2D = packed.instantiate() as Node2D
	if enemy == null:
		return null
	var world_pos: Vector2 = global_position + local_pos
	enemy.position = world_pos
	if enemy.get("health_scale") != null:
		enemy.set("health_scale", DungeonRules.hp_scale(player_count) * hp_mult)
	if enemy.get("damage_scale") != null:
		enemy.set("damage_scale", DungeonRules.damage_scale(player_count) * dmg_mult)
	if enemy.get("emerge_on_spawn") != null:
		enemy.set("emerge_on_spawn", true)
	var parent_container: Node = _enemy_container()
	parent_container.add_child(enemy, true)
	_spawned_enemies.append(enemy)
	return enemy


func _enemy_container() -> Node:
	if is_inside_tree():
		var world: Node = get_tree().get_first_node_in_group("world")
		if world != null:
			var enemies_node: Node = world.get_node_or_null("Enemies")
			if enemies_node != null:
				return enemies_node
	return self


## Spawns the glowing Steinsetzer Return Seal at `local_pos` after victory.
func spawn_exit_seal(local_pos: Vector2) -> void:
	if _exit_seal != null and is_instance_valid(_exit_seal):
		return
	var seal: DungeonExitSeal = DungeonExitSeal.new()
	seal.position = local_pos
	add_child(seal)
	_exit_seal = seal


## Host-only: completes this dungeon run cleanly.
func finish_victory(reliquary_local_pos: Vector2, exit_local_pos: Vector2) -> void:
	if not multiplayer.is_server() or completed:
		return
	completed = true
	if manager != null and manager.has_method("host_complete_run"):
		manager.call("host_complete_run", slot_index, global_position + reliquary_local_pos, exit_local_pos, bonus_part_broken)


## Cleans up all enemies still alive in this slot when the dungeon unmounts.
func cleanup_instance() -> void:
	if multiplayer.is_server():
		for e: Node in _spawned_enemies:
			if e != null and is_instance_valid(e):
				e.queue_free()
	_spawned_enemies.clear()
	if is_inside_tree():
		get_tree().call_group("boss_bar", "release")
