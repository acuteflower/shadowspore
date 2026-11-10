class_name FeatherBurst
extends Node2D
## The Rissfeder's last wing beat (docs/rissfeder.md) and the Himmelsbruch of the Himmelsriss (docs/rissklinge.md): a tear of violet light opens in the air, black feathers
## burst outwards, turn in the air and drift down while they fade. Pixel feathers only (five pixels along one of eight directions, a vane pair beside them), nothing
## rotated or scaled. Unlit, like the other flashes, and on real time so it also shows in slow motion: `FeatherBurst.burst(parent, ground_point, radius, count)`
## (the ring on the ground is a `ShockRing`). `draw_feather` is shared with `RiftFx`.

const LIFE: float = 1.2
const COUNT: int = 14
const DARK: Color = Color("14102a")
const MID: Color = Color("3b2d6b")
const LIGHT: Color = Color("7d6ad0")
const CRACK: Color = Color("c07bff")
const CORE: Color = Color("f4ecff")
const OCTANTS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]

var _age: float = 0.0
var _feathers: Array[Dictionary] = []


static func burst(parent: Node, ground_point: Vector2, radius: float, count: int = COUNT) -> void:
	var node: FeatherBurst = FeatherBurst.new()
	node.position = ground_point + Vector2(0.0, -14.0)
	node._scatter(radius, count)
	parent.add_child(node)
	ShockRing.burst(parent, ground_point, radius, 0.8)


## One pixel feather on `canvas` at `cell`: a quill of five pixels along the octant `spin` points to and a vane pair beside it.
static func draw_feather(canvas: CanvasItem, cell: Vector2i, spin: float, alpha: float, cracked: bool) -> void:
	var step: Vector2i = OCTANTS[posmod(roundi(spin / (PI / 4.0)), 8)]
	var side: Vector2i = Vector2i(-step.y, step.x)
	for i: int in range(-2, 3): ## the quill
		var spot: Vector2i = cell + step * i
		var tone: Color = DARK if i < 0 else (LIGHT if i == 1 else MID)
		canvas.draw_rect(Rect2(spot.x, spot.y, 1, 1), Color(tone, alpha))
	for i: int in range(-1, 1): ## the vane, a pair beside the quill
		for flank: int in [-1, 1]:
			var spot: Vector2i = cell + step * i + side * flank
			canvas.draw_rect(Rect2(spot.x, spot.y, 1, 1), Color(MID if flank < 0 else DARK, alpha))
	if cracked: ## a few carry the violet crack along their spine
		canvas.draw_rect(Rect2(cell.x, cell.y, 1, 1), Color(CRACK, alpha))


func _scatter(radius: float, count: int) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(position))
	for i: int in count:
		_feathers.append({
			"dir": Vector2.from_angle(TAU * float(i) / count + rng.randf_range(-0.22, 0.22)),
			"reach": rng.randf_range(0.5, 1.0) * radius,
			"rise": rng.randf_range(6.0, 22.0),
			"turn": rng.randf_range(2.0, 5.0) * (1.0 if rng.randf() < 0.5 else -1.0),
			"phase": rng.randf() * TAU,
		})


func _ready() -> void:
	z_index = 6
	material = Unlit.material()
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	_age += delta / maxf(Engine.time_scale, 0.05) ## real time
	if _age >= LIFE:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t: float = _age / LIFE
	var out: float = 1.0 - pow(1.0 - clampf(t * 1.7, 0.0, 1.0), 3.0) ## flung out fast, then they hang
	var alpha: float = clampf((1.0 - t) / 0.4, 0.0, 1.0)
	if _age < 0.32: ## the tear in the sky: a jagged line of light that closes again
		var open: float = 1.0 - _age / 0.32
		for k: int in range(-22, 8):
			var x: int = roundi(sin(float(k) * 0.85 + 1.3) * 1.6 * open)
			draw_rect(Rect2(x, k, 1, 1), Color(CORE if absi(k + 8) < 3 else CRACK, open))
			if k % 3 == 0:
				draw_rect(Rect2(x + 1, k, 1, 1), Color(CRACK, open * 0.6))
	for f: Dictionary in _feathers:
		var at: Vector2 = (f["dir"] as Vector2) * float(f["reach"]) * out
		at.y = at.y * 0.6 - float(f["rise"]) * out * (1.0 - t) + 26.0 * t * t ## a flattened circle, a lift, then the fall
		at.x += sin(_age * 3.0 + float(f["phase"])) * 2.0 * t
		var spin: float = float(f["phase"]) + _age * float(f["turn"])
		draw_feather(self, Vector2i(roundi(at.x), roundi(at.y)), spin, alpha, posmod(int(float(f["phase"]) * 4.0), 3) == 0)
