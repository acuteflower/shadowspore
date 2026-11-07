class_name VoidGlow
extends RefCounted
## The shared violet light of every shadow creature (spider, listener, crusher): one heartbeat that pulses its veins, and one soft pixel bloom for veins, cores and eyes.
## Callers draw on an additive, unshaded canvas; `strength` is already multiplied by the creature's own fade.

const INTENSITY: float = 0.78 ## one knob for the light of every shadow creature
const VEIN: Color = Color("7d57e0") ## slightly cooler and less saturated than the first violet
const VEIN_LIGHT: Color = Color("a98af0")
const BLOOM_OUTER: float = 0.035
const BLOOM_MID: float = 0.09
const BLOOM_VEIN: float = 0.1 ## the thin halo of a vein pixel: veins are drawn pixel after pixel, so more would stack into a solid tube
const BLOOM_SPOT: float = 0.22


## A double heartbeat (lub-dub) in 0..1; `phase` offsets it, a vein passes `-distance * 0.012` so the pulse runs along it.
static func beat(time: float, phase: float = 0.0, rate: float = 0.8) -> float:
	var x: float = fposmod(time * rate + phase, 1.0)
	return clampf(exp(-pow((x - 0.08) * 13.0, 2.0)) + 0.65 * exp(-pow((x - 0.3) * 13.0, 2.0)), 0.0, 1.0)


## The resting glow with the heartbeat on top: never fully dark, bright on the beat.
static func pulse(time: float, phase: float = 0.0, rate: float = 0.8, floor_value: float = 0.38) -> float:
	return floor_value + (1.0 - floor_value) * beat(time, phase, rate)


## A one pixel light. `bloom` up to 0.5 is a vein pixel (a faint 3x3 so a line stays a thin line); above it is an eye or a core: a stronger 3x3 plus 5x5 and 7x7 steps that scale with `bloom`.
static func halo(canvas: CanvasItem, point: Vector2, color: Color, strength: float, bloom: float = 0.5) -> void:
	if strength <= 0.01:
		return
	var at: Vector2 = point.round()
	var s: float = clampf(strength * INTENSITY, 0.0, 1.5)
	var spot: bool = bloom > 0.5
	if spot:
		canvas.draw_rect(Rect2(at - Vector2(3, 3), Vector2(7, 7)), Color(color, s * BLOOM_OUTER * bloom))
		canvas.draw_rect(Rect2(at - Vector2(2, 2), Vector2(5, 5)), Color(color, s * BLOOM_MID * bloom))
	canvas.draw_rect(Rect2(at - Vector2.ONE, Vector2(3, 3)), Color(color, s * (BLOOM_SPOT if spot else BLOOM_VEIN)))
	canvas.draw_rect(Rect2(at, Vector2.ONE), Color(color.lerp(Color.WHITE, 0.25 * minf(s, 1.0)), minf(1.0, s)))
