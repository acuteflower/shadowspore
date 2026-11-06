class_name CookingBook
extends RefCounted
## Discovered cooking variants; separate from character saves and inventory.
const PATH: String = "user://cooking_book.json"
static func read(path: String = PATH) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary: return {}
	var discoveries: Variant = (parsed as Dictionary).get("discoveries",{})
	var valid: Dictionary = {}
	if discoveries is Dictionary:
		for key: String in discoveries as Dictionary:
			var entry: Variant = (discoveries as Dictionary)[key]
			if entry is Dictionary and (entry as Dictionary).get("name") is String and (entry as Dictionary).get("notes") is Array:
				valid[key] = entry
	return valid
static func remember(result: Dictionary,path: String = PATH) -> bool:
	if result.is_empty(): return false
	var discoveries: Dictionary = read(path)
	discoveries[String(result.recipe)+":"+String(result.variant)] = result.duplicate(true)
	# Atomic replacement: an interrupted write does not destroy earlier discoveries.
	var temp: String = path+".tmp"
	var file: FileAccess = FileAccess.open(temp,FileAccess.WRITE)
	if file==null: return false
	file.store_string(JSON.stringify({"version":1,"discoveries":discoveries},"\t"))
	file.close()
	return DirAccess.rename_absolute(temp,path)==OK
