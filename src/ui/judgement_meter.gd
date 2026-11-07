class_name JudgementMeter
extends Control
## The counter of the judgement (docs/boss_sky_cleaver.md), local to every player near the arena: under the boss bar the word URTEIL and a crack of light that runs out
## with the seconds that are left, the number at its end. It turns magenta and stutters in the last seconds. `show_for(fight)` creates it (null for a peer without a
## local player near the arena), `leave()` lets it fade. It only reads the fight (`judge_elapsed`, `judge_total`, `judge_failed`).

const GOLD: Color = Color("ffd98a")
const VEIN: Color = Color("7d57e0")
const VEIN_LIGHT: Color = Color("a98af0")
const CORE_HOT: Color = Color("fff7ff")
const MAGENTA: Color = Color("ff4fd8")
const INK: Color = Color("040109")
const W: int = 300
const SIZE_PX: Vector2 = Vector2(380, 30)
const BAR_Y_OFFSET: float = 50.0

var _fight: MornathFight
var _t: float = 0.0
var _life: float = 0.0
var _leaving: bool = false
var _layer: CanvasLayer


static func show_for(fight: MornathFight) -> JudgementMeter:
	if DisplayServer.get_name() == "headless":
		return null
	var near: bool = false
	for player: Player in Player.all:
		if player.is_multiplayer_authority() and player.health.current > 0.0 and player.global_position.distance_to(fight.boss.centre()) < 700.0:
			near = true
			break
	if not near:
		return null
	var meter: JudgementMeter = JudgementMeter.new()
	meter._fight = fight
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meter.size = SIZE_PX
	var bar: Control = fight.get_tree().get_first_node_in_group("boss_bar") as Control
	if bar != null:
		bar.add_child(meter)
		meter.position = Vector2((bar.size.x - SIZE_PX.x) * 0.5, BAR_Y_OFFSET)
	else:
		meter._layer = CanvasLayer.new()
		meter._layer.layer = 40
		fight.get_tree().root.add_child(meter._layer)
		meter._layer.add_child(meter)
		meter.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_KEEP_SIZE)
		meter.position.y = BAR_Y_OFFSET
	return meter


func leave() -> void:
	_leaving = true


func _process(delta: float) -> void:
	_t += delta
	_life = move_toward(_life, 0.0 if _leaving else 1.0, delta * 2.5)
	if _leaving and _life <= 0.0:
		if _layer != null:
			_layer.queue_free()
		queue_free()
		return
	if not is_instance_valid(_fight):
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	if not is_instance_valid(_fight) or _life <= 0.01:
		return
	var total: float = maxf(_fight.judge_total(), 0.01)
	var left: float = total - _fight.judge_elapsed()
	var k: float = clampf(left / total, 0.0, 1.0)
	var urgent: float = 1.0 - smoothstep(4.0, 12.0, left)
	var failed: bool = _fight.judge_failed
	var a: float = _life
	var stutter: float = 1.0
	if urgent > 0.6 or failed:
		stutter = 1.0 if fmod(_t * (9.0 + 8.0 * urgent), 1.0) > 0.18 else 0.35
	var accent: Color = VEIN_LIGHT.lerp(MAGENTA, urgent)
	var x0: float = roundf((SIZE_PX.x - float(W)) * 0.5)
	var y: float = 20.0
	# the word, small, in gold that turns magenta
	var label: String = "URTEIL"
	var lw: int = PixelText.width(label)
	PixelText.draw(self, label, Vector2i(int(roundf(SIZE_PX.x * 0.5 - float(lw) * 0.5)), 4), Color(GOLD.lerp(MAGENTA, urgent), a * stutter), Color(INK, a))
	# the crack: its length is the time that is left, jagged by whole pixels
	var length: int = int(float(W) * k)
	for i: int in length:
		var jag: int = int(roundf((_noise(float(i) * 0.13 + 4.0) - 0.5) * 3.0))
		var edge: float = 1.0 - pow(float(i) / float(maxi(length, 1)), 6.0) * 0.0
		var pos: Vector2 = Vector2(x0 + float(i), y + float(jag))
		draw_rect(Rect2(pos + Vector2(0, -1), Vector2(1, 3)), Color(INK, 0.8 * a))
	for i2: int in length:
		var jag2: int = int(roundf((_noise(float(i2) * 0.13 + 4.0) - 0.5) * 3.0))
		var beat: float = VoidGlow.beat(_t - float(i2) * 0.012, 0.0, 0.8 + urgent * 0.6)
		var color: Color = accent.lerp(CORE_HOT, 0.25 + 0.5 * beat)
		draw_rect(Rect2(Vector2(x0 + float(i2), y + float(jag2)), Vector2(1, 1)), Color(color, a * stutter * (0.65 + 0.35 * beat)))
	# the tip burns
	var tip: Vector2 = Vector2(x0 + float(length), y)
	draw_rect(Rect2(tip + Vector2(-1, -2), Vector2(3, 5)), Color(CORE_HOT, a * stutter))
	# the number at the end of the crack
	var seconds: String = str(maxi(ceili(left), 0))
	PixelText.draw(self, seconds, Vector2i(int(x0) + W + 6, 16), Color(CORE_HOT.lerp(MAGENTA, urgent), a * stutter), Color(INK, a))


func _noise(x: float) -> float:
	var i: float = floorf(x)
	var f: float = x - i
	f = f * f * (3.0 - 2.0 * f)
	return lerpf(_h(int(i)), _h(int(i) + 1), f)


func _h(n: int) -> float:
	return float(hash(n * 7919 + 13) % 1000) / 1000.0
