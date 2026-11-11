class_name WorldLevel
extends TestLevel
## The real world: the frozen RegionMap (data/world_map.json) painted in chunks around the players.
## Every peer paints its own ground from the same data, so only gameplay state is networked.
## Named areas share the world's selected biome; ground, foliage and wildlife follow that biome.
## Land ends where the baked coast ends
## (assets/world/land_sdf.png, see tools/bake_land_sdf.gd): the void beyond is blocked by collision
## and drawn by `VoidEdge`; a violet light shines along the edge at night.

const SKY_CLEAVER_SCENE: PackedScene = preload("res://src/entities/enemies/sky_cleaver.tscn")
const CHUNK: int = 32 ## tiles per chunk side
const STREAM_BUDGET_USEC: int = 2000 ## cooperative CPU preparation per frame
const STREAM_URGENT_USEC: int = 5000 ## ... while the chunk being built touches a player's own ring (it may come into view soon)
const STREAM_OWN_CHUNK_USEC: int = 4000 ## cooperative CPU preparation when the player stands in the building chunk
const MAX_UNLOADS_PER_FRAME: int = 1 ## unloads are queued to avoid frame spikes from clearing multiple chunks at once
const LOOKAHEAD_SECONDS: float = 2.5 ## the ring round where a moving player will be this soon is loaded too (ahead of the camera)
const LOOKAHEAD_MAX_SPEED: float = 420.0 ## px/s; faster jumps are teleports, not running
const DETAIL_BUCKET: float = 64.0
const GEN_PHASES: int = 5 ## phases 0-4 only read static inputs and build detached nodes: they run as one job on a worker thread
const PREFETCH: int = 4 ## chunks whose worker job is started ahead (nearest first)
const LOAD_RADIUS: int = 1 ## chunks around every player that are kept painted
const UNLOAD_RADIUS: int = 2 ## farther chunks are dropped (the gap stops flicker at the border)
const BORDER_WARP: float = 5.0 ## tiles; jitter that roughens the 4-tile lookup grid of the map
const PICK_SLACK: float = 14.0 ## px the host forgives on top of the interaction range
const STONE_BED: Texture2D = preload("res://assets/props/stonebed.png")
const FOREST_BED: Texture2D = preload("res://assets/props/forestbed.png")
const FOREST_BED_FRAME: Vector2i = Vector2i(192, 128)
const FOREST_BED_FLATTEN: float = 0.64 ## the litter patches are drawn as flattened ellipses (tools/art_forestbed.py)
const SDF_TEXTURE: Texture2D = preload("res://assets/world/land_sdf.png")
const OUTER_SDF: Texture2D = preload("res://assets/world/outer_sdf.png")
const VOID_MARGIN: float = 6.0 ## px the void's collision reaches into the land (the edge shader eats that far)
const EDGE_LIGHT_CELL: int = 8 ## tiles; one edge light per cell that touches the coast
const EDGE_LIGHT_COLOR: Color = Color("8a4dff")
const DIRECTIONS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]
const INTRO_SPAWN: Vector2 = Vector2(36.0, 12.0) ## px from the cover's middle where she stands up (after the crawl) and where players start
const PLACEHOLDER_CHANCE: float = 0.08 ## share of placeholder tiles that carry a decoration

var fallen_knight: FallenKnight

var edits: WorldEdits = WorldEdits.new()
var editor_camera: Camera2D
var _cliffs: ReliefLayer

var _map: RegionMap
var _layers: Dictionary = {} ## biome id -> TileMapLayer
var _chunks: Dictionary = {} ## Vector2i -> Chunk
var _zone: FastNoiseLite
var _warp_x: FastNoiseLite
var _warp_y: FastNoiseLite
var _props: Node2D ## y-sorted: bushes
var _generator: PropGenerator
var sowing: PlantSowing ## plants that seeded themselves (saved with the props)
var _things: Dictionary = {} ## Vector2i cell -> WorldProp (loaded ones)
var _young: Dictionary = {} ## cell -> {"age", "variant"}: saplings the generator planted; their stage follows the day (see `_young_state`), nothing is stored
var _thing_states: Dictionary = {} ## cell -> state dict, only for props that are not untouched (every peer)
var _harvest_states: Dictionary = {} ## "c:x,y" clover field / "l:x,y" fallen log -> state ({"h": hits, "f": 1 = cut}), only where touched (every peer)
var _harvest_nodes: Dictionary = {} ## the same keys -> the CloverField / FallenLog node while its chunk is loaded
var _sdf: PackedByteArray ## baked coast: one byte per tile, 128 = coast, above = land
var _outer_sdf: PackedByteArray ## exterior coast only: inland lakes carry no void rim/light
var _rivers: WorldRivers
var _arena_phase: Dictionary = {} ## arena id -> the phase its boss fight restarts from after a wipe (set by `SkyCleaver.checkpoint_reached`, not saved)
var _relief: Relief ## baked height levels (walls, ramps, stairs)
var _start: Vector2i
var cover_node: ManholeCover ## the manhole cover (the intro animates its lid)
var _berry_free: Dictionary = {} ## tiles of the story's first stretch: no berries (nothing heals her)
var _barriers: Dictionary = {} ## id -> StaticBody2D: the invisible walls that keep her near the footpath
var _stone_cells: Dictionary = {} ## tiles lying on the old flagstones: no trees there
var opening_over: bool = false
var witch_arena: WitchArena
var _cover_at: Vector2 = Vector2.ZERO ## the manhole cover (world px), where the story starts; zero = none baked
var _building: ChunkBuild
var _gen_pool: Array[PropGenerator] = [] ## forks of `_generator` for the worker jobs (each has its own cluster cache)
var _gen_lock: Mutex = Mutex.new()
var _paused_builds: Dictionary = {} ## Vector2i -> ChunkBuild: half-prepared chunks the stream moved away from; kept while still wanted
var _pending_commit: ChunkBuild ## committed ground waiting one frame for its props (see `_finish_commit`)
var night: NightDirector ## host: spawns and steers the creatures of the night
var knight_taken: bool = false ## Valdric is a settler (`take_knight`): the story actor stays hidden
var _town_node: TownManager ## the player's town (docs/town.md): what it has cleared stays cleared
var _tiles: Dictionary

@onready var _wildlife: WildlifePopulation = $Wildlife


## What a loaded chunk owns, so it can be taken down again.
class Chunk:
	var node: Node2D ## lights and collision
	var cells: Dictionary = {} ## biome id -> Array[Vector2i] painted on that layer
	var atlas: Dictionary = {} ## cell -> atlas coordinates, applied only at commit
	var glow_cells: Array[Vector2i] = []
	var water_near: bool = true ## no river chunk in the 3x3 neighbourhood: every tile is clear of water (see `_paint`)
	var things: Array[WorldProp] = []
	var fallen_logs: Array[FallenLog] = []
	var clover: Array[CloverField] = [] ## standing clover fields, y-sorted in the Props chain


## Detached preparation: no partial terrain, collision, interaction or wildlife enters
## the live world. Each work unit is a row, cluster, prop or detail candidate.
class ChunkBuild:
	var cell: Vector2i
	var chunk: Chunk
	var query: PropGenerator.Query
	var phase: int = 0
	var index: int = 0
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var body: StaticBody2D
	var open_runs: Dictionary = {}
	var lit_cells: Dictionary = {}
	var reserved: Dictionary = {}
	var custom_keys: Array = []
	var custom: Dictionary = {}
	var obstacles: Array[Dictionary] = []
	var obstacle_grid: Dictionary = {}
	var log_grid: Dictionary = {} ## every obstacle by the bucket of its centre, for FallenLogScatter (edited ones included)
	var log_reach: float = 0.0 ## the largest final-check radius among them
	var beds: Array[Dictionary] = [] ## the forest floors of this chunk and its neighbours {pos, rx}: what grows between the trees changes there
	var points: Array[Dictionary] = []
	var density: Dictionary = {} ## the wind's detail densities, read once per chunk
	var clover_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var clover_count: int = 0
	var clover_discs: Array[Vector3] = [] ## (x, y, rx) of the fields placed so far (read instead of the nodes, which a worker may still be painting)
	var clover_jobs: Array[Jobs.Job] = [] ## each field paints its atlas on a worker (`CloverField.setup`); phase 9 waits for them
	var commit_index: int = 0 ## props of `chunk.things` already added to the tree by `_finish_commit`
	var commit_stage: int = 0 ## 0 = props, 1 = logs, 2 = clover, 3 = finalize
	var commit_sub_index: int = 0 ## index within logs or clover
	var patches_seen: Array[Node] = [] ## Terrain.patches as this chunk last saw them (compared per candidate)
	var job: Jobs.Job ## phases 0-4 (generator, ground, cliffs, prop nodes) run on a worker thread (Jobs); null = not started / sliced on the main thread
	var beds_pending: Array[Dictionary] = [] ## forest beds that passed the worker checks; the surface patches decide on the main thread
	var gen_ready: bool = false ## the job delivered: phases 0-4 are done, the build is the main thread's again
	var filtered: bool = false ## the prepared props were checked against the live world (`_filter_prepared`)
	var young: Dictionary = {} ## cell -> sapling record, applied to `_young` by `_filter_prepared`


func _fill_ground() -> void:
	RenderingServer.set_default_clear_color(Color("120e1f")) ## the void behind the land
	LightTexture.prewarm(PackedInt32Array([24, 26, 28, 34, 36, 40])) ## the common glow/night light cookies, before the first chunk needs them
	_map = RegionMap.new(0, DataRegistry.table("world_map"))
	_tiles = DataRegistry.table("grass_tiles")
	_props = Node2D.new()
	_props.name = "Props"
	_props.y_sort_enabled = true
	add_child(_props)
	_zone = _noise(11, 0.035, 2)
	_warp_x = _noise(21, 1.0 / 14.0, 1)
	_warp_y = _noise(22, 1.0 / 14.0, 1)
	var image: Image = SDF_TEXTURE.get_image()
	image.convert(Image.FORMAT_L8)
	_sdf = image.get_data()
	var outer_image: Image = OUTER_SDF.get_image()
	outer_image.convert(Image.FORMAT_L8)
	_outer_sdf = outer_image.get_data()
	var interiors: Interiors = Interiors.new() ## the pocket spaces behind the doors (huts, houses)
	add_child(interiors)
	var mines: MineManager = MineManager.new() ## the mine: fixed levels far outside the world (docs/mine.md)
	mines.setup(_map.world_seed)
	add_child(mines)
	_town_node = TownManager.new() ## the town the group builds on the meadow (docs/town.md)
	_town_node.setup(self)
	add_child(_town_node)
	var discovery: MapDiscovery = MapDiscovery.new() ## the fog of the map (M)
	discovery.name = "MapDiscovery"
	add_child(discovery)
	var waystones: Waystones = Waystones.new() ## the goddess statues (teleport points): which are awake (docs/waystones.md)
	waystones.name = "Waystones"
	add_child(waystones)
	var relics: BossRelics = BossRelics.new() ## what the bosses leave to one player alone (docs/rissfeder.md)
	relics.name = "BossRelics"
	add_child(relics)
	var loot_chests: LootChests = LootChests.new() ## the loot chests of the wild and the bosses' Glutreliquiare (docs/beutetruhen_konzept.md)
	loot_chests.name = "LootChests"
	add_child(loot_chests)
	var pets: PetRegistry = PetRegistry.new() ## the bond with wild crows and ravens (docs/pet_konzept.md)
	pets.name = "PetRegistry"
	add_child(pets)
	_relief = Relief.new()
	Terrain.relief = _relief
	if multiplayer.is_server():
		edits.read()
	_relief.editor_apply(edits.terrain)
	_cliffs = ReliefLayer.new()
	_cliffs.setup(_relief.editor_texture, _relief.editor_field, _relief)
	add_child(_cliffs)
	var edge: VoidEdge = VoidEdge.new()
	edge.setup(OUTER_SDF)
	add_child(edge)
	var biomes: Dictionary = DataRegistry.table("biomes")
	for id: String in biomes:
		var active: String = RegionMap.active_biome(id)
		if not _layers.has(active):
			_layers[active] = _ground if active == "meadow" or (biomes[active] as Dictionary).has("gloom") else _make_layer(active, Color((biomes[active] as Dictionary).color as String)) ## a biome with `gloom` is painted by the ground shader itself (palette mixed by BiomeBlend), on the shared layer
		_layers[id] = _layers[active]
	_start = _map.start if _map.start.x >= 0 else _map.anchor(_map.start_region)
	var cleared: Rect2i = Rect2i() ## nothing is cleared by area any more: the generator fills the start like everywhere else (only the footpath and the cover stay free)
	_generator = PropGenerator.new(_zone, _sdf, _relief, cleared, _map.world_seed)
	Moisture.world_seed = _map.world_seed
	_generator.bare = _map.bare_cells()
	BiomeBlend.install(_map)
	_generator.blocked_cells = _add_ground_decals()
	_generator.extra_props = _extra_props()
	_rivers = WorldRivers.new()
	_rivers.name = "Rivers"
	add_child(_rivers)
	_generator.water_clear = _rivers.clear_for_prop
	_generator.water_dist = func(at: Vector2) -> float: return _rivers.field_at(at).x
	_generator.tree_free_cells = _stone_cells
	_generator.berry_free_cells = _berry_free
	var scenes: Array[String] = []
	for plant: Variant in DataRegistry.table("plants").values(): ## the worker jobs instantiate these: load them (and their scripts) here first, see Jobs.warm
		var path: String = String((plant as Dictionary).get("scene", ""))
		if not path.is_empty() and not scenes.has(path): scenes.append(path)
	Jobs.warm(scenes)
	var wind: WorldWind = WorldWind.new()
	wind.name = "WorldWind"
	wind.setup(self)
	add_child(wind)
	_wildlife.setup(_map.world_seed, _rabbit_habitat, _bird_habitat, _fauna_habitat, _flower_targets)
	var encounters: WildlifeEvents = WildlifeEvents.new()
	encounters.name = "WildlifeEvents"
	encounters.setup(self)
	add_child(encounters)
	sowing = PlantSowing.new() ## seed flight and the town's edge flowers (docs/plant_life.md)
	sowing.setup(self)
	add_child(sowing)
	night = NightDirector.new() ## the night (docs/nacht_monster_konzept.md): the host's director
	night.setup(self)
	add_child(night)
	_stream(true)
	fallen_knight = FallenKnight.new()
	fallen_knight.name = "FallenKnight"
	var knight_tile: Array = DataRegistry.get_entry("ground", "fallen_knight").get("tile", [501,685])
	fallen_knight.position = Vector2(float(knight_tile[0]), float(knight_tile[1])) * 16 + Vector2(8,8)
	add_child(fallen_knight)
	_spawn_guards.call_deferred()
	if multiplayer.is_server() and not opening_over:
		TimeManager.lock_at(0.0) ## day 1, 00:00: the opening is at night, the clock stands still until she reaches the town
	TimeManager.day_started.connect(_age_young) ## every peer counts the days itself
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(func(id: int) -> void: _rpc_thing_snapshot.rpc_id(id, _thing_states))
		multiplayer.peer_connected.connect(func(id: int) -> void: _rpc_harvest_snapshot.rpc_id(id, _harvest_states))
		TimeManager.day_started.connect(_grow_things)
		multiplayer.peer_connected.connect(func(id: int) -> void: _rpc_editor_snapshot.rpc_id(id, edits.data()))


## The hand-authored ground (tools/bake_ground.py): old flagstone fields, the footpath and the manhole cover. Returns the tiles
## the props must keep clear (along the footpath and around the cover).
func _add_ground_decals() -> Dictionary:
	var baked: Dictionary = DataRegistry.table("ground_baked")
	var decals: Array = baked.get("decals", []) as Array
	for i: int in range(decals.size() - 1, -1, -1): ## the footpath first, the stones lie over its start
		var spec: Dictionary = decals[i] as Dictionary
		var decal: GroundDecal = GroundDecal.new()
		decal.setup(String(spec.texture), String(spec.mask), Vector2(float(spec.x), float(spec.y)), String(spec.get("glow", "")))
		add_child(decal)
		var size: Vector2 = decal.texture.get_size()
		for ty: int in range(int(spec.y) / 16, int((float(spec.y) + size.y) / 16.0) + 1):
			for tx: int in range(int(spec.x) / 16, int((float(spec.x) + size.x) / 16.0) + 1):
				if decal.surface_at(Vector2(tx, ty) * 16.0 + Vector2(8, 8)) == "stone":
					_stone_cells[Vector2i(tx, ty)] = true
	for barrier: Dictionary in baked.get("barriers", []) as Array:
		var body: StaticBody2D = StaticBody2D.new()
		body.name = "Barrier_" + String(barrier.id)
		for rect: Array in barrier.rects as Array:
			var shape: CollisionShape2D = CollisionShape2D.new()
			var box: RectangleShape2D = RectangleShape2D.new()
			box.size = Vector2(float(rect[2]), float(rect[3]))
			shape.shape = box
			shape.position = Vector2(float(rect[0]), float(rect[1])) + box.size / 2.0
			body.add_child(shape)
		add_child(body)
		_barriers[String(barrier.id)] = body
	for run: Array in baked.get("berry_free", []) as Array:
		for tx: int in range(int(run[0]), int(run[2]) + 1):
			_berry_free[Vector2i(tx, int(run[1]))] = true
	var clear: Dictionary = {}
	var knight: Dictionary = DataRegistry.get_entry("ground", "fallen_knight")
	var tile: Array = knight.get("tile", [501,685])
	_clear_around(clear, Vector2(float(tile[0]), float(tile[1])) * 16 + Vector2(8,8), int(knight.get("clear_radius", 4)))
	for sign_spec: Dictionary in DataRegistry.table("ground").get("signposts", []) as Array: ## standard signposts (Signpost)
		var post: Signpost = Signpost.new()
		var stile: Array = sign_spec.tile as Array
		post.name = "Signpost_" + String(sign_spec.id)
		post.position = Vector2(float(stile[0]), float(stile[1])) * 16.0 + Vector2(8, 8)
		post.variant = int(sign_spec.get("variant", 0))
		post.dialogue_id = String(sign_spec.get("dialogue", ""))
		post.flag = String(sign_spec.get("flag", ""))
		add_child(post)
		_clear_around(clear, post.position, int(sign_spec.get("clear_radius", 3)))
	var crow_site: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/crow_tree_site.json")) as Dictionary
	var crow_tree: CrowTree = CrowTree.new()
	crow_tree.name = "CrowTree"
	crow_tree.position = Vector2(float(crow_site.tile[0]), float(crow_site.tile[1])) * 16.0 + Vector2(8, 8)
	add_child(crow_tree)
	_clear_around(clear, crow_tree.position, int(crow_site.clear_radius))
	witch_arena = WitchArena.new() ## Morwenna's fight under the tree (docs/enemies/boss_mora.md)
	add_child(witch_arena)
	witch_arena.setup(self)
	for tower_spec: Dictionary in DataRegistry.table("ground").get("towers", []) as Array: ## the Hexenwald's witch tower, origin = the foot of its gate
		var tower: WitchTower = WitchTower.new()
		var ttile: Array = tower_spec.tile as Array
		tower.name = "Tower_" + String(tower_spec.id)
		tower.position = Vector2(float(ttile[0]), float(ttile[1])) * 16.0 + Vector2(8, 8)
		add_child(tower)
		_clear_around(clear, tower.position + Vector2(0, -16), 9) ## the body and the yard stay free of generated plants
	for stone_spec: Dictionary in DataRegistry.table("waystones").get("statues", []) as Array: ## the waystones, goddess statues on their plinths (WaystoneStatue)
		var statue: WaystoneStatue = WaystoneStatue.new()
		var wtile: Array = stone_spec.tile as Array
		statue.name = "Waystone_" + String(stone_spec.id)
		statue.id = String(stone_spec.id)
		statue.display_name = String(stone_spec.get("name", ""))
		statue.reveal_cells = float(stone_spec.get("reveal", 15.0))
		statue.position = Vector2(float(wtile[0]), float(wtile[1])) * 16.0 + Vector2(8, 8)
		add_child(statue)
		_clear_around(clear, statue.position, int(stone_spec.get("clear_radius", 5)))
	for hut_spec: Dictionary in DataRegistry.table("ground").get("huts", []) as Array: ## buildings with an interior behind their door
		var hut: Hut = Hut.new()
		var htile: Array = hut_spec.tile as Array
		hut.name = "Hut_" + String(hut_spec.id)
		hut.interior_id = String(hut_spec.interior)
		hut.art = String(hut_spec.get("art", "hut"))
		hut.yard_props = (hut_spec.get("yard", {}) as Dictionary).get("props", []) as Array
		hut.position = Vector2(float(htile[0]), float(htile[1])) * 16.0 + Vector2(8, 8)
		add_child(hut)
		(get_node("Interiors") as Interiors).register_entrance(hut.interior_id, hut)
		_clear_around(clear, hut.position + Vector2(0, -10), int(hut_spec.get("clear_radius", 8)))
		if hut_spec.has("ring"): ## ward stones round the house (the lake witch's, docs/seehexe_konzept.md 3.3)
			var ring: WardRing = WardRing.new()
			ring.name = "WardRing_" + String(hut_spec.id)
			ring.setup(String(hut_spec.id), hut_spec.ring as Dictionary, hut.position)
			add_child(ring)
			for stone: Array in ring.stones:
				_clear_around(clear, ring.position + (stone[0] as Vector2), 1)
			if String(hut_spec.id) == "lake_hut": ## the lake witch's entry quest "Der Ring am See"
				var story: LakeWitchStory = LakeWitchStory.new()
				story.setup(hut, ring)
				add_child(story)
	for quarry_spec: Dictionary in DataRegistry.table("ground").get("quarries", []) as Array: ## the quarry where the knight is mining
		var quarry: Quarry = Quarry.new()
		var qtile: Array = quarry_spec.tile as Array
		quarry.name = "Quarry_" + String(quarry_spec.id)
		quarry.spec = quarry_spec
		quarry.position = Vector2(float(qtile[0]), float(qtile[1])) * 16.0 + Vector2(8, 8)
		add_child(quarry)
		_clear_around(clear, quarry.position + Vector2(-50, -14), int(quarry_spec.get("clear_radius", 9)))
	for wagon_spec: Dictionary in DataRegistry.table("ground").get("wagons", []) as Array: ## Gustav's wrecked wagon (quest gustav_rescue)
		var wagon: GustavWagon = GustavWagon.new()
		var wtile2: Array = wagon_spec.tile as Array
		wagon.name = "Wagon_" + String(wagon_spec.id)
		wagon.position = Vector2(float(wtile2[0]), float(wtile2[1])) * 16.0 + Vector2(8, 8)
		add_child(wagon)
		_clear_around(clear, wagon.position + Vector2(20, -6), int(wagon_spec.get("clear_radius", 12)))
	for mine_spec: Dictionary in DataRegistry.table("ground").get("mines", []) as Array: ## the old mine's gate (docs/mine.md)
		var gate: MineEntrance = MineEntrance.new()
		var mtile: Array = mine_spec.tile as Array
		gate.name = "MineEntrance_" + String(mine_spec.id)
		gate.position = Vector2(float(mtile[0]), float(mtile[1])) * 16.0 + Vector2(8, 8)
		add_child(gate)
		(get_node("Mines") as MineManager).entrance = gate.exit_position
		_clear_around(clear, gate.position + Vector2(0, -20), int(mine_spec.get("clear_radius", 10)))
	_add_arenas(clear)
	if baked.has("manhole"):
		var at: Vector2 = Vector2(float((baked.manhole as Array)[0]), float((baked.manhole as Array)[1]))
		var cover: ManholeCover = ManholeCover.new()
		cover.position = at
		add_child(cover)
		_cover_at = at
		cover_node = cover
		_clear_around(clear, at, 4) ## room for the crawl
	var centre: Vector2 = Vector2(_start) * 16.0 + Vector2(8.0, 8.0)
	for guard: Dictionary in DataRegistry.table("ground").get("guards", []) as Array:
		var gat: Array = guard.at as Array
		_clear_around(clear, centre + Vector2(float(gat[0]), float(gat[1])), 3) ## no bush or tree beside a guard
	for path: Dictionary in DataRegistry.table("ground").get("paths", []) as Array:
		var points: Array = path.points as Array
		var reach: int = ceili((float(path.get("width", 24.0)) * 0.5 + 14.0) / 16.0)
		for i: int in range(points.size() - 1):
			var a: Vector2 = centre + Vector2(float((points[i] as Array)[0]), float((points[i] as Array)[1]))
			var b: Vector2 = centre + Vector2(float((points[i + 1] as Array)[0]), float((points[i + 1] as Array)[1]))
			for step: int in range(int(a.distance_to(b) / 8.0) + 1):
				_clear_around(clear, a.lerp(b, step * 8.0 / maxf(a.distance_to(b), 1.0)), reach)
	return clear


## Boss arenas (data/ground.json "arenas": a flagstone floor baked as a ground decal, plus pillars): every tile inside the drawn polygon
## (and `clear_margin` px around it) stays free of generated trees, bushes and plants, so the stage is empty but for what is placed by hand.
func _add_arenas(clear: Dictionary) -> void:
	for spec: Dictionary in DataRegistry.table("ground").get("arenas", []) as Array:
		var tile: Array = spec.tile as Array
		var origin: Vector2 = Vector2(float(tile[0]), float(tile[1])) * 16.0 + Vector2(8, 8)
		var poly: PackedVector2Array = PackedVector2Array()
		for point: Array in spec.poly as Array:
			poly.append(origin + Vector2(float(point[0]), float(point[1])))
		var zones: Array[PackedVector2Array] = [poly]
		for grown: PackedVector2Array in Geometry2D.offset_polygon(poly, float(spec.get("clear_margin", 16.0))):
			zones.append(grown)
		var lo: Vector2i = Vector2i(poly[0] / 16.0)
		var hi: Vector2i = lo
		for p: Vector2 in poly:
			lo = Vector2i(mini(lo.x, int(p.x / 16.0)), mini(lo.y, int(p.y / 16.0)))
			hi = Vector2i(maxi(hi.x, int(p.x / 16.0)), maxi(hi.y, int(p.y / 16.0)))
		for ty: int in range(lo.y - 3, hi.y + 4):
			for tx: int in range(lo.x - 3, hi.x + 4):
				var centre: Vector2 = Vector2(tx, ty) * 16.0 + Vector2(8, 8)
				for zone: PackedVector2Array in zones:
					if Geometry2D.is_point_in_polygon(centre, zone):
						clear[Vector2i(tx, ty)] = true
						break
		for pillar_spec: Dictionary in spec.get("pillars", []) as Array:
			var at: Array = pillar_spec.pos as Array
			var pillar: ArenaPillar = ArenaPillar.new()
			pillar.index = (spec.pillars as Array).find(pillar_spec)
			pillar.arena = String(spec.id)
			pillar.name = "Pillar_%s_%d" % [String(spec.id), pillar.index]
			pillar.variant = int(pillar_spec.get("variant", 0))
			pillar.position = origin + Vector2(float(at[0]), float(at[1]))
			add_child(pillar)
			_clear_around(clear, pillar.position, 2)
		for item: Dictionary in spec.get("decor", []) as Array: ## rubble, stumps, braziers, banners ... (tools/art_arena_decor.py): one HutYard each, so every piece sorts by its own feet
			var at_item: Array = item.pos as Array
			var yard: HutYard = HutYard.new()
			yard.name = "Decor_%s_%s" % [String(spec.id), String(item.get("id", "item"))]
			yard.position = origin + Vector2(float(at_item[0]), float(at_item[1]))
			var prop: Dictionary = item.duplicate()
			prop["pos"] = [0, 0]
			yard.setup([prop], "res://assets/props/arena/")
			add_child(yard)
		if spec.has("story"): ## the quest, the dead knight at the pillar and the hologram (ArenaStory)
			var story: ArenaStory = ArenaStory.new()
			story.name = "ArenaStory_%s" % String(spec.id)
			add_child(story)
			story.setup(self, spec, origin)


## The boss of an arena is not there on its own: the story calls it (`ArenaStory`: the knight at the pillar was inspected, or the hologram in the middle was
## touched). Any peer asks, the host summons it once (`_summon_arena_boss`); while a boss of that arena exists nothing happens. Not saved.
func request_arena_boss(arena_id: String, from: Vector2) -> void:
	if multiplayer.is_server():
		_host_summon_arena(arena_id, from)
	else:
		_rpc_request_arena_boss.rpc_id(1, arena_id, from)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_arena_boss(arena_id: String, from: Vector2) -> void:
	if multiplayer.is_server():
		_host_summon_arena(arena_id, from)


func arena_boss_present(arena_id: String) -> bool:
	for node: Node in get_tree().get_nodes_in_group("bosses"):
		if node is SkyCleaver and (node as SkyCleaver).arena == arena_id and not node.is_queued_for_deletion():
			return true
	return false


func _host_summon_arena(arena_id: String, from: Vector2) -> void:
	if arena_boss_present(arena_id):
		return
	for spec: Dictionary in DataRegistry.table("ground").get("arenas", []) as Array:
		if String(spec.id) == arena_id and not (spec.get("boss", {}) as Dictionary).is_empty():
			_summon_arena_boss(spec, from)
			return


func _arena_origin(spec: Dictionary) -> Vector2:
	var tile: Array = spec.tile as Array
	return Vector2(float(tile[0]), float(tile[1])) * 16.0 + Vector2(8, 8)


## The boss flies in from beyond the screen: it spawns `arrival.distance` px past its pillar (seen from the one who stepped in, and farther if need be
## so that no player has it on the screen) at `arrival.height`, and swoops onto the pillar (`SkyCleaver`: FLYING -> HOVER -> LANDING).
func _summon_arena_boss(spec: Dictionary, trigger_at: Vector2) -> void:
	var boss: Dictionary = spec.get("boss", {}) as Dictionary
	var start: int = int(boss.get("pillar", 0))
	var at: Array = ((spec.pillars as Array)[start] as Dictionary).pos as Array
	var perch: Vector2 = _arena_origin(spec) + Vector2(float(at[0]), float(at[1]))
	var arrival: Dictionary = DataRegistry.get_entry("enemies", String(boss.species)).get("arrival", {}) as Dictionary
	var away: Vector2 = (perch - trigger_at).normalized()
	if away == Vector2.ZERO:
		away = Vector2.UP
	var distance: float = float(arrival.get("distance", 460.0))
	var entry: Vector2 = perch + away * distance
	for attempt: int in 8: ## nobody may see it appear: the screen reaches about 370 px from its middle
		var seen: bool = false
		for player: Player in Player.all:
			if player.global_position.distance_to(entry) < 430.0:
				seen = true
				break
		if not seen:
			break
		distance += 60.0
		entry = perch + away * distance
	var node: SkyCleaver = SKY_CLEAVER_SCENE.instantiate() as SkyCleaver
	_enemy_count += 1
	node.name = "Boss%d" % _enemy_count
	node.enemy_id = String(boss.species)
	node.arena = String(spec.id)
	node.pillar_index = start
	node.arrive_height = float(arrival.get("height", 210.0))
	node.start_phase = int(_arena_phase.get(String(spec.id), 0)) ## a wipe in the judgement sends the next fight back to the beginning of phase 2, not of the fight
	node.position = entry
	_enemies.add_child(node)
	node.reset_requested.connect(_reset_arena_boss.bind(node, spec))
	node.defeated.connect(func() -> void: _arena_phase.erase(String(spec.id))) ## won: the next call (hologram) starts from phase 1 again
	node.checkpoint_reached.connect(func(p: int) -> void: _arena_phase[String(spec.id)] = maxi(p, int(_arena_phase.get(String(spec.id), 0))))


## Nobody is left in the fight (everyone fell or left): the boss and its feathers go, the pillars stand again; the hologram in the middle (`ArenaStory`) calls it anew.
func _reset_arena_boss(node: SkyCleaver, _spec: Dictionary) -> void:
	if is_instance_valid(node):
		node.queue_free()


## The opening (intro, spider gate, knight, crossroads, rescue) ends when she wakes up in the hut and the town begins: the story calls
## this then (nothing does yet). Until then the clock is locked, and a death brings her back wounded.
func finish_opening() -> void:
	opening_over = true
	TimeManager.unlock()


## Opens a story barrier (the invisible walls along the footpath): `id` as in data/ground.json "barrier".
func open_barrier(id: String) -> void:
	if _barriers.has(id):
		(_barriers[id] as Node).queue_free()
		_barriers.erase(id)


## A new game without the intro: the first quest starts at once.
func begin_story() -> void:
	var player: Player = _players.get_child(0) as Player if _players.get_child_count() > 0 else null
	if player != null and player.quests != null:
		player.quests.start("find_help")


## The story's intro (new game, singleplayer): she crawls out of the manhole. Called by main.gd.
func start_intro() -> void:
	var player: Player = _players.get_child(0) as Player if _players.get_child_count() > 0 else null
	if player == null or cover_node == null or not player.is_multiplayer_authority():
		return
	var scene: IntroScene = IntroScene.new()
	player.add_child(scene)
	scene.start(player, cover_node)


## The rescue is over: she wakes up in the hut's bed (WakeScene) and, once she stands, the opening is over. Solo / host only for now.
func start_wake(player: Player) -> void:
	if not player.is_multiplayer_authority() or player.get_node_or_null("WakeScene") != null:
		return
	var scene: WakeScene = WakeScene.new()
	scene.name = "WakeScene"
	player.add_child(scene)
	scene.start(player, self)


## She has reached the knight at the quarry: the meeting cutscene (KnightMeetScene). Solo / host only for now.
func start_knight_meet(player: Player) -> void:
	var quarry: Quarry = get_node_or_null("Quarry_quarry") as Quarry
	if quarry == null or not player.is_multiplayer_authority() or player.get_node_or_null("KnightMeetScene") != null:
		return
	var scene: KnightMeetScene = KnightMeetScene.new()
	scene.name = "KnightMeetScene"
	player.add_child(scene)
	scene.start(player, quarry)


## Developer: puts her on the floor of the Schieferkessel; with `fight` Morwenna falls out of the crown at once (no spiders first).
func debug_morwenna(player: Player, fight: bool) -> void:
	if player == null or witch_arena == null or not player.is_multiplayer_authority():
		return
	player.request_teleport(witch_arena.tree_position() + Vector2(0, 150))
	if fight:
		witch_arena.debug_fight()


func has_arena_story() -> bool:
	for child: Node in get_children():
		if child is ArenaStory:
			return true
	return false


## Developer: starts the boss quest `mornath` again from its first step (the knight lies at the pillar, the hologram is gone), or with `jump` only puts her on the arena
## floor in front of the east pillar. The quest is not part of the story yet: this is the only way to start it.
func debug_mornath(player: Player, jump: bool) -> void:
	if player == null or player.quests == null or not player.is_multiplayer_authority():
		return
	for child: Node in get_children():
		if child is ArenaStory:
			var story: ArenaStory = child as ArenaStory
			if jump:
				player.request_teleport(story.foot_point())
			else:
				player.quests.restart(story.quest_id)
			return


## She inspects the dead knight at the arena's pillar: the walk up, the search, the dialogue and the boss's entrance (MornathInspectScene). Local player only.
func start_mornath_inspect(player: Player, story: ArenaStory) -> void:
	if not player.is_multiplayer_authority() or player.get_node_or_null("MornathInspectScene") != null:
		return
	var scene: MornathInspectScene = MornathInspectScene.new()
	scene.name = "MornathInspectScene"
	player.add_child(scene)
	scene.start(player, story)


## The meeting is over: the knight walks back to the hut and she follows (KnightWalkScene). A save that stopped there starts it again.
func start_knight_walk(player: Player) -> void:
	var quarry: Quarry = get_node_or_null("Quarry_quarry") as Quarry
	var hut: Hut = _hut() ## the knight's hut, not the lumberjack's cabin
	if quarry == null or hut == null or not player.is_multiplayer_authority() or player.get_node_or_null("KnightWalkScene") != null or quarry.knight_left:
		return
	var scene: KnightWalkScene = KnightWalkScene.new()
	scene.name = "KnightWalkScene"
	player.add_child(scene)
	scene.start(player, quarry, hut)


func _hut(interior: String = "hut") -> Hut:
	for child: Node in get_children():
		if child is Hut and (child as Hut).interior_id == interior:
			return child as Hut
	return null


## She sat down at one of the two places at the fire (`seat` "east" = the stump, "south" = the log): the fire scene (KnightFireScene), the evening and the talk.
func start_fire_scene(player: Player, seat: String) -> void:
	var quarry: Quarry = get_node_or_null("Quarry_quarry") as Quarry
	var hut: Hut = _hut()
	if quarry == null or hut == null or not player.is_multiplayer_authority() or player.get_node_or_null("KnightFireScene") != null:
		return
	var scene: KnightFireScene = KnightFireScene.new()
	scene.name = "KnightFireScene"
	player.add_child(scene)
	scene.start(player, quarry, hut, seat)


## She has stepped into the lumberjack's cabin: one shadow spider rises in the room and she has to beat it (CabinSpiderScene). `talked`: the dialogue was already played.
func start_cabin_spider(player: Player, talked: bool = false) -> void:
	var cabin: Hut = _hut("cabin")
	if cabin == null or not player.is_multiplayer_authority() or player.get_node_or_null("CabinSpiderScene") != null:
		return
	var scene: CabinSpiderScene = CabinSpiderScene.new()
	scene.name = "CabinSpiderScene"
	player.add_child(scene)
	scene.start(player, self, cabin, talked)


func _wagon() -> GustavWagon:
	return get_node_or_null("Wagon_gustav") as GustavWagon


## Quest `gustav_rescue`: the spider at the wagon (mode "fight") and the first talk with the stranger (mode "meet"), see GustavRescueScene.
func start_gustav_rescue(player: Player, mode: String) -> void:
	var wagon: GustavWagon = _wagon()
	if wagon == null or not player.is_multiplayer_authority() or player.get_node_or_null("GustavRescueScene") != null:
		return
	var scene: GustavRescueScene = GustavRescueScene.new()
	scene.name = "GustavRescueScene"
	player.add_child(scene)
	scene.start(player, self, wagon, mode)


## Gustav is packed: the escort home through the dusk (GustavEscortScene).
func start_gustav_escort(player: Player) -> void:
	var wagon: GustavWagon = _wagon()
	if wagon == null or _town_node == null or not player.is_multiplayer_authority() or player.get_node_or_null("GustavEscortScene") != null:
		return
	var scene: GustavEscortScene = GustavEscortScene.new()
	scene.name = "GustavEscortScene"
	player.add_child(scene)
	scene.start(player, self, wagon, _town_node)


## Gustav stands in the light: he walks to Valdric, the welcome dialogue, he moves in (GustavWelcomeScene).
func start_gustav_welcome(player: Player) -> void:
	if _town_node == null or not player.is_multiplayer_authority() or player.get_node_or_null("GustavWelcomeScene") != null:
		return
	var scene: GustavWelcomeScene = GustavWelcomeScene.new()
	scene.name = "GustavWelcomeScene"
	player.add_child(scene)
	scene.start(player, self, _town_node)


## She goes to bed (the bed's E): black, the night, the second morning (WakeScene as a second wake-up).
func start_sleep(player: Player, rest: bool = false) -> void:
	if not player.is_multiplayer_authority() or player.get_node_or_null("SleepScene") != null:
		return
	var scene: SleepScene = SleepScene.new()
	scene.name = "SleepScene"
	player.add_child(scene)
	scene.start(player, self, rest)


## Valdric joins the town's daily life (data/settlers.json `takes_over`): the story's actor is put away for good and a settler is him from now on. Returns where the actor stood
## (the settler walks on from there), INF when he was not on the map.
func take_knight() -> Vector2:
	knight_taken = true
	var quarry: Quarry = get_node_or_null("Quarry_quarry") as Quarry
	if quarry == null or quarry.knight == null:
		return Vector2.INF
	var at: Vector2 = quarry.knight.global_position if quarry.knight.visible else Vector2.INF
	quarry.knight.visible = false
	quarry.set_knight_solid(false)
	return at


## Puts the knight where the story wants him: "fire" = sitting on the log by the fire, "door" = resting in front of the hut's door (the second morning on).
func place_knight(where: String) -> void:
	if knight_taken:
		return ## he lives in the town now (a settler, see `take_knight`)
	var quarry: Quarry = get_node_or_null("Quarry_quarry") as Quarry
	var hut: Hut = _hut()
	if quarry == null or hut == null:
		return
	if not quarry.knight_left:
		quarry.hand_over_knight(self)
	quarry.show_pick(true)
	var knight: Adventurer = quarry.knight
	if where == "fire":
		knight.global_position = hut.global_position + KnightFireScene.LOG + Vector2(4, 3)
		knight.play("sit", Vector2(1, -1))
	else:
		knight.global_position = hut.exit_position + Vector2(-26, 12)
		knight.play("stand", Vector2(0.4, 1.0))
	quarry.set_knight_solid(true)


## The hut is mended: the new boards on the roof and over the hole in the floor.
func _apply_renewed(on: bool) -> void:
	var hut: Hut = _hut()
	if hut != null:
		hut.set_renewed(on)
	var room: Interior = (get_node("Interiors") as Interiors).interior("hut")
	if room != null:
		room.set_renewed(on)


func apply_renewed() -> void:
	_apply_renewed(true)


## A story conversation started by a quest step (event `story:<id>`): the full dialogue `id` of data/dialogue.json; when it is closed its `take` {item, count} is taken out of her bag
## and its `flag` is set (this is what ends the step).
func play_story_dialogue(player: Player, id: String) -> void:
	if not player.is_multiplayer_authority():
		return
	var entry: Dictionary = DataRegistry.get_entry("dialogue", id)
	for child: Node in player.get_children():
		var box: DialogueBox = child.get_node_or_null("DialogueBox") as DialogueBox
		if box != null:
			box.start(id)
			await box.finished
			break
	var take: Dictionary = entry.get("take", {}) as Dictionary
	if not take.is_empty():
		player.inventory.remove_item(String(take.item), int(take.count))
	for gift: Variant in entry.get("give", []) as Array: ## what the speaker hands over ({item, count}); a full bag keeps nothing of it
		player.inventory.give(String((gift as Dictionary).item), int((gift as Dictionary).count))
	if String(entry.get("town_talk", "")) != "" and _town_node != null:
		_town_node.request_talk(String(entry.town_talk)) ## the first talk with a settler counts as the day's talk
	if player.quests != null and String(entry.get("flag", "")) != "":
		player.quests.set_flag(String(entry.flag))


## The developer checkpoint is offered only in a free, living solo session.
func debug_can_return_home() -> bool:
	if not multiplayer.is_server() or not multiplayer.get_peers().is_empty() or _players.get_child_count() == 0:
		return false
	var player: Player = _players.get_child(0) as Player
	return player != null and player.is_multiplayer_authority() and player.intro == null and not player.story_lock and not player.fainting and player.health.current > 0.0


## Developer checkpoint: back home after the lumberjack's cabin, with the story gear.
## No automatic save write; use the normal menu to keep this checkpoint if desired.
func debug_return_home() -> void:
	if not debug_can_return_home(): return
	var player: Player = _players.get_child(0) as Player
	var hut: Hut = _hut()
	if hut == null: return
	var saved: Dictionary = player.quests.export_data()
	var flags: Dictionary = saved.flags as Dictionary
	for quest_id: String in ["find_help", "lumberjack"]:
		(saved.active as Dictionary).erase(quest_id)
		(saved.active_steps as Dictionary).erase(quest_id)
		if not (saved.done as Array).has(quest_id):
			(saved.done as Array).append(quest_id)
		for step: Dictionary in DataRegistry.get_entry("quests", quest_id).steps as Array:
			if step.has("flag"): flags[String(step.flag)] = true
	for flag: String in ["rescued", "knight_dialogue_done", "hud_unlocked", "map_opened", "knows_adventurer", "day2_started", "cabin_board_moved", "left_cabin"]:
		flags[flag] = true
	player.quests.import_data(saved)
	if not player.inventory.has_item("sword_basic"):
		if (player.inventory.equipment.get("main_hand", {}) as Dictionary).is_empty():
			player.inventory.equipment["main_hand"] = {"id": "sword_basic", "count": 1}
			player.inventory._commit()
		else:
			player.inventory.give("sword_basic", 1)
	if not player.inventory.has_item("axe_basic"):
		player.inventory.give("axe_basic", 1)
	player.health.floor_value = 0.0
	player.health.heal_full()
	player.stamina.refill()
	player.set_bandaged(false)
	player.sync_wound_visuals()
	player.auto_walk = Vector2.INF
	player.request_teleport(hut.exit_position + Vector2(24, 24))
	player.facing = Vector2.DOWN
	player._camera.zoom = Vector2.ONE
	var interiors: Interiors = get_node("Interiors") as Interiors
	interiors.interior("hut").set_bed_frame(1)
	interiors.apply_view(player)
	TimeManager.set_time(10.0 / 24.0)
	finish_opening()
	resume_story(player) ## knight at home, cabin board moved aside


## Developer checkpoint: the finished town. Everything before it counts as done (the hut renewed, the first lessons), every piece of the catalogue stands finished, the craftsman is at his
## bench and the town quest stands at "a stranger comes to the light". Solo only, no auto-save. `all_done`: the whole quest chain is finished and Torben lives in the smithy too.
func debug_jump_town(all_done: bool = false) -> void:
	if not debug_can_return_home() or _town_node == null:
		return
	debug_return_home()
	var player: Player = _players.get_child(0) as Player
	var saved: Dictionary = player.quests.export_data()
	var flags: Dictionary = saved.flags as Dictionary
	for quest_id: String in ["rebuild_hut", "town_start", "gustav_rescue", "town_workshop"]:
		var until: String = "ws_pickaxe" if quest_id == "town_workshop" and not all_done else ""
		_quest_to_step(saved, quest_id, until)
	for flag: String in ["rebuild_done", "lumberjack_reported", "rebuild_delivered", "rebuild_wood_delivered", "hut_mushrooms_removed", "hut_tree_felled", "knows_gustav", "gustav_packed", "gustav_joined", "built_workshop", "workshop_done"]:
		flags[flag] = true
	player.quests.import_data(saved)
	if not player.inventory.has_item("sickle_basic"):
		player.inventory.give("sickle_basic", 1) ## Gustav's gift; the pickaxe is made at his bench
	if all_done and not player.inventory.has_item("pickaxe_basic"):
		player.inventory.give("pickaxe_basic", 1)
	resume_story(player) ## the hut mended, the knight at the door
	_town_node.debug_build_all(all_done) ## she stands at the hut's door: the workshop and its craftsman are a short walk away


## Marks `quest_id` in an exported quest state (QuestComponent.export_data) as done, or as running at step `until` with every earlier step's flags set.
func _quest_to_step(saved: Dictionary, quest_id: String, until: String) -> void:
	var flags: Dictionary = saved.flags as Dictionary
	(saved.active as Dictionary).erase(quest_id)
	(saved.active_steps as Dictionary).erase(quest_id)
	var steps: Array = DataRegistry.get_entry("quests", quest_id).steps as Array
	for i: int in steps.size():
		var step: Dictionary = steps[i] as Dictionary
		if until != "" and String(step.get("id", "")) == until:
			(saved.active as Dictionary)[quest_id] = i
			(saved.active_steps as Dictionary)[quest_id] = until
			return
		if step.has("flag"):
			flags[String(step.flag)] = true
		for task: Variant in step.get("tasks", []) as Array:
			if (task as Dictionary).has("flag"):
				flags[String((task as Dictionary).flag)] = true
	if not (saved.done as Array).has(quest_id):
		(saved.done as Array).append(quest_id)


## Developer checkpoint "GUSTAV GERETTET": the escort is over, Gustav lives in the town; the quest waits at the workshop's material list (sickle in the bag, nothing built yet).
func debug_jump_gustav() -> void:
	if not debug_can_return_home() or _town_node == null:
		return
	debug_return_home()
	var player: Player = _players.get_child(0) as Player
	var saved: Dictionary = player.quests.export_data()
	var flags: Dictionary = saved.flags as Dictionary
	for quest_id: String in ["rebuild_hut", "town_start", "gustav_rescue", "town_workshop"]:
		_quest_to_step(saved, quest_id, "ws_gather" if quest_id == "town_workshop" else "")
	for flag: String in ["rebuild_done", "lumberjack_reported", "rebuild_delivered", "rebuild_wood_delivered", "hut_mushrooms_removed", "hut_tree_felled", "built_lamp_post", "knows_gustav", "gustav_packed", "gustav_joined"]:
		flags[flag] = true
	player.quests.import_data(saved)
	if not player.inventory.has_item("sickle_basic"):
		player.inventory.give("sickle_basic", 1)
	resume_story(player)
	_town_node.request_found()
	_town_node.add_story_resident("gustav", false) ## he is simply at the camp by the fire


## A loaded save that stopped in the middle of the wake-up starts it again.
func resume_story(player: Player) -> void:
	if player.quests != null and player.quests.active_step_id("find_help") == "wake":
		start_wake(player)
	elif player.quests != null and player.quests.active_step_id("find_help") == "meet":
		start_knight_meet(player) ## a save that stopped in the middle of the meeting plays it again
	elif player.quests != null and player.quests.active_step_id("find_help") == "follow_knight":
		start_knight_walk(player)
	elif player.quests != null and player.quests.active_step_id("find_help") in ["sit_fire", "sleep"]:
		place_knight("fire") ## a save from the evening: he sits by the fire
	elif player.quests != null and player.quests.has_flag("day2_started"):
		place_knight("door")
	if player.quests != null and player.quests.active_step_id("lumberjack") == "kill_spider":
		start_cabin_spider(player, true) ## a save from in the fight: a spider rises again when she is inside
	if player.quests != null:
		var gustav_step: String = player.quests.active_step_id("gustav_rescue")
		var wagon: GustavWagon = _wagon()
		if wagon != null and player.quests.has_flag("wagon_opened"):
			wagon.set_open(true, false) ## the door stays open once she has freed him
		if gustav_step == "kill_wagon_spider":
			start_gustav_rescue(player, "fight") ## a save from in the fight: the spider is there again
		elif gustav_step == "gustav_meet":
			start_gustav_rescue(player, "meet")
		elif gustav_step == "escort":
			start_gustav_escort(player)
		elif gustav_step == "welcome":
			start_gustav_welcome(player)
	if player.quests != null and player.quests.active_step_id("lumberjack") == "report_back" and not player.inventory.has_item("axe_basic"):
		player.inventory.give("axe_basic", 1) ## a save from between dropping and picking up the axe: never soft-locked without it
	var hut_room: Interior = (get_node("Interiors") as Interiors).interior("hut")
	if hut_room != null and player.quests != null: ## a save from while the hut was being renewed: what is gone stays gone
		for node: Interactable in hut_room.pickups:
			var spot: InteriorPickup = node as InteriorPickup
			if player.quests.has_flag(String(spot.spec.flag)):
				spot.apply_gone()
		if hut_room.tree != null and player.quests.has_flag("hut_tree_felled"):
			(hut_room.tree as HutTree).set_felled(true)
	if player.quests != null and player.quests.active_step_id("rebuild_hut") == "rebuild_finale":
		start_hut_finale(player) ## a save from just before the building: it starts again
	if player.quests != null and player.quests.has_flag("rebuild_done"):
		_apply_renewed(true) ## the hut stays mended
		if player.quests.is_finished("rebuild_hut"):
			player.quests.start("town_start") ## a save from before the town quest existed: it begins now (start() keeps existing progress)
	var cabin: Hut = _hut("cabin")
	if cabin != null and cabin.board != null and player.quests != null and player.quests.has_flag("cabin_board_moved"):
		cabin.board.set_moved(true) ## a save from after the board was carried aside
	# Checkpoints and older saves can mark the cabin quest done without its normal
	# completion event. Restore its follow-up; start() preserves existing progress.
	if player.quests != null and player.quests.is_finished("lumberjack"):
		var next: String = String(DataRegistry.get_entry("quests", "lumberjack").get("next", ""))
		if next != "":
			player.quests.start(next)
	if player.quests != null: ## the town quests lead into each other; a migrated old save may stand between two (start() keeps existing progress)
		for chained: String in ["town_start", "gustav_rescue"]:
			if player.quests.is_finished(chained):
				var follow: String = String(DataRegistry.get_entry("quests", chained).get("next", ""))
				if follow != "":
					player.quests.start(follow)


## Hand-placed props around the start (data/ground.json "props": kind, variant, tile offset from the start tile).
func _extra_props() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for spec: Dictionary in DataRegistry.table("ground").get("props", []) as Array:
		var tile: Array = spec.tile as Array
		out.append({"cell": _start + Vector2i(int(tile[0]), int(tile[1])), "kind": String(spec.kind), "variant": int(spec.variant)})
	return out


func _clear_around(cells: Dictionary, at: Vector2, radius: int) -> void:
	var tile: Vector2i = Vector2i(at / 16.0)
	for y: int in range(-radius, radius + 1):
		for x: int in range(-radius, radius + 1):
			if x * x + y * y <= radius * radius:
				cells[tile + Vector2i(x, y)] = true


## Players start beside the manhole cover, where she crawls out (see IntroSequence); without a baked cover at the map's start tile.
## The story's guard spiders beside the footpath (data/ground.json "guards", px relative to the start tile): they stand still, sway a little and
## kill whoever they notice; only sneaking gets her past.
func _spawn_guards() -> void:
	if not multiplayer.is_server():
		return
	var centre: Vector2 = Vector2(_start) * 16.0 + Vector2(8.0, 8.0)
	for guard: Dictionary in DataRegistry.table("ground").get("guards", []) as Array:
		var at: Array = guard.at as Array
		var face: Array = guard.face as Array
		var spider: ShadowSpider = SPIDER_SCENE.instantiate() as ShadowSpider
		_enemy_count += 1
		spider.name = "Guard%d" % _enemy_count
		spider.enemy_id = String(guard.enemy)
		spider.position = centre + Vector2(float(at[0]), float(at[1]))
		spider.heading = Vector2(float(face[0]), float(face[1])).angle()
		_enemies.add_child(spider)


## A story spider (`enemy_id` from data/enemies.json) for a cutscene; host only.
func spawn_story_spider(enemy_id: String, at: Vector2, heading: float) -> ShadowSpider:
	if not multiplayer.is_server():
		return null
	var spider: ShadowSpider = SPIDER_SCENE.instantiate() as ShadowSpider
	_enemy_count += 1
	spider.name = "Story%d" % _enemy_count
	spider.enemy_id = enemy_id
	spider.emerge_on_spawn = true
	spider.position = at
	spider.heading = heading
	_enemies.add_child(spider)
	return spider


## The crossroad ambush (story step "ambush"): three shadow spiders, a fight she cannot win. Solo / host only for now.
func start_ambush(player: Player) -> void:
	if not multiplayer.is_server() or not player.is_multiplayer_authority() or player.get_node_or_null("AmbushScene") != null:
		return
	var scene: AmbushScene = AmbushScene.new()
	scene.name = "AmbushScene"
	player.add_child(scene)
	scene.start(player, self)


## Scene initialization uses the same starting health on host and all peers.
func starting_health_ratio() -> float:
	return float(DataRegistry.get_entry("ground", "story_start").get("health_ratio", 0.1))


func _spawn_position(index: int) -> Vector2:
	if _cover_at != Vector2.ZERO:
		return _cover_at + Vector2(INTRO_SPAWN.x + 16.0 * (index % 2), INTRO_SPAWN.y + 16.0 * (index / 2))
	return Vector2(_start) * 16.0 + Vector2(8.0 + 16.0 * index, 8.0)


func _clamp_spawn(pos: Vector2) -> Vector2:
	return pos


var _wood_clock: float = 0.0
var _wood_busy: bool = false
var _stream_settled: bool = false ## the last `_stream(false)` left nothing to load or drop (see `_stream`)
var _stream_centers: Array[Vector2i] = [] ## the chunk centres of that pass
var _stream_motion: Dictionary = {} ## player instance id -> [last position, smoothed velocity] for the look-ahead ring
var _unload_queue: Array[Vector2i] = [] ## chunks waiting to be unloaded gradually (MAX_UNLOADS_PER_FRAME)


func _process(delta: float) -> void:
	super(delta)
	_stream(false)
	_wood_clock -= delta
	if _wood_clock <= 0.0:
		_wood_clock = 0.4
		_watch_wood_handover()


## Quest "renew the hut": with 20 pieces of wood in the bag, standing near Valdric, the wood is handed over (a short dialogue takes it and ends that task).
func _watch_wood_handover() -> void:
	if _wood_busy or _players.get_child_count() == 0:
		return
	var player: Player = _players.get_child(0) as Player
	var quarry: Quarry = get_node_or_null("Quarry_quarry") as Quarry
	if player == null or quarry == null or not player.is_multiplayer_authority() or player.quests == null or player.story_lock or InputManager.ui_blocking:
		return
	if player.quests.active_step_id("rebuild_hut") != "rebuild_tasks" or player.quests.has_flag("rebuild_wood_delivered") or player.inventory.count_item("wood") < 20:
		return
	if player.global_position.distance_to(quarry.knight.global_position) < 90.0:
		_wood_busy = true
		await play_story_dialogue(player, "rebuild_wood")
		_wood_busy = false


## All three jobs of the renewal are done (quest step `rebuild_finale`): Valdric says it is time, they begin to build (HutFinaleScene). Inside the hut he comes in to her first.
func start_hut_finale(player: Player) -> void:
	var quarry: Quarry = get_node_or_null("Quarry_quarry") as Quarry
	var hut: Hut = _hut()
	if quarry == null or hut == null or not player.is_multiplayer_authority() or player.get_node_or_null("HutFinaleScene") != null:
		return
	var scene: HutFinaleScene = HutFinaleScene.new()
	scene.name = "HutFinaleScene"
	player.add_child(scene)
	scene.start(player, self, quarry, hut)


func _noise(noise_seed: int, frequency: float, octaves: int) -> FastNoiseLite:
	var n: FastNoiseLite = FastNoiseLite.new()
	n.seed = noise_seed
	n.frequency = frequency
	n.fractal_octaves = octaves
	return n


func _make_layer(biome: String, tint: Color) -> TileMapLayer:
	var layer: TileMapLayer = TileMapLayer.new()
	layer.name = biome
	layer.tile_set = _ground.tile_set
	layer.material = _ground.material
	layer.z_index = _ground.z_index
	layer.modulate = Color.WHITE.lerp(tint, 0.6)
	add_child(layer)
	Terrain.register_layer(layer)
	return layer


## Keeps the chunks around the players painted: `all` loads the whole ring now (start), otherwise
## nearest first. Runtime preparation is budgeted; activation is atomic.
func _stream(all: bool) -> void:
	var frame_deadline: int = Time.get_ticks_usec() + STREAM_BUDGET_USEC ## one budget for adding last frame's props and preparing the next chunk
	_finish_commit(frame_deadline) ## the ground committed last frame gets its props now (over several frames when it has many)
	var centers: Array[Vector2i] = []
	var ahead: Array[Vector2i] = [] ## look-ahead centres: loaded after the players' own rings, never built at once
	var is_teleport: bool = false
	if all:
		centers.append(_start / CHUNK)
		centers.append(Vector2i(_spawn_position(0) / (16.0 * CHUNK)))
	else:
		var delta: float = maxf(get_process_delta_time(), 0.001)
		for player: Node in _players.get_children():
			var at: Vector2 = Interiors.outer(get_tree(), (player as Node2D).position)
			var own: Vector2i = Vector2i(at / (16.0 * CHUNK))
			centers.append(own)
			var motion: Array = _stream_motion.get(player.get_instance_id(), [at, Vector2.ZERO])
			var step: Vector2 = (at - (motion[0] as Vector2)) / delta
			if step.length() > LOOKAHEAD_MAX_SPEED:
				is_teleport = true
			var velocity: Vector2 = Vector2.ZERO if step.length() > LOOKAHEAD_MAX_SPEED else (motion[1] as Vector2).lerp(step, minf(1.0, delta * 4.0))
			_stream_motion[player.get_instance_id()] = [at, velocity]
			var forward: Vector2i = Vector2i((at + velocity * LOOKAHEAD_SECONDS) / (16.0 * CHUNK))
			if forward != own and not ahead.has(forward):
				ahead.append(forward)
	if is_instance_valid(editor_camera):
		centers.append(Vector2i(editor_camera.position / (16.0 * CHUNK)))
	# Nothing changed since a pass that left nothing to load or drop: only a moved player, a pending build or the editor needs the loops.
	var probe: Array[Vector2i] = centers + ahead
	if not all and _stream_settled and not is_instance_valid(editor_camera) and probe == _stream_centers:
		return
	_stream_settled = false
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: int = 1 << 30
	var wanted: Dictionary = {} ## the chunks round the players (loaded ones too); used to keep or drop paused builds
	var missing: Array[Vector3i] = [] ## (squared distance, x, y) of every wanted chunk that is not loaded, for the worker prefetch
	var own_count: int = centers.size()
	if not all:
		centers.append_array(ahead)
	for center_index: int in centers.size():
		var center: Vector2i = centers[center_index]
		var penalty: int = 0 if center_index < own_count else 3 ## the look-ahead ring waits for the rings the players stand in
		var radius: int = LOAD_RADIUS
		if is_instance_valid(editor_camera) and center == Vector2i(editor_camera.position / (16.0 * CHUNK)):
			radius = clampi(ceili(get_viewport_rect().size.x / editor_camera.zoom.x / (16.0 * CHUNK) * 0.5 + 0.5), 1, 4)
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				var c: Vector2i = center + Vector2i(dx, dy)
				wanted[c] = true ## (loaded ones too: the prune only looks at unloaded builds)
				if _chunks.has(c) or c.x < 0 or c.y < 0 or c.x * CHUNK >= RegionMap.WORLD_TILES or c.y * CHUNK >= RegionMap.WORLD_TILES:
					continue
				missing.append(Vector3i(dx * dx + dy * dy + penalty, c.x, c.y))
				if not all and dx * dx + dy * dy + penalty < best_d:
					best_d = dx * dx + dy * dy + penalty
					best = c
	if all:
		if Jobs.threaded: ## the whole ring at once: all chunk jobs run in parallel, the loop below only collects them
			for entry: Vector3i in missing:
				_prefetch(Vector2i(entry.y, entry.z))
		for entry: Vector3i in missing:
			_load_chunk(Vector2i(entry.y, entry.z))
	if not all:
		# Builds nobody wants any more are dropped; a build the nearest target has overtaken waits in `_paused_builds` with its progress.
		for paused: Vector2i in _paused_builds.keys():
			if not wanted.has(paused):
				_free_build(_paused_builds[paused] as ChunkBuild)
				_paused_builds.erase(paused)
		if _building != null and not wanted.has(_building.cell):
			_free_build(_building)
			_building = null
		if best.x >= 0 and (_building == null or _building.cell != best):
			if _building != null: _paused_builds[_building.cell] = _building
			_building = _take_build(best)
		if Jobs.threaded and not missing.is_empty(): ## the next few chunks are prepared by the workers while the nearest one is finished here
			missing.sort()
			for i: int in mini(PREFETCH, missing.size()):
				_prefetch(Vector2i(missing[i].y, missing[i].z))
		if _building != null and _pending_commit == null:
			var has_ground_near: bool = false
			for center: Vector2i in centers:
				for dy: int in range(-1, 2):
					for dx: int in range(-1, 2):
						if _chunks.has(center + Vector2i(dx, dy)):
							has_ground_near = true
							break
					if has_ground_near: break
				if has_ground_near: break
			var is_teleport_dest: bool = (best_d == 0 and not has_ground_near)
			var time_now: int = Time.get_ticks_usec()
			if not all and time_now >= frame_deadline and not is_teleport_dest:
				pass
			else:
				var deadline: int = 0 if is_teleport_dest else ((frame_deadline - STREAM_BUDGET_USEC + STREAM_OWN_CHUNK_USEC) if best_d == 0 else (frame_deadline - STREAM_BUDGET_USEC + STREAM_URGENT_USEC if best_d <= 2 else frame_deadline))
				if _advance_chunk(_building, deadline):
					var finished: ChunkBuild = _building
					_building = null
					_commit_chunk(finished)
					if is_teleport_dest:
						_finish_commit()
	if all or centers.is_empty():
		return
	for c: Vector2i in _chunks.keys():
		var near: bool = false
		for center: Vector2i in centers:
			var radius: int = UNLOAD_RADIUS
			if is_instance_valid(editor_camera) and center == Vector2i(editor_camera.position / (16.0 * CHUNK)):
				radius = clampi(ceili(get_viewport_rect().size.x / editor_camera.zoom.x / (16.0 * CHUNK) * 0.5 + 0.5), 1, 4) + 1
			if maxi(absi(c.x - center.x), absi(c.y - center.y)) <= radius:
				near = true
				break
		if not near:
			if not _unload_queue.has(c):
				_unload_queue.append(c)
		else:
			_unload_queue.erase(c)
	var unloads: int = 0
	while not _unload_queue.is_empty() and unloads < MAX_UNLOADS_PER_FRAME:
		var c_to_unload: Vector2i = _unload_queue.pop_front()
		if _chunks.has(c_to_unload):
			_unload_chunk(c_to_unload)
			unloads += 1
	_stream_centers = probe
	if _stream_motion.size() > _players.get_child_count() + 4:
		_stream_motion.clear()
	_stream_settled = best.x < 0 and _building == null and _paused_builds.is_empty() and _pending_commit == null and _unload_queue.is_empty()


func _land_at(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= RegionMap.WORLD_TILES or y >= RegionMap.WORLD_TILES:
		return false
	return _sdf[y * RegionMap.WORLD_TILES + x] >= 128


## The biome of a land tile. The lookup is bent by a little noise so borders are ragged at tile
## size; where the bent lookup falls in the sea the nearest land decides.
func _land_biome(cell: Vector2i) -> String:
	if not _map.world_biome.is_empty() and _map.own_biomes.is_empty():
		return _map.world_biome
	var authored: Dictionary = {} if edits.terrain.is_empty() else edits.terrain.get(WorldEdits.key(cell), {})
	if authored.has("biome"):
		return String(authored.biome)
	var bend: Vector2i = Vector2i(roundi(_warp_x.get_noise_2d(cell.x, cell.y) * BORDER_WARP), roundi(_warp_y.get_noise_2d(cell.x, cell.y) * BORDER_WARP))
	var biome: String = _map.biome_at(cell + bend)
	for radius: int in [4, 8, 12]:
		if biome != "":
			break
		for dir: Vector2i in DIRECTIONS:
			biome = _map.biome_at(cell + dir * radius)
			if biome != "":
				break
	return biome if biome != "" else "meadow"


## Biome at one tile ("" = void).
func _biome_at(cell: Vector2i) -> String:
	return _land_biome(cell) if _land_at(cell.x, cell.y) else ""


func _load_chunk(c: Vector2i) -> void:
	_finish_commit()
	if _chunks.has(c): return
	var build: ChunkBuild
	if _building != null and _building.cell == c:
		build = _building
		_building = null
	else:
		build = _take_build(c)
	_advance_chunk(build)
	_commit_chunk(build)
	_finish_commit()


## A paused build of `c` continues where it stopped; otherwise a new one starts.
func _take_build(c: Vector2i) -> ChunkBuild:
	if _paused_builds.has(c):
		var resumed: ChunkBuild = _paused_builds[c] as ChunkBuild
		_paused_builds.erase(c)
		return resumed
	return _begin_chunk(c)


## Starts the worker job of chunk `c` (if it has no build yet): the build waits in `_paused_builds` with its job running.
func _prefetch(c: Vector2i) -> void:
	if _chunks.has(c) or _paused_builds.has(c) or (_building != null and _building.cell == c) or (_pending_commit != null and _pending_commit.cell == c):
		return
	var build: ChunkBuild = _begin_chunk(c)
	_start_gen(build)
	_paused_builds[c] = build


func _begin_chunk(c: Vector2i) -> ChunkBuild:
	var build: ChunkBuild = ChunkBuild.new()
	build.cell = c
	build.chunk = Chunk.new()
	build.chunk.node = Node2D.new()
	build.chunk.node.name = "Chunk%d_%d" % [c.x, c.y]
	build.body = StaticBody2D.new()
	build.chunk.node.add_child(build.body)
	build.rng.seed = hash(Vector3i(c.x, c.y, _map.world_seed))
	build.custom_keys = edits.props.keys()
	build.chunk.water_near = _rivers.near_water(c)
	build.density = DataRegistry.get_entry("wind", "detail_density")
	return build


## Phases 0-4 (generator query, ground, cliffs, prop nodes) are one worker job; the main thread continues from phase 5.
## `deadline` 0 waits for the job (or runs it right here when no worker has started it); without threads the old slicing is used.
func _advance_chunk(build: ChunkBuild, deadline: int = 0) -> bool:
	if build.phase < GEN_PHASES:
		if build.job != null or Jobs.threaded:
			_start_gen(build)
			if deadline == 0:
				Jobs.wait(build.job)
			if not build.gen_ready:
				return false
		elif not _advance_to(build, deadline, GEN_PHASES):
			return false
	if not build.filtered:
		_filter_prepared(build)
	return _advance_to(build, deadline, 10)


func _start_gen(build: ChunkBuild) -> void:
	if build.job != null or build.phase >= GEN_PHASES:
		return
	build.job = Jobs.run(_gen_work.bind(build), _gen_done.bind(build), Jobs.Prio.NORMAL, _gen_discard.bind(build), build.cell)


## (worker thread) Reads only what no one changes while chunks load and builds detached nodes.
func _gen_work(build: ChunkBuild) -> Variant:
	var generator: PropGenerator = _acquire_generator()
	build.query = generator.begin_chunk(Rect2i(build.cell * CHUNK, Vector2i(CHUNK, CHUNK)))
	_advance_to(build, 0, GEN_PHASES)
	_release_generator(generator)
	return build


func _gen_done(_result: Variant, build: ChunkBuild) -> void:
	build.gen_ready = true


## (main thread) The chunk was dropped while its job was running or waiting for delivery.
func _gen_discard(_result: Variant, build: ChunkBuild) -> void:
	_free_build_nodes(build)


func _acquire_generator() -> PropGenerator:
	_gen_lock.lock()
	var generator: PropGenerator = _gen_pool.pop_back() if not _gen_pool.is_empty() else null
	_gen_lock.unlock()
	if generator == null:
		return _generator.fork()
	generator.sync_inputs(_generator)
	return generator


func _release_generator(generator: PropGenerator) -> void:
	_gen_lock.lock()
	_gen_pool.append(generator)
	_gen_lock.unlock()


## (main thread, once the worker part is done) What needs the live world: a prop something else stands on or the town cleared in the
## meantime is dropped, generated saplings are recorded, forest beds look at the surface patches.
func _filter_prepared(build: ChunkBuild) -> void:
	build.filtered = true
	var kept: Array[WorldProp] = []
	for thing: WorldProp in build.chunk.things:
		if _things.has(thing.cell) or (_town_node != null and _town_node.cleared.has(thing.cell)):
			thing.free()
			continue
		if build.young.has(thing.cell):
			_young[thing.cell] = build.young[thing.cell]
		kept.append(thing)
	build.chunk.things = kept
	for bed: Dictionary in build.beds_pending:
		_add_forest_bed(build.chunk.node, bed.pos as Vector2, int(bed.variant), true)


func _advance_to(build: ChunkBuild, deadline: int, last_phase: int) -> bool:
	while build.phase < last_phase:
		if deadline > 0 and Time.get_ticks_usec() >= deadline: return false
		match build.phase:
			0:
				if build.query == null:
					build.query = _generator.begin_chunk(Rect2i(build.cell * CHUNK, Vector2i(CHUNK, CHUNK)))
				if not build.query.advance(deadline): return false
				build.obstacles = build.query.outer.duplicate()
				build.phase = 1
			1:
				_build_ground_row(build)
				build.index += 1
				if build.index == CHUNK:
					_update_void_rects(build.body, build.cell, build.open_runs, [] as Array[Vector2i], CHUNK)
					build.phase = 2
					build.index = 0
			2:
				var cliffs: StaticBody2D = StaticBody2D.new()
				cliffs.add_to_group("relief_walls")
				build.chunk.node.add_child(cliffs)
				for wall: Rect2 in _relief.blockers(Rect2i(build.cell * CHUNK, Vector2i(CHUNK, CHUNK))):
					var shape: CollisionShape2D = CollisionShape2D.new()
					var box: RectangleShape2D = RectangleShape2D.new()
					box.size = wall.size
					shape.shape = box
					shape.position = wall.get_center()
					cliffs.add_child(shape)
				build.phase = 3
			3:
				if build.index >= build.query.inner.size():
					build.phase = 4
					build.index = 0
					continue
				var spec: Dictionary = build.query.inner[build.index]
				build.index += 1
				if String(spec.kind) == "stonebed":
					_add_stone_bed(build.chunk.node, spec.pos as Vector2, int(spec.variant))
				elif String(spec.kind) == "forestbed":
					if _forest_bed_ok(spec.pos as Vector2, int(spec.variant), false): ## (the surface patches are asked on the main thread, `_filter_prepared`)
						build.beds_pending.append({"pos": spec.pos, "variant": spec.variant})
				elif not edits.props.has(WorldEdits.key(spec.cell as Vector2i)):
					_prepare_thing(build, spec.cell, String(spec.kind), int(spec.variant), spec)
			4:
				if build.index >= build.custom_keys.size():
					build.phase = 5
					build.index = 0
					continue
				var key_string: String = build.custom_keys[build.index]
				build.index += 1
				var cell: Vector2i = WorldEdits.cell(key_string)
				var spec: Dictionary = edits.props[key_string]
				if bool(spec.get("removed", false)): continue
				var at: Vector2 = PropGenerator.position_of(cell)
				var pos: Array = spec.get("pos", [at.x, at.y])
				build.obstacles.append({"pos": Vector2(float(pos[0]), float(pos[1])), "kind": spec.kind, "variant": int(spec.variant), "custom": true, "scale": float(spec.get("scale", 1.0))})
				if cell / CHUNK == build.cell:
					_prepare_thing(build, cell, String(spec.kind), int(spec.variant))
					build.custom[cell] = spec
			5:
				if build.index >= build.obstacles.size():
					build.phase = 6
					build.index = 0
					build.rng.seed = hash(Vector4i(build.cell.x, build.cell.y, _map.world_seed, 7919))
					continue
				_index_detail_obstacle(build, build.obstacles[build.index])
				build.log_reach = maxf(build.log_reach, FallenLogScatter.index_obstacle(build.log_grid, build.obstacles[build.index]))
				build.index += 1
			6:
				_detail_candidate(build)
				build.index += 1
				if build.index == (CHUNK / 2) * (CHUNK / 2):
					build.phase = 7
					build.index = 0
			7:
				var log_spec: Dictionary = FallenLogScatter.candidate(self,build.cell,build.index,build.obstacles,build.log_grid,build.log_reach)
				if not log_spec.is_empty():
					var log_node: FallenLog = FallenLog.new()
					log_node.name = "FallenLog_%d_%d_%d" % [build.cell.x,build.cell.y,build.index]
					log_node.setup(log_spec.pos as Vector2,int(log_spec.frame),self)
					build.chunk.fallen_logs.append(log_node)
				build.index += 1
				if build.index == 16:
					build.phase = 8
					build.index = 0
			8: ## one clover field per step (each paints its own atlas), then the details in a step of their own
				if build.index == 0:
					build.clover_rng.seed = hash(Vector4i(build.cell.x, build.cell.y, _map.world_seed, 6151))
					build.clover_count = 2 + (1 if build.clover_rng.randf() < 0.6 else 0) + (1 if build.clover_rng.randf() < 0.3 else 0)
				if build.index < build.clover_count:
					for _attempt: int in 5: ## a spot that is not open ground is given up on, the next try is somewhere else
						if _try_clover_field(build, build.clover_rng):
							break
					build.index += 1
				else:
					build.phase = 9
			9:
				for clover_job: Jobs.Job in build.clover_jobs:
					if not clover_job.is_finished():
						if deadline > 0: return false
						Jobs.wait(clover_job)
				build.clover_jobs.clear()
				if not build.points.is_empty():
					var details: MeadowDetails = MeadowDetails.new()
					details.name = "MeadowDetails"
					details.setup(build.points, Vector2(build.cell * CHUNK) * 16.0)
					build.chunk.node.add_child(details)
				build.phase = 10
	return true


func _build_ground_row(build: ChunkBuild) -> void:
	var y: int = build.index
	var runs: Array[Vector2i] = []
	var run_start: int = -1
	for x: int in CHUNK + 1:
		var cell: Vector2i = build.cell * CHUNK + Vector2i(x, y)
		var biome: String = "-" if x == CHUNK else _biome_at(cell)
		var lake: bool = x < CHUNK and _rivers.lake_at(Vector2(cell) * 16.0 + Vector2(8, 8))
		if biome == "" and not lake:
			if run_start < 0: run_start = x
			continue
		if run_start >= 0:
			runs.append(Vector2i(run_start, x))
			run_start = -1
		if x < CHUNK and biome != "":
			_paint(build.chunk, cell, biome, build.rng)
			if _outer_sdf[cell.y * RegionMap.WORLD_TILES + cell.x] < 136:
				_add_edge_light(build.chunk.node, cell, build.lit_cells)
	_update_void_rects(build.body, build.cell, build.open_runs, runs, y)


func _prepare_thing(build: ChunkBuild, cell: Vector2i, kind: String, variant: int, extra: Dictionary = {}) -> void:
	if build.reserved.has(cell): return ## (what the live world holds there is checked by `_filter_prepared`)
	var plant: Dictionary = DataRegistry.get_entry("plants", kind)
	var radius: float = _generator._foot(plant, kind, variant) * float(extra.get("scale", 1.0))
	var authored: Dictionary = edits.props.get(WorldEdits.key(cell), {})
	var at: Vector2 = PropGenerator.position_of(cell)
	var offset: Array = authored.get("pos", [at.x, at.y])
	if not _rivers.clear_for_prop(Vector2(float(offset[0]), float(offset[1])), radius * float(authored.get("scale", 1.0))): return
	build.reserved[cell] = true
	if extra.has("young"):
		build.young[cell] = {"age": int(extra.young), "variant": variant}
	build.chunk.things.append(_create_thing(cell, kind, variant, extra))


func _commit_chunk(build: ChunkBuild) -> void:
	var chunk: Chunk = build.chunk
	for biome: String in chunk.cells:
		for cell: Vector2i in chunk.cells[biome]:
			(_layers[biome] as TileMapLayer).set_cell(cell, 0, chunk.atlas[cell])
	for cell: Vector2i in chunk.glow_cells:
		_glow.set_cell(cell, 0, chunk.atlas[cell])
	chunk.atlas.clear()
	add_child(chunk.node) ## the ground (collision, lights, details) enters the world now; props follow next frame
	_pending_commit = build


## Second half of a commit, one frame later: props, fallen logs, clover, river surface, registration and wildlife. Until then the
## chunk is not in `_chunks`, so nothing unloads or builds it twice.
func _finish_commit(deadline: int = 0) -> void:
	var build: ChunkBuild = _pending_commit
	if build == null: return
	var chunk: Chunk = build.chunk

	# Stage 0: Props
	if build.commit_stage == 0:
		if build.commit_index == 0 and _town_node != null and not _town_node.cleared.is_empty(): ## a chunk that was in preparation while the town cleared a foundation
			var kept: Array[WorldProp] = []
			for prepared: WorldProp in chunk.things:
				if _town_node.cleared.has(prepared.cell):
					prepared.free()
				else:
					kept.append(prepared)
			chunk.things = kept
		while build.commit_index < chunk.things.size(): ## props enter the tree one by one: each runs its _ready (sprites, glow, light), which adds up on a thick wood
			if deadline > 0 and build.commit_index > 0 and Time.get_ticks_usec() >= deadline:
				return ## the rest follows next frame; the chunk is not in `_chunks` until it is whole
			var thing: WorldProp = chunk.things[build.commit_index]
			build.commit_index += 1
			_props.add_child(thing)
			_things[thing.cell] = thing
			if build.custom.has(thing.cell):
				var spec: Dictionary = build.custom[thing.cell]
				var pos: Array = spec.get("pos", [thing.position.x, thing.position.y])
				thing.position = Vector2(float(pos[0]), float(pos[1]))
				thing.scale = Vector2(float(spec.get("scale", 1.0)) * (-1.0 if bool(spec.get("flip", false)) else 1.0), float(spec.get("scale", 1.0)))
		build.commit_stage = 1
		build.commit_sub_index = 0

	# Stage 1: Fallen Logs
	if build.commit_stage == 1:
		while build.commit_sub_index < chunk.fallen_logs.size():
			if deadline > 0 and Time.get_ticks_usec() >= deadline:
				return
			var log_node: FallenLog = chunk.fallen_logs[build.commit_sub_index]
			build.commit_sub_index += 1
			_props.add_child(log_node)
			_register_harvest(log_node)
		build.commit_stage = 2
		build.commit_sub_index = 0

	# Stage 2: Clover Fields
	if build.commit_stage == 2:
		while build.commit_sub_index < chunk.clover.size():
			if deadline > 0 and Time.get_ticks_usec() >= deadline:
				return
			var field: CloverField = chunk.clover[build.commit_sub_index]
			build.commit_sub_index += 1
			_props.add_child(field)
			_register_harvest(field)
		build.commit_stage = 3

	# Stage 3: Finalize
	if build.commit_stage == 3:
		if deadline > 0 and Time.get_ticks_usec() >= deadline:
			return
		_pending_commit = null
		if sowing != null:
			sowing.populate(build.cell, chunk)
		_rivers.attach_chunk(chunk.node, build.cell)
		_chunks[build.cell] = chunk
		LeafCritter.settle_chunk(chunk.things)
		_wildlife.chunk_loaded(build.cell)


## Frees a build that never became live (its things and logs are not in the tree; a committed node is queued).
func _free_build(build: ChunkBuild) -> void:
	if build.job != null and Jobs.cancel(build.job):
		return ## a worker is (or was) busy with it: the discard hook frees it once the worker has let go
	_free_build_nodes(build)


func _free_build_nodes(build: ChunkBuild) -> void:
	for clover_job: Jobs.Job in build.clover_jobs: ## a worker may still paint a field: let it finish before the node goes
		Jobs.cancel(clover_job)
		Jobs.wait(clover_job)
	build.clover_jobs.clear()
	for thing: WorldProp in build.chunk.things:
		_things.erase(thing.cell)
		_young.erase(thing.cell)
		if thing.is_inside_tree():
			_props.remove_child(thing)
			thing.queue_free()
		else:
			thing.free()
	for log_node: FallenLog in build.chunk.fallen_logs:
		_unregister_harvest(log_node)
		if log_node.is_inside_tree():
			_props.remove_child(log_node)
			log_node.queue_free()
		else:
			log_node.free()
	for field: CloverField in build.chunk.clover:
		_unregister_harvest(field)
		if field.is_inside_tree():
			_props.remove_child(field)
			field.queue_free()
		else:
			field.free()
	if build.chunk.node.is_inside_tree(): build.chunk.node.queue_free()
	else: build.chunk.node.free()


func _discard_chunk_build() -> void:
	_finish_commit() ## a committed chunk becomes whole first, so an unload sees all of it
	_unload_queue.clear()
	if _building != null:
		_free_build(_building)
		_building = null
	for paused: ChunkBuild in _paused_builds.values():
		_free_build(paused)
	_paused_builds.clear()
	Jobs.drain() ## no worker may still read the relief or the edits when they change


func _exit_tree() -> void:
	if _pending_commit != null: ## its props never entered the tree: free them here, not in `_finish_commit`
		_free_build(_pending_commit)
		_pending_commit = null
	_discard_chunk_build()


## Tiles inland from the coast (0 at the shore; the baked field has 8 steps per tile). Negative outside the land.
func coast_tiles(point: Vector2) -> float:
	var x: int = floori(point.x / 16.0)
	var y: int = floori(point.y / 16.0)
	if x < 0 or y < 0 or x >= RegionMap.WORLD_TILES or y >= RegionMap.WORLD_TILES:
		return -1.0
	return (float(_sdf[y * RegionMap.WORLD_TILES + x]) - 128.0) / 8.0


## Where somebody who fell comes back: at the door of the hut / the town's house once the opening is over (the manhole before that).
func spawn_point() -> Vector2:
	if _town_node != null and _town_node.founded: ## (not `opening_over`: clients never play the opening, the founded town is synced)
		return _town_node.respawn_point()
	var hut: Hut = _hut() if opening_over else null
	if hut != null:
		return hut.exit_position
	return super()


## How deep the river or lake water is at `point` (-1 on land and in unloaded ground, 0 at the bank, 1 where swimming begins): where water creatures may be.
func water_depth(point: Vector2) -> float:
	var chunk: Vector2i = Vector2i(floori(point.x / (CHUNK * 16.0)), floori(point.y / (CHUNK * 16.0)))
	if not _chunks.has(chunk) or Interiors.slot_at(point) >= 0 or MineManager.in_mine(point):
		return -1.0
	return _rivers.depth_amount(point)


## Enemy navigation stays inside loaded land, including wall faces used by climb links.
func navigation_floor(point: Vector2) -> bool:
	if MineManager.in_mine(point):
		return (get_node("Mines") as MineManager).navigation_floor(point)
	if Interiors.slot_at(point) >= 0:
		return true ## inside a building the floor is the room (its colliders do the rest): the story fights there
	var tile: Vector2i = Vector2i(floori(point.x / 16.0), floori(point.y / 16.0))
	var chunk: Vector2i = Vector2i(floori(point.x / (CHUNK * 16.0)), floori(point.y / (CHUNK * 16.0)))
	var floor: bool = (_land_at(tile.x, tile.y) and _relief.is_land(tile.x, tile.y)) or _rivers.lake_at(point)
	return _chunks.has(chunk) and floor and not _rivers.is_deep(point)


## Grows void rectangles over equal runs of consecutive rows and emits finished ones.
func _update_void_rects(body: StaticBody2D, c: Vector2i, open_runs: Dictionary, runs: Array[Vector2i], row: int) -> void:
	var keys: Array[String] = []
	for run: Vector2i in runs:
		keys.append("%d:%d" % [run.x, run.y])
		if not open_runs.has(keys[-1]):
			open_runs[keys[-1]] = row
	for key: String in open_runs.keys():
		if keys.has(key):
			continue
		var x0: int = key.get_slice(":", 0).to_int()
		var x1: int = key.get_slice(":", 1).to_int()
		var y0: int = open_runs[key]
		open_runs.erase(key)
		var shape: CollisionShape2D = CollisionShape2D.new()
		var rect: RectangleShape2D = RectangleShape2D.new()
		rect.size = Vector2(x1 - x0, row - y0) * 16.0 + Vector2.ONE * 2.0 * VOID_MARGIN
		shape.shape = rect
		shape.position = (Vector2(c * CHUNK) + Vector2(x0 + x1, y0 + row) * 0.5) * 16.0
		body.add_child(shape)


## One violet light per few tiles of coast, so the edge also shines on the grass at night.
func _add_edge_light(parent: Node2D, cell: Vector2i, taken: Dictionary) -> void:
	var key: Vector2i = cell / EDGE_LIGHT_CELL
	if taken.has(key):
		return
	taken[key] = true
	var light: NightLight = NightLight.new()
	light.glow_color = EDGE_LIGHT_COLOR
	light.radius = 46
	light.base_energy = 0.55
	light.pulse = 0.25
	light.position = Vector2(cell) * 16.0 + Vector2(8.0, 8.0)
	parent.add_child(light)


func _paint(chunk: Chunk, cell: Vector2i, biome: String, rng: RandomNumberGenerator) -> void:
	var authored: Dictionary = {} if edits.terrain.is_empty() else edits.terrain.get(WorldEdits.key(cell), {}) ## (no key string per tile without edits)
	biome = RegionMap.active_biome(String(authored.get("biome", biome)))
	var kind: String = "plain"
	var ground: Dictionary = (DataRegistry.get_entry("biomes", biome).get("ground", {}) as Dictionary)
	if biome == "meadow":
		kind = _pick_tile_kind(_zone.get_noise_2d(cell.x, cell.y) * 0.5 + 0.5, rng)
	elif not ground.is_empty(): ## a biome with its own ground: only the kinds it names (the Hexenwald: plain grass and low tufts)
		var kinds: Array = ground.kinds as Array
		if rng.randf() < float(ground.chance):
			kind = String(kinds[rng.randi() % kinds.size()])
	elif rng.randf() < PLACEHOLDER_CHANCE:
		kind = COMMON_KINDS[rng.rand_weighted(COMMON_WEIGHTS)]
	if _relief.kind(cell.x, cell.y) != Relief.FLOOR: ## walls, ramps and stairs are drawn over plain ground
		kind = "plain"
	kind = String(authored.get("ground", kind))
	if chunk.water_near and not _rivers.clear_for_prop(Vector2(cell) * 16.0 + Vector2(8, 8), 0.0): kind = "plain"
	var options: Array = _tiles.get(kind, _tiles["plain"])
	var atlas: Array = options[rng.randi() % options.size()]
	var coords: Vector2i = Vector2i(int(atlas[0]), int(atlas[1]))
	chunk.atlas[cell] = coords
	if not chunk.cells.has(biome):
		chunk.cells[biome] = [] as Array[Vector2i]
	(chunk.cells[biome] as Array[Vector2i]).append(cell)
	if biome == "meadow" and GLOW_KINDS.has(kind):
		chunk.glow_cells.append(cell)
		_add_glow(cell, kind, options.find(atlas), chunk.node)


func _unload_chunk(c: Vector2i) -> void:
	_unload_queue.erase(c)
	if not _chunks.has(c):
		return
	_wildlife.chunk_unloaded(c)
	var chunk: Chunk = _chunks[c]
	for biome: String in chunk.cells:
		for cell: Vector2i in chunk.cells[biome]:
			(_layers[biome] as TileMapLayer).erase_cell(cell)
	for cell: Vector2i in chunk.glow_cells:
		_glow.erase_cell(cell)
	for thing: WorldProp in chunk.things:
		_things.erase(thing.cell)
		_young.erase(thing.cell)
		_props.remove_child(thing)
		thing.queue_free()
	for log_node: FallenLog in chunk.fallen_logs:
		_unregister_harvest(log_node)
		_props.remove_child(log_node)
		log_node.queue_free()
	for field: CloverField in chunk.clover:
		_unregister_harvest(field)
		_props.remove_child(field)
		field.queue_free()
	remove_child(chunk.node)
	chunk.node.queue_free()
	_chunks.erase(c)


# ---------------------------------------------------------------------------------- props
## Insert obstacle discs into every covered bucket, including moved/scaled authored props.
func _index_detail_obstacle(build: ChunkBuild, obstacle: Dictionary) -> void:
	if String(obstacle.kind) == "forestbed": ## the forest floor does not block small plants, it changes which ones grow
		if _forest_bed_ok(obstacle.pos as Vector2, int(obstacle.variant)):
			build.beds.append({"pos": obstacle.pos, "rx": PropGenerator.FOREST_BED_RX[int(obstacle.variant) % PropGenerator.FOREST_BED_RX.size()]})
		return
	if not bool(obstacle.get("custom", false)) and obstacle.has("cell") and edits.props.has(WorldEdits.key(obstacle.cell as Vector2i)): return
	var radius: float = 60.0
	if String(obstacle.kind) != "stonebed":
		var plant: Dictionary = DataRegistry.get_entry("plants", String(obstacle.kind))
		radius = float((plant.radius as Array)[int(obstacle.variant)]) * float(obstacle.get("scale", 1.0))
	radius += 8.0
	var pos: Vector2 = obstacle.pos
	var lo: Vector2i = Vector2i(((pos - Vector2.ONE * radius) / DETAIL_BUCKET).floor())
	var hi: Vector2i = Vector2i(((pos + Vector2.ONE * radius) / DETAIL_BUCKET).floor())
	var disc: Dictionary = {"pos": pos, "reach": radius}
	for y: int in range(lo.y, hi.y + 1):
		for x: int in range(lo.x, hi.x + 1):
			(build.obstacle_grid.get_or_add(Vector2i(x, y), []) as Array).append(disc)


func _detail_candidate(build: ChunkBuild) -> void:
	var x: int = (build.index % (CHUNK / 2)) * 2
	var y: int = (build.index / (CHUNK / 2)) * 2
	var cell: Vector2i = build.cell * CHUNK + Vector2i(x + build.rng.randi_range(0, 1), y + build.rng.randi_range(0, 1))
	if not _land_at(cell.x, cell.y) or _generator.blocked_cells.has(cell) or _stone_cells.has(cell):
		return
	var biome: String = _land_biome(cell)
	var density: float = float(build.density.get(biome, 0.3))
	var patch: float = _zone.get_noise_2d(cell.x * 2.3, cell.y * 2.3)
	if build.rng.randf() > density * (0.8 + patch):
		return
	var pos: Vector2 = Vector2(cell) * 16.0 + Vector2(build.rng.randf_range(3,13),build.rng.randf_range(5,14)).round()
	if not _rivers.clear_for_prop(pos, 10.0): return
	if not _relief.flat_around(pos, 10.0):
		return
	var obstructed: bool = false
	if Terrain.patches != build.patches_seen: build.patches_seen.assign(Terrain.patches) ## re-read only when the list changed, so the check below stays exact
	for patch_node: Node in build.patches_seen:
		if String(patch_node.call("surface_at", pos)) != "":
			obstructed = true
			break
	if obstructed:
		return
	# Every bucket includes all obstacle discs covering it; keep the exact old test.
	var bucket: Vector2i = Vector2i(floori(pos.x / DETAIL_BUCKET), floori(pos.y / DETAIL_BUCKET))
	for obstacle: Dictionary in build.obstacle_grid.get(bucket, []):
		if (obstacle.pos as Vector2).distance_to(pos) < float(obstacle.reach):
			obstructed = true
			break
	if obstructed:
		return
	var in_bed: bool = false
	for bed: Dictionary in build.beds: ## on a forest floor only shade plants grow, and fewer of them
		var offset: Vector2 = pos - (bed.pos as Vector2)
		var rx: float = float(bed.rx)
		if pow(offset.x / rx, 2.0) + pow(offset.y / (rx * FOREST_BED_FLATTEN), 2.0) < 0.8:
			in_bed = true
			break
	var kind: int = build.rng.randi_range(0,MeadowDetails.MEADOW_COUNT-3)
	# Most new ground cover stays green; blossoms accent the open patches.
	if build.rng.randf() < 0.35: kind = [0,1,2,3,9,10,11,12,13,14,18,19,20,21][build.rng.randi_range(0,13)]
	if biome == "mist_forest" and build.rng.randf() < 0.55:
		kind = [9,10,11,18,19,20,21][build.rng.randi_range(0,6)]
	elif biome == "glass_cliffs":
		kind = [0,2,5,7][build.rng.randi_range(0,3)]
	if in_bed:
		if build.rng.randf() < (0.15 if biome == "witch_forest" else 0.45): return ## the Hexenwald's floor is its own ground cover: little is left bare
		kind = [9,10,11,18,19,24,24,25,25,25][build.rng.randi_range(0,9)] ## ferns and shade moss
	else:
		var slope: float = _generator.aspect(pos / 16.0)
		if slope < -0.35 and build.rng.randf() < 0.65:
			kind = [9,10,11,18,19,24,25][build.rng.randi_range(0,6)] ## north slopes and cliff feet: damp, ferns and moss
		elif slope > 0.35 and build.rng.randf() < 0.55:
			kind = [22,23,0,2,22,23][build.rng.randi_range(0,5)] ## sunny slopes: dry straw and thin grass
		else:
			var damp: float = _generator.damp_at(pos / 16.0)
			if damp > 0.7 and build.rng.randf() < 0.5:
				kind = [9,10,11,18,19,24,25][build.rng.randi_range(0,6)] ## wet ground: moss and ferns
			elif damp < 0.18 and build.rng.randf() < 0.5:
				kind = [22,23,0,2,22,23][build.rng.randi_range(0,5)] ## dry ground: straw and thin grass
	if biome == "witch_forest": ## its own floor: dark grass, witch-hair moss, dead leaves, roots, tiny toadstools; on its forest beds no grass
		if in_bed:
			kind = [26, 26, 27, 27, 27, 28, 29, 25][build.rng.randi_range(0, 7)]
		elif build.rng.randf() < 0.5:
			kind = [0, 1, 2, 3, 12, 13, 13, 14][build.rng.randi_range(0, 7)]
		else:
			kind = [26, 26, 27, 28, 29, 24, 13][build.rng.randi_range(0, 6)]
	var tint: Color = Color.WHITE
	match biome:
		"witch_forest": tint = Color.WHITE.lerp(Color(0.42, 0.5, 0.68) if kind < MeadowDetails.MEADOW_COUNT else Color(0.82, 0.84, 0.94), BiomeBlend.amount_at(pos)) ## grass as dark as the ground under it, its own kinds only a little
		"mist_forest": tint = Color(0.79,0.95,0.94)
		"glass_cliffs": tint = Color(0.88,0.85,1.0)
		"sunken_ruins": tint = Color(0.94,0.88,0.73)
		"void_bloom": tint = Color(0.85,0.70,0.92)
	build.points.append({"pos":pos,"kind":kind,"phase":build.rng.randf(),"sway":build.rng.randf_range(0.8,1.5),"tint":tint,"exposure":float(DataRegistry.get_entry("wind","exposure").get(biome,1.0))})


## Small clover fields: each one is a crowd of standing clumps drawn from its own seed (CloverField), y-sorted so you stand in it. A field only
## lies on open, flat, dry meadow, off the footpath and stone floors; it may lie under trees and bushes (they stand over it).
func _try_clover_field(build: ChunkBuild, rng: RandomNumberGenerator) -> bool:
	var field: Dictionary = CloverField.plan(rng)
	var tile: Vector2i = build.cell * CHUNK + Vector2i(rng.randi_range(5, CHUNK - 6), rng.randi_range(5, CHUNK - 6))
	var open: float = 1.0 - smoothstep(0.5, 0.78, 1.0 - (_zone.get_noise_2d(tile.x, tile.y) * 0.5 + 0.5)) ## clover likes the open ground
	if rng.randf() > 0.6 + 0.4 * open:
		return false
	var center: Vector2 = Vector2(tile) * 16.0 + Vector2(8, 8)
	var rx: float = float(field.rx)
	var ry: float = float(field.ry)
	for other: Vector3 in build.clover_discs: ## two fields never lie in each other
		if Vector2(other.x, other.y).distance_to(center) < other.z + rx + 8.0:
			return false
	var ok: bool = _relief.flat_around(center, ry * 0.7) and _rivers.clear_for_prop(center, rx * 0.9)
	for a: int in 8:
		var edge: Vector2 = center + Vector2.from_angle(float(a) * TAU / 8.0) * Vector2(rx, ry) * 0.9
		var cell: Vector2i = Vector2i((edge / 16.0).floor())
		if not ok or not _land_at(cell.x, cell.y) or _generator.blocked_cells.has(cell) or _stone_cells.has(cell) or _generator.is_bare(cell):
			ok = false
			break
	if ok:
		for patch_node: Node in Terrain.patches:
			if String(patch_node.call("surface_at", center)) != "":
				ok = false
				break
	if ok: ## only on open ground: most of the field must be free of trees, bushes and rocks
		var free: int = 0
		for k: int in 14:
			var sample: Vector2 = center + Vector2.from_angle(float(k) * 2.4) * Vector2(rx, ry) * (0.2 + 0.6 * float(k % 5) / 4.0)
			if _detail_spot_free(build, sample):
				free += 1
		ok = free >= 10
	if not ok:
		return false
	var node: CloverField = CloverField.new()
	if Jobs.threaded: ## painting the atlas takes milliseconds: a worker does it while the chunk goes on
		build.clover_jobs.append(Jobs.run(func() -> Variant:
			node.setup(field, center, self)
			return null, Callable(), Jobs.Prio.HIGH, Callable(), build.cell))
	else:
		node.setup(field, center, self)
	build.clover_discs.append(Vector3(center.x, center.y, rx))
	build.chunk.clover.append(node)
	return true


## True when no prop of the chunk (and no solid ground decal) stands where a small plant would.
func _detail_spot_free(build: ChunkBuild, pos: Vector2) -> bool:
	var cell: Vector2i = Vector2i((pos / 16.0).floor())
	if not _land_at(cell.x, cell.y) or _generator.blocked_cells.has(cell) or _stone_cells.has(cell) or not _rivers.clear_for_prop(pos, 6.0):
		return false
	var bucket: Vector2i = Vector2i(floori(pos.x / DETAIL_BUCKET), floori(pos.y / DETAIL_BUCKET))
	for obstacle: Dictionary in build.obstacle_grid.get(bucket, []):
		if (obstacle.pos as Vector2).distance_to(pos) < float(obstacle.reach):
			return false
	return true


## The gravel under a rock formation: a decal on the ground, below everything that stands on it.
func _add_stone_bed(parent: Node2D, at: Vector2, variant: int) -> void:
	if not _rivers.clear_for_prop(at, PropGenerator.BED_RX[variant]): return
	var bed: Sprite2D = Sprite2D.new()
	bed.texture = STONE_BED
	bed.region_enabled = true
	bed.region_rect = Rect2(variant * 176, 0, 176, 120)
	bed.position = at
	bed.z_index = -9
	parent.add_child(bed)


## True where a litter patch of this size may lie: on land, dry, level, off the old stones and the footpath.
func _forest_bed_ok(at: Vector2, variant: int, check_patches: bool = true) -> bool:
	var rx: float = PropGenerator.FOREST_BED_RX[variant % PropGenerator.FOREST_BED_RX.size()]
	if not _rivers.clear_for_prop(at, rx * 0.8) or not _relief.flat_around(at, rx * 0.55):
		return false
	for angle: float in [0.0, PI * 0.5, PI, PI * 1.5]:
		var edge: Vector2 = at + Vector2.from_angle(angle) * Vector2(rx, rx * FOREST_BED_FLATTEN) * 0.75
		var cell: Vector2i = Vector2i((edge / 16.0).floor())
		if not _land_at(cell.x, cell.y) or _generator.blocked_cells.has(cell) or _stone_cells.has(cell):
			return false
	return not check_patches or _forest_bed_patches_ok(at)


func _forest_bed_patches_ok(at: Vector2) -> bool:
	for patch_node: Node in Terrain.patches:
		if String(patch_node.call("surface_at", at)) != "":
			return false
	return true


## The forest floor under a tree of a wood: litter, humus and moss, a decal on the ground below everything that stands on it.
func _add_forest_bed(parent: Node2D, at: Vector2, variant: int, checked: bool = false) -> void:
	if checked:
		if not _forest_bed_patches_ok(at): return
	elif not _forest_bed_ok(at, variant): return
	var bed: Sprite2D = Sprite2D.new()
	bed.texture = FOREST_BED
	bed.region_enabled = true
	var count: int = PropGenerator.FOREST_BED_RX.size() ## row 0 the meadow's litter, row 1 the Hexenwald's floor
	bed.region_rect = Rect2((variant % count) * FOREST_BED_FRAME.x, (variant / count) * FOREST_BED_FRAME.y, FOREST_BED_FRAME.x, FOREST_BED_FRAME.y)
	bed.position = at
	bed.z_index = -9
	parent.add_child(bed)


func _create_thing(cell: Vector2i, prop_kind: String, variant: int, extra: Dictionary = {}) -> WorldProp:
	var scene: PackedScene = load(String(DataRegistry.get_entry("plants", prop_kind).scene)) as PackedScene
	var thing: WorldProp = scene.instantiate() as WorldProp
	thing.setup(self, cell, prop_kind, variant)
	thing.position = PropGenerator.position_of(cell)
	if extra.has("scale"): ## Krummholz on the high levels: more swept by the wind. The sprite is never scaled: a shrunken sprite would have finer pixels than everything else.
		thing.wind_boost = 1.0 + 3.0 * (1.0 - float(extra.scale))
	return thing


func _spawn_thing(cell: Vector2i, prop_kind: String, variant: int) -> WorldProp:
	var thing: WorldProp = _create_thing(cell, prop_kind, variant)
	_props.add_child(thing)
	_things[cell] = thing
	return thing


## The props that are not untouched, for the save file ("x,y" -> state).
func export_things() -> Dictionary:
	var out: Dictionary = {}
	for cell: Vector2i in _thing_states:
		out["%d,%d" % [cell.x, cell.y]] = _thing_states[cell]
	for key: String in _harvest_states: ## clover fields and fallen logs: "h:" + their key
		out["h:" + key] = _harvest_states[key]
	if sowing != null:
		out.merge(sowing.export()) ## plants that seeded themselves: "s:x,y"
	return out


## Host, after loading a save: every prop takes the saved state (the others become untouched).
func import_things(saved: Dictionary) -> void:
	_thing_states.clear()
	_harvest_states.clear()
	if sowing != null:
		sowing.import_saved(saved)
	for key: String in saved:
		if key.begins_with("s:"):
			continue
		var state: Dictionary = {}
		for field: String in (saved[key] as Dictionary):
			var value: Variant = (saved[key] as Dictionary)[field]
			state[field] = int(value) if value is float else value ## JSON has only floats
		if state.has("pts"): ## cut spots of a clover field: JSON turned the Vector2s into strings "(x, y)"
			var pts: Array = []
			for point: Variant in (state["pts"] as Array):
				var v: Variant = str_to_var("Vector2" + String(point)) if point is String else point
				if v is Vector2:
					pts.append(v)
			state["pts"] = pts
		if key.begins_with("h:"):
			_harvest_states[key.trim_prefix("h:")] = state
			continue
		var parts: PackedStringArray = key.split(",")
		_thing_states[Vector2i(int(parts[0]), int(parts[1]))] = state
	for cell: Vector2i in _things:
		(_things[cell] as WorldProp).apply_state(thing_state(cell), "")
	for key: String in _harvest_nodes:
		_apply_harvest_to(key, "")


func thing_state(cell: Vector2i) -> Dictionary:
	if not _thing_states.has(cell) and _young.has(cell):
		return _young_state(cell)
	return _thing_states.get(cell, {})


## A sapling the generator planted: it grows with the days (`YOUNG_GROW_DAYS`), shown through the same felled -> stump / sapling / young
## tree states as a regrowing tree (state `f` and `h`), so it cannot be chopped until it is a fir. Mature = {} and forgotten.
func _young_state(cell: Vector2i) -> Dictionary:
	var info: Dictionary = _young[cell]
	var progress: float = (float(info.age) + float(TimeManager.day) - 1.0) / PropGenerator.YOUNG_GROW_DAYS
	if progress >= 1.0:
		_young.erase(cell)
		return {}
	var hits: Array = DataRegistry.get_entry("plants", "tree").get("hits", [4, 6, 8, 8]) as Array
	var slots: int = int(hits[int(info.variant)])
	return {"k": "tree", "f": 1, "h": clampi(slots - maxi(1, int(progress * float(slots))), 1, slots - 1)} ## never the bare stump (h = slots): a planted sapling is at least a sapling


## Sunrise: the saplings in view grow a step (every peer counts the days itself).
func _age_young(_day: int) -> void:
	for cell: Vector2i in _young.keys():
		var thing: WorldProp = _things.get(cell) as WorldProp
		if thing != null:
			thing.apply_state(thing_state(cell), "regrow")


## Local player pressed E at something that can be picked up (berries, a little stone).
func request_pick(cell: Vector2i) -> void:
	if multiplayer.is_server():
		_host_pick(cell, multiplayer.get_unique_id())
	else:
		_rpc_pick.rpc_id(1, cell)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_pick(cell: Vector2i) -> void:
	if multiplayer.is_server():
		_host_pick(cell, multiplayer.get_remote_sender_id())


func _host_pick(cell: Vector2i, peer: int) -> void:
	var thing: WorldProp = _things.get(cell) as WorldProp
	var player: Player = _players.get_node_or_null(str(peer)) as Player
	if thing == null or player == null or player.health.current <= 0.0 or thing.prompt() == "":
		return
	if thing.reach_distance(player.global_position) > Interactable.INTERACT_RANGE + PICK_SLACK:
		return
	_pick_thing(thing)


## Host: hand over what `thing` gives when picked and mark it picked (E, or a sickle blow on a plant that is picked).
func _pick_thing(thing: WorldProp) -> void:
	var cell: Vector2i = thing.cell
	var pickup: Dictionary = thing.spec().get("pickup", {}) as Dictionary
	if pickup.is_empty():
		return
	var amount_min: int = int(pickup.min) if pickup.has("min") else 1
	var amount_max: int = int(pickup.max) if pickup.has("max") else amount_min
	if pickup.has("amount"): ## the variant decides: a cluster of three gives three
		amount_min = int((pickup.amount as Array)[thing.variant])
		amount_max = amount_min
	var entries: Array = [{"id": pickup.item, "chance": 1.0, "min": amount_min, "max": amount_max}]
	var seed_drop: Dictionary = FarmRules.wild_seed(thing.kind) ## some wild plants give a seed as well (docs/farming.md)
	if not seed_drop.is_empty():
		entries.append({"id": seed_drop.id, "chance": seed_drop.chance, "min": 1, "max": 1})
	DropComponent.spawn_drops(get_tree(), entries, thing.global_position + Vector2(0, -8))
	var next: Dictionary = thing.state.duplicate()
	next["p"] = TimeManager.day + 1 ## the day it was picked (+ 1, so day 0 still counts as set)
	next["k"] = thing.kind
	_rpc_thing_state.rpc(cell, next, "pick")


## Host -> everyone: a prop plays a one-off effect (the Fangblume snapping shut). Props are found by cell, so a peer that has not loaded it skips it.
@rpc("authority", "call_local", "reliable")
func _rpc_thing_fx(cell: Vector2i, fx: String, at: Vector2) -> void:
	var thing: WorldProp = _things.get(cell) as WorldProp
	if is_instance_valid(thing) and thing.has_method("play_fx"):
		thing.call("play_fx", fx, at)


## Local player pressed E at an undergrowth animal on a bush (`LeafCritter`).
func request_catch(cell: Vector2i) -> void:
	if multiplayer.is_server():
		_host_catch(cell, multiplayer.get_unique_id(), true)
	else:
		_rpc_catch.rpc_id(1, cell)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_catch(cell: Vector2i) -> void:
	if multiplayer.is_server():
		_host_catch(cell, multiplayer.get_remote_sender_id(), true)


## A real foliage contact on the host scares a beetle away without dropping bait.
## The saved daily absence also prevents a client joining later from seeing it return.
func startle_critter(cell: Vector2i) -> void:
	if not multiplayer.is_server(): return
	var thing: WorldProp = _things.get(cell) as WorldProp
	if thing == null or LeafCritter.today(thing) != "beetle" or not LeafCritter.can_catch(thing): return
	var next: Dictionary = thing.state.duplicate()
	next["c"] = TimeManager.day + 1
	next["k"] = thing.kind
	_rpc_thing_state.rpc(cell, next, "depart")


## Host: take (or scare off) the animal sitting on the bush at `cell`. By hand it is a sure catch, with the sickle 55 %; either way it is
## gone until tomorrow. A catch is an item (bait for the river).
func _host_catch(cell: Vector2i, peer: int, by_hand: bool) -> void:
	var thing: WorldProp = _things.get(cell) as WorldProp
	var player: Player = _players.get_node_or_null(str(peer)) as Player
	if thing == null or player == null or player.health.current <= 0.0:
		return
	if by_hand and thing.reach_distance(player.global_position) > Interactable.INTERACT_RANGE + PICK_SLACK:
		return ## (a sickle blow was already measured by the hit scan)
	var animal: String = LeafCritter.today(thing)
	if animal == "" or not LeafCritter.can_catch(thing):
		return
	var caught: bool = by_hand or randf() < 0.55
	if caught:
		DropComponent.spawn_drops(get_tree(), [{"id": LeafCritter.ITEMS[animal], "chance": 1.0, "min": 1, "max": 1}], thing.global_position + Vector2(0, -10))
	var next: Dictionary = thing.state.duplicate()
	next["c"] = TimeManager.day + 1
	next["k"] = thing.kind
	_rpc_thing_state.rpc(cell, next, "catch" if caught else "scare")


## Host: a weapon's hit scan found `thing`. Only the prop's tool (sickle, pickaxe) harvests it, any
## other weapon just makes it rustle.
func harvest_hit(thing: WorldProp, source: int) -> void:
	if not multiplayer.is_server():
		return
	var harvest: Dictionary = thing.spec().get("harvest", {})
	var player: Player = _players.get_node_or_null(str(source)) as Player
	var tool_id: String = ""
	if player != null:
		tool_id = String(Items.definition(player.inventory.active_stack()).get("tool", ""))
	if tool_id == "sickle" and thing.spec().has("critters") and LeafCritter.can_catch(thing):
		_host_catch(thing.cell, source, false) ## the blow shakes the animal off (or it is caught)
	if harvest.is_empty() and thing.spec().has("pickup") and not thing.spec().has("pull"): ## plants E picks: the sickle cuts them too
		if tool_id == "sickle" and thing.prompt() != "":
			_pick_thing(thing)
		elif thing.prompt() != "":
			_rpc_thing_state.rpc(thing.cell, thing.state, "rustle")
		return
	if harvest.is_empty() or thing.is_depleted():
		return
	if tool_id != String(harvest.tool):
		_rpc_thing_state.rpc(thing.cell, thing.state, "rustle")
		return
	var hits: int = int(thing.state.get("h", 0)) + 1
	var next: Dictionary = thing.state.duplicate()
	var entries: Array = (harvest.drops as Array).duplicate()
	var strip: bool = hits >= thing.slots()
	next["h"] = hits
	next["k"] = thing.kind
	if strip:
		entries.append_array(harvest.final_drops as Array)
		if thing.spec().get("crown_fade") != null: ## trees: felled, then they regrow stage by stage
			next["f"] = 1
	DropComponent.spawn_drops(get_tree(), entries, thing.global_position + Vector2(0, -10))
	_rpc_thing_state.rpc(thing.cell, next, "strip" if strip else "hit")


## Host, every sunrise: each harvested prop gets one slot back per `regrow_days` of its kind, picked
## berries and stones come back after the kind's pickup `regrow_days`. Nothing ever disappears.
func _grow_things(day: int) -> void:
	_grow_harvest()
	for cell: Vector2i in _thing_states.keys():
		var before: Dictionary = _thing_states[cell]
		var plant: Dictionary = DataRegistry.get_entry("plants", String(before.get("k", "bush")))
		var next: Dictionary = before.duplicate()
		var slot_days: int = maxi(1, int((plant.get("harvest", {}) as Dictionary).get("regrow_days", 1)))
		if int(next.get("h", 0)) > 0 and day % slot_days == 0:
			next["h"] = int(next.h) - 1
			if int(next.h) <= 0:
				next.erase("h")
		var pick_days: int = int((plant.get("pickup", {}) as Dictionary).get("regrow_days", 3))
		if Moisture.is_wet_day(day):
			pick_days = maxi(1, pick_days - 1) ## a damp day: mushrooms, moss and herbs come back faster
		if next.has("c") and int(next.c) != day + 1:
			next.erase("c")
		if next.has("p") and day + 1 - int(next.p) >= pick_days:
			next.erase("p")
		if not next.has("h"):
			next.erase("f") ## fully regrown
		if next.keys() == ["k"]:
			next.clear()
		if next != before:
			_rpc_thing_state.rpc(cell, next, "regrow")


@rpc("authority", "call_local", "reliable")
func _rpc_thing_state(cell: Vector2i, state: Dictionary, fx: String) -> void:
	if state.is_empty():
		_thing_states.erase(cell)
	else:
		_thing_states[cell] = state
	var thing: WorldProp = _things.get(cell) as WorldProp
	if thing != null:
		thing.apply_state(state, fx)


## Clover fields and fallen logs (data/harvest.json): a sickle cuts a clover field, an axe chops a fallen log up. Only the host decides;
## every peer shows the state of the nodes its chunks have loaded.
func harvest_field_hit(node: Node, source: int) -> void:
	if not multiplayer.is_server():
		return
	var spec: Dictionary = node.call("spec") as Dictionary
	var key: String = String(node.get("key"))
	if spec.is_empty() or bool(node.call("is_depleted")):
		return
	var player: Player = _players.get_node_or_null(str(source)) as Player
	var tool_id: String = ""
	if player != null:
		tool_id = String(Items.definition(player.inventory.active_stack()).get("tool", ""))
	var at: Vector2 = player.global_position if player != null else (node as Node2D).global_position
	var state: Dictionary = (_harvest_states.get(key, {}) as Dictionary).duplicate()
	if tool_id != String(spec.get("tool", "")):
		_rpc_harvest_state.rpc(key, state, "rustle", at)
		return
	state["h"] = int(state.get("h", 0)) + 1
	var strip: bool = int(state["h"]) >= int(spec.get("hits", 1))
	if node.has_method("next_cut"): ## clover: each blow takes the clumps round one spot; the field is gone when none are left
		var points: Array = (state.get("pts", []) as Array).duplicate()
		points.append((node as Node2D).to_local(node.call("next_cut", at) as Vector2))
		state["pts"] = points
		if bool(node.call("all_cut", points)):
			strip = true
	var entries: Array = (spec.drops as Array).duplicate()
	if strip:
		state["f"] = 1
		entries.append_array(spec.final_drops as Array)
	DropComponent.spawn_drops(get_tree(), entries, (node as Node2D).global_position + Vector2(0, -6))
	_rpc_harvest_state.rpc(key, state, "strip" if strip else "hit", at)


@rpc("authority", "call_local", "reliable")
func _rpc_harvest_state(key: String, state: Dictionary, fx: String, at: Vector2) -> void:
	if state.is_empty():
		_harvest_states.erase(key)
	else:
		_harvest_states[key] = state
	_apply_harvest_to(key, fx, at)


@rpc("authority", "call_remote", "reliable")
func _rpc_harvest_snapshot(snapshot: Dictionary) -> void:
	_harvest_states = snapshot
	for key: String in _harvest_nodes:
		_apply_harvest_to(key, "")


func _apply_harvest_to(key: String, fx: String, at: Vector2 = Vector2.ZERO) -> void:
	var node: Object = _harvest_nodes.get(key)
	if is_instance_valid(node):
		node.call("apply_harvest", _harvest_states.get(key, {}), fx, at)


func _register_harvest(node: Node) -> void:
	var key: String = String(node.get("key"))
	_harvest_nodes[key] = node
	_apply_harvest_to(key, "")


func _unregister_harvest(node: Node) -> void:
	var key: String = String(node.get("key"))
	if _harvest_nodes.get(key) == node:
		_harvest_nodes.erase(key)


## Host, every sunrise: a clover field or water plant that was cut grows back whole. Fallen logs stay chopped.
func _grow_harvest() -> void:
	for key: String in _harvest_states.keys():
		if key.begins_with("c:") or key.begins_with("w:"):
			_rpc_harvest_state.rpc(key, {}, "regrow", Vector2.ZERO)


## A peer that joins gets every prop that is not untouched.
@rpc("authority", "call_remote", "reliable")
func _rpc_thing_snapshot(snapshot: Dictionary) -> void:
	_thing_states = snapshot
	for cell: Vector2i in _things:
		(_things[cell] as WorldProp).apply_state(thing_state(cell), "")


## Wildlife is native to green meadow floors, away from the void and steep relief edges.
func _rabbit_habitat(at: Vector2) -> bool:
	var cell: Vector2i = Vector2i(floori(at.x / 16.0), floori(at.y / 16.0))
	if not _land_at(cell.x, cell.y) or _sdf[cell.y * RegionMap.WORLD_TILES + cell.x] < 152:
		return false
	var biomes: Array = DataRegistry.get_entry("wildlife", "rabbit").get("biomes", ["meadow"])
	return biomes.has(_land_biome(cell)) and _relief.flat_around(at, 5.0) and _rivers.clear_for_prop(at, 5.0)


func _bird_habitat(at: Vector2, species: String) -> bool:
	var cell: Vector2i = Vector2i(floori(at.x / 16.0), floori(at.y / 16.0))
	if not _land_at(cell.x, cell.y) or _sdf[cell.y * RegionMap.WORLD_TILES + cell.x] < 152:
		return false
	var biomes: Array = DataRegistry.get_entry("wildlife", species).get("biomes", ["meadow"])
	return biomes.has(_land_biome(cell)) and _relief.flat_around(at, 4.0) and _rivers.clear_for_prop(at, 4.0)


func _fauna_habitat(at: Vector2, species: String) -> bool:
	var cell: Vector2i = Vector2i(floori(at.x / 16.0), floori(at.y / 16.0))
	if not _land_at(cell.x, cell.y) or _sdf[cell.y * RegionMap.WORLD_TILES + cell.x] < 152:
		return false
	var spec: Dictionary = DataRegistry.get_entry("wildlife", species)
	var biomes: Array = spec.get("biomes", ["meadow"])
	return biomes.has(_land_biome(cell)) and _relief.flat_around(at, float(spec.get("body_radius", 3.0)) + 2.0) and _rivers.clear_for_prop(at, float(spec.get("body_radius", 3.0)))


## Real painted meadow blossoms, not arbitrary air positions. Called after a chunk is painted.
func _flower_targets(chunk: Vector2i) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var atlases: Dictionary = {} ## a set of atlas coordinates (lookups per cell, not a list scan)
	for kind: String in DataRegistry.get_entry("wildlife", "butterfly").get("flower_kinds", []):
		for xy: Array in _tiles.get(kind, []):
			atlases[Vector2i(int(xy[0]), int(xy[1]))] = true
	for y: int in CHUNK:
		for x: int in CHUNK:
			var cell: Vector2i = chunk * CHUNK + Vector2i(x, y)
			if atlases.has(_ground.get_cell_atlas_coords(cell)):
				result.append(Vector2(cell) * 16.0 + Vector2(8, 8))
	return result


## Host-owned authoring snapshot; late joiners receive this same layer.
@rpc("authority", "call_remote", "reliable")
func _rpc_editor_snapshot(data: Dictionary) -> void:
	editor_apply(data, false)

func editor_apply(data: Dictionary, broadcast: bool = true) -> void:
	_discard_chunk_build()
	var terrain_changed: bool = edits.terrain != data.get("terrain", {})
	edits.assign(data)
	if terrain_changed:
		_relief.editor_apply(edits.terrain)
		_generator._cache.clear()
	var loaded: Array = _chunks.keys()
	for c: Vector2i in _chunks.keys():
		_unload_chunk(c)
	for c: Vector2i in loaded:
		_load_chunk(c)
	_stream(true)
	if broadcast and multiplayer.is_server() and not multiplayer.get_peers().is_empty():
		_rpc_editor_snapshot.rpc(edits.data())

func editor_prop(cell: Vector2i) -> Dictionary:
	if not _things.has(cell):
		return {}
	var thing: WorldProp = _things[cell]
	return {"kind": thing.kind, "variant": thing.variant, "pos": [thing.position.x, thing.position.y], "scale": absf(thing.scale.y), "flip": thing.scale.x < 0.0}

func editor_pick(pos: Vector2) -> WorldProp:
	var best: WorldProp
	var distance: float = 48.0
	for thing: WorldProp in _things.values():
		var d: float = pos.distance_to(thing.position + Vector2(0, -minf(thing._height * 0.4, 28.0)))
		if d < distance:
			distance = d
			best = thing
	return best

func editor_land(cell: Vector2i) -> bool:
	return _land_at(cell.x, cell.y)

func editor_height(cell: Vector2i) -> int:
	return _relief.level(cell.x, cell.y)

func editor_refresh() -> void:
	_stream_settled = false
	_stream(false)


# ---------------------------------------------------------------------------------- the town (docs/town.md)
func hut_node() -> Hut:
	return _hut()


func town() -> TownManager:
	return _town_node


## What the ground says against a piece standing on `rect` (px, its footprint): "" = nothing. Land, one flat level, no water, nothing solid in the way.
func town_probe(rect: Rect2) -> String:
	var wide: Rect2 = rect.grow(8.0)
	var middle: Vector2i = Vector2i(floori(rect.get_center().x / 16.0), floori(rect.get_center().y / 16.0))
	var home: int = _relief.level(middle.x, middle.y)
	for y: int in range(floori(wide.position.y / 16.0), floori(wide.end.y / 16.0) + 1):
		for x: int in range(floori(wide.position.x / 16.0), floori(wide.end.x / 16.0) + 1):
			if not _land_at(x, y) or not _relief.is_land(x, y):
				return "KEIN LAND"
			if _relief.kind(x, y) != Relief.FLOOR or _relief.level(x, y) != home:
				return "ZU UNEBEN"
	if not _rivers.clear_for_prop(rect.get_center(), maxf(rect.size.x, rect.size.y) * 0.5):
		return "ZU NAH AM WASSER"
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = rect.size - Vector2(2.0, 2.0)
	query.shape = box
	query.transform = Transform2D(0.0, rect.get_center())
	query.collision_mask = 1
	if not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
		return "IM WEG"
	return ""


## The height level a point stands on (for the town's ways, which stay on one level).
func town_level_at(point: Vector2) -> int:
	return _relief.level(floori(point.x / 16.0), floori(point.y / 16.0))


## Can a trampled way run over this point? Land, flat floor of `level`, no water, nothing solid within 5 px.
func town_walkable(point: Vector2, level: int) -> bool:
	var x: int = floori(point.x / 16.0)
	var y: int = floori(point.y / 16.0)
	if not _land_at(x, y) or not _relief.is_land(x, y) or _relief.kind(x, y) != Relief.FLOOR or _relief.level(x, y) != level:
		return false
	if not _rivers.clear_for_prop(point, 4.0):
		return false
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 5.0
	query.shape = circle
	query.transform = Transform2D(0.0, point)
	query.collision_mask = 1
	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _town_soft(thing: WorldProp) -> bool:
	if thing.kind in ((TownRules.config().get("soft_kinds", []) as Array)):
		return true
	if thing.kind in PropGenerator.TREE_KINDS:
		return thing.state.has("f") ## felled: stump and sapling have no collision (a young tree grows back by itself otherwise)
	return (thing.kind == "rock" or thing.kind == "iron_rock" or thing.kind == "curse_rock") and thing.is_depleted()


## The loaded props a foundation on `rect` sweeps away (cells): bushes, grass, pebbles, mushrooms, stumps and spent rocks.
func town_soft_cells(rect: Rect2) -> Array:
	var out: Array = []
	for cell: Vector2i in _things:
		var thing: WorldProp = _things[cell] as WorldProp
		if _town_soft(thing) and rect.grow(thing._radius * 0.8).has_point(thing.position):
			out.append(cell)
	return out


## Everyone: these props are gone (the town cleared them).
func town_clear_cells(cells: Array) -> void:
	for raw: Variant in cells:
		var cell: Vector2i = raw as Vector2i
		_thing_states.erase(cell) ## nothing grows back there
		if not _things.has(cell):
			continue
		var thing: WorldProp = _things[cell] as WorldProp
		_things.erase(cell)
		for chunk: Chunk in _chunks.values():
			chunk.things.erase(thing)
		if thing.get_parent() != null:
			thing.get_parent().remove_child(thing)
		thing.queue_free()


func export_story() -> Dictionary:
	return fallen_knight.export_data() if fallen_knight != null else {}
func import_story(data: Dictionary) -> void:
	if fallen_knight != null: fallen_knight.import_data(data)
