extends Node
## Automated verification of Ellie's 208-clip Foley footstep system:
## 13 surfaces x 4 gaits (sneak, walk, jog, sprint) x 4 variants, terrain.json mappings,
## non-repeating variant selection, shader-synced rain puddles, soaked boots, and mine cave puddles.

const SURFACES: Array[String] = [
	"grass", "steppe", "path", "slope", "stone", "mine_stone", "quartz",
	"sand", "wood", "bed", "mud", "shallow_water", "puddle",
]
const GAITS: Array[String] = ["sneak", "walk", "jog", "sprint"]

var _checks: int = 0
var _failures: int = 0


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FOOTSTEPS: " + message)


func _ready() -> void:
	_run.call_deferred()


func _active_players(comp: FootstepComponent) -> Array[AudioStreamPlayer2D]:
	var out: Array[AudioStreamPlayer2D] = []
	for child: Node in comp.get_children():
		if child is AudioStreamPlayer2D:
			out.append(child as AudioStreamPlayer2D)
	return out


func _clear_players(comp: FootstepComponent) -> void:
	for p: AudioStreamPlayer2D in _active_players(comp):
		p.stop()
		comp.remove_child(p)
		p.free()


func _run() -> void:
	# 1. All 208 WAV streams exist, load cleanly, and have crisp reasonable duration
	var loaded_count: int = 0
	for s: String in SURFACES:
		for g: String in GAITS:
			for v: int in range(1, FootstepComponent.STEP_VARIANTS + 1):
				var stream: AudioStream = FootstepComponent._step_stream(s, g, v)
				if stream != null and stream.get_length() > 0.15 and stream.get_length() < 0.65:
					loaded_count += 1
	_check(loaded_count == 208, "all 208 footstep WAVs load cleanly with valid lengths (got %d)" % loaded_count)

	# 2. Swim MP3s in assets/audio/steps/ remain intact
	_check(
		ResourceLoader.exists("res://assets/audio/steps/swim_dive_1.mp3")
		and ResourceLoader.exists("res://assets/audio/steps/swim_stroke_1.mp3")
		and ResourceLoader.exists("res://assets/audio/steps/swim_stroke_2.mp3"),
		"swim MP3 clips in assets/audio/steps/ preserved"
	)

	# 3. Every surface in data/terrain.json has valid gait streams & distinct desert/farm mappings
	var terrain_table: Dictionary = DataRegistry.table("terrain")
	_check(String((terrain_table.get("steppe", {}) as Dictionary).get("sound", "")) == "steppe", "steppe uses steppe sound")
	_check(String((terrain_table.get("sand", {}) as Dictionary).get("sound", "")) == "sand", "sand uses sand sound")
	_check(String((terrain_table.get("quartz", {}) as Dictionary).get("sound", "")) == "quartz", "quartz uses quartz sound")
	_check(String((terrain_table.get("field", {}) as Dictionary).get("sound", "")) == "bed", "field uses crumbly bed soil sound")
	_check(String((terrain_table.get("puddle", {}) as Dictionary).get("sound", "")) == "puddle", "puddle surface registered in terrain.json")
	for tid: String in terrain_table.keys():
		var entry: Dictionary = terrain_table[tid] as Dictionary
		var snd: String = String(entry.get("sound", ""))
		if not snd.is_empty():
			_check(FootstepComponent._step_stream(snd, "walk", 1) != null, "terrain '%s' resolves valid sound '%s'" % [tid, snd])

	# 4. Instantiate FootstepComponent and verify non-repeating variants & gait loudness progression
	var comp: FootstepComponent = FootstepComponent.new()
	var puff: CPUParticles2D = CPUParticles2D.new()
	puff.name = "Puff"
	puff.emitting = false
	puff.one_shot = true
	comp.add_child(puff)
	add_child(comp)
	comp.global_position = Vector2(2400.0, 2400.0)

	var prev_v: int = -1
	var repeat_found: bool = false
	for _i: int in 80:
		var nv: int = comp._next_variant("grass_walk")
		if nv == prev_v:
			repeat_found = true
		prev_v = nv
	_check(not repeat_found, "variant picker never plays the same clip twice in a row")

	var stone_data: Dictionary = Terrain.surface_data("stone")
	var gait_dbs: Array[float] = []
	# Dry check (force zero moisture/weather interference by testing inside room pocket space)
	comp.global_position = Vector2(Interiors.POCKET_X0 + 64.0, Interiors.POCKET_Y0 + 64.0)
	for g_idx: int in 4:
		_clear_players(comp)
		comp._left_foot = true # so step() flips to false every time for deterministic comparison
		var quiet: bool = g_idx == 0
		var gait_arg: int = maxi(g_idx - 1, 0)
		var spd: float = [38.0, 60.0, 88.0, 120.0][g_idx]
		comp.step(stone_data, Vector2(spd, 0.0), quiet, 0.0, gait_arg)
		var players: Array[AudioStreamPlayer2D] = _active_players(comp)
		_check(players.size() == 1, "dry indoor step spawns 1 AudioStreamPlayer2D for gait %d (got %d)" % [g_idx, players.size()])
		if not players.is_empty():
			var res_path: String = players[0].stream.resource_path
			_check(res_path.find("stone_" + GAITS[g_idx] + "_") != -1, "gait %d selects %s stream (%s)" % [g_idx, GAITS[g_idx], res_path])
			gait_dbs.append(players[0].volume_db)
	if gait_dbs.size() == 4:
		_check(
			gait_dbs[0] < gait_dbs[1] and gait_dbs[1] < gait_dbs[2] and gait_dbs[2] < gait_dbs[3],
			"in-engine dB rises monotonically sneak < walk < jog < sprint (%s)" % str(gait_dbs)
		)

	# 5. Soaked boots (`wet = 0.8`) add wet-sole puddle sheen on dry ground
	_clear_players(comp)
	comp._puddle_wet = 0.0
	comp.step(stone_data, Vector2(60.0, 0.0), false, 0.8, 0)
	_check(_active_players(comp).size() == 2, "soaked boots layer wet-sole slap over dry stone (got %d players)" % _active_players(comp).size())

	# 6. Outdoor shader-synced rain puddle detection (`BiomeBlend.puddle_at`)
	var puddle_spot: Vector2 = Vector2.INF
	for tx: int in range(120, 420):
		for ty: int in range(120, 420):
			var probe: Vector2 = Vector2(tx * 8.0, ty * 8.0)
			if BiomeBlend.puddle_at(probe, 0.85) > 0.35:
				puddle_spot = probe
				break
		if puddle_spot.is_finite():
			break
	_check(puddle_spot.is_finite(), "BiomeBlend.puddle_at finds standing rain puddles matching ground_tone.gdshader")

	# 7. Mine cave puddle detection (`puddle_a` / `puddle_b` -> "puddle")
	var mines: MineManager = MineManager.new()
	mines.setup(42)
	add_child(mines)
	var mine_puddle_pos: Vector2 = Vector2.INF
	for lvl: int in range(1, 6):
		var layout: MineLayout = mines.layout(lvl)
		for cell_key: Variant in layout.chunk_props.keys():
			for prop: Dictionary in layout.chunk_props[cell_key] as Array:
				var k: String = String(prop.get("kind", ""))
				if k == "puddle_a" or k == "puddle_b":
					mine_puddle_pos = MineManager.origin(lvl) + Vector2(float(prop.x), float(prop.y))
					break
			if mine_puddle_pos.is_finite():
				break
		if mine_puddle_pos.is_finite():
			break
	if mine_puddle_pos.is_finite():
		_check(mines.surface_at(mine_puddle_pos) == "puddle", "MineManager.surface_at returns 'puddle' on cave puddles")
		_check(mines.surface_at(MineManager.origin(1) + layout_floor_away(mines.layout(1), mine_puddle_pos - MineManager.origin(1))) == "mine_stone", "MineManager.surface_at returns 'mine_stone' on dry cave floor")

	_clear_players(comp)
	mines.queue_free()
	comp.queue_free()

	if _failures == 0:
		print("PASS test_footsteps (%d checks)" % _checks)
		get_tree().quit(0)
	else:
		printerr("FAIL test_footsteps (%d/%d failed)" % [_failures, _checks])
		get_tree().quit(1)


func layout_floor_away(layout: MineLayout, avoid: Vector2) -> Vector2:
	var center: Vector2 = layout.tile_center(layout.entry)
	if center.distance_to(avoid) > 36.0:
		return center
	return layout.tile_center(layout.exit)
