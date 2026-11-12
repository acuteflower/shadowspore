class_name AttackComponent
extends Node2D
## Swings the equipped main-hand weapon toward the cursor. Holding the button chains the weapon
## class's combo (data/weapon_classes.json). Visuals run on every peer; hit detection and damage
## run on the host only.

signal combo_stage(weapon: String, stage: int) ## host-confirmed active swing, owner only

signal lunged(impulse: Vector2) ## owner only: a small step into the swing
signal hit_landed(shake: float) ## owner only: the swing connected
signal charge_stage(stage: int) ## every peer: 0 charging started / dropped, 1 worth releasing, 2 fully charged
signal heavy_struck(power: float) ## owner only: the heavy blow was let loose

enum Phase { IDLE, WINDUP, ACTIVE, RECOVERY }

const BODY_CENTER: Vector2 = Vector2(0, -24)
const HURTBOX_MASK: int = 1 << 4 ## physics layer 5
const HAND_SORT: float = 6.0 ## px in front of / behind the player's own y
const TRAIL_FADE: float = 0.2 ## seconds
const TRAIL_STEPS: int = 14
const TRAIL_EDGE: Color = Color("aac8ff")
const TRAIL_CORE: Color = Color("f2f7ff")
const MOTE_COLORS: Array[Color] = [Color("f2f7ff"), Color("aac8ff"), Color("c9a8ff"), Color("8a5cf0")] ## what a swing sheds: white, ice, lilac, violet
const MOTES_PER_SEC: float = 110.0
const BURST_LIFE: float = 0.2 ## seconds the shock crescent at the end of a swing lasts
const SPARK_TEXTURE: Texture2D = preload("res://assets/fx/puff.png")
const DEPTH_SQUASH: float = GripRig.SINP ## how much a direction toward the camera is shortened on screen (the hero renderer's camera)
const ROT_ANGLES: int = 48 ## the held sprite is pre-rotated (tools/art_weapons.py): 48 steps around the circle,
const ROT_LENGTHS: Array[float] = [0.4, 0.52, 0.64, 0.76, 0.88, 1.0] ## and 6 foreshortenings along the shaft (rows)
const OUT_OF_COMBAT: float = 10.0 ## seconds after the last swing until the weapon is put away
const BLADE_PX: float = 22.0 ## grip to tip of the held blade on screen at full length (heavy trail, charge motes)
const CHOP_PITCH_REST: float = deg_to_rad(32.0) ## the heavy blow: blade height above the horizon at rest ...
const CHOP_PITCH_UP: float = deg_to_rad(104.0) ## ... lifted over the shoulder (above 90 = leaning back) ...
const CHOP_PITCH_WIND: float = deg_to_rad(116.0) ## ... pulled a little further back in the instant before the blow ...
const CHOP_PITCH_END: float = deg_to_rad(-28.0) ## ... and driven down past the target
const CHOP_YAW_BACK: float = 0.6 ## radians toward her sword side while charging ...
const CHOP_YAW_WIND: float = 0.72
const CHOP_YAW_END: float = -0.35 ## ... and across to the other side at the end: a diagonal chop
const HEAVY_BURST_LIFE: float = 0.38
const HEAVY_TRAIL_LIFE: float = 0.22
const HEAVY_SOUNDS: String = "res://assets/audio/heavy/"

@export var inventory: InventoryComponent

var facing: Vector2 = Vector2.DOWN ## set by the player every frame
var rig_shoulder: Vector2 = Vector2(-4.0, -31.0) ## right shoulder and natural hand, relative to the feet,
var rig_hand: Vector2 = Vector2(-5.0, -21.0) ## from the current sheet frame (set by the player every frame)
var carrying: bool = false ## sprinting: the blade trails behind the runner
var body_dir: Vector2 = Vector2.DOWN ## the facing the body sheet shows (its sector), set by the player every frame: the item rests relative to it
var free_hand: bool = true ## the main sheet plays (no clip owns the hand): the fist may leave the natural hand for the item's own hold (set by the player)
var _dir: Vector3 = Vector3(1.0, 0.0, 0.0) ## where the held item points in GripRig space (docs/griff_system.md)
var _yaw: float = 0.0 ## the same as compass angle and pitch, with their speeds: the resting item is a damped spring on these
var _pitch: float = 0.0
var _yaw_v: float = 0.0
var _pitch_v: float = 0.0
var _swing_from: Vector3 = Vector3(1.0, 0.0, 0.0) ## the item's direction when the current swing, blow or charge began
var _shape: Dictionary = {} ## the current swing's shape (GripRig.swing_of)
var _style: Dictionary = {} ## how the held item rests (GripRig.style_of)
var _ready_k: float = 0.0 ## 0 relaxed carry .. 1 ready (just swung)
var _sprint_k: float = 0.0
var _free_k: float = 1.0 ## how much the item's own hold moves the fist away from the sheet's hand
var _hold_k: float = 0.0 ## 0 empty hand .. 1 holding something visible
var _hand_vel: Vector2 = Vector2.ZERO ## the fist's screen speed (its change swings the resting tip)
var _prev_hand: Vector2 = Vector2.INF
var _weapon_behind: bool = false
var _arm_behind: bool = false
var _theta_from: float = 0.0 ## the slash's sweep from its first to its current angle (the trail follows the real path)
var _theta_head: float = 0.0
var _shoulder3: Vector3 = Vector3.ZERO ## the arm as solved this frame (ArmPainter)
var _elbow3: Vector3 = Vector3.ZERO
var _wrist3: Vector3 = Vector3.ZERO
var _fist3: Vector3 = Vector3.ZERO
var _flip: bool = false ## the item is shown mirrored across its own axis (the other side of a tool with an edge: data/grips.json `edge`, `upright`)
var _flip_wait: float = 0.0
var _swing_flip: bool = false ## during a swing: mirrored so that the working edge leads
var _arm_sort: Node2D ## the arm sorts on its own: a near arm can hold a blade that points behind her
var _arm_key: PackedFloat32Array = PackedFloat32Array() ## the arm pose last painted
var _skin: ShaderMaterial ## the player's sprite shader, mirrored onto the arm and the item (mirror_material)
var sheathed: bool = false ## set by the player while sneaking: the weapon fades out, and in again for a swing
var aim_dir: Vector2 = Vector2.RIGHT ## direction of the current swing
var rod_pose: Vector3 = Vector3.INF ## fishing: how the rod points (forward, side, lift) relative to where she faces, from the body clip; INF = resting pose
var always_drawn: bool = false ## a rod stays in the hand (it is no weapon: no swings, never put away)
var _staff: bool = false ## a magic staff is in her hand (docs/magie_konzept.md): its crystals are drawn by StaffCrystals
var held_weapon: String = "": ## item id shown in the hand, synced by the owner
	set(value):
		held_weapon = value
		_refresh_weapon()
var _blade_angle: float = 0.0 ## the blade's angle and length factor as the pose put them this frame (refinement glints run along it)
var _blade_scale: float = 1.0
var _edge_clock: float = 0.0
var held_refine: int = 0 ## its refinement level (RefineRules), synced with it: every peer draws the same reach and tempo

var _since_swing: float = OUT_OF_COMBAT + 1.0 ## seconds since the last swing; the weapon starts put away
var _phase: Phase = Phase.IDLE
var _time: float = 0.0
var _step: Dictionary = {} ## the combo step being swung
var _reach: float = 22.0
const MAX_MOTES: int = 90
static var _spark_gradient: Gradient = null
static var _sparks_pool: Array[CPUParticles2D] = []

var _has_weapon: bool = false
var _weapon_alpha: float = 1.0
var _rest_angle: float = 0.0 ## blade angle at rest, eased between ready and sprint carry
var _rest_length: float = 1.0 ## blade length factor at rest (a blade pointing at the camera looks short)
var _grip: Vector2 = Vector2.ZERO ## where the hand holds the weapon, relative to the feet
var _trail_head: float = 0.0 ## how far the blade has swept (radians from the arc's start)
var _trail_age: float = TRAIL_FADE ## >= TRAIL_FADE means hidden
var _thrust_progress: float = 0.0
var _motes: Array[Dictionary] = [] ## sparkles shed by the blade: {pos (world), vel, age, life, kind, color, size}
var _mote_carry: float = 0.0
var _trail_was_active: bool = false
var _burst_age: float = BURST_LIFE ## the crescent / ring where a swing ends; >= BURST_LIFE means hidden
var _burst_done: bool = true
var _burst_angle: float = 0.0
var _burst_center: Vector2 = Vector2.ZERO
var _burst_thrust: bool = false
var _combo_index: int = 0
var _combo_window: float = 0.5
var _combo_deadline_msec: int = 0
var _server_combo_index: int = 0
var _server_combo_until: int = 0
var _server_ready_msec: int = 0
var _charging: bool = false ## the secondary attack is being charged (every peer)
var _charge_time: float = 0.0
var _charge_cfg: Dictionary = {} ## the weapon class's `secondary` block of the charging weapon
var _charge_chained: bool = false ## started right after a light hit (shorter minimum)
var _charge_stage: int = 0
var _charge_carry: float = 0.0
var _release_key: float = 2.0 ## heavy-sheet key where the blow started
var _release_pitch: float = CHOP_PITCH_UP
var _release_yaw: float = CHOP_YAW_BACK
var _freeze: float = 0.0 ## seconds the whole swing stands still (hit stop)
var _server_charge_msec: int = 0
var _alt_stage: int = 0 ## owner: the Himmelsriss's right-click chain: the slash last started (1 or 2, 0 = none)
var _alt_deadline_msec: int = 0 ## owner: until when a second right click still makes the second slash
var _alt_buffer_msec: int = 0 ## owner: a right click during the first slash's recovery waits here for it to end
var _alt_buffer_dir: Vector2 = Vector2.RIGHT
var _server_alt_stage: int = 0 ## host: the same chain as the host saw it
var _server_alt_until: int = 0
var _blade_length: float = 1.0
var _emit_kind: int = 0 ## the pose asks for motes this frame: 1 a cut, 2 a thrust
var _last_tip: Vector2 = Vector2.ZERO ## the tip one frame ago (world px): motes fly on the way it moved
var _tips: Array[Dictionary] = [] ## the heavy blow's path: {mid (world), tip (world), age}
var _burst_life: float = BURST_LIFE
var _burst_heavy: bool = false
var _flash: float = 0.0 ## the fully-charged flash at the tip (seconds left)
var _sounds: Dictionary = {}
var _fx_colors: Array[Color] = MOTE_COLORS.duplicate() ## what this weapon sheds (item `fx.motes`), its trail (`fx.trail_edge/core`) and where its own sounds live (`fx.sounds`)
var _trail_edge: Color = TRAIL_EDGE
var _trail_core: Color = TRAIL_CORE
var _sound_dir: String = ""
var _stamina: StaminaComponent
var _talismans: TalismanComponent ## damage and charge speed of the worn jewellery
var _skills: SkillTreeComponent ## which combo steps are learned (data/skills.json upgrades)

@onready var _hand: Node2D = $Hand ## its y decides if the sword is drawn in front of or behind the body
@onready var _weapon: Sprite2D = $Hand/Weapon
var wound: float = 0.0 ## 0..1 blood loss (set by the player)
@onready var _arm: Node2D = $Hand/Arm ## draws the sword arm after the weapon, so the glove covers the grip
@onready var _trail: Node2D = $Trail


func _ready() -> void:
	if inventory == null:
		inventory = get_node("../InventoryComponent") as InventoryComponent
	_trail.draw.connect(_draw_trail)
	_arm.draw.connect(_draw_arm)
	_arm_sort = Node2D.new()
	_arm_sort.name = "ArmSort"
	add_child(_arm_sort)
	move_child(_arm_sort, _hand.get_index() + 1)
	_arm.reparent(_arm_sort, false)
	_stamina = get_node_or_null("../StaminaComponent") as StaminaComponent
	_talismans = get_node_or_null("../TalismanComponent") as TalismanComponent
	_skills = get_node_or_null("../SkillTreeComponent") as SkillTreeComponent
	var crystals: StaffCrystals = StaffCrystals.new() ## the stones in a held magic staff (docs/magie_konzept.md)
	crystals.name = "StaffCrystals"
	crystals.attack = self
	_weapon.get_parent().add_child(crystals)
	_refresh_weapon()


func _process(delta: float) -> void:
	if _freeze > 0.0:
		_freeze -= delta ## hit stop: the swing stands still for a moment, the world runs on
	else:
		_advance(delta)
		if _charging:
			_charge_time += delta * _charge_rate()
			_charge_effects(delta)
	_update_pose(delta)
	_track_tips(delta)
	_flash = maxf(_flash - delta, 0.0)
	if _phase == Phase.ACTIVE and not bool(_step.get("heavy", false)):
		_trail_age = 0.0
	elif _trail_age < TRAIL_FADE:
		_trail_age += delta
	_edge_glints(delta)
	_update_motes(delta)
	var trail_active: bool = _is_trail_active()
	if trail_active or _trail_was_active:
		_trail.queue_redraw()
	_trail_was_active = trail_active


func _is_trail_active() -> bool:
	if _trail_age < TRAIL_FADE:
		return true
	if not _motes.is_empty():
		return true
	if _tips.size() >= 2:
		return true
	if _burst_age < _burst_life:
		return true
	if _charging:
		return true
	if held_refine >= RefineRules.max_level() and _has_weapon and _weapon_alpha >= 0.4 and not always_drawn:
		return true
	return false


func is_swinging() -> bool:
	return _phase != Phase.IDLE


## True while the secondary attack is being charged.
func is_charging() -> bool:
	return _charging


## 0..1 how strong the blow would be now (0 until it is worth releasing); the cursor and the effects read this.
func charge_amount() -> float:
	return HeavyRules.power(_charge_cfg, _charge_time, _charge_chained) if _charging else 0.0


## 0..1 how far the draw-back is (shows before the blow is ready).
func charge_draw() -> float:
	return HeavyRules.draw_progress(_charge_cfg, _charge_time) if _charging else 0.0


## Walking speed factor while the charge is held (1 when not charging).
func charge_move_factor() -> float:
	return float(_charge_cfg.get("move_factor", 0.4)) if _charging else 1.0


func charge_ready() -> bool:
	return _charging and HeavyRules.is_ready(_charge_cfg, _charge_time, _charge_chained)


## True during a heavy blow (windup to recovery).
func is_heavy_swing() -> bool:
	return _phase != Phase.IDLE and bool(_step.get("heavy", false))


## How much louder than a normal swing the blow is heard (1 = normal).
func noise_scale() -> float:
	return float(_step.get("noise", 1.0)) if is_heavy_swing() or _is_diag() else 1.0


## A diagonal slash of the right-click chain is being swung (the blade follows its own path, `_step.diag`).
func _is_diag() -> bool:
	return _phase != Phase.IDLE and _step.has("diag")


## How fast the heavy blow charges: a talisman's Aufladetempo up to the full charge, then in real time.
func _charge_rate() -> float:
	if _talismans == null or _charge_time >= float(_charge_cfg.get("charge_full", 1.0)):
		return 1.0
	return _talismans.charge_rate()


## Key position on the heavy sheet for the body animation (0..HEAVY_KEYS - 1), or -1 when the heavy attack does not play.
func heavy_key() -> float:
	if _charging:
		return HeavyRules.charge_key(_charge_cfg, _charge_time)
	if not is_heavy_swing():
		return -1.0
	match _phase:
		Phase.WINDUP:
			return lerpf(_release_key, 4.0, clampf(_time / float(_step["windup"]), 0.0, 1.0))
		Phase.ACTIVE:
			return 4.0 + 2.0 * pow(clampf(_time / float(_step["active"]), 0.0, 1.0), 1.5)
		_:
			var t: float = clampf(_time / float(_step["recovery"]), 0.0, 1.0)
			return 6.0 + t / 0.15 if t < 0.15 else 7.0 + 2.0 * (t - 0.15) / 0.85


## True while an attack animation is active or shortly after the last swing.
func is_in_combat(timeout: float = 1.5) -> bool:
	return _phase != Phase.IDLE or _charging or _since_swing < timeout


## For the body animation: x = which attack (0 forehand, 1 backhand, 2 thrust, 3 and 4 the learned combo steps from player_combo.png), y = keyframe position
## (-1..0 winding up into the first pose, 0..3 striking, 3..5 recovering). Zero when not swinging.
func animation_state() -> Vector2:
	if _phase == Phase.IDLE or _step.is_empty() or bool(_step.get("heavy", false)):
		return Vector2.ZERO
	var block: float = 2.0 if String(_step["style"]) == "thrust" else (0.0 if float(_step["sweep"]) < 0.0 else 1.0)
	if int(_step.get("block", -1)) >= 3:
		block = float(_step["block"])
	var key: float = 0.0
	match _phase:
		Phase.WINDUP:
			key = clampf(_time / float(_step["windup"]), 0.0, 1.0) - 1.0
		Phase.ACTIVE:
			var t: float = clampf(_time / float(_step["active"]), 0.0, 1.0)
			key = 3.0 * (1.0 - pow(1.0 - t, 3.0)) ## the same easing as the blade
		Phase.RECOVERY:
			key = 3.0 + 2.0 * clampf(_time / float(_step["recovery"]), 0.0, 1.0)
	return Vector2(block, key)


func can_attack() -> bool:
	return _phase == Phase.IDLE and held_weapon != "" and not always_drawn and not _charging


## The held weapon has a secondary attack and she has the strength to start it.
func can_charge() -> bool:
	if not can_attack():
		return false
	var cfg: Dictionary = HeavyRules.config(DataRegistry.get_entry("items", held_weapon))
	return String(cfg.get("kind", "")) == HeavyRules.KIND_CHARGE and (_stamina == null or HeavyRules.can_start(cfg, _stamina.current))


## A magic staff is in her hand (docs/magie_konzept.md).
func holds_staff() -> bool:
	return _staff


## A point on the held item `px` along its shaft from the grip (item picture px), in the frame of the `Hand` node (StaffCrystals draws there).
func blade_point(px: float) -> Vector2:
	return _weapon.position + Vector2.from_angle(_blade_angle) * _blade_length * px


## A point of the held item off its shaft: `along` px from the grip, `across` px to the side (+ = downwards in the item picture, which points
## right), in the frame of the `Hand` node. The foreshortening only shortens the length (the Bleichgabel's two prongs, StaffCrystals).
func item_point(along: float, across: float) -> Vector2:
	return blade_point(along) + Vector2.from_angle(_blade_angle + PI * 0.5) * across

## How visible the held item is right now (0 hidden .. 1).
func weapon_alpha() -> float:
	return _weapon_alpha if _weapon != null and _weapon.visible else 0.0


## Where the far end of the held item is (world px): a rod's tip, where the line starts. `length_px` = grip to tip in the item picture.
func tip_position(length_px: float) -> Vector2:
	return _weapon.global_position + Vector2.from_angle(_rest_angle) * _rest_length * length_px * _weapon.global_scale.x


## Owner only: starts the next swing of the combo everywhere and asks the host to score it.
func attack(dir: Vector2) -> void:
	if not can_attack():
		return
	var def: Dictionary = DataRegistry.get_entry("items", held_weapon)
	var count: int = _combo_size(def)
	if count == 0:
		return
	if _combo_index >= count or Time.get_ticks_msec() > _combo_deadline_msec:
		_combo_index = 0
	var step: int = _combo_index
	_combo_index += 1
	dir = dir.normalized()
	_swing.rpc(dir, held_weapon, step, held_refine)
	if multiplayer.is_server():
		_server_swing(dir, step)
	else:
		_rpc_server_swing.rpc_id(1, dir, step)


## The held weapon's right click is a chain of slashes (the Himmelsriss) and she may start one now.
func can_alt() -> bool:
	if not can_attack():
		return false
	var cfg: Dictionary = HeavyRules.config(DataRegistry.get_entry("items", held_weapon))
	return HeavyRules.is_rift_slash(cfg) and (_stamina == null or _stamina.current >= HeavyRules.rift_cost(cfg, 1))


## Owner only: the right mouse button went down on a weapon with a slash chain. Starts the first slash, or the second when it follows the first in time;
## pressed during the first one it waits until that has ended (nothing is lost by pressing a little early).
func alt_press(dir: Vector2) -> void:
	var cfg: Dictionary = HeavyRules.config(DataRegistry.get_entry("items", held_weapon))
	if not HeavyRules.is_rift_slash(cfg):
		return
	dir = dir.normalized() if dir != Vector2.ZERO else aim_dir
	if _phase != Phase.IDLE:
		if bool(_step.get("alt", false)) and int(_step.get("stage", 0)) == 1:
			_alt_buffer_msec = Time.get_ticks_msec()
			_alt_buffer_dir = dir
		return
	if held_weapon == "" or always_drawn or _charging:
		return
	_alt_start(cfg, dir)


func _alt_start(cfg: Dictionary, dir: Vector2) -> void:
	var stage: int = 2 if _alt_stage == 1 and Time.get_ticks_msec() <= _alt_deadline_msec else 1
	if _stamina != null and not _stamina.spend(HeavyRules.rift_cost(cfg, stage)):
		return
	_alt_stage = stage
	_alt_buffer_msec = 0
	aim_dir = dir
	_alt_swing.rpc(dir, held_weapon, stage, held_refine)
	if multiplayer.is_server():
		_server_alt(dir, stage)
	else:
		_rpc_server_alt.rpc_id(1, dir, stage)


## The step of the chain for a stack (times scaled by its own speed, a refined weapon is faster).
func _alt_step(stack: Dictionary, stage: int) -> Dictionary:
	var cfg: Dictionary = HeavyRules.config(Items.definition(stack))
	return HeavyRules.rift_step(cfg, {"stats": {"speed": Items.stat(stack, "speed", 1.0)}}, stage)


@rpc("authority", "call_local", "reliable")
func _alt_swing(dir: Vector2, weapon_id: String, stage: int, refine_level: int = 0) -> void:
	var stack: Dictionary = _stack_of(weapon_id, refine_level)
	var step: Dictionary = _alt_step(stack, stage)
	if step.is_empty():
		return
	_step = step
	_reach = Items.stat(stack, "reach", 22.0) * float(step["reach"])
	_combo_window = 0.5
	_combo_index = 0
	aim_dir = dir
	_charging = false
	_phase = Phase.WINDUP
	_time = 0.0
	_swing_from = _dir
	_trail_age = TRAIL_FADE
	_trail_head = -float(step["arc"]) / 2.0
	_thrust_progress = 0.0
	_burst_done = true ## the ribbon and the feathers are its flourish, no crescent
	_tips.clear()
	_play_sound("swing", -3.0, 1.0 if stage == 1 else 0.86)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_server_alt(dir: Vector2, stage: int) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		_server_alt(dir, stage)


## Host: scores a slash of the chain after its wind-up. The second slash only counts right after the first.
func _server_alt(dir: Vector2, stage: int) -> void:
	var now: int = Time.get_ticks_msec()
	var stack: Dictionary = inventory.active_stack()
	if now < _server_ready_msec or stack.is_empty() or dir == Vector2.ZERO:
		return
	if stage == 2 and (_server_alt_stage != 1 or now > _server_alt_until):
		return
	var step: Dictionary = _alt_step(stack, stage)
	if step.is_empty():
		return
	_server_alt_stage = stage
	_server_alt_until = now + int((float(step["windup"]) + float(step["active"]) + float(step["recovery"]) + HeavyRules.rift_window(HeavyRules.config(Items.definition(stack)))) * 1000.0)
	_server_combo_index = 0
	_server_combo_until = 0
	_server_ready_msec = now + int((float(step["windup"]) + float(step["active"]) + float(step["recovery"]) * 0.5) * 1000.0)
	await get_tree().create_timer(float(step["windup"])).timeout
	await get_tree().physics_frame
	if is_inside_tree() and (get_parent() as Player).health.current > 0 and _phase != Phase.IDLE:
		_hit_scan(dir.normalized(), step, stack)


## Owner only: the right mouse button went down. Starts charging the weapon's secondary attack everywhere.
func begin_charge(dir: Vector2) -> void:
	if not can_charge():
		return
	var chained: bool = _combo_index > 0 and Time.get_ticks_msec() <= _combo_deadline_msec
	aim_dir = dir.normalized() if dir != Vector2.ZERO else aim_dir
	_charge_begin.rpc(held_weapon, chained)
	if multiplayer.is_server():
		_server_charge_msec = Time.get_ticks_msec()
	else:
		_rpc_server_charge.rpc_id(1)


## Owner only, every frame while charging: keeps the aim and pays for holding too long. Returns false once the charge ended
## (the blow was let loose or dropped).
func charge_input(held: bool, ui_took_over: bool, dir: Vector2, delta: float) -> bool:
	if not _charging:
		return false
	if dir != Vector2.ZERO:
		aim_dir = dir.normalized()
	if not held:
		if ui_took_over:
			cancel_charge()
		else:
			release_charge(aim_dir)
		return false
	if HeavyRules.overcharge(_charge_cfg, _charge_time) > 0.0 and _stamina != null: ## holding at full strength wears her out, but never below what the blow costs
		var spare: float = _stamina.current - HeavyRules.stamina_cost(_charge_cfg)
		if spare > 0.0:
			_stamina.spend(minf(float(_charge_cfg.get("overcharge_drain", 8)) * delta, spare))
	if HeavyRules.must_release(_charge_cfg, _charge_time):
		release_charge(aim_dir)
		return false
	return true


## Owner only: lets the blow go (or drops the charge when it is too short, or the stamina is gone). Strength comes from the time held.
func release_charge(dir: Vector2) -> void:
	if not _charging:
		return
	var cfg: Dictionary = _charge_cfg
	var time: float = _charge_time
	var chained: bool = _charge_chained
	if not HeavyRules.is_ready(cfg, time, chained) or (_stamina != null and not _stamina.spend(HeavyRules.stamina_cost(cfg))):
		cancel_charge()
		return
	dir = dir.normalized() if dir != Vector2.ZERO else aim_dir
	_heavy_swing.rpc(dir, held_weapon, time, chained)
	heavy_struck.emit(HeavyRules.power(cfg, time, chained))
	if multiplayer.is_server():
		_server_heavy(dir, time, chained)
	else:
		_rpc_server_heavy.rpc_id(1, dir, time, chained)


## Owner only: she lowers the blade again (button let go too early, a dodge, a menu, a cutscene). Nothing is paid.
func cancel_charge() -> void:
	if _charging:
		_charge_cancel.rpc()


## Owner only: the shadow step tears her out of whatever the weapon is doing (a swing in any phase, a charge, the right-click chain):
## it stops on every peer, and the host's pending hit scan finds the swing idle, so no blow lands. Nothing is paid.
func cancel_action() -> void:
	_alt_stage = 0
	_alt_buffer_msec = 0
	if _charging:
		_charge_cancel.rpc()
	if _phase != Phase.IDLE:
		_swing_cancel.rpc()


@rpc("authority", "call_local", "reliable")
func _swing_cancel() -> void:
	_phase = Phase.IDLE
	_time = 0.0
	_freeze = 0.0
	_combo_index = 0
	_burst_done = true
	_server_combo_index = 0
	_server_ready_msec = 0 ## the host lets her swing again right after the step


## Owner only: a hit while charging breaks it and costs a little stamina.
func interrupt_charge() -> void:
	if not _charging:
		return
	if _stamina != null:
		_stamina.spend(minf(float(_charge_cfg.get("interrupt_cost", 10)), _stamina.current))
	_charge_cancel.rpc()


@rpc("authority", "call_local", "reliable")
func _charge_begin(weapon_id: String, chained: bool) -> void:
	var cfg: Dictionary = HeavyRules.config(DataRegistry.get_entry("items", weapon_id))
	if cfg.is_empty():
		return
	_charge_cfg = cfg
	_charging = true
	_charge_time = 0.0
	_charge_chained = chained
	_charge_stage = 0
	_charge_carry = 0.0
	_swing_from = _dir
	_play_sound("draw", -6.0)
	charge_stage.emit(0)


@rpc("authority", "call_local", "reliable")
func _charge_cancel() -> void:
	if _charging:
		_charging = false
		_charge_stage = 0
		charge_stage.emit(0)
		_play_sound("drop", -10.0)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_server_charge() -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		_server_charge_msec = Time.get_ticks_msec()


@rpc("authority", "call_local", "reliable")
func _heavy_swing(dir: Vector2, weapon_id: String, charge_time: float, chained: bool) -> void:
	var def: Dictionary = DataRegistry.get_entry("items", weapon_id)
	var cfg: Dictionary = HeavyRules.config(def)
	var step: Dictionary = HeavyRules.step(cfg, def, charge_time, chained)
	if step.is_empty():
		return
	_release_key = HeavyRules.charge_key(cfg, charge_time)
	var draw: float = HeavyRules.draw_progress(cfg, charge_time)
	var ease_draw: float = draw * draw * (3.0 - 2.0 * draw)
	_release_pitch = lerpf(CHOP_PITCH_REST, CHOP_PITCH_UP, ease_draw)
	_release_yaw = lerpf(0.2, CHOP_YAW_BACK, ease_draw)
	_charging = false
	_charge_stage = 0
	_step = step
	_reach = float(def.get("stats", {}).get("reach", 22)) * float(step["reach"])
	_combo_window = 0.5
	_combo_index = 0
	aim_dir = dir
	_phase = Phase.WINDUP
	_time = 0.0
	_swing_from = _dir
	_trail_age = TRAIL_FADE
	_thrust_progress = 0.0
	_burst_done = false
	_tips.clear()
	var swing_pitch: float = 0.92 + 0.16 * float(step["power"])
	if _sound_dir.is_empty() and Sfx.has("sword_swing_a"): ## the shared set; a weapon with its own sounds (item `fx.sounds`) keeps them
		Sfx.at(self, "sword_swing_b" if float(step["sweep"]) > 0.0 and String(step["style"]) != "thrust" else "sword_swing_a", global_position, -2.0, 0.04)
	else:
		_play_sound("swing", -3.0, swing_pitch)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_server_heavy(dir: Vector2, charge_time: float, chained: bool) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		_server_heavy(dir, charge_time, chained)


## Host: checks what the owner claims against its own clock, then scores the blow like a swing (after its wind-up).
func _server_heavy(dir: Vector2, claimed: float, chained: bool) -> void:
	var now: int = Time.get_ticks_msec()
	var stack: Dictionary = inventory.active_stack()
	if now < _server_ready_msec or stack.is_empty() or dir == Vector2.ZERO:
		return
	var def: Dictionary = Items.definition(stack)
	var cfg: Dictionary = HeavyRules.config(def)
	if cfg.is_empty():
		return
	var seen: float = float(now - _server_charge_msec) / 1000.0 if _server_charge_msec > 0 else 0.0
	if _talismans != null:
		seen = HeavyRules.scaled_time(seen, cfg, _talismans.charge_rate()) ## the owner's clock ran faster up to the full charge
	var time: float = HeavyRules.host_charge(claimed, seen, cfg)
	if not HeavyRules.is_ready(cfg, time + 0.05, chained):
		return
	var step: Dictionary = HeavyRules.step(cfg, def, time, chained)
	_server_charge_msec = 0
	_server_combo_index = 0
	_server_combo_until = 0
	_server_ready_msec = now + int((float(step["windup"]) + float(step["active"]) + float(step["recovery"]) * 0.5) * 1000.0)
	await get_tree().create_timer(float(step["windup"])).timeout
	await get_tree().physics_frame
	if is_inside_tree() and (get_parent() as Player).health.current > 0 and _phase != Phase.IDLE:
		_hit_scan(dir.normalized(), step, def.get("stats", {}))


@rpc("authority", "call_local", "reliable")
func _swing(dir: Vector2, weapon_id: String, step_index: int, refine_level: int = 0) -> void:
	var def: Dictionary = DataRegistry.get_entry("items", weapon_id)
	var stack: Dictionary = _stack_of(weapon_id, refine_level)
	_step = _step_data(stack, step_index)
	if _step.is_empty():
		return
	_reach = Items.stat(stack, "reach", 22.0) * float(_step["reach"])
	_combo_window = float(DataRegistry.get_entry("weapon_classes", String(def.get("weapon_class", ""))).get("combo_window", 0.5))
	aim_dir = dir
	_charging = false
	_phase = Phase.WINDUP
	_time = 0.0
	_swing_from = _dir
	_shape = GripRig.swing_of(String(def.get("weapon_class", "")), int(_step.get("block", -1)))
	_swing_flip = _edge_leads()
	_trail_age = TRAIL_FADE
	_trail_head = -float(_step["arc"]) / 2.0
	_thrust_progress = 0.0
	_burst_done = false


@rpc("any_peer", "call_remote", "reliable")
func _rpc_server_swing(dir: Vector2, step_index: int) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		_server_swing(dir, step_index)


func _server_swing(dir: Vector2, step_index: int) -> void:
	var now: int = Time.get_ticks_msec()
	var stack: Dictionary = inventory.active_stack()
	if now < _server_ready_msec or stack.is_empty() or dir == Vector2.ZERO:
		return
	var def: Dictionary = Items.definition(stack)
	var step: Dictionary = _step_data(stack, step_index)
	if step.is_empty():
		return
	if step_index != 0 and (step_index != _server_combo_index or now > _server_combo_until): return
	if not _step_unlocked(step): return ## a combo step she has not learned (a modified client cannot swing it)
	_server_combo_index = step_index + 1
	var combo_window: float = float(DataRegistry.get_entry("weapon_classes", String(def.get("weapon_class", ""))).get("combo_window", 0.5))
	_server_combo_until = now + int((float(step["windup"]) + float(step["active"]) + float(step["recovery"]) + combo_window) * 1000)
	_server_ready_msec = now + int((float(step["windup"]) + float(step["active"]) + float(step["recovery"]) * 0.5) * 1000.0) ## anti-spam only; slack for network jitter
	await get_tree().create_timer(float(step["windup"])).timeout
	await get_tree().physics_frame
	if is_inside_tree() and (get_parent() as Player).health.current > 0 and _phase != Phase.IDLE:
		_confirm_stage.rpc_id(get_multiplayer_authority(), String(stack.id), step_index)
		_hit_scan(dir.normalized(), step, stack)


## Hits every hurtbox inside the swing's fan once, then tells everyone where it connected.
func _hit_scan(dir: Vector2, step: Dictionary, stack: Dictionary) -> void:
	var origin: Vector2 = global_position + BODY_CENTER
	var damage: float = Items.stat(stack, "damage", 1.0) * float(step["damage"]) ## the stack's own stats: a refined weapon hits harder
	if _talismans != null:
		damage *= _talismans.damage_factor(bool(step.get("heavy", false))) ## Wuchtreif and the like (host: from its own copy of her bag)
		damage *= _talismans.dive_factor() ## Rissfeder: the first blow after a blink
	var knockback: float = Items.stat(stack, "knockback", 0.0) * float(step["knock"])
	var targets: Array[HurtboxComponent] = HitScan.fan(self, origin, dir, Items.stat(stack, "reach", 20.0) * float(step["reach"]), float(step["arc"]), HURTBOX_MASK)
	for target: HurtboxComponent in targets:
		target.armor_floor = float(step.get("armor_floor", 0.0))
		target.take_hit(damage, origin, knockback, get_multiplayer_authority())
		target.armor_floor = 0.0
	if not targets.is_empty():
		if _talismans != null:
			_talismans.spend_dive() ## it connected: the dive is used up
		_on_hit.rpc(_hit_point(targets[0]), dir, float(step["shake"]), float(step.get("hit_stop", 0.0)))
	_rift(origin, dir, step, stack, damage, targets)


## Host: what the Himmelsriss adds to a blow (docs/rissklinge.md): the thrust of the combo (`rift` "line") throws a short lane of light, a slash of the right-click
## chain (`volley`) shoots a fan of feathers from the blade's tip. `damage` is what the blow itself did to each target.
func _rift(origin: Vector2, dir: Vector2, step: Dictionary, stack: Dictionary, damage: float, already: Array[HurtboxComponent]) -> void:
	var unit: float = damage / maxf(float(step["damage"]), 0.01) ## the weapon's own strength, not the blow's bonus
	if step.has("volley"):
		_volley(origin, dir, step, stack, unit)
		return
	if String(step.get("rift", "")) != "line":
		return
	var class_cfg: Dictionary = DataRegistry.get_entry("weapon_classes", String(Items.definition(stack).get("weapon_class", "")))
	var cfg: Dictionary = HeavyRules.rift_data(class_cfg.get("secondary", {}) as Dictionary, "passive")
	if cfg.is_empty():
		return
	var length: float = float(cfg.get("length", 100.0))
	var half: float = float(cfg.get("width", 12.0)) * 0.5
	_rift_fx.rpc(origin, dir, length, float(cfg.get("life", 0.5)))
	for target: HurtboxComponent in HitScan.lane(self, origin, dir, length, half, HURTBOX_MASK):
		if not already.has(target):
			target.take_hit(unit * float(cfg.get("ratio", 0.5)), origin, Items.stat(stack, "knockback", 0.0) * float(cfg.get("knock", 1.0)), get_multiplayer_authority())


## Host: the feathers of a slash. A fan of narrow lanes from the blade's tip; a feather that meets something stops there (the fx gets the distance). Everyone a feather
## hits takes `ratio` of the weapon's damage per feather, up to `max_hits` of them (close to her the fan is a shotgun, far away it is one or two). With the Rissfeder
## worn, each one the second slash's feathers hit shortens the pause of its Letzter Flügelschlag (Federbund).
func _volley(origin: Vector2, dir: Vector2, step: Dictionary, stack: Dictionary, unit: float) -> void:
	var volley: Dictionary = step["volley"] as Dictionary
	var count: int = maxi(int(volley.get("count", 5)), 1)
	var spread: float = deg_to_rad(float(volley.get("spread", 40.0)))
	var length: float = float(volley.get("length", 150.0))
	var half: float = float(volley.get("width", 8.0)) * 0.5
	var tip: Vector2 = origin + dir * Items.stat(stack, "reach", 22.0) * float(step["reach"]) * 0.8
	var hits: Dictionary = {}
	var stops: PackedFloat32Array = PackedFloat32Array()
	for i: int in count:
		var turn: float = 0.0 if count == 1 else lerpf(-spread / 2.0, spread / 2.0, float(i) / float(count - 1))
		var along: Vector2 = dir.rotated(turn)
		var stop: float = length
		for target: HurtboxComponent in HitScan.lane(self, tip, along, length, half, HURTBOX_MASK):
			hits[target] = int(hits.get(target, 0)) + 1
			stop = minf(stop, maxf((_hit_point(target) - tip).dot(along), 6.0))
		stops.append(stop)
	var max_hits: int = maxi(int(volley.get("max_hits", 3)), 1)
	for target: Variant in hits:
		var hurt: HurtboxComponent = target as HurtboxComponent
		hurt.take_hit(unit * float(volley.get("ratio", 0.4)) * float(mini(int(hits[target]), max_hits)), tip, Items.stat(stack, "knockback", 0.0) * float(volley.get("knock", 1.0)), get_multiplayer_authority())
	_volley_fx.rpc(tip, dir, count, spread, float(volley.get("speed", 560.0)), stops, int(step.get("stage", 1)))
	if hits.is_empty():
		return
	if _talismans != null and volley.has("ward_refund"):
		_talismans.shorten_ward(minf(float(volley["ward_refund"]) * hits.size(), float(volley.get("ward_cap", 0.0)))) ## Federbund
	_on_hit.rpc(_hit_point(hits.keys()[0] as HurtboxComponent), dir, float(step["shake"]), 0.0)


## Every peer: the lane of light of the thrust (`RiftFx.lane`).
@rpc("any_peer", "call_local", "reliable")
func _rift_fx(at: Vector2, dir: Vector2, length: float, life: float) -> void:
	if multiplayer.get_remote_sender_id() > 1:
		return
	RiftFx.lane(get_tree().current_scene, at, dir, length, life)
	_play_sound("line", -4.0, randf_range(0.95, 1.08))


## Every peer: the feathers fly (`FeatherVolley`), each as far as `stops` says.
@rpc("any_peer", "call_local", "reliable")
func _volley_fx(at: Vector2, dir: Vector2, count: int, spread: float, speed: float, stops: PackedFloat32Array, stage: int) -> void:
	if multiplayer.get_remote_sender_id() > 1:
		return
	FeatherVolley.shoot(get_tree().current_scene, at, dir, count, spread, speed, stops)
	_play_sound("volley", -3.0, 1.0 if stage == 1 else 0.88)


func _hit_point(target: HurtboxComponent) -> Vector2:
	var area: Node2D = target.get_child(0) as Node2D
	return area.global_position if area != null else target.global_position


## Sparks fly back toward the attacker on every peer; the attacker's camera shakes.
@rpc("any_peer", "call_local", "reliable")
func _on_hit(point: Vector2, dir: Vector2, shake: float, hit_stop: float = 0.0) -> void:
	if multiplayer.get_remote_sender_id() > 1:
		return
	_spawn_sparks(point, dir, hit_stop > 0.0)
	if hit_stop > 0.0:
		_freeze = maxf(_freeze, hit_stop) ## the heavy blow bites: the swing stands still for a moment (animation only)
		_play_sound("hit", -2.0)
	elif Sfx.has("sword_hit"):
		Sfx.at(self, "sword_hit", point, -4.0, 0.06) ## every normal blow that lands
	if is_multiplayer_authority():
		hit_landed.emit(shake)


static func _get_spark_gradient() -> Gradient:
	if _spark_gradient == null:
		_spark_gradient = Gradient.new()
		_spark_gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		_spark_gradient.colors = PackedColorArray([Color("fff6dc"), Color("ffb347"), Color(1.0, 0.5, 0.2, 0.0)])
	return _spark_gradient


static func _recycle_sparks(sparks: CPUParticles2D) -> void:
	if not is_instance_valid(sparks):
		return
	sparks.emitting = false
	if sparks.get_parent() != null:
		sparks.get_parent().remove_child(sparks)
	if _sparks_pool.size() < 24:
		_sparks_pool.append(sparks)
	else:
		sparks.queue_free()


func _spawn_sparks(point: Vector2, dir: Vector2, heavy: bool = false) -> void:
	var sparks: CPUParticles2D = null
	while not _sparks_pool.is_empty():
		var candidate: CPUParticles2D = _sparks_pool.pop_back()
		if is_instance_valid(candidate):
			sparks = candidate
			break
	if sparks == null:
		sparks = CPUParticles2D.new()
		sparks.texture = SPARK_TEXTURE
		sparks.lifetime = 0.28
		sparks.one_shot = true
		sparks.explosiveness = 1.0
		sparks.spread = 75.0
		sparks.gravity = Vector2.ZERO
		sparks.damping_min = 160.0
		sparks.damping_max = 230.0
		sparks.scale_amount_min = 0.5
		sparks.scale_amount_max = 0.9
		sparks.color_ramp = _get_spark_gradient()
		sparks.z_index = 20
		sparks.finished.connect(_recycle_sparks.bind(sparks))
	sparks.amount = 24 if heavy else 10
	sparks.initial_velocity_min = 50.0
	sparks.initial_velocity_max = 200.0 if heavy else 140.0
	sparks.direction = -dir
	if sparks.get_parent() != get_tree().current_scene:
		if sparks.get_parent() != null:
			sparks.get_parent().remove_child(sparks)
		get_tree().current_scene.add_child(sparks)
	sparks.global_position = point
	sparks.restart()


## How many steps of the weapon class's combo she can swing: the leading ones whose `requires` skill is learned.
func _combo_size(def: Dictionary) -> int:
	var combo: Array = DataRegistry.get_entry("weapon_classes", String(def.get("weapon_class", ""))).get("combo", [])
	var count: int = 0
	for step: Variant in combo:
		if not _skill_learned(String((step as Dictionary).get("requires", ""))):
			break
		count += 1
	return count


func _skill_learned(requires: String) -> bool:
	return requires.is_empty() or (_skills != null and _skills.is_learned(requires))


func _step_unlocked(step: Dictionary) -> bool:
	return _skill_learned(String(step.get("requires", "")))


## One combo step with its times scaled by the weapon's `speed` stat.
func _step_data(stack: Dictionary, index: int) -> Dictionary:
	var def: Dictionary = Items.definition(stack)
	var combo: Array = DataRegistry.get_entry("weapon_classes", String(def.get("weapon_class", ""))).get("combo", [])
	if combo.is_empty():
		return {}
	var step: Dictionary = combo[clampi(index, 0, combo.size() - 1)]
	var speed: float = maxf(Items.stat(stack, "speed", 1.0), 0.1)
	return {
		"style": String(step.get("style", "slash")),
		"sweep": float(step.get("sweep", 1)),
		"arc": deg_to_rad(float(step.get("arc", 100))),
		"windup": float(step.get("windup", 0.1)) / speed,
		"active": float(step.get("active", 0.1)) / speed,
		"recovery": float(step.get("recovery", 0.2)) / speed,
		"damage": float(step.get("damage", 1)),
		"reach": float(step.get("reach", 1)),
		"knock": float(step.get("knock", 1)),
		"lunge": float(step.get("lunge", 0)),
		"shake": float(step.get("shake", 1)),
		"block": int(step.get("block", -1)),
		"requires": String(step.get("requires", "")),
		"rift": String(step.get("rift", "")),
	}


## While she holds the charge: motes gather at the blade's tip, a click when it is worth releasing, a flash at full strength.
func _charge_effects(delta: float) -> void:
	var power: float = charge_amount()
	var stage: int = 0
	if charge_ready():
		stage = 2 if power >= 0.995 else 1
	if stage != _charge_stage:
		if stage > _charge_stage:
			_play_sound("ready" if stage == 1 else "full", -6.0 if stage == 1 else -3.0)
			if stage == 2:
				_flash = 0.25
		_charge_stage = stage
		charge_stage.emit(stage)
	if power <= 0.0:
		return
	_charge_carry += delta * (14.0 + 50.0 * power)
	var tip: Vector2 = _weapon.global_position + Vector2.from_angle(_blade_angle) * _blade_length * BLADE_PX
	while _charge_carry >= 1.0:
		_charge_carry -= 1.0
		var around: Vector2 = tip + Vector2.from_angle(randf() * TAU) * randf_range(7.0, 13.0)
		var vel: Vector2 = (tip - around).normalized() * randf_range(18.0, 34.0) ## gathering inwards
		_motes.append({"pos": around, "vel": vel, "age": 0.0, "life": randf_range(0.18, 0.3), "kind": 0 if randf() < 0.8 else 1, "color": _fx_colors[1 + randi() % 3], "size": randf_range(0.8, 1.2)})
	if _motes.size() > MAX_MOTES:
		_motes = _motes.slice(_motes.size() - MAX_MOTES)


## Remembers where the blade has been during a heavy blow, for the ribbon it leaves behind.
func _track_tips(delta: float) -> void:
	for i: int in range(_tips.size() - 1, -1, -1):
		_tips[i]["age"] = float(_tips[i]["age"]) + delta
		if float(_tips[i]["age"]) >= HEAVY_TRAIL_LIFE:
			_tips.remove_at(i)
	if (is_heavy_swing() or _is_diag()) and _phase != Phase.WINDUP and _freeze <= 0.0:
		var dir: Vector2 = Vector2.from_angle(_blade_angle)
		var base: Vector2 = _weapon.global_position
		_tips.append({"mid": base + dir * _blade_length * BLADE_PX * 0.45, "tip": base + dir * _blade_length * BLADE_PX, "age": 0.0})


## Dust and chips where the blade bites the ground at the end of the blow.
func _impact_dust() -> void:
	var at: Vector2 = global_position + aim_dir.normalized() * minf(_reach * 0.8, 40.0)
	var dust: CPUParticles2D = CPUParticles2D.new()
	dust.texture = SPARK_TEXTURE
	dust.amount = 14
	dust.lifetime = 0.45
	dust.one_shot = true
	dust.explosiveness = 1.0
	dust.direction = Vector2.UP
	dust.spread = 80.0
	dust.gravity = Vector2(0, 40)
	dust.initial_velocity_min = 25.0
	dust.initial_velocity_max = 75.0
	dust.damping_min = 90.0
	dust.damping_max = 140.0
	dust.scale_amount_min = 0.7
	dust.scale_amount_max = 1.3
	var ramp: Gradient = Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 1.0])
	ramp.colors = PackedColorArray([Color(0.72, 0.68, 0.62, 0.7), Color(0.55, 0.5, 0.48, 0.0)])
	dust.color_ramp = ramp
	dust.z_index = 2
	get_tree().current_scene.add_child(dust)
	dust.global_position = at
	dust.emitting = true
	get_tree().create_timer(0.8).timeout.connect(dust.queue_free)
	_play_sound("thud", -4.0)


func _play_sound(id: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var key: String = _sound_dir + id
	var stream: AudioStream = _sounds.get(key) as AudioStream
	if stream == null:
		var path: String = _sound_dir + id + ".wav" ## a weapon's own sound first (item `fx.sounds`), else the shared ones
		if _sound_dir.is_empty() or not ResourceLoader.exists(path):
			path = HEAVY_SOUNDS + id + ".wav"
		if not ResourceLoader.exists(path):
			return
		stream = load(path) as AudioStream
		_sounds[key] = stream
	var player: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.max_distance = 360.0
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


## The look of this weapon's swing: colours of the motes and the trail and the folder of its own sounds (item `fx`), the shared ones when it has none.
func _load_fx(def: Dictionary) -> void:
	var fx: Dictionary = def.get("fx", {}) as Dictionary
	_fx_colors = MOTE_COLORS.duplicate()
	var motes: Array = fx.get("motes", []) as Array
	if motes.size() >= 4:
		for i: int in 4:
			_fx_colors[i] = Color(String(motes[i]))
	_trail_edge = Color(String(fx["trail_edge"])) if fx.has("trail_edge") else TRAIL_EDGE
	_trail_core = Color(String(fx["trail_core"])) if fx.has("trail_core") else TRAIL_CORE
	_sound_dir = String(fx.get("sounds", ""))


## A stack as every peer knows it from the synced item id and refinement level.
static func _stack_of(weapon_id: String, refine_level: int) -> Dictionary:
	var stack: Dictionary = {"id": weapon_id, "count": 1}
	if refine_level > 0:
		stack[RefineRules.KEY_LEVEL] = refine_level
	return stack


func _refresh_weapon() -> void:
	var def: Dictionary = DataRegistry.get_entry("items", held_weapon)
	always_drawn = String(def.get("tool", "")) == "rod" or String(def.get("tool", "")) == "staff" ## a rod or a staff is no weapon: no swings, never put away
	_staff = String(def.get("tool", "")) == "staff"
	if _weapon == null:
		return
	_has_weapon = not def.is_empty()
	_style = GripRig.style_of(def)
	_load_fx(def)
	_weapon.visible = _has_weapon and _weapon_alpha > 0.01
	if _has_weapon:
		_weapon.texture = load(String(def.get("held", "")).replace("_held.png", "_held_rot.png")) as Texture2D ## the grip is the middle pixel of every cell


func _advance(delta: float) -> void:
	if _phase == Phase.IDLE:
		return
	_time += delta
	match _phase:
		Phase.WINDUP:
			if _time >= float(_step["windup"]):
				_time -= float(_step["windup"])
				_phase = Phase.ACTIVE
				if is_multiplayer_authority() and float(_step["lunge"]) > 0.0:
					lunged.emit(aim_dir * float(_step["lunge"]))
		Phase.ACTIVE:
			if _time >= float(_step["active"]):
				_time -= float(_step["active"])
				_phase = Phase.RECOVERY
		Phase.RECOVERY:
			if _time >= float(_step["recovery"]):
				_phase = Phase.IDLE
				_combo_deadline_msec = Time.get_ticks_msec() + int(_combo_window * 1000.0)
				if bool(_step.get("alt", false)) and is_multiplayer_authority():
					_alt_chain_ended()


## The owner's slash of the right-click chain ended: the first one opens the window for the second (and starts it at once when the button was pressed during
## the recovery), the second closes the chain.
func _alt_chain_ended() -> void:
	if int(_step.get("stage", 0)) != 1:
		_alt_stage = 0
		return
	var cfg: Dictionary = HeavyRules.config(DataRegistry.get_entry("items", held_weapon))
	_alt_deadline_msec = Time.get_ticks_msec() + int(HeavyRules.rift_window(cfg) * 1000.0)
	if _alt_buffer_msec > 0 and Time.get_ticks_msec() - _alt_buffer_msec < 350 and HeavyRules.is_rift_slash(cfg):
		_alt_start(cfg, _alt_buffer_dir)
	_alt_buffer_msec = 0


## The held item and the arm that holds it (docs/griff_system.md). Everything is solved in GripRig's 3D space and projected the way her body
## sheets are rendered:
## - the fist starts at the sheet's natural hand (rig_hand) and moves to the item's own hold (data/grips.json: ready, carry, sprint) while no
##   clip owns the hand; swings, picking, eating, casting and fishing keep the sheet's hand;
## - the arm is a two-bone solve from the rig shoulder to the fist with the renderer's arm lengths and elbow pole, painted by ArmPainter;
## - the item points along a 3D direction. At rest a damped spring pulls it toward its hold, so it has weight: it lags behind the fist, swings
##   round when she turns and settles with a small overshoot. Swings, blows and charges key it along real paths (a slash sweeps through a tilted
##   plane round her and overshoots in the recovery, a chop comes over the head), and it foreshortens when it points at or away from the camera
##   instead of spinning round the hand like a clock hand. Only the angle and the foreshortening reach the pre-rotated sprite.
func _update_pose(delta: float) -> void:
	var spring: Dictionary = GripRig.data().get("spring", {}) as Dictionary
	var forward: Vector2 = body_dir.normalized() if body_dir.length() > 0.01 else Vector2.DOWN
	var right: Vector2 = GripRig.right_of(forward)
	var busy: bool = _phase != Phase.IDLE or _charging
	var blend: float = float(spring.get("blend", 4.5))
	_ready_k = move_toward(_ready_k, 1.0 if is_in_combat(float(spring.get("ready_for", 2.2))) else 0.0, blend * delta)
	_sprint_k = move_toward(_sprint_k, 1.0 if carrying and not busy else 0.0, blend * 1.5 * delta)
	_free_k = move_toward(_free_k, 1.0 if free_hand and not busy and not rod_pose.is_finite() else 0.0, (14.0 if busy or not free_hand else 6.0) * delta)
	_hold_k = move_toward(_hold_k, 1.0 if _has_weapon and _weapon_alpha > 0.05 else 0.0, 5.0 * delta)
	var hold: Array = _rest_hold()
	var rest_dir: Vector3 = _rod_dir(forward, right) if rod_pose.is_finite() else GripRig.body_dir(forward, float(hold[1]), float(hold[2]))
	_shoulder3 = GripRig.shoulder_3d(rig_shoulder, forward)
	var natural: Vector3 = GripRig.hand_3d(rig_hand, _shoulder3, forward)
	var fist_goal: Vector3 = natural + GripRig.body_offset(forward, right, hold[0] as Vector3) * (_free_k * _hold_k)
	var solved: Array[Vector3] = GripRig.arm(_shoulder3, fist_goal, GripRig.pole(forward))
	_elbow3 = solved[0]
	_wrist3 = solved[1]
	_fist3 = solved[2]
	var grip: Vector2 = GripRig.screen(_fist3)
	var hand_acc: Vector2 = Vector2.ZERO ## the fist's acceleration, smoothed (the sheets move it in whole pixels)
	if delta > 0.0:
		if _prev_hand.is_finite():
			var smooth: float = 1.0 - exp(-10.0 * delta)
			var vel: Vector2 = _hand_vel.lerp((grip - _prev_hand) / delta, smooth)
			hand_acc = (vel - _hand_vel) / delta
			_hand_vel = vel
		_prev_hand = grip
	_emit_kind = 0
	var keyed: Variant = _keyed_dir(rest_dir) if _has_weapon else null
	if keyed is Vector3:
		_set_dir(keyed as Vector3, delta)
	else:
		_spring_to(rest_dir, hand_acc, delta, spring, rod_pose.is_finite())
	var shown: Vector2 = GripRig.project_dir(_dir)
	var angle: float = shown.angle()
	var length: float = clampf(shown.length(), 0.4, 1.0)
	_rest_angle = angle
	_rest_length = length
	# depth: the item and the arm each go in front of or behind her body (a near arm may hold a blade that points away)
	var mid: Vector3 = _fist3 + _dir * 7.0
	if mid.y < -1.4:
		_weapon_behind = true
	elif mid.y > 0.4:
		_weapon_behind = false
	var arm_mid: float = (_elbow3.y + _fist3.y) * 0.5
	if arm_mid < -0.6:
		_arm_behind = true
	elif arm_mid > 0.0:
		_arm_behind = false
	_hand.position = Vector2(0, -HAND_SORT if _weapon_behind else HAND_SORT)
	_arm_sort.position = Vector2(0, (-HAND_SORT if _arm_behind else HAND_SORT) + 0.01)
	_blade_angle = angle
	_blade_scale = length
	_blade_length = length
	_grip = grip
	_weapon.position = (grip - _hand.position).round() + Vector2(0.5, 0.5) ## the middle of the glove's pixel
	var flip: bool = _flip_for(angle, length, busy, delta)
	var step: int = roundi(wrapf(-angle if flip else angle, 0.0, TAU) / TAU * float(ROT_ANGLES)) % ROT_ANGLES ## mirrored: the frame of the opposite angle, flipped back
	var level: int = 0
	for i: int in ROT_LENGTHS.size(): ## nearest foreshortening
		if absf(ROT_LENGTHS[i] - length) < absf(ROT_LENGTHS[level] - length):
			level = i
	_weapon.frame = level * ROT_ANGLES + step
	_weapon.flip_v = flip
	if _emit_kind > 0:
		_emit_motes(_emit_kind == 2, delta)
	_last_tip = _grip_world() + _blade_vector()
	_since_swing = 0.0 if busy else _since_swing + delta
	var hide: bool = (sheathed or (_since_swing > OUT_OF_COMBAT and not always_drawn)) and not busy ## a swing always draws the weapon
	_weapon_alpha = 1.0 if not hide and busy else move_toward(_weapon_alpha, 0.0 if hide else 1.0, 8.0 * delta)
	_weapon.modulate.a = _weapon_alpha
	_weapon.visible = _has_weapon and _weapon_alpha > 0.01
	var arm_key: PackedFloat32Array = _arm_pose_key() ## the arm is painted again only when it moved (a worn bracelet shimmers: every frame)
	if arm_key != _arm_key or (_talismans != null and _talismans.worn_id("bracelet") != ""):
		_arm_key = arm_key
		_arm.queue_redraw()


## Whether a tool with a working side is shown mirrored. The pre-rotated sprite can only turn, so a tool pointing left would show its other face
## upside down (the watering can on its head, the axe's edge behind the haft). At rest it shows the mirror image when it points left, as a side
## view from her other side would; the change waits for a moment when it hardly shows (near upright or foreshortened). During a swing the
## working edge (`edge`: +1 the picture's lower side, -1 its upper side) leads the cut; `upright` tools (the can) always keep their top up.
func _flip_for(angle: float, length: float, busy: bool, delta: float) -> bool:
	var edge: int = int(_style.get("edge", 0))
	var upright: bool = bool(_style.get("upright", false))
	if edge == 0 and not upright:
		_flip = false
		return false
	if busy and not upright and _phase != Phase.IDLE and not _step.has("diag") and not bool(_step.get("heavy", false)):
		_flip = _swing_flip
		_flip_wait = 0.0
		return _flip
	var left: bool = cos(angle) < 0.0
	if left == _flip:
		_flip_wait = 0.0
	else:
		_flip_wait += delta
		if absf(cos(angle)) < 0.45 or length < 0.6 or _flip_wait > 0.25 or upright:
			_flip = left
			_flip_wait = 0.0
	return _flip


## Which way the current swing turns on the screen around its contact, and so whether the tool must be mirrored for its edge to lead.
func _edge_leads() -> bool:
	var edge: int = int(_style.get("edge", 0))
	if edge == 0 or _step.is_empty() or String(_step["style"]) == "thrust":
		return false
	var aim: Vector2 = aim_dir.normalized() if aim_dir.length() > 0.01 else Vector2.RIGHT
	var contact: Vector3 = GripRig.dir(aim.angle(), clampf(GripRig.aim_pitch(aim) + deg_to_rad(float(_shape.get("pitch", 0.0))), -1.05, 1.05))
	var sweep: float = -1.0 if bool(_shape.get("top_down", false)) else float(_step["sweep"])
	var tilt: float = _swing_tilt(sweep)
	var before: Vector2 = GripRig.project_dir(GripRig.swing_dir(contact, aim, tilt, -sweep * 0.15))
	var after: Vector2 = GripRig.project_dir(GripRig.swing_dir(contact, aim, tilt, sweep * 0.15))
	var turning: int = 1 if before.cross(after) > 0.0 else -1 ## +1: the angle grows on the screen, the picture's lower side leads
	return turning != edge


## The hold her item rests in now: [fist offset (forward, right, up), radians toward her right, pitch], blended carry -> ready -> sprint.
func _rest_hold() -> Array:
	var carry: Array = _hold_of("carry")
	var ready: Array = _hold_of("ready")
	var sprint: Array = _hold_of("sprint")
	var hand: Vector3 = (carry[0] as Vector3).lerp(ready[0] as Vector3, _ready_k).lerp(sprint[0] as Vector3, _sprint_k)
	var yaw: float = lerp_angle(lerp_angle(float(carry[1]), float(ready[1]), _ready_k), float(sprint[1]), _sprint_k)
	var pitch: float = lerpf(lerpf(float(carry[2]), float(ready[2]), _ready_k), float(sprint[2]), _sprint_k)
	return [hand, yaw, pitch]


func _hold_of(kind: String) -> Array:
	var entry: Dictionary = _style.get(kind, {}) as Dictionary
	var hand: Array = entry.get("hand", [0, 0, 0]) as Array
	var aim: Array = entry.get("dir", [20, 20]) as Array
	return [Vector3(float(hand[0]), float(hand[1]), float(hand[2])), deg_to_rad(float(aim[0])), deg_to_rad(float(aim[1]))]


## A rod or a staff as its clip holds it: `rod_pose` = (forward, toward her right, up).
func _rod_dir(forward: Vector2, right: Vector2) -> Vector3:
	var ground: Vector2 = forward * rod_pose.x + right * rod_pose.y
	var d: Vector3 = Vector3(ground.x, ground.y, rod_pose.z)
	return d.normalized() if d.length() > 0.001 else GripRig.body_dir(forward, 0.0, 0.5)


## Where a swing, a blow or a charge puts the item this frame, or null when it rests (then the spring moves it). Also asks for motes
## (`_emit_kind`: 1 a cut, 2 a thrust) and lights the crescent where a swing lands.
func _keyed_dir(rest_dir: Vector3) -> Variant:
	if _charging:
		var draw: float = HeavyRules.draw_progress(_charge_cfg, _charge_time)
		var ease_draw: float = draw * draw * (3.0 - 2.0 * draw)
		var shiver: float = charge_amount() * 0.05 * sin(_charge_time * 55.0) ## a held, straining blade trembles
		var lifted: Vector3 = _chop_dir(lerpf(CHOP_PITCH_REST, CHOP_PITCH_UP, ease_draw) + shiver, lerpf(0.2, CHOP_YAW_BACK, ease_draw))
		return _turn(_swing_from, lifted, _smooth(_charge_time / 0.14))
	if _phase == Phase.IDLE or _step.is_empty():
		return null
	var aim: Vector2 = aim_dir.normalized() if aim_dir.length() > 0.01 else Vector2.RIGHT
	var windup: float = clampf(_time / maxf(float(_step["windup"]), 0.001), 0.0, 1.0)
	var active: float = clampf(_time / maxf(float(_step["active"]), 0.001), 0.0, 1.0)
	var recovery: float = clampf(_time / maxf(float(_step["recovery"]), 0.001), 0.0, 1.0)
	if bool(_step.get("heavy", false)):
		match _phase:
			Phase.WINDUP:
				return _chop_dir(lerpf(_release_pitch, CHOP_PITCH_WIND, windup), lerpf(_release_yaw, CHOP_YAW_WIND, windup))
			Phase.ACTIVE:
				var eased: float = pow(active, 1.5) ## a heavy blade starts slowly and arrives fast
				if active >= 0.85 and not _burst_done: ## the blow lands: a wide crescent and a puff of dust
					_burst_done = true
					_burst_age = 0.0
					_burst_life = HEAVY_BURST_LIFE
					_burst_heavy = true
					_burst_thrust = false
					_burst_angle = aim.angle()
					_burst_center = global_position + BODY_CENTER
					_impact_dust()
				_emit_kind = 1
				return _chop_dir(lerpf(CHOP_PITCH_WIND, CHOP_PITCH_END, eased), lerpf(CHOP_YAW_WIND, CHOP_YAW_END, eased))
			_:
				return _turn(_chop_dir(CHOP_PITCH_END, CHOP_YAW_END), rest_dir, _smooth(recovery))
	if _step.has("diag"):
		var path: Dictionary = _step["diag"] as Dictionary ## a diagonal slash: over the shoulder and down across her
		var from: Vector3 = _chop_dir(float(path["pitch0"]), float(path["yaw0"]))
		var to: Vector3 = _chop_dir(float(path["pitch1"]), float(path["yaw1"]))
		match _phase:
			Phase.WINDUP:
				return _turn(_swing_from, from, _smooth(windup))
			Phase.ACTIVE:
				var cut: float = 1.0 - pow(1.0 - active, 3.0) ## fast start, soft end
				_emit_kind = 1
				return _chop_dir(lerpf(float(path["pitch0"]), float(path["pitch1"]), cut), lerpf(float(path["yaw0"]), float(path["yaw1"]), cut))
			_:
				return _turn(to, rest_dir, _smooth(recovery))
	var thrust: bool = String(_step["style"]) == "thrust"
	var contact: Vector3 = GripRig.dir(aim.angle(), clampf(GripRig.aim_pitch(aim) + deg_to_rad(float(_shape.get("pitch", 0.0))), -1.05, 1.05))
	var half: float = float(_step["arc"]) / 2.0
	var sweep: float = -1.0 if bool(_shape.get("top_down", false)) else float(_step["sweep"])
	var tilt: float = _swing_tilt(sweep)
	var theta0: float = -sweep * (half + float(_shape.get("cock", 0.5)))
	var theta1: float = sweep * (half + float(_shape.get("follow", 0.3)))
	match _phase:
		Phase.WINDUP:
			_theta_from = theta0
			_theta_head = theta0
			return _turn(_swing_from, contact if thrust else GripRig.swing_dir(contact, aim, tilt, theta0), _smooth(windup))
		Phase.ACTIVE:
			var eased: float = 1.0 - pow(1.0 - active, 2.2) ## the cut whips through and slows into the follow-through
			var theta: float = lerpf(theta0, theta1, eased)
			_theta_head = theta
			if active >= 0.9 and not _burst_done: ## the swing lands: a shock crescent (a ring for a thrust) flashes out
				_burst_done = true
				_burst_age = 0.0
				_burst_life = BURST_LIFE
				_burst_heavy = false
				_burst_thrust = thrust
				_burst_angle = aim.angle() if thrust else aim.angle() + clampf(theta, -half, half)
				_burst_center = global_position + BODY_CENTER
			if thrust:
				_thrust_progress = eased
				_emit_kind = 2
				return contact
			_emit_kind = 1
			return GripRig.swing_dir(contact, aim, tilt, theta)
		_:
			if thrust:
				return _turn(contact, rest_dir, _smooth((recovery - 0.2) / 0.8))
			var over: float = theta1 + signf(theta1 - theta0) * float(_shape.get("over", 0.2)) ## it does not stop dead: the follow-through carries on
			if recovery < 0.3:
				var k: float = recovery / 0.3
				return GripRig.swing_dir(contact, aim, tilt, lerpf(theta1, over, 1.0 - (1.0 - k) * (1.0 - k)))
			return _turn(GripRig.swing_dir(contact, aim, tilt, over), rest_dir, _smooth((recovery - 0.3) / 0.7))


## How far the current swing's plane leans up on her right side: a forehand (sweep -1, from her right) uses `tilt`, a backhand `tilt_back`.
func _swing_tilt(sweep: float) -> float:
	return deg_to_rad(float(_shape.get("tilt" if sweep < 0.0 else "tilt_back", _shape.get("tilt", 20.0))))


## The keyed direction becomes the state; its speed is kept, so the spring carries on from it when the swing hands over.
func _set_dir(d: Vector3, delta: float) -> void:
	var yaw: float = GripRig.yaw_of(d) if Vector2(d.x, d.y).length() > 0.05 else _yaw
	var pitch: float = GripRig.pitch_of(d)
	if delta > 0.0:
		_yaw_v = clampf(wrapf(yaw - _yaw, -PI, PI) / delta, -24.0, 24.0) * clampf(cos(pitch) * 3.0, 0.0, 1.0)
		_pitch_v = clampf((pitch - _pitch) / delta, -24.0, 24.0)
	_yaw = yaw
	_pitch = pitch
	_dir = d.normalized()


## The resting item: a damped spring on its compass angle and pitch toward `target`, pushed by the fist's acceleration (the tip lags).
func _spring_to(target: Vector3, hand_acc: Vector2, delta: float, spring: Dictionary, fast: bool) -> void:
	var omega: float = 34.0 if fast else float(spring.get("omega", 19.0))
	var zeta: float = 1.0 if fast else float(spring.get("damping", 0.6))
	var inertia: float = 0.0 if fast else float(spring.get("inertia", 0.0005))
	var goal_yaw: float = GripRig.yaw_of(target) if Vector2(target.x, target.y).length() > 0.05 else _yaw
	var goal_pitch: float = GripRig.pitch_of(target)
	goal_pitch += clampf(hand_acc.y * inertia, -0.3, 0.3) ## the fist drops: the tip stays up a moment, and the other way round
	goal_yaw += clampf(hand_acc.x * inertia * sin(_yaw), -0.3, 0.3)
	var max_dt: float = float(spring.get("max_dt", 0.034))
	var steps: int = clampi(ceili(delta / max_dt), 1, 8)
	var h: float = delta / float(steps)
	for i: int in steps:
		var acc_yaw: float = omega * omega * wrapf(goal_yaw - _yaw, -PI, PI) - 2.0 * zeta * omega * _yaw_v
		var acc_pitch: float = omega * omega * (goal_pitch - _pitch) - 2.0 * zeta * omega * _pitch_v
		_yaw_v += acc_yaw * h
		_pitch_v += acc_pitch * h
		_yaw = wrapf(_yaw + _yaw_v * h, -PI, PI)
		_pitch = clampf(_pitch + _pitch_v * h, -1.5, 1.5)
	_dir = GripRig.dir(_yaw, _pitch)


## From one direction to another along the shorter great circle (over the top when they point apart).
static func _turn(a: Vector3, b: Vector3, u: float) -> Vector3:
	u = clampf(u, 0.0, 1.0)
	if a.dot(b) < -0.96:
		var top: Vector3 = Vector3(0.0, 0.0, 1.0) if absf(a.z) < 0.9 else Vector3(a.y, -a.x, 0.0).normalized()
		return a.slerp(top, u * 2.0) if u < 0.5 else top.slerp(b, u * 2.0 - 1.0)
	return a.slerp(b, u).normalized()


static func _smooth(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Where the blade points when it stands `pitch` above the horizon (above 90 deg = leaning back) and `yaw` radians from her aim toward
## her sword side.
func _chop_dir(pitch: float, yaw: float) -> Vector3:
	var ground: Vector2 = aim_dir.normalized().rotated(yaw) * cos(pitch)
	return Vector3(ground.x, ground.y, sin(pitch))


## The arm's pose to a quarter pixel: when it is the same as last frame, last frame's painting still stands.
func _arm_pose_key() -> PackedFloat32Array:
	var key: PackedFloat32Array = PackedFloat32Array()
	for p: Vector3 in [_shoulder3, _elbow3, _wrist3, _fist3]:
		key.append(roundf(p.x * 4.0))
		key.append(roundf(p.y * 4.0))
		key.append(roundf(p.z * 4.0))
	key.append(_arm_sort.position.y)
	return key


## Shows or hides the drawn arm and the held item together (the shadow step, swimming: those sheets carry both arms).
func set_arm_shown(on: bool) -> void:
	_hand.visible = on
	if _arm_sort != null:
		_arm_sort.visible = on


func arm_shown() -> bool:
	return _hand.visible


## The arm and the item wear the same shader as her sprite: pallor, wetness, the hit flash, the mist veil and the daylight grade fall on
## them as on the sheet (blood and bandage stay off: their maps belong to the sheet).
func mirror_material(source: Material) -> void:
	var src: ShaderMaterial = source as ShaderMaterial
	if src == null or src.shader == null:
		return
	if _skin == null or _skin.shader != src.shader:
		_skin = ShaderMaterial.new()
		_skin.shader = src.shader
		_arm.material = _skin
		_weapon.material = _skin
	for key: StringName in [&"wound", &"soak", &"flash", &"flash_color", &"veil", &"veil_keep", &"veil_seed"]:
		var value: Variant = src.get_shader_parameter(key)
		if value != null:
			_skin.set_shader_parameter(key, value)


## Her sword arm, painted like her left one (ArmPainter); a worn bracelet sits on the violet band.
func _draw_arm() -> void:
	var drawn: Array[Vector2] = ArmPainter.paint(_arm, _arm_sort.position, _shoulder3, _elbow3, _wrist3, _fist3, 1.0)
	var bracelet: String = _talismans.worn_id("bracelet") if _talismans != null else ""
	if bracelet != "": ## the worn bracelet (Wuchtreif ...) takes the place of the band
		TalismanArt.draw_bracelet(_arm, bracelet, drawn[0], drawn[1], float(Time.get_ticks_msec()) / 1000.0)


## The blade's trail: a wedge that grows with the sweep, brightest at the blade, fading afterwards.
func _draw_trail() -> void:
	var alpha: float = 1.0 - _trail_age / TRAIL_FADE
	_draw_heavy_ribbon()
	if alpha > 0.0 and not _step.is_empty() and not bool(_step.get("heavy", false)) and not _step.has("diag"):
		if String(_step["style"]) == "thrust":
			_draw_thrust_trail(alpha)
		else:
			_draw_slash_trail(alpha)
	_draw_burst()
	_draw_edge_glow()
	_draw_motes()
	_draw_charge_glint()


## The heavy blow's ribbon: quads between the last positions of the blade's middle and tip, brightest at the newest.
func _draw_heavy_ribbon() -> void:
	if _tips.size() < 2:
		return
	for i: int in range(1, _tips.size()):
		var a: Dictionary = _tips[i - 1]
		var b: Dictionary = _tips[i]
		var k: float = 1.0 - float(b["age"]) / HEAVY_TRAIL_LIFE
		var color: Color = _trail_edge.lerp(_trail_core, k)
		color.a = clampf(k, 0.0, 1.0) * 0.85
		var a_mid: Vector2 = _trail.to_local(a["mid"] as Vector2)
		var a_tip: Vector2 = _trail.to_local(a["tip"] as Vector2)
		var b_tip: Vector2 = _trail.to_local(b["tip"] as Vector2)
		var b_mid: Vector2 = _trail.to_local(b["mid"] as Vector2)
		# Two triangles instead of one quad: a twisted (bow-tie) or flat quad cannot be triangulated.
		_draw_ribbon_triangle(a_mid, a_tip, b_tip, color)
		_draw_ribbon_triangle(a_mid, b_tip, b_mid, color)


## Draws a triangle only when it has a real area (degenerate ones make the renderer log a triangulation error).
func _draw_ribbon_triangle(p0: Vector2, p1: Vector2, p2: Vector2, color: Color) -> void:
	var area2: float = (p1 - p0).cross(p2 - p0)
	if absf(area2) < 0.05:
		return
	_trail.draw_colored_polygon(PackedVector2Array([p0, p1, p2]), color)


## A tiny cross of light on the tip while the blow is charged, and a bigger flash the moment it is full.
func _draw_charge_glint() -> void:
	if not _charging or _blade_length <= 0.0:
		return
	var power: float = charge_amount()
	if power <= 0.0 and _flash <= 0.0:
		return
	var tip: Vector2 = _trail.to_local(_weapon.global_position + Vector2.from_angle(_blade_angle) * _blade_length * BLADE_PX).round()
	var color: Color = _fx_colors[0]
	color.a = 0.35 + 0.5 * power + 0.5 * (_flash / 0.25)
	var arm: float = 2.0 + 2.0 * power + 4.0 * (_flash / 0.25)
	_trail.draw_rect(Rect2(tip - Vector2(arm, 0), Vector2(arm * 2.0 + 1.0, 1)), color)
	_trail.draw_rect(Rect2(tip - Vector2(0, arm), Vector2(1, arm * 2.0 + 1.0)), color)
	_trail.draw_rect(Rect2(tip, Vector2(1, 1)), Color.WHITE)


## A refined blade glints: from +10 now and then a twinkle somewhere along the edge, at +15 many of them and a thin gold light along the whole blade.
func _edge_glints(delta: float) -> void:
	if held_refine < 10 or not _has_weapon or _weapon_alpha < 0.4 or always_drawn:
		return
	_edge_clock += delta
	var every: float = 0.11 if held_refine >= RefineRules.max_level() else 0.5
	if _edge_clock < every:
		return
	_edge_clock = 0.0
	var blade: Vector2 = _blade_vector()
	var colour: Color = RefineStyle.color(held_refine).lightened(0.25)
	if held_refine >= RefineRules.max_level() and randf() < 0.3:
		colour = Color("ff9ae6") ## a touch of the void's magenta in the perfect blade
	_motes.append({"pos": _grip_world() + blade * randf_range(0.35, 1.0), "vel": Vector2(randf_range(-4.0, 4.0), randf_range(-12.0, -4.0)), "age": 0.0, "life": randf_range(0.3, 0.55), "kind": 1 if randf() < 0.6 else 0, "color": colour, "size": 1.0})


## The blade from the hilt to the tip in world px as the pose shows it now (a reach-long blade, shortened by foreshortening).
func _blade_vector() -> Vector2:
	return Vector2.from_angle(_blade_angle) * Items.stat(_stack_of(held_weapon, held_refine), "reach", 24.0) * 0.8 * clampf(_blade_scale, 0.4, 1.0)


func _grip_world() -> Vector2:
	return _hand.global_position + _weapon.position


func _draw_edge_glow() -> void:
	if held_refine < RefineRules.max_level() or not _has_weapon or _weapon_alpha < 0.4 or always_drawn:
		return
	var from: Vector2 = _trail.to_local(_grip_world()).round()
	var to: Vector2 = _trail.to_local(_grip_world() + _blade_vector()).round()
	var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
	_trail.draw_line(from.lerp(to, 0.25), to, Color(RefineStyle.GOLD, (0.22 + 0.22 * pulse) * _weapon_alpha), 1.0)


## The blade sheds sparkles while it is in the air: from its outer part, flying on the way the tip really moved, rising a little and fading.
func _emit_motes(thrust: bool, delta: float) -> void:
	_mote_carry += delta * MOTES_PER_SEC
	var grip: Vector2 = _grip_world()
	var blade: Vector2 = _blade_vector()
	var along: Vector2 = blade.normalized() if blade.length() > 0.01 else aim_dir.normalized()
	var moved: Vector2 = grip + blade - _last_tip
	var flight: Vector2 = along if thrust or moved.length() < 0.5 else moved.normalized() ## the way the tip is moving
	while _mote_carry >= 1.0:
		_mote_carry -= 1.0
		var kind: int = [0, 0, 0, 0, 0, 1][randi() % 6]
		var color: Color = _fx_colors[1 + randi() % 2]
		var speed: float = randf_range(18.0, 55.0)
		var vel: Vector2 = flight * speed + along * randf_range(-12.0, 30.0) + Vector2(randf_range(-14.0, 14.0), randf_range(-14.0, 6.0))
		_motes.append({"pos": grip + blade * randf_range(0.6, 1.0) + along.rotated(PI / 2.0) * randf_range(-1.5, 1.5), "vel": vel, "age": 0.0, "life": randf_range(0.2, 0.42), "kind": kind, "color": color, "size": randf_range(0.8, 1.3)})
	if _motes.size() > MAX_MOTES:
		_motes = _motes.slice(_motes.size() - MAX_MOTES)


func _update_motes(delta: float) -> void:
	if _burst_age < _burst_life:
		_burst_age += delta
	if _motes.is_empty():
		return
	var damping: float = exp(-3.2 * delta)
	for i: int in range(_motes.size() - 1, -1, -1):
		var mote: Dictionary = _motes[i]
		mote["age"] = float(mote["age"]) + delta
		if float(mote["age"]) >= float(mote["life"]):
			_motes.remove_at(i)
			continue
		var vel: Vector2 = (mote["vel"] as Vector2) * damping + Vector2(0.0, -16.0 * delta) ## drift up like embers
		mote["vel"] = vel
		mote["pos"] = (mote["pos"] as Vector2) + vel * delta


func _draw_motes() -> void:
	if _motes.is_empty():
		return
	var trail_inv: Transform2D = _trail.global_transform.affine_inverse()
	for mote: Dictionary in _motes:
		var k: float = float(mote["age"]) / float(mote["life"])
		var color: Color = mote["color"] as Color
		color.a = clampf((1.0 - k) * 1.5, 0.0, 1.0) * 0.8 * (0.8 + 0.2 * sin(float(mote["age"]) * 40.0 + float(mote["size"]) * 9.0)) ## a faint twinkle
		var at: Vector2 = (trail_inv * (mote["pos"] as Vector2)).round()
		var size: float = float(mote["size"]) * (1.0 - 0.5 * k)
		match int(mote["kind"]):
			0: ## a speck
				var side: float = 1.0
				_trail.draw_rect(Rect2(at, Vector2(side, side)), color)
			1: ## a four-point glint
				var arm: float = 1.0
				_trail.draw_rect(Rect2(at - Vector2(arm, 0), Vector2(arm * 2.0 + 1.0, 1)), color)
				_trail.draw_rect(Rect2(at - Vector2(0, arm), Vector2(1, arm * 2.0 + 1.0)), color)
				var core: Color = _fx_colors[0]
				core.a = color.a
				_trail.draw_rect(Rect2(at, Vector2(1, 1)), core)
			_: ## a streak along its flight
				var dir: Vector2 = (mote["vel"] as Vector2).normalized()
				var tail: Vector2 = at - dir * (3.0 + 7.0 * (1.0 - k))
				_trail.draw_line(tail, at, color, 1.0)


## Where a swing ends: an expanding crescent of light (a ring for a thrust), two thin pixel layers.
func _draw_burst() -> void:
	if _burst_age >= _burst_life:
		return
	var k: float = _burst_age / _burst_life
	var grow: float = 1.0 - pow(1.0 - k, 2.5)
	var fade: float = pow(1.0 - k, 1.4)
	var center: Vector2 = _trail.to_local(_burst_center)
	for layer: int in (2 if _burst_heavy else 1):
		var color: Color = _fx_colors[1 - layer] if _burst_heavy else _fx_colors[1]
		color.a = fade * (0.7 if _burst_heavy else 0.5)
		if _burst_heavy:
			var wide: float = _reach + 2.0 + 10.0 * grow - 2.0 * layer
			var span: float = 1.0 - 0.3 * grow
			_trail.draw_arc(center, wide, _burst_angle - span, _burst_angle + span, 24, color, 1.0 + float(1 - layer))
		elif _burst_thrust:
			var tip: Vector2 = center + Vector2.from_angle(_burst_angle) * _reach
			_trail.draw_arc(tip, 2.0 + 5.0 * grow, 0.0, TAU, 16, color, 1.0)
		else:
			var radius: float = _reach + 1.0 + 6.0 * grow
			var half: float = 0.5 - 0.2 * grow
			_trail.draw_arc(center, radius, _burst_angle - half, _burst_angle + half, 14, color, 1.0)


## The cut's trail: a ribbon along the path the tip really took through space (GripRig.swing_dir), seen from the fist where it is now,
## thin and faint where the cut began, bright at the blade.
func _draw_slash_trail(alpha: float) -> void:
	var span: float = _theta_head - _theta_from
	if absf(span) <= 0.02:
		return
	var aim: Vector2 = aim_dir.normalized() if aim_dir.length() > 0.01 else Vector2.RIGHT
	var contact: Vector3 = GripRig.dir(aim.angle(), clampf(GripRig.aim_pitch(aim) + deg_to_rad(float(_shape.get("pitch", 0.0))), -1.05, 1.05))
	var tilt: float = _swing_tilt(-1.0 if bool(_shape.get("top_down", false)) else float(_step["sweep"]))
	var length: float = Items.stat(_stack_of(held_weapon, held_refine), "reach", 24.0) * 0.8
	var quad: PackedVector2Array = PackedVector2Array()
	quad.resize(4)
	var prev: Vector2 = GripRig.project_dir(GripRig.swing_dir(contact, aim, tilt, _theta_from))
	for i: int in TRAIL_STEPS:
		var k1: float = float(i + 1) / TRAIL_STEPS
		var here: Vector2 = GripRig.project_dir(GripRig.swing_dir(contact, aim, tilt, _theta_from + span * k1))
		var inner: float = length - lerpf(1.5, 9.0, k1)
		var color: Color = _trail_edge.lerp(_trail_core, k1)
		color.a = alpha * lerpf(0.1, 0.95, k1)
		quad[0] = _grip + prev * inner
		quad[1] = _grip + prev * length
		quad[2] = _grip + here * length
		quad[3] = _grip + here * inner
		_draw_ribbon_triangle(quad[0], quad[1], quad[2], color)
		_draw_ribbon_triangle(quad[0], quad[2], quad[3], color)
		prev = here


func _draw_thrust_trail(alpha: float) -> void:
	var perp: Vector2 = aim_dir.rotated(PI / 2.0)
	var tail: Vector2 = BODY_CENTER + aim_dir * 2.0
	var tip: Vector2 = BODY_CENTER + aim_dir * (2.0 + (_reach - 2.0) * _thrust_progress)
	for layer: int in 2:
		var width: float = 4.0 - layer * 2.0
		var color: Color = _trail_edge.lerp(_trail_core, float(layer))
		color.a = alpha * (0.6 + 0.3 * layer)
		_trail.draw_colored_polygon(PackedVector2Array([tail + perp * 0.4, tip + perp * width, tip - perp * width, tail - perp * 0.4]), color)


@rpc("any_peer", "call_local", "reliable")
func _confirm_stage(weapon: String, stage: int) -> void:
	if multiplayer.get_remote_sender_id() <= 1 and is_multiplayer_authority():
		combo_stage.emit(weapon, stage)
