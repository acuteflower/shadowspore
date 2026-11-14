class_name ButterflyPopulation
extends Node2D
## Sparse flower patches, not screen-space particles. The world's flower callback returns the
## positions of actual painted flower/clover/bloom tiles; butterflies feed and rest on them.

var _seed: int = 0
var _source: Callable
var _active: Dictionary = {}
var _patches: Dictionary = {}
var _pending: Array[Vector2i] = []
var _serial: int = 0
var _maintenance: float = 0.0

@onready var _butterflies: Node2D = $Butterflies


func _ready() -> void:
	set_process(multiplayer.is_server())


func setup(seed_value: int, source: Callable) -> void:
	_seed = seed_value
	_source = source


func chunk_loaded(cell: Vector2i) -> void:
	if multiplayer.is_server():
		_active[cell] = true
		if not _patches.has(cell) and not _pending.has(cell):
			_pending.append(cell)


func chunk_unloaded(cell: Vector2i) -> void:
	_active.erase(cell)
	_pending.erase(cell)


func _process(delta: float) -> void:
	if not _pending.is_empty():
		var cell: Vector2i = _pending.pop_front()
		if _active.has(cell):
			_populate(cell)
	_maintenance -= delta
	if _maintenance <= 0.0:
		_maintenance = 0.5
		for home: Vector2i in _patches.keys():
			if not _active.has(home):
				var group: Array[MeadowButterfly] = _patches[home]
				for i: int in range(group.size() - 1, -1, -1):
					var animal: MeadowButterfly = group[i]
					if not is_instance_valid(animal):
						group.remove_at(i)
						continue
					var cell: Vector2i = Vector2i(floori(animal.global_position.x / 512.0), floori(animal.global_position.y / 512.0))
					if not _active.has(cell):
						animal.queue_free()
						group.remove_at(i)
				if group.is_empty():
					_patches.erase(home)


func _populate(cell: Vector2i) -> void:
	if _patches.has(cell) or not _source.is_valid():
		return
	var group: Array[MeadowButterfly] = []
	_patches[cell] = group
	var spec: Dictionary = DataRegistry.get_entry("wildlife", "butterfly")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(cell.x, cell.y, _seed + 8147))
	var mid_px: Vector2 = Vector2(cell) * 512.0 + Vector2(256.0, 256.0)
	var w_wind: float = MeadowHabitats.wind_meadow_at(mid_px)
	var bf_chance: float = float(spec["chunk_chance"]) * (1.0 + 1.35 * w_wind)
	var bf_cap: int = int(spec["max_loaded"]) + (8 if w_wind >= 0.40 else 0)
	if rng.randf() > bf_chance or _butterflies.get_child_count() >= bf_cap:
		return
	var flowers: Array[Vector2] = []
	for point: Vector2 in _source.call(cell):
		flowers.append(point)
	if flowers.size() < int(spec["min_flowers"]):
		return
	var center: Vector2 = flowers[rng.randi_range(0, flowers.size() - 1)]
	var patch: Array[Vector2] = []
	for point: Vector2 in flowers:
		if point.distance_to(center) <= float(spec["patch_radius"]):
			patch.append(point)
	if patch.size() < 3:
		return
	var extra_bf: int = 3 if w_wind >= 0.40 else 0
	var count: int = rng.randi_range(int(spec["group_min"]) + extra_bf, int(spec["group_max"]) + extra_bf)
	for i: int in count:
		if _butterflies.get_child_count() >= bf_cap:
			break
		var animal: MeadowButterfly = load(String(spec["scene"])).instantiate() as MeadowButterfly
		_serial += 1
		animal.name = "Butterfly%d" % _serial
		animal.home = center
		animal.position = patch[rng.randi_range(0, patch.size() - 1)]
		animal.flowers = patch
		animal.appearance = rng.randi_range(0, 3)
		_butterflies.add_child(animal)
		group.append(animal)
