class_name HutTreeHurtbox
extends HurtboxComponent
## The part of the hut's young tree that weapons find (physics layer 5); every hit goes to the `HutTree`.

var tree: Node2D ## the `HutTree` (typed loosely: no circular class dependency)


func take_hit(_damage: float, _from: Vector2, _knockback: float, source: int = 0) -> void:
	if tree != null:
		tree.call("hit", source)
