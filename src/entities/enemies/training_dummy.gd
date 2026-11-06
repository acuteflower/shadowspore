extends StaticBody2D
## Training target: takes hits, flashes, wobbles, shows damage numbers and resets after "dying".

const RESPAWN_SECONDS: float = 1.5
const HURTBOX_LAYER: int = 16 ## physics layer 5

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _health: HealthComponent = $HealthComponent
@onready var _hurtbox: HurtboxComponent = $Hurtbox


func _ready() -> void:
	_health.damaged.connect(_on_damaged)
	_health.changed.connect(_on_health_changed)
	if multiplayer.is_server():
		_health.died.connect(_on_died)


func _on_damaged(amount: float, from: Vector2, knockback: float) -> void:
	var flash: ShaderMaterial = _sprite.material as ShaderMaterial
	flash.set_shader_parameter("flash", 1.0)
	create_tween().tween_property(flash, "shader_parameter/flash", 0.0, 0.15)
	_sprite.position = (global_position - from).normalized() * clampf(knockback / 20.0, 1.0, 5.0) ## recoil away from the hit
	create_tween().tween_property(_sprite, "position", Vector2.ZERO, 0.12)
	DamageNumber.spawn(get_tree().current_scene, global_position + Vector2(0, -30), amount, (global_position - from).normalized())


func _on_health_changed(current: float, _maximum: float) -> void:
	var alive: bool = current > 0.0
	_sprite.visible = alive
	_hurtbox.collision_layer = HURTBOX_LAYER if alive else 0


func _on_died() -> void:
	await get_tree().create_timer(RESPAWN_SECONDS).timeout
	_health.heal_full()
