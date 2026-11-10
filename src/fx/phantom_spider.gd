class_name PhantomSpider
extends Node2D
## A shadow spider that is not there (docs/hexenwald_nebel_konzept.md): what a hallucinating heroine sees in the Hexenwald. It borrows the real spider's look
## (`SpiderRig`, the birth mouth, the red warning fan) and plays a fixed script on her own machine only: it tears out of the ground, stalks her, winds up and
## simply dissolves in the middle of its blow (it thins out, no burst). A swing at it cuts nothing. No body, no hurtbox, no damage, no host, nothing replicated or saved.
## Tells: it leaves no shadow prints, walks through trunks, flickers witch green now and then and finds her even when she sneaks.

signal vanished

enum Step { RISE, STALK, WINDUP, STRIKE, GONE }

const BODY: Texture2D = preload("res://assets/enemies/shadow_spider_body.png")
const FLASH: Shader = preload("res://assets/shaders/hit_flash.gdshader")
const SOUNDS: String = "res://assets/audio/hexenwald/"
const ZONE_DARK: Color = Color("c21f3b")
const ZONE_HOT: Color = Color("ff4a63")
const GIVE_UP: float = 10.0 ## seconds of stalking after which it simply thins out
const FADE: float = 0.7

var target: Player
var step: Step = Step.RISE

var _def: Dictionary
var _rig: SpiderRig
var _zone: Node2D
var _time: float = 0.0 ## in this step
var _heading: float = PI / 2.0
var _dir: Vector2 = Vector2.DOWN
var _orbit: float = 1.0
var _flicker: float = 1.2


func _ready() -> void:
	_def = DataRegistry.get_entry("enemies", "shadow_spider")
	_orbit = 1.0 if randf() < 0.5 else -1.0
	_zone = Node2D.new()
	_zone.z_index = -8
	_zone.material = Unlit.material()
	_zone.draw.connect(_draw_zone)
	add_child(_zone)
	_rig = SpiderRig.new()
	for part: String in ["Back", "Body", "Front", "Glow"]:
		var node: Node2D = Sprite2D.new() if part == "Body" else Node2D.new()
		node.name = part
		_rig.add_child(node)
	var body: Sprite2D = _rig.get_node("Body") as Sprite2D
	body.texture = BODY
	body.hframes = 8
	var flash: ShaderMaterial = ShaderMaterial.new()
	flash.shader = FLASH
	body.material = flash
	var add: CanvasItemMaterial = CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	(_rig.get_node("Glow") as Node2D).material = add
	_rig.strike_reach = float(_def["reach"])
	_rig.strike_arc = deg_to_rad(float(_def["arc"]))
	_rig.strike_hit_fraction = float(_def["strike_hit_time"]) / float(_def["strike"])
	_rig.emergence = 0.0
	add_child(_rig)
	var birth: ShadowBirth = ShadowBirth.new()
	add_child(birth)
	_rig.emergence_seed = randf() * 1000.0
	if is_instance_valid(target):
		_dir = (target.global_position - global_position).normalized()
		_heading = _dir.angle()


func _process(delta: float) -> void:
	if not is_instance_valid(target):
		queue_free()
		return
	_time += delta
	var to: Vector2 = target.global_position - global_position
	var distance: float = to.length()
	var velocity: Vector2 = Vector2.ZERO
	match step:
		Step.RISE:
			_rig.emergence = clampf(_time / ShadowBirth.DURATION, 0.0, 1.0)
			if _time >= ShadowBirth.DURATION:
				_enter(Step.STALK)
		Step.STALK:
			_dir = to.normalized().rotated(_orbit * 0.6 * clampf((distance - 44.0) / 90.0, 0.0, 1.0)) ## it circles in, like the real one
			velocity = _dir * float(_def["chase_speed"])
			global_position += velocity * delta
			_heading = lerp_angle(_heading, to.angle(), 1.0 - exp(-float(_def["turn_speed"]) * delta))
			if distance <= float(_def["attack_range"]):
				_dir = to.normalized()
				_enter(Step.WINDUP)
				_rig.start_pose(SpiderRig.Pose.WINDUP, float(_def["windup"]))
			elif _time > GIVE_UP:
				dissolve(false)
		Step.WINDUP:
			if _time < float(_def["windup"]) - float(_def["aim_lock_seconds"]): ## the aim locks before the blow, as with the real one
				_dir = to.normalized()
				_heading = _dir.angle()
			if _time >= float(_def["windup"]):
				_enter(Step.STRIKE)
				_rig.start_pose(SpiderRig.Pose.STRIKE, float(_def["strike"]))
		Step.STRIKE:
			if _time >= float(_def["strike_hit_time"]) * 0.6: ## in the middle of the blow, a breath before it would land
				dissolve(true)
		Step.GONE:
			_rig.modulate.a = 1.0 - clampf(_time / FADE, 0.0, 1.0)
			if _time >= FADE:
				vanished.emit()
				queue_free()
	if step in [Step.STALK, Step.WINDUP] and distance < 48.0 and target.attack != null and target.attack.is_swinging():
		dissolve(true) ## her blade goes through smoke
	if step != Step.GONE:
		_flicker -= delta
		_rig.modulate = Color(0.55, 1.5, 0.5) if _flicker < 0.0 else Color.WHITE ## the tell: for a blink it is the wood's green, not the void's violet
		if _flicker < -0.06:
			_flicker = randf_range(1.1, 2.6)
	_rig.set_aim(_dir)
	_rig.update_rig(delta, velocity, _heading)
	_zone.queue_redraw()


func _enter(next: Step) -> void:
	step = next
	_time = 0.0


## It falls apart. `loud`: with the suck, the burst and a jolt of her camera (the blow that never lands); quiet when it merely thins out.
func dissolve(loud: bool) -> void:
	if step == Step.GONE:
		return
	_enter(Step.GONE)
	puff(get_parent(), global_position, -6.0 if loud else -80.0)
	if loud and is_instance_valid(target):
		target.add_shake(2.0)


## The sound of something that was never there, at `at` (a child of `parent`, frees itself). No particles: what is false simply thins out.
static func puff(parent: Node, at: Vector2, volume_db: float) -> void:
	if parent == null or volume_db <= -60.0 or not ResourceLoader.exists(SOUNDS + "puff.wav"):
		return
	var voice: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	voice.stream = load(SOUNDS + "puff.wav") as AudioStream
	voice.volume_db = volume_db
	voice.pitch_scale = randf_range(0.9, 1.1)
	voice.max_distance = 400.0
	parent.add_child(voice)
	voice.global_position = at
	voice.finished.connect(voice.queue_free)
	voice.play()


## The same flowing red fan the real spider warns with (ShadowSpider._zone_fan), without the hit behind it.
func _draw_zone() -> void:
	if step != Step.WINDUP:
		return
	var locked: bool = _time >= float(_def["windup"]) - float(_def["aim_lock_seconds"])
	var density: float = 0.6 if locked else 0.38
	var strength: float = (0.8 + 0.2 * signf(sin(_time * 40.0))) if locked else 0.75
	var flow: float = 13.0 if locked else 7.0
	var reach: float = float(_def["reach"]) + 3.0
	var half_arc: float = deg_to_rad(float(_def["arc"])) / 2.0
	var span: int = ceili(reach)
	for y: int in range(-span, span + 1):
		for x: int in range(-span, span + 1):
			var offset: Vector2 = Vector2(x, y)
			var distance: float = offset.length()
			if distance < 3.0 or distance > reach:
				continue
			var off_axis: float = absf(angle_difference(_dir.angle(), offset.angle()))
			if off_axis > half_arc:
				continue
			var h: float = fposmod(sin(float(x) * 12.9898 + float(y) * 78.233) * 43758.5453, 1.0)
			if h > density:
				continue
			var wave: float = 0.5 + 0.5 * sin(distance * 0.3 - _time * flow + h * TAU)
			var edge: float = minf(smoothstep(3.0, 9.0, distance), 1.0 - smoothstep(reach - 7.0, reach, distance)) * (1.0 - smoothstep(half_arc * 0.7, half_arc, off_axis))
			var alpha: float = strength * (0.4 + 0.6 * wave) * edge * 0.9
			if alpha > 0.04:
				_zone.draw_rect(Rect2(offset + Vector2(0, 2), Vector2.ONE), Color(ZONE_DARK.lerp(ZONE_HOT, wave), alpha))
