class_name HurtboxComponent
extends Area2D
## Where a body can be hit (physics layer 5). Weapon hit scans find these and call take_hit on the host.

@export var health: HealthComponent


## Finds the sibling HealthComponent when none was assigned in the inspector.
func _ready() -> void:
	if health == null:
		health = get_node_or_null("../HealthComponent") as HealthComponent


func take_hit(damage: float, from: Vector2, knockback: float, source: int = 0) -> void:
	if health:
		health.take_damage(damage, from, knockback, source)
