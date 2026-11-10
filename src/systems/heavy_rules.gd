class_name HeavyRules
extends RefCounted
## Pure rules of the right-click attack of a weapon class ("secondary" block in data/weapon_classes.json). Today there is
## one kind, `charge_strike` (the sword's Wuchtschlag): hold to charge, let go to strike. Nothing here touches nodes,
## so the host, the owner and the tests all ask the same questions. Numbers: docs/heavy_attack.md.

const KIND_CHARGE: String = "charge_strike"
const KIND_RIFT: String = "rift_slash" ## the Himmelsriss: no charging, two diagonal slashes that shoot feathers (docs/rissklinge.md)


## The secondary block of an item's weapon class, {} when the weapon has none.
static func config(item_def: Dictionary) -> Dictionary:
	var cls: Dictionary = DataRegistry.get_entry("weapon_classes", String(item_def.get("weapon_class", "")))
	var cfg: Variant = cls.get("secondary", {})
	return cfg as Dictionary if cfg is Dictionary else {}


static func has_secondary(item_def: Dictionary) -> bool:
	return String(config(item_def).get("kind", "")) == KIND_CHARGE


## 0..1 over the draw-back (she pulls the blade over her shoulder).
static func draw_progress(cfg: Dictionary, charge_time: float) -> float:
	return clampf(charge_time / maxf(float(cfg.get("draw", 0.25)), 0.01), 0.0, 1.0)


## True once the blow would be worth releasing; `chained` = it follows a light hit within the combo window.
static func is_ready(cfg: Dictionary, charge_time: float, chained: bool = false) -> bool:
	return charge_time >= minimum(cfg, chained)


static func minimum(cfg: Dictionary, chained: bool = false) -> float:
	return float(cfg.get("chain_min", 0.2)) if chained else float(cfg.get("charge_min", 0.35))


## Charge strength 0 (just ready) .. 1 (fully charged), smooth in between. Below the minimum it is 0 too.
static func power(cfg: Dictionary, charge_time: float, chained: bool = false) -> float:
	var lo: float = minimum(cfg, chained)
	var hi: float = maxf(float(cfg.get("charge_full", 1.0)), lo + 0.01)
	var k: float = clampf((charge_time - lo) / (hi - lo), 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)


## Seconds she has been holding at full charge.
static func overcharge(cfg: Dictionary, charge_time: float) -> float:
	return maxf(charge_time - float(cfg.get("charge_full", 1.0)), 0.0)


## She cannot hold the blade any longer and lets go by herself.
static func must_release(cfg: Dictionary, charge_time: float) -> bool:
	return overcharge(cfg, charge_time) >= float(cfg.get("hold_extra", 1.0))


static func stamina_cost(cfg: Dictionary) -> float:
	return float(cfg.get("stamina_cost", 20))


## Stamina needed to start charging (the same as the blow costs).
static func can_start(cfg: Dictionary, stamina: float) -> bool:
	return stamina >= stamina_cost(cfg)


## One strike as a swing step in the shape `AttackComponent` uses (multipliers of the weapon's stats, times scaled by its
## `speed` stat; the charge time itself is not scaled). `charge_time` decides the strength.
static func step(cfg: Dictionary, item_def: Dictionary, charge_time: float, chained: bool = false) -> Dictionary:
	if cfg.is_empty():
		return {}
	var p: float = power(cfg, charge_time, chained)
	var speed: float = maxf(float(item_def.get("stats", {}).get("speed", 1.0)), 0.1)
	return {
		"style": "chop",
		"heavy": true,
		"power": p,
		"sweep": 1.0,
		"arc": deg_to_rad(float(cfg.get("arc", 150))),
		"windup": float(cfg.get("windup", 0.08)) / speed,
		"active": float(cfg.get("active", 0.12)) / speed,
		"recovery": float(cfg.get("recovery", 0.65)) / speed,
		"damage": lerpf(float(cfg.get("damage_min", 2.2)), float(cfg.get("damage_full", 3.4)), p),
		"reach": float(cfg.get("reach", 1.25)),
		"knock": lerpf(float(cfg.get("knock_min", 2.0)), float(cfg.get("knock_full", 3.0)), p),
		"lunge": lerpf(float(cfg.get("lunge_min", 230)), float(cfg.get("lunge_full", 300)), p),
		"shake": lerpf(float(cfg.get("shake_min", 3.0)), float(cfg.get("shake_full", 7.0)), p),
		"armor_floor": float(cfg.get("armor_floor", 0.0)),
		"hit_stop": float(cfg.get("hit_stop", 0.06)),
		"noise": float(cfg.get("noise", 1.0)),
	}


## The right click of the Himmelsriss is no charge but a chain of two slashes (`secondary.kind` "rift_slash", `steps` [stage 1, stage 2]).
static func is_rift_slash(cfg: Dictionary) -> bool:
	return String(cfg.get("kind", "")) == KIND_RIFT


static func rift_steps(cfg: Dictionary) -> int:
	return (cfg.get("steps", []) as Array).size() if is_rift_slash(cfg) else 0


## Stamina one slash costs (stage 1 or 2).
static func rift_cost(cfg: Dictionary, stage: int) -> float:
	var steps: Array = cfg.get("steps", []) as Array
	return float((steps[clampi(stage - 1, 0, steps.size() - 1)] as Dictionary).get("stamina_cost", 20)) if not steps.is_empty() else 0.0


## Seconds after a slash ends in which the second right click still continues the chain.
static func rift_window(cfg: Dictionary) -> float:
	return float(cfg.get("window", 0.6))


## One slash of the chain as a swing step in the shape `AttackComponent` uses (times scaled by the weapon's `speed` stat). `stage` 1 or 2. Carries `diag`
## (the blade's path in radians: pitch above the horizon and yaw toward her sword side, start and end) and `volley` (the feathers it shoots).
static func rift_step(cfg: Dictionary, item_def: Dictionary, stage: int) -> Dictionary:
	var steps: Array = cfg.get("steps", []) as Array
	if not is_rift_slash(cfg) or steps.is_empty():
		return {}
	var index: int = clampi(stage - 1, 0, steps.size() - 1)
	var data: Dictionary = steps[index] as Dictionary
	var speed: float = maxf(float(item_def.get("stats", {}).get("speed", 1.0)), 0.1)
	var diag: Dictionary = data.get("diag", {}) as Dictionary
	return {
		"style": "slash",
		"alt": true,
		"stage": index + 1,
		"name": String(data.get("name", "")),
		"sweep": float(data.get("sweep", 1)),
		"arc": deg_to_rad(float(data.get("arc", 120))),
		"windup": float(data.get("windup", 0.1)) / speed,
		"active": float(data.get("active", 0.1)) / speed,
		"recovery": float(data.get("recovery", 0.4)) / speed,
		"damage": float(data.get("damage", 1.5)),
		"reach": float(data.get("reach", 1.2)),
		"knock": float(data.get("knock", 1.5)),
		"lunge": float(data.get("lunge", 0)),
		"shake": float(data.get("shake", 3.0)),
		"block": -1,
		"requires": "",
		"rift": "",
		"noise": float(cfg.get("noise", 1.0)),
		"diag": {"pitch0": deg_to_rad(float(diag.get("pitch0", 70))), "pitch1": deg_to_rad(float(diag.get("pitch1", -10))), "yaw0": deg_to_rad(float(diag.get("yaw0", 60))), "yaw1": deg_to_rad(float(diag.get("yaw1", -60)))},
		"volley": data.get("volley", {}) as Dictionary,
	}


## The numbers of one rift part ("passive": the thrust's lane) of a weapon class's `secondary.rift` block ({} when there is none).
static func rift_data(cfg: Dictionary, key: String) -> Dictionary:
	var rift: Variant = cfg.get("rift", {})
	if rift is Dictionary and (rift as Dictionary).get(key, {}) is Dictionary:
		return (rift as Dictionary).get(key, {}) as Dictionary
	return {}


## The charge time a hold of `real` seconds reaches when the charge runs `rate` times as fast up to the full charge (a talisman's Aufladetempo); the extra
## hold beyond it runs in real time, so the bracelet never shortens how long she may hold.
static func scaled_time(real: float, cfg: Dictionary, rate: float) -> float:
	var fast: float = float(cfg.get("charge_full", 1.0)) / maxf(rate, 0.01)
	return real * rate if real <= fast else float(cfg.get("charge_full", 1.0)) + (real - fast)


## The host's idea of how long the owner really held: never more than the host saw, never less than what the owner claims minus a little jitter.
static func host_charge(claimed: float, seen: float, cfg: Dictionary) -> float:
	var cap: float = float(cfg.get("charge_full", 1.0)) + float(cfg.get("hold_extra", 1.0))
	return clampf(minf(claimed, seen + 0.15), 0.0, cap)


## Key position on the heavy sheet (0..HEAVY_KEYS-1, see tools/art_hero_heavy.py) while charging.
static func charge_key(cfg: Dictionary, charge_time: float) -> float:
	var draw: float = draw_progress(cfg, charge_time)
	var ease_draw: float = draw * draw * (3.0 - 2.0 * draw)
	return ease_draw * 2.0 + power(cfg, charge_time) * 1.0
