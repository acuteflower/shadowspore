class_name DungeonExitSeal
extends Interactable
## Glowing Steinsetzer Return Seal spawned in a dungeon arena on victory.
## Pressing E leaves the dungeon cleanly and returns the player to their saved overworld spot.

var _time: float = 0.0
var _light: NightLight = null


func _ready() -> void:
	name = "DungeonExitSeal"
	material = Unlit.material()
	z_index = 4
	_light = NightLight.new()
	_light.radius = 68.0
	_light.squash = 0.72
	_light.base_energy = 0.75
	_light.pulse = 0.18
	_light.glow_color = Color("4df2e0")
	add_child(_light)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func prompt() -> String:
	return "GEWÖLBE VERLASSEN"


func reach_distance(from: Vector2) -> float:
	return maxf(0.0, global_position.distance_to(from) - 24.0)


func prompt_position() -> Vector2:
	return Vector2(0.0, -36.0)


func interact(_player: Player) -> void:
	var dm: DungeonManager = DungeonManager.of(get_tree())
	if dm != null:
		dm.request_leave_dungeon()


func _draw() -> void:
	var pulse: float = 0.78 + 0.22 * sin(_time * 3.8)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.56))
	draw_circle(Vector2.ZERO, 18.0, Color(Color("162638"), 0.85))
	draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 28, Color(Color("4df2e0"), 0.9 * pulse), 2.0)
	draw_arc(Vector2.ZERO, 12.0, _time * 1.4, _time * 1.4 + PI * 1.45, 20, Color(Color("ffd98a"), 0.85), 1.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	## Vertical rising light wisps
	for i: int in 5:
		var u: float = fposmod(_time * 0.75 + float(i) * 0.2, 1.0)
		var x: float = sin(float(i) * 2.1 + _time * 2.0) * 9.0
		var y: float = -4.0 - u * 34.0
		var a: float = sin(u * PI) * 0.85
		draw_rect(Rect2(roundf(x), roundf(y), 2.0, 3.0), Color(Color("d0fff8"), a))
