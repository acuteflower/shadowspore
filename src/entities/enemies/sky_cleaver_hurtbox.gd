class_name SkyCleaverHurtbox
extends HurtboxComponent
## Mornath's hurtbox: every blow counts by the factor the fight sets (`SkyCleaver.armour`): braced for a shot he is harder to hurt, tired after the rain
## and down after the chase he is soft, so every attack he survives gives the players a window.


func take_hit(damage: float, from: Vector2, knockback: float, source: int = 0) -> void:
	var boss: SkyCleaver = get_parent() as SkyCleaver
	if boss != null:
		damage = maxf(1.0, roundf(damage * boss.armour))
	super(damage, from, knockback, source)
