class_name GripRig
extends RefCounted
## The held-item system's geometry (docs/griff_system.md): everything she holds lives in the same small 3D world as her body model in
## tools/art_hero3d.py and is projected the same way, so a blade swings through space instead of turning like a clock hand on the screen.
##
## Space: x = east (screen right), y = south along the ground (toward the camera), z = up; one unit = one art pixel, the origin is her feet.
## The renderer looks down at PITCH 26 degrees: a point's screen position is (x, y sin - z cos), its depth toward the camera y cos + z sin.
## Pure functions only: every peer computes the same pose from the same synced state.

const SINP: float = 0.43837 ## sin(26 deg), the same camera as art_hero3d.py
const COSP: float = 0.89879
const SCALE: float = 0.92 ## art_hero3d.SCALE: model units to pixels
const UPPER: float = 6.6 * SCALE ## upper arm, shoulder to elbow (the renderer's ik2 lengths)
const FORE: float = 6.0 * SCALE ## forearm, elbow to wrist
const PALM: float = 0.9 * SCALE ## wrist to the middle of the fist (the rig's "hand" point = where the grip sits)
const SHOULDER_OUT: float = 4.5 * SCALE ## her right shoulder sits this far to her right of the body's axis
const LIGHT: Vector3 = Vector3(-0.5, 0.5, 0.72) ## art_hero3d LIGHT (-0.5, 0.72, 0.5) in this space (y and z swapped); normalised in `light()`
const SCREEN_DOWN: Vector3 = Vector3(0.0, SINP, -COSP) ## the 3D direction that shows as straight down on the screen with no depth
const VIEW: Vector3 = Vector3(0.0, COSP, SINP) ## toward the camera

static var _data: Dictionary = {}


## Screen position (relative to the feet) of a point.
static func screen(p: Vector3) -> Vector2:
	return Vector2(p.x, p.y * SINP - p.z * COSP)


## How far a point is toward the camera (bigger = in front).
static func depth(p: Vector3) -> float:
	return p.y * COSP + p.z * SINP


## The 3D point that shows at `at` on the screen and lies `toward` units south (toward the camera) of the feet.
static func lift(at: Vector2, toward: float) -> Vector3:
	return Vector3(at.x, toward, (toward * SINP - at.y) / COSP)


## A direction from its compass angle on the ground (screen angle convention: 0 east, PI/2 south) and its pitch above the horizon.
static func dir(yaw: float, pitch: float) -> Vector3:
	return Vector3(cos(pitch) * cos(yaw), cos(pitch) * sin(yaw), sin(pitch))


static func yaw_of(d: Vector3) -> float:
	return atan2(d.y, d.x)


static func pitch_of(d: Vector3) -> float:
	return atan2(d.z, Vector2(d.x, d.y).length())


## A direction given in her own frame: `yaw` radians from `forward` toward her right hand (+), `pitch` above the horizon.
static func body_dir(forward: Vector2, yaw: float, pitch: float) -> Vector3:
	return dir(forward.angle() + yaw, pitch)


## Her right hand's side of a ground direction (screen convention, y down).
static func right_of(forward: Vector2) -> Vector2:
	return Vector2(-forward.y, forward.x)


## A body-frame offset (forward, right, up) as a 3D vector.
static func body_offset(forward: Vector2, right: Vector2, v: Vector3) -> Vector3:
	var g: Vector2 = forward * v.x + right * v.y
	return Vector3(g.x, g.y, v.z)


## How a unit direction shows on the screen: the vector a one pixel long item would cover (shorter when it points at or away from the camera).
static func project_dir(d: Vector3) -> Vector2:
	return Vector2(d.x, d.y * SINP - d.z * COSP)


## The pitch at which an item pointing along the ground direction `aim` shows ON the aim line on the screen: a little down when she
## cuts toward the camera, raised when she cuts away from it, level to the sides. A blow then reads where it lands.
static func aim_pitch(aim: Vector2) -> float:
	return atan(-(1.0 - SINP) / COSP * aim.normalized().y)


## Her right shoulder in 3D from its screen position: it lies SHOULDER_OUT to her right of the body's axis.
static func shoulder_3d(at: Vector2, forward: Vector2) -> Vector3:
	return lift(at, right_of(forward).y * SHOULDER_OUT)


## The hand in 3D from its screen position. The screen hides one coordinate; the hand is assumed a little in front of her and a little
## out to the side (whichever of the two the screen does not show is fixed), then pulled in when that would stretch the arm.
static func hand_3d(at: Vector2, shoulder: Vector3, forward: Vector2) -> Vector3:
	var right: Vector2 = right_of(forward)
	var ox: float = at.x - shoulder.x
	var ahead: float = 2.0
	var out: float = 0.6
	if absf(forward.x) >= absf(right.x):
		ahead = clampf((ox - out * right.x) / forward.x, -7.0, 10.0)
	else:
		out = clampf((ox - ahead * forward.x) / right.x, -6.0, 9.0)
	var ground: Vector2 = Vector2(shoulder.x, shoulder.y) + forward * ahead + right * out
	var p: Vector3 = lift(at, ground.y)
	var reach: float = UPPER + FORE + PALM
	if p.distance_to(shoulder) > reach: ## too far for the arm: slide it along the line of sight (the screen stays) toward the point nearest the shoulder
		p = p.lerp(lift(at, shoulder.y + (at.y - screen(shoulder).y) * SINP), 0.8)
	return p


## Two-bone solve from the shoulder to the fist (art_hero3d ik2): the elbow bends toward `pole`. Returns [elbow, wrist, fist] (the fist is
## pulled in when it is out of reach).
static func arm(shoulder: Vector3, fist: Vector3, pole: Vector3) -> Array[Vector3]:
	var fore: float = FORE + PALM
	var to: Vector3 = fist - shoulder
	var dist: float = clampf(to.length(), 0.5, UPPER + fore - 0.02)
	var axis: Vector3 = to.normalized() if to.length() > 0.01 else Vector3.DOWN
	var reached: Vector3 = shoulder + axis * dist
	var along: float = (dist * dist + UPPER * UPPER - fore * fore) / (2.0 * dist)
	var bend: float = sqrt(maxf(UPPER * UPPER - along * along, 0.0))
	var side: Vector3 = pole - axis * pole.dot(axis)
	if side.length() < 0.01:
		side = Vector3(0.0, 0.0, -1.0) - axis * (-axis.z)
	side = side.normalized()
	var elbow: Vector3 = shoulder + axis * along + side * bend
	var down: Vector3 = (reached - elbow).normalized()
	return [elbow, reached - down * PALM, reached]


## Where the elbow wants to go for her right arm: down, out to her right and back, like the renderer's pole (-0.8, -0.6, -0.3).
static func pole(forward: Vector2) -> Vector3:
	return body_offset(forward, right_of(forward), Vector3(-0.3, 0.8, -0.6))


static func light() -> Vector3:
	return LIGHT.normalized()


## data/grips.json, read once.
static func data() -> Dictionary:
	if _data.is_empty():
		_data = DataRegistry.table("grips")
	return _data


## How an item is held (a style of data/grips.json `styles`): by its `grip` key, its tool, else a sword.
static func style_of(def: Dictionary) -> Dictionary:
	var styles: Dictionary = data().get("styles", {}) as Dictionary
	var name: String = String(def.get("grip", ""))
	if name.is_empty():
		var tool: String = String(def.get("tool", ""))
		name = tool if styles.has(tool) else "sword"
	return styles.get(name, styles.get("sword", {})) as Dictionary


## The swing shape of a weapon class (data/grips.json `swings`) with the block's own overrides; `like` copies another class.
static func swing_of(weapon_class: String, block: int) -> Dictionary:
	var swings: Dictionary = data().get("swings", {}) as Dictionary
	var entry: Dictionary = swings.get(weapon_class, {}) as Dictionary
	if entry.has("like"):
		entry = swings.get(String(entry["like"]), {}) as Dictionary
	var out: Dictionary = (swings.get("default", {}) as Dictionary).duplicate()
	out.merge(entry, true)
	var blocks: Dictionary = entry.get("blocks", {}) as Dictionary
	if blocks.has(str(block)):
		out.merge(blocks[str(block)] as Dictionary, true)
	return out


## The blade's direction `theta` radians along a swing: `contact` is where it points when it passes the aim, the swing's plane leans
## `tilt` radians up on her right side (0 = a flat sweep, PI/2 = a straight overhead chop). theta > 0 is the right / upper side.
static func swing_dir(contact: Vector3, aim: Vector2, tilt: float, theta: float) -> Vector3:
	var right: Vector2 = right_of(aim.normalized())
	var tangent: Vector3 = Vector3(right.x, right.y, 0.0) * cos(tilt) + Vector3(0.0, 0.0, 1.0) * sin(tilt)
	tangent = (tangent - contact * tangent.dot(contact)).normalized()
	return (contact * cos(theta) + tangent * sin(theta)).normalized()
