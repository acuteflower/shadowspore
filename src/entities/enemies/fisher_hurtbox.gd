class_name FisherHurtbox
extends HurtboxComponent
## The Lichtfischer has two places that can be hit: the lantern (`kind` "lure": the weak point, it hangs in the air and breaks a casting) and the open maw
## (`kind` "body": only reachable while it is up for a bite, and softest while it gapes). A sweep that overlaps both counts once.

@export var kind: String = "body"


func take_hit(damage: float, from: Vector2, knockback: float, source: int = 0) -> void:
	var fisher: LightFisher = get_parent() as LightFisher
	if fisher == null:
		super(damage, from, knockback, source)
		return
	if not fisher.accept_hit(kind, source):
		return
	damage = maxf(1.0, roundf(damage * fisher.damage_factor(kind)))
	super(damage, from, knockback, source)
