class_name FishBook
extends RefCounted
## The river book: what this player has caught, per species (count, best length, first day). Local to the
## player's machine, saved atomically beside the character save , never in save.json.

var path: String
var species: Dictionary = {} ## id -> {"caught": int, "best": int, "first_day": int}


func _init(file: String = "") -> void:
	path = file if file != "" else String((FishingRules.settings()["book"] as Dictionary)["path"])
	load_book()


func load_book() -> void:
	species = {}
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return
	var table: Dictionary = FishingRules.species_table()
	var stored: Variant = (parsed as Dictionary).get("species", {})
	if not stored is Dictionary:
		return
	for id: String in stored as Dictionary:
		var entry: Variant = (stored as Dictionary)[id]
		if table.has(id) and entry is Dictionary and int((entry as Dictionary).get("caught", 0)) > 0:
			species[id] = {"caught": int((entry as Dictionary)["caught"]), "best": int((entry as Dictionary).get("best", 0)), "first_day": int((entry as Dictionary).get("first_day", 1))}


## Records one catch. Returns true when it is a new species or a new best length.
func record(id: String, length: int, day: int) -> bool:
	if not FishingRules.species_table().has(id):
		return false
	var entry: Dictionary = species.get(id, {"caught": 0, "best": 0, "first_day": day}) as Dictionary
	var record_made: bool = int(entry["caught"]) == 0 or length > int(entry["best"])
	entry["caught"] = int(entry["caught"]) + 1
	entry["best"] = maxi(int(entry["best"]), length)
	species[id] = entry
	save()
	return record_made


func known(id: String) -> bool:
	return species.has(id)


func save() -> bool:
	var tmp: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": 1, "species": species}))
	file.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path)) == OK
