class_name WeaveCube
extends Interactable
## One cube of the root weave (`RootWeave`): the half-buried stone with its rune, risen out of the earth or still under it. The picture is one cell
## of assets/props/puzzles/weave_cubes.png (heart and crown: weave_heart.png) shown as a region, so the part still under the ground is cut away
## while it rises (`rise` 0..1). E asks the weave (`cube_prompt`, `cube_used`); focusing it shows what a touch would switch (`RootWeave.focus`).

const SHEET: Texture2D = preload("res://assets/props/puzzles/weave_cubes.png")
const SHEET_GLOW: Texture2D = preload("res://assets/props/puzzles/weave_cubes_glow.png")
const BIG: Texture2D = preload("res://assets/props/puzzles/weave_heart.png")
const BIG_GLOW: Texture2D = preload("res://assets/props/puzzles/weave_heart_glow.png")
const RUNE_DARK: Color = Color("2a2440")
const RUNE_LIT: Color = Color("9ff8ee")
const RUNE_GOLD: Color = Color("ffd27a")

var weave: RootWeave
var bit: int = -1
var kind: String = "cube"
var variant: int = 0
var rune: Array = [] ## 5 strings of the trial rune on its front
var rise: float = 0.0 ## 0 under the earth .. 1 out
var shown: int = 0 ## the column shown: 0 asleep, 1 lit, 2 gold (heart: 0 lit, 1 dark, 2 gold; crown: 3 shut, 4 bloom)
var opened: bool = false ## a seed that has grown shows its bloom
var jitter: Vector2 = Vector2.ZERO ## the preview's tremble

var _body: Sprite2D
var _glow: Sprite2D
var _mark: Node2D
var _shape: CollisionShape2D
var _fw: int = 40
var _fh: int = 44
var _gr: int = 36
var _anchor: Vector2 = Vector2.ZERO
var _rows: Array = []


func big() -> bool:
	return kind == "heart" or kind == "crown"


func _ready() -> void:
	var art: Dictionary = DataRegistry.table("puzzle_art").get("weave", {}) as Dictionary
	_rows = art.get("rows", []) as Array
	if big():
		var f: Array = art.get("heart_frame", [60, 66]) as Array
		_fw = int(f[0])
		_fh = int(f[1])
		_gr = int(art.get("heart_ground", 54))
	else:
		var f2: Array = art.get("frame", [40, 44]) as Array
		_fw = int(f2[0])
		_fh = int(f2[1])
		_gr = int(art.get("ground", 36))
		var anchors: Array = art.get("rune", []) as Array
		var row: int = _row()
		if row < anchors.size():
			var a: Array = anchors[row] as Array
			_anchor = Vector2(float(a[0]), float(a[1])).round()
	_body = Sprite2D.new()
	_body.texture = BIG if big() else SHEET
	_body.centered = false
	_body.region_enabled = true
	add_child(_body)
	_glow = Sprite2D.new()
	_glow.texture = BIG_GLOW if big() else SHEET_GLOW
	_glow.centered = false
	_glow.region_enabled = true
	_glow.material = Unlit.material()
	add_child(_glow)
	_mark = Node2D.new()
	_mark.material = Unlit.material()
	_mark.draw.connect(_draw_rune)
	add_child(_mark)
	var body: StaticBody2D = StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	_shape = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(30, 12) if big() else Vector2(18, 9)
	_shape.shape = rect
	_shape.position = Vector2(0, -3)
	body.add_child(_shape)
	add_child(body)
	refresh()


func _row() -> int:
	match kind:
		"seed":
			return maxi(0, _rows.find("seed_open" if opened else "seed"))
		"thorn":
			return maxi(0, _rows.find("thorn%d" % (variant % 2)))
	return maxi(0, _rows.find("cube%d" % (variant % 3)))


## Shows the current picture, cut where it is still under the earth.
func refresh() -> void:
	if _body == null:
		return
	var sink: float = (1.0 - rise) * float(_gr + 2)
	var vis: int = clampi(int(float(_gr) - sink + float(_fh - _gr) * rise) + 1, 0, _fh)
	var row: int = 0 if big() else _row()
	var rect: Rect2 = Rect2(shown * _fw, row * _fh, _fw, vis)
	var off: Vector2 = Vector2(-_fw / 2, -_gr + roundf(sink)) + jitter
	for s: Sprite2D in [_body, _glow]:
		s.visible = vis > 0
		s.region_rect = rect
		s.offset = off
	_shape.disabled = rise < 0.6
	_mark.queue_redraw()


func _draw_rune() -> void:
	if big() or rune.is_empty() or rise <= 0.0:
		return
	var sink: float = roundf((1.0 - rise) * float(_gr + 2))
	var col: Color = [RUNE_DARK, RUNE_LIT, RUNE_GOLD][clampi(shown, 0, 2)]
	if kind == "thorn":
		col = col.darkened(0.35)
	var top: Vector2 = _anchor + Vector2(-2, -2 + sink) + jitter
	for y: int in rune.size():
		var line: String = String(rune[y])
		for x: int in line.length():
			if line[x] != "X" or top.y + y > 0.0:
				continue
			_mark.draw_rect(Rect2(top + Vector2(x, y), Vector2.ONE), col)


func prompt() -> String:
	return weave.cube_prompt(bit) if weave != null else ""


func prompt_hint() -> String:
	return weave.cube_hint(bit) if weave != null else ""


func reach_distance(from: Vector2) -> float:
	return maxf(0.0, global_position.distance_to(from) - (22.0 if big() else 14.0))


func prompt_position() -> Vector2:
	return Vector2(0, -52) if big() else Vector2(0, -36)


func interact(player: Player) -> void:
	if weave != null:
		weave.cube_used(bit, player)


func set_focused(on: bool) -> void:
	super.set_focused(on)
	if weave != null:
		weave.focus(bit, on)
