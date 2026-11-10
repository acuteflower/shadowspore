extends Node
## Developer "whole map" reveal (pause menu ENTWICKLER -> KARTE): every cell counts as seen, the table from before comes back with
## NEBEL ZURÜCKSETZEN, and both survive a save (`export_before` / `import_before`). Headless: `tools/test_map_reveal.tscn`.

var _ok: bool = true


func _check(name: String, value: bool) -> void:
	if not value:
		_ok = false
		print("FAILED: ", name)


func _ready() -> void:
	var fog: MapDiscovery = MapDiscovery.new()
	add_child(fog)
	fog.set_process(false)
	fog._rpc_reveal(PackedInt32Array([5, 6, 7]))
	var before: PackedByteArray = fog.bytes().duplicate()
	var full: int = MapDiscovery.GRID * MapDiscovery.GRID
	_check("walked cells counted", fog.seen_count() == 3)
	_check("no reveal yet", not fog.is_reveal_all())
	fog.reveal_all()
	_check("reveal active", fog.is_reveal_all())
	_check("every cell seen", fog.seen_count() == full)
	_check("cell far away seen", fog.is_seen_cell(MapDiscovery.GRID - 1, MapDiscovery.GRID - 1))
	fog.reveal_all() ## a second press changes nothing
	_check("second press keeps the table", fog.is_reveal_all() and fog.seen_count() == full)

	var table: PackedByteArray = fog.export_data()
	var saved_before: PackedByteArray = fog.export_before()
	var reloaded: MapDiscovery = MapDiscovery.new()
	add_child(reloaded)
	reloaded.set_process(false)
	reloaded.import_saved(table)
	reloaded.import_before(saved_before)
	_check("reveal survives a save", reloaded.is_reveal_all() and reloaded.seen_count() == full)
	reloaded.reset_reveal()
	_check("reset is not active", not reloaded.is_reveal_all())
	_check("reset gives the old fog back", reloaded.seen_count() == 3 and reloaded.bytes() == before)

	var plain: MapDiscovery = MapDiscovery.new()
	add_child(plain)
	plain.set_process(false)
	plain.import_saved(before.compress(FileAccess.COMPRESSION_ZSTD))
	plain.import_before(PackedByteArray())
	_check("old save without reveal stays", not plain.is_reveal_all() and plain.seen_count() == 3)

	print("MAP REVEAL ", "OK" if _ok else "FAILED")
	get_tree().quit(0 if _ok else 1)
