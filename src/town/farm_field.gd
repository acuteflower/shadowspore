class_name FarmField
extends TownStructure
## The picture of a field (piece with `farm: true`, docs/farming.md): ground painted by `FieldSoil` (it melts with neighbouring fields and crumbles into the meadow at its
## own edges) and one `FieldCell` per 16 px bed on top. A field is ground: no collider, you walk over the beds. It is `y_sort_enabled`, so the crops sort with the
## people and trees round them. The cells' state is `FarmManager.fields`; this node only repaints when it changes.

const SWAY: Shader = preload("res://assets/shaders/sway_rows.gdshader")

var farm: FarmManager
var _cells: Array[FieldCell] = []
var _grid: Vector2i = Vector2i(3, 3)
var _soil: ImageTexture
var _sway_mat: ShaderMaterial
var _dirty: bool = false
var _near_key: String = ""
var _beds_open: bool = false


func setup(owner_manager: TownManager, structure_id: int) -> void:
	farm = owner_manager.farm
	y_sort_enabled = true
	super.setup(owner_manager, structure_id)
	_grid = FarmManager.grid_of(piece)
	_sway_mat = ShaderMaterial.new()
	_sway_mat.shader = SWAY
	_sway_mat.set_shader_parameter("pivot_row", 29.0) ## the crops' feet
	_sway_mat.set_shader_parameter("dir", -1.0) ## rooted at the pivot: the rows above it sway
	_sway_mat.set_shader_parameter("amount", 3.0)
	_sway_mat.set_shader_parameter("flutter", 0.35)
	_sway_mat.set_shader_parameter("cell_w", 8.0)
	var rect: Rect2 = manager.rect_of(id)
	for index: int in _grid.x * _grid.y:
		var at: Vector2i = FarmRules.cell_coords(index, _grid.x)
		var cell: FieldCell = FieldCell.new()
		add_child(cell)
		cell.setup(self, index, Vector2((float(at.x) + 0.5) * float(FarmRules.CELL) - rect.size.x * 0.5, (float(at.y) + 0.5) * float(FarmRules.CELL) - rect.size.y), _sway_mat)
		_cells.append(cell)
	_near_key = _neighbour_key()
	farm.cell_changed.connect(_on_cell_changed)
	farm.reset.connect(_on_reset)
	manager.changed.connect(_on_town_changed)
	_set_active(progress >= TownManager.PROGRESS_FULL)


func _exit_tree() -> void:
	if farm != null:
		if farm.cell_changed.is_connected(_on_cell_changed):
			farm.cell_changed.disconnect(_on_cell_changed)
		if farm.reset.is_connected(_on_reset):
			farm.reset.disconnect(_on_reset)
	if manager != null and manager.changed.is_connected(_on_town_changed):
		manager.changed.disconnect(_on_town_changed)


## The soil is painted, not loaded: the first picture is made here for the base class.
func _load_picture(_texture_name: String) -> Texture2D:
	_soil = ImageTexture.create_from_image(_render())
	return _soil


func _render() -> Image:
	var rects: Array[Rect2] = []
	for field_id: int in manager.structures:
		if bool(TownRules.piece(String((manager.structures[field_id] as Dictionary).p)).get("farm", false)):
			rects.append(manager.rect_of(field_id))
	return FieldSoil.render(rects, manager.rect_of(id), FarmManager.grid_of(piece).x, farm.fields.get(id, {}) as Dictionary, TimeManager.day)


## Which other fields lie close: when this changes (one was built or taken down next door) the edge has to be painted again.
func _neighbour_key() -> String:
	var mine: Rect2 = manager.rect_of(id).grow(float(FieldSoil.MARGIN + 8))
	var parts: PackedStringArray = []
	for field_id: int in manager.structures:
		if field_id != id and bool(TownRules.piece(String((manager.structures[field_id] as Dictionary).p)).get("farm", false)) and mine.intersects(manager.rect_of(field_id)):
			parts.append(str(field_id))
	return ",".join(parts)


func _on_cell_changed(field_id: int, index: int, fx: String) -> void:
	if field_id != id:
		return
	if index >= 0 and index < _cells.size():
		_cells[index].refresh(fx)
	_dirty = true


func _on_reset() -> void:
	for cell: FieldCell in _cells:
		cell.refresh("")
	_dirty = true


func _on_town_changed() -> void:
	if not manager.structures.has(id):
		return ## being taken down
	var key: String = _neighbour_key()
	if key != _near_key:
		_near_key = key
		_dirty = true


func set_progress(value: int, done: bool = false) -> void:
	super.set_progress(value, done)
	_set_active(progress >= TownManager.PROGRESS_FULL)


func _set_active(on: bool) -> void:
	_beds_open = on
	for cell: FieldCell in _cells:
		cell.set_active(on)


func _process(delta: float) -> void:
	super._process(delta)
	if _sway_mat != null:
		_sway_mat.set_shader_parameter("wind", WorldWind.sample(global_position).x)
		_sway_mat.set_shader_parameter("time", _time)
	if _dirty and manager.structures.has(id):
		_dirty = false
		_soil.update(_render())
