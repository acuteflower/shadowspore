class_name PillarHurtbox
extends HurtboxComponent
## Where a pillar of the boss arena can be struck while it is armed (`ArenaPillar.set_armed`): the weapon hit scan finds it like any other hurtbox and the pillar
## takes the damage as wear.


func take_hit(damage: float, from: Vector2, _knockback: float, _source: int = 0) -> void:
	var pillar: ArenaPillar = get_parent() as ArenaPillar
	if pillar != null:
		pillar.take_hit(damage, from)
