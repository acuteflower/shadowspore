class_name BlinkComponent
extends Node
## Void blink: cooldown bookkeeping and the visuals. The player does the actual movement.

signal cooldown_changed(left: float, total: float)

const FX_SCENE: PackedScene = preload("res://src/fx/blink_fx.tscn")
const ARRIVE_TINT: Color = Color(0.55, 0.25, 1.0)

@export var blink_range: float = 96.0 ## px, fixed (upgradeable later)
@export var cooldown: float = 5.0 ## seconds
@export var min_distance: float = 8.0 ## shorter blinks (wall right in front) are cancelled

var cooldown_left: float = 0.0
var total: float = 0.0 ## the length of the cooldown that runs now (the talismans can shorten `cooldown`)


func _process(delta: float) -> void:
	if cooldown_left > 0.0:
		cooldown_left = maxf(cooldown_left - delta, 0.0)
		cooldown_changed.emit(cooldown_left, total)


func is_ready() -> bool:
	return cooldown_left <= 0.0


func start_cooldown() -> void:
	var talismans: TalismanComponent = get_node_or_null("../TalismanComponent") as TalismanComponent
	total = cooldown * (talismans.blink_scale() if talismans != null else 1.0) ## Rissfeder and the like
	cooldown_left = total
	cooldown_changed.emit(cooldown_left, total)


## Rifts at both ends, a shard burst and a violet flash on arrival.
func play_effects(sprite: Sprite2D, from: Vector2, to: Vector2) -> void:
	var world: Node = get_tree().current_scene
	for point: Vector2 in [from, to]:
		var fx: Node2D = FX_SCENE.instantiate() as Node2D
		fx.global_position = point
		world.add_child(fx)

	sprite.modulate = ARRIVE_TINT
	create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.35)
