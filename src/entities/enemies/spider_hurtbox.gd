class_name SpiderHurtbox
extends HurtboxComponent
## Directional V2 hurtbox for `ShadowSpider`: routes weapon & spell impacts through `EnemyPostureComponent`
## so flanking into the rear Opisthosoma (`1.25x`) and striking during `EXPOSED` (`1.35x`) reward Movement-2.0 footwork.


func take_hit(damage: float, from: Vector2, knockback: float, source: int = 0) -> void:
	var spider: Node = get_parent()
	if spider != null and spider.has_method("evaluate_hurtbox_hit"):
		damage = float(spider.call("evaluate_hurtbox_hit", damage, from, knockback))
	super(damage, from, knockback, source)
