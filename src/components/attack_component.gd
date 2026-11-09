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
const DEPTH_SQUASH: float = 0.44 ## how much a direction toward the camera is shortened on screen
const ARM_UPPER: float = 5.8 ## px, the sword arm drawn from the shoulder to the grip
const ARM_FORE: float = 5.4
const ARM_SLEEVE: Color = Color("503359")
const ARM_SLEEVE_SHADE: Color = Color("30203c")
const ARM_BRACER: Color = Color("241b3a")
const ARM_BRACER_LIGHT: Color = Color("3b3058")
const ARM_GLOVE: Color = Color("150f22")
const ARM_CUFF: Color = Color("8a5cf0")
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
var sheathed: bool = false ## set by the player while sneaking: the weapon fades out, and in again for a swing
var aim_dir: Vector2 = Vector2.RIGHT ## direction of the current swing
var rod_pose: Vector3 = Vector3.INF ## fishing: how the rod points (forward, side, lift) relative to where she faces, from the body clip; INF = resting pose
var always_drawn: bool = false ## a rod stays in the hand (it is no weapon: no swings, never put away)
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
var _blade_angle: float = 0.0
var _blade_length: float = 1.0
var _tips: Array[Dictionary] = [] ## the heavy blow's path: {mid (world), tip (world), age}
var _burst_life: float = BURST_LIFE
var _burst_heavy: bool = false
var _flash: float = 0.0 ## the fully-charged flash at the tip (seconds left)
var _sounds: Dictionary = {}
var _stamina: StaminaComponent

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
	_stamina = get_node_or_null("../StaminaComponent") as StaminaComponent
	_refresh_weapon()


func _process(delta: float) -> void:
	if _freeze > 0.0:
		_freeze -= delta ## hit stop: the swing stands still for a moment, the world runs on
	else:
		_advance(delta)
		if _charging:
			_charge_time += delta
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
	_trail.queue_redraw()


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
	return float(_step.get("noise", 1.0)) if is_heavy_swing() else 1.0


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


## For the body animation: x = which attack (0 forehand, 1 backhand, 2 thrust), y = keyframe position
## (-1..0 winding up into the first pose, 0..3 striking, 3..5 recovering). Zero when not swinging.
func animation_state() -> Vector2:
	if _phase == Phase.IDLE or _step.is_empty() or bool(_step.get("heavy", false)):
		return Vector2.ZERO
	var block: float = 2.0 if String(_step["style"]) == "thrust" else (0.0 if float(_step["sweep"]) < 0.0 else 1.0)
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


## Owner only: right mouse button went down. Starts charging the weapon's secondary attack everywhere.
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
	_trail_age = TRAIL_FADE
	_thrust_progress = 0.0
	_burst_done = false
	_tips.clear()
	_play_sound("swing", -3.0, 0.92 + 0.16 * float(step["power"]))


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
	var knockback: float = Items.stat(stack, "knockback", 0.0) * float(step["knock"])
	var targets: Array[HurtboxComponent] = HitScan.fan(self, origin, dir, Items.stat(stack, "reach", 20.0) * float(step["reach"]), float(step["arc"]), HURTBOX_MASK)
	for target: HurtboxComponent in targets:
		target.armor_floor = float(step.get("armor_floor", 0.0))
		target.take_hit(damage, origin, knockback, get_multiplayer_authority())
		target.armor_floor = 0.0
	if not targets.is_empty():
		_on_hit.rpc(_hit_point(targets[0]), dir, float(step["shake"]), float(step.get("hit_stop", 0.0)))


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
	if is_multiplayer_authority():
		hit_landed.emit(shake)


func _spawn_sparks(point: Vector2, dir: Vector2, heavy: bool = false) -> void:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	gradient.colors = PackedColorArray([Color("fff6dc"), Color("ffb347"), Color(1.0, 0.5, 0.2, 0.0)])
	var sparks: CPUParticles2D = CPUParticles2D.new()
	sparks.texture = SPARK_TEXTURE
	sparks.amount = 24 if heavy else 10
	sparks.lifetime = 0.28
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.direction = -dir
	sparks.spread = 75.0
	sparks.gravity = Vector2.ZERO
	sparks.initial_velocity_min = 50.0
	sparks.initial_velocity_max = 200.0 if heavy else 140.0
	sparks.damping_min = 160.0
	sparks.damping_max = 230.0
	sparks.scale_amount_min = 0.5
	sparks.scale_amount_max = 0.9
	sparks.color_ramp = gradient
	sparks.z_index = 20
	get_tree().current_scene.add_child(sparks)
	sparks.global_position = point
	sparks.emitting = true
	get_tree().create_timer(0.6).timeout.connect(sparks.queue_free)


func _combo_size(def: Dictionary) -> int:
	return (DataRegistry.get_entry("weapon_classes", String(def.get("weapon_class", ""))).get("combo", []) as Array).size()


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
		_motes.append({"pos": around, "vel": vel, "age": 0.0, "life": randf_range(0.18, 0.3), "kind": 0 if randf() < 0.8 else 1, "color": MOTE_COLORS[1 + randi() % 3], "size": randf_range(0.8, 1.2)})
	if _motes.size() > 260:
		_motes = _motes.slice(_motes.size() - 260)


## Remembers where the blade has been during a heavy blow, for the ribbon it leaves behind.
func _track_tips(delta: float) -> void:
	for i: int in range(_tips.size() - 1, -1, -1):
		_tips[i]["age"] = float(_tips[i]["age"]) + delta
		if float(_tips[i]["age"]) >= HEAVY_TRAIL_LIFE:
			_tips.remove_at(i)
	if is_heavy_swing() and _phase != Phase.WINDUP and _freeze <= 0.0:
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
	var path: String = HEAVY_SOUNDS + id + ".wav"
	var stream: AudioStream = _sounds.get(id) as AudioStream
	if stream == null:
		if not ResourceLoader.exists(path):
			return
		stream = load(path) as AudioStream
		_sounds[id] = stream
	var player: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.max_distance = 360.0
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


## A stack as every peer knows it from the synced item id and refinement level.
static func _stack_of(weapon_id: String, refine_level: int) -> Dictionary:
	var stack: Dictionary = {"id": weapon_id, "count": 1}
	if refine_level > 0:
		stack[RefineRules.KEY_LEVEL] = refine_level
	return stack


func _refresh_weapon() -> void:
	var def: Dictionary = DataRegistry.get_entry("items", held_weapon)
	always_drawn = String(def.get("tool", "")) == "rod"
	if _weapon == null:
		return
	_has_weapon = not def.is_empty()
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


## Rest: the hand holds the sword where the walk cycle puts it, blade forward (trailing behind
## while sprinting). Swings: the hand follows the body animation (the player feeds `rig_hand` from the
## attack keyframes); only the blade's angle and length come from here: cocked, sweep the arc (or drive
## straight for a thrust), return. The arm is drawn from the shoulder to the grip, so the sword is
## always in the hand.
func _update_pose(delta: float) -> void:
	var rest_dir: Vector2 = facing.normalized()
	var side: Vector2 = rest_dir.rotated(PI / 2.0) ## toward her right hand
	var rest_pos: Vector2 = rig_hand
	var rest_blade: Vector2 = _rod_blade(rest_dir, side) if rod_pose.is_finite() else _rest_blade(rest_dir, side)
	var ease_k: float = 1.0 - exp(-(30.0 if rod_pose.is_finite() else 16.0) * delta)
	_rest_angle = lerp_angle(_rest_angle, rest_blade.angle(), ease_k)
	_rest_length = lerpf(_rest_length, clampf(rest_blade.length(), 0.4, 1.0), ease_k)
	var rest_angle: float = _rest_angle
	var pos: Vector2 = rest_pos
	var angle: float = rest_angle
	var length: float = _rest_length
	var behind: bool = rest_dir.y < -0.35 or side.y < -0.35 ## the right hand is on the far side
	if _has_weapon and _charging:
		var draw: float = HeavyRules.draw_progress(_charge_cfg, _charge_time)
		var ease_draw: float = draw * draw * (3.0 - 2.0 * draw)
		var power: float = charge_amount()
		var blade: Vector2 = _chop_blade(lerpf(CHOP_PITCH_REST, CHOP_PITCH_UP, ease_draw), lerpf(0.2, CHOP_YAW_BACK, ease_draw))
		var shiver: float = power * 0.05 * sin(_charge_time * 55.0) ## a held, straining blade trembles
		angle = blade.angle() + shiver
		length = lerpf(_rest_length, clampf(blade.length(), 0.4, 1.0), minf(ease_draw * 1.5, 1.0))
		behind = aim_dir.y < -0.35
	elif _has_weapon and _phase != Phase.IDLE and not _step.is_empty() and bool(_step.get("heavy", false)):
		var aim_h: float = aim_dir.angle()
		behind = aim_dir.y < -0.35
		match _phase:
			Phase.WINDUP:
				var t: float = clampf(_time / float(_step["windup"]), 0.0, 1.0)
				var pulled: Vector2 = _chop_blade(lerpf(_release_pitch, CHOP_PITCH_WIND, t), lerpf(_release_yaw, CHOP_YAW_WIND, t))
				angle = pulled.angle()
				length = clampf(pulled.length(), 0.4, 1.0)
			Phase.ACTIVE:
				var t: float = clampf(_time / float(_step["active"]), 0.0, 1.0)
				var eased: float = pow(t, 1.5) ## a heavy blade starts slowly and arrives fast
				var chop: Vector2 = _chop_blade(lerpf(CHOP_PITCH_WIND, CHOP_PITCH_END, eased), lerpf(CHOP_YAW_WIND, CHOP_YAW_END, eased))
				angle = chop.angle()
				length = clampf(chop.length(), 0.4, 1.0)
				if t >= 0.85 and not _burst_done: ## the blow lands: a wide crescent and a puff of dust
					_burst_done = true
					_burst_age = 0.0
					_burst_life = HEAVY_BURST_LIFE
					_burst_heavy = true
					_burst_thrust = false
					_burst_angle = aim_h
					_burst_center = global_position + BODY_CENTER
					_impact_dust()
				_emit_motes(angle, 1.0, false, delta)
			Phase.RECOVERY:
				var t: float = clampf(_time / float(_step["recovery"]), 0.0, 1.0)
				var low: Vector2 = _chop_blade(CHOP_PITCH_END, CHOP_YAW_END)
				var settle: float = t * t * (3.0 - 2.0 * t)
				angle = lerp_angle(low.angle(), rest_angle, settle)
				length = lerpf(clampf(low.length(), 0.4, 1.0), _rest_length, settle)
	elif _has_weapon and _phase != Phase.IDLE and not _step.is_empty():
		var aim: float = aim_dir.angle()
		var half: float = float(_step["arc"]) / 2.0
		var sweep: float = float(_step["sweep"])
		var cocked: float = -(half + 0.6) ## blade offsets from the aim, in sweep direction
		var follow: float = half + 0.25
		var thrust: bool = String(_step["style"]) == "thrust"
		behind = aim_dir.y < -0.35
		match _phase:
			Phase.WINDUP:
				var t: float = clampf(_time / float(_step["windup"]), 0.0, 1.0)
				angle = lerp_angle(rest_angle, aim if thrust else aim + sweep * cocked, t)
				length = lerpf(_rest_length, 1.0, t)
			Phase.ACTIVE:
				var t: float = clampf(_time / float(_step["active"]), 0.0, 1.0)
				var eased: float = 1.0 - pow(1.0 - t, 3.0) ## fast start, soft end
				if t >= 0.9 and not _burst_done: ## the swing lands: a shock crescent (a ring for a thrust) flashes out
					_burst_done = true
					_burst_age = 0.0
					_burst_life = BURST_LIFE
					_burst_heavy = false
					_burst_thrust = thrust
					_burst_angle = aim if thrust else aim + sweep * lerpf(cocked, follow, eased)
					_burst_center = global_position + BODY_CENTER
				if thrust:
					angle = aim
					length = 1.0
					_thrust_progress = eased
					_emit_motes(angle, 0.0, true, delta)
				else:
					var offset: float = lerpf(cocked, follow, eased)
					angle = aim + sweep * offset
					length = 1.0
					_trail_head = clampf(offset, -half, half)
					_emit_motes(angle, sweep, false, delta)
			Phase.RECOVERY:
				var t: float = clampf(_time / float(_step["recovery"]), 0.0, 1.0)
				var end_angle: float = aim if thrust else aim + sweep * follow
				angle = lerp_angle(end_angle, rest_angle, t)
				length = lerpf(1.0, _rest_length, t)
	pos = rig_shoulder + (pos - rig_shoulder).limit_length(ARM_UPPER + ARM_FORE - 0.6) ## the arm only reaches so far
	_hand.position = Vector2(0, -HAND_SORT if behind else HAND_SORT)
	_blade_angle = angle
	_blade_scale = length
	_grip = pos
	_weapon.position = (pos - _hand.position).round() + Vector2(0.5, 0.5) ## the middle of the glove's pixel
	var step: int = roundi(wrapf(angle, 0.0, TAU) / TAU * float(ROT_ANGLES)) % ROT_ANGLES
	var level: int = 0
	for i: int in ROT_LENGTHS.size(): ## nearest foreshortening
		if absf(ROT_LENGTHS[i] - length) < absf(ROT_LENGTHS[level] - length):
			level = i
	_weapon.frame = level * ROT_ANGLES + step
	_blade_angle = angle
	_blade_length = length
	var busy: bool = _phase != Phase.IDLE or _charging
	_since_swing = 0.0 if busy else _since_swing + delta
	var hide: bool = (sheathed or (_since_swing > OUT_OF_COMBAT and not always_drawn)) and not busy ## a swing always draws the weapon
	_weapon_alpha = 1.0 if not hide and busy else move_toward(_weapon_alpha, 0.0 if hide else 1.0, 8.0 * delta)
	_weapon.modulate.a = _weapon_alpha
	_weapon.visible = _has_weapon and _weapon_alpha > 0.01
	_arm.queue_redraw()


## Where the blade points on screen when it stands `pitch` above the horizon (above 90 deg = leaning back) and `yaw` radians
## from her aim toward her sword side, seen in the 3/4 perspective (same projection as the resting blade).
func _chop_blade(pitch: float, yaw: float) -> Vector2:
	var ground: Vector2 = aim_dir.normalized().rotated(yaw) * cos(pitch)
	var lift: float = sin(pitch)
	return Vector2(ground.x, ground.y * DEPTH_SQUASH - lift * 0.9)


## The rod as the fishing clip holds it: `rod_pose` = (forward, side, lift) in her own frame, seen in the 3/4 perspective.
func _rod_blade(rest_dir: Vector2, side: Vector2) -> Vector2:
	var ground: Vector2 = rest_dir * rod_pose.x + side * rod_pose.y
	var lift: float = rod_pose.z
	var length3d: float = maxf(sqrt(ground.length_squared() + lift * lift), 0.001)
	return Vector2(ground.x, ground.y * DEPTH_SQUASH - lift * 0.9) / length3d


## Where the resting blade points on screen: seen in perspective, it leans forward and up (or
## trails back and down while sprinting), so a blade pointing at the camera comes out short.
func _rest_blade(rest_dir: Vector2, side: Vector2) -> Vector2:
	var ground: Vector2 = rest_dir * 0.75 + side * 0.3
	var lift: float = 0.55
	if carrying:
		ground = -rest_dir * 0.8 + side * 0.35
		lift = -0.4
	var length3d: float = sqrt(ground.length_squared() + lift * lift)
	return Vector2(ground.x, ground.y * DEPTH_SQUASH - lift * 0.9) / length3d


## Her sword arm: a coat sleeve to the elbow, a dark bracer to the wrist, a glove on the grip. Pixel steps
## instead of lines so it stays crisp at any angle.
func _draw_arm() -> void:
	var origin: Vector2 = _hand.position
	var shoulder: Vector2 = (rig_shoulder - origin).round()
	var hand: Vector2 = (_grip - origin).round()
	var elbow: Vector2 = _elbow(shoulder, hand).round()
	_pixel_line(shoulder, elbow, ARM_SLEEVE, ARM_SLEEVE_SHADE)
	_pixel_line(elbow, hand, ARM_BRACER, ARM_BRACER_LIGHT)
	_arm.draw_rect(Rect2(elbow.lerp(hand, 0.62) - Vector2(1.0, 1.0), Vector2(2.0, 2.0)), ARM_CUFF)
	_arm.draw_rect(Rect2(hand - Vector2(1.0, 1.0), Vector2(3.0, 3.0)), ARM_GLOVE)
	_arm.draw_rect(Rect2(hand - Vector2(1.0, 1.0), Vector2(1.0, 1.0)), ARM_BRACER_LIGHT)


func _pixel_line(from: Vector2, to: Vector2, color: Color, shade: Color) -> void:
	var steps: int = maxi(1, ceili(from.distance_to(to)))
	for i: int in steps + 1:
		var p: Vector2 = from.lerp(to, float(i) / float(steps)).round()
		_arm.draw_rect(Rect2(p - Vector2(1.0, 1.0), Vector2(2.0, 2.0)), shade)
		_arm.draw_rect(Rect2(p - Vector2(1.0, 1.0), Vector2(1.0, 1.0)), color)


## Two-bone solve: the elbow hangs low, like a relaxed arm.
func _elbow(shoulder: Vector2, hand: Vector2) -> Vector2:
	var to: Vector2 = hand - shoulder
	var dist: float = clampf(to.length(), 1.0, ARM_UPPER + ARM_FORE - 0.01)
	var dir: Vector2 = to.normalized() if to.length() > 0.01 else Vector2.DOWN
	var along: float = (dist * dist + ARM_UPPER * ARM_UPPER - ARM_FORE * ARM_FORE) / (2.0 * dist)
	var bend: float = sqrt(maxf(ARM_UPPER * ARM_UPPER - along * along, 0.0))
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var first: Vector2 = shoulder + dir * along + perp * bend
	var second: Vector2 = shoulder + dir * along - perp * bend
	return first if first.y >= second.y else second


## The blade's trail: a wedge that grows with the sweep, brightest at the blade, fading afterwards.
func _draw_trail() -> void:
	var alpha: float = 1.0 - _trail_age / TRAIL_FADE
	_draw_heavy_ribbon()
	if alpha > 0.0 and not _step.is_empty() and not bool(_step.get("heavy", false)):
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
		var color: Color = TRAIL_EDGE.lerp(TRAIL_CORE, k)
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
	var color: Color = MOTE_COLORS[0]
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


## The blade sheds sparkles while it is in the air: they fly on along its path, rise a little and fade.
func _emit_motes(angle: float, sweep: float, thrust: bool, delta: float) -> void:
	_mote_carry += delta * MOTES_PER_SEC
	var origin: Vector2 = global_position + BODY_CENTER
	var along: Vector2 = Vector2.from_angle(angle)
	while _mote_carry >= 1.0:
		_mote_carry -= 1.0
		var radius: float = _reach * randf_range(0.8, 1.0)
		var flight: Vector2 = along if thrust else along.rotated(sweep * PI / 2.0) ## the way the blade is moving
		var kind: int = [0, 0, 0, 0, 0, 1][randi() % 6]
		var color: Color = MOTE_COLORS[1 + randi() % 2]
		var speed: float = randf_range(18.0, 55.0)
		var vel: Vector2 = flight * speed + along * randf_range(-12.0, 30.0) + Vector2(randf_range(-14.0, 14.0), randf_range(-14.0, 6.0))
		_motes.append({"pos": origin + along * radius + along.rotated(PI / 2.0) * randf_range(-1.5, 1.5), "vel": vel, "age": 0.0, "life": randf_range(0.2, 0.42), "kind": kind, "color": color, "size": randf_range(0.8, 1.3)})
	if _motes.size() > 260:
		_motes = _motes.slice(_motes.size() - 260)


func _update_motes(delta: float) -> void:
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
	if _burst_age < _burst_life:
		_burst_age += delta


func _draw_motes() -> void:
	for mote: Dictionary in _motes:
		var k: float = float(mote["age"]) / float(mote["life"])
		var color: Color = mote["color"] as Color
		color.a = clampf((1.0 - k) * 1.5, 0.0, 1.0) * 0.8 * (0.8 + 0.2 * sin(float(mote["age"]) * 40.0 + float(mote["size"]) * 9.0)) ## a faint twinkle
		var at: Vector2 = _trail.to_local(mote["pos"] as Vector2).round()
		var size: float = float(mote["size"]) * (1.0 - 0.5 * k)
		match int(mote["kind"]):
			0: ## a speck
				var side: float = 1.0
				_trail.draw_rect(Rect2(at, Vector2(side, side)), color)
			1: ## a four-point glint
				var arm: float = 1.0
				_trail.draw_rect(Rect2(at - Vector2(arm, 0), Vector2(arm * 2.0 + 1.0, 1)), color)
				_trail.draw_rect(Rect2(at - Vector2(0, arm), Vector2(1, arm * 2.0 + 1.0)), color)
				var core: Color = MOTE_COLORS[0]
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
		var color: Color = MOTE_COLORS[1 - layer] if _burst_heavy else MOTE_COLORS[1]
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


func _draw_slash_trail(alpha: float) -> void:
	var aim: float = aim_dir.angle()
	var sweep: float = float(_step["sweep"])
	var from_offset: float = -float(_step["arc"]) / 2.0
	var span: float = _trail_head - from_offset
	if span <= 0.02:
		return
	for i: int in TRAIL_STEPS:
		var k0: float = float(i) / TRAIL_STEPS
		var k1: float = float(i + 1) / TRAIL_STEPS
		var a0: float = aim + sweep * (from_offset + span * k0)
		var a1: float = aim + sweep * (from_offset + span * k1)
		var outer: float = _reach
		var inner: float = _reach - lerpf(1.5, 9.0, k1)
		var color: Color = TRAIL_EDGE.lerp(TRAIL_CORE, k1)
		color.a = alpha * lerpf(0.1, 0.95, k1)
		_trail.draw_colored_polygon(PackedVector2Array([
			BODY_CENTER + Vector2.from_angle(a0) * inner, BODY_CENTER + Vector2.from_angle(a0) * outer,
			BODY_CENTER + Vector2.from_angle(a1) * outer, BODY_CENTER + Vector2.from_angle(a1) * inner]), color)


func _draw_thrust_trail(alpha: float) -> void:
	var perp: Vector2 = aim_dir.rotated(PI / 2.0)
	var tail: Vector2 = BODY_CENTER + aim_dir * 2.0
	var tip: Vector2 = BODY_CENTER + aim_dir * (2.0 + (_reach - 2.0) * _thrust_progress)
	for layer: int in 2:
		var width: float = 4.0 - layer * 2.0
		var color: Color = TRAIL_EDGE.lerp(TRAIL_CORE, float(layer))
		color.a = alpha * (0.6 + 0.3 * layer)
		_trail.draw_colored_polygon(PackedVector2Array([tail + perp * 0.4, tip + perp * width, tip - perp * width, tail - perp * 0.4]), color)


@rpc("any_peer", "call_local", "reliable")
func _confirm_stage(weapon: String, stage: int) -> void:
	if multiplayer.get_remote_sender_id() <= 1 and is_multiplayer_authority():
		combo_stage.emit(weapon, stage)
