class_name StealthComponent
extends Node
## Sneak state. Enemies will scale their sight range by `detection_multiplier()` (not wired yet).

signal sneaking_changed(sneaking: bool)

@export var sneak_detection_multiplier: float = 0.5 ## 0.5 = enemies see half as far while sneaking

var surface_noise_mult: float = 1.0 ## Movement 2.0 (T12): moss/grass dampens footsteps, stone/puddle amplifies them
var shadow_cover: float = 0.0 ## Movement 2.0 (V9): 0..1 canopy/tall-grass/night shadow cover while sneaking
var impulse_bonus: float = 0.0 ## brief acoustic spike on hard sprint-pivots or ledge landings, decays quickly

var sneaking: bool = false:
	set(value):
		if value == sneaking:
			return
		sneaking = value
		sneaking_changed.emit(sneaking)


func detection_multiplier() -> float:
	var vt: VeilThreads = VeilThreads.of(get_tree()) if is_inside_tree() else null
	var spore_scale: float = vt.stealth_spook_scale() if vt != null else 1.0
	if not sneaking:
		return spore_scale
	var shade_bonus: float = lerpf(1.0, float(MovementRules.section("impulse").get("shadow_stealth_bonus", 0.76)), clampf(shadow_cover, 0.0, 1.0))
	return sneak_detection_multiplier * shade_bonus * spore_scale


## Talismans (Schweigtropfen), weather cover, and Movement 2.0 surface acoustics (`surface_noise_mult` + brief `impulse_bonus`).
func alarm_scale() -> float:
	var talismans: TalismanComponent = get_node_or_null("../TalismanComponent") as TalismanComponent
	var base: float = talismans.alarm_scale() if talismans != null else 1.0
	var owner_node: Node2D = get_parent() as Node2D
	var weather: float = WeatherManager.current.alarm_factor_at(owner_node.global_position) if WeatherManager.current != null and owner_node != null else 1.0
	return base * weather * clampf(surface_noise_mult + impulse_bonus, 0.65, 1.45)
