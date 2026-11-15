class_name AurelithHurtbox
extends HurtboxComponent
## Hurtbox for Aurelith, Herz des Sonnenquarzes.
## Pure weapon & spell focus: zero extra pickaxe multiplier (1.0x parity across all weapons and wands).
## Scales incoming hits by `boss.armour` (harder while braced, softer during Overheat Stagger).


func take_hit(damage: float, from: Vector2, knockback: float, source: int = 0) -> void:
	var boss: Aurelith = get_parent() as Aurelith
	if boss != null:
		if boss.mode != Aurelith.Mode.ACTIVE or not boss.act_hittable:
			return
		damage = maxf(1.0, roundf(damage * boss.armour))
	super(damage, from, knockback, source)
