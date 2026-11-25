class_name ZoneWorld
extends "res://src/world/test_level.gd"
## Official v2 main world host (`ALTMARK`, `ZoneDirector`, `Interiors`, `MineManager`, `PocketSpace`, `NightDirector`,
## `MapDiscovery`, `Waystones`, `GoddessSystem`, `Vistas`, `BossRelics`, `PetRegistry`, `LootChests`, `Puzzles`,
## `VeilThreads`, `WildlifePopulation`).
## Replaces `WorldLevel` and the legacy v1 zone prototype in `GameLauncher`, `MainMenu`, and `PauseMenu`.
## Joins group `"world"` ONLY (never `"zone_world"` or `"story_world"`).


class _ZoneMapStub extends RefCounted:
	var world_seed: int = 42


const PICK_SLACK: float = 16.0
const VEIL_THREADS_PATH: String = "res://src/systems/veil_threads.gd"

var _map: _ZoneMapStub = _ZoneMapStub.new() ## WorldWind and NightDirector read `_map.world_seed`
var opening_over: bool = true ## no legacy sewer lock; NightDirector.active() uses `night_enabled()`
var night: NightDirector

@onready var _wildlife: WildlifePopulation = get_node_or_null("Wildlife") as WildlifePopulation

var _atlas: Atlas
var _director: ZoneDirector
var _interiors: Interiors
var _mines: MineManager
var _dungeons: DungeonManager
var _wind: WorldWind
var _chests: LootChests
var _puzzles: Puzzles
var _veil_threads: Node = null
var _water_field: WaterField = null

var _zone_wildlife_chunks: Dictionary = {} ## zone_id -> Array[Vector2i]
var _zone_chests_placed: Dictionary = {} ## zone_id -> true
var _zone_puzzles_placed: Dictionary = {} ## zone_id -> true
var _zone_dungeons_placed: Dictionary = {} ## zone_id -> true

var _init_stage: int = 0
var _start_zone_attached: bool = false
var _warm_stage: int = 0
var _teardown_started: bool = false
var _vista_focus_pos: Vector2 = Vector2.INF
var _vista_focus_radius: int = 0
var _capture_dir: String = ""
var _capture_started: bool = false
var _cli_dungeon_id: String = ""
var _cli_dungeon_started: bool = false


func _ready() -> void:
	add_to_group("world")
	_capture_dir = _parse_capture_arg()
	_cli_dungeon_id = _parse_cli_arg("--dungeon=")
	if (not _capture_dir.is_empty() or not _cli_dungeon_id.is_empty()) and multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		NetworkManager.host_singleplayer()
	if loading_in_steps:
		_begin_stepped_load()
		return
	while not loading_init_step():
		pass
	while not loading_step():
		pass
	while not loading_warmup_step():
		pass


static func _parse_capture_arg() -> String:
	return _parse_cli_arg("--capture-windkap=")


static func _parse_cli_arg(prefix: String) -> String:
	var all_args: PackedStringArray = OS.get_cmdline_user_args()
	all_args.append_array(OS.get_cmdline_args())
	for arg: String in all_args:
		if arg.begins_with(prefix):
			return arg.substr(prefix.length()).strip_edges()
	return ""


func _fill_ground() -> void:
	pass ## v2 zones paint their own ground via ZoneStage


func loading_init_step() -> bool:
	if _stepped_init_done:
		return true
	match _init_stage:
		0:
			RenderingServer.set_default_clear_color(Color("120e1f"))
			LightTexture.prewarm(PackedInt32Array([24, 26, 28, 34, 36, 40]))
			_atlas = Atlas.shared()
			_director = ZoneDirector.new()
			_director.setup(_atlas, &"main", _ground.tile_set, _ground.material, _players)
			_director.flags_source = func() -> Dictionary:
				var local_p: Player = SaveGame._local_player(get_tree())
				if local_p != null and local_p.quests != null:
					return local_p.quests._flags
				return {}
			_director.stage_attached.connect(_on_stage_attached)
			_director.stage_detached.connect(_on_stage_detached)
			add_child(_director)
			_interiors = Interiors.new()
			_interiors.defer_setup = true
			add_child(_interiors)
			_mines = MineManager.new()
			_mines.setup(_map.world_seed)
			add_child(_mines)
			_dungeons = DungeonManager.new()
			add_child(_dungeons)
			var discovery: MapDiscovery = MapDiscovery.new()
			discovery.name = "MapDiscovery"
			add_child(discovery)
			var waystones: Waystones = Waystones.new()
			waystones.name = "Waystones"
			add_child(waystones)
			var goddess: GoddessSystem = GoddessSystem.new()
			goddess.name = "GoddessSystem"
			add_child(goddess)
			var vistas: Vistas = Vistas.new()
			vistas.name = "Vistas"
			add_child(vistas)
			var relics: BossRelics = BossRelics.new()
			relics.name = "BossRelics"
			add_child(relics)
			var pets: PetRegistry = PetRegistry.new()
			pets.name = "PetRegistry"
			add_child(pets)
			_chests = LootChests.new()
			_chests.name = "LootChests"
			_chests.load_default_placed = false
			add_child(_chests)
			_puzzles = Puzzles.new()
			_puzzles.name = "Puzzles"
			_puzzles.source = ""
			add_child(_puzzles)
			if ResourceLoader.exists(VEIL_THREADS_PATH):
				var vt_script: Script = load(VEIL_THREADS_PATH) as Script
				if vt_script != null:
					var vt_node: Node = vt_script.new() as Node
					if vt_node != null:
						vt_node.name = "VeilThreads"
						add_child(vt_node)
						_veil_threads = vt_node
			if _wildlife != null:
				_wildlife.setup(
					_map.world_seed,
					_wildlife_ground_ok,
					_bird_habitat_ok,
					_fauna_habitat_ok,
					_zone_flower_targets
				)
			_wind = WorldWind.new()
			_wind.name = "WorldWind"
			_wind.setup(self)
			add_child(_wind)
			night = NightDirector.new()
			night.name = "NightDirector"
			night.setup(self)
			add_child(night)
			if multiplayer.is_server():
				TimeManager.day_started.connect(_on_day_started_grow)
				multiplayer.peer_connected.connect(_on_peer_connected_props)
			_init_stage = 1
			return false
		1:
			if _interiors.setup_step(Time.get_ticks_usec() + 5500):
				_init_stage = 2
			return false
		2:
			_init_server_players()
			_stepped_init_done = true
			return true
	return true


func loading_step() -> bool:
	if _director == null:
		return true
	if _start_zone_attached:
		return not _director.is_building()
	var target: StringName = &""
	var local_p: Player = SaveGame._local_player(get_tree())
	if local_p != null and _atlas != null:
		var outer_pos: Vector2 = Interiors.outer(get_tree(), local_p.global_position)
		target = _atlas.zone_at(&"main", outer_pos)
	if target == &"":
		target = _start_zone_id()
	if target != &"" and not _director.is_loaded(target):
		_director.load_now(target)
	_start_zone_attached = true
	return not _director.is_building()


func loading_warmup_step() -> bool:
	match _warm_stage:
		0:
			var local_p: Player = SaveGame._local_player(get_tree())
			if local_p != null:
				var cam: Camera2D = local_p.get("_camera") as Camera2D
				if cam != null:
					cam.reset_smoothing()
				if _interiors != null:
					_interiors.apply_view(local_p)
			_warm_stage = 1
			return false
		1:
			var deadline: int = Time.get_ticks_usec() + 5500
			for player: Player in Player.all:
				if player.is_multiplayer_authority() and player._hud != null:
					var map_win: MapWindow = player._hud.get_node_or_null("MapWindow") as MapWindow
					if map_win != null and not map_win.warm_step(deadline):
						return false
					break
			_warm_stage = 2
			return false
		2:
			var day_night: DayNight = get_node_or_null("DayNight") as DayNight
			if day_night != null:
				day_night._process(0.016)
			if _wind != null:
				_wind._process(0.016)
			_warm_stage = 3
			if not _capture_dir.is_empty() and not _capture_started:
				_capture_started = true
				call_deferred("_run_windkap_capture")
			elif not _cli_dungeon_id.is_empty() and not _cli_dungeon_started:
				_cli_dungeon_started = true
				call_deferred("_launch_cli_dungeon")
			return true
	return true


func _launch_cli_dungeon() -> void:
	if _dungeons == null or not multiplayer.is_server():
		return
	var p: Player = SaveGame._local_player(get_tree())
	if p == null:
		return
	var def: Dictionary = DungeonRules.by_id(_cli_dungeon_id)
	var min_lv: int = int(def.get("min_level", 1))
	if p.progress != null and p.progress.level < min_lv:
		p.progress.award(0, maxi(0, Levels.xp_at(min_lv) - p.progress.xp))
		p.progress.request_claim(min_lv)
	if p.dungeons != null:
		p.dungeons.mark_discovered(_cli_dungeon_id)
	_dungeons.request_enter_solo(_cli_dungeon_id, true)


func _on_stage_attached(zone_id: StringName) -> void:
	if _director == null:
		return
	var stage: ZoneStage = _director.stages.get(zone_id) as ZoneStage
	if stage == null:
		return
	if stage.water != null:
		_water_field = stage.water

	var raw: Dictionary = stage.zone.raw
	var origin: Vector2 = Vector2(stage.zone.origin)

	if _chests != null and not _zone_chests_placed.has(zone_id):
		_zone_chests_placed[zone_id] = true
		var chests_v: Variant = raw.get("chests")
		if chests_v is Array:
			for c_v: Variant in chests_v as Array:
				if not (c_v is Dictionary):
					continue
				var cd: Dictionary = c_v as Dictionary
				var cid: String = String(cd.get("id", ""))
				var t_arr: Array = cd.get("tile", []) as Array
				if cid.is_empty() or t_arr.size() < 2:
					continue
				var pos_px: Vector2 = Atlas.px_of(origin + Vector2(float(t_arr[0]), float(t_arr[1]))).round()
				_chests.place(cid, String(cd.get("tier", "common")), pos_px, bool(cd.get("flip", false)))

	if _puzzles != null and not _zone_puzzles_placed.has(zone_id):
		_zone_puzzles_placed[zone_id] = true
		var puzzles_v: Variant = raw.get("puzzles")
		if puzzles_v is Array:
			for p_v: Variant in puzzles_v as Array:
				if p_v is Dictionary:
					_puzzles.place_trial(p_v as Dictionary, origin)

	if not _zone_dungeons_placed.has(zone_id):
		_zone_dungeons_placed[zone_id] = true
		for ddef: Dictionary in DungeonRules.in_zone(zone_id):
			if not bool(ddef.get("playable", false)):
				continue
			var tile_arr: Array = ddef.get("entrance_tile", []) as Array
			if tile_arr.size() < 2:
				continue
			var gate: DungeonEntrance = DungeonEntrance.new()
			gate.name = "DungeonGate_%s" % String(ddef.get("id", ""))
			gate.dungeon_id = String(ddef.get("id", ""))
			gate.zone_id = zone_id
			gate.position = Atlas.px_of(origin + Vector2(float(tile_arr[0]), float(tile_arr[1]))).round()
			add_child(gate)

	if multiplayer.is_server() and _wildlife != null:
		var bpx: Rect2 = Rect2(Atlas.px_of(stage.zone.bbox.position), Atlas.px_of(stage.zone.bbox.size))
		var min_c: Vector2i = Vector2i(floori(bpx.position.x / 512.0), floori(bpx.position.y / 512.0))
		var max_c: Vector2i = Vector2i(floori(bpx.end.x / 512.0), floori(bpx.end.y / 512.0))
		var cells: Array[Vector2i] = []
		for cy: int in range(min_c.y, max_c.y + 1):
			for cx: int in range(min_c.x, max_c.x + 1):
				var cell: Vector2i = Vector2i(cx, cy)
				cells.append(cell)
				_wildlife.load_zone_chunk(cell)
		_zone_wildlife_chunks[zone_id] = cells

		var w_raw: Variant = raw.get("wildlife")
		if w_raw is Dictionary:
			var sites_v: Variant = (w_raw as Dictionary).get("crow_sites")
			if sites_v is Array:
				var sites_px: Array[Vector2] = []
				for s_v: Variant in sites_v as Array:
					if s_v is Array and (s_v as Array).size() >= 2:
						var sa: Array = s_v as Array
						sites_px.append(Atlas.px_of(origin + Vector2(float(sa[0]), float(sa[1]))).round())
				var corvids: CorvidPopulation = get_tree().get_first_node_in_group("corvid_population") as CorvidPopulation
				if corvids != null and not sites_px.is_empty():
					corvids.spawn_zone_crow_sites(sites_px, String(zone_id))


func _on_stage_detached(zone_id: StringName) -> void:
	if _water_field != null and not is_instance_valid(_water_field):
		_water_field = null
	if _director != null and (_water_field == null or not _water_field.is_inside_tree()):
		_water_field = null
		for st_v: Variant in _director.stages.values():
			var st: ZoneStage = st_v as ZoneStage
			if st != null and st.water != null:
				_water_field = st.water
				break
	if multiplayer.is_server():
		var corvids: CorvidPopulation = get_tree().get_first_node_in_group("corvid_population") as CorvidPopulation
		if corvids != null:
			corvids.clear_zone_crow_sites(String(zone_id))
		if _wildlife != null and _zone_wildlife_chunks.has(zone_id):
			var old_cells: Array[Vector2i] = _zone_wildlife_chunks[zone_id] as Array[Vector2i]
			_zone_wildlife_chunks.erase(zone_id)
			var still_used: Dictionary = {}
			for other_list_v: Variant in _zone_wildlife_chunks.values():
				for oc: Vector2i in other_list_v as Array[Vector2i]:
					still_used[oc] = true
			for c: Vector2i in old_cells:
				if not still_used.has(c):
					_wildlife.chunk_unloaded(c)


func resume_story(_player: Player) -> void:
	TimeManager.unlock()


const CRYPT_SHAFT: Vector2 = Vector2(366.0, 263.0) ## room px in sternenauge_krypta: inside the shaft at its east rim; she crawls out east along the hand prints and drag marks


## A new game (host/solo): she arrives through the canal shaft in the crypt under the Sternenauge (`CryptArrival`).
func start_intro() -> void:
	TimeManager.unlock()
	var player: Player = SaveGame._local_player(get_tree())
	var interiors: Interiors = get_tree().get_first_node_in_group("interiors") as Interiors
	if player == null or interiors == null or interiors.interior(Sternenauge.CRYPT) == null:
		return
	interiors.place_player(player, Sternenauge.CRYPT, CRYPT_SHAFT)
	var arrival: CryptArrival = CryptArrival.new()
	add_child(arrival)
	arrival.start(player, interiors.interior(Sternenauge.CRYPT).room_to_global(CRYPT_SHAFT))


func begin_story() -> void:
	TimeManager.unlock()


func teardown_step(deadline_usec: int) -> bool:
	if not _teardown_started:
		_teardown_started = true
		set_process(false)
		set_physics_process(false)
		if _director != null:
			_director.set_process(false)
			if _director._job != null:
				Jobs.cancel(_director._job)
				Jobs.wait(_director._job)
				_director._job = null
				_director._job_zone = &""
			if _director._attaching != null:
				_director._attaching.free()
				_director._attaching = null
	if _director != null:
		for zid: Variant in _director.stages.keys():
			_director._unload(zid as StringName)
			if deadline_usec > 0 and Time.get_ticks_usec() >= deadline_usec:
				break
		return _director.stages.is_empty()
	return true


func director() -> ZoneDirector:
	return _director


func _start_zone_id() -> StringName:
	if _atlas == null:
		return &""
	if _atlas.zone(&"windkap") != null:
		return &"windkap"
	var main_zones: Array[Atlas.Zone] = _atlas.zones_of(&"main")
	return main_zones[0].id if not main_zones.is_empty() else &""


static func _extract_tile(value: Variant, dict_keys: PackedStringArray) -> Vector2:
	if value is Array:
		var arr: Array = value as Array
		if arr.size() >= 2:
			return Vector2(float(arr[0]), float(arr[1]))
	elif value is Dictionary:
		var dict: Dictionary = value as Dictionary
		for key: String in dict_keys:
			var nested: Variant = dict.get(key)
			if nested is Array:
				var arr: Array = nested as Array
				if arr.size() >= 2:
					return Vector2(float(arr[0]), float(arr[1]))
	return Vector2.INF


func spawn_player_at_windkap_camp() -> Vector2:
	if _atlas != null:
		var z: Atlas.Zone = _atlas.zone(_start_zone_id())
		if z != null:
			var camp_tile: Vector2 = _extract_tile(z.raw.get("camp_tile"), PackedStringArray(["tile", "camp_tile"]))
			if not camp_tile.is_finite():
				camp_tile = _extract_tile(z.raw.get("spawn"), PackedStringArray(["camp_tile", "tile"]))
			if not camp_tile.is_finite():
				camp_tile = _extract_tile(z.raw.get("camp"), PackedStringArray(["tile", "campfire_tile"]))
			if camp_tile.is_finite():
				return Atlas.px_of(Vector2(z.origin) + camp_tile)
			for lm: Atlas.Landmark in z.landmarks:
				if lm.id == &"camp" or lm.id == &"coastal_camp":
					return Atlas.px_of(lm.pos)
			return Atlas.px_of(z.center())
	return Vector2(1600.0, 1600.0)


func _spawn_position(index: int) -> Vector2:
	return spawn_player_at_windkap_camp() + Vector2(16.0 * float(index), 0.0)


func _clamp_spawn(pos: Vector2) -> Vector2:
	return pos


func spawn_point() -> Vector2:
	return spawn_player_at_windkap_camp()


## Host: may `peer` come back at `target`? "" / home / camp always; a waystone only when it is awake and lies in the
## zone the player fell in (when that is known).
func respawn_allowed(peer_id: int, target: StringName) -> bool:
	if target == &"" or target == &"home" or target == &"camp":
		return true
	var ws: Waystones = Waystones.of(get_tree())
	if ws == null or not ws.is_awake(String(target)):
		return false
	if _director != null:
		var here: StringName = _director.player_zone.get(peer_id, &"") as StringName
		var there: StringName = ws.zone_of(String(target))
		if here != &"" and there != &"" and here != there:
			return false
	return true


## Where a player comes back: an awake waystone, home (the town's door once it is founded) or the coast camp.
func respawn_point_for(_peer_id: int, target: StringName = &"") -> Vector2:
	if target != &"" and target != &"camp" and target != &"home":
		var ws: Waystones = Waystones.of(get_tree())
		if ws != null and ws.is_awake(String(target)):
			var spec: Dictionary = ws.specs().get(String(target), {}) as Dictionary
			var tile: Variant = spec.get("tile")
			if tile is Array and (tile as Array).size() >= 2:
				var arr: Array = tile as Array
				var pos: Vector2 = Atlas.px_of(Vector2(float(arr[0]), float(arr[1]))) + Vector2(8.0, 16.0)
				if _director != null and _atlas != null:
					var zid: StringName = _atlas.zone_at(_director.continent_id, pos)
					if zid != &"" and not _director.is_loaded(zid):
						_director.load_now(zid)
				return pos
	if target != &"camp":
		var town: TownManager = get_tree().get_first_node_in_group("town") as TownManager
		if town != null and town.founded:
			var door: Vector2 = town.respawn_point()
			if door.is_finite() and door != Vector2.ZERO:
				return door
	return spawn_player_at_windkap_camp()


func set_vista_focus(world_pos: Vector2, chunk_radius: int = 2) -> void:
	_vista_focus_pos = world_pos
	_vista_focus_radius = maxi(chunk_radius, 1)


func clear_vista_focus() -> void:
	_vista_focus_pos = Vector2.INF
	_vista_focus_radius = 0


# ---------------------------------------------------------------------------------- water, navigation & wildlife queries

func water_depth(point: Vector2) -> float:
	if PocketSpace.is_pocket(point) or Interiors.slot_at(point) >= 0 or MineManager.in_mine(point):
		return -1.0
	if _water_field != null and is_instance_valid(_water_field):
		var d: float = _water_field.depth_amount(point)
		if d >= 0.0:
			return d
	if _director != null:
		for st_v: Variant in _director.stages.values():
			var st: ZoneStage = st_v as ZoneStage
			if st != null and st.water != null and st.water != _water_field:
				var d2: float = st.water.depth_amount(point)
				if d2 >= 0.0:
					return d2
	return -1.0


func navigation_floor(point: Vector2) -> bool:
	if DungeonManager.in_dungeon(point) and _dungeons != null:
		return _dungeons.navigation_floor(point)
	if PocketSpace.is_pocket(point):
		return true
	if _director == null or _atlas == null:
		return false
	var zid: StringName = _atlas.zone_at(_director.continent_id, point)
	if zid == &"" or not _director.is_loaded(zid):
		return false
	return water_depth(point) < 0.08


func _wildlife_ground_ok(pos: Vector2) -> bool:
	return navigation_floor(pos)


func _bird_habitat_ok(pos: Vector2, _species: String) -> bool:
	return navigation_floor(pos)


func _fauna_habitat_ok(pos: Vector2, _species: String) -> bool:
	return navigation_floor(pos)


func _zone_flower_targets(cell: Vector2i) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if _director == null:
		return out
	var box: Rect2 = Rect2(Vector2(cell) * 512.0, Vector2(512.0, 512.0))
	for st_v: Variant in _director.stages.values():
		var st: ZoneStage = st_v as ZoneStage
		if st == null:
			continue
		for prop_v: Variant in st.flora_nodes.values():
			var prop: WorldProp = prop_v as WorldProp
			if prop == null or not is_instance_valid(prop):
				continue
			if box.has_point(prop.global_position):
				out.append(prop.global_position)
				if out.size() >= 18:
					return out
	return out


func coast_tiles(_point: Vector2 = Vector2.ZERO) -> float:
	return 999.0


func town() -> TownManager:
	return null


func town_probe(_rect: Rect2, _exclude: Array[RID] = []) -> String:
	return ""


func _land_biome(_tile: Vector2i) -> String:
	return "meadow"


# ---------------------------------------------------------------------------------- night director hooks (townless zones)

func night_enabled() -> bool:
	if _director == null:
		return false
	for st_v: Variant in _director.stages.values():
		var st: ZoneStage = st_v as ZoneStage
		if st == null:
			continue
		var ns: Variant = st.zone.raw.get("night_spawns")
		if ns is Dictionary and bool((ns as Dictionary).get("enabled", true)):
			return true
	return false


func raids_allowed() -> bool:
	return false


func zone_danger_scale(members: Array[Player]) -> float:
	if _atlas == null or _director == null or members.is_empty():
		return 1.0
	var zid: StringName = _atlas.zone_at(_director.continent_id, members[0].global_position)
	if zid == &"":
		return 1.0
	return _atlas.danger_scale(zid)


func zone_allows_water_night(members: Array[Player]) -> bool:
	if _atlas == null or _director == null or members.is_empty():
		return false
	var zid: StringName = _atlas.zone_at(_director.continent_id, members[0].global_position)
	if zid == &"":
		return false
	var z: Atlas.Zone = _atlas.zone(zid)
	if z == null:
		return false
	var ns: Variant = z.raw.get("night_spawns")
	return ns is Dictionary and bool((ns as Dictionary).get("light_fisher", false))


## Blocks night spawns ONLY inside lit safe sanctuaries (campfires, lighthouse, awakened waystones); never blocks water!
func spawn_blocked(pos: Vector2) -> bool:
	for node: Node in get_tree().get_nodes_in_group("campfires"):
		var n2: Node2D = node as Node2D
		if n2 != null and is_instance_valid(n2) and n2.global_position.distance_squared_to(pos) <= 145.0 * 145.0:
			return true
	for node: Node in get_tree().get_nodes_in_group("windkap_lighthouse"):
		var n2: Node2D = node as Node2D
		if n2 != null and is_instance_valid(n2) and n2.global_position.distance_squared_to(pos) <= 120.0 * 120.0:
			return true
	var ws: Waystones = Waystones.of(get_tree())
	if ws != null:
		for wid: String in ws.specs():
			if not ws.is_awake(wid):
				continue
			var tile_v: Variant = (ws.specs()[wid] as Dictionary).get("tile")
			if tile_v is Array and (tile_v as Array).size() >= 2:
				var a: Array = tile_v as Array
				var wpx: Vector2 = Atlas.px_of(Vector2(float(a[0]), float(a[1])))
				if wpx.distance_squared_to(pos) <= 115.0 * 115.0:
					return true
	return false


# ---------------------------------------------------------------------------------- host-authoritative harvestable flora

func _find_prop_and_stage(cell: Vector2i) -> Dictionary:
	if _director == null:
		return {}
	for st_v: Variant in _director.stages.values():
		var st: ZoneStage = st_v as ZoneStage
		if st != null and st.flora_nodes.has(cell):
			return {"stage": st, "prop": st.flora_nodes[cell] as WorldProp}
	return {}


func thing_state(cell: Vector2i) -> Dictionary:
	if _director == null:
		return {}
	for st_v: Variant in _director.stages.values():
		var st: ZoneStage = st_v as ZoneStage
		if st != null and st.prop_states.has(cell):
			return st.prop_states[cell] as Dictionary
	return {}


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
	var found: Dictionary = _find_prop_and_stage(cell)
	if found.is_empty():
		return
	var stage: ZoneStage = found["stage"] as ZoneStage
	var thing: WorldProp = found["prop"] as WorldProp
	var player: Player = _players.get_node_or_null(str(peer)) as Player
	if thing == null or player == null or player.health.current <= 0.0 or thing.prompt() == "":
		return
	if thing.reach_distance(player.global_position) > Interactable.INTERACT_RANGE + PICK_SLACK:
		return
	_pick_thing(stage, thing)


func _pick_thing(stage: ZoneStage, thing: WorldProp) -> void:
	var pickup: Dictionary = thing.spec().get("pickup", {}) as Dictionary
	if pickup.is_empty():
		return
	var amount_min: int = int(pickup.min) if pickup.has("min") else 1
	var amount_max: int = int(pickup.max) if pickup.has("max") else amount_min
	if pickup.has("amount"):
		amount_min = int((pickup.amount as Array)[thing.variant])
		amount_max = amount_min
	var entries: Array = [{"id": pickup.item, "chance": 1.0, "min": amount_min, "max": amount_max}]
	var vt_sys: VeilThreads = VeilThreads.of(get_tree())
	if vt_sys != null:
		var bonus_ch: float = vt_sys.harvest_double_chance()
		if stage != null and stage.zone != null:
			var zb: Dictionary = vt_sys.zone_blessing_status(stage.zone.id)
			if bool(zb.get("half_unlocked", false)):
				bonus_ch += 0.10
		if bonus_ch > 0.0 and randf() < bonus_ch:
			entries.append({"id": pickup.item, "chance": 1.0, "min": 1, "max": 1})
	var seed_drop: Dictionary = FarmRules.wild_seed(thing.kind)
	if not seed_drop.is_empty():
		entries.append({"id": seed_drop.id, "chance": seed_drop.chance, "min": 1, "max": 1})
	DropComponent.spawn_drops(get_tree(), entries, thing.global_position + Vector2(0.0, -8.0))
	var next: Dictionary = thing.state.duplicate()
	next["p"] = TimeManager.day + 1
	next["k"] = thing.kind
	_broadcast_prop_state(stage.zone.id, thing.cell, next, "pick")


func request_catch(cell: Vector2i) -> void:
	if multiplayer.is_server():
		_host_catch(cell, multiplayer.get_unique_id(), true)
	else:
		_rpc_catch.rpc_id(1, cell)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_catch(cell: Vector2i) -> void:
	if multiplayer.is_server():
		_host_catch(cell, multiplayer.get_remote_sender_id(), true)


func startle_critter(cell: Vector2i) -> void:
	if not multiplayer.is_server():
		return
	var found: Dictionary = _find_prop_and_stage(cell)
	if found.is_empty():
		return
	var stage: ZoneStage = found["stage"] as ZoneStage
	var thing: WorldProp = found["prop"] as WorldProp
	if thing == null or LeafCritter.today(thing) != "beetle" or not LeafCritter.can_catch(thing):
		return
	var next: Dictionary = thing.state.duplicate()
	next["c"] = TimeManager.day + 1
	next["k"] = thing.kind
	_broadcast_prop_state(stage.zone.id, cell, next, "depart")


func _host_catch(cell: Vector2i, peer: int, by_hand: bool) -> void:
	var found: Dictionary = _find_prop_and_stage(cell)
	if found.is_empty():
		return
	var stage: ZoneStage = found["stage"] as ZoneStage
	var thing: WorldProp = found["prop"] as WorldProp
	var player: Player = _players.get_node_or_null(str(peer)) as Player
	if thing == null or player == null or player.health.current <= 0.0:
		return
	if by_hand and thing.reach_distance(player.global_position) > Interactable.INTERACT_RANGE + PICK_SLACK:
		return
	var animal: String = LeafCritter.today(thing)
	if animal == "" or not LeafCritter.can_catch(thing):
		return
	var caught: bool = by_hand or randf() < 0.55
	if caught:
		DropComponent.spawn_drops(get_tree(), [{"id": LeafCritter.ITEMS[animal], "chance": 1.0, "min": 1, "max": 1}], thing.global_position + Vector2(0.0, -10.0))
	var next: Dictionary = thing.state.duplicate()
	next["c"] = TimeManager.day + 1
	next["k"] = thing.kind
	_broadcast_prop_state(stage.zone.id, cell, next, "catch" if caught else "scare")


func harvest_hit(thing: WorldProp, source: int) -> void:
	if not multiplayer.is_server():
		return
	var found: Dictionary = _find_prop_and_stage(thing.cell)
	if found.is_empty():
		return
	var stage: ZoneStage = found["stage"] as ZoneStage
	var harvest: Dictionary = thing.spec().get("harvest", {}) as Dictionary
	var player: Player = _players.get_node_or_null(str(source)) as Player
	var tool_id: String = ""
	if player != null:
		tool_id = String(Items.definition(player.inventory.active_stack()).get("tool", ""))
	if tool_id == "sickle" and thing.spec().has("critters") and LeafCritter.can_catch(thing):
		_host_catch(thing.cell, source, false)
	if harvest.is_empty() and thing.spec().has("pickup") and not thing.spec().has("pull"):
		if tool_id == "sickle" and thing.prompt() != "":
			_pick_thing(stage, thing)
		elif thing.prompt() != "":
			_broadcast_prop_state(stage.zone.id, thing.cell, thing.state, "rustle")
		return
	if harvest.is_empty() or thing.is_depleted():
		return
	if tool_id != String(harvest.tool):
		_broadcast_prop_state(stage.zone.id, thing.cell, thing.state, "rustle")
		return
	var hits: int = int(thing.state.get("h", 0)) + 1
	var next: Dictionary = thing.state.duplicate()
	var entries: Array = (harvest.drops as Array).duplicate()
	var strip: bool = hits >= thing.slots()
	next["h"] = hits
	next["k"] = thing.kind
	if strip:
		entries.append_array(harvest.final_drops as Array)
	DropComponent.spawn_drops(get_tree(), entries, thing.global_position + Vector2(0.0, -10.0))
	_broadcast_prop_state(stage.zone.id, thing.cell, next, "strip" if strip else "hit")


func _broadcast_prop_state(zone_id: StringName, cell: Vector2i, state: Dictionary, fx: String) -> void:
	if NetworkManager.rpc_ready(self):
		_rpc_zone_prop_state.rpc(String(zone_id), cell, state, fx)
	else:
		_rpc_zone_prop_state(String(zone_id), cell, state, fx)


@rpc("authority", "call_local", "reliable")
func _rpc_zone_prop_state(zone_id_str: String, cell: Vector2i, state: Dictionary, fx: String) -> void:
	if _director == null:
		return
	var st: ZoneStage = _director.stages.get(StringName(zone_id_str)) as ZoneStage
	if st == null:
		return
	if state.is_empty():
		st.prop_states.erase(cell)
	else:
		st.prop_states[cell] = state
	var prop: WorldProp = st.flora_nodes.get(cell) as WorldProp
	if prop != null and is_instance_valid(prop):
		prop.apply_state(state, fx)


func _on_day_started_grow(_day: int) -> void:
	if not multiplayer.is_server() or _director == null:
		return
	for st_v: Variant in _director.stages.values():
		var st: ZoneStage = st_v as ZoneStage
		if st == null:
			continue
		var before: Dictionary = st.prop_states.duplicate(true)
		st.catch_up(1)
		for cell_v: Variant in before.keys():
			var cell: Vector2i = cell_v as Vector2i
			var next_state: Dictionary = st.prop_states.get(cell, {}) as Dictionary
			if next_state != (before[cell] as Dictionary):
				_broadcast_prop_state(st.zone.id, cell, next_state, "regrow")


func _on_peer_connected_props(peer_id: int) -> void:
	if not multiplayer.is_server() or _director == null or not NetworkManager.rpc_ready(self):
		return
	var snap: Dictionary = {}
	for zid_v: Variant in _director.stages:
		var st: ZoneStage = _director.stages[zid_v] as ZoneStage
		if st != null and not st.prop_states.is_empty():
			snap[String(zid_v as StringName)] = st.prop_states.duplicate(true)
	if not snap.is_empty():
		_rpc_zone_prop_snapshot.rpc_id(peer_id, snap)


@rpc("authority", "call_remote", "reliable")
func _rpc_zone_prop_snapshot(snap: Dictionary) -> void:
	if _director == null:
		return
	for zid_str: Variant in snap:
		var st: ZoneStage = _director.stages.get(StringName(String(zid_str))) as ZoneStage
		if st == null:
			continue
		var states: Dictionary = snap[zid_str] as Dictionary
		for cell_v: Variant in states:
			var cell: Vector2i = cell_v as Vector2i
			var state: Dictionary = states[cell] as Dictionary
			st.prop_states[cell] = state
			var prop: WorldProp = st.flora_nodes.get(cell) as WorldProp
			if prop != null and is_instance_valid(prop):
				prop.apply_state(state, "")


# ---------------------------------------------------------------------------------- persistence

func export_zone_state() -> Dictionary:
	return {
		"director": _director.export_state() if _director != null else {},
		"opening_over": opening_over,
	}


func import_zone_state(data: Dictionary) -> void:
	opening_over = bool(data.get("opening_over", true))
	if _director != null and data.has("director"):
		_director.import_state(SaveGame.as_dict(data.get("director")))


# ---------------------------------------------------------------------------------- automated ingame verification captures

func _run_windkap_capture() -> void:
	DirAccess.make_dir_recursive_absolute(_capture_dir)
	var z: Atlas.Zone = _atlas.zone(&"windkap") if _atlas != null else null
	var p: Player = SaveGame._local_player(get_tree())
	if z == null or p == null:
		push_error("ZoneWorld capture failed: windkap zone or local player missing")
		get_tree().quit(1)
		return
	var cam: Camera2D = p.get("_camera") as Camera2D
	var origin: Vector2 = Vector2(z.origin)
	if p._hud != null:
		p._hud.visible = false
	var shots: Array = [
		{"file": "windkap_camp.png", "local": Vector2(83.5, 194.5), "zoom": 1.0, "time": 0.42, "off": Vector2(0.0, 12.0)},
		{"file": "windkap_ruin_vista.png", "local": Vector2(49.5, 158.0), "zoom": 1.0, "time": 0.42, "off": Vector2(-12.0, -4.0)},
		{"file": "windkap_vista_zoom.png", "local": Vector2(38.8, 161.1), "zoom": 0.56, "time": 0.42, "off": Vector2(-220.0, 140.0)},
		{"file": "windkap_bridge.png", "local": Vector2(185.1, 121.0), "zoom": 1.0, "time": 0.44, "off": Vector2(0.0, 0.0)},
		{"file": "windkap_blocker.png", "local": Vector2(133.5, 29.0), "zoom": 1.0, "time": 0.44, "off": Vector2(0.0, -16.0)},
		{"file": "windkap_blocker_gate.png", "local": Vector2(283.5, 62.5), "zoom": 1.0, "time": 0.44, "off": Vector2(18.0, -8.0)},
		{"file": "windkap_night.png", "local": Vector2(83.5, 199.5), "zoom": 0.90, "time": 0.96, "off": Vector2(0.0, 32.0), "night_test": true},
		{"file": "windkap_waystone.png", "local": Vector2(142.1, 56.5), "zoom": 1.0, "time": 0.44, "off": Vector2(0.0, -8.0)},
	]
	for shot_v: Variant in shots:
		var shot: Dictionary = shot_v as Dictionary
		for grp: String in ["speech_box", "dialogue_box"]:
			for ui_n: Node in get_tree().get_nodes_in_group(grp):
				if ui_n is CanvasItem:
					(ui_n as CanvasItem).visible = false
				if ui_n.has_method("close"):
					ui_n.call("close")
		var t_day: float = float(shot["time"])
		TimeManager.lock_at(t_day)
		var pos: Vector2 = Atlas.px_of(origin + (shot["local"] as Vector2))
		p.global_position = pos
		if cam != null:
			var zf: float = float(shot["zoom"])
			cam.zoom = Vector2(zf, zf)
			cam.offset = shot["off"] as Vector2
			cam.reset_smoothing()
		if bool(shot.get("night_test", false)) and night != null:
			for _t: int in 14:
				night._spawn_clock = 999.0
				night._water_wait = 0.0
				night.tick()
			print("CAPTURE NIGHT live=%d water=%d" % [night.live_count(), night.live_water()])
			if night.live_water() == 0:
				var deep_pt: Vector2 = water_spot(pos + Vector2(0.0, 140.0), 0.55, 240.0)
				if deep_pt.is_finite():
					spawn_species("light_fisher", deep_pt, 0.0, 1.0, 1.0, false)
		for _f: int in 10:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		var out_path: String = _capture_dir.path_join(String(shot["file"]))
		img.save_png(out_path)
		print("CAPTURED ", out_path)
	get_tree().quit(0)
