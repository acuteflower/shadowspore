class_name EnemyScaling
extends RefCounted
## An enemy definition (data/enemies.json) made tougher: `max_health` times `health_scale`, every `damage` in it (melee, grapple, wave, scream) times `damage_scale`.
## The mine scales its enemies with depth (`MineManager.health_scale`); the result is a copy, the shared table stays as it is.


static func scaled(def: Dictionary, health_scale: float, damage_scale: float) -> Dictionary:
	if is_equal_approx(health_scale, 1.0) and is_equal_approx(damage_scale, 1.0):
		return def
	var out: Dictionary = def.duplicate(true)
	out["max_health"] = maxf(1.0, roundf(float(def["max_health"]) * health_scale))
	_damage(out, damage_scale)
	return out


static func _damage(node: Variant, factor: float) -> void:
	if node is Dictionary:
		var dict: Dictionary = node as Dictionary
		for key: Variant in dict.keys():
			if key == "damage":
				dict[key] = maxf(1.0, roundf(float(dict[key]) * factor))
			else:
				_damage(dict[key], factor)
