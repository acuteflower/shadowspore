class_name WaterPlantCut
extends Node2D
## The sickle's hold on one river plant (reeds, shore blooms, ferns, lilies, pads, hornwort; data/harvest.json "water_plant"): a small
## hurtbox on physics layer 5 over the plant's sprite. The host counts the blows (`WorldLevel.harvest_field_hit`), the plant sways for
## each one and is gone at the last; it grows back at sunrise. The state is kept under `key` ("w:x,y") and shown by every peer.
const HARVEST_LAYER: int = 1 << 4
const RADIUS: float = 9.0

var key: String = ""
var level: WorldLevel
var cut: bool = false
var plant: Sprite2D
var _harvest: HarvestHurtbox
var _tween: Tween


func setup(sprite: Sprite2D) -> void:
	plant = sprite
	position = sprite.position
	name = "Cut"
	key = "w:%d,%d" % [roundi(sprite.position.x), roundi(sprite.position.y)]
	_harvest = HarvestHurtbox.new()
	_harvest.name = "Harvest"
	_harvest.harvest_target = self
	_harvest.collision_layer = HARVEST_LAYER
	_harvest.collision_mask = 0
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = RADIUS
	var shape: CollisionShape2D = CollisionShape2D.new()
	shape.shape = circle
	shape.position = Vector2(0.0, -9.0)
	_harvest.add_child(shape)
	add_child(_harvest)


func _enter_tree() -> void:
	level = get_tree().get_first_node_in_group("world") as WorldLevel
	if level != null and key != "":
		level.call("_register_harvest", self)


func _exit_tree() -> void:
	if level != null and is_instance_valid(level):
		level.call("_unregister_harvest", self)


func spec() -> Dictionary:
	return DataRegistry.table("harvest").get("water_plant", {}) as Dictionary


func is_depleted() -> bool:
	return cut


func harvest_hit(source: int) -> void:
	if level != null:
		level.harvest_field_hit(self, source)


## Everyone: the host's state. `fx` "hit" / "rustle" sways the plant, "strip" takes it away, "regrow" brings it back.
func apply_harvest(state: Dictionary, fx: String, _at: Vector2) -> void:
	cut = bool(state.get("f", 0))
	if is_instance_valid(plant):
		plant.visible = not cut
	_harvest.collision_layer = 0 if cut else HARVEST_LAYER
	if fx == "" or fx == "regrow" or cut or not is_instance_valid(plant):
		return
	if _tween != null:
		_tween.kill()
	plant.rotation = 0.14 if fx == "hit" else 0.07
	_tween = create_tween().set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(plant, "rotation", 0.0, 0.6)
