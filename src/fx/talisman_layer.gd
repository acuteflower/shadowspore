class_name TalismanLayer
extends Node2D
## The worn necklace and earrings on her sprite (docs/talisman_konzept.md section 5): a child of the player's Sprite2D (so it follows the limp's lean and the
## bob), it draws what `TalismanArt` draws at the points of the sprite's current frame. Cutscene sheets carry no points and show nothing. The pixels that shine
## on their own (void stones at night) are a second pass on an unlit child.
## The bracelet is not here: it sits on the arm `AttackComponent` draws.

var _sprite: Sprite2D
var _talismans: TalismanComponent
var _glow: Node2D
var _time: float = 0.0
var _flash: float = 0.0 ## a swallowed blow: the stones flare for a moment
var _key: Array = [null, -1] ## texture and frame of `_data`
var _data: PackedInt32Array = PackedInt32Array()


func _ready() -> void:
	_sprite = get_parent() as Sprite2D
	_talismans = _sprite.get_parent().get_node_or_null("TalismanComponent") as TalismanComponent
	_glow = Node2D.new()
	_glow.material = Unlit.material()
	_glow.draw.connect(func() -> void: _paint(null, _glow))
	add_child(_glow)
	if _talismans != null:
		_talismans.absorbed.connect(func() -> void: _flash = 1.0)


func _process(delta: float) -> void:
	_time += delta
	_flash = maxf(_flash - delta * 2.2, 0.0)
	if _talismans == null or _talismans.worn.is_empty() or not _sprite.visible:
		if not _data.is_empty():
			_data = PackedInt32Array()
			queue_redraw()
			_glow.queue_redraw()
		return
	if _key[0] != _sprite.texture or int(_key[1]) != _sprite.frame:
		_key = [_sprite.texture, _sprite.frame]
		_data = TalismanArt.frame_data(_sprite.texture, _sprite.frame)
	queue_redraw()
	_glow.queue_redraw()


func _draw() -> void:
	_paint(self, null)


func _paint(canvas: CanvasItem, glow: CanvasItem) -> void:
	if _talismans == null or _data.is_empty():
		return
	TalismanArt.draw_worn(canvas, glow, _talismans.worn, _data, Vector2.ZERO, 1.0, _time, MineManager.night_at(self, TimeManager.night_amount()), _flash)
