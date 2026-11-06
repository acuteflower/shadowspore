class_name CrusherHurtbox
extends HurtboxComponent
## The crusher's armour is directional: hits from the front land on the horn collar (a quarter of the damage), hits from behind find the exposed void core (three times).
## The factor depends on where the attacker stood (`from`) against the crusher's facing, so every weapon, tool and enemy projectile is handled the same way.


func take_hit(damage: float, from: Vector2, knockback: float, source: int = 0) -> void:
	var crusher: VoidCrusher = get_parent() as VoidCrusher
	if crusher != null:
		damage = maxf(1.0, roundf(damage * crusher.damage_factor(from)))
	super(damage, from, knockback, source)
