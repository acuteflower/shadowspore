class_name Puzzles
extends Node2D
## The trials of the Wächterin in the world (docs/raetsel_konzept.md). Built: the wisp trail (`WispTrail`), the crow's hoard (`CrowHoard`) the root weave (`RootWeave`) and the star mirror (`StarMirror`), all
## `WorldTrial`s. Every trial of `data/puzzles.json` `placed` is built on every peer the same way; the host runs them and decides when one is solved
## (`_host_solved`): then every peer marks it (`_rpc_solved`) and the reward chest comes where the trial ended (`LootChests.appear`, id `trial_<id>`,
## out of the light or out of the earth, `WorldTrial.reward_rise`; saved like any chest that stands in the world). Solved trials stay solved, a trial
## may keep progress of its own (`export_progress`); save key `"puzzles"`, a joining peer gets the list (`_rpc_snapshot`). Dev: `debug_reset(id)`,
## `trial_spot(id)` for the teleport (ENTWICKLER -> IRRLICHT / HORTKRÄHE).

const KINDS: Dictionary = {"wisp": "wisp", "crow_hoard": "crow", "raven_trade": "raven", "root_weave": "weave", "star_mirror": "stars", "prism_seal": "prism"} ## kind -> tuning block of data/puzzles.json

var _trials: Dictionary = {} ## id -> WorldTrial
var _specs: Dictionary = {} ## id -> entry of data/puzzles.json
var _solved: Dictionary = {} ## id -> true
var source: String = "placed" ## which list of data/puzzles.json to build: "placed" (the world) or "trial_world" (the flat test world); set before it enters the tree


static func of(tree: SceneTree) -> Puzzles:
	return tree.get_first_node_in_group("puzzles") as Puzzles


func _ready() -> void:
	add_to_group("puzzles")
	y_sort_enabled = true
	var table: Dictionary = DataRegistry.table("puzzles")
	if not source.is_empty():
		for entry: Dictionary in table.get(source, []) as Array:
			place_trial(entry, Vector2.ZERO)
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(func(peer: int) -> void: _rpc_snapshot.rpc_id(peer, PackedStringArray(_solved.keys()), _progress()))


## Dynamically place a trial (used by v2 zones when a ZoneStage attaches). `origin_tile` offsets zone-local tile coordinates.
func place_trial(raw_entry: Dictionary, origin_tile: Vector2 = Vector2.ZERO) -> WorldTrial:
	var entry: Dictionary = _offset_entry(raw_entry, origin_tile) if origin_tile != Vector2.ZERO else raw_entry
	var trial_id: String = String(entry.get("id", ""))
	var kind: String = String(entry.get("kind", ""))
	if trial_id == "" or not KINDS.has(kind):
		return null
	if _trials.has(trial_id):
		return _trials[trial_id] as WorldTrial
	var table: Dictionary = DataRegistry.table("puzzles")
	var node: WorldTrial = null
	match kind:
		"wisp":
			node = WispTrail.new()
		"crow_hoard", "raven_trade":
			node = CrowHoard.new()
		"root_weave":
			node = RootWeave.new()
		"star_mirror":
			node = StarMirror.new()
		"prism_seal":
			node = PrismSeal.new()
	if node == null:
		return null
	node.name = "Trial_" + trial_id
	node.setup(entry, table.get(String(KINDS[kind]), {}) as Dictionary)
	node.solved.connect(_on_trial_solved)
	add_child(node)
	_trials[trial_id] = node
	_specs[trial_id] = entry
	if _solved.has(trial_id):
		node.set_solved_instant()
	return node


static func _offset_entry(raw_entry: Dictionary, origin_tile: Vector2) -> Dictionary:
	var out: Dictionary = raw_entry.duplicate(true)
	for key: String in ["tile", "mound"]:
		var val: Variant = out.get(key)
		if val is Array and (val as Array).size() >= 2:
			var arr: Array = val as Array
			out[key] = [float(arr[0]) + origin_tile.x, float(arr[1]) + origin_tile.y]
	for list_key: String in ["route", "stations"]:
		var list_v: Variant = out.get(list_key)
		if list_v is Array:
			var shifted: Array = []
			for pt_v: Variant in list_v as Array:
				if pt_v is Array and (pt_v as Array).size() >= 2:
					var pa: Array = pt_v as Array
					shifted.append([float(pa[0]) + origin_tile.x, float(pa[1]) + origin_tile.y])
			out[list_key] = shifted
	return out


## Where the world must stay free of generated props: [world px, radius in tiles].
static func clear_spots() -> Array:
	var out: Array = []
	for entry: Dictionary in DataRegistry.table("puzzles").get("placed", []) as Array:
		var keep: Array = []
		match String(entry.get("kind", "")):
			"wisp":
				var route: Array = entry.get("route", []) as Array
				if not route.is_empty():
					keep = [[route[0], 2], [route[route.size() - 1], 3]]
					for k: int in range(1, route.size() - 1): ## where it hovers stays free of trunks and bushes
						keep.append([route[k], 1])
			"crow_hoard", "raven_trade":
				keep = [[entry.get("tile", [0, 0]), 2], [entry.get("mound", [0, 0]), 2]]
				for st: Variant in entry.get("stations", []) as Array:
					keep.append([st, 1])
			"root_weave":
				keep = [[entry.get("tile", [0, 0]), 14]]
			"star_mirror":
				var fo: Array = entry.get("field", [0, 9]) as Array
				var tl: Array = entry.get("tile", [0, 0]) as Array
				keep = [[tl, 7], [[float(tl[0]) + float(fo[0]), float(tl[1]) + float(fo[1])], 8]]
			"prism_seal":
				keep = [[entry.get("tile", [0, 0]), 7]]
		for k: Array in keep:
			var t: Array = k[0] as Array
			out.append([Vector2(float(t[0]), float(t[1])) * 16.0 + Vector2(8, 8), int(k[1])])
	return out


func trial(id: String) -> WorldTrial:
	return _trials.get(id) as WorldTrial


func ids() -> Array:
	return _trials.keys()


## The first trial of a kind ("" = none).
func first_of(kind: String) -> String:
	for id: String in _specs:
		if String((_specs[id] as Dictionary).get("kind", "")) == kind:
			return id
	return ""


func is_solved(id: String) -> bool:
	return _solved.has(id)


## A spot to stand at to begin a trial (dev teleport).
func trial_spot(id: String) -> Vector2:
	var node: WorldTrial = _trials.get(id) as WorldTrial
	return node.start_position() if node != null else Vector2.INF


func _chest_id(id: String) -> String:
	return "trial_" + id


func _tier(id: String) -> String:
	return String((_specs.get(id, {}) as Dictionary).get("tier", "common"))


func _on_trial_solved(id: String, at: Vector2) -> void:
	if multiplayer.is_server():
		_host_solved(id, at)


func _host_solved(id: String, at: Vector2) -> void:
	if _solved.has(id):
		return
	var node: WorldTrial = _trials.get(id) as WorldTrial
	var chests: LootChests = LootChests.of(get_tree())
	if node != null and chests != null and not node.reward_extra().is_empty():
		chests.add_extra(_chest_id(id), node.reward_extra())
	if multiplayer.get_peers().is_empty():
		_rpc_solved(id, at)
	else:
		_rpc_solved.rpc(id, at)


@rpc("authority", "call_local", "reliable")
func _rpc_solved(id: String, at: Vector2) -> void:
	_solved[id] = true
	var node: WorldTrial = _trials.get(id) as WorldTrial
	var chests: LootChests = LootChests.of(get_tree())
	if chests != null:
		chests.appear(_chest_id(id), _tier(id), at, true, false, node != null and node.reward_rise())


@rpc("authority", "reliable")
func _rpc_snapshot(solved: PackedStringArray, progress: Dictionary) -> void:
	for id: String in progress:
		var node: WorldTrial = _trials.get(id) as WorldTrial
		if node != null and not solved.has(id):
			node.import_progress(progress[id] as Dictionary)
	for id: String in solved:
		_mark_solved(id)


func _progress() -> Dictionary:
	var out: Dictionary = {}
	for id: String in _trials:
		if _solved.has(id):
			continue
		var p: Dictionary = (_trials[id] as WorldTrial).export_progress()
		if not p.is_empty():
			out[id] = p
	return out


func _mark_solved(id: String) -> void:
	_solved[id] = true
	var node: WorldTrial = _trials.get(id) as WorldTrial
	if node != null:
		node.set_solved_instant()
		var chests: LootChests = LootChests.of(get_tree())
		if chests != null:
			chests.appear(_chest_id(id), _tier(id), node.end_position(), false)


## Dev (host): the trial is open again, its chest gone.
func debug_reset(id: String) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_peers().is_empty():
		_rpc_reset(id)
	else:
		_rpc_reset.rpc(id)


@rpc("authority", "call_local", "reliable")
func _rpc_reset(id: String) -> void:
	_solved.erase(id)
	var node: WorldTrial = _trials.get(id) as WorldTrial
	if node != null:
		node.reset_trial()
	var chests: LootChests = LootChests.of(get_tree())
	if chests != null:
		chests.forget(_chest_id(id))


func export_state() -> Dictionary:
	var out: Dictionary = {"solved": _solved.keys()}
	var progress: Dictionary = _progress()
	if not progress.is_empty():
		out["progress"] = progress
	return out


## True when nothing of the trials needs saving.
func is_blank() -> bool:
	return _solved.is_empty() and _progress().is_empty()


func import_state(data: Dictionary) -> void:
	var progress: Dictionary = SaveGame.as_dict(data.get("progress"))
	for id: Variant in progress:
		var node: WorldTrial = _trials.get(String(id)) as WorldTrial
		if node != null and progress[id] is Dictionary:
			node.import_progress(progress[id] as Dictionary)
	for id: Variant in SaveGame.as_array(data.get("solved")):
		_mark_solved(String(id))
	if multiplayer.is_server() and not multiplayer.get_peers().is_empty() and NetworkManager.rpc_ready(self):
		_rpc_snapshot.rpc(PackedStringArray(_solved.keys()), _progress())
