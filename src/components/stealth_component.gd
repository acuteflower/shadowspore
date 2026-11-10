class_name StealthComponent
extends Node
## Sneak state. Enemies will scale their sight range by `detection_multiplier()` (not wired yet).

signal sneaking_changed(sneaking: bool)

@export var sneak_detection_multiplier: float = 0.5 ## 0.5 = enemies see half as far while sneaking

var sneaking: bool = false:
	set(value):
		if value == sneaking:
			return
		sneaking = value
		sneaking_changed.emit(sneaking)


func detection_multiplier() -> float:
	return sneak_detection_multiplier if sneaking else 1.0


## Talismans (Schweigtropfen): shadow creatures notice her only from this fraction of their usual distance (sight and hearing). 1 without them.
func alarm_scale() -> float:
	var talismans: TalismanComponent = get_node_or_null("../TalismanComponent") as TalismanComponent
	var base: float = talismans.alarm_scale() if talismans != null else 1.0
	var owner_node: Node2D = get_parent() as Node2D
	var weather: float = WeatherManager.current.alarm_factor_at(owner_node.global_position) if WeatherManager.current != null and owner_node != null else 1.0
	return base * weather ## rain and thunder swallow footsteps and cover her outline (docs/wetter_konzept.md 9)
