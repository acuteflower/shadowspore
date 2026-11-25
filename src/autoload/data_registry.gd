extends Node
## Loads every res://data/*.json into memory, keyed by file name (e.g. "items").

const DATA_DIR: String = "res://data/"

var _tables: Dictionary = {}
var _assets: Dictionary = {}
var _json: Dictionary = {}
var _json_lock: Mutex = Mutex.new()


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


## A JSON object below res://data/ by relative path (e.g. "world/continents/main.json"), loaded once and cached.
## For nested data that `table()` does not see (it only reads the top folder). Missing or broken file = {}.
## Safe to call from workers (mutex), but build anything heavy from it on the main thread first.
func json(rel_path: String) -> Dictionary:
	_json_lock.lock()
	var cached: Variant = _json.get(rel_path)
	_json_lock.unlock()
	if cached is Dictionary:
		return cached as Dictionary
	var path: String = DATA_DIR + rel_path
	var out: Dictionary = {}
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			out = parsed as Dictionary
		else:
			push_error("DataRegistry: %s is not a JSON object" % rel_path)
	_json_lock.lock()
	_json[rel_path] = out
	_json_lock.unlock()
	return out


## Forget cached `json()` files (tools and tests that rewrite data at run time).
func forget_json() -> void:
	_json_lock.lock()
	_json.clear()
	_json_lock.unlock()


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
