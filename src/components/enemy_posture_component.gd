class_name EnemyPostureComponent
extends Node
## Reusable V2 directional hit-zone & posture/stagger component (`T5`):
## - Front guard (`COIL` / `OBSERVE` / `CREVICE_CROUCH`): folded raptorial forelimbs soften light frontal grazing (`0.85x`).
## - Rear/Flank Opisthosoma weakpoint: Movement-2.0 strafing behind/beside the creature deals `1.25x` damage + `1.8x` posture break!
## - `EXPOSED` knockdown state: heavy blow interruption (`knockback >= expose_knockback`) or full posture depletion opens
##   a clear `1.1 s` critical punish window (`1.35x` damage).

signal posture_broken(from: Vector2)

var max_posture: float = 34.0
var posture: float = 34.0
var regen_delay: float = 2.4
var regen_per_sec: float = 8.0
var front_guard_mult: float = 0.85
var rear_weak_mult: float = 1.25
var exposed_mult: float = 1.35
var exposed_seconds: float = 1.1
var expose_knockback: float = 108.0

var _regen_wait: float = 0.0


func configure(enemy_def: Dictionary, health_scale: float = 1.0) -> void:
	var cfg: Dictionary = enemy_def.get("posture", {}) as Dictionary
	max_posture = float(cfg.get("max", 34.0)) * maxf(0.8, sqrt(health_scale))
	posture = max_posture
	regen_delay = float(cfg.get("regen_delay", 2.4))
	regen_per_sec = float(cfg.get("regen_per_sec", 8.0))
	front_guard_mult = float(cfg.get("front_guard_mult", 0.85))
	rear_weak_mult = float(cfg.get("rear_weak_mult", 1.25))
	exposed_mult = float(cfg.get("exposed_mult", 1.35))
	exposed_seconds = float(cfg.get("exposed_seconds", 1.1))
	expose_knockback = float(cfg.get("expose_knockback", 108.0))


func tick(delta: float, is_exposed: bool) -> void:
	if is_exposed:
		return
	if _regen_wait > 0.0:
		_regen_wait = maxf(0.0, _regen_wait - delta)
	elif posture < max_posture:
		posture = minf(max_posture, posture + regen_per_sec * delta)


func restore_full() -> void:
	posture = max_posture
	_regen_wait = 0.0


## Computes the directional damage multiplier for a weapon/spell hit arriving from world `from_pos`
## and accumulates posture strain on the host.
func evaluate_incoming_hit(
	damage: float,
	from_pos: Vector2,
	knockback: float,
	body_pos: Vector2,
	heading: float,
	front_guarded: bool,
	is_exposed: bool,
	can_break_now: bool,
	is_server: bool
) -> float:
	if is_exposed:
		return maxf(1.0, roundf(damage * exposed_mult))

	var to_attacker: Vector2 = from_pos - body_pos
	var mult: float = 1.0
	var posture_mult: float = 1.0
	if to_attacker.length_squared() > 1.0:
		var ang: float = absf(angle_difference(heading, to_attacker.angle()))
		if ang >= deg_to_rad(108.0):
			# Direct strike into the soft, pulsing rear Opisthosoma spore-sac!
			mult = rear_weak_mult
			posture_mult = 1.80
		elif ang <= deg_to_rad(52.0) and front_guarded and knockback < expose_knockback:
			mult = front_guard_mult

	var final_dmg: float = maxf(1.0, roundf(damage * mult))

	if is_server and can_break_now:
		_regen_wait = regen_delay
		var strain: float = (damage * 0.65 + knockback * 0.14) * posture_mult
		posture = maxf(0.0, posture - strain)
		if posture <= 0.0 or knockback >= expose_knockback:
			posture = max_posture
			posture_broken.emit(from_pos)

	return final_dmg
