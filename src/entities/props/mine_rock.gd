class_name MineRock
extends Rock
## A rock in the mine (kinds `mine_rock` and `mine_collapse` in data/plants.json: the world's rocks, same pictures and rules: pickaxe, hit by hit down to
## rubble, the stone drops out). The state lives in `WorldLevel` like every prop's, keyed by the rock's tile in the mine's far-off slot, so saving, joining,
## host decisions and growing back come for free. Differences: the crystals and veins always glow (it is always dark down here) and light the floor
## with a lamp of their own that does not wait for night.

var _mine_light: InteriorLight


## The glow is always strong: the mine has no day.
func set_night(_amount: float) -> void:
	super(0.9)


func _set_light(on: bool, color: Color, radius: int, energy: float) -> void:
	if on and _mine_light == null:
		_mine_light = InteriorLight.new()
		_mine_light.radius = radius + 6
		_mine_light.squash = 0.7
		_mine_light.base_energy = energy * 0.8
		_mine_light.glow_color = color
		_mine_light.flicker = 0.05
		_mine_light.position = Vector2(0, -6)
		add_child(_mine_light)
	if _mine_light != null:
		_mine_light.visible = on
		_mine_light.enabled = on
