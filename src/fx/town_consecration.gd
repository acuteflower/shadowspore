class_name TownConsecration
extends Node2D
## The moment a town piece is finished (docs/stadtbau_konzept.md section 4), on every peer, cosmetic: a deep impact and a bell, a pressure wave of light and dust
## that runs out over the ground (the props it tears out are removed by `WorldLevel.town_uproot` in step with it), the trees round it sway, the light of the piece
## floods out to its reach, the gains fly to the stockpile, and the piece's name rises over it with what it adds to the town. Frees itself.

const WAVE_SPEED: float = 260.0
const WAVE_START: float = 0.2
const FLOOD_START: float = 0.9
const FLOOD_TIME: float = 1.3
const TEXT_START: float = 1.1
const LIFE: float = 4.2
const EDGE: Color = Color("eafff9")
const TEAL: Color = Color("78f4e6")
const GOLD: Color = Color("ffd27a")
const DUST: Color = Color("b8a68e")
const INK: Color = Color("0a0612")

var radius: float = 0.0 ## the pressure wave's reach (px); 0 = no wave
var reach: float = 0.0 ## the light the piece carries (px); 0 = no flood
var title: String = ""
var worth: float = 0.0
var light_color: Color = GOLD
var gains: Array = [] ## [Vector2 from, String item]: what the wave brought into the stock
var gain_target: Vector2 = Vector2.INF ## where the gains fly (the stockpile's door), INF = up into the light
var height: float = 40.0 ## how tall the piece is (the name rises above it)

var _t: float = 0.0
var _ground: Node2D
var _shade: Node2D
var _top: Node2D
var _shook: bool = false
var _flooded: bool = false
var _trees: Array[Node2D] = []


static func play(parent: Node, at: Vector2, settings: Dictionary) -> TownConsecration:
	var fx: TownConsecration = TownConsecration.new()
	fx.position = at
	for key: String in settings:
		fx.set(key, settings[key])
	parent.add_child(fx)
	return fx


func _ready() -> void:
	var glow: CanvasItemMaterial = CanvasItemMaterial.new()
	glow.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	glow.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_shade = Node2D.new() ## the ground pressed down under the wave: world-lit, so it reads on bright grass
	_shade.z_index = -4
	_shade.draw.connect(_draw_shade)
	add_child(_shade)
	_ground = Node2D.new()
	_ground.z_index = -3
	_ground.material = glow
	_ground.draw.connect(_draw_ground)
	add_child(_ground)
	_top = Node2D.new()
	_top.z_index = 40
	_top.material = Unlit.material()
	_top.draw.connect(_draw_top)
	add_child(_top)
	_sound("consecrate_hit", 0.0, 0.0)
	_sound("consecrate_bell", 0.15, -4.0)
	if radius > 0.0:
		_sound("wave", WAVE_START, -4.0)
		_dust()
		for node: Node in get_tree().get_nodes_in_group("bird_perches"):
			var tree: Node2D = node as Node2D
			if tree != null and tree.has_method("_shake") and tree.global_position.distance_to(global_position) < radius * 1.7 + 30.0:
				_trees.append(tree)
	if reach > 0.0:
		_sound("light_flood", FLOOD_START, -6.0)


func _process(delta: float) -> void:
	_t += delta
	if not _shook and _t >= WAVE_START:
		_shook = true
		for player: Player in Player.all:
			if player.is_multiplayer_authority():
				var d: float = player.global_position.distance_to(global_position)
				if d < 360.0:
					player.add_shake(lerpf(1.1, 0.15, d / 360.0) * (1.0 if radius > 0.0 else 0.5))
	var front: float = (_t - WAVE_START) * WAVE_SPEED
	for i: int in range(_trees.size() - 1, -1, -1):
		var tree: Node2D = _trees[i]
		if not is_instance_valid(tree):
			_trees.remove_at(i)
		elif front >= tree.global_position.distance_to(global_position):
			tree.call("_shake", 0.9)
			if tree.has_method("_needle_rain"):
				tree.call("_needle_rain", 10)
			_trees.remove_at(i)
	_ground.queue_redraw()
	_shade.queue_redraw()
	_top.queue_redraw()
	if _t >= LIFE:
		queue_free()


func _sound(file: String, delay: float, db: float) -> void:
	var path: String = "res://assets/audio/town/%s.wav" % file
	if not ResourceLoader.exists(path):
		return
	var player: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	player.stream = load(path) as AudioStream
	player.volume_db = db
	player.max_distance = 520.0
	add_child(player)
	player.finished.connect(player.queue_free)
	if delay <= 0.0:
		player.play()
	else:
		get_tree().create_timer(delay, false).timeout.connect(func() -> void:
			if is_instance_valid(player):
				player.play())


## The dust thrown up by the wave: a ring of grains flying out with it, falling and fading (world-lit, it is earth).
func _dust() -> void:
	var puff: CPUParticles2D = CPUParticles2D.new()
	puff.one_shot = true
	puff.explosiveness = 0.9
	puff.amount = clampi(int(radius * 0.9), 24, 110)
	puff.lifetime = 0.9
	puff.direction = Vector2.RIGHT
	puff.spread = 180.0
	puff.initial_velocity_min = WAVE_SPEED * 0.55
	puff.initial_velocity_max = WAVE_SPEED * 0.95
	puff.damping_min = WAVE_SPEED * 0.6
	puff.damping_max = WAVE_SPEED * 0.9
	puff.gravity = Vector2(0, -14)
	puff.scale_amount_min = 1.0
	puff.scale_amount_max = 2.0
	var ramp: Gradient = Gradient.new()
	ramp.colors = PackedColorArray([Color(DUST, 0.0), Color(DUST, 0.8), Color(DUST, 0.0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	puff.color_ramp = ramp
	puff.position = Vector2(0, -6)
	puff.z_index = 2
	add_child(puff)
	get_tree().create_timer(WAVE_START, false).timeout.connect(func() -> void:
		if is_instance_valid(puff):
			puff.emitting = true)


## A ring of pixels on `canvas`: `alpha` per pixel is broken by a hash so the edge reads ragged; `gap` = share of pixels left out.
func _ring(canvas: Node2D, r: float, color: Color, alpha: float, gap: float, seed: int) -> void:
	if r < 1.0 or alpha <= 0.01:
		return
	var count: int = maxi(int(TAU * r), 12)
	for k: int in count:
		var h: float = fposmod(sin(float(k * 12.9898 + seed * 78.233)) * 43758.5453, 1.0)
		if h < gap:
			continue
		var p: Vector2 = (Vector2.from_angle(TAU * float(k) / float(count)) * r).round()
		canvas.draw_rect(Rect2(p, Vector2.ONE), Color(color, alpha * (0.6 + 0.4 * h)))


func _front() -> float:
	return (_t - WAVE_START) * WAVE_SPEED


func _wave_fade(front: float) -> float:
	return clampf((radius + 10.0 - front) / 30.0, 0.0, 1.0) * clampf(front / 8.0, 0.0, 1.0)


## Under the light: the band of ground the wave presses down and a ridge of earth it pushes ahead (darker pixels, world-lit).
func _draw_shade() -> void:
	var front: float = _front()
	if radius <= 0.0 or front <= 0.0 or front > radius + 10.0:
		return
	var fade: float = _wave_fade(front)
	var ink: Color = Color(0.06, 0.04, 0.1)
	for i: int in 9:
		_ring(_shade, front - 1.0 - float(i), ink, fade * (0.55 - 0.055 * float(i)), 0.05 + 0.07 * float(i), 20 + i)
	_ring(_shade, front + 1.0, Color(0.42, 0.33, 0.24), fade * 0.85, 0.2, 30)
	_ring(_shade, front + 2.0, Color(0.55, 0.46, 0.33), fade * 0.7, 0.45, 31)
	_ring(_shade, front + 3.0, Color(0.55, 0.46, 0.33), fade * 0.4, 0.75, 32)


func _draw_ground() -> void:
	if radius > 0.0:
		var front: float = _front()
		if front > 0.0 and front < radius + 10.0:
			var fade: float = _wave_fade(front)
			_ring(_ground, front, EDGE, fade, 0.0, 1)
			_ring(_ground, front - 1.0, EDGE, fade, 0.0, 2)
			_ring(_ground, front - 2.0, TEAL, fade, 0.05, 3)
			_ring(_ground, front - 3.0, TEAL, fade * 0.8, 0.2, 4)
			_ring(_ground, front - 4.0, GOLD, fade * 0.6, 0.35, 5)
			_ring(_ground, front - 6.0, GOLD, fade * 0.4, 0.55, 6)
			_ring(_ground, front - 10.0, TEAL, fade * 0.3, 0.7, 7)
			_ring(_ground, front - 16.0, TEAL, fade * 0.15, 0.85, 11)
	if reach > 0.0 and _t >= FLOOD_START:
		var k: float = clampf((_t - FLOOD_START) / FLOOD_TIME, 0.0, 1.0)
		var r: float = reach * (1.0 - pow(1.0 - k, 3.0))
		var fade: float = clampf((LIFE - _t) / 1.6, 0.0, 1.0)
		var tone: Color = light_color.lerp(GOLD, 0.4)
		_ring(_ground, r, tone, 0.9 * fade, 0.3, 8)
		_ring(_ground, r - 1.0, tone, 0.6 * fade, 0.5, 9)
		_ring(_ground, r - 3.0, light_color, 0.3 * fade, 0.75, 10)
		_ground.draw_circle(Vector2.ZERO, r, Color(light_color, 0.07 * (1.0 - k * 0.6) * fade))
	var flash: float = clampf(1.0 - _t / 0.5, 0.0, 1.0)
	if flash > 0.0:
		_ground.draw_circle(Vector2(0, -4), 18.0 + 30.0 * (1.0 - flash), Color(EDGE, 0.25 * flash))


func _draw_top() -> void:
	for gain: Variant in gains:
		_draw_gain(gain as Array)
	if title == "" or _t < TEXT_START:
		return
	var age: float = _t - TEXT_START
	var appear: float = clampf(age / 0.35, 0.0, 1.0)
	var fade: float = clampf((LIFE - 0.3 - _t) / 0.9, 0.0, 1.0)
	var y: float = -height - 10.0 - age * 6.0
	var name_w: float = float(PixelText.width(title)) * 2.0
	_top.draw_set_transform(Vector2(roundf(-name_w / 2.0), roundf(y)), 0.0, Vector2(2, 2))
	PixelText.draw(_top, title, Vector2i.ZERO, Color(GOLD, appear * fade), Color(INK, appear * fade))
	_top.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if worth > 0.0:
		var line: String = "+%s WERT" % (str(int(worth)) if is_equal_approx(worth, roundf(worth)) else "%.1f" % worth)
		PixelText.draw(_top, line, Vector2i(-PixelText.width(line) / 2, int(roundf(y)) + 13), Color(TEAL, appear * fade), Color(INK, appear * fade))
	var spread: float = 60.0 * (1.0 - fade)
	if fade < 1.0:
		for i: int in 14:
			var a: float = float(i) * 2.399
			var p: Vector2 = Vector2(cos(a) * name_w * 0.5 * fposmod(float(i) * 0.37, 1.0), y + 4.0) + Vector2(cos(a), sin(a) - 0.8) * spread
			_top.draw_rect(Rect2(p.round(), Vector2.ONE), Color(GOLD, fade))


## One gain flies from where its plant stood (once the wave has passed there) in an arc to the stockpile and shrinks into it.
func _draw_gain(gain: Array) -> void:
	var from: Vector2 = (gain[0] as Vector2) - global_position
	var start: float = WAVE_START + from.length() / WAVE_SPEED + 0.25
	var k: float = (_t - start) / 0.9
	if k <= 0.0 or k >= 1.0:
		return
	var to: Vector2 = (gain_target - global_position) if gain_target != Vector2.INF else from + Vector2(0, -60)
	var e: float = k * k * (3.0 - 2.0 * k)
	var p: Vector2 = from.lerp(to, e) + Vector2(0, -40.0 * sin(PI * k) - 8.0)
	var texture: Texture2D = Items.icon({"id": String(gain[1]), "count": 1})
	var alpha: float = clampf(k * 5.0, 0.0, 1.0) * clampf((1.0 - k) * 4.0, 0.0, 1.0)
	_top.draw_circle(p.round(), 5.0, Color(TEAL, 0.25 * alpha))
	if texture != null:
		_top.draw_texture(texture, (p - Vector2(8, 8)).round(), Color(1, 1, 1, alpha))
