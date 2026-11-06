class_name CookingTiming
extends RefCounted
## A reversible, frame-rate independent timing gesture. Reading the book pauses it.
const PERFECT: float = 0.055
const GOOD: float = 0.16
var running: bool = false
var elapsed: float = 0.0
var position: float = 0.12
var speed: float = 0.55

func begin() -> void:
	elapsed = 0.0
	position = 0.12
	running = true

func advance(delta: float) -> void:
	if not running: return
	elapsed += maxf(0.0,delta)
	var phase: float = fposmod(0.12+elapsed*speed,2.0)
	position = phase if phase<=1.0 else 2.0-phase

static func grade(at: float) -> String:
	var distance: float = absf(clampf(at,0.0,1.0)-0.5)
	return "perfect" if distance<=PERFECT else ("good" if distance<=GOOD else "rough")

func hit() -> Dictionary:
	if not running: return {}
	running = false
	return {"position":position,"grade":grade(position)}
