extends Node
## The sword's heavy blow (right mouse button): pure rules, charge / release / cancel / interrupt with a real player, stamina,
## damage tiers, noise, the crusher's front armour pierced. Offline, no saves, no game socket.
## Run: Godot --headless --path . --fixed-fps 60 tools/test_heavy.tscn
const ARENA: PackedScene = preload("res://src/world/test_level.tscn")

class EmptyArena:
	extends TestLevel
	func _spawn_player(_id: int) -> void:
		pass
	func _fill_ground() -> void:
		pass

var _checks: int = 0
var _failed: int = 0
var _arena: TestLevel
var _player: Player
var _struck: Array[float] = []


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		push_error("FAILED: " + message)


func _wait(seconds: float) -> void:
	for _i: int in ceili(seconds * 60.0): ## frames, not timers: the fixed-fps run counts game time per frame
		await get_tree().process_frame


func _run() -> void:
	_test_rules()
	await _test_player()
	await _test_crusher()
	print("HEAVY TESTS: %d checks, %d failures" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_rules() -> void:
	for id: String in ["sword_basic", "sword_iron", "sword_void"]:
		var def: Dictionary = DataRegistry.get_entry("items", id)
		_check(HeavyRules.has_secondary(def), "%s has the heavy blow" % id)
	for id: String in ["axe_basic", "pickaxe_basic", "sickle_basic", "rod_basic"]:
		_check(not HeavyRules.has_secondary(DataRegistry.get_entry("items", id)), "%s has no right-click attack yet" % id)
	var def: Dictionary = DataRegistry.get_entry("items", "sword_basic")
	var cfg: Dictionary = HeavyRules.config(def)
	_check(HeavyRules.stamina_cost(cfg) == 20.0, "the blow costs 20 stamina")
	_check(not HeavyRules.is_ready(cfg, 0.2) and HeavyRules.is_ready(cfg, 0.36), "ready only after the minimum charge")
	_check(HeavyRules.is_ready(cfg, 0.21, true) and not HeavyRules.is_ready(cfg, 0.1, true), "after a light hit the minimum is shorter")
	_check(HeavyRules.power(cfg, 0.2) == 0.0 and is_equal_approx(HeavyRules.power(cfg, 1.0), 1.0) and is_equal_approx(HeavyRules.power(cfg, 5.0), 1.0), "power runs 0..1 and stops at full")
	var last: float = -1.0
	for i: int in 21:
		var p: float = HeavyRules.power(cfg, 0.35 + 0.65 * float(i) / 20.0)
		_check(p >= last, "power never falls while charging")
		last = p
	var weak: Dictionary = HeavyRules.step(cfg, def, 0.36)
	var strong: Dictionary = HeavyRules.step(cfg, def, 1.0)
	_check(float(strong["damage"]) > float(weak["damage"]) and float(weak["damage"]) >= 2.0, "a full charge hits harder, even the weakest beats two light hits")
	_check(float(strong["knock"]) > float(weak["knock"]) and float(strong["lunge"]) > float(weak["lunge"]) and bool(strong["heavy"]), "knock-back and lunge grow with the charge")
	_check(HeavyRules.overcharge(cfg, 1.4) > 0.39 and not HeavyRules.must_release(cfg, 1.5) and HeavyRules.must_release(cfg, 2.1), "she lets go by herself after holding at full strength")
	_check(is_equal_approx(HeavyRules.host_charge(5.0, 0.5, cfg), 0.65) and is_equal_approx(HeavyRules.host_charge(0.3, 2.0, cfg), 0.3), "the host does not believe a longer charge than it saw")
	_check(HeavyRules.charge_key(cfg, 0.0) == 0.0 and HeavyRules.charge_key(cfg, 0.25) >= 2.0 and HeavyRules.charge_key(cfg, 1.0) <= 3.0 + 0.001, "the body key runs 0..3 while charging")
	_check(not HeavyRules.can_start(cfg, 19.0) and HeavyRules.can_start(cfg, 20.0), "she needs the stamina to start")


func _test_player() -> void:
	_player = load("res://src/entities/player/player.tscn").instantiate() as Player
	_player.name = "1"
	add_child(_player)
	await get_tree().process_frame
	var attack: AttackComponent = _player.attack
	attack.held_weapon = "sword_basic"
	attack.heavy_struck.connect(func(power: float) -> void: _struck.append(power))
	_check(attack.noise_scale() == 1.0 and attack.heavy_key() < 0.0, "idle: normal noise, no heavy key")
	_player.stamina.refill()
	# the real button: a tap is dropped for free
	Input.action_press("action_secondary")
	await _wait(0.1)
	_check(attack.is_charging() and not attack.can_attack() and _player.is_busy(), "the right button starts a charge, which blocks light swings and marks her busy")
	_check(attack.charge_draw() > 0.2 and not attack.charge_ready() and attack.heavy_key() > 0.0, "the draw shows before the blow is ready")
	Input.action_release("action_secondary")
	await _wait(0.1)
	_check(not attack.is_charging() and not attack.is_swinging() and _struck.is_empty(), "a tap is dropped, not struck")
	_check(is_equal_approx(_player.stamina.current, _player.stamina.max_stamina), "a dropped charge costs nothing")
	# a full strike, walking slowly while charging
	Input.action_press("action_secondary")
	Input.action_press("move_right")
	await _wait(0.7)
	_check(attack.is_charging() and _player.velocity.length() > 5.0 and _player.velocity.length() <= _player.max_speed * 0.4 + 1.0, "she walks slowly while charging (%.1f px/s)" % _player.velocity.length())
	_check(not _player.sprinting and not _player.stealth.sneaking, "no sprint or sneak while charging")
	Input.action_release("move_right")
	await _wait(0.5)
	_check(attack.charge_ready() and attack.charge_amount() > 0.95, "over a second of holding is a full charge")
	var before: float = _player.stamina.current
	Input.action_release("action_secondary")
	await _wait(0.04)
	_check(attack.is_heavy_swing() and attack.noise_scale() > 1.2, "letting go strikes: a heavy swing, louder")
	_check(is_equal_approx(before - _player.stamina.current, 20.0), "the blow costs 20 stamina (%.1f)" % (before - _player.stamina.current))
	_check(_struck.size() == 1 and _struck[0] > 0.95, "heavy_struck reports the power")
	_check(attack.heavy_key() >= 2.9 and attack.heavy_key() <= 9.0, "the body keys run on from the charge through the strike")
	await get_tree().process_frame
	_check(_player._sheet == 11, "the heavy sheet is shown")
	await _wait(1.3)
	_check(not attack.is_swinging() and attack.heavy_key() < 0.0, "she recovers and the key resets")
	# holding too long lets go by herself
	_player.stamina.refill()
	Input.action_press("action_secondary")
	await _wait(2.6)
	_check(not attack.is_charging() and _struck.size() == 2, "after holding at full strength she lets go by herself")
	Input.action_release("action_secondary")
	await _wait(1.3)
	# direct API checks (her own physics is off, so nothing reads the button)
	_player.set_physics_process(false)
	_player.stamina.refill()
	# a menu takes the input: the charge drops, nothing is paid
	attack.begin_charge(Vector2.RIGHT)
	await _wait(0.5)
	var struck_before: int = _struck.size()
	attack.charge_input(false, true, Vector2.RIGHT, 0.016)
	_check(not attack.is_charging() and _struck.size() == struck_before and is_equal_approx(_player.stamina.current, _player.stamina.max_stamina), "a menu taking the mouse drops the charge for free")
	# a hit breaks the charge and costs a little
	attack.begin_charge(Vector2.RIGHT)
	await _wait(0.5)
	var spent_from: float = _player.stamina.current
	attack.interrupt_charge()
	_check(not attack.is_charging() and is_equal_approx(spent_from - _player.stamina.current, 10.0), "a hit breaks the charge for 10 stamina")
	# no stamina, no charge
	_player.stamina.spend(_player.stamina.current - 5.0)
	attack.begin_charge(Vector2.RIGHT)
	_check(not attack.is_charging(), "she cannot start a charge with too little stamina")
	_player.stamina.refill()
	# a weapon without a secondary does nothing
	attack.held_weapon = "axe_basic"
	attack.begin_charge(Vector2.RIGHT)
	_check(not attack.is_charging(), "an axe has no heavy blow")
	attack.held_weapon = "sword_basic"
	_player.queue_free()
	await get_tree().process_frame


func _test_crusher() -> void:
	Terrain.relief = null
	_arena = ARENA.instantiate() as TestLevel
	_arena.set_script(EmptyArena)
	add_child(_arena)
	_player = load("res://src/entities/player/player.tscn").instantiate() as Player
	_player.name = "1"
	_arena.get_node("Players").add_child(_player)
	_player.set_physics_process(false)
	_player.attack.held_weapon = "sword_basic"
	_player.global_position = Vector2(-300, 150)
	var crusher: VoidCrusher = _arena._spawn_crusher(Vector2(-270, 150))
	crusher.set_physics_process(false)
	crusher.set_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	# its front faces her: a light swing is reduced hard, the heavy blow only by half
	var loss_light: float = await _loss(crusher, false)
	var loss_heavy: float = await _loss(crusher, true)
	print("crusher front: light %.1f, heavy %.1f" % [loss_light, loss_heavy])
	_check(loss_light > 0.0, "the light swing reached the crusher")
	_check(loss_heavy > loss_light * 3.0, "the heavy blow pierces the front armour (light %.1f, heavy %.1f)" % [loss_light, loss_heavy])
	_arena.queue_free()


## Health the crusher loses to one blow from the player standing west of it (its front faces her).
func _loss(crusher: VoidCrusher, heavy: bool) -> float:
	crusher.heading = PI
	crusher._health.current = crusher._health.max_health
	crusher._set_state(VoidCrusher.State.IDLE)
	crusher._flinch_cd = 0.0
	crusher._health.invulnerable_seconds = 0.0
	var start: float = crusher._health.current
	var attack: AttackComponent = _player.attack
	_player.stamina.refill()
	if heavy:
		attack.begin_charge(Vector2.RIGHT)
		await _wait(1.1)
		attack.release_charge(Vector2.RIGHT)
	else:
		attack.attack(Vector2.RIGHT)
	await _wait(1.3)
	return start - crusher._health.current
