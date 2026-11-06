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
