extends Node
## Loads every res://data/*.json into memory, keyed by file name (e.g. "items").

const DATA_DIR: String = "res://data/"

var _tables: Dictionary = {}


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
