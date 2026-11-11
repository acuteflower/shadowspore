class_name SpellAim
extends Node2D
## What the crystal in her staff will do if she casts now (docs/magie_konzept.md), drawn only on her own screen while she holds the staff:
##   Glutschwarm      a little flame mark over every creature a shard would fly to, one ember dot per shard on it (KEIN ZIEL: nothing)
##   Nebelschleier    a ring of mist dashes under the player who would be veiled (the one under the pointer, else herself)
##   Leerenschlund    the pull circle, dotted, where the tear would open
##   Wurzelgrund      the circle where the roots would break out
## Dim while the crystal still charges; the Bleichgabel shows both prongs (the right-button one fainter). A child of the y-sorted world (so it sits on the ground), made by SpellComponent for its owner.

const STEP: float = 1.0 / 20.0

var spells: SpellComponent
var _t: float = 0.0
var _acc: float = 0.0


func _ready() -> void:
	z_index = 2
	material = SpellZone.add_material()
	top_level = true


func _process(delta: float) -> void:
	_t += delta
	_acc += delta
	if _acc >= STEP:
		_acc = 0.0
		queue_redraw()


func _draw() -> void:
	if spells == null or not is_instance_valid(spells) or not spells.staff_held or InputManager.ui_blocking:
		return
	var player: Player = spells.get_parent() as Player
	if player == null or player.health.current <= 0.0 or not player.attack.holds_staff():
		return
	var aim: Vector2 = InputManager.aim_world_position() if InputManager.using_mouse else player.global_position + player.facing * 60.0
	for prong: int in spells.prongs: ## the Bleichgabel: the second prong (right button) is drawn a little fainter
		_draw_prong(player, prong, aim, 1.0 if prong == 0 else 0.65)


func _draw_prong(player: Player, prong: int, aim: Vector2, weight: float) -> void:
	var p: Dictionary = spells.cast_params(prong)
	if p.is_empty():
		return
	var origin: Vector2 = player.global_position
	var bright: float = (0.85 if spells.is_ready(prong) else 0.25) * weight
	var colour: Color = SpellRules.school_color(String(p["school"]))
	match String(p["kind"]):
		"volley":
			var targets: Array[HurtboxComponent] = SpellComponent.volley_targets(player, origin, aim, float(p["range"]))
			var counts: Dictionary = {}
			for step: Array in SpellRules.volley_plan(targets.size(), int(p["shards"]), float(p["focus"])):
				counts[int(step[0])] = int(counts.get(int(step[0]), 0)) + 1
			for i: int in targets.size():
				if not counts.has(i):
					continue
				var at: Vector2 = targets[i].global_position + Vector2(0.0, -14.0) - global_position
				_flame_mark(at.round(), colour, bright, int(counts[i]))
		"veil":
			var mate: Player = SpellComponent.veil_target(origin, aim, float(p["range"]))
			var who: Player = mate if mate != null else player
			_ring(who.global_position - global_position, 10.0, colour, bright, 14, 0.8)
		"maw":
			var at2: Vector2 = SpellRules.target_point(origin, aim, float(p["range"])) - global_position
			_ring(at2, float(p["radius"]), colour, bright * 0.8, 40, -0.6)
			_ring(at2, float(p["radius"]) * 0.34, Color("ff4fd8"), bright * 0.6, 12, 1.4)
		"ground":
			var at3: Vector2 = SpellRules.target_point(origin, aim, float(p["range"])) - global_position
			_ring(at3, float(p["radius"]), colour, bright * 0.7, 36, 0.3)


## A flat dotted ring on the ground, its dots slowly turning (`spin` rad/s).
func _ring(at: Vector2, r: float, colour: Color, a: float, dots: int, spin: float) -> void:
	for k: int in dots:
		var ang: float = TAU * float(k) / float(dots) + _t * spin
		draw_rect(Rect2((at + Vector2(cos(ang) * r, sin(ang) * r * SpellZone.SQUASH)).round(), Vector2(2.0 if k % 3 == 0 else 1.0, 1.0)), Color(colour, a))


## Over a creature: a small flame, and an ember dot per shard that would hit it.
func _flame_mark(at: Vector2, colour: Color, a: float, shards: int) -> void:
	var flick: float = 1.0 if fmod(_t * 6.0, 1.0) < 0.5 else 0.0
	draw_rect(Rect2(at + Vector2(-1.0, -2.0), Vector2(3.0, 2.0)), Color(colour, a))
	draw_rect(Rect2(at + Vector2(0.0, -4.0 - flick), Vector2(1.0, 2.0 + flick)), Color(Color("ffd36a"), a))
	draw_rect(Rect2(at + Vector2(-2.0, 0.0), Vector2(5.0, 1.0)), Color(Color("d8461a"), a * 0.8))
	for s: int in shards:
		draw_rect(Rect2(at + Vector2(float(s) * 2.0 - float(shards - 1), 3.0), Vector2.ONE), Color(Color("fff4d0") if s == 0 else colour, a))
