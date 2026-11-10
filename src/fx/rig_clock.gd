class_name RigClock
extends RefCounted
## Paces a procedural creature rig (geometry rebuild + GDScript pixel drawing, milliseconds each): on screen it is rebuilt
## `hz` times a second (faster while the creature runs, so planted feet do not skate), off screen only a few times
## (nobody sees it; its timing still advances). Same idea as `SkyCleaverRig.tick_hz`.
## Use at the top of `update_rig`: `delta = _clock.step(self, delta, velocity.length())`, `if delta < 0.0: return`.

const OFFSCREEN_HZ: float = 10.0
const FAST_SPEED: float = 110.0 ## px/s: above this the rig follows every frame up to `fast_hz`
const SCREEN_MARGIN: float = 120.0 ## px around the view that still count as on screen (limbs reach out)
const MAX_STEP: float = 0.12 ## a frame hitch is advanced as at most this much (springs and steps stay stable)

var hz: float = 30.0
var fast_hz: float = 60.0
var _acc: float = 0.0


func _init(rate: float = 30.0, fast_rate: float = 60.0) -> void:
	hz = rate
	fast_hz = fast_rate


## The delta to rebuild with now, or -1 when this frame is skipped.
func step(rig: CanvasItem, delta: float, speed: float = 0.0) -> float:
	if delta <= 0.0:
		return delta
	_acc += delta
	var rate: float = OFFSCREEN_HZ
	if on_screen(rig):
		rate = fast_hz if speed > FAST_SPEED else hz
	if _acc < 1.0 / rate - 0.0005:
		return -1.0
	var out: float = minf(_acc, MAX_STEP)
	_acc = 0.0
	return out


static func on_screen(item: CanvasItem) -> bool:
	if not item.is_inside_tree():
		return false
	var view: Rect2 = item.get_viewport_rect().grow(SCREEN_MARGIN)
	return view.has_point(item.get_global_transform_with_canvas().origin)
