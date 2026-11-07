class_name MineChunk
extends Node2D
## A 32 x 32 tile piece of a mine level. Its shape is a smooth field (`MineField`, bent by noise), painted once by `mine_terrain.gdshader` into a texture (`_bake`:
## floor, wall faces and rock top), and the collision is the field's contour as line segments, so the picture and what stops you are the same edge. Rails and the
## ropes of the lamp chains are drawn on top of that. The tile atlas only supplies the rails now (tools/art_mine.py, data/mine_tiles.json).

const SIZE: int = 32
const TILE: int = 16

var cell: Vector2i = Vector2i.ZERO
var layout: MineLayout
var body: StaticBody2D
var decor: HutYard ## the props of this chunk (a sibling in the level, so they y-sort with the players)
var lights: Array[InteriorLight] = []
var rocks: Array[WorldProp] = [] ## MineRocks (registered in the world's table of props, so they are saved, grow back and answer to the pickaxe)
const TERRAIN: Shader = preload("res://assets/shaders/mine_terrain.gdshader")

var field: MineField
var _atlas: Texture2D
var _table: Dictionary
var _blob: PackedInt32Array = PackedInt32Array()
var _full: int = 46
var _cols: int = 8
var _ground: Sprite2D
var _frames: int = 0


func _exit_tree() -> void:
	if is_instance_valid(decor):
		decor.queue_free()
	var world: WorldLevel = get_tree().get_first_node_in_group("world") as WorldLevel if is_inside_tree() else null
	for rock: WorldProp in rocks:
		if is_instance_valid(rock):
			if world != null and world._things.get(rock.cell) == rock:
				world._things.erase(rock.cell)
			rock.queue_free()
	rocks.clear()


func setup(chunk_cell: Vector2i, mine_layout: MineLayout, atlas: Texture2D) -> void:
	cell = chunk_cell
	layout = mine_layout
	_atlas = atlas
	_table = DataRegistry.table("mine_tiles")
	_blob = PackedInt32Array(_table.blob as Array)
	_full = int(_table.full)
	_cols = int(_table.cols)
	position = Vector2(cell * SIZE * TILE)
	z_index = -6 ## above the world's void quads and the level backdrop, below everything that stands
	name = "Chunk_%d_%d" % [cell.x, cell.y]
	body = StaticBody2D.new()
	body.name = "Walls"
	add_child(body)
	field = MineField.new().build(layout, cell)
	var contour: PackedVector2Array = field.segments()
	if not contour.is_empty():
		var shape: ConcavePolygonShape2D = ConcavePolygonShape2D.new()
		shape.segments = contour
		var collider: CollisionShape2D = CollisionShape2D.new()
		collider.shape = shape
		body.add_child(collider)
	_bake()


## Paints the ground and the rock once: a SubViewport renders the shader for one frame, then it stays as the chunk's child (UPDATE_DISABLED) and its texture is the ground sprite.
func _bake() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var zone: Dictionary = MineManager.zone(layout.level)
	var look: Dictionary = zone.get("terrain", {}) as Dictionary
	var view: SubViewport = SubViewport.new()
	view.name = "Bake"
	view.size = Vector2i(SIZE * TILE, SIZE * TILE)
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	view.disable_3d = true
	view.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	var rect: ColorRect = ColorRect.new()
	rect.size = Vector2(view.size)
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = TERRAIN
	material.set_shader_parameter("field", field.texture())
	material.set_shader_parameter("kinds", ImageTexture.create_from_image(field.kinds))
	material.set_shader_parameter("origin", position)
	material.set_shader_parameter("field_origin", position + MineField.origin_px())
	material.set_shader_parameter("field_size", Vector2(MineField.SIDE * MineField.CELL, MineField.SIDE * MineField.CELL))
	material.set_shader_parameter("kinds_tiles", Vector2(field.kinds.get_size()))
	material.set_shader_parameter("useed", field.seed_value & 0x7FFFFFFF)
	material.set_shader_parameter("face", float(look.get("face", 40.0)))
	material.set_shader_parameter("timber", float(look.get("timber", 0.5)))
	material.set_shader_parameter("moss", float(look.get("moss", 0.5)))
	for key: String in ["rock", "floor"]:
		var colors: Array = look.get(key, []) as Array
		for i: int in mini(4, colors.size()):
			material.set_shader_parameter("%s_%s" % [key, "abcd"[i]], Color(String(colors[i])))
	rect.material = material
	view.add_child(rect)
	add_child(view)
	RenderingServer.frame_post_draw.connect(_baked.bind(view), CONNECT_ONE_SHOT)


func _baked(view: SubViewport) -> void:
	_frames += 1
	if _frames < 2 and is_instance_valid(view):
		RenderingServer.frame_post_draw.connect(_baked.bind(view), CONNECT_ONE_SHOT)
		return
	if not is_instance_valid(view):
		return
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED ## rendered once: the picture stays on the GPU as the viewport's texture (no CPU readback)
	_ground = Sprite2D.new()
	_ground.name = "Ground"
	_ground.centered = false
	_ground.show_behind_parent = true ## under the rails and ropes this node draws itself
	_ground.texture = view.get_texture()
	add_child(_ground)


## The row (level px) where the floor begins under the rock at this x: things that hang on or lean at a wall are set on the real edge, not on the tile border.
func wall_edge(at: Vector2) -> float:
	var local: Vector2 = at - position
	var y: float = local.y
	if field.is_rock(Vector2(local.x, y)):
		for step: int in 24: ## inside the rock: down to the floor
			y += 1.0
			if not field.is_rock(Vector2(local.x, y)):
				return position.y + y
	else:
		for step: int in 24: ## on the floor: up to the rock
			if field.is_rock(Vector2(local.x, y - 1.0)):
				return position.y + y
			y -= 1.0
	return at.y


## Bit mask of the eight neighbours that are wall (outside the level counts as wall): N=1 NE=2 E=4 SE=8 S=16 SW=32 W=64 NW=128.
func wall_mask(x: int, y: int) -> int:
	var m: int = 0
	if not layout.is_floor(x, y - 1): m |= 1
	if not layout.is_floor(x + 1, y - 1): m |= 2
	if not layout.is_floor(x + 1, y): m |= 4
	if not layout.is_floor(x + 1, y + 1): m |= 8
	if not layout.is_floor(x, y + 1): m |= 16
	if not layout.is_floor(x - 1, y + 1): m |= 32
	if not layout.is_floor(x - 1, y): m |= 64
	if not layout.is_floor(x - 1, y - 1): m |= 128
	return m


func _src(index: int, row0: int) -> Rect2:
	return Rect2(float((index % _cols) * TILE), float((row0 + index / _cols) * TILE), float(TILE), float(TILE))


func _draw() -> void:
	var x0: int = cell.x * SIZE
	var y0: int = cell.y * SIZE
	for rail: Vector3i in layout.chunk_rails.get(cell, []) as Array: ## rails lie on the floor, under the shade
		draw_texture_rect_region(_atlas, Rect2(float((rail.x - x0) * TILE), float((rail.y - y0) * TILE), float(TILE), float(TILE)), _src(rail.z, int(_table.rails_row)))
	for cable: Dictionary in layout.chunk_cables.get(cell, []) as Array: ## the ropes of the lamp chains
		var a: Vector2 = (cable.a as Vector2) - position
		var b: Vector2 = (cable.b as Vector2) - position
		var sag: float = 4.0 + absf(b.x - a.x) * 0.05
		var previous: Vector2 = a
		for i: int in range(1, 9):
			var t: float = float(i) / 8.0
			var point: Vector2 = a.lerp(b, t) + Vector2(0.0, sag * 4.0 * t * (1.0 - t))
			point = point.round()
			draw_line(previous + Vector2(0, 1), point + Vector2(0, 1), Color("14101c"), 1.0)
			draw_line(previous, point, Color("7c6a42") if i % 3 else Color("a8946a"), 1.0)
			previous = point
