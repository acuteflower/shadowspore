class_name Player
extends CharacterBody2D
## Owned by the peer whose id is the node name. The owner simulates movement
## and the MultiplayerSynchronizer pushes position, velocity and facing to everyone else.
## Looks toward the mouse cursor when in combat or aiming, otherwise toward the walking direction.

signal wounded_changed(on: bool)
signal bandaged_changed(on: bool)

static var all: Array[Player] = []

const RESPAWN_FALLBACK_SECONDS: float = 90.0 ## a fallen player who never chooses comes back after this long
const SPAWN_POINT: Vector2 = Vector2.ZERO
const HUD_SCENE: PackedScene = preload("res://src/ui/hud.tscn")
const RUN_DUST_MIN_SPEED: float = 40.0 ## px/s
const BODY_CENTER: Vector2 = Vector2(0, -24) ## aim origin, relative to the feet
## Facing sector 0 = east, counting clockwise (screen y points down): E SE S SW W NW N NE.
## Sheet (assets/characters/player.png): one row per sector, rows 8-15 are the crouched copies.
## Columns 0-5 are the walk cycle, 6-11 the sprint cycle (contacts at 0 and 3 of each), 12-15 the idle loop.
## The sword combo has its own sheet (player_attack.png): one row per sector; per attack (forehand, backhand,
## thrust) 7 leg variants (0 = planted stance, 1-6 = the walk cycle's phases) x 6 keyframes.
const WALK_FRAMES: int = 6
const RUN_COL: int = 6
const IDLE_COL: int = 12
const IDLE_FRAMES: int = 4
const ATTACK_SHEET: Texture2D = preload("res://assets/characters/player_attack.png")
const ATTACK_FRAMES: int = 6
const ATTACK_LEGS: int = 7
const ATTACK_COLS: int = 3 * ATTACK_LEGS * ATTACK_FRAMES
const HEAVY_SHEET: Texture2D = preload("res://assets/characters/player_heavy.png") ## tools/art_hero_heavy.py: the sword's heavy blow (charge, chop, recover)
const HEAVY_BLOOD: Texture2D = preload("res://assets/characters/player_heavy_blood.png")
const HEAVY_KEYS: int = 10
const HEAVY_COLS: int = HEAVY_KEYS * ATTACK_LEGS ## per sector row: 7 leg variants x 10 keys
const PICK_SHEET: Texture2D = preload("res://assets/characters/player_pick.png")
const EAT_SHEET: Texture2D = preload("res://assets/characters/player_eat.png")
const TOUCH_SHEET: Texture2D = preload("res://assets/characters/player_touch.png") ## tools/art_hero3d.py touchonly: both palms on a waystone statue
const PULL_SHEET: Texture2D = preload("res://assets/characters/player_pull.png") ## tools/art_hero3d.py pullonly: she heaves a root out of the ground
const FISH_SHEET: Texture2D = preload("res://assets/characters/player_fish.png") ## tools/art_hero_fish.py: the rod's body clips (cast, strike, fight, land, snap, sag)
const FISH_BLOOD: Texture2D = preload("res://assets/characters/player_fish_blood.png")
const STANDBY_SHEET: Texture2D = preload("res://assets/characters/player_standby.png")
const STANDBY_BLOOD: Texture2D = preload("res://assets/characters/player_standby_blood.png")
const STANDBY_FRAMES: int = 24
const STANDBY_CLIPS: int = 3
const STANDBY_FPS: float = 12.0
const STANDBY_COLS: int = STANDBY_FRAMES * STANDBY_CLIPS
const BLOOD_MAPS: Array[Texture2D] = [ ## the baked blood thresholds of each sheet (main, sword, pick, eat), see hit_flash.gdshader
	preload("res://assets/characters/player_blood.png"), preload("res://assets/characters/player_attack_blood.png"),
	preload("res://assets/characters/player_pick_blood.png"), preload("res://assets/characters/player_eat_blood.png"),
	preload("res://assets/characters/player_pull_blood.png"), preload("res://assets/characters/player_touch_blood.png")]
const EMERGE_BLOOD: Texture2D = preload("res://assets/characters/player_emerge_blood.png")
const FAINT_SHEET: Texture2D = preload("res://assets/characters/player_faint.png") ## tools/art_hero_faint.py: she collapses (side view, facing east)
const SIT_SHEET: Texture2D = preload("res://assets/characters/player_sit.png") ## tools/art_hero_sit.py: she sits down by the fire
const SIT_BLOOD: Texture2D = preload("res://assets/characters/player_sit_blood.png")
const WARDROBE_SHEET: Texture2D = preload("res://assets/characters/player_wardrobe.png") ## tools/art_hero_wardrobe.py: she shuts her wardrobe (north view), the opening of her room
const CARRY_SHEET: Texture2D = preload("res://assets/characters/player_carry.png") ## tools/art_hero_carry.py: she carries a board (side view, facing east)
const FAINT_BLOOD: Texture2D = preload("res://assets/characters/player_faint_blood.png")
const STUMBLE_SHEET: Texture2D = preload("res://assets/characters/player_stumble.png") ## tools/art_hero_stumble.py: 8 views, she trips and gets up
const STUMBLE_BLOOD: Texture2D = preload("res://assets/characters/player_stumble_blood.png")
const STUMBLE_SOUNDS: Dictionary = {
	"gasp": preload("res://assets/audio/intro/gasp.wav"),
	"thud": preload("res://assets/audio/intro/body_thud.wav"),
	"cough": preload("res://assets/audio/intro/cough.wav"),
}
const EAT_VARIANTS: int = 7 ## the eat sheet repeats every frame per leg variant (0 planted, 1-6 the walk cycle's phases), like the attack sheet
const PICK_FRAMES: int = 12 ## the one-second action animations (picking, eating): 12 frames, sampled at (i + 0.5) / 12
const PICK_SECONDS: float = 1.0
const PICK_GRAB_TIME: float = 0.34 ## picking: the hand closes around the berries here
const TOUCH_TIME: float = 0.45 ## touching a statue: the palms lie on the stone here (the statue wakes)
const TOUCH_HOLD_AT: float = 0.52 ## and stay there until `release_touch`
const PULL_GRAB_TIME: float = 0.52 ## pulling a root: it gives here and she is thrown back
const EAT_USE_TIME: float = 0.48 ## eating: the berry reaches her mouth (EatEffect.BITE) and takes effect
const IDLE_FPS: float = 3.5 ## idle frames per second (breathing, hair)
const WOUND_ENTER: float = 0.10 ## wounded at this share of the maximum health or less ...
const WOUND_LEAVE: float = 0.13 ## ... and recovered above this share (so regeneration does not flicker it)
const WOUND_SPEED: float = 0.58 ## walking speed while wounded
const WOUND_PALE_FROM: float = 0.8 ## the blood loss starts to show below this share of health
const SHEET_COLS: int = 16

@export var max_speed: float = 62.0 ## px/s
@export var acceleration: float = 700.0 ## px/s²
@export var friction: float = 900.0 ## px/s²
@export var walk_fps: float = 13.0 ## walk frames per second at max_speed (6 frames = 1 cycle = 2 steps)
@export var jog_fps: float = 15.0 ## sprint-cycle frames per second at sprint_speed
@export var sneak_speed: float = 42.0 ## px/s while sneaking (Ctrl or C)
@export_group("Sprint")
@export var sprint_speed: float = 104.0 ## px/s while sprinting
@export var burst_speed: float = 260.0 ## px/s right after pressing sprint, decays into sprint_speed
@export var burst_cost: float = 20.0 ## stamina, paid once on press
@export var sprint_cost_per_sec: float = 12.0 ## stamina while sprinting

var facing: Vector2 = Vector2.DOWN ## synced

var _walk_time: float = 0.0
var _idle_time: float = 0.0
var _standby_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _standby_wait: float = -1.0
var _standby_clip: int = -1
var _standby_last: int = -1
var _standby_time: float = 0.0
var _rig_standby_shoulder: PackedVector2Array
var _rig_standby_hand: PackedVector2Array
var _rig_heavy_shoulder: PackedVector2Array
var _rig_heavy_hand: PackedVector2Array
var _rig_shoulder: PackedVector2Array ## per sheet frame, relative to the feet (data/hero_rig.json)
var _rig_hand: PackedVector2Array
var _rig_attack_shoulder: PackedVector2Array ## the same for the attack sheet
var _rig_attack_hand: PackedVector2Array
var _rig_pick_shoulder: PackedVector2Array ## and for the picking sheet
var _rig_pick_hand: PackedVector2Array
var _rig_pull_shoulder: PackedVector2Array ## and for the pulling sheet
var _rig_pull_hand: PackedVector2Array
var _rig_touch_shoulder: PackedVector2Array ## and for the touching sheet
var _rig_touch_hand: PackedVector2Array
var touch_hold: bool = false ## the palms stay on the stone (frozen at the end of the reach) until `release_touch`
var _touch_wait: float = 0.0
var _rig_eat_shoulder: PackedVector2Array ## and for the eating sheet
var _rig_eat_hand: PackedVector2Array
var _rig_eat_mouth: PackedVector2Array
var _eat_fx: EatEffect
var fishing: FishingComponent ## the rod (docs/fishing.md)
var effects: StatusEffects ## burning and the like (data/status_effects.json)
var _main_sheet: Texture2D
var _sheet: int = 0 ## which sheet the sprite shows: 0 main, 1 sword swing, 2 picking, 3 eating, 4 pulling a root
var _busy_kind: String = "pick" ## which one-second action runs while `_busy`
var _busy: bool = false ## synced by RPC: she is picking and stands still
var _busy_time: float = 0.0
var _sector: int = 2
var sprinting: bool = false ## synced

var _surface: Dictionary = {} ## terrain.json entry under the feet
var _last_step: int = -1 ## walk-cycle frame of the previous tick, -1 while standing
var _sink: float = 0.0 ## px the sprite sits lower in water
var _idle_ripple_timer: float = 0.0
var _shake: float = 0.0 ## camera shake in px, decays
var view_shift: Vector2 = Vector2.ZERO ## the camera looks this far (world px) beside her: shops frame the person she talks to on the left (BoardWindow)
var _was_dead: bool = false
var _slows: Dictionary = {} ## instance id of whatever slows her (a bush) -> speed factor
var _focus: Interactable ## what E would use right now
var _hotbar: Hotbar ## the local HUD's hotbar: which slot E eats from
var quests: QuestComponent ## the owner's quests (null on other peers)
var wounded: bool = false ## at 10 % health or less (until 13 %): slow, limping, no sprint, a red border on the HUD, on every peer
var _wound: float = 0.0 ## how much blood she has lost, 0..1, drives her look (eased towards the health)
var _limp_dip: float = 0.0
var _drip_timer: float = 2.0
var _hud: Node ## the local HUD
var stumbling: bool = false ## she is tripping, lying and getting up (the stumble sheet, see `begin_stumble`)
var _stumble_time: float = 0.0
var _stumble_phase: int = 0
var _stumble_wait: float = 0.0
var _stumble_cough_at: float = 1.4
var _stumble_prompt: InteractPrompt
var _stumble_fired: Dictionary = {}
const INTERACT_SCAN_SECONDS: float = 0.2 ## how often the interactables group is searched for the prompt (a press always searches)
var _scan_clock: float = 0.0
var _candidate: Interactable = null ## the nearest usable thing of the last scan, re-checked every frame
var fainting: bool = false ## the faint sheet is shown (AmbushScene drives the frames)
var _respawn_asked: bool = false
var story_lock: bool = false ## a cutscene holds her still (she still animates, the HUD stays)
var auto_walk: Vector2 = Vector2.INF ## while `story_lock`: a cutscene walks her slowly to this point (her limp and all)
var auto_walk_factor: float = -1.0 ## share of her top speed for that walk (< 0: the slow wounded walk)
var intro: Node ## while a story scene owns her (IntroScene, WakeScene) she cannot move or act
var bandaged: bool = false ## the rescuer dressed the wound: no blood, no red border, no heartbeat any more (she still limps while her health is low)

@onready var stamina: StaminaComponent = $StaminaComponent
@onready var blink: BlinkComponent = $BlinkComponent
@onready var stealth: StealthComponent = $StealthComponent
@onready var health: HealthComponent = $HealthComponent
@onready var progress: ProgressComponent = $ProgressComponent
@onready var inventory: InventoryComponent = $InventoryComponent
@onready var attack: AttackComponent = $AttackComponent
@onready var talismans: TalismanComponent = $TalismanComponent
@onready var _camera: Camera2D = $Camera2D
@onready var _sprite: Sprite2D = $Sprite2D
@onready var _dash_dust: CPUParticles2D = $DashDust
@onready var _run_dust: CPUParticles2D = $RunDust
@onready var _footsteps: FootstepComponent = $FootstepComponent
@onready var _ripples: WaterRipples = $WaterRipples
@onready var _water: WaterOverlay = $WaterOverlay


func _enter_tree() -> void:
	if not all.has(self):
		all.append(self)
	set_multiplayer_authority(name.to_int())


func _exit_tree() -> void:
	all.erase(self)


func _ready() -> void:
	add_to_group("players")
	_standby_rng.randomize()
	_load_rig()
	var rest: RestComponent = RestComponent.new()
	rest.name = "RestComponent"
	add_child(rest)
	fishing = FishingComponent.new()
	fishing.name = "FishingComponent"
	fishing.set_multiplayer_authority(get_multiplayer_authority()) ## a child made in _ready does not inherit the owner (its own _ready needs it)
	add_child(fishing)
	effects = StatusEffects.new()
	effects.name = "Effects"
	effects.set_multiplayer_authority(get_multiplayer_authority())
	add_child(effects)
	_eat_fx = EatEffect.new()
	add_child(_eat_fx)
	_main_sheet = _sprite.texture
	_sprite.add_child(TalismanLayer.new()) ## the worn necklace and earrings
	(_sprite.material as ShaderMaterial).set_shader_parameter("blood_map", BLOOD_MAPS[0])
	health.damaged.connect(_on_damaged)
	health.ticked.connect(_on_ticked)
	health.changed.connect(_update_wounded)
	var world: Node = get_tree().get_first_node_in_group("world")
	if world != null and world.has_method("starting_health_ratio"):
		health.current = maxf(1, health.max_health * float(world.call("starting_health_ratio")))
		sync_wound_visuals()
		_shake = 0.0
	_update_wounded(health.current, health.max_health)
	health.healed.connect(_on_healed)
	if multiplayer.is_server():
		health.died.connect(_respawn_after_delay)
	_camera.enabled = is_multiplayer_authority()
	_camera.reset_smoothing()
	if is_multiplayer_authority():
		var free_cam: FreeCam = FreeCam.new()
		free_cam.name = "FreeCam"
		add_child(free_cam) ## L: the free camera (dev tool)
		quests = QuestComponent.new()
		quests.name = "QuestComponent"
		add_child(quests)
		quests.story_event.connect(func(event_name: String) -> void:
			var story_world: Node = get_tree().get_first_node_in_group("world")
			if event_name == "ambush:crossroad" and story_world is WorldLevel:
				(story_world as WorldLevel).start_ambush(self)
			elif event_name == "wake:hut" and story_world is WorldLevel:
				(story_world as WorldLevel).start_wake(self)
			elif event_name == "meet:knight" and story_world is WorldLevel:
				(story_world as WorldLevel).start_knight_meet(self)
			elif event_name == "follow:knight" and story_world is WorldLevel:
				(story_world as WorldLevel).start_knight_walk(self)
			elif event_name.begins_with("story:") and story_world is WorldLevel:
				(story_world as WorldLevel).play_story_dialogue(self, event_name.trim_prefix("story:"))
			elif event_name == "finale:hut" and story_world is WorldLevel:
				(story_world as WorldLevel).start_hut_finale(self)
			elif event_name == "cabin:fight" and story_world is WorldLevel:
				(story_world as WorldLevel).start_cabin_spider(self)
			elif event_name == "wagon:fight" and story_world is WorldLevel:
				(story_world as WorldLevel).start_gustav_rescue(self, "fight")
			elif event_name == "wagon:meet" and story_world is WorldLevel:
				(story_world as WorldLevel).start_gustav_rescue(self, "meet")
			elif event_name == "escort:gustav" and story_world is WorldLevel:
				(story_world as WorldLevel).start_gustav_escort(self)
			elif event_name == "welcome:gustav" and story_world is WorldLevel:
				(story_world as WorldLevel).start_gustav_welcome(self))
		var hud: Node = HUD_SCENE.instantiate()
		_hud = hud
		add_child(hud)
		hud.call("bind", self)
		if world != null and world.has_method("starting_health_ratio"):
			var guide: OpeningGuide = OpeningGuide.new()
			guide.name = "OpeningGuide"
			add_child(guide)
			var stumbles: StumbleGuide = StumbleGuide.new()
			stumbles.name = "StumbleGuide"
			add_child(stumbles)
		_hotbar = hud.get_node("Hotbar") as Hotbar
		_hotbar.use_requested.connect(use_slot)
		inventory.changed.connect(_on_inventory_changed)
		health.changed.connect(_on_health_changed)
		attack.lunged.connect(func(impulse: Vector2) -> void: velocity += impulse)
		attack.hit_landed.connect(func(strength: float) -> void: _shake = maxf(_shake, strength))
		_on_inventory_changed()


## The camera, for windows that frame a scene (zoom and `view_shift`).
func view_camera() -> Camera2D:
	return _camera


func _process(delta: float) -> void:
	_camera.offset = view_shift + ((Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake * GameSettings.shake_factor()).round() if _shake > 0.0 else Vector2.ZERO)
	_shake = move_toward(_shake, 0.0, 14.0 * delta)


var _last_surface_pos: Vector2 = Vector2(INF, INF)
var _last_surface_result: Dictionary = {}

func _physics_process(delta: float) -> void:
	if global_position.distance_squared_to(_last_surface_pos) > 4.0:
		_last_surface_pos = global_position
		_surface = Terrain.surface_data(Terrain.surface_at(global_position))
		for patch: Node in Terrain.patches:
			if patch is WorldRivers:
				_surface = (patch as WorldRivers).wade_data(global_position, _surface)
		_last_surface_result = _surface
	else:
		_surface = _last_surface_result
	var down: bool = health.current <= 0.0
	_sprite.self_modulate = Color(0.35, 0.25, 0.5, 0.55) if down else Color.WHITE.lerp(Color(1.5, 1.9, 1.55), _eat_glow())
	attack.visible = not down and intro == null and not fainting and not stumbling
	if down:
		velocity = Vector2.ZERO
		_set_focus(null)
	elif launch_left > 0.0 and is_multiplayer_authority():
		_step_launch(delta)
		_set_focus(null)
	elif intro != null or story_lock:
		velocity = Vector2.ZERO ## the intro owns her: it places her and shows the frames
		if story_lock and intro == null and auto_walk != Vector2.INF and is_multiplayer_authority():
			var to_goal: Vector2 = auto_walk - global_position
			if to_goal.length() > 2.0:
				velocity = to_goal.normalized() * max_speed * (auto_walk_factor if auto_walk_factor > 0.0 else WOUND_SPEED * 0.8)
				facing = to_goal.normalized()
				move_and_slide()
		_set_focus(null)
	elif stumbling:
		velocity = velocity.move_toward(Vector2.ZERO, 260.0 * delta) ## she slides on a little
		if is_multiplayer_authority():
			move_and_slide()
		_set_focus(null)
		_update_stumble(delta)
	elif is_multiplayer_authority():
		_move(delta)
		_update_interact()
	else:
		position += velocity * delta ## remote player: the synchronizer sends at 20 Hz, so carry on with the synced velocity until the next packet
	_wound = move_toward(_wound, _wound_target(), delta * 0.5)
	(_sprite.material as ShaderMaterial).set_shader_parameter("wound", _wound)
	attack.wound = _wound
	attack.facing = facing
	if intro == null and not fainting and not stumbling:
		_animate(delta)
	else:
		_cancel_standby()
	_update_run_dust()
	_update_water(delta)


## Dust shoots out behind the player at the moment of the dash. Runs on every peer.
@rpc("authority", "call_local", "reliable")
func play_burst(dir: Vector2) -> void:
	if _is_submerged():
		return
	_dash_dust.direction = -dir
	_dash_dust.restart()


## Void blink effects (rifts, silhouette trail, flash). Runs on every peer.
@rpc("authority", "call_local", "reliable")
func play_blink(from: Vector2, to: Vector2) -> void:
	blink.play_effects(_sprite, from, to)


## Jumps toward the facing direction, at most `blink_range` and not past the cursor.
## Stops at obstacles.
func _try_blink() -> void:
	var start: Vector2 = global_position
	var distance: float = blink.blink_range
	if InputManager.using_mouse:
		distance = minf(distance, InputManager.aim_world_position().distance_to(start + BODY_CENTER))
	move_and_collide(facing * distance)
	if global_position.distance_to(start) < blink.min_distance:
		global_position = start ## wall right in front: cancelled, no cooldown spent
		return
	blink.start_cooldown()
	play_blink.rpc(start, global_position)


## Dev menu: jumps to a place (the owner moves herself; the synchronizer tells the others).
func request_teleport(to: Vector2) -> void:
	global_position = to
	velocity = Vector2.ZERO
	_camera.reset_smoothing()


## A boss throws her across the floor: she slides from where she stands to `target` in `seconds` (fast at first, slowing down, stopped by anything solid on
## the way); she cannot act meanwhile. Sent to the one who owns her (`launch`), who moves her.
var launch_left: float = 0.0
var launch_total: float = 1.0
var launch_from: Vector2 = Vector2.ZERO
var launch_to: Vector2 = Vector2.ZERO


func launch(target: Vector2, seconds: float) -> void:
	_rpc_launch.rpc_id(get_multiplayer_authority(), target, seconds)


@rpc("any_peer", "call_local", "reliable")
func _rpc_launch(target: Vector2, seconds: float) -> void:
	if multiplayer.get_remote_sender_id() > 1:
		return
	_busy = false
	_cancel_standby()
	launch_from = global_position
	launch_to = target
	launch_total = maxf(seconds, 0.05)
	launch_left = launch_total


func _step_launch(delta: float) -> void:
	launch_left = maxf(launch_left - delta, 0.0)
	var k: float = clampf(1.0 - launch_left / launch_total, 0.0, 1.0)
	var want: Vector2 = launch_from.lerp(launch_to, 1.0 - pow(1.0 - k, 3.0))
	velocity = (want - global_position) / maxf(delta, 0.0001)
	move_and_slide()
	if launch_left <= 0.0:
		velocity = Vector2.ZERO


## Cheat menu: full health (the host decides, so a client asks) and full stamina.
func request_heal() -> void:
	stamina.refill()
	if multiplayer.is_server():
		health.heal_full()
	else:
		_rpc_heal.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_heal() -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		health.heal_full()


func _on_inventory_changed() -> void:
	var in_hand: Dictionary = inventory.active_stack()
	attack.held_weapon = String(in_hand.get("id", "")) ## a selected tool replaces the weapon
	attack.held_refine = Items.refine(in_hand)


## Everyone sees the hit; the owner also gets knocked back and shaken.
func _on_damaged(amount: float, from: Vector2, knockback: float) -> void:
	_busy = false ## a hit interrupts picking
	_cancel_standby()
	if is_multiplayer_authority():
		attack.interrupt_charge() ## ... and the charge of a heavy blow
	var away: Vector2 = (global_position - from).normalized()
	var flash: ShaderMaterial = _sprite.material as ShaderMaterial
	flash.set_shader_parameter("flash", 1.0)
	create_tween().tween_property(flash, "shader_parameter/flash", 0.0, 0.2)
	DamageNumber.spawn(get_tree().current_scene, global_position + Vector2(0, -50), amount, away, Color("ff5a6a"))
	if is_multiplayer_authority():
		velocity += away * knockback
		_shake = maxf(_shake, 3.0)


## Everyone sees a small number in the colour of the burning (a tick of damage over time).
func _on_ticked(amount: float) -> void:
	DamageNumber.spawn_text(get_tree().current_scene, global_position + Vector2(randf_range(-6.0, 6.0), -46), str(roundi(amount)), Color("ff6ad8"))


## Everyone sees the green number.
func _on_healed(amount: float) -> void:
	var over: bool = health.current > health.max_health ## overheal is white, health green
	DamageNumber.spawn_text(get_tree().current_scene, global_position + Vector2(0, -50), "+%d" % roundi(amount), Color("f4f0ff") if over else Color("9af0a8"))


func _on_health_changed(current: float, _maximum: float) -> void:
	if _was_dead and current > 0.0: ## respawned
		var level: TestLevel = get_parent().get_parent() as TestLevel ## players hang under the level's `Players` node
		global_position = level.spawn_point() if level else SPAWN_POINT
		velocity = Vector2.ZERO
		_camera.reset_smoothing()
		sync_wound_visuals()
	_was_dead = current <= 0.0


## Host: after a fall the player waits for the choice on her death screen (`request_respawn`); a player who never answers
## (gone, stuck) is brought back after `RESPAWN_FALLBACK_SECONDS` anyway.
func _respawn_after_delay() -> void:
	_respawn_asked = false
	var left: float = RESPAWN_FALLBACK_SECONDS
	while not _respawn_asked and left > 0.0 and health.current <= 0.0:
		await get_tree().create_timer(0.25).timeout
		if not is_inside_tree():
			return
		left -= 0.25
	_respawn_asked = false
	if health.current > 0.0:
		return
	var world: Node = get_tree().get_first_node_in_group("world")
	if world is WorldLevel and not (world as WorldLevel).opening_over: ## still in the opening: she comes back wounded
		health.set_health(health.max_health * (world as WorldLevel).starting_health_ratio())
	else:
		health.heal_full()


## The death screen's ZURÜCKKEHREN: the host brings her back (a client asks).
func request_respawn() -> void:
	if multiplayer.is_server():
		_respawn_asked = true
	else:
		_rpc_respawn.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_respawn() -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		_respawn_asked = true


func _is_submerged() -> bool:
	return float(_surface.get("submerge", 0.0)) > 0.0


func _update_water(delta: float) -> void:
	var submerge: float = float(_surface.get("submerge", 0.0))
	_water.submerge = submerge
	_sink = move_toward(_sink, roundf(submerge / 2.5), 20.0 * delta)
	if bool(_surface.get("ripples", false)) and velocity.length() < 5.0: ## ripples while standing still
		_idle_ripple_timer -= delta
		if _idle_ripple_timer <= 0.0:
			_ripples.add(global_position)
			_idle_ripple_timer = 0.9


## Called at every footfall (also for remote players, driven by the walk animation).
func _on_step() -> void:
	_footsteps.step(_surface, velocity, stealth.sneaking)
	if (wounded or _wound > 0.55) and not bandaged:
		BloodSplat.drop(get_tree().current_scene, global_position + Vector2(randf_range(-3.0, 3.0), randf_range(-1.0, 2.0)), 1 + int(randf() < 0.4))
	if bool(_surface.get("ripples", false)):
		_ripples.add(_footsteps.contact_position(velocity), clampf(velocity.length() / 65.0, 0.35, 1.5))


func _update_run_dust() -> void:
	var running: bool = sprinting and velocity.length() > RUN_DUST_MIN_SPEED and not _is_submerged()
	_run_dust.emitting = running
	if running:
		_run_dust.direction = -velocity.normalized()


func _move(delta: float) -> void:
	var eating: bool = _busy and _busy_kind == "eat" ## eating, unlike picking, goes on while she walks
	if fishing != null and fishing.locks_movement(): ## a fish is on the line: she braces and stands still
		velocity = velocity.move_toward(Vector2.ZERO, friction * 2.0 * delta)
		move_and_slide()
		return
	if _busy and not eating: ## she stands still while she picks
		velocity = velocity.move_toward(Vector2.ZERO, friction * 2.0 * delta)
		move_and_slide()
		return
	var charging: bool = _update_charge()
	var dir: Vector2 = InputManager.move_vector()
	if attack.is_heavy_swing():
		dir = Vector2.ZERO ## the heavy blow is struck planted
	var can_sprint: bool = bool(_surface.get("allow_sprint", true)) and not wounded ## wounded: no sprinting
	var want_sprint: bool = InputManager.sprint_held() and can_sprint and dir != Vector2.ZERO and not attack.is_swinging() and not _busy and not charging
	if want_sprint and stamina.current > 0.0:
		sprinting = stamina.drain(sprint_cost_per_sec, delta)
	else:
		sprinting = false

	if InputManager.blink_pressed() and blink.is_ready() and not _busy and bool(_surface.get("allow_blink", true)):
		_try_blink()

	stealth.sneaking = InputManager.sneak_held() and not sprinting and not _busy and not charging

	if dir == Vector2.ZERO:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	else:
		var base_speed: float = sprint_speed if sprinting else (sneak_speed if stealth.sneaking else max_speed)
		var speed: float = base_speed * float(_surface.get("speed", 1.0)) * _slow_factor() * (WOUND_SPEED if wounded else 1.0) * attack.charge_move_factor()
		velocity = velocity.move_toward(dir * speed, acceleration * delta)
	move_and_slide()

	if attack.is_swinging():
		facing = attack.aim_dir ## locked toward the swing
		return
	if charging:
		facing = attack.aim_dir ## follows the cursor while the blow is charged
		return
	var in_combat: bool = attack.is_in_combat(1.5)
	if in_combat and InputManager.using_mouse:
		var look_mouse: Vector2 = InputManager.aim_vector(global_position + BODY_CENTER)
		if look_mouse != Vector2.ZERO:
			facing = look_mouse
	elif dir != Vector2.ZERO:
		facing = dir.normalized()
	if InputManager.attack_pressed() and attack.can_attack() and not _busy:
		if InputManager.using_mouse:
			var attack_aim: Vector2 = InputManager.aim_vector(global_position + BODY_CENTER)
			if attack_aim != Vector2.ZERO:
				facing = attack_aim
		sprinting = false ## swinging while sprinting drops her into a walk
		attack.attack(facing)


## Owner, every physics frame: the right mouse button charges the weapon's secondary attack (the sword's heavy blow) and
## lets it go on release. A menu taking the input, a dodge, a cutscene or a fall drops the charge. True while charging.
func _update_charge() -> bool:
	if not is_multiplayer_authority():
		return false
	var blocked: bool = _busy or stumbling or fainting or intro != null or story_lock or health.current <= 0.0
	if attack.is_charging():
		if blocked or InputManager.blink_pressed():
			attack.cancel_charge()
			return false
		var aim: Vector2 = InputManager.aim_vector(global_position + BODY_CENTER) if InputManager.using_mouse else Vector2.ZERO
		var still: bool = attack.charge_input(InputManager.secondary_held(), InputManager.secondary_down(), aim, get_physics_process_delta_time())
		return still and attack.is_charging()
	if blocked or not InputManager.secondary_pressed() or not attack.can_charge():
		return false
	var start_aim: Vector2 = InputManager.aim_vector(global_position + BODY_CENTER) if InputManager.using_mouse else facing
	sprinting = false ## the charge drops a sprint into a walk
	attack.begin_charge(start_aim)
	return attack.is_charging()


## Something owns her: a cutscene, an action, a fall (the rod cannot be cast then).
func is_busy() -> bool:
	return _busy or stumbling or fainting or intro != null or story_lock or attack.is_swinging() or attack.is_charging()


## Local player: picks toward `dir` (about a second, she stands still, the weapon is put away);
## `on_grab` runs at the moment the hand closes, when the reward should appear.
func begin_pick(dir: Vector2, on_grab: Callable) -> void:
	_begin_action("pick", dir, on_grab, PICK_GRAB_TIME)


## Local player: pulls a root out of the ground toward `dir`; `on_grab` runs when it gives (and she stumbles back).
func begin_pull(dir: Vector2, on_grab: Callable) -> void:
	_begin_action("pull", dir, on_grab, PULL_GRAB_TIME)


## Local player: lays both palms on something (a waystone statue) toward `dir`; `on_touch` runs when they lie on it. She keeps the hands there until
## `release_touch()` (the statue's light runs over it), then draws back. Hit or stopped: the hold ends by itself after 14 s.
func begin_touch(dir: Vector2, on_touch: Callable) -> void:
	_begin_action("touch", dir, on_touch, TOUCH_TIME)


## Ends the hold of `begin_touch` (any peer may call it for the local player; it is replicated).
func release_touch() -> void:
	if is_multiplayer_authority():
		_play_release_touch.rpc()


@rpc("authority", "call_local", "reliable")
func _play_release_touch() -> void:
	touch_hold = false


## Local player: eats what is in hotbar slot `slot` (a consumable), if that would do anything. The
## berry is used up when it reaches her mouth (EAT_USE_TIME); being hit before that stops it.
func use_slot(slot: int) -> void:
	if _busy or stumbling or attack.is_swinging() or attack.is_charging() or health.current <= 0.0 or slot < 0 or slot >= InventoryComponent.HOTBAR_SIZE:
		return
	var stack: Dictionary = inventory.slots[slot]
	var def: Dictionary = Items.definition(stack)
	if stack.is_empty() or String(def.get("kind", "")) != "consumable":
		return
	var stats: Dictionary = def.get("stats", {})
	if float(stats.get("heal", 0)) + float(stats.get("regen", 0)) > 0.0 and not health.can_heal():
		return ## nothing to heal: keep the berry
	_begin_action("eat", Vector2.ZERO, func() -> void:
		inventory.request("use", [slot, 0])
		_shake = maxf(_shake, 1.2), EAT_USE_TIME)


func _begin_action(kind: String, dir: Vector2, on_moment: Callable, moment_time: float) -> void:
	if _busy or attack.is_swinging() or attack.is_charging() or not is_multiplayer_authority():
		return
	_set_focus(null)
	_play_action.rpc(kind, dir)
	await get_tree().create_timer(moment_time).timeout
	if _busy and _busy_kind == kind and is_inside_tree() and on_moment.is_valid():
		on_moment.call()


@rpc("authority", "call_local", "reliable")
func _play_action(kind: String, dir: Vector2) -> void:
	_busy = true
	_busy_kind = kind
	_busy_time = 0.0
	touch_hold = kind == "touch"
	_touch_wait = 0.0
	sprinting = false
	if dir != Vector2.ZERO:
		facing = dir
	if kind != "eat":
		_walk_time = 0.0


## The camera shakes for a moment (a tree hits the ground nearby).
func add_shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


## 0..1: she glows a moment when the berry takes effect.
func _eat_glow() -> float:
	if not _busy or _busy_kind != "eat":
		return 0.0
	var k: float = (_busy_time - EAT_USE_TIME) / 0.4
	return sin(k * PI) if k > 0.0 and k < 1.0 else 0.0


## Something (a bush) slows her while she is in it; the slowest one counts. Local machine only.
func set_slow(source: Object, factor: float) -> void:
	_slows[source.get_instance_id()] = factor


func clear_slow(source: Object) -> void:
	_slows.erase(source.get_instance_id())


func _slow_factor() -> float:
	var factor: float = 1.0
	for value: float in _slows.values():
		factor = minf(factor, value)
	return factor


## The nearest thing within reach that E can use gets the prompt; E uses it. The group is scanned five times a second; in between the stored
## candidate is only re-checked (still there, usable, in reach), and a press scans again first, so E always uses what is current.
func _update_interact() -> void:
	if _busy:
		return
	_scan_clock -= get_physics_process_delta_time()
	if _scan_clock <= 0.0 or InputManager.interact_pressed():
		_scan_clock = INTERACT_SCAN_SECONDS
		_candidate = _scan_interact()
	elif not is_instance_valid(_candidate) or not _candidate_usable(_candidate):
		_candidate = null
	_set_focus(_candidate)
	if InputManager.interact_pressed():
		if _focus != null:
			_focus.interact(self)
		elif _hotbar != null: ## nothing to use here: E eats from the selected hotbar slot
			use_slot(_hotbar.selected)


## The full scan of the interactables group (what `_update_interact` picks up).
func _scan_interact() -> Interactable:
	var best: Interactable = null
	var best_distance: float = Interactable.INTERACT_RANGE
	if InputManager.ui_blocking:
		return null
	for node: Node in get_tree().get_nodes_in_group("interactables"):
		var item: Interactable = node as Interactable
		if item == null:
			continue
		if absf(item.global_position.x - global_position.x) > 48.0 or absf(item.global_position.y - global_position.y) > 48.0:
			continue
		if item.prompt() == "":
			continue
		var distance: float = item.reach_distance(global_position)
		if distance < best_distance:
			best_distance = distance
			best = item
	return best


## The cheap per-frame check of the stored candidate: same rules as `_scan_interact`, for one item.
func _candidate_usable(item: Interactable) -> bool:
	if InputManager.ui_blocking or not item.is_in_group("interactables"):
		return false
	if absf(item.global_position.x - global_position.x) > 48.0 or absf(item.global_position.y - global_position.y) > 48.0:
		return false
	if item.prompt() == "":
		return false
	return item.reach_distance(global_position) < Interactable.INTERACT_RANGE


func _set_focus(item: Interactable) -> void:
	if item == _focus:
		return
	if is_instance_valid(_focus):
		_focus.set_focused(false)
	_focus = item
	if _focus != null:
		_focus.set_focused(true)


## The sword arm is drawn by AttackComponent from these per-frame points (see tools/art_hero3d.py).
func _load_rig() -> void:
	var rig: Dictionary = DataRegistry.table("hero_rig")
	for point: Array in rig.get("shoulder", []):
		_rig_shoulder.append(Vector2(float(point[0]), float(point[1])))
	for point: Array in rig.get("hand", []):
		_rig_hand.append(Vector2(float(point[0]), float(point[1])))
	for point: Array in rig.get("attack_shoulder", []):
		_rig_attack_shoulder.append(Vector2(float(point[0]), float(point[1])))
	for point: Array in rig.get("attack_hand", []):
		_rig_attack_hand.append(Vector2(float(point[0]), float(point[1])))
	for point: Array in rig.get("heavy_shoulder", []):
		_rig_heavy_shoulder.append(Vector2(float(point[0]), float(point[1])))
	for point: Array in rig.get("heavy_hand", []):
		_rig_heavy_hand.append(Vector2(float(point[0]), float(point[1])))
	for point: Array in rig.get("pick_shoulder", []):
		_rig_pick_shoulder.append(Vector2(float(point[0]), float(point[1])))
	for point: Array in rig.get("pick_hand", []):
		_rig_pick_hand.append(Vector2(float(point[0]), float(point[1])))
	for point: Array in rig.get("pull_shoulder", []):
		_rig_pull_shoulder.append(Vector2(float(point[0]), float(point[1])))
	for point: Array in rig.get("pull_hand", []):
		_rig_pull_hand.append(Vector2(float(point[0]), float(point[1])))
	for point: Array in rig.get("touch_shoulder", []):
		_rig_touch_shoulder.append(Vector2(float(point[0]), float(point[1])))
	for point: Array in rig.get("touch_hand", []):
		_rig_touch_hand.append(Vector2(float(point[0]), float(point[1])))
	for point: Array in rig.get("eat_shoulder", []):
		_rig_eat_shoulder.append(Vector2(float(point[0]), float(point[1])))
	for point: Array in rig.get("eat_hand", []):
		_rig_eat_hand.append(Vector2(float(point[0]), float(point[1])))
	for point: Array in rig.get("eat_mouth", []):
		_rig_eat_mouth.append(Vector2(float(point[0]), float(point[1])))
	var standby: Dictionary = rig.get("standby", {}) as Dictionary
	for point: Array in standby.get("shoulder", []):
		_rig_standby_shoulder.append(Vector2(float(point[0]), float(point[1])))
	for point: Array in standby.get("hand", []):
		_rig_standby_hand.append(Vector2(float(point[0]), float(point[1])))


@rpc("authority", "call_local", "reliable")
func _start_standby(clip: int) -> void:
	if clip < 0 or clip >= STANDBY_CLIPS:
		return
	_standby_clip = clip
	_standby_last = clip
	_standby_time = 0.0
	_standby_wait = -1.0


@rpc("authority", "call_local", "reliable")
func _stop_standby() -> void:
	_standby_clip = -1
	_standby_time = 0.0
	_standby_wait = -1.0


func _cancel_standby() -> void:
	if _standby_clip >= 0 and is_multiplayer_authority() and multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		_stop_standby.rpc()
	else:
		_stop_standby()


func _update_standby(delta: float, moving: bool) -> void:
	var blocked: bool = moving or (fishing != null and fishing.anim != "") or health.current <= 0.0 or stealth.sneaking or _busy or story_lock or intro != null or fainting or stumbling or _is_submerged() or attack.is_in_combat(AttackComponent.OUT_OF_COMBAT)
	if is_multiplayer_authority() and (InputManager.ui_blocking or InputManager.map_open or (InputManager.skills_open or InputManager.progress_open) or InputManager.move_vector() != Vector2.ZERO):
		blocked = true
	if blocked:
		_cancel_standby()
		return
	if _standby_clip >= 0:
		_standby_time += delta * (0.65 if wounded else 1.0)
		if _standby_time >= float(STANDBY_FRAMES) / STANDBY_FPS:
			_stop_standby()
			_idle_time = 0.0
		return
	if not is_multiplayer_authority() or _rig_standby_hand.size() != 8 * STANDBY_COLS or _rig_standby_shoulder.size() != 8 * STANDBY_COLS:
		return
	if _standby_wait < 0.0:
		_standby_wait = _standby_rng.randf_range(8.0, 16.0)
	_standby_wait = maxf(_standby_wait - delta, 0.0)
	if _standby_wait > 0.0 or int(_idle_time) != 0:
		return
	var clip: int = _standby_rng.randi_range(0, STANDBY_CLIPS - 1) if _standby_last < 0 else _standby_rng.randi_range(0, STANDBY_CLIPS - 2)
	if _standby_last >= 0 and clip >= _standby_last:
		clip += 1 ## each next gesture differs from the previous one
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		_start_standby.rpc(clip)
	else:
		_start_standby(clip)


## Picks the sheet frame: walk or sprint cycle while moving, idle loop while standing.
func _animate(delta: float) -> void:
	var angle: float = facing.angle() / (PI / 4.0)
	if absf(wrapf(angle - float(_sector), -4.0, 4.0)) > 0.62: ## hysteresis: no flicker on sector borders
		_sector = posmod(roundi(angle), 8)

	var moving: bool = velocity.length() > 5.0
	var running: bool = moving and sprinting and not stealth.sneaking
	var col: int
	if moving:
		var direction: float = -1.0 if velocity.dot(facing) < 0.0 else 1.0 ## walking backwards plays in reverse
		var pace: float = clampf(velocity.length() / max_speed, 0.5, 2.0)
		var animation_fps: float = walk_fps
		if running: ## the relaxed jog follows actual speed, including slowed surfaces
			pace = clampf(velocity.length() / maxf(sprint_speed, 0.01), 0.25, 1.65)
			animation_fps = jog_fps
		var limp_k: float = 1.0 + 0.6 * sin(TAU * _walk_time / float(WALK_FRAMES) + 0.6) if wounded else 1.0 ## the good leg swings quickly, the bad one is dragged
		_walk_time = fposmod(_walk_time + direction * animation_fps * pace * limp_k * delta, float(WALK_FRAMES))
		var step: int = int(_walk_time)
		col = (RUN_COL if running else 0) + step
		if step != _last_step and step % (WALK_FRAMES / 2) == 0: ## the two contact frames of the cycle
			_on_step()
		_last_step = step
		_idle_time = 0.0
	else:
		_walk_time = 0.0
		_last_step = -1
		_idle_time = fposmod(_idle_time + IDLE_FPS * (0.6 if wounded else 1.0) * delta, float(IDLE_FRAMES)) ## slow, heavy breathing when wounded
		col = IDLE_COL + int(_idle_time)
	var was_standby: bool = _standby_clip >= 0
	_update_standby(delta, moving)
	if was_standby and _standby_clip < 0 and not moving:
		col = IDLE_COL ## the gesture ends on exactly this breathing frame
	var main_frame: int = (_sector + (8 if stealth.sneaking else 0)) * SHEET_COLS + col
	_animate_limp(delta, moving)
	_sprite.position.y = _sink + _limp_dip
	var shoulder: Vector2 = Vector2(-4.0, -31.0)
	var hand: Vector2 = Vector2(-5.0, -21.0)
	if main_frame < _rig_hand.size():
		shoulder = _rig_shoulder[main_frame]
		hand = _rig_hand[main_frame]
	if _busy:
		var holding: bool = _busy_kind == "touch" and touch_hold and _busy_time >= TOUCH_HOLD_AT
		if holding:
			_touch_wait += delta
			if _touch_wait > 14.0:
				touch_hold = false
		else:
			_busy_time += delta
		if _busy_time >= PICK_SECONDS:
			_busy = false
	var fish_frame: Dictionary = fishing.body_frame(_sector, moving) if fishing != null and not _busy else {}
	var fish_frame_ok: bool = not fish_frame.is_empty() and not attack.is_swinging()
	if not fish_frame_ok:
		attack.rod_pose = Vector3.INF
	if _busy and not _rig_pick_hand.is_empty() and not _rig_eat_hand.is_empty():
		## Picking and eating have their own sheets too (legs planted); the right arm is drawn from the rig, weapon put away.
		var position_in_sheet: float = _busy_time / PICK_SECONDS * float(PICK_FRAMES)
		var key: float = clampf(position_in_sheet - 0.5, 0.0, float(PICK_FRAMES - 1) - 0.001)
		var i: int = int(key)
		var f: float = key - float(i)
		var eating: bool = _busy_kind == "eat"
		var legs: int = 1 + clampi(int(_walk_time), 0, WALK_FRAMES - 1) if moving and eating else 0 ## eating while walking keeps the walk cycle's legs
		var base: int = _sector * PICK_FRAMES * (EAT_VARIANTS if eating else 1) + legs * PICK_FRAMES
		var pulling: bool = _busy_kind == "pull" and not _rig_pull_hand.is_empty()
		var touching: bool = _busy_kind == "touch" and not _rig_touch_hand.is_empty()
		var hands: PackedVector2Array = _rig_eat_hand if eating else (_rig_touch_hand if touching else (_rig_pull_hand if pulling else _rig_pick_hand))
		var shoulders: PackedVector2Array = _rig_eat_shoulder if eating else (_rig_touch_shoulder if touching else (_rig_pull_shoulder if pulling else _rig_pick_shoulder))
		_use_sheet(3 if eating else (5 if touching else (4 if pulling else 2)))
		_sprite.frame = base + clampi(int(position_in_sheet), 0, PICK_FRAMES - 1)
		hand = hands[base + i].lerp(hands[base + i + 1], f)
		shoulder = shoulders[base + i].lerp(shoulders[base + i + 1], f)
		if eating:
			var mouth: Vector2 = _rig_eat_mouth[base + i].lerp(_rig_eat_mouth[base + i + 1], f)
			_eat_fx.show_state(_busy_time, hand + Vector2(0.0, _sink), mouth + Vector2(0.0, _sink))
	elif attack.heavy_key() >= 0.0 and not _rig_heavy_hand.is_empty():
		## The heavy blow (charge, chop, recover) has its own sheet: 10 keys, legs planted or following the walk cycle.
		var heavy: float = clampf(attack.heavy_key(), 0.0, float(HEAVY_KEYS - 1) - 0.001)
		var hi: int = int(heavy)
		var hf: float = heavy - float(hi)
		var heavy_legs: int = 1 + clampi(int(_walk_time), 0, WALK_FRAMES - 1) if moving and not attack.is_heavy_swing() else 0
		var heavy_base: int = _sector * HEAVY_COLS + heavy_legs * HEAVY_KEYS
		_use_sheet(11)
		_sprite.frame = heavy_base + (hi + 1 if hf >= 0.5 else hi)
		hand = _rig_heavy_hand[heavy_base + hi].lerp(_rig_heavy_hand[heavy_base + hi + 1], hf)
		shoulder = _rig_heavy_shoulder[heavy_base + hi].lerp(_rig_heavy_shoulder[heavy_base + hi + 1], hf)
	elif attack.is_swinging() and not _rig_attack_hand.is_empty():
		## The swing has its own sheet: upper body from the keyframe, legs planted while she stands and
		## following the walk cycle while she moves.
		var swing: Vector2 = attack.animation_state() ## x: which attack, y: keyframe position (-1 winding up .. 5)
		var legs: int = 1 + clampi(int(_walk_time), 0, WALK_FRAMES - 1) if moving else 0
		var base: int = _sector * ATTACK_COLS + (int(swing.x) * ATTACK_LEGS + legs) * ATTACK_FRAMES
		var key: float = swing.y
		var i: int = clampi(int(maxf(key, 0.0)), 0, ATTACK_FRAMES - 2)
		var f: float = maxf(key, 0.0) - float(i)
		_use_sheet(1)
		_sprite.frame = base + clampi(int(maxf(key, 0.0)), 0, ATTACK_FRAMES - 1)
		var to_hand: Vector2 = _rig_attack_hand[base + i].lerp(_rig_attack_hand[base + i + 1], f)
		var to_shoulder: Vector2 = _rig_attack_shoulder[base + i].lerp(_rig_attack_shoulder[base + i + 1], f)
		if key < 0.0: ## winding up: from where the hand was into the first keyframe
			to_hand = hand.lerp(_rig_attack_hand[base], key + 1.0)
			to_shoulder = shoulder.lerp(_rig_attack_shoulder[base], key + 1.0)
		hand = to_hand
		shoulder = to_shoulder
	elif fish_frame_ok:
		_use_sheet(10)
		_sprite.frame = int(fish_frame["frame"])
		hand = fish_frame["hand"] as Vector2
		shoulder = fish_frame["shoulder"] as Vector2
		attack.rod_pose = fish_frame["rod"] as Vector3
	elif _standby_clip >= 0:
		var key: float = clampf(_standby_time * STANDBY_FPS, 0.0, float(STANDBY_FRAMES - 1))
		var i: int = int(key)
		var next: int = mini(i + 1, STANDBY_FRAMES - 1)
		var base: int = _sector * STANDBY_COLS + _standby_clip * STANDBY_FRAMES
		_use_sheet(9)
		_sprite.frame = base + i
		hand = _rig_standby_hand[base + i].lerp(_rig_standby_hand[base + next], key - float(i))
		shoulder = _rig_standby_shoulder[base + i].lerp(_rig_standby_shoulder[base + next], key - float(i))
	else:
		_use_sheet(0)
		_sprite.frame = main_frame
	if not (_busy and _busy_kind == "eat"):
		_eat_fx.clear()
	attack.rig_shoulder = shoulder + Vector2(-_sprite.skew * shoulder.y, _sink + _limp_dip)
	attack.rig_hand = hand + Vector2(-_sprite.skew * hand.y, _sink + _limp_dip)
	attack.carrying = running and not attack.is_swinging()
	attack.sheathed = stealth.sneaking or _busy ## sneaking and picking put the weapon away


## The intro starts: normal HUD parts hide, the wound border and blood stay active.
func begin_intro(scene: Node) -> void:
	intro = scene
	facing = Vector2.RIGHT
	_sector = 0
	if _hud != null:
		_hud.call("begin_intro")
	_main_sheet_restore()


## One frame of the emerge sheet, and where she stands (the intro calls this every frame).
func show_emerge_frame(texture: Texture2D, frames: int, frame: int, at: Vector2, blood_map: Texture2D = EMERGE_BLOOD, sprite_offset: Vector2 = Vector2(0.0, -13.0)) -> void:
	if _sheet != 4 or _sprite.texture != texture:
		_sheet = 4
		(_sprite.material as ShaderMaterial).set_shader_parameter("blood_map", blood_map)
		_sprite.texture = texture
		_sprite.hframes = frames
		_sprite.vframes = 1
		_sprite.offset = sprite_offset ## the emerge frames are 76 high (the shaft below her feet), feet at row 51
	_sprite.frame = frame
	_sprite.position.y = 0.0
	global_position = at


## She trips (the story's footpath, `StumbleGuide`): the foot catches, the knee gives, she lands on her hands and knees, stays there a moment,
## pushes up and walks on. Owner only; every peer plays it (`_play_stumble`). Not while she is busy, in a cutscene or hurt to death.
func begin_stumble() -> bool:
	if stumbling or intro != null or story_lock or fainting or _busy or attack.is_swinging() or attack.is_charging() or health.current <= 0.0 or not is_multiplayer_authority():
		return false
	_play_stumble.rpc(_sector)
	return true


@rpc("authority", "call_local", "reliable")
func _play_stumble(sector: int) -> void:
	stumbling = true
	_stumble_time = 0.0
	_stumble_phase = 0
	_stumble_wait = 0.0
	_stumble_cough_at = 1.4
	_stumble_fired.clear()
	_sector = sector
	sprinting = false
	stealth.sneaking = false
	_sheet = 6
	(_sprite.material as ShaderMaterial).set_shader_parameter("blood_map", STUMBLE_BLOOD)
	_sprite.texture = STUMBLE_SHEET
	var rig: Dictionary = (DataRegistry.table("hero_rig").get("stumble", {}) as Dictionary)
	_sprite.hframes = int(rig.get("frames", 1))
	_sprite.vframes = 8
	_sprite.offset = Vector2(0.0, -13.0)


## Phases: 0 she falls (until `hold`), 1 she stays on her hands and knees, breathing, until she presses E (`rise`), 2 she gets up.
func _update_stumble(delta: float) -> void:
	var rig: Dictionary = (DataRegistry.table("hero_rig").get("stumble", {}) as Dictionary)
	var fps: float = float(rig.get("fps", 24))
	var frames: int = int(rig.get("frames", 1))
	var events: Dictionary = rig.get("events", {}) as Dictionary
	var hold_at: float = float(events.get("hold", 0.7))
	var rise_at: float = float(events.get("rise", 1.15))
	var frame: int
	if _stumble_phase == 1:
		_stumble_wait += delta
		var first: int = int(hold_at * fps)
		var last: int = int(rise_at * fps) - 1
		var span: int = maxi(last - first, 1)
		var step: int = int(_stumble_wait * 9.0) % (span * 2) ## breathing: back and forth over the held frames
		frame = first + (step if step <= span else span * 2 - step)
		if _stumble_wait > 1.0 and _stumble_prompt == null: ## "E GET UP" hangs over her
			_stumble_prompt = InteractPrompt.new()
			_stumble_prompt.position = Vector2(0, -44)
			add_child(_stumble_prompt)
			_stumble_prompt.show_text("AUFSTEHEN")
		if is_multiplayer_authority() and _stumble_wait > 0.7 and InputManager.interact_pressed():
			_stumble_rise.rpc()
	else:
		_stumble_time += delta
		if _stumble_phase == 0 and _stumble_time >= hold_at:
			_stumble_phase = 1
			_stumble_wait = 0.0
			_stumble_time = hold_at
		frame = mini(int(_stumble_time * fps), frames - 1)
	_sprite.frame = _sector * frames + frame
	_sprite.position.y = 0.0
	for event_name: String in events:
		if _stumble_phase != 1 and _stumble_time >= float(events[event_name]) and not _stumble_fired.has(event_name):
			_stumble_fired[event_name] = true
			_stumble_event(event_name)
	if _stumble_phase == 1 and _stumble_wait >= _stumble_cough_at:
		_stumble_cough_at += 3.4
		_stumble_event("cough")
	if _stumble_phase == 2 and _stumble_time >= float(rig.get("duration", 2.0)):
		stumbling = false
		_sheet = -1 ## the next _animate puts the normal sheet back
		_sprite.offset = Vector2(0.0, -23.0)


## E: she pushes herself up (every peer plays the rest of the animation).
@rpc("authority", "call_local", "reliable")
func _stumble_rise() -> void:
	if not stumbling or _stumble_phase != 1:
		return
	_stumble_phase = 2
	var rig: Dictionary = (DataRegistry.table("hero_rig").get("stumble", {}) as Dictionary)
	var events: Dictionary = rig.get("events", {}) as Dictionary
	_stumble_time = float(events.get("rise", 1.15))
	for event_name: String in events:
		if float(events[event_name]) <= _stumble_time:
			_stumble_fired[event_name] = true
	if _stumble_prompt != null:
		_stumble_prompt.queue_free()
		_stumble_prompt = null
	_stumble_event("gasp")


func _stumble_event(event_name: String) -> void:
	if STUMBLE_SOUNDS.has(event_name):
		var sound: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		sound.stream = STUMBLE_SOUNDS[event_name] as AudioStream
		sound.volume_db = -8.0 if event_name != "thud" else -4.0
		sound.max_distance = 360.0
		add_child(sound)
		sound.finished.connect(sound.queue_free)
		sound.play()
	match event_name:
		"gasp":
			_shake = maxf(_shake, 1.0)
		"thud":
			_shake = maxf(_shake, 3.0)
			_dash_dust.direction = Vector2.UP
			_dash_dust.restart()
			BloodSplat.drop(get_tree().current_scene, global_position + Vector2(randf_range(-6.0, 6.0), randf_range(-2.0, 3.0)), 2)
			BloodSplat.drop(get_tree().current_scene, global_position + Vector2(randf_range(-6.0, 6.0), randf_range(-2.0, 3.0)), 1)
		"cough":
			_shake = maxf(_shake, 1.2)
			BloodSplat.drop(get_tree().current_scene, global_position + Vector2(randf_range(-4.0, 4.0), randf_range(0.0, 3.0)), 1)


## One frame of the faint sheet; west uses its own rendered row.
func show_faint_frame(frame: int, flip: bool) -> void:
	if _sheet != 5:
		_sheet = 5
		fainting = true
		(_sprite.material as ShaderMaterial).set_shader_parameter("blood_map", FAINT_BLOOD)
		_sprite.texture = FAINT_SHEET
		_sprite.hframes = int(FAINT_SHEET.get_width() / 72.0)
		_sprite.vframes = 2
		_sprite.offset = Vector2(0.0, -13.0)
	_sprite.frame_coords = Vector2i(frame, 1 if flip else 0)
	_sprite.flip_h = false
	_sprite.position.y = 0.0


## One story-sitting frame; each direction has its own rendered row.
func show_sit_frame(frame: int, sector: int) -> void:
	if _sheet != 6:
		_sheet = 6
		fainting = true
		(_sprite.material as ShaderMaterial).set_shader_parameter("blood_map", SIT_BLOOD)
		_sprite.texture = SIT_SHEET
		_sprite.hframes = int(SIT_SHEET.get_width() / 72.0)
		_sprite.vframes = 8
		_sprite.offset = Vector2(0.0, -13.0)
	_sprite.frame_coords = Vector2i(frame, clampi(sector, 0, 7))
	_sprite.flip_h = false
	_sprite.position.y = 0.0


## Free sitting uses an independently rendered row for each facing.
func show_rest_frame(frame: int, row: int) -> void:
	if _sheet != 8:
		_sheet = 8
		fainting = true
		(_sprite.material as ShaderMaterial).set_shader_parameter("blood_map", RestComponent.BLOOD)
		_sprite.texture = RestComponent.SHEET
		var rig: Dictionary = DataRegistry.table("hero_rig").rest as Dictionary
		_sprite.hframes = int(rig.cols)
		_sprite.vframes = int(rig.rows)
		_sprite.offset = Vector2(0, -13)
	_sprite.frame_coords = Vector2i(frame, row)
	_sprite.flip_h = false
	_sprite.position.y = 0.0


## One frame of the carry sheet; west uses its own rendered row.
func show_carry_frame(frame: int, flip: bool) -> void:
	if _sheet != 7:
		_sheet = 7
		fainting = true
		(_sprite.material as ShaderMaterial).set_shader_parameter("blood_map", null)
		_sprite.texture = CARRY_SHEET
		_sprite.hframes = int(CARRY_SHEET.get_width() / 72.0)
		_sprite.vframes = 2
		_sprite.offset = Vector2(0.0, -13.0)
	_sprite.frame_coords = Vector2i(frame, 1 if flip else 0)
	_sprite.flip_h = false
	_sprite.position.y = 0.0


## One frame of the wardrobe clip (the opening of her room, RoomIntro): she stands at the wardrobe facing north.
func show_wardrobe_frame(frame: int) -> void:
	if _sheet != 11:
		_sheet = 11
		fainting = true
		(_sprite.material as ShaderMaterial).set_shader_parameter("blood_map", null)
		_sprite.texture = WARDROBE_SHEET
		_sprite.hframes = int(WARDROBE_SHEET.get_width() / 72.0)
		_sprite.vframes = 1
		_sprite.offset = Vector2(0.0, -13.0)
	_sprite.frame_coords = Vector2i(frame, 0)
	_sprite.flip_h = false
	_sprite.position.y = 0.0


## The opening of her room is over: she stands at `at` facing north and the game is hers. No HUD and no quest here (RoomIntro starts the quest).
func end_room_intro(at: Vector2) -> void:
	global_position = at
	intro = null
	end_faint()
	facing = Vector2.UP
	_camera.reset_smoothing()


## Back to the normal sheet.
func end_faint() -> void:
	fainting = false
	_sheet = -1
	_sprite.flip_h = false
	_sprite.offset = Vector2(0.0, -23.0)


## She is out and stands at `at`, facing east; the HUD comes back and the game is hers.
func end_intro(at: Vector2) -> void:
	global_position = at
	intro = null
	facing = Vector2.RIGHT
	_sheet = -1 ## the next _animate puts the normal sheet back
	_sprite.offset = Vector2(0.0, -23.0)
	if _hud != null:
		_hud.call("end_intro") ## the vines grow in
	if quests != null:
		get_tree().create_timer(2.2).timeout.connect(func() -> void: quests.start("find_help")) ## the story's first quest, once the HUD has grown in
	_camera.reset_smoothing()


## The wake-up in the hut is over: she stands at `at`, facing east, the HUD grows in. (No quest starts here: the quest steps carry on.)
func end_wake(at: Vector2) -> void:
	global_position = at
	intro = null
	z_index = 0
	facing = Vector2.RIGHT
	_sheet = -1
	_sprite.offset = Vector2(0.0, -23.0)
	if _hud != null:
		_hud.call("end_intro")
	_camera.reset_smoothing()


## The rescuer's bandage: the wound stops bleeding for the eye (no blood on her, no drops, no red border, no heartbeat); the sprite shader draws the cloth.
func set_bandaged(on: bool) -> void:
	bandaged = on
	(_sprite.material as ShaderMaterial).set_shader_parameter("bandage", 1.0 if on else 0.0)
	bandaged_changed.emit(on)


func _main_sheet_restore() -> void:
	_camera.reset_smoothing()


## The wounded state follows her health with a little hysteresis; everyone sees it.
func _update_wounded(current: float, maximum: float) -> void:
	var share: float = current / maxf(maximum, 1.0)
	var now: bool = current > 0.0 and (share <= WOUND_ENTER or (wounded and share <= WOUND_LEAVE))
	if now == wounded:
		return
	wounded = now
	if now:
		sprinting = false
		_shake = maxf(_shake, 4.0)
	wounded_changed.emit(now)


## How pale and bloody she looks for the health she has (0 healthy .. 1 nearly bled out), starting gently at 80 %.
func _wound_target() -> float:
	if bandaged and health.current > 0.0:
		return 0.0
	if health.current <= 0.0:
		return 1.0
	var t: float = clampf((WOUND_PALE_FROM - health.current / maxf(health.max_health, 1.0)) / (WOUND_PALE_FROM - 0.05), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## The limp: while wounded she drops onto the bad leg every second step (her body dips a pixel, she leans a little towards where she is
## going, hunched), and drips now and then when she stands.
func _animate_limp(delta: float, moving: bool) -> void:
	var dip: float = 0.0
	var lean: float = 0.0
	if wounded:
		lean = 0.055 * signf(facing.x) if absf(facing.x) > 0.3 else 0.0
		if moving:
			var phase: float = _walk_time / float(WALK_FRAMES)
			var on_bad_leg: float = smoothstep(0.42, 0.55, phase) * (1.0 - smoothstep(0.92, 1.0, phase))
			dip = 1.0 * on_bad_leg
			lean += 0.035 * on_bad_leg * signf(facing.x)
		elif not bandaged:
			_drip_timer -= delta
			if _drip_timer <= 0.0:
				_drip_timer = randf_range(2.0, 4.5)
				BloodSplat.drop(get_tree().current_scene, global_position + Vector2(randf_range(-4.0, 4.0), randf_range(-1.0, 1.0)), 1)
	_limp_dip = lerpf(_limp_dip, dip, minf(1.0, 14.0 * delta))
	_sprite.skew = lerpf(_sprite.skew, lean, minf(1.0, 10.0 * delta))


## Cheat menu: sets her health (the host decides, so a client asks).
func request_set_health(value: float) -> void:
	if multiplayer.is_server():
		health.set_health(value)
	else:
		_rpc_set_health.rpc_id(1, value)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_health(value: float) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		health.set_health(value)


func _use_sheet(sheet: int) -> void:
	if sheet == _sheet:
		return
	_sheet = sheet
	(_sprite.material as ShaderMaterial).set_shader_parameter("blood_map", HEAVY_BLOOD if sheet == 11 else (STANDBY_BLOOD if sheet == 9 else (FISH_BLOOD if sheet == 10 else (BLOOD_MAPS[sheet] if sheet < BLOOD_MAPS.size() else null))))
	match sheet:
		1:
			_sprite.texture = ATTACK_SHEET
			_sprite.hframes = ATTACK_COLS
			_sprite.vframes = 8
		2, 3, 4, 5:
			_sprite.texture = PICK_SHEET if sheet == 2 else (EAT_SHEET if sheet == 3 else (TOUCH_SHEET if sheet == 5 else PULL_SHEET))
			_sprite.hframes = PICK_FRAMES * (EAT_VARIANTS if sheet == 3 else 1)
			_sprite.vframes = 8
		11:
			_sprite.texture = HEAVY_SHEET
			_sprite.hframes = HEAVY_COLS
			_sprite.vframes = 8
		10:
			_sprite.texture = FISH_SHEET
			_sprite.hframes = int((DataRegistry.table("hero_rig").get("fish", {}) as Dictionary).get("cols", 1))
			_sprite.vframes = 8
		9:
			_sprite.texture = STANDBY_SHEET
			_sprite.hframes = STANDBY_COLS
			_sprite.vframes = 8
		_:
			_sprite.texture = _main_sheet
			_sprite.hframes = SHEET_COLS
			_sprite.vframes = 16


## Spawn/load initializes blood and pallor immediately; ordinary healing still fades them.
func sync_wound_visuals() -> void:
	_update_wounded(health.current, health.max_health)
	_wound = _wound_target()
	(_sprite.material as ShaderMaterial).set_shader_parameter("wound", _wound)
	attack.wound = _wound
