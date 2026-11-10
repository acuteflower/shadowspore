class_name DamageNumber
extends Node2D
## Floating hit number in the pixel font. Pops in big, arcs away from the hit and fades.
## Bigger hits are orange or red and drawn at double size. Spawn with DamageNumber.spawn().

const LIFETIME: float = 0.9
const GRAVITY: float = 150.0
const POP_TIME: float = 0.07 ## extra size right after spawning
const STRONG_HIT: float = 8.0
const HEAVY_HIT: float = 15.0
const NORMAL: Color = Color("fff1c9")
const STRONG: Color = Color("ffb347")
const HEAVY: Color = Color("ff6a5a")
const POOL_CAPACITY: int = 40

static var _pool: Array[DamageNumber] = []

var _text: String = ""
var _color: Color = NORMAL
var _size: int = 1
var _pop: bool = true ## brief size-up right after spawning (hits only; loot messages stay calm)
var _velocity: Vector2 = Vector2.ZERO
var _age: float = 0.0
var _active: bool = false


func _ready() -> void:
	material = Unlit.material() ## stays bright at night
	z_index = 20
	if not _active:
		visible = false
		set_process(false)


static func _obtain(world: Node) -> DamageNumber:
	var item: DamageNumber = null
	for i: int in range(_pool.size() - 1, -1, -1):
		var n: DamageNumber = _pool[i]
		if not is_instance_valid(n):
			_pool.remove_at(i)
		elif not n._active and item == null:
			item = n
	if item == null:
		if _pool.size() < POOL_CAPACITY:
			item = DamageNumber.new()
			_pool.append(item)
		else:
			var oldest: DamageNumber = _pool[0]
			var max_age: float = -1.0
			for n: DamageNumber in _pool:
				if n._age > max_age:
					max_age = n._age
					oldest = n
			item = oldest

	if not item.is_inside_tree():
		item.z_index = 20
		world.add_child(item)
	elif item.get_parent() != world:
		item.get_parent().remove_child(item)
		item.z_index = 20
		world.add_child(item)

	item._active = true
	item._age = 0.0
	item.visible = true
	item.set_process(true)
	return item


func _recycle() -> void:
	_active = false
	visible = false
	set_process(false)


## `away` is the direction from the attacker to the target; the number drifts that way.
static func spawn(world: Node, pos: Vector2, amount: float, away: Vector2 = Vector2.ZERO, tint: Color = Color(0, 0, 0, 0)) -> void:
	if not bool(GameSettings.get_value("numbers")) or world == null or not is_instance_valid(world):
		return
	var number: DamageNumber = _obtain(world)
	number._text = str(roundi(amount))
	number._color = HEAVY if amount >= HEAVY_HIT else (STRONG if amount >= STRONG_HIT else NORMAL)
	number._size = 2 if amount >= STRONG_HIT else 1
	if tint.a > 0.0: ## e.g. damage taken
		number._color = tint
		number._size = 1
	number._pop = true
	number._velocity = Vector2(away.x * randf_range(12.0, 38.0) + randf_range(-14.0, 14.0), randf_range(-120.0, -95.0))
	number.global_position = pos + Vector2(randf_range(-9.0, 9.0), randf_range(-5.0, 5.0))
	number.queue_redraw()


## A plain floating message, e.g. "+12 XP".
static func spawn_text(world: Node, pos: Vector2, text: String, color: Color) -> void:
	if world == null or not is_instance_valid(world):
		return
	var number: DamageNumber = _obtain(world)
	number._text = text
	number._color = color
	number._size = 1
	number._pop = false
	number._velocity = Vector2(randf_range(-10.0, 10.0), randf_range(-70.0, -55.0))
	number.global_position = pos + Vector2(randf_range(-5.0, 5.0), 0.0)
	number.queue_redraw()


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		_recycle()
		return
	_velocity.y += GRAVITY * delta
	position += _velocity * delta
	queue_redraw()


func _draw() -> void:
	var fade: float = 1.0 - maxf(0.0, (_age / LIFETIME - 0.55) / 0.45)
	var scale_now: int = _size + (1 if _pop and _age < POP_TIME else 0) ## whole-number scales keep the pixels crisp
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(scale_now, scale_now))
	var pos: Vector2i = Vector2i(-PixelText.width(_text) / 2, -PixelText.HEIGHT / 2)
	PixelText.draw(self, _text, pos + Vector2i(0, 1), Color(_color.darkened(0.55), fade)) ## drop shadow
	PixelText.draw(self, _text, pos, Color(_color, fade), Color(UiStyle.OUTLINE, fade))
