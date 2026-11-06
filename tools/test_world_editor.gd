extends Node
## Isolated editor regression; never writes the player's map or game save.
var failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + label)
	else:
		print("PASS: " + label)

func _run() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	get_tree().root.add_child(world)
	await get_tree().process_frame
	var baseline: Dictionary = world.edits.data()
	world.editor_apply({"props": {}, "terrain": {}})
	var editor: WorldEditor = WorldEditor.new()
	world.add_child(editor)
	editor.start(world)
	await get_tree().process_frame
	check(get_tree().paused and InputManager.ui_blocking, "editor pauses gameplay and blocks input")
	check(world.editor_camera == editor.camera, "free camera owns streaming center")
	var cell: Vector2i = world._start
	var found: bool = false
	for y: int in range(-35, 36):
		if found: break
		for x: int in range(-35, 36):
			var candidate: Vector2i = world._start + Vector2i(x, y)
			var clear: bool = true
			for dy: int in range(-5, 6):
				for dx: int in range(-5, 6):
					clear = clear and world.editor_land(candidate + Vector2i(dx, dy)) and world._relief.is_land(candidate.x + dx, candidate.y + dy)
			if clear:
				cell = candidate
				found = true
				break
	check(found, "test footprint lies fully on land")
	editor.camera.position = Vector2(cell) * 16.0
	editor.camera.force_update_scroll()
	var key: String = WorldEdits.key(cell)
	var next: Dictionary = world.edits.data()
	next.props[key] = {"kind": "rock", "variant": 1, "pos": [cell.x * 16 + 8, cell.y * 16 + 13], "scale": 1.2, "flip": true}
	editor._selected = cell
	editor._commit(next)
	check(world.editor_prop(cell).get("kind") == "rock", "place object")
	check(world.editor_prop(cell).get("flip") == true, "object scale and mirror")
	editor._delete_selected()
	check(world.editor_prop(cell).is_empty(), "delete object")
	editor.undo()
	check(world.editor_prop(cell).get("kind") == "rock", "undo deletion")
	editor.redo()
	check(world.editor_prop(cell).is_empty(), "redo deletion")
	editor.undo()
	var chunk: Vector2i = cell / world.CHUNK
	world._unload_chunk(chunk)
	world._load_chunk(chunk)
	check(world.editor_prop(cell).get("kind") == "rock", "object survives chunk unload")
	# Moving across a chunk boundary keeps the destination and removes the source.
	editor._drag = world._things[cell]
	editor._drag_origin = editor._drag.position
	editor._drag.position += Vector2(33 * 16, 0)
	var dest: Vector2i = cell + Vector2i(33, 0)
	if world.editor_land(dest) and not world._things.has(dest):
		editor._finish_drag()
		check(bool(world.edits.props[key].get("removed", false)), "move suppresses source")
		check(world.edits.props.has(WorldEdits.key(dest)), "move authors destination across chunk boundary")
		editor.undo()
	else:
		editor._cancel_gesture()
	editor._selected = cell
	editor._catalog.select(editor._kinds.find("bush"))
	editor._variant.value = 0
	editor._edit_selected()
	check(world.editor_prop(cell).get("kind") == "bush", "replace selected object")
	editor.undo()
	# A wide plateau must update both the height field and southern wall collision.
	var original_block: PackedByteArray = world._relief._block.duplicate()
	next = world.edits.data()
	for y: int in range(-3, 4):
		for x: int in range(-3, 4):
			next.terrain[WorldEdits.key(cell + Vector2i(x, y))] = {"height": 1, "kind": 0, "style": 1, "ground": "plain", "biome": "meadow"}
	editor._commit(next)
	check(world.editor_height(cell) == 1, "terrain target height")
	check(world._relief.level_at(Vector2(cell) * 16 + Vector2(8, 8)) == 1.0, "gameplay height uses edited terrain")
	check(world._relief._block != original_block, "terrain collision rebuilt")
	editor.undo()
	check(world._relief._block == original_block, "undo restores baked collision exactly")
	editor.redo()
	var edits: WorldEdits = WorldEdits.new()
	edits.assign(world.edits.data())
	var path: String = OS.get_temp_dir().path_join("voidbloom-world-editor-test.json")
	check(edits.save(path), "atomic map save")
	var loaded: WorldEdits = WorldEdits.new()
	loaded.read(path)
	check(JSON.parse_string(JSON.stringify(loaded.data())) == JSON.parse_string(JSON.stringify(edits.data())), "map reload round trip")
	DirAccess.remove_absolute(path)
	# Connector footprint and landing geometry.
	editor._tool.select(5)
	editor._height.value = 0
	editor._pending = world.edits.data()
	editor._stamp(cell)
	editor._commit(editor._pending)
	check(world._relief.kind(cell.x, cell.y) == Relief.RAMP, "ramp stamp")
	check(world.editor_height(cell + Vector2i.UP) == 1, "ramp upper landing")
	check(world._relief.level_at(Vector2(cell) * 16 + Vector2(8, 8)) > 0.5, "ramp interpolated height")
	editor._tool.select(6)
	editor._pending = world.edits.data()
	editor._stamp(cell)
	editor._commit(editor._pending)
	check(world._relief.kind(cell.x, cell.y) == Relief.STAIRS, "stairs stamp")
	editor._tool.select(3)
	editor._size.value = 0
	editor._ground_kind.select(editor._grounds.find("tuft"))
	editor._pending = world.edits.data()
	editor._stamp(cell)
	editor._commit(editor._pending)
	check(world.edits.terrain[key].get("ground") == "tuft", "paint ground while preserving height")
	editor._tool.select(7)
	editor._pending = world.edits.data()
	editor._stamp(cell)
	editor._commit(editor._pending)
	check(not world.edits.terrain.has(key), "restore original terrain cell")
	editor.undo()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--capture="))
	editor._saved = world.edits.data()
	editor._request_close()
	await get_tree().process_frame
	check(not get_tree().paused and not InputManager.ui_blocking and world.editor_camera == null, "exit restores game and camera")
	var menu: PauseMenu = world._players.get_child(0).find_child("PauseMenu", true, false) as PauseMenu
	menu._set_open(true)
	menu._select_tab(3)
	menu._run_action("editor")
	check(world.editor_camera != null and paused_state(), "developer settings opens editor")
	for child: Node in world.get_children():
		if child is WorldEditor:
			(child as WorldEditor)._close()
	await get_tree().process_frame
	world.editor_apply(baseline)
	world.queue_free()
	await get_tree().process_frame
	print("WORLD EDITOR: %d failures" % failures)
	get_tree().quit(1 if failures else 0)

func paused_state() -> bool:
	return get_tree().paused
