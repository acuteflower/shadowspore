class_name WorldEdits
extends RefCounted
## Authored map layer, independent of harvested props and the player's save.
const PATH: String = "user://world_edits.json"
var props: Dictionary = {}
var terrain: Dictionary = {}

static func key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]

static func cell(key_string: String) -> Vector2i:
	return Vector2i(int(key_string.get_slice(",", 0)), int(key_string.get_slice(",", 1)))

func data() -> Dictionary:
	return {"version": 1, "map": map_signature(), "props": props.duplicate(true), "terrain": terrain.duplicate(true)}

## Only actual layout changes invalidate authored placements; names/biomes are metadata.
static func map_signature(source: Dictionary = {}) -> String:
	var map: Dictionary = DataRegistry.table("world_map") if source.is_empty() else source
	var layout: Dictionary = {}
	for field: String in ["seed", "cell", "world_tiles", "start_region", "start", "regions", "grid"]:
		layout[field] = map.get(field)
	var areas: Array[Dictionary] = []
	for area: Dictionary in map.get("supers", []):
		var geometry: Dictionary = area.duplicate(true)
		geometry.erase("biome")
		geometry.erase("name")
		areas.append(geometry)
	layout["supers"] = areas
	return JSON.stringify(layout).sha256_text()

static func compatible_map(digest: String) -> bool:
	var signature: String = map_signature()
	if digest == signature or digest == FileAccess.get_sha256("res://data/world_map.json"):
		return true
	for previous: Dictionary in DataRegistry.table("world_map").get("editor_compatible_maps", []):
		if String(previous.get("hash", "")) == digest and String(previous.get("layout", "")) == signature:
			return true
	return false

func assign(raw: Dictionary) -> void:
	props = (raw.get("props", {}) as Dictionary).duplicate(true)
	terrain = (raw.get("terrain", {}) as Dictionary).duplicate(true)

func read(path: String = PATH) -> void:
	if not FileAccess.file_exists(path):
		return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if raw is Dictionary and int(raw.get("version", 0)) == 1 and compatible_map(String(raw.get("map", ""))):
		assign(raw)

func save(path: String = PATH) -> bool:
	var file: FileAccess = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data(), "\t"))
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK:
		return false
	return DirAccess.rename_absolute(path + ".tmp", path) == OK
