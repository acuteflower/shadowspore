class_name Rock
extends WorldProp
## A big rock with glowing crystals, veins, runes and fungi (the glow sprite, see WorldProp): solid, broken up with a pickaxe (hit by hit it shrinks to a rubble pile, the stone
## drops out of it), and over the days it grows back, one slot a day (data/plants.json).

const CHIPS: Array[Color] = [Color("665f94"), Color("8a83b8"), Color("47436f")]
const LIGHT_COLOR: Color = Color("9a8cff") ## the crystals and veins light the ground a little at night
const REGROW_BURST: Array[Color] = [Color("d9c8ff"), Color("78f4e6")]

@onready var _body: StaticBody2D = $Body
@onready var _body_shape: CollisionShape2D = $Body/Shape


## The chips that fly off: the stone's, or the colours the data names (`chips`, hex): iron ore throws rust and stone.
func _chips() -> Array:
	var named: Array = _spec.get("chips", []) as Array
	if named.is_empty():
		return CHIPS
	var colors: Array[Color] = []
	for hex: Variant in named:
		colors.append(Color(String(hex)))
	return colors


func _setup_prop() -> void:
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(_radius * 1.5, 7.0)
	_body_shape.shape = rect
	_body_shape.position = Vector2(0, -3.5)


func apply_state(new_state: Dictionary, fx: String) -> void:
	state = new_state
	var total: int = slots()
	var used: int = int(state.get("h", 0))
	var stage: int = 3 if used >= total else (0 if used * 3 < total else (1 if used * 3 < total * 2 else 2))
	_sprite.texture = load(String(_spec.texture)) as Texture2D
	_sprite.hframes = int(_spec.columns)
	_sprite.vframes = int(_spec.rows)
	_sprite.frame = variant + stage * int(_spec.columns)
	_sync_glow(true)
	var lights: Array = _spec.get("light", [])
	var energy: float = float(lights[variant]) if variant < lights.size() else 0.0
	_set_light(energy > 0.0 and stage < 3, LIGHT_COLOR, int(_radius * 0.9), energy)
	_body_shape.set_deferred("disabled", stage == 3) ## rubble can be walked over
	_hurtbox.set_deferred("monitorable", stage != 3)
	match fx:
		"rustle":
			_rustle(randf_range(-1.0, 1.0), 0.04) ## other weapons only make it ring
		"hit":
			_rustle(randf_range(-1.0, 1.0), 0.05)
			_burst(7, _chips(), 46.0, Vector2(0, -_radius * 0.8))
			Sfx.at(self, "pick_rock", global_position, -2.0, 0.06)
		"strip":
			_rustle(randf_range(-1.0, 1.0), 0.07)
			_burst(16, _chips(), 60.0, Vector2(0, -_radius * 0.6))
			Sfx.at(self, "rock_break", global_position, -1.0, 0.05)
		"regrow":
			_burst(6, REGROW_BURST, 0.0)
