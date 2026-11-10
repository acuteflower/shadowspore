class_name PetTag
extends Node2D
## The little bark-paper card over a registered crow or raven (docs/pet_konzept.md 9.1): its name, five feather pips (one filled per stage the LOCAL player's
## bond has reached) and a thin teal thread along the lower edge that fills towards the next stage. It shows while the local player is near (`tag.near` px),
## while the mouse rests on the bird and for a few seconds after a feeding, when a gold "+N" rises from it. Unlit, cosmetic, every peer draws it for its own player.
## Birds that are not registered have no tag.

const INK: Color = Color("1b1a2e")
const GOLD: Color = Color("ffd98a")
const TEAL: Color = Color("78f4e6")
const DIM: Color = Color("5b4f7a")
const PIPS: int = 5

var _bird: WildCorvid
var _alpha: float = 0.0
var _hold: float = 0.0 ## seconds the card stays after a feeding
var _pop_age: float = 99.0
var _pop_text: String = ""


func _ready() -> void:
	_bird = get_parent() as WildCorvid
	z_index = 60
	material = Unlit.material()
	var registry: PetRegistry = PetRegistry.of(get_tree())
	if registry != null:
		registry.bond_changed.connect(_on_bond)


func _on_bond(key: String, peer: int, gained: float, _up: bool) -> void:
	if _bird == null or key != _bird.pet_key or peer != multiplayer.get_unique_id() or gained <= 0.0:
		return
	_hold = float((PetRules.table()["tag"] as Dictionary)["show_seconds"])
	_pop_age = 0.0
	_pop_text = "+%d" % roundi(gained)


## A word over the bird for a moment (modes, abilities, the whistle).
func flash(text: String) -> void:
	_hold = 2.6
	_pop_age = 0.0
	_pop_text = text


func _local() -> Player:
	for player: Player in Player.all:
		if player.is_multiplayer_authority():
			return player
	return null


func _process(delta: float) -> void:
	var registry: PetRegistry = PetRegistry.of(get_tree())
	if _bird == null or registry == null or not registry.has_record(_bird.pet_key):
		if _alpha > 0.0:
			_alpha = 0.0
			queue_redraw()
		return
	_hold = maxf(0.0, _hold - delta)
	_pop_age += delta
	var me: Player = _local()
	var near: float = float((PetRules.table()["tag"] as Dictionary)["near"])
	var wanted: bool = _hold > 0.0 or (me != null and me.global_position.distance_to(_bird.global_position) < near) \
		or get_global_mouse_position().distance_to(_bird.global_position - Vector2(0.0, 6.0)) < 16.0
	_alpha = move_toward(_alpha, 1.0 if wanted else 0.0, delta * 4.0)
	position = Vector2(0.0, -(28.0 + _bird._height))
	if _alpha > 0.0 or _pop_age < 1.4:
		queue_redraw()


func _draw() -> void:
	var registry: PetRegistry = PetRegistry.of(get_tree())
	if _alpha <= 0.01 or _bird == null or registry == null or not registry.has_record(_bird.pet_key):
		return
	var key: String = _bird.pet_key
	var label: String = registry.name_of(key)
	var bp: float = registry.bp_of(key, multiplayer.get_unique_id())
	var stage: int = PetRules.stage_of(bp)
	var width: int = maxi(PixelText.width(label), PIPS * 4 - 1) + 8
	var left: int = -int(width / 2.0)
	var top: int = -16
	var a: float = _alpha
	draw_rect(Rect2(left, top, width, 16), Color(INK, a))
	draw_rect(Rect2(left + 1, top + 1, width - 2, 14), Color(VineStyle.BARK_VOID.lerp(VineStyle.BARK, 0.45), a))
	draw_rect(Rect2(left + 1, top + 1, width - 2, 1), Color(VineStyle.BARK.lightened(0.25), a * 0.7)) ## lit upper edge
	PixelText.draw(self, label, Vector2i(left + 4, top + 3), Color(GOLD, a))
	var pips_x: int = -int((PIPS * 4 - 1) / 2.0)
	for i: int in PIPS:
		var filled: bool = i < stage
		var at: Vector2i = Vector2i(pips_x + i * 4, top + 10)
		draw_rect(Rect2(at.x, at.y, 3, 3), Color(INK, a))
		draw_rect(Rect2(at.x + 1, at.y + 1, 1, 1), Color(GOLD if filled else DIM, a))
		if filled:
			draw_rect(Rect2(at.x, at.y, 1, 1), Color(GOLD.lightened(0.4), a * 0.8))
	var progress: float = PetRules.stage_progress(bp)
	draw_rect(Rect2(left + 1, top + 14, width - 2, 1), Color(DIM, a * 0.6))
	draw_rect(Rect2(left + 1, top + 14, roundi((width - 2) * progress), 1), Color(TEAL, a))
	draw_rect(Rect2(-1, 0, 3, 1), Color(INK, a)) ## the stalk down to the bird
	draw_rect(Rect2(0, 0, 1, 2), Color(INK, a))
	if _pop_age < 1.4 and _pop_text != "":
		var rise: float = _pop_age / 1.4
		PixelText.draw(self, _pop_text, Vector2i(left + width + 2, top + 2 - int(rise * 10.0)), Color(GOLD, (1.0 - rise) * a), Color(INK, (1.0 - rise) * a))
