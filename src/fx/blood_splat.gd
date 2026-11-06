class_name BloodSplat
extends Node2D
## A few drops of blood on the ground that she leaves while she is wounded: dark red pixels that dry and fade after a while. At most MAX_SPLATS
## exist (the oldest go first). Cosmetic, every peer makes its own.

const MAX_SPLATS: int = 60
const LIFE: float = 28.0
const COLORS: Array[Color] = [Color("5a0a14"), Color("7a1020"), Color("3e0710")]

static var all_splats: Array[BloodSplat] = []

var _age: float = 0.0
var _pixels: Array[Rect2] = []
var _tones: Array[int] = []


static func drop(parent: Node, at: Vector2, size: int = 1) -> void:
	if all_splats.size() >= MAX_SPLATS:
		var oldest: BloodSplat = all_splats.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	var splat: BloodSplat = BloodSplat.new()
	splat.position = at.round()
	splat.make(size)
	parent.add_child(splat)


func make(size: int) -> void:
	z_index = -4 if MineManager.in_mine(position) else -6 ## in the mine the ground is painted at z -6
	add_to_group("blood_splats")
	all_splats.append(self)
	var count: int = 2 + size * 2
	for i: int in count:
		var spot: Vector2 = Vector2(randi_range(-size - 1, size + 1), randi_range(-size, size) * 0.6).round()
		_pixels.append(Rect2(spot, Vector2(1 + int(randf() < 0.3), 1)))
		_tones.append(randi() % COLORS.size())


func _exit_tree() -> void:
	all_splats.erase(self)


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFE:
		queue_free()
		return
	modulate.a = 1.0 - smoothstep(LIFE * 0.6, LIFE, _age)
	if _age <= 4.0:
		queue_redraw()


func _draw() -> void:
	var wet: float = 1.0 - clampf(_age / 4.0, 0.0, 1.0) ## wet blood is brighter, then it dries darker
	for i: int in _pixels.size():
		draw_rect(_pixels[i], COLORS[_tones[i]].lerp(Color("a01a2c"), wet * 0.5))
