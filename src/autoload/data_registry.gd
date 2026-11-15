extends Node
## Loads every res://data/*.json into memory, keyed by file name (e.g. "items").

const DATA_DIR: String = "res://data/"

var _tables: Dictionary = {}
var _assets: Dictionary = {}


func _ready() -> void:
	for file: String in DirAccess.get_files_at(DATA_DIR):
		if file.get_extension() != "json":
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_DIR + file))
		if parsed is Dictionary:
			_tables[file.get_basename()] = parsed
		else:
			push_error("DataRegistry: %s is not a JSON object" % file)


func table(name: String) -> Dictionary:
	return _tables.get(name, {})


func get_entry(table: String, id: String) -> Dictionary:
	return (_tables.get(table, {}) as Dictionary).get(id, {})


func asset(path: String) -> Resource:
	if path.is_empty():
		return null
	var cached: Variant = _assets.get(path)
	if cached != null:
		return cached as Resource
	if not ResourceLoader.exists(path):
		return null
	var res: Resource = load(path)
	if res != null:
		_assets[path] = res
	return res


func tex(path: String) -> Texture2D:
	return asset(path) as Texture2D


func scene(path: String) -> PackedScene:
	return asset(path) as PackedScene


func audio(path: String) -> AudioStream:
	return asset(path) as AudioStream
