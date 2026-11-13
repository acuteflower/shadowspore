class_name StarStone
extends Interactable
## One moonstone of the star mirror (`StarMirror`). Lying: E "AUFHEBEN". Carried: the node rides in front of its carrier's feet, where it would be set
## down, and offers that player "ABLEGEN" there (a faint ring marks the spot); everybody else sees it only in her arms (the carry sheet).
## On a star of the field it shows its lit picture and breathes a little light.

const SHEET: Texture2D = preload("res://assets/props/puzzles/moonstones.png")
const SHEET_GLOW: Texture2D = preload("res://assets/props/puzzles/moonstones_glow.png")
const RING: Color = Color("9ff8ee")

var mirror: StarMirror
var index: int = 0
var shape: int = 0
var carrier: int = 0 ## peer id carrying it, 0 = it lies
var on_star: int = -1 ## the star it lies on, -1 = none
var hidden_until: float = 0.0 ## after a set-down it shows only when her hands have let go

var _body: Sprite2D
var _glow: Sprite2D
var _w: int = 28
var _h: int = 24
var _g: int = 19
var _time: float = 0.0
var _shown_prompt: String = ""


func _ready() -> void:
	var art: Dictionary = DataRegistry.table("puzzle_art").get("star_mirror", {}) as Dictionary
	var f: Array = art.get("stone_frame", [28, 24]) as Array
	_w = int(f[0])
	_h = int(f[1])
	_g = int(art.get("stone_ground", 19))
	_body = Sprite2D.new()
	_body.texture = SHEET
	_body.centered = false
	_body.region_enabled = true
	_body.offset = Vector2(-_w / 2, -_g)
	add_child(_body)
	_glow = Sprite2D.new()
	_glow.texture = SHEET_GLOW
	_glow.centered = false
	_glow.region_enabled = true
	_glow.offset = _body.offset
	_glow.material = Unlit.material()
	add_child(_glow)
	refresh()


func refresh() -> void:
	if _body == null:
		return
	var lit: int = 1 if on_star >= 0 else 0
	var rect: Rect2 = Rect2(shape * _w, lit * _h, _w, _h)
	_body.region_rect = rect
	_glow.region_rect = rect
	var shown: bool = carrier == 0 and _time >= hidden_until
	_body.visible = shown
	_glow.visible = shown
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if _prompt_node != null and _prompt_node.visible: ## the verb changes under her hands (AUFHEBEN -> ABLEGEN): the shown tag follows
		var now: String = prompt() + "|" + prompt_hint()
		if now != _shown_prompt:
			_shown_prompt = now
			_prompt_node.show_text(prompt(), prompt_hint())
	if carrier != 0 and mirror != null:
		var p: Player = mirror.player_of(carrier)
		if p != null:
			global_position = mirror.drop_point(p)
		queue_redraw()
	elif not _body.visible and _time >= hidden_until:
		refresh()
	elif on_star >= 0:
		_glow.modulate.a = 0.75 + 0.25 * sin(_time * 2.4 + index)


func set_time_base(t: float) -> void:
	_time = t


func _draw() -> void:
	if carrier == 0 or carrier != multiplayer.get_unique_id():
		return
	var pulse: float = 0.5 + 0.5 * sin(_time * 5.0)
	var col: Color = RING
	col.a = 0.35 + 0.3 * pulse
	var snap: bool = mirror != null and mirror.snap_star(global_position, index) >= 0
	for k: int in 16: ## a dotted ring where it will lie (brighter when it would sit on a free star)
		var a: float = float(k) / 16.0 * TAU
		var p: Vector2 = (Vector2(cos(a) * 9.0, sin(a) * 4.5)).round()
		if k % 2 == 0 or snap:
			draw_rect(Rect2(p, Vector2.ONE), col if not snap else Color("fff2cc", col.a + 0.2))


func set_focused(on: bool) -> void:
	super.set_focused(on)
	_shown_prompt = prompt() + "|" + prompt_hint() if on else ""


func prompt() -> String:
	return mirror.stone_prompt(self) if mirror != null else ""


func prompt_hint() -> String:
	return mirror.stone_hint(self) if mirror != null else ""


func reach_distance(from: Vector2) -> float:
	if carrier != 0:
		return 0.0 if carrier == multiplayer.get_unique_id() else INF
	return maxf(0.0, global_position.distance_to(from) - 10.0)


func prompt_position() -> Vector2:
	return Vector2(0, -22)


func interact(player: Player) -> void:
	if mirror != null:
		mirror.stone_used(self, player)
