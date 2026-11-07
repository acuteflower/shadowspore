class_name MineLevel
extends Node2D
## One built level of the mine at its slot (`MineManager.origin`). Streams its 32 x 32 tile chunks around the players that are in it (3 x 3 kept, dropped
## beyond 2 chunks away; the chunk a player stands in or sees is built at once, others one per frame) and owns the dark backdrop behind the rock.

const CHUNK: int = MineChunk.SIZE
const NEAR: float = 360.0 ## px: a missing chunk this close to a player is built at once
const KEEP: int = 2
const LIGHT_CAP: int = 28 ## lights shining at once (the rest of the loaded ones are switched off, the farthest first)
const LIGHT_REACH: float = 520.0
const PROP_FEET: Dictionary = {"lamp": 36, "lamp_dead": 36} ## the row of the sprite that stands on the position, where it differs from mine_props.json

var level: int = 1
var layout: MineLayout
var chunks: Dictionary = {} ## Vector2i -> MineChunk
var idle: float = 0.0 ## seconds without a player (the manager frees the level after a while)
var _atlas: Texture2D
var _backdrop: ColorRect
var _points: Array[Vector2] = [] ## where the players are (level px), from the last `stream`
var _light_clock: float = 0.0


func setup(level_number: int, mine_layout: MineLayout) -> void:
	level = level_number
	layout = mine_layout
	name = "Level_%d" % level
	y_sort_enabled = true
	position = MineManager.origin(level)
	var table: Dictionary = DataRegistry.table("mine_tiles")
	var style: String = String(MineManager.zone(level).get("tile_style", "timber"))
	_atlas = load(String((table.styles as Dictionary)[style])) as Texture2D
	_backdrop = ColorRect.new() ## the world's void quads would show through otherwise
	_backdrop.size = Vector2(layout.edge * 16 + 512, layout.edge * 16 + 512)
	_backdrop.position = Vector2(-256, -256)
	_backdrop.z_index = -7
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.color = Color(String((table.backdrops as Dictionary)[style])) ## the colour of the rock tops: the unseen inside of the mass
	add_child(_backdrop)


## Builds the chunks around the given positions (level px). A chunk a player stands in is built at once; every other missing chunk comes in
## one per frame, the near ones (within NEAR) before the far ones, nearest first, so a fresh level never builds a ring of chunks in one frame.
func stream(points: Array[Vector2]) -> void:
	idle = 0.0
	_points = points
	var wanted: Dictionary = {}
	var near_cell: Vector2i = Vector2i(-1, -1)
	var near_d: float = 1e30
	var queue_cell: Vector2i = Vector2i(-1, -1)
	var queue_d: float = 1e30
	for p: Vector2 in points:
		var c: Vector2i = Vector2i(floori(p.x / (CHUNK * 16.0)), floori(p.y / (CHUNK * 16.0)))
		for dy: int in range(-1, 2):
			for dx: int in range(-1, 2):
				var n: Vector2i = c + Vector2i(dx, dy)
				var last: int = (layout.edge + CHUNK - 1) / CHUNK ## one ring of chunks beyond the level is painted too: solid rock out to the camera's limits
				if n.x < -1 or n.y < -1 or n.x > last or n.y > last:
					continue
				wanted[n] = true
				if chunks.has(n):
					continue
				var rect: Rect2 = Rect2(Vector2(n * CHUNK * 16), Vector2.ONE * CHUNK * 16.0)
				var d: float = rect.grow(0.0).get_center().distance_to(p)
				var gap: float = maxf(maxf(rect.position.x - p.x, p.x - rect.end.x), maxf(rect.position.y - p.y, p.y - rect.end.y))
				if gap <= 0.0: ## the player stands in it: at once
					build(n)
				elif gap < NEAR:
					if d < near_d:
						near_d = d
						near_cell = n
				elif d < queue_d:
					queue_d = d
					queue_cell = n
	var pick: Vector2i = near_cell if near_cell.x >= 0 else queue_cell
	if pick.x >= 0 and not chunks.has(pick):
		build(pick)
	for c: Vector2i in chunks.keys():
		var far: bool = true
		for p: Vector2 in points:
			var pc: Vector2i = Vector2i(floori(p.x / (CHUNK * 16.0)), floori(p.y / (CHUNK * 16.0)))
			if absi(c.x - pc.x) <= KEEP and absi(c.y - pc.y) <= KEEP:
				far = false
				break
		if far:
			(chunks[c] as MineChunk).queue_free()
			chunks.erase(c)


func build(c: Vector2i) -> void:
	if chunks.has(c):
		return
	var chunk: MineChunk = MineChunk.new()
	chunk.setup(c, layout, _atlas)
	add_child(chunk)
	chunks[c] = chunk
	_dress(chunk)


## Solid footprints of the props: [width, depth, x offset, y offset] in px from the feet.
const SOLID: Dictionary = {
	"crates": [56, 10, -28, -8], "barrel": [18, 9, -9, -8], "sacks": [40, 9, -20, -8], "bunk": [56, 10, -28, -10], "table": [66, 10, -33, -8], "stool": [10, 6, -5, -5],
	"cart": [56, 12, -28, -10], "cart_loaded": [56, 12, -28, -10], "stalagmites": [30, 8, -15, -6], "waysign": [8, 6, -4, -5], "shelf": [64, 8, -32, -8],
	"pots": [34, 8, -17, -8], "post": [8, 6, -4, -5], "stairs_up": [70, 10, -35, -8], "stairs_down": [56, 20, -28, -36], "winch": [72, 12, -36, -10],
	"fire_pit": [34, 14, -17, -11], "seat_log": [32, 7, -16, -6], "seat_stump": [12, 6, -6, -4], "nest": [40, 12, -20, -10],
	"anvil": [26, 8, -13, -6], "forge": [48, 16, -24, -14], "quench": [34, 8, -17, -6], "crystal_a": [22, 8, -11, -6], "crystal_b": [22, 8, -11, -6], "crystal_big": [28, 10, -14, -8],
	"void_pod": [14, 7, -7, -5],
}
const HUT: String = "res://assets/interior/hut/"
## Props that are not in mine_props.json (the hut's fire and seats) or that differ from it.
const SPECIAL: Dictionary = {
	"fire_pit": {"tex": HUT + "yard_pit.png", "feet": 46, "glow": true, "anim": {"tex": HUT + "yard_fire.png", "frames": 8, "fps": 11, "at": [0, 0], "feet": 27}, "sparks": true, "smoke": true, "sound": "fire.wav"},
	"forge": {"tex": "res://assets/mine/props/forge.png", "feet": 76, "glow": true, "anim": {"tex": HUT + "yard_fire.png", "frames": 8, "fps": 11, "at": [0, -9], "feet": 27}, "smoke": true},
	"seat_log": {"tex": HUT + "yard_seats.png", "frames": 4, "frame": 0, "feet": 26},
	"seat_stump": {"tex": HUT + "yard_seats.png", "frames": 4, "frame": 1, "feet": 26},
}
const WALL_ATTACHED: Dictionary = {"lamp": 1.0, "lamp_dead": 1.0, "ladder": 3.0, "chain": 3.0} ## kind -> how far under the wall's edge its feet stand
const FLAT_KINDS: Array[String] = ["bones", "puddle_a", "puddle_b", "web", "void_crack", "void_eyes", "rubble_a", "rubble_b", "rubble_c", "planks", "pickaxe", "rope", "bucket", "lantern_floor"]


## The props, lights and ropes of a chunk: the sprites (with their glow sheets) come from `HutYard`, the lights are always on; chests, notes, drips and
## shafts are nodes of their own.
func _dress(chunk: MineChunk) -> void:
	var table: Dictionary = DataRegistry.table("mine_props")
	var mines: MineManager = get_parent() as MineManager
	var specs: Array = []
	var nodes: Array[Node2D] = []
	for entry: Dictionary in layout.chunk_props.get(chunk.cell, []) as Array:
		var kind: String = String(entry.kind)
		var at: Vector2 = Vector2(float(entry.x), float(entry.y))
		if WALL_ATTACHED.has(kind): ## hangs or leans on a wall: on the real edge of the smooth rock
			at.y = chunk.wall_edge(at) + float(WALL_ATTACHED[kind])
		var info: Dictionary = (SPECIAL.get(kind) as Dictionary) if SPECIAL.has(kind) else (table.get(kind, {}) as Dictionary)
		match kind:
			"drip":
				var drip: MineDrip = MineDrip.new()
				drip.position = at
				drip.every = float(entry.get("every", 4.0))
				nodes.append(drip)
				continue
			"shaft":
				var shaft: MineShaft = MineShaft.new()
				shaft.position = at
				nodes.append(shaft)
				continue
			"chest":
				var key: String = "chest:%d:%d" % [level, floori(at.x / 16.0) + floori(at.y / 16.0) * layout.edge]
				var chest: MineChest = MineChest.new()
				chest.position = at
				chest.setup(key, String(info.tex), int(info.feet), mines != null and mines.is_set(key))
				nodes.append(chest)
				continue
			"notes":
				var note: MineNote = MineNote.new()
				note.position = at
				note.z_index = -5
				note.setup(layout.zone_id, floori(at.x / 16.0) * 31 + floori(at.y / 16.0), String(info.tex), int(info.feet))
				nodes.append(note)
				continue
		if kind == "stairs_up" or kind == "stairs_down": ## the way up and the way down are used with E
			var stairs: MineStairs = MineStairs.new()
			stairs.position = at + Vector2(0.0, 10.0 if kind == "stairs_up" else 6.0)
			stairs.level = level
			stairs.up = kind == "stairs_up"
			nodes.append(stairs)
		elif kind == "winch":
			var winch: MineWinch = MineWinch.new()
			winch.position = at + Vector2(0.0, 2.0)
			winch.level = level
			nodes.append(winch)
		if info.is_empty():
			continue
		var spec: Dictionary = {"id": kind, "tex": String(info.tex), "pos": [at.x, at.y], "feet": int(PROP_FEET.get(kind, int(info.feet))), "glow": bool(info.get("glow", false)) if SPECIAL.has(kind) else info.has("glow")}
		if SPECIAL.has(kind):
			spec.merge(info, true)
			spec.pos = [at.x, at.y]
		if SOLID.has(kind) and not bool(entry.get("nosolid", false)):
			spec.solid = SOLID[kind]
		if kind in FLAT_KINDS:
			spec.z = -5
		spec.merge(entry.get("spec", {}) as Dictionary, true)
		specs.append(spec)
	var yard: HutYard = HutYard.new()
	yard.name = "Decor_%d_%d" % [chunk.cell.x, chunk.cell.y]
	add_child(yard)
	yard.setup(specs)
	for node: Node2D in nodes:
		yard.add_child(node)
	chunk.decor = yard
	var world: WorldLevel = mines.get_parent() as WorldLevel if mines != null else null
	if world != null:
		for r: Dictionary in layout.chunk_rocks.get(chunk.cell, []) as Array:
			var global: Vector2 = position + Vector2(float(r.x), float(r.y))
			var cell: Vector2i = Vector2i(floori(global.x / 16.0), floori(global.y / 16.0))
			if world._things.has(cell):
				continue
			var rock: WorldProp = world._spawn_thing(cell, String(r.kind), int(r.variant))
			if rock == null:
				continue
			rock.position = global
			chunk.rocks.append(rock)
	for l: Dictionary in layout.chunk_lights.get(chunk.cell, []) as Array:
		var light: InteriorLight = InteriorLight.new()
		light.position = Vector2(float(l.x), float(l.y))
		light.radius = int(l.radius)
		light.squash = 0.8
		light.base_energy = float(l.energy)
		light.glow_color = Color(String(l.color))
		light.flicker = float(l.flicker)
		yard.add_child(light)
		chunk.lights.append(light)


func _process(delta: float) -> void:
	_light_clock -= delta
	if _light_clock > 0.0:
		return
	_light_clock = 0.2
	_cull_lights()


## Only the lights near a player shine, at most LIGHT_CAP of them: a lit level may hold hundreds.
func _cull_lights() -> void:
	var ranked: Array[Array] = []
	for chunk: MineChunk in chunks.values():
		for light: InteriorLight in chunk.lights:
			var nearest: float = 1e9
			for p: Vector2 in _points:
				nearest = minf(nearest, p.distance_to(light.position))
			ranked.append([nearest, light])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for i: int in ranked.size():
		(ranked[i][1] as InteriorLight).enabled = i < LIGHT_CAP and float(ranked[i][0]) < LIGHT_REACH


## The chunk with a tile in it, at once.
func build_at(tile: Vector2i) -> void:
	build(Vector2i(tile.x / CHUNK, tile.y / CHUNK))
