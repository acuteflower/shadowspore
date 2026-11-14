class_name QuartzGolemHurtbox
extends HurtboxComponent
## Mining pickaxes fracture the Quartz Golem's crystal-sandstone seams for +35% bonus damage,
## while swords and spells still deal full 1.0x damage.


func take_hit(damage: float, from: Vector2, knockback: float, source: int = 0) -> void:
	var golem: Node = get_parent()
	if golem != null and source != 0:
		for player: Player in Player.all:
			if player.name.to_int() == source:
				var stack: Dictionary = player.inventory.active_stack()
				var tool_id: String = String(Items.definition(stack).get("tool", ""))
				if tool_id == "pickaxe":
					var mult: float = float(golem.call("pickaxe_multiplier")) if golem.has_method("pickaxe_multiplier") else 1.35
					damage = maxf(1.0, roundf(damage * mult))
					if golem.has_method("note_pickaxe_hit"):
						golem.call("note_pickaxe_hit", from)
				break
	super(damage, from, knockback, source)
