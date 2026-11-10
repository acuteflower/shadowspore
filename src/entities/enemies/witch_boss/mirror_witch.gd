class_name MirrorWitch
extends Node2D
## Morwenna, die Spiegelhexe (`boss_morwenna`, docs/enemies/boss_mora.md): the second boss, in the Schieferkessel under the Rabenbaum.
## This node is the shell of the real witch: health, hurtbox, loot, the boss bar and the entrance screen, the ties to the tree and the level. It does
## not decide anything itself: its child `MirrorWitchFight` (on every peer) moves the real body (index 0, the child `Body`, at this node's place) and
## the up to two glitch clones, and asks the handles below. Spawned by `WitchArena` through the level's enemy spawner; the spawn properties
## (`enemy_id`, `health_scale`, `damage_scale`) replicate, everything else follows from the data, the baked hollow and the tree.

signal touched_down ## she has hit the ground after the fall out of the crown (the boss bar and the entrance screen wait for it)
signal reset_requested ## host: nobody is left in the hollow; the arena removes her and opens the gates
signal defeated ## every peer: she is released (died)

const TITLE: String = "MORWENNA"
const HURTBOX_LAYER: int = 1 << 4
const HEAL_STEP: float = 0.5 ## host: the leech's healing is paid out in steps (one floating number, one message) instead of every frame

var enemy_id: String = "boss_morwenna"
var health_scale: float = 1.0
var damage_scale: float = 1.0
var emerge_on_spawn: bool = false ## the shared spawn contract (unused: she falls out of the tree)
var body: WitchBody
var field: FeatherField
var fx: WitchFx
var fight: MirrorWitchFight
var tree: CrowTree
var act_hittable: bool = false
var armour: float = 1.0 ## every blow is multiplied by this (`MirrorWitchHurtbox`): braced she is harder, tired softer
var _def: Dictionary = {}
var _arena: Dictionary = {}
var _baked: Dictionary = {}
var _spawn_at: Vector2 = Vector2.ZERO
var _real_visible: bool = true
var _hittable: bool = true
var _landed: bool = false
var _bar_shown: bool = false
var _intro: BossIntro
var _heal_store: float = 0.0
var _heal_clock: float = 0.0
var _reset_asked: bool = false

@onready var _health: HealthComponent = $HealthComponent
@onready var _hurtbox: HurtboxComponent = $Hurtbox
@onready var _voice: AudioStreamPlayer2D = $Voice


func _ready() -> void:
	add_to_group("predators")
	add_to_group("bosses")
	_def = EnemyScaling.scaled(DataRegistry.get_entry("enemies", enemy_id), health_scale, damage_scale)
	_arena = DataRegistry.table("witch_arena")
	_baked = DataRegistry.table("witch_arena_baked")
	_health.max_health = float(_def["max_health"])
	_health.current = _health.max_health
	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_died)
	_spawn_at = global_position
	tree = get_tree().get_first_node_in_group("crow_tree") as CrowTree
	body = WitchBody.new()
	body.name = "Body"
	add_child(body)
	var zone: Dictionary = _baked.get("zone", {}) as Dictionary
	field = FeatherField.new()
	field.name = "Field"
	add_child(field)
	field.setup({"mask": String(zone.get("mask", "")), "x": float(zone.get("x", 0.0)), "y": float(zone.get("y", 0.0))}, multiplayer.is_server())
	field.damage_scale = damage_scale
	fx = WitchFx.new()
	fx.name = "Fx"
	add_child(fx)
	fx.setup(field, multiplayer.is_server())
	fx.damage_scale = damage_scale
	fight = MirrorWitchFight.new()
	fight.name = "Fight"
	add_child(fight)
	touched_down.connect(_on_touched_down)
	fight.setup(self)
	_set_hittable(false)
	if multiplayer.is_server():
		_start_intro(0.0)
	else:
		fight.request_sync()
		_ask_entrance.rpc_id(1)


func _process(_delta: float) -> void:
	_update_bar()


func _physics_process(delta: float) -> void:
	_set_hittable(act_hittable and _real_visible and _health.current > 0.0)
	if not multiplayer.is_server() or _heal_store <= 0.0:
		return
	_heal_clock += delta
	if _heal_clock >= HEAL_STEP:
		_heal_clock = 0.0
		_health.heal(_heal_store)
		_heal_store = 0.0


# --- entrance and boss bar -----------------------------------------------------------------------------------------


## A peer that comes in while she is still falling sees the entrance screen too (skipping what has passed).
@rpc("any_peer", "call_remote", "reliable")
func _ask_entrance() -> void:
	if multiplayer.is_server() and fight != null and fight.mode == MirrorWitchFight.Mode.ENTRANCE and not _landed:
		_rpc_entrance.rpc_id(multiplayer.get_remote_sender_id(), fight.elapsed())


@rpc("authority", "call_remote", "reliable")
func _rpc_entrance(elapsed: float) -> void:
	_start_intro(elapsed)


func _start_intro(skip: float) -> void:
	if _intro != null or DisplayServer.get_name() == "headless":
		return
	var shown: Dictionary = _def.get("intro", {}) as Dictionary
	if shown.is_empty():
		return
	for player: Player in Player.all:
		if player.is_multiplayer_authority() and player.health.current > 0.0 and player.global_position.distance_to(centre()) < float(shown.get("range", 700.0)):
			_intro = BossIntro.play(self, player, String(shown["name"]), String(shown["epithet"]), skip)
			_intro.finished.connect(func() -> void: _intro = null)
			return


func _on_touched_down() -> void:
	_landed = true
	var entrance: Dictionary = (_def.get("fight", {}) as Dictionary).get("entrance", {}) as Dictionary
	say(String(entrance.get("line", ""))) ## "Nein... rührt das Holz nicht an!"


func _update_bar() -> void:
	var near: bool = false
	var range_px: float = float(_def.get("bar_range", 360.0)) * (1.25 if _bar_shown else 1.0)
	if _health.current > 0.0 and _landed and _intro == null:
		for player: Player in Player.all:
			if player.is_multiplayer_authority() and player.health.current > 0.0 and player.global_position.distance_to(centre()) < range_px:
				near = true
				break
	if near and not _bar_shown:
		_bar_shown = true
		get_tree().call_group("boss_bar", "track", TITLE, _health)
	elif not near and _bar_shown:
		_bar_shown = false
		if _health.current > 0.0:
			get_tree().call_group("boss_bar", "release")


## For the entrance screen: where she will stand, and her eyes.
func landing_spot() -> Vector2:
	return _spawn_at + Vector2(0, -34)


func eye_position() -> Vector2:
	return global_position + Vector2(0, -roundf(body.height) - 40.0) if body != null else global_position


func intro_running() -> bool:
	return _intro != null


# --- hits and death ------------------------------------------------------------------------------------------------


func _set_hittable(on: bool) -> void:
	if on == _hittable:
		return
	_hittable = on
	_hurtbox.set_deferred("collision_layer", HURTBOX_LAYER if on else 0)


func _on_damaged(amount: float, from: Vector2, knockback: float) -> void:
	var away: Vector2 = (global_position - from).normalized()
	DamageNumber.spawn(get_tree().current_scene, global_position + Vector2(0, -roundf(body.height) - 56.0), amount, away)
	body.hit_flash()
	body.glitch(0.8, 0.08)
	if multiplayer.is_server() and _health.current > 0.0:
		fight.on_damaged(amount, knockback)


func _on_died() -> void:
	_set_hittable(false)
	fight.on_died()
	defeated.emit()


# --- the fight's handles -------------------------------------------------------------------------------------------


func def_value(key: String) -> Variant:
	return _def.get(key)


## The middle of the hollow: the tree (the mood overlay and the boss bar measure from here).
func centre() -> Vector2:
	return tree_position()


func leash() -> float:
	return float(_arena.get("leash", 520.0))


func reset_seconds() -> float:
	return float(_arena.get("reset_seconds", 8.0))


func max_health() -> float:
	return _health.max_health


func health_now() -> float:
	return _health.current


func health_floor() -> float:
	return _health.floor_value


func set_floor(value: float) -> void:
	_health.floor_value = value


func host_set_health_fraction(fraction: float) -> void:
	if multiplayer.is_server():
		_health.set_health(_health.max_health * fraction)


## Host: the leech drinks (paid out every `HEAL_STEP`).
func host_heal(amount: float) -> void:
	if multiplayer.is_server() and _health.current > 0.0:
		_heal_store += amount


func set_combat(hittable: bool, factor: float) -> void:
	act_hittable = hittable
	armour = factor


## Gone into smoke, under the earth, faded: no blow can find her.
func set_real_visible(on: bool) -> void:
	_real_visible = on


func request_reset() -> void:
	if multiplayer.is_server() and not _reset_asked:
		_reset_asked = true
		reset_requested.emit()


func say(line: String) -> void:
	if line.is_empty() or not is_inside_tree():
		return
	for player: Player in Player.all:
		if player.is_multiplayer_authority() and player.global_position.distance_to(centre()) < 700.0:
			var box: Node = get_tree().get_first_node_in_group("speech_box")
			if box != null:
				box.call("speak", "MORWENNA", line, 3.2)
			return


func shake_near(point: Vector2, amount: float) -> void:
	var radius: float = float(_def.get("shake_radius", 240.0))
	for player: Player in Player.all:
		if player.is_multiplayer_authority():
			player.add_shake(amount * (1.0 - smoothstep(30.0, radius, player.global_position.distance_to(point))))


func tree_position() -> Vector2:
	if is_instance_valid(tree):
		return tree.global_position
	var tile: Array = _arena.get("tile", [0, 0]) as Array
	return Vector2(float(tile[0]), float(tile[1])) * 16.0 + Vector2(8, 8)


func tap_point() -> Vector2:
	return tree.tap_point() if is_instance_valid(tree) else tree_position() + Vector2(2, 20)


func crown_height() -> float:
	return tree.crown_height() if is_instance_valid(tree) else 168.0


func tree_drain(value: float) -> void:
	if is_instance_valid(tree):
		tree.drain = value


func tree_hour(value: float) -> void:
	if is_instance_valid(tree):
		tree.set_hour(value)


## She is released: the tree breathes again (every peer; the arena saves it on the host).
func tree_free() -> void:
	if is_instance_valid(tree):
		tree.set_liberated(true)
	get_tree().call_group("witch_arena", "on_released")


func _exit_tree() -> void:
	if _bar_shown and is_inside_tree() and _health != null and _health.current > 0.0:
		get_tree().call_group("boss_bar", "release")
	if is_instance_valid(_voice):
		_voice.stop()
