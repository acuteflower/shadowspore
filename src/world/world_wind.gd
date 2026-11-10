class_name WorldWind
extends Node2D
## One paused/game-time clock for foliage and world-anchored airborne details.
## Contacts update sparse chunk fields, never one physics object per blade.
static var current: WorldWind
var clock: float = 0.0
var direction: Vector2 = Vector2.RIGHT
var gust: float = 0.0
var _world: Variant ## dynamic to avoid the WorldLevel -> HUD/interior preload cycle
var _previous: Dictionary = {}
var _tick: float = 0.0
var _air_timer: float = 2.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _air: Array[Dictionary] = []
var _config: Dictionary
var _rustle: AudioStreamPlayer2D
var _rustle_wait: float = 0.0

func setup(world: Variant) -> void:
	_world = world
	_config = DataRegistry.table("wind")
	_rng.seed = world._map.world_seed + 4187

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	current = self
	z_index = 3
	_rustle = AudioStreamPlayer2D.new()
	_rustle.stream = preload("res://assets/audio/hut/rustle.wav")
	_rustle.max_distance = 130.0
	_rustle.volume_db = -28.0
	add_child(_rustle)

func _exit_tree() -> void:
	if current == self: current = null

static func sample(at: Vector2) -> Vector2:
	if not is_instance_valid(current): return Vector2.ZERO
	var pulse: float = 0.5 + 0.5 * sin(at.dot(current.direction)*0.014-current.clock*1.6)
	return current.direction * (0.12 + current.gust * (0.35+0.65*pulse))

func exposure(at: Vector2) -> float:
	var biome: String = _world._land_biome(Vector2i(floori(at.x/16.0),floori(at.y/16.0)))
	return float((_config.get("exposure",{}) as Dictionary).get(biome,1.0))

func _process(delta: float) -> void:
	clock += delta
	direction = Vector2.from_angle(0.24+sin(clock*0.025)*0.65+sin(clock*0.061)*0.18)
	gust = 0.15+0.85*pow(maxf(0.0,sin(clock*0.23+0.6)),3.0)
	RenderingServer.global_shader_parameter_set("g_wind_dir",direction) ## the same wind for the shaders of the small plants (flora_wind)
	RenderingServer.global_shader_parameter_set("g_wind_gust",gust)
	RenderingServer.global_shader_parameter_set("g_wind_clock",clock)
	_tick += delta
	_rustle_wait = maxf(0.0,_rustle_wait-delta)
	if _tick >= float(_config.get("contact_tick",0.08)):
		_contacts(_tick)
		_tick = 0.0
	var had_air: bool = not _air.is_empty()
	_advance_air(delta)
	# Only redraw while air particles exist (one more time when the last one goes, to clear it).
	if had_air or not _air.is_empty(): queue_redraw()

func _contacts(delta: float) -> void:
	var seen: Dictionary = {}
	var actors: Array[Node] = []
	actors.append_array(Player.all)
	actors.append_array(get_tree().get_nodes_in_group("predators"))
	actors.append_array(get_tree().get_nodes_in_group("wildlife"))
	actors.append_array(get_tree().get_nodes_in_group("woodland_mammals"))
	var details: Array[Node] = get_tree().get_nodes_in_group("meadow_details")
	for actor: Node in actors:
		var body: Node2D = actor as Node2D
		if body == null: continue
		var id: int = body.get_instance_id()
		seen[id] = true
		var pos: Vector2 = body.global_position
		var before: Vector2 = _previous.get(id,pos)
		_previous[id] = pos
		var distance: float = before.distance_to(pos)
		# Teleports / room changes do not mow the land between destinations.
		if distance < 0.8 or distance > 96.0: continue
		var speed: float = distance/maxf(delta,0.01)
		var force: float = clampf(speed/100.0,0.20,1.4)
		if not body is Player: force *= 0.65
		var touched: bool = false
		for node: MeadowDetails in details:
			if node.stamp_segment(before,pos,force): touched = true
		var player: Player = body as Player
		if touched and player != null and player.is_multiplayer_authority() and _rustle_wait <= 0.0 and not InputManager.ui_blocking and not player.story_lock:
			_rustle_wait = 0.50 if player.stealth.sneaking else 0.32
			_rustle.position = pos
			_rustle.volume_db = -34.0 if player.stealth.sneaking else -28.0
			_rustle.pitch_scale = _rng.randf_range(0.85,1.15)
			if not _rustle.playing: _rustle.play()
			if speed > 135.0: _release_seed(pos)
	for id: int in _previous.keys():
		if not seen.has(id): _previous.erase(id)
	for node: MeadowDetails in details: node.advance_contacts(delta)

func _viewer() -> Player:
	for player: Player in Player.all:
		if player.is_multiplayer_authority(): return player
	return null

func _air_allowed(player: Player) -> bool:
	return player != null and not player.story_lock and not InputManager.ui_blocking and not InputManager.map_open and _world.navigation_floor(player.global_position)

func _release_seed(pos: Vector2) -> void:
	if _air.size() >= int(_config.get("air_budget",8)): return
	_air.append({"pos":pos-Vector2(0,7),"age":0.0,"life":_rng.randf_range(2.3,4.0),"kind":1,"phase":_rng.randf()*TAU,"origin":pos})

func _advance_air(delta: float) -> void:
	var viewer: Player = _viewer()
	for i: int in range(_air.size()-1,-1,-1):
		var particle: Dictionary = _air[i]
		particle.age = float(particle.age)+delta
		if float(particle.age) >= float(particle.life) or viewer == null or (particle.pos as Vector2).distance_to(viewer.global_position)>450.0:
			_air.remove_at(i)
			continue
		var vel: Vector2 = sample(particle.pos as Vector2)* (40.0 if int(particle.kind)==3 else 20.0)
		vel.y += sin(clock*1.6+float(particle.phase))*3.0-1.0
		if int(particle.kind) >= 4: ## the Hexenwald: a dead leaf tumbles down from the crowns, ash sinks slowly, both rock from side to side
			var leaf: bool = int(particle.kind) == 4
			vel = sample(particle.pos as Vector2) * (8.0 if leaf else 12.0) + Vector2(sin(clock * (2.2 if leaf else 1.1) + float(particle.phase)) * (9.0 if leaf else 4.0), 8.0 if leaf else 3.5)
		particle.pos = (particle.pos as Vector2)+vel*delta
	_air_timer -= delta
	if _air_timer > 0.0: return
	var gap: Array = _config.get("air_spawn_gap",[1.8,4.6])
	_air_timer = _rng.randf_range(float(gap[0]),float(gap[1]))
	if not _air_allowed(viewer) or _air.size() >= int(_config.get("air_budget",8)): return
	# Ambient particles originate at real foliage in visible chunks, not screen edges.
	var source: Vector2 = Vector2.INF
	var plant_kind: int = 0
	var chunks: Array[Node] = get_tree().get_nodes_in_group("meadow_details")
	for attempt: int in 8:
		if chunks.is_empty(): break
		var detail: MeadowDetails = chunks[_rng.randi_range(0,chunks.size()-1)] as MeadowDetails
		if detail.sources.is_empty(): continue
		var index: int = _rng.randi_range(0,detail.sources.size()-1)
		var candidate: Vector2 = detail.sources[index]
		if candidate.distance_to(viewer.global_position) < 180.0:
			source = candidate
			plant_kind = detail.source_kinds[index]
			break
	if not source.is_finite(): return
	if plant_kind >= MeadowDetails.MEADOW_COUNT or BiomeBlend.amount_at(source) > 0.5: ## the Hexenwald's air: dead leaves from the crowns, now and then ash
		var leaf: bool = _rng.randf() < 0.7
		_air.append({"pos":source-Vector2(_rng.randf_range(-12,12),_rng.randf_range(38,80)) if leaf else source-Vector2(0,_rng.randf_range(20,40)),"origin":source,"age":0.0,"life":_rng.randf_range(5.0,8.0),"kind":4 if leaf else 5,"phase":_rng.randf()*TAU,"petal_tint":[Color("5a2430"),Color("8e3a3a"),Color("6a4e42"),Color("927460")][_rng.randi_range(0,3)]})
		return
	var kind: int = 0
	if plant_kind < 4 or plant_kind in [12,13,14,22,23]: kind = 1
	elif plant_kind in [4,5,6,7,8,15,16,17]: kind = 2
	# Short, faint air traces are restricted to calm exploration, never active combat.
	if gust > 0.75 and _rng.randf() < 0.25 and _safe_for_trace(viewer): kind = 3
	_air.append({"pos":source-Vector2(0,10),"origin":source,"age":0.0,"life":0.4 if kind==3 else _rng.randf_range(3.0,6.0),"kind":kind,"phase":_rng.randf()*TAU,"petal_tint":[Color("d8d4ab"),Color("ad9ccc"),Color("c99bab")][plant_kind%3]})

func _safe_for_trace(player: Player) -> bool:
	for node: Node in get_tree().get_nodes_in_group("predators"):
		if (node as Node2D).global_position.distance_to(player.global_position)<180.0: return false
	return true

func _draw() -> void:
	var viewer: Player = _viewer()
	if not _air_allowed(viewer): return
	for particle: Dictionary in _air:
		var life: float = float(particle.life)
		var age: float = float(particle.age)
		var alpha: float = minf(age*3.0,(life-age)*2.0)
		var at: Vector2 = to_local(particle.pos as Vector2).round()
		var kind: int = int(particle.kind)
		if kind == 3:
			if not _safe_for_trace(viewer): continue
			for i: int in 9:
				if i%4==0: continue
				var p: Vector2 = at-direction*float(i)*1.6+Vector2(0,sin(i*0.35)*2.0)
				draw_rect(Rect2(p.round(),Vector2.ONE),Color(0.78,0.84,0.76,0.09*alpha))
		elif kind == 4: ## a tumbling leaf: flat, then on edge, then flat again
			var leaf_color: Color = particle.get("petal_tint",Color("6a4e42")) as Color
			leaf_color.a = alpha*0.85
			var flat: bool = sin(clock*4.0+float(particle.phase)) > -0.3
			draw_rect(Rect2(at,Vector2(2,1) if flat else Vector2(1,1)),leaf_color)
			if flat: draw_rect(Rect2(at+Vector2(0,-1),Vector2.ONE),Color(leaf_color.lightened(0.2),alpha*0.6))
		elif kind == 5: ## ash: a grey flake, once in a while a violet ember in it
			var ember: bool = sin(clock*1.3+float(particle.phase)*5.0) > 0.92
			draw_rect(Rect2(at,Vector2.ONE),Color(Color("c690ec") if ember else Color("8a8698"),alpha*(0.9 if ember else 0.55)))
		else:
			var color: Color = [Color("8aa772"),Color("bfbc92"),Color("bc9daf")][kind]
			if kind == 2: color = particle.get("petal_tint",color) as Color
			color.a = alpha*0.65
			draw_rect(Rect2(at,Vector2(2 if kind==0 else 1,1)),color)
			if kind==0 and sin(clock*3.0+float(particle.phase))>0.0:
				draw_rect(Rect2(at+Vector2(1,-1),Vector2.ONE),Color(color,alpha*0.4))
