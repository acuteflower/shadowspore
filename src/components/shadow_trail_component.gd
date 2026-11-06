class_name ShadowTrailComponent
extends Node
## Lets a shadow creature leave creeping shadow on the ground (ShadowPatch). Meant for every
## shadow creature: call `leave()` wherever it touches the ground and `infest()` when it dies.
## Purely cosmetic, so each peer runs it on its own.

const MIN_GAP: float = 8.0 ## patches closer than this to a recent one are skipped
const REMEMBER: int = 6
const FOOT_SIZES: Array[Vector2i] = [Vector2i(12, 10), Vector2i(14, 10), Vector2i(16, 12)]
const INFEST_SIZE: Vector2i = Vector2i(64, 46)
const SATELLITE_SIZE: Vector2i = Vector2i(24, 18)
const SATELLITES: int = 3

@export var life: float = 3.0 ## seconds a footprint lasts before it starts to dissolve
@export var fade: float = 2.5 ## seconds a footprint takes to dissolve
@export var infest_life: float = 10.0 ## same for the infestation a death leaves behind
@export var infest_fade: float = 6.0
@export var infest_size: Vector2i = INFEST_SIZE ## a big creature leaves a bigger stain
@export var infest_tendrils: int = 8
@export var foot_scale: float = 1.0 ## big creatures eat bigger holes into the ground: scales every footprint (and the gap between them)
@export var heavy_scale: float = 1.0 ## the same for the heavy marks (claws, club, cracks)
@export var foot_arms: int = 4 ## tendrils in a footprint
@export var heavy_arms: int = 4

var _recent: Array[Vector2] = []


## A small patch under a foot; `heavy` makes a big one (claws digging in).
func leave(world_pos: Vector2, heavy: bool = false) -> void:
	if not heavy:
		for point: Vector2 in _recent:
			if point.distance_to(world_pos) < MIN_GAP * foot_scale:
				return
	_recent.append(world_pos)
	if _recent.size() > REMEMBER:
		_recent.pop_front()
	var size: Vector2i = Vector2i(28, 20) if heavy else FOOT_SIZES[randi() % FOOT_SIZES.size()]
	var scale_by: float = heavy_scale if heavy else foot_scale
	size = Vector2i(roundi(size.x * scale_by / 2.0) * 2, roundi(size.y * scale_by / 2.0) * 2) ## the shader wants even sizes
	ShadowPatch.spawn(get_tree().current_scene, world_pos, size, life * randf_range(0.85, 1.2) * (1.0 + (scale_by - 1.0) * 0.5), fade * (1.0 + (scale_by - 1.0) * 0.4), heavy_arms if heavy else foot_arms)


## A death: a big writhing infestation with a few smaller ones spreading around it. Lasts much
## longer than a footprint.
func infest(world_pos: Vector2) -> void:
	var world: Node = get_tree().current_scene
	ShadowPatch.spawn(world, world_pos, infest_size, infest_life, infest_fade, infest_tendrils)
	for i: int in SATELLITES:
		var offset: Vector2 = Vector2.from_angle(randf() * TAU) * randf_range(20.0, 30.0)
		offset.y *= 0.7
		ShadowPatch.spawn(world, world_pos + offset, SATELLITE_SIZE, infest_life * randf_range(0.6, 0.9), infest_fade, 3)
