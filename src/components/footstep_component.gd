class_name FootstepComponent
extends Node2D
## Per-step feedback from the surface data (data/terrain.json): puffs or splashes, and
## footprints on soft ground. Called by the player at every footfall, on every peer.

const FOOTPRINT: Texture2D = preload("res://assets/fx/footprint.png")
const FOOTPRINT_Z: int = -9 ## above the ground layer, below all entities
const FOOT_OFFSET: float = 2.5 ## px, feet alternate left/right of the walking line

var _left_foot: bool = false

@onready var _puff: CPUParticles2D = $Puff


## `quiet` (sneaking) skips the puff but still leaves footprints.
func step(surface: Dictionary, velocity: Vector2, quiet: bool) -> void:
	_left_foot = not _left_foot
	var fx: Dictionary = surface.get("step", {})
	if not fx.is_empty() and not quiet:
		_emit(fx, velocity)
	var print_data: Dictionary = surface.get("footprint", {})
	if not print_data.is_empty():
		_leave_footprint(print_data, velocity)


func contact_position(velocity: Vector2) -> Vector2:
	var dir: Vector2 = velocity.normalized()
	return (global_position + Vector2(-dir.y, dir.x) * (FOOT_OFFSET if _left_foot else -FOOT_OFFSET)).round()

func _emit(fx: Dictionary, velocity: Vector2) -> void:
	_puff.color = Color(String(fx.get("color", "#ffffff")))
	_puff.amount = int(fx.get("amount", 3))
	_puff.position = to_local(contact_position(velocity))
	if fx.get("kind", "puff") == "splash":
		_puff.direction = Vector2.UP
		_puff.spread = 55.0
		_puff.gravity = Vector2(0, 240)
		_puff.amount = clampi(roundi(velocity.length() / 18.0), 2, 7)
		_puff.initial_velocity_min = lerpf(14.0, 40.0, clampf(velocity.length() / 90.0, 0.0, 1.0))
		_puff.initial_velocity_max = _puff.initial_velocity_min * 1.5
		_puff.damping_min = 0.0
		_puff.damping_max = 0.0
		_puff.lifetime = 0.4
	else:
		_puff.direction = -velocity.normalized()
		_puff.spread = 40.0
		_puff.gravity = Vector2.ZERO
		_puff.initial_velocity_min = 15.0
		_puff.initial_velocity_max = 35.0
		_puff.damping_min = 50.0
		_puff.damping_max = 70.0
		_puff.lifetime = 0.3
	_puff.restart()


func _leave_footprint(data: Dictionary, velocity: Vector2) -> void:
	var dir: Vector2 = velocity.normalized()
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = FOOTPRINT
	sprite.modulate = Color(String(data.get("color", "#000000")))
	sprite.modulate.a = 0.7
	sprite.rotation = roundf(dir.angle() / (PI / 4.0)) * (PI / 4.0) ## 8 directions keep the pixels clean
	sprite.z_index = FOOTPRINT_Z
	get_tree().current_scene.add_child(sprite)
	sprite.global_position = (global_position + Vector2(-dir.y, dir.x) * (FOOT_OFFSET if _left_foot else -FOOT_OFFSET)).round()

	var seconds: float = float(data.get("seconds", 10.0))
	var tween: Tween = sprite.create_tween()
	tween.tween_interval(seconds * 0.6)
	tween.tween_property(sprite, "modulate:a", 0.0, seconds * 0.4)
	tween.tween_callback(sprite.queue_free)
