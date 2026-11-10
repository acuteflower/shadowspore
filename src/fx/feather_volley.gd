class_name FeatherVolley
extends Node2D
## The feathers a slash of the Himmelsriss shoots (docs/rissklinge.md), every peer, cosmetic: from the blade's tip a fan of pixel feathers flies out, each with a thin
## violet trail, slightly swaying; one that meets something stops there (the host says how far each one flew), sticks for a moment and goes out in a few sparks.
## Unlit, pixels only (a feather is `FeatherBurst.draw_feather` along the nearest of eight directions), on real time so it also shows in slow motion.
## `FeatherVolley.shoot(parent, tip, dir, count, spread, speed, stops)`; damage is the host's business (`AttackComponent._volley`).

const TRAIL: int = 9
const STICK: float = 0.35 ## seconds a feather that hit stays
const FADE: float = 0.18
const CRACK: Color = Color("c07bff")
const VIOLET: Color = Color("9a6bff")
const CORE: Color = Color("f4ecff")

var _age: float = 0.0
var _speed: float = 560.0
var _life: float = 0.5
var _feathers: Array[Dictionary] = []


static func shoot(parent: Node, tip: Vector2, dir: Vector2, count: int, spread: float, speed: float, stops: PackedFloat32Array) -> void:
	var node: FeatherVolley = FeatherVolley.new()
	node.position = tip
	node._speed = maxf(speed, 50.0)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(tip)) + count
	for i: int in count:
		var turn: float = 0.0 if count == 1 else lerpf(-spread / 2.0, spread / 2.0, float(i) / float(count - 1))
		var stop: float = stops[i] if i < stops.size() else 150.0
		node._feathers.append({
			"dir": dir.rotated(turn),
			"stop": stop,
			"late": rng.randf_range(0.0, 0.05), ## the fan does not leave in one line
			"sway": rng.randf_range(0.6, 1.6),
			"phase": rng.randf() * TAU,
			"cracked": i % 2 == 0,
		})
		node._life = maxf(node._life, stop / node._speed + 0.05 + STICK + FADE)
	parent.add_child(node)


func _ready() -> void:
	z_index = 6
	var mat: CanvasItemMaterial = CanvasItemMaterial.new() ## additive and unlit: the feathers shine
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	_age += delta / maxf(Engine.time_scale, 0.05) ## real time
	if _age >= _life:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	if _age < 0.12: ## the shot: a short flash of light at the tip
		var open: float = 1.0 - _age / 0.12
		for f: Dictionary in _feathers:
			var cell: Vector2 = ((f["dir"] as Vector2) * (2.0 + 5.0 * (1.0 - open))).round()
			draw_rect(Rect2(cell.x, cell.y, 1, 1), Color(CORE, open))
	for f: Dictionary in _feathers:
		var dir: Vector2 = f["dir"] as Vector2
		var stop: float = float(f["stop"])
		var flown: float = (_age - float(f["late"])) * _speed
		if flown <= 0.0:
			continue
		var reached: bool = flown >= stop
		var distance: float = minf(flown, stop)
		var landed: float = _age - float(f["late"]) - stop / _speed ## seconds since it stopped
		var alpha: float = 1.0
		if reached:
			alpha = clampf(1.0 - (landed - STICK) / FADE, 0.0, 1.0)
		else:
			alpha = clampf((stop - distance) / 24.0 + 0.5, 0.5, 1.0) if stop < 400.0 and distance > stop - 12.0 else 1.0
		var side: Vector2 = Vector2(-dir.y, dir.x)
		var sway: float = sin(_age * 22.0 * float(f["sway"]) + float(f["phase"])) * 1.2 * (0.0 if reached else 1.0)
		var at: Vector2 = dir * distance + side * sway
		for k: int in range(TRAIL, 0, -1): ## the thin violet trail behind it
			var back: float = distance - float(k) * 3.0
			if back < 0.0:
				continue
			var cell: Vector2 = (dir * back + side * sway * (1.0 - float(k) / float(TRAIL + 1))).round()
			draw_rect(Rect2(cell.x, cell.y, 1, 1), Color(CRACK if k % 2 == 0 else VIOLET, alpha * 0.8 * (1.0 - float(k) / float(TRAIL + 1))))
		_glow(at, dir, alpha, float(f["phase"]))
		FeatherBurst.draw_feather(self, Vector2i(roundi(at.x), roundi(at.y)), dir.angle() + PI * 0.0, alpha, bool(f["cracked"]))
		if reached and landed < 0.18: ## it bites in: a few sparks fly back
			var k: float = landed / 0.18
			for spark: int in 4:
				var angle: float = dir.angle() + PI + (float(spark) - 1.5) * 0.7
				var cell: Vector2 = (at + Vector2.from_angle(angle) * (2.0 + 6.0 * k)).round()
				draw_rect(Rect2(cell.x, cell.y, 1, 1), Color(CORE if spark % 2 == 0 else CRACK, 1.0 - k))


## The glow of a feather: a pulsing violet bloom (a diamond of soft pixels, two rings) round its body and a light-white heart; it stays while the feather sticks.
func _glow(at: Vector2, dir: Vector2, alpha: float, phase: float) -> void:
	var pulse: float = 0.8 + 0.2 * sin(_age * 30.0 + phase)
	var centre: Vector2 = at + dir * 2.0
	for r: int in range(1, 6):
		var ring: float = (1.0 - float(r) / 6.0) * 0.16 * alpha * pulse
		for step: int in r * 4:
			var angle: float = TAU * float(step) / float(r * 4)
			var cell: Vector2 = (centre + Vector2.from_angle(angle) * float(r)).round()
			draw_rect(Rect2(cell.x, cell.y, 1, 1), Color(VIOLET if r > 2 else CRACK, ring))
	draw_rect(Rect2(roundf(centre.x), roundf(centre.y), 1, 1), Color(CORE, 0.8 * alpha * pulse))
