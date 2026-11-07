class_name HarvestHurtbox
extends HurtboxComponent
## The part of a plant that weapons find (physics layer 5). Instead of health it hands every hit
## to the world, which checks the tool and decides what drops (host only, like all hits). Props set
## `owner_prop`; clover fields and fallen logs set `harvest_target` (any node with `harvest_hit`).

var owner_prop: WorldProp
var harvest_target: Object


## What the hit belongs to: the prop, or the field / log that set `harvest_target`. The cursor asks this too.
func harvest_owner() -> Object:
	var target: Object = harvest_target
	if owner_prop != null:
		target = owner_prop
	return target


func take_hit(_damage: float, _from: Vector2, _knockback: float, source: int = 0) -> void:
	var target: Object = harvest_owner()
	if target != null:
		target.call("harvest_hit", source)
