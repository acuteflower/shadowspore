extends Node
## Tests the elevation occlusion and south-plateau shadow.

const WORLD: PackedScene = preload("res://src/world/world_level.tscn")
const TEST_SPOT: Vector2 = Vector2(6608, 9325) # standing right at the edge of the level 1 ridge

class EmptyWorld extends WorldLevel:
	func _spawn_player(_id: int) -> void:
		pass

var _failures: int = 0
var _checks: int = 0

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error("FAIL: " + label)
	else:
		print("PASS: " + label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	Jobs.threaded = false
	if DisplayServer.get_name() == "headless":
		for action: StringName in InputMap.get_actions():
			for event: InputEvent in InputMap.action_get_events(action):
				if event is InputEventKey and (event as InputEventKey).keycode == KEY_NONE:
					(event as InputEventKey).keycode = (event as InputEventKey).physical_keycode
	var world: WorldLevel = WORLD.instantiate() as WorldLevel
	world.set_script(EmptyWorld)
	world.opening_over = true
	add_child(world)
	world.set_process(false)
	world.night.process_mode = Node.PROCESS_MODE_DISABLED
	if world.has_node("Wildlife"):
		world.get_node("Wildlife").process_mode = Node.PROCESS_MODE_DISABLED
	
	var center_chunk: Vector2i = Vector2i((TEST_SPOT / 512.0).floor())
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c: Vector2i = center_chunk + Vector2i(dx, dy)
			if not world._chunks.has(c):
				world._load_chunk(c)
	
	var relief: Relief = Terrain.relief
	_check(relief != null, "Relief is loaded")
	
	var player: Player = TestLevel.PLAYER_SCENE.instantiate() as Player
	player.name = "1"
	player.position = TEST_SPOT
	world.get_node("Players").add_child(player)
	player.health.heal_full()
	player.facing = Vector2.DOWN
	
	await get_tree().physics_frame
	await get_tree().process_frame
	
	var low: float = relief.level_at(TEST_SPOT)
	_check(is_equal_approx(low, 0.0), "Player starts at level 0 (north of elevation)")
	
	var south_lvl: float = relief.level_at(TEST_SPOT + Vector2(0, 20))
	_check(is_equal_approx(south_lvl, 1.0), "South of player is elevated to level 1")
	
	# Check ReliefLayer overhang exists
	var cliffs: ReliefLayer = world._cliffs
	_check(cliffs != null, "Cliffs layer exists")
	var overhang: ColorRect = cliffs.get_node_or_null("ReliefOverhang") as ColorRect
	_check(overhang != null, "ReliefOverhang node exists")
	_check(overhang.z_index == 1, "ReliefOverhang renders above player (z_index = 1)")
	
	# Learn WallClimb and check interaction
	player.progress.xp = Levels.xp_at(2)
	var skills: SkillTreeComponent = player.get_node("SkillTreeComponent") as SkillTreeComponent
	skills.request_learn(WallClimb.SKILL)
	await get_tree().physics_frame
	var climb: WallClimb = player.climb
	
	print("climb._available: ", climb._available())
	var landing: Vector2 = climb._landing(Vector2.DOWN)
	print("landing: ", landing)
	var can_climb: bool = climb.offer(Vector2.DOWN, false)
	_check(can_climb, "WallClimb offers prompt towards southern elevation")
	
	print("ELEVATION TEST: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures else 0)
