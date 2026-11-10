class_name FisherDazzle
extends CanvasLayer
## What the Lichtfischer's flash does to the eyes of whoever stood in it (local, cosmetic): a white-out that burns away and leaves a handful of false teal lamps
## drifting in the picture, like afterimages. The lamps are the lie again: for a moment you cannot tell them from real lights. Drawn in the 640x360 picture.

const LAYER_INDEX: int = 54 ## under the death screen (60), over the HUD
static var _active: FisherDazzle = null

var _life: float = 1.2
var _strength: float = 1.0
var _age: float = 0.0
var _lamps: Array[Dictionary] = []
var _canvas: Node2D


## `seconds`: how long the picture takes to clear, `strength` 0..1 how white it gets.
static func spawn(tree: SceneTree, seconds: float, strength: float) -> void:
	if _active != null and is_instance_valid(_active):
		_active.queue_free()
	var layer: FisherDazzle = FisherDazzle.new()
	layer.layer = LAYER_INDEX
	layer._life = maxf(seconds, 0.2)
	layer._strength = clampf(strength, 0.0, 1.0)
	tree.root.add_child(layer)
	_active = layer


func _ready() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	for i: int in 5:
		_lamps.append({"p": Vector2(rng.randf_range(80.0, 560.0), rng.randf_range(60.0, 300.0)), "r": rng.randf_range(3.0, 6.0), "phase": rng.randf() * TAU, "drift": Vector2(rng.randf_range(-6.0, 6.0), rng.randf_range(-9.0, -2.0))})
	_canvas = Node2D.new()
	_canvas.draw.connect(_draw_canvas)
	add_child(_canvas)


func _process(delta: float) -> void:
	_age += delta
	if _age >= _life:
		if _active == self:
			_active = null
		queue_free()
		return
	_canvas.queue_redraw()


func _draw_canvas() -> void:
	var t: float = clampf(_age / _life, 0.0, 1.0)
	var size: Vector2 = get_viewport().get_visible_rect().size
	var white: float = _strength * (1.0 - smoothstep(0.0, 0.5, t))
	_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 1.0, 1.0, white * 0.96))
	var veil: float = _strength * 0.42 * pow(1.0 - t, 2.0)
	_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(0.78, 1.0, 0.95, veil))
	var lamp_alpha: float = smoothstep(0.1, 0.35, t) * (1.0 - smoothstep(0.55, 1.0, t)) * _strength
	for lamp: Dictionary in _lamps:
		var at: Vector2 = ((lamp["p"] as Vector2) + (lamp["drift"] as Vector2) * _age + Vector2(sin(_age * 2.0 + float(lamp["phase"])) * 3.0, 0.0)).round()
		var r: float = float(lamp["r"])
		_canvas.draw_rect(Rect2(at - Vector2.ONE * r * 2.6, Vector2.ONE * r * 5.2), Color(0.5, 0.94, 0.85, 0.07 * lamp_alpha))
		_canvas.draw_rect(Rect2(at - Vector2.ONE * r * 1.6, Vector2.ONE * r * 3.2), Color(0.5, 0.94, 0.85, 0.16 * lamp_alpha))
		_canvas.draw_rect(Rect2(at - Vector2.ONE * r, Vector2.ONE * r * 2.0), Color(0.82, 1.0, 0.96, 0.55 * lamp_alpha))
		_canvas.draw_rect(Rect2(at - Vector2.ONE, Vector2.ONE * 2.0), Color(1.0, 1.0, 1.0, lamp_alpha))
