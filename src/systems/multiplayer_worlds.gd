class_name MultiplayerWorlds
extends RefCounted
## Registry for persistent hosted multiplayer worlds and recently joined hosts.
## Each world owns its own save file under `user://mp_worlds/<id>.json`, keeps a persistent
## 6-character join code, port, max_players, and summary metadata for the Multiplayer tab.

const INDEX_PATH: String = "user://mp_worlds.json"
const WORLDS_DIR: String = "user://mp_worlds"
const LEGACY_COOP_PATH: String = "user://coop_save.json"
const VERSION: int = 1
const MAX_RECENT_HOSTS: int = 6
const CODE_LENGTH: int = 6
const CODE_CHARS: String = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" ## 32 unambiguous chars (no I, O, 0, 1)

static var _index_override: String = ""
static var _dir_override: String = ""


static func set_test_paths(index_path: String = "", worlds_dir: String = "") -> void:
	_index_override = index_path
	_dir_override = worlds_dir


static func index_path() -> String:
	return INDEX_PATH if _index_override.is_empty() else _index_override


static func worlds_dir() -> String:
	return WORLDS_DIR if _dir_override.is_empty() else _dir_override


static func generate_code() -> String:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var out: String = ""
	for _i: int in CODE_LENGTH:
		out += CODE_CHARS[rng.randi_range(0, CODE_CHARS.length() - 1)]
	return out


static func normalize_code(raw: String) -> String:
	var upper: String = raw.to_upper()
	var out: String = ""
	for ch: String in upper:
		var code: int = ch.unicode_at(0)
		var is_letter: bool = code >= 65 and code <= 90
		var is_digit: bool = code >= 48 and code <= 57
		if is_letter or is_digit:
			out += ch
			if out.length() >= CODE_LENGTH:
				break
	return out


static func sanitize_name(raw: String, fallback: String = "KOOP-WELT") -> String:
	var cleaned: String = raw.replace("ß", "SS").replace("ß", "SS").strip_edges().to_upper()
	var out: String = ""
	for ch: String in cleaned:
		var c: int = ch.unicode_at(0)
		var ok: bool = (
			(c >= 65 and c <= 90)
			or (c >= 48 and c <= 57)
			or ch in [" ", "-", "_", ".", "Ä", "Ö", "Ü", "&", "!"]
		)
		if ok:
			out += ("-" if ch == "_" else ch)
		if out.length() >= 18:
			break
	out = out.strip_edges()
	return fallback if out.is_empty() else out


static func list() -> Array[Dictionary]:
	var data: Dictionary = _load_index()
	var raw_worlds: Array = data.get("worlds", [])
	var out: Array[Dictionary] = []
	var dirty: bool = false
	for item: Variant in raw_worlds:
		if not (item is Dictionary):
			continue
		var entry: Dictionary = _normalize_world(item as Dictionary)
		var save_path: String = String(entry.get("save_path", ""))
		if not save_path.is_empty() and FileAccess.file_exists(save_path):
			var info: Dictionary = SaveGame.info(save_path)
			if not info.is_empty():
				var info_day: int = int(info.get("day", entry["day"]))
				var info_time: float = float(info.get("time", entry["time"]))
				var saved_at: int = int(info.get("saved_at", entry["last_played"]))
				if info_day != int(entry["day"]) or absf(info_time - float(entry["time"])) > 0.001 or saved_at > int(entry["last_played"]):
					entry["day"] = info_day
					entry["time"] = info_time
					entry["last_played"] = maxi(int(entry["last_played"]), saved_at)
					dirty = true
				entry["has_save"] = true
			else:
				entry["has_save"] = false
		else:
			entry["has_save"] = false
		out.append(entry)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("last_played", 0)) > int(b.get("last_played", 0))
	)
	if dirty:
		data["worlds"] = out
		_write_index(data)
	return out


static func get_world(world_id: String) -> Dictionary:
	if world_id.is_empty():
		return {}
	for entry: Dictionary in list():
		if String(entry.get("id", "")) == world_id:
			return entry
	return {}


static func create_world(world_name: String, max_players: int = 4, port: int = 7777, code: String = "") -> Dictionary:
	var data: Dictionary = _load_index()
	var now: int = int(Time.get_unix_time_from_system())
	var clean_name: String = sanitize_name(world_name, "KOOP-WELT")
	var clean_code: String = normalize_code(code)
	if clean_code.length() < 4:
		clean_code = generate_code()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var world_id: String = "mp_%d_%04x" % [now, rng.randi_range(0, 0xffff)]
	var dir: String = worlds_dir()
	var save_path: String = "%s/%s.json" % [dir, world_id]
	var entry: Dictionary = _normalize_world({
		"id": world_id,
		"name": clean_name,
		"code": clean_code,
		"port": clampi(port, 1024, 65535),
		"max_players": clampi(max_players, 2, 4),
		"created_at": now,
		"last_played": now,
		"day": 0,
		"time": 0.3,
		"players_seen": 1,
		"save_path": save_path,
		"has_save": false,
	})
	var worlds: Array = data.get("worlds", [])
	worlds.append(entry)
	data["worlds"] = worlds
	_write_index(data)
	return entry


static func delete_world(world_id: String) -> bool:
	if world_id.is_empty():
		return false
	var data: Dictionary = _load_index()
	var worlds: Array = data.get("worlds", [])
	var kept: Array = []
	var deleted_save: String = ""
	var found: bool = false
	for item: Variant in worlds:
		if not (item is Dictionary):
			continue
		var entry: Dictionary = item as Dictionary
		if String(entry.get("id", "")) == world_id:
			found = true
			deleted_save = String(entry.get("save_path", ""))
		else:
			kept.append(entry)
	if not found:
		return false
	data["worlds"] = kept
	_write_index(data)
	if not deleted_save.is_empty() and FileAccess.file_exists(deleted_save):
		DirAccess.remove_absolute(deleted_save)
	return true


static func update_world(world_id: String, patch: Dictionary) -> Dictionary:
	if world_id.is_empty():
		return {}
	var data: Dictionary = _load_index()
	var worlds: Array = data.get("worlds", [])
	var updated: Dictionary = {}
	for i: int in worlds.size():
		if not (worlds[i] is Dictionary):
			continue
		var entry: Dictionary = _normalize_world(worlds[i] as Dictionary)
		if String(entry.get("id", "")) == world_id:
			for key: String in patch:
				entry[key] = patch[key]
			entry["code"] = normalize_code(String(entry.get("code", "")))
			entry["name"] = sanitize_name(String(entry.get("name", "")), "KOOP-WELT")
			entry["max_players"] = clampi(int(entry.get("max_players", 4)), 2, 4)
			entry["port"] = clampi(int(entry.get("port", 7777)), 1024, 65535)
			worlds[i] = entry
			updated = entry
			break
	if not updated.is_empty():
		data["worlds"] = worlds
		_write_index(data)
	return updated


static func regenerate_code(world_id: String) -> String:
	var next_code: String = generate_code()
	var updated: Dictionary = update_world(world_id, {"code": next_code})
	return String(updated.get("code", next_code))


static func touch_save(world_id: String, day: int, time: float, guest_count: int = -1) -> void:
	if world_id.is_empty():
		return
	var current: Dictionary = get_world(world_id)
	if current.is_empty():
		return
	var patch: Dictionary = {
		"last_played": int(Time.get_unix_time_from_system()),
		"day": maxi(day, 0),
		"time": fposmod(time, 1.0),
		"has_save": true,
	}
	if guest_count >= 0:
		patch["players_seen"] = maxi(int(current.get("players_seen", 1)), guest_count + 1)
	update_world(world_id, patch)


static func recent_hosts() -> Array[Dictionary]:
	var data: Dictionary = _load_index()
	var raw: Array = data.get("recent_hosts", [])
	var out: Array[Dictionary] = []
	for item: Variant in raw:
		if item is Dictionary:
			var d: Dictionary = item as Dictionary
			var addr: String = String(d.get("address", "")).strip_edges()
			if addr.is_empty():
				continue
			out.append({
				"address": addr,
				"port": clampi(int(d.get("port", 7777)), 1024, 65535),
				"code": normalize_code(String(d.get("code", ""))),
				"label": sanitize_name(String(d.get("label", addr)), addr),
				"last_seen": int(d.get("last_seen", 0)),
			})
	return out


static func add_recent_host(address: String, port: int, code: String, label: String = "") -> void:
	var clean_addr: String = address.strip_edges()
	if clean_addr.is_empty():
		return
	var clean_port: int = clampi(port, 1024, 65535)
	var clean_code: String = normalize_code(code)
	var clean_label: String = sanitize_name(label if not label.is_empty() else clean_addr, clean_addr)
	var data: Dictionary = _load_index()
	var raw: Array = data.get("recent_hosts", [])
	var kept: Array = [{
		"address": clean_addr,
		"port": clean_port,
		"code": clean_code,
		"label": clean_label,
		"last_seen": int(Time.get_unix_time_from_system()),
	}]
	for item: Variant in raw:
		if not (item is Dictionary):
			continue
		var d: Dictionary = item as Dictionary
		if String(d.get("address", "")) == clean_addr and int(d.get("port", 7777)) == clean_port:
			continue
		kept.append(d)
		if kept.size() >= MAX_RECENT_HOSTS:
			break
	data["recent_hosts"] = kept
	_write_index(data)


static func parse_address_port(raw: String, fallback_port: int = 7777) -> Dictionary:
	var text: String = raw.strip_edges()
	var port: int = clampi(fallback_port, 1024, 65535)
	var address: String = text
	var colon: int = text.rfind(":")
	if colon > 0 and colon < text.length() - 1:
		var maybe_port: String = text.substr(colon + 1)
		if maybe_port.is_valid_int():
			port = clampi(maybe_port.to_int(), 1024, 65535)
			address = text.substr(0, colon).strip_edges()
	return {"address": address, "port": port}


static func _normalize_world(raw: Dictionary) -> Dictionary:
	var now: int = int(Time.get_unix_time_from_system())
	var id: String = String(raw.get("id", ""))
	return {
		"id": id,
		"name": sanitize_name(String(raw.get("name", "KOOP-WELT")), "KOOP-WELT"),
		"code": normalize_code(String(raw.get("code", generate_code()))),
		"port": clampi(int(raw.get("port", 7777)), 1024, 65535),
		"max_players": clampi(int(raw.get("max_players", 4)), 2, 4),
		"created_at": int(raw.get("created_at", now)),
		"last_played": int(raw.get("last_played", now)),
		"day": maxi(int(raw.get("day", 0)), 0),
		"time": fposmod(float(raw.get("time", 0.3)), 1.0),
		"players_seen": maxi(int(raw.get("players_seen", 1)), 1),
		"save_path": String(raw.get("save_path", "%s/%s.json" % [worlds_dir(), id])),
		"has_save": bool(raw.get("has_save", false)),
	}


static func _load_index() -> Dictionary:
	var path: String = index_path()
	var data: Dictionary = {"version": VERSION, "legacy_imported": false, "worlds": [], "recent_hosts": []}
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			data = parsed as Dictionary
			if not data.has("worlds") or not (data["worlds"] is Array):
				data["worlds"] = []
			if not data.has("recent_hosts") or not (data["recent_hosts"] is Array):
				data["recent_hosts"] = []
	if not bool(data.get("legacy_imported", false)) and _index_override.is_empty():
		data["legacy_imported"] = true
		if FileAccess.file_exists(LEGACY_COOP_PATH):
			var info: Dictionary = SaveGame.info(LEGACY_COOP_PATH)
			var legacy_dir: String = worlds_dir()
			DirAccess.make_dir_recursive_absolute(legacy_dir)
			var dest: String = "%s/legacy_coop.json" % legacy_dir
			if not FileAccess.file_exists(dest):
				var bytes: PackedByteArray = FileAccess.get_file_as_bytes(LEGACY_COOP_PATH)
				if not bytes.is_empty():
					var f: FileAccess = FileAccess.open(dest, FileAccess.WRITE)
					if f != null:
						f.store_buffer(bytes)
						f.flush()
						f.close()
			var legacy_entry: Dictionary = _normalize_world({
				"id": "legacy_coop",
				"name": "ALTE KOOP-WELT",
				"code": generate_code(),
				"port": 7777,
				"max_players": 4,
				"created_at": int(info.get("saved_at", Time.get_unix_time_from_system())),
				"last_played": int(info.get("saved_at", Time.get_unix_time_from_system())),
				"day": int(info.get("day", 0)),
				"time": float(info.get("time", 0.3)),
				"players_seen": 1,
				"save_path": dest,
				"has_save": FileAccess.file_exists(dest),
			})
			(data["worlds"] as Array).append(legacy_entry)
		_write_index(data)
	return data


static func _write_index(data: Dictionary) -> void:
	var path: String = index_path()
	var base: String = path.get_base_dir()
	if not base.is_empty():
		DirAccess.make_dir_recursive_absolute(base)
	var pending: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(pending, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	var ok: bool = file.get_error() == OK
	file.close()
	if ok:
		DirAccess.rename_absolute(pending, path)
