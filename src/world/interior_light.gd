class_name InteriorLight
extends PointLight2D
## A light inside an interior: always on (unlike `NightLight`), a flat dithered pool like the others. `flicker` makes it dance (a fire), `day_only` ties it to the
## daylight (a window): it fades out as the evening comes. Placed from data/interiors.json "lights" and the props' `light`.

@export var radius: int = 60
@export var squash: float = 0.8
@export var base_energy: float = 1.0
@export var glow_color: Color = Color.WHITE
@export var flicker: float = 0.0
@export var day_only: bool = false

var _phase: float = 0.0


func _ready() -> void:
	var variant: int = absi(int(position.x * 7.0 + position.y * 13.0)) % 3
	texture = LightTexture.get_texture(radius * 2, squash, variant)
	color = glow_color
	_phase = fposmod(position.x * 0.37 + position.y * 0.71, TAU)


func _process(_delta: float) -> void:
	var t: float = Time.get_ticks_msec() * 0.001
	var dance: float = 1.0 + flicker * (0.5 * sin(t * 11.0 + _phase) + 0.3 * sin(t * 17.3 + _phase * 2.0) + 0.2 * sin(t * 4.1))
	var breath: float = 1.0 + 0.05 * sin(t * 1.3 + _phase)
	energy = base_energy * dance * breath * ((1.0 - TimeManager.night_amount()) if day_only else 1.0)
