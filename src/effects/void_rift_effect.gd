class_name VoidRiftEffect
extends Node
## The void rift effect (Leere-Trank). Host: opens a rift at the player's position that
## deals void damage to enemies, heals the player via lifesteal, and may slow enemies.
## The rift lasts several seconds and grows larger with higher potion tiers.

signal rift_opened(centre: Vector2, radius: float, duration: float)
signal rift_closed(centre: Vector2)

var _active: bool = false
var _centre: Vector2 = Vector2.ZERO
var _radius: float = 128.0
var _dps: float = 8.0
var _lifesteal: float = 0.0
var _self_dps: float = 2.0
var _slow: float = 0.0
var _pull: float = 0.0
var _remaining: float = 0.0
var _tick_timer: float = 0.0

func open(centre: Vector2, radius: float, dps: float, lifesteal: float, self_dps: float, slow: float, pull: float, duration: float) -> void:
	_active = true
	_centre = centre
	_radius = radius
	_dps = dps
	_lifesteal = lifesteal
	_self_dps = self_dps
	_slow = slow
	_pull = pull
	_remaining = duration
	_tick_timer = 0.0
	rift_opened.emit(centre, radius, duration)

func close() -> void:
	if _active:
		_active = false
		rift_closed.emit(_centre)

func _process(delta: float) -> void:
	if not _active:
		return
	_remaining -= delta
	_tick_timer += delta
	if _tick_timer >= 0.5:
		_tick_timer = 0.0
		_tick()
	if _remaining <= 0.0:
		close()

func _tick() -> void:
	# Find enemies in radius and deal void damage
	var world: Node = get_tree().get_first_node_in_group("world")
	if world == null:
		return
	var player: Node2D = get_tree().get_first_node_in_group("players") as Node2D
	var enemies: Array[Node] = get_tree().get_nodes_in_group("enemies")
	for enemy: Node in enemies:
		if not is_instance_valid(enemy) or not (enemy is Node2D):
			continue
		var enemy_2d: Node2D = enemy as Node2D
		var dist: float = enemy_2d.global_position.distance_to(_centre)
		if dist <= _radius:
			var damage: float = _dps * 0.5  # per tick
			if enemy.has_method("take_damage"):
				enemy.take_damage(damage, "void", 0)
			# Lifesteal: heal player
			if player != null and player.has_method("heal"):
				player.heal(damage * _lifesteal)
			# Slow enemies
			if _slow > 0.0 and enemy.has_method("apply_slow"):
				enemy.apply_slow(_slow, 1.0)
	# Self-damage to player
	if player != null and _self_dps > 0.0:
		var dist: float = player.global_position.distance_to(_centre)
		if dist <= _radius and player.has_method("take_damage"):
			player.take_damage(_self_dps * 0.5, "void", 0)

func is_active() -> bool:
	return _active

func get_remaining() -> float:
	return maxf(_remaining, 0.0)