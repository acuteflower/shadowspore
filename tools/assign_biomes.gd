extends SceneTree
## Assign the shared meadow biome; preserve all region ids, boundaries and area names.
## Godot --headless --path . --script tools/assign_biomes.gd

func _init() -> void:
	var biomes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/biomes.json"))
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_map.json"))
	data["biome"] = "meadow"
	for area: Dictionary in data.supers:
		if not area.has("name"):
			area["name"] = String((biomes.get(String(area.biome), biomes["meadow"]) as Dictionary).name)
		area["biome"] = "meadow"
		print("area %d: %s -> meadow" % [int(area.id), String(area.name)])
	var file: FileAccess = FileAccess.open("res://data/world_map.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	quit()
