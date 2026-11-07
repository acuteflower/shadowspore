class_name LeafCritter
extends Node2D
## Undergrowth animals (docs/plant_life.md): a shimmer beetle, a leaf caterpillar or a leaf snail sits on a bush that has a `critters`
## block in data/plants.json. Which one, and whether there is one at all today, is a pure function of the bush's cell and the day
## (`today`), so every peer sees the same animal and nothing is sent; wet days bring out more of them, and nothing sits on a bush at
## night (snails stay a little longer). The sickle (or E, "ABLESEN") takes it: the host rolls a catch (an item, bait for the river) or the
## animal simply escapes, either way it is gone until tomorrow (state "c" = day + 1 on the bush). Walking through a bush startles a
## beetle for a while. The drawing is a few pixels in code (no sheet) and sits on a painted top edge of the bush's current picture.
const ITEMS: Dictionary = {"beetle": "shimmer_beetle", "caterpillar": "leaf_caterpillar", "snail": "leaf_snail"}
const OUTLINE: Color = Color("1b1a2e")
const FRAME: Vector2i = Vector2i(40, 34)
const FEET: Vector2 = Vector2(20, 31)

static var _images: Dictionary = {} ## texture path -> Image (decoded once)

var kind: String = ""
var _bush: WorldProp
var _anchor: Vector2 = Vector2.ZERO
var _walk: float = 0.0 ## position along the little path it paces (px)
var _dir: float = 1.0
var _wait: float = 0.0
var _phase: float = 0.0
var _flee: float = -1.0 ## 0..1 while it escapes (or is taken), -1 not
var _flee_dir: float = 1.0
var _startled_until: float = 0.0
var _redraw: float = 0.0


## What sits on this bush today ("" = nothing). Pure: the cell, the day and the state of the bush decide.
static func today(thing: WorldProp) -> String:
	var spec: Dictionary = thing.spec().get("critters", {}) as Dictionary
	if spec.is_empty() or thing.is_depleted():
		return ""
	var day: int = TimeManager.day
	if int(thing.state.get("c", 0)) == day + 1:
		return ""
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([thing.cell.x, thing.cell.y, day, 3917])
	var wet: bool = Moisture.is_wet_day(day)
	if rng.randf() >= minf(float(spec.get("chance", 0.2)) * (2.0 if wet else 1.0), 0.7):
		return ""
	var roll: float = rng.randf()
	var snail_share: float = 0.42 if wet else 0.22
	if roll < snail_share:
		return "snail"
	return "beetle" if roll < snail_share + (1.0 - snail_share) * 0.5 else "caterpillar"


func setup(bush: WorldProp) -> void:
	_bush = bush
	name = "Critter"
	z_index = 1
	y_sort_enabled = false
	_phase = fposmod(float(bush.cell.x) * 0.73 + float(bush.cell.y) * 0.41, TAU)
	TimeManager.day_started.connect(func(_day: int) -> void: refresh(""))


## The bush's state or picture changed: show what is there now. `fx` "catch" / "scare" plays the escape.
func refresh(fx: String) -> void:
	var was: String = kind
	var now: String = LeafCritter.today(_bush)
	if fx == "catch" or fx == "scare":
		if was != "":
			_flee = 0.0
			_flee_dir = 1.0 if randf() < 0.5 else -1.0
			set_process(true)
		return
	if now == kind and _flee < 0.0:
		_place()
		return
	kind = now
	_flee = -1.0
	_walk = 0.0
	_place()
	set_process(kind != "")
	queue_redraw()


## A walker brushed the bush: a beetle takes off for a while.
func startle() -> void:
	if kind == "beetle" and _flee < 0.0 and Time.get_ticks_msec() / 1000.0 > _startled_until:
		_startled_until = Time.get_ticks_msec() / 1000.0 + 6.0


func _place() -> void:
	if kind == "":
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([_bush.cell.x, _bush.cell.y, TimeManager.day, 71])
	_anchor = _find_spot(rng)
	position = _anchor


## A painted pixel on the upper edge of the bush's current frame (something sits ON a leaf).
func _find_spot(rng: RandomNumberGenerator) -> Vector2:
	var sprite: Sprite2D = _bush.get_node_or_null("Sprite") as Sprite2D
	var fallback: Vector2 = Vector2(float(rng.randi_range(-5, 5)), -float((_bush.spec().height as Array)[_bush.variant]) * 0.7)
	if sprite == null or sprite.texture == null:
		return fallback
	var path: String = sprite.texture.resource_path
	if not _images.has(path):
		_images[path] = sprite.texture.get_image()
	var image: Image = _images[path] as Image
	if image == null or image.is_empty():
		return fallback
	var cell_w: int = image.get_width() / maxi(sprite.hframes, 1)
	var cell_h: int = image.get_height() / maxi(sprite.vframes, 1)
	var origin: Vector2i = Vector2i((sprite.frame % maxi(sprite.hframes, 1)) * cell_w, (sprite.frame / maxi(sprite.hframes, 1)) * cell_h)
	var best: Vector2 = fallback
	var best_top: float = INF
	for _try: int in 30:
		var x: int = rng.randi_range(6, cell_w - 7)
		var y: int = rng.randi_range(3, int(float(cell_h) * 0.62))
		if image.get_pixel(origin.x + x, origin.y + y).a < 0.9:
			continue
		var open_above: bool = image.get_pixel(origin.x + x, origin.y + maxi(y - 2, 0)).a < 0.1
		var score: float = float(y) + (0.0 if open_above else 6.0)
		if score < best_top:
			best_top = score
			best = Vector2(float(x), float(y + 2)) + sprite.offset ## a little into the leaves, not on the rim
	return best.round()


func _process(delta: float) -> void:
	if kind == "" and _flee < 0.0:
		set_process(false)
		return
	_redraw -= delta
	var now: float = Time.get_ticks_msec() / 1000.0
	if _flee >= 0.0:
		_flee += delta / 0.8
		if _flee >= 1.0:
			_flee = -1.0
			kind = ""
			set_process(false)
			queue_redraw()
			return
	else:
		_wait -= delta
		if _wait <= 0.0:
			var step: float = 1.0 if kind != "snail" else 0.5
			_walk += _dir * step
			if absf(_walk) > (6.0 if kind == "caterpillar" else 4.0):
				_dir = -_dir
			_wait = {"beetle": randf_range(0.8, 2.5), "caterpillar": 0.22, "snail": randf_range(1.2, 3.0)}.get(kind, 1.0)
	if _redraw <= 0.0:
		_redraw = 0.08
		visible = _active() and now >= _startled_until
		if visible:
			queue_redraw()


## Beetles and caterpillars sleep at night; snails stay out into the first dark.
func _active() -> bool:
	var night: float = TimeManager.night_amount()
	return night < (0.75 if kind == "snail" else 0.35) or _flee >= 0.0


func _draw() -> void:
	if kind == "":
		return
	var t: float = Time.get_ticks_msec() / 1000.0
	var fade: float = 1.0
	var shift: Vector2 = Vector2.ZERO
	if _flee >= 0.0:
		var f: float = _flee
		fade = 1.0 - f
		match kind:
			"beetle":
				shift = Vector2(_flee_dir * 26.0 * f, -18.0 * sin(f * PI) - 12.0 * f)
			_:
				shift = Vector2(_flee_dir * 3.0 * f, 24.0 * f * f)
	var at: Vector2 = Vector2(_walk, 0.0) + shift
	match kind:
		"beetle":
			_draw_beetle(at, t, fade, _flee >= 0.0)
		"caterpillar":
			_draw_caterpillar(at, t, fade)
		"snail":
			_draw_snail(at, t, fade, _flee < 0.0 and Player.all.any(func(p: Player) -> bool: return is_instance_valid(p) and p.global_position.distance_to(global_position) < 36.0))


func _px(at: Vector2, size: Vector2, color: Color, fade: float) -> void:
	color.a = fade
	draw_rect(Rect2(at.round(), size), color)


func _draw_beetle(at: Vector2, t: float, fade: float, flying: bool) -> void:
	_px(at + Vector2(-3, -3), Vector2(6, 4), OUTLINE, fade)
	_px(at + Vector2(-2, -2), Vector2(4, 3), Color("3aa8b0"), fade)
	_px(at + Vector2(-2, -2), Vector2(2, 1), Color("b0f4e8"), fade)
	_px(at + Vector2(0, -2), Vector2(1, 3), Color("14506a"), fade) ## the seam of the wing cases
	_px(at + Vector2(2, -2), Vector2(1, 2), Color("0e3a4a"), fade) ## head
	if flying:
		var flap: float = 1.0 if int(t * 40.0) % 2 == 0 else 0.0
		_px(at + Vector2(-3, -5 - flap), Vector2(3, 1), Color(0.86, 0.95, 1.0, 0.85), fade)
		_px(at + Vector2(0, -5 - flap), Vector2(3, 1), Color(0.86, 0.95, 1.0, 0.85), fade)
	elif int(t * 0.9 + _phase) % 4 == 0 and int(t * 12.0) % 2 == 0: ## a feeler twitch
		_px(at + Vector2(3, -3), Vector2(1, 1), OUTLINE, fade)


func _draw_caterpillar(at: Vector2, t: float, fade: float) -> void:
	for i: int in 5:
		var arch: float = maxf(0.0, sin(t * 4.0 - float(i) * 0.9 + _phase)) * 1.6
		var seg: Vector2 = at + Vector2(float(i) * 2.0 * _dir * -1.0, -arch)
		_px(seg + Vector2(-1, -3), Vector2(4, 4), OUTLINE, fade)
	for i: int in 5:
		var arch: float = maxf(0.0, sin(t * 4.0 - float(i) * 0.9 + _phase)) * 1.6
		var seg: Vector2 = at + Vector2(float(i) * 2.0 * _dir * -1.0, -arch)
		_px(seg + Vector2(0, -2), Vector2(2, 2), Color("e8f8a8") if i % 2 == 0 else Color("9ad060"), fade)
	var head: Vector2 = at + Vector2(2.0 * _dir, 0.0)
	_px(head + Vector2(-1, -3), Vector2(3, 3), Color("2c6e54"), fade)
	_px(head + Vector2(1.0 if _dir > 0.0 else -1.0, -2), Vector2(1, 1), Color("f4ecd8"), fade)


func _draw_snail(at: Vector2, t: float, fade: float, hiding: bool) -> void:
	var out: float = 0.0 if hiding else 1.0
	_px(at + Vector2(-3, 0), Vector2(5.0 + 2.0 * out, 2), OUTLINE, fade)
	_px(at + Vector2(-2, 0), Vector2(3.0 + 2.0 * out, 1), Color("a0a0c0"), fade)
	_px(at + Vector2(-2, -3), Vector2(4, 4), OUTLINE, fade)
	_px(at + Vector2(-1, -3), Vector2(3, 3), Color("9a5a6a"), fade)
	_px(at + Vector2(-1, -3), Vector2(1, 1), Color("f4c8a8"), fade)
	_px(at + Vector2(0, -2), Vector2(1, 1), Color("5a3248"), fade)
	if out > 0.5:
		var sway: float = sin(t * 1.6 + _phase)
		_px(at + Vector2(3.0 + sway * 0.6, -2), Vector2(1, 2), Color("6a6a8a"), fade)
		_px(at + Vector2(4.0 + sway, -3), Vector2(1, 1), Color("f4ecd8"), fade)
