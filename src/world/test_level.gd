class_name TestLevel
extends Node2D
## Movement test arena (the base of `World`, which overrides `_fill_ground`, `_spawn_position` and `_clamp_spawn`). Server spawns one Player per connected peer.

const PLAYER_SCENE: PackedScene = preload("res://src/entities/player/player.tscn")
const SPIDER_SCENE: PackedScene = preload("res://src/entities/enemies/shadow_spider.tscn")
const LISTENER_SCENE: PackedScene = preload("res://src/entities/enemies/void_listener.tscn")
const CRUSHER_SCENE: PackedScene = preload("res://src/entities/enemies/void_crusher.tscn")
const FISHER_SCENE: PackedScene = preload("res://src/entities/enemies/light_fisher.tscn")
const RESONANCE_SCENE: PackedScene = preload("res://src/entities/enemies/resonance_wave.tscn")
const QUARTZ_GOLEM_PATH: String = "res://src/entities/enemies/quartz_golem.tscn"
const QUARTZ_SHARD_PATH: String = "res://src/entities/enemies/quartz_shard.tscn"
const ARENA_LIMIT: Vector2 = Vector2(380, 220)

const LUSH_KINDS: Array[String] = ["flower", "petal", "bloom", "clover", "tuft"]
const LUSH_WEIGHTS: PackedFloat32Array = [5.0, 2.0, 1.2, 1.5, 1.0]
const WILD_KINDS: Array[String] = ["fern", "mushroom", "stone", "clump", "glyph"]
const WILD_WEIGHTS: PackedFloat32Array = [3.0, 2.0, 1.5, 2.0, 0.12]
const COMMON_KINDS: Array[String] = ["tuft", "clump", "clover", "petal"]
const COMMON_WEIGHTS: PackedFloat32Array = [3.0, 1.0, 1.0, 0.5]
## Night glow of the flora: kind -> [color, light radius px, energy]. The third mushroom tile is teal.
const GLOW_KINDS: Dictionary = {
	"bloom": [Color("5ff0dc"), 28, 0.95],
	"mushroom": [Color("a97cff"), 24, 0.8],
	"glyph": [Color("5ff0dc"), 36, 0.6],
}
const GROUND_RECT: Rect2i = Rect2i(-52, -32, 104, 64) ## in tiles, covers arena plus camera overscroll

@onready var _ground: TileMapLayer = $Ground
@onready var _glow: TileMapLayer = $Glow ## the glowing pixels of luminous plants, unshaded
@onready var _players: Node2D = $Players
@onready var _enemies: Node2D = $Enemies

var _enemy_count: int = 0
var _wave_count: int = 0


func _ready() -> void:
	add_to_group("world") ## the save file finds it here
	_fill_ground()
	Terrain.register_layer(_ground)
	if not multiplayer.is_server():
		return
	multiplayer.peer_connected.connect(_spawn_player)
	multiplayer.peer_disconnected.connect(_despawn_player)
	_spawn_player(multiplayer.get_unique_id())


func _process(_delta: float) -> void:
	if InputManager.debug_spawn_pressed():
		var pos: Vector2 = InputManager.aim_world_position()
		if multiplayer.is_server():
			_spawn_enemy(pos)
		else:
			_rpc_spawn_enemy.rpc_id(1, pos)
	if InputManager.debug_listener_pressed():
		var pos: Vector2 = InputManager.aim_world_position()
		if multiplayer.is_server():
			_spawn_listener(pos)
		else:
			_rpc_spawn_listener.rpc_id(1, pos)
	if InputManager.debug_crusher_pressed():
		var pos: Vector2 = InputManager.aim_world_position()
		if multiplayer.is_server():
			_spawn_crusher(pos)
		else:
			_rpc_spawn_crusher.rpc_id(1, pos)
	if InputManager.debug_fisher_pressed():
		var pos: Vector2 = InputManager.aim_world_position()
		if multiplayer.is_server():
			_spawn_fisher(pos)
		else:
			_rpc_spawn_fisher.rpc_id(1, pos)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_spawn_fisher(pos: Vector2) -> void:
	if multiplayer.is_server():
		_spawn_fisher(pos)


## Water creatures may only be where there is water: depth as a share of the swimming depth, -1 on land. The arena has none; `WorldLevel` answers from the rivers and lakes.
func water_depth(_point: Vector2) -> float:
	return -1.0


## The nearest water at least `min_depth` deep within `radius` px of `pos` (a ring search); INF when there is none.
func water_spot(pos: Vector2, min_depth: float, radius: float = 160.0) -> Vector2:
	if water_depth(pos) >= min_depth:
		return pos
	var step: float = 8.0
	var rings: int = int(radius / step)
	for ring: int in range(1, rings + 1):
		var sides: int = maxi(8, ring * 6)
		for side: int in sides:
			var point: Vector2 = pos + Vector2.from_angle(side * TAU / float(sides)) * float(ring) * step
			if water_depth(point) >= min_depth:
				return point
	return Vector2.INF


## F5: the nearest deep enough water to the cursor, so a click on the shore also works. Nothing happens away from water.
func _spawn_fisher(pos: Vector2) -> LightFisher:
	if not multiplayer.is_server():
		return null
	var min_depth: float = float(DataRegistry.get_entry("enemies", "light_fisher").get("min_depth", 0.3))
	var at: Vector2 = water_spot(pos, min_depth + 0.25)
	if not at.is_finite():
		return null
	var fisher: LightFisher = FISHER_SCENE.instantiate() as LightFisher
	_enemy_count += 1
	fisher.name = "Fisher%d" % _enemy_count
	fisher.position = at
	fisher.heading = randf() * TAU
	fisher.emerge_on_spawn = true
	_enemies.add_child(fisher)
	return fisher


@rpc("any_peer", "call_remote", "reliable")
func _rpc_spawn_listener(pos: Vector2) -> void:
	if multiplayer.is_server():
		_spawn_listener(pos)


## Dev spawns choose the nearest clear footprint (a circle of `radius`), including at cliffs/trees; INF when there is none.
func _clear_spot(pos: Vector2, radius: float) -> Vector2:
	var at: Vector2 = _clamp_spawn(pos)
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = radius
	query.shape = circle
	query.collision_mask = 1
	for ring: int in 9:
		for side: int in 12:
			var point: Vector2 = at + Vector2.from_angle(side * TAU / 12.0) * ring * 8.0
			if has_method("navigation_floor") and not bool(call("navigation_floor", point)):
				continue
			query.transform = Transform2D(0.0, point + Vector2(0, -4))
			if get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
				return point
	return Vector2.INF


@rpc("any_peer", "call_remote", "reliable")
func _rpc_spawn_crusher(pos: Vector2) -> void:
	if multiplayer.is_server():
		_spawn_crusher(pos)


func _spawn_crusher(pos: Vector2) -> VoidCrusher:
	if not multiplayer.is_server():
		return null
	var at: Vector2 = _clear_spot(pos, 11.0)
	if not at.is_finite():
		return null
	var crusher: VoidCrusher = CRUSHER_SCENE.instantiate() as VoidCrusher
	_enemy_count += 1
	crusher.name = "Crusher%d" % _enemy_count
	crusher.position = at
	crusher.heading = randf() * TAU
	_enemies.add_child(crusher)
	return crusher


func _spawn_listener(pos: Vector2) -> VoidListener:
	if not multiplayer.is_server():
		return null
	var at: Vector2 = _clear_spot(pos, 7.0)
	if not at.is_finite():
		return null
	var listener: VoidListener = LISTENER_SCENE.instantiate() as VoidListener
	_enemy_count += 1
	listener.name = "Listener%d" % _enemy_count
	listener.position = at
	listener.heading = randf() * TAU
	_enemies.add_child(listener)
	return listener


func spawn_resonance(at: Vector2, dir: Vector2, mouth: Vector2 = Vector2.INF, damage_scale: float = 1.0) -> ResonanceWave:
	if not multiplayer.is_server():
		return null
	var wave: ResonanceWave = RESONANCE_SCENE.instantiate() as ResonanceWave
	_wave_count += 1
	wave.name = "Resonance%d" % _wave_count
	wave.origin = at
	wave.direction = dir
	wave.emission_point = mouth
	wave.damage_scale = damage_scale
	wave.position = at
	get_node("EnemyProjectiles").add_child(wave)
	return wave


func spawn_quartz_shard(at: Vector2, dir: Vector2, emission: Vector2, variant: int = 0, damage_scale: float = 1.0) -> Node2D:
	if not multiplayer.is_server():
		return null
	var shard_scene: PackedScene = load(QUARTZ_SHARD_PATH) as PackedScene
	var shard: Node2D = shard_scene.instantiate() as Node2D
	_wave_count += 1
	shard.name = "QuartzShard%d" % _wave_count
	shard.set("origin", at)
	shard.set("direction", dir)
	shard.set("emission_point", emission)
	shard.set("variant", variant)
	shard.set("damage_scale", damage_scale)
	shard.position = at
	get_node("EnemyProjectiles").add_child(shard)
	return shard


func spawn_quartz_golem(at: Vector2, heading: float, variant: int = 0, start_dormant: bool = false, health_scale: float = 1.0, damage_scale: float = 1.0, emerge: bool = false) -> Node2D:
	if not multiplayer.is_server():
		return null
	var golem_scene: PackedScene = load(QUARTZ_GOLEM_PATH) as PackedScene
	var golem: Node2D = golem_scene.instantiate() as Node2D
	_enemy_count += 1
	golem.name = "Enemy%d" % _enemy_count
	golem.position = at
	golem.set("home_pos", at)
	golem.set("heading", heading)
	golem.set("variant", variant)
	golem.set("start_dormant", start_dormant)
	golem.set("health_scale", health_scale)
	golem.set("damage_scale", damage_scale)
	golem.set("emerge_on_spawn", emerge)
	_enemies.add_child(golem)
	return golem


@rpc("any_peer", "call_remote", "reliable")
func _rpc_spawn_enemy(pos: Vector2) -> void:
	if multiplayer.is_server():
		_spawn_enemy(pos)


## Host only. Dev tool for now; night waves will use the same path.
func _spawn_enemy(pos: Vector2) -> void:
	var spider: ShadowSpider = SPIDER_SCENE.instantiate() as ShadowSpider
	_enemy_count += 1
	spider.name = "Spider%d" % _enemy_count
	spider.position = _clamp_spawn(pos)
	spider.heading = randf() * TAU
	_enemies.add_child(spider)


## Host only: an enemy of the species `enemy_id` (data/enemies.json; a void crusher, a void listener, every other one is a spider) with the given scale of health and damage; `emerge`: it rises out of the ground (the night's cracks).
## The species and the scale travel with the spawn, so every peer builds the same one.
func spawn_species(enemy_id: String, at: Vector2, heading: float, health_scale: float = 1.0, damage_scale: float = 1.0, emerge: bool = false) -> Node2D:
	if not multiplayer.is_server():
		return null
	var enemy: Node2D
	if enemy_id == "void_crusher":
		var crusher: VoidCrusher = CRUSHER_SCENE.instantiate() as VoidCrusher
		crusher.health_scale = health_scale
		crusher.damage_scale = damage_scale
		crusher.emerge_on_spawn = emerge
		enemy = crusher
	elif enemy_id == "void_listener":
		var listener: VoidListener = LISTENER_SCENE.instantiate() as VoidListener
		listener.health_scale = health_scale
		listener.damage_scale = damage_scale
		listener.emerge_on_spawn = emerge
		enemy = listener
	elif enemy_id == "light_fisher":
		var fisher: LightFisher = FISHER_SCENE.instantiate() as LightFisher
		fisher.health_scale = health_scale
		fisher.damage_scale = damage_scale
		fisher.emerge_on_spawn = emerge
		enemy = fisher
	elif enemy_id == "quartz_golem":
		var golem_scene2: PackedScene = load(QUARTZ_GOLEM_PATH) as PackedScene
		var golem2: Node2D = golem_scene2.instantiate() as Node2D
		golem2.set("health_scale", health_scale)
		golem2.set("damage_scale", damage_scale)
		golem2.set("emerge_on_spawn", emerge)
		golem2.set("home_pos", at)
		enemy = golem2
	else:
		var spider: ShadowSpider = SPIDER_SCENE.instantiate() as ShadowSpider
		spider.enemy_id = enemy_id
		spider.health_scale = health_scale
		spider.damage_scale = damage_scale
		spider.emerge_on_spawn = emerge
		enemy = spider
	_enemy_count += 1
	enemy.name = "Enemy%d" % _enemy_count
	enemy.position = at
	enemy.set("heading", heading)
	_enemies.add_child(enemy)
	return enemy


func _clamp_spawn(pos: Vector2) -> Vector2:
	return pos.clamp(-ARENA_LIMIT, ARENA_LIMIT)


func _spawn_position(index: int) -> Vector2:
	return Vector2(16 * index, 0)


## Where a player comes back after dying.
func spawn_point() -> Vector2:
	return _spawn_position(0)


## Paints the meadow: plain grass with decorations from data/grass_tiles.json, laid out in zones
## (flower meadows in light areas, ferns, mushrooms and stones in shaded ones) so it looks grown.
func _fill_ground() -> void:
	var tiles: Dictionary = DataRegistry.table("grass_tiles")
	var zone := FastNoiseLite.new()
	zone.seed = 11
	zone.frequency = 0.035
	zone.fractal_octaves = 2
	var rng := RandomNumberGenerator.new()
	rng.seed = 1 ## fixed so every peer paints the same ground
	for y: int in range(GROUND_RECT.position.y, GROUND_RECT.end.y):
		for x: int in range(GROUND_RECT.position.x, GROUND_RECT.end.x):
			var density: float = zone.get_noise_2d(x, y) * 0.5 + 0.5
			var kind: String = _pick_tile_kind(density, rng)
			var options: Array = tiles.get(kind, tiles["plain"])
			var atlas: Array = options[rng.randi() % options.size()]
			_ground.set_cell(Vector2i(x, y), 0, Vector2i(int(atlas[0]), int(atlas[1])))
			if GLOW_KINDS.has(kind):
				_glow.set_cell(Vector2i(x, y), 0, Vector2i(int(atlas[0]), int(atlas[1])))
				_add_glow(Vector2i(x, y), kind, options.find(atlas))


## A light that glows at night where a luminous plant stands (same on every peer).
func _add_glow(cell: Vector2i, kind: String, variant: int, parent: Node = self) -> void:
	var spec: Array = GLOW_KINDS[kind]
	var light: NightLight = NightLight.new()
	light.glow_color = Color("5ff0dc") if kind == "mushroom" and variant == 2 else (spec[0] as Color)
	light.radius = int(spec[1])
	light.base_energy = float(spec[2])
	light.position = Vector2(cell) * 16.0 + Vector2(8.0, 9.0)
	light.add_to_group("flora_glow") ## the fireflies gather here
	parent.add_child(light)


func _pick_tile_kind(density: float, rng: RandomNumberGenerator) -> String:
	var lush: float = smoothstep(0.5, 0.78, density)
	var wild: float = smoothstep(0.5, 0.78, 1.0 - density)
	var roll: float = rng.randf()
	if roll < 0.065 + 0.26 * lush: ## flower meadows carry a few more blossoms than they used to (the second band moves up by the same amount)
		return LUSH_KINDS[rng.rand_weighted(LUSH_WEIGHTS)]
	if roll < 0.115 + 0.26 * lush + 0.14 * wild:
		if wild > 0.15 and rng.randf() < wild:
			return WILD_KINDS[rng.rand_weighted(WILD_WEIGHTS)]
		return COMMON_KINDS[rng.rand_weighted(COMMON_WEIGHTS)]
	return "plain"


func _spawn_player(id: int) -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	player.name = str(id)
	player.position = _spawn_position(_players.get_child_count())
	_players.add_child(player)
	if id != multiplayer.get_unique_id():
		var town: TownManager = get_tree().get_first_node_in_group("town") as TownManager
		if town != null and town.board != null:
			town.board.restore_guest(player)


func _despawn_player(id: int) -> void:
	var player: Node = _players.get_node_or_null(str(id))
	if player:
		player.queue_free()
