class_name BurnFx
extends Node2D
## A burning player (the `burn` status effect, src/components/status_effects.gd): tongues of pink-violet fire lick up from the legs, the back and the shoulders and
## sparks rise off her; the fire dies down in the last second. Child of the player (origin = her feet), unshaded and additive, every peer draws its own; the same
## `PixelFlames.flame` as the fire of Mornath's last phase, so they belong together.

const ANCHORS: Array[Vector3] = [Vector3(-4.0, -7.0, 6.0), Vector3(4.0, -8.0, 6.0), Vector3(0.0, -18.0, 8.0), Vector3(-6.0, -27.0, 5.0), Vector3(6.0, -28.0, 5.0), Vector3(0.0, -35.0, 5.0)] ## x, y, width
const TICK: float = 1.0 / 20.0

var _effects: StatusEffects
var _t: float = 0.0
var _acc: float = 0.0


func _ready() -> void:
	z_index = 3
	var add: CanvasItemMaterial = CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = add


func bind(effects: StatusEffects) -> void:
	_effects = effects


func _process(delta: float) -> void:
	_t += delta
	_acc += delta
	if _acc >= TICK:
		_acc = 0.0
		queue_redraw()


func _draw() -> void:
	if _effects == null or not is_instance_valid(_effects):
		return
	var life: float = smoothstep(0.0, 1.0, _effects.left("burn")) ## it dies down in the last second
	var born: float = clampf(_t / 0.25, 0.0, 1.0)
	var strength: float = life * born
	if strength <= 0.02:
		return
	for i: int in ANCHORS.size():
		var a: Vector3 = ANCHORS[i]
		var salt: float = float(i) * 7.3 + 1.1
		var beat: float = 0.55 + 0.45 * sin(_t * 5.0 + salt)
		PixelFlames.flame(self, Vector2(a.x, a.y), a.z * (0.8 + 0.3 * beat), (7.0 + 5.0 * beat) * (0.5 + 0.5 * strength), _t, salt, strength * 0.85)
