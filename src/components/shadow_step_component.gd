class_name ShadowStepComponent
extends Node
## The shadow step's cooldown bookkeeping (the first and only ability of the void branch). The player does the step itself
## (`Player._try_shadow_step`, `play_shadow_step`); the HUD's skill crystal (`BlinkIcon`) reads this. Talismans that shorten
## the old blink's pause (Rissfeder, `blink_cooldown`) shorten the step's pause instead.

signal cooldown_changed(left: float, total: float)

@export var cooldown: float = 0.8 ## seconds

var cooldown_left: float = 0.0
var total: float = 0.0 ## the length of the cooldown that runs now


func _process(delta: float) -> void:
	if cooldown_left > 0.0:
		cooldown_left = maxf(cooldown_left - delta, 0.0)
		cooldown_changed.emit(cooldown_left, total)


func is_ready() -> bool:
	return cooldown_left <= 0.0


func start_cooldown() -> void:
	var talismans: TalismanComponent = get_node_or_null("../TalismanComponent") as TalismanComponent
	total = cooldown * (talismans.blink_scale() if talismans != null else 1.0)
	cooldown_left = total
	cooldown_changed.emit(cooldown_left, total)
