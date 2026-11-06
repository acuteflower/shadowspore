class_name HarvestHurtbox
extends HurtboxComponent
## The part of a plant that weapons find (physics layer 5). Instead of health it hands every hit
## to the world, which checks the tool and decides what drops (host only, like all hits).

var owner_prop: WorldProp


func take_hit(_damage: float, _from: Vector2, _knockback: float, source: int = 0) -> void:
	if owner_prop != null:
		owner_prop.harvest_hit(source)
