extends Node
## Prints where the clover fields are around a tile: `-- --at=x,y [--radius=3]` (chunks). Headless is fine.
const WORLD: PackedScene = preload("res://src/world/world_level.tscn")
class EmptyWorld:
	extends WorldLevel
	func _spawn_player(_id: int) -> void: pass
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	var tile: Vector2 = Vector2(520, 520)
	var radius: int = 3
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--at="):
			var parts: PackedStringArray = arg.trim_prefix("--at=").split(",")
			tile = Vector2(float(parts[0]), float(parts[1]))
		if arg.begins_with("--radius="): radius = int(arg.trim_prefix("--radius="))
	var world: WorldLevel = WORLD.instantiate() as WorldLevel
	world.set_script(EmptyWorld)
	add_child(world)
	var cell: Vector2i = Vector2i((tile * 16.0 / 512.0).floor())
	for dy: int in range(-radius, radius + 1):
		for dx: int in range(-radius, radius + 1):
			var c: Vector2i = cell + Vector2i(dx, dy)
			if not world._chunks.has(c): world._load_chunk(c)
			for field: CloverField in (world._chunks[c] as WorldLevel.Chunk).clover:
				print("CLOVER tile ", (field.position / 16.0).round(), " radius ", field.radius)
	get_tree().quit()
