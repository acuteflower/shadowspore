extends Node
## What the HUD costs, part by part, in the v2 main world (docs/hud_v2_konzept.md 2.3, step 1).
## `Godot --headless --path . tools/test_hud_profile.tscn [-- --out=/abs.json]`. Prints a table and `HUD PROFILE OK`.
##
## How it measures (no engine profiler needed):
## * `_process`: every node of the HUD that processes gets its own `process_priority` slot, and a probe node runs in the
##   slot right before and right after it, so the time between the two probes is that node's `_process` alone.
## * `_draw`: queued redraws run as deferred calls in order. The test queues [start, the node's redraw, stop] for a node
##   at the very start of the frame, so the stop minus the start is that node's `_draw` (and its `draw` signal) alone.
##   Frames where the node's own redraw ran earlier (outside the brackets) are not counted.
## * How often each node redraws by itself is counted on its `draw` signal while nothing is forced.
## Cost per frame = process + draw x natural redraws per frame. Headless: drawing goes to the dummy renderer, so this is the
## GDScript cost (the part that matters for these immediate-mode vines), not the GPU.
## Fails only when the whole HUD costs more than BUDGET_USEC per frame; parts above PART_WARN_USEC are listed as WARN.

const HudTestWorld := preload("res://tools/hud_test_world.gd")
const BUDGET_USEC: float = 2500.0
const PART_WARN_USEC: float = 300.0
const NATURAL_FRAMES: int = 240
const FORCED_FRAMES: int = 120
const PRIORITY_BASE: int = 900000

class Probe extends Node:
	var owner_test: Node
	var index: int = 0
	func _process(_delta: float) -> void:
		owner_test.call("_probe", index)


var _failures: int = 0
var _out: String = ""
var _player: Player
var _hud: CanvasLayer

var _proc_nodes: Array[Node] = [] ## nodes whose _process is timed, slot i
var _proc_part: PackedStringArray = PackedStringArray() ## part name per slot
var _probe_t: PackedInt64Array = PackedInt64Array()
var _draw_nodes: Array[CanvasItem] = []
var _draw_part: PackedStringArray = PackedStringArray()

var _measuring: bool = false
var _forcing: bool = false
var _inside: CanvasItem = null
var _bracket_t: int = 0
var _proc_sum: Dictionary = {} ## part -> usec
var _proc_max: Dictionary = {}
var _draw_sum: Dictionary = {} ## part -> usec of forced draws (all its nodes)
var _draw_frames: Dictionary = {} ## part -> counted forced draws
var _natural: Dictionary = {} ## part -> draws seen while not forcing
var _frame_draw: Dictionary = {} ## part -> usec this frame (forced)
var _results: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -1000000 ## runs before everything: the forced redraws are queued first
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error(label)


func _run() -> void:
	_player = await HudTestWorld.open(self)
	_check(_player != null, "v2 world loaded with a local player")
	if _player == null:
		get_tree().quit(1)
		return
	_hud = _player.get("_hud") as CanvasLayer
	_player.inventory.give("dusk_berry", 4)
	_player.inventory.give("axe_basic", 1)
	if _player.quests != null:
		_player.quests.start("lumberjack")
	_collect()
	_check(_proc_nodes.size() > 5 and _draw_nodes.size() > 5, "HUD parts found (%d processing, %d drawing)" % [_proc_nodes.size(), _draw_nodes.size()])
	for scene: String in ["day", "night", "busy"]:
		await _scene(scene)
	_report()
	print("HUD PROFILE OK" if _failures == 0 else "HUD PROFILE: %d failures" % _failures)
	get_tree().quit(1 if _failures else 0)


## Every processing / drawing node of the HUD (and the zone inscriptions, which live on their own layer).
func _collect() -> void:
	var roots: Array[Node] = [_hud]
	var world: Node = HudTestWorld.world_of(self)
	if world != null and world.has_method("director"):
		var director: ZoneDirector = world.call("director") as ZoneDirector
		if director != null and director.arrival != null:
			roots.append(director.arrival)
	for root: Node in roots:
		var nodes: Array[Node] = [root]
		nodes.append_array(root.find_children("*", "", true, false))
		for node: Node in nodes:
			var part: String = _part_of(root, node)
			if node.has_method("_process"):
				_proc_nodes.append(node)
				_proc_part.append(part)
			var item: CanvasItem = node as CanvasItem
			if item != null and (item.has_method("_draw") or not item.get_signal_connection_list("draw").is_empty()):
				_draw_nodes.append(item)
				_draw_part.append(part)
	# a probe before every timed node and one after the last: probe i at slot 2i, node i at 2i + 1
	_probe_t.resize(_proc_nodes.size() + 1)
	for i: int in _proc_nodes.size():
		_proc_nodes[i].process_priority = PRIORITY_BASE + 2 * i + 1
	for i: int in _proc_nodes.size() + 1:
		var probe: Probe = Probe.new()
		probe.owner_test = self
		probe.index = i
		probe.process_mode = Node.PROCESS_MODE_ALWAYS
		probe.process_priority = PRIORITY_BASE + 2 * i
		add_child(probe)
	for i: int in _draw_nodes.size():
		_draw_nodes[i].draw.connect(_on_draw.bind(_draw_part[i], _draw_nodes[i]))


## The HUD child a node belongs to ("Hud" for the layer itself).
func _part_of(root: Node, node: Node) -> String:
	if node == _hud:
		return "Hud"
	if root != _hud:
		return String(root.name)
	var n: Node = node
	while n.get_parent() != _hud:
		n = n.get_parent()
	return String(n.name)


func _probe(index: int) -> void:
	var now: int = Time.get_ticks_usec()
	if index > 0 and _measuring:
		var node: Node = _proc_nodes[index - 1]
		if node.is_processing() and node.can_process():
			var part: String = _proc_part[index - 1]
			var took: float = float(now - _probe_t[index - 1])
			_proc_sum[part] = float(_proc_sum.get(part, 0.0)) + took
			_frame_proc[part] = float(_frame_proc.get(part, 0.0)) + took
	_probe_t[index] = Time.get_ticks_usec()


var _frame_proc: Dictionary = {}


func _process(_delta: float) -> void:
	if not _measuring:
		return
	for part: String in _frame_proc:
		_proc_max[part] = maxf(float(_proc_max.get(part, 0.0)), float(_frame_proc[part]))
	_frame_proc.clear()
	if not _forcing:
		return
	for i: int in _draw_nodes.size():
		var item: CanvasItem = _draw_nodes[i]
		if not item.is_visible_in_tree():
			continue
		_begin_draw.call_deferred(item)
		item.queue_redraw()
		_end_draw.call_deferred(item, _draw_part[i])


func _begin_draw(item: CanvasItem) -> void:
	_inside = item
	_bracket_t = Time.get_ticks_usec()


func _end_draw(item: CanvasItem, part: String) -> void:
	var took: int = Time.get_ticks_usec() - _bracket_t
	if _inside == item and item.has_meta("_hud_profile_drawn"): ## its draw ran inside the brackets
		_draw_sum[part] = float(_draw_sum.get(part, 0.0)) + float(took)
		_draw_frames[part] = int(_draw_frames.get(part, 0)) + 1
	item.remove_meta("_hud_profile_drawn")
	_inside = null


func _on_draw(part: String, item: CanvasItem) -> void:
	if _forcing:
		if _inside == item:
			item.set_meta("_hud_profile_drawn", true)
		return
	if _measuring:
		_natural[part] = int(_natural.get(part, 0)) + 1


## Measure one scene: natural frames (process + how often each part redraws), then forced frames (draw cost).
func _scene(scene: String) -> void:
	match scene:
		"day":
			TimeManager.set_time(0.45)
		"night":
			TimeManager.set_time(0.92)
		"busy": ## night, wounded, burning, a boss bar, the quest typing anew
			TimeManager.set_time(0.9)
			_player.health.floor_value = 1.0 ## the ticks must not kill her: a death starts the goddess's StarHall rescue
			_player.health.set_health(_player.health.max_health * 0.08)
			if _player.effects != null:
				_player.effects.apply("burn", 30.0)
				_player.effects.apply("shadow_venom", 30.0)
			var boss: HealthComponent = HealthComponent.new()
			boss.max_health = 900.0
			add_child(boss)
			get_tree().call_group("boss_bar", "track", "MORNATH", boss)
	for i: int in (360 if scene == "busy" else 60): ## settle (the boss bar's intro, shards and first tag flares must be over)
		await get_tree().process_frame
	_proc_sum.clear()
	_proc_max.clear()
	_draw_sum.clear()
	_draw_frames.clear()
	_natural.clear()
	_measuring = true
	_forcing = false
	for i: int in NATURAL_FRAMES:
		await get_tree().process_frame
	_forcing = true
	var proc_natural: Dictionary = _proc_sum.duplicate()
	for i: int in FORCED_FRAMES:
		await get_tree().process_frame
	_measuring = false
	_forcing = false
	var parts: Dictionary = {}
	for part: String in _proc_part:
		parts[part] = true
	for part: String in _draw_part:
		parts[part] = true
	var rows: Dictionary = {}
	for part: String in parts:
		var proc_us: float = float(proc_natural.get(part, 0.0)) / NATURAL_FRAMES
		var counted: int = int(_draw_frames.get(part, 0))
		var draw_us: float = float(_draw_sum.get(part, 0.0)) / maxf(float(counted) / maxf(_nodes_of(part), 1.0), 1.0)
		var per_frame: float = float(_natural.get(part, 0)) / NATURAL_FRAMES / maxf(_nodes_of(part), 1.0)
		rows[part] = {
			"process_us": proc_us,
			"process_max_us": float(_proc_max.get(part, 0.0)),
			"draw_us": draw_us if counted > 0 else 0.0,
			"redraws_per_s": per_frame * 60.0,
			"cost_us": proc_us + (draw_us if counted > 0 else 0.0) * per_frame,
		}
	_results[scene] = rows


## How many drawing nodes a part has (its draw cost is the sum of all of them).
func _nodes_of(part: String) -> float:
	var n: int = 0
	for p: String in _draw_part:
		if p == part:
			n += 1
	return float(n)


func _report() -> void:
	for scene: String in _results:
		var rows: Dictionary = _results[scene] as Dictionary
		var names: Array = rows.keys()
		names.sort_custom(func(a: String, b: String) -> bool: return float(rows[a].cost_us) > float(rows[b].cost_us))
		var total: float = 0.0
		print("")
		print("== HUD %s  (us per frame; draw = one full redraw; redraws per second when left alone)" % scene.to_upper())
		print("%-18s %9s %9s %9s %9s %9s" % ["part", "process", "proc max", "draw", "redraw/s", "cost"])
		for part: String in names:
			var r: Dictionary = rows[part] as Dictionary
			total += float(r.cost_us)
			if float(r.cost_us) < 1.0 and float(r.draw_us) < 1.0:
				continue
			var warn: String = "  WARN" if float(r.cost_us) > PART_WARN_USEC else ""
			print("%-18s %9.1f %9.1f %9.1f %9.1f %9.1f%s" % [part, r.process_us, r.process_max_us, r.draw_us, r.redraws_per_s, r.cost_us, warn])
		print("%-18s %49.1f" % ["TOTAL", total])
		_check(total < BUDGET_USEC, "%s: the whole HUD costs %.0f us per frame (budget %.0f)" % [scene, total, BUDGET_USEC])
		rows["_total"] = total
	if _out != "":
		var file: FileAccess = FileAccess.open(_out, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(_results, "\t"))
			print("written ", _out)
