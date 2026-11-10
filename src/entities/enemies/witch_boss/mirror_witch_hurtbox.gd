class_name MirrorWitchHurtbox
extends HurtboxComponent
## Morwenna's hurtbox: every blow counts by the factor the fight sets (`MirrorWitch.armour`): braced she is harder to hurt, tired after a frenzy
## and staggered out of a broken leech she is soft.


func take_hit(damage: float, from: Vector2, knockback: float, source: int = 0) -> void:
	var boss: MirrorWitch = get_parent() as MirrorWitch
	if boss != null:
		damage = maxf(1.0, roundf(damage * boss.armour))
	super(damage, from, knockback, source)
