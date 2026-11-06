extends SceneTree
## Freezes a generated region map as data/world_map.json:
##   Godot --headless --path . --script tools/bake_world_map.gd -- seed=4
## After that the game plays on the file; re-run only to deliberately replace the world.

func _init() -> void:
	var world_seed: int = 4
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("seed="):
			world_seed = arg.substr(5).to_int()
	var map: RegionMap = RegionMap.new(world_seed)
	var file: FileAccess = FileAccess.open("res://data/world_map.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(map.to_data()))
	file.close()
	print("baked seed %d: %d regions, %d super regions" % [world_seed, map.regions.size(), map.supers.size()])
	quit()
