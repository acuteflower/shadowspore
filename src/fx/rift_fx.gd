class_name RiftFx
extends Node2D
## The rifts of the Himmelsriss (docs/rissklinge.md), every peer, cosmetic. Pixels only, nothing rotated or scaled, unlit and on real time (also in slow motion):
## `RiftFx.lane(parent, origin, dir, length, life)` throws a jagged lane of violet light out of the blade (the Spitzenriss of the thrust: it shoots out, holds, then
## closes from the hilt outwards, black feathers shed from it). Damage is the host's business (`AttackComponent._rift`); the feathers of the right-click slashes are `FeatherVolley`.

const DARK: Color = Color("14102a")
const VIOLET: Color = Color("9a6bff")
const CRACK: Color = Color("c07bff")
const CORE: Color = Color("f4ecff")

var _age: float = 0.0
var _life: float = 0.5
var _dir: Vector2 = Vector2.RIGHT
var _length: float = 100.0
var _seed: int = 0
var _feathers: Array[Dictionary] = []


static func lane(parent: Node, origin: Vector2, dir: Vector2, length: float, life: float) -> void:
	var node: RiftFx = RiftFx.new()
	node.position = origin
	node._dir = dir.normalized()
	node._length = length
	node._life = life
	node._seed = hash(Vector2i(origin))
	node._shed(6)
	parent.add_child(node)


func _ready() -> void:
	z_index = 6
	material = Unlit.material()
	process_mode = Node.PROCESS_MODE_ALWAYS


func _shed(count: int) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _seed
	for i: int in count:
		_feathers.append({"u": rng.randf_range(0.15, 0.95), "side": 1.0 if rng.randf() < 0.5 else -1.0, "drift": rng.randf_range(5.0, 15.0), "phase": rng.randf() * TAU, "turn": rng.randf_range(2.0, 4.0)})


func _process(delta: float) -> void:
	_age += delta / maxf(Engine.time_scale, 0.05)
	if _age >= _life + 0.5:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	_draw_lane()


func _draw_lane() -> void:
	var t: float = _age / _life
	var reach: float = clampf(_age / 0.07, 0.0, 1.0) ## shoots out of the blade
	var closed: float = clampf((t - 0.3) / 0.7, 0.0, 1.0) ## and closes again from the hilt outwards
	var perp: Vector2 = Vector2(-_dir.y, _dir.x)
	var steps: int = maxi(int(_length / 2.0), 2)
	for i: int in steps:
		var u: float = float(i) / steps
		if u > reach or u < closed:
			continue
		var wobble: float = sin(float(i) * 1.9 + float(_seed % 13)) * (1.3 + 1.5 * u) * (1.0 - closed)
		var base: Vector2 = _dir * u * _length + perp * wobble
		var open: float = (1.0 - closed) * (1.0 - 0.45 * u)
		var arms: int = 1 + int(2.2 * open)
		for w: int in range(-arms - 1, arms + 2):
			var cell: Vector2 = (base + perp * float(w)).round()
			var edge: int = absi(w)
			var color: Color
			if edge > arms:
				color = Color(DARK, 0.9 * open) if (i + w) % 2 == 0 else Color(VIOLET, 0.35 * open)
			elif edge == arms and arms > 1:
				color = Color(CRACK, 0.85 * open)
			elif edge == 0:
				color = Color(CORE, open)
			else:
				color = Color(CRACK, 0.9 * open)
			draw_rect(Rect2(cell.x, cell.y, 1, 1), color)
	for f: Dictionary in _feathers:
		var u: float = float(f["u"])
		if u > reach or u < closed:
			continue
		var at: Vector2 = _dir * u * _length + perp * float(f["side"]) * (2.0 + float(f["drift"]) * t)
		at.y += 10.0 * t * t
		FeatherBurst.draw_feather(self, Vector2i(roundi(at.x), roundi(at.y)), float(f["phase"]) + _age * float(f["turn"]), clampf((1.0 - t) * 1.8, 0.0, 1.0), true)
