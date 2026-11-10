class_name BoardNotes
extends Node2D
## The notices of the quest board, seen from outside (docs/questtafel_konzept.md): every notice that hangs is a small paper pinned to the panel of the built board, so a
## passer-by sees at once whether there is something new. Six places on the panel (story notices take the first ones), a new notice drops into place, a paper the local player
## has already taken or finished hangs faded, a story notice is gold with a glowing teal seal (the unlit pass), the paper flicks in the wind now and then.
## One child of the board's `TownStructure`, twice: the lit paper and, with `unlit`, the seal on top. The drawing is static (`paint`) so a preview can use it without a world.
## The panel of art_quest_board.py spans x -14..14, y -30..-15 from the feet (frame 56x56, feet row 50).

const SLOTS: Array[Vector2] = [Vector2(-13, -29), Vector2(-4, -29), Vector2(5, -29), Vector2(-13, -21), Vector2(-4, -21), Vector2(5, -21)] ## top left of each 7x6 paper
const W: int = 7
const H: int = 6
const FETCH_PAPER: Color = Color("e8dcc0")
const KILL_PAPER: Color = Color("e6c9b4")
const STORY_PAPER: Color = Color("e9c76a")
const INK: Color = Color("3a2c3e")
const RED: Color = Color("b8465a")
const PIN: Color = Color("8a8296")
const SEAL: Color = Color("78f4e6")
const DROP_TIME: float = 0.55

var board: BoardManager
var structure: TownStructure
var unlit: bool = false
var _time: float = 0.0
var _ages: Dictionary = {} ## offer id -> seconds it has hung on this peer (new ones drop in)
var _seen_first: bool = false


func _ready() -> void:
	z_index = 1 if unlit else 0
	if unlit:
		material = Unlit.material()
	if board != null:
		board.changed.connect(queue_redraw)


func _exit_tree() -> void:
	if board != null and board.changed.is_connected(queue_redraw):
		board.changed.disconnect(queue_redraw)


func _process(delta: float) -> void:
	_time += delta
	var built: bool = structure != null and structure.progress >= TownManager.PROGRESS_FULL
	visible = built
	if not built or board == null:
		return
	var present: Dictionary = {}
	for offer: Dictionary in board.offers:
		var id: int = int(offer.id)
		present[id] = true
		if not _ages.has(id):
			_ages[id] = 99.0 if not _seen_first else 0.0 ## what already hangs when the board comes into view does not drop in
		else:
			_ages[id] = float(_ages[id]) + delta
	for id: Variant in _ages.keys():
		if not present.has(id):
			_ages.erase(id)
	_seen_first = true
	queue_redraw()


func _draw() -> void:
	if board == null or structure == null:
		return
	var peer: int = multiplayer.get_unique_id()
	var notes: Array[Dictionary] = []
	for offer: Dictionary in board.offers:
		var mine: bool = not board.entry_of(int(offer.id), peer).is_empty()
		var age: float = float(_ages.get(int(offer.id), 99.0))
		notes.append({"k": String(offer.k), "id": int(offer.id), "a": 0.5 if mine else 1.0, "drop": 1.0 - clampf(age / DROP_TIME, 0.0, 1.0)})
	BoardNotes.paint(self, notes, _time, structure.is_flipped(), unlit, TimeManager.night_amount())


## The order of the places: story notices first, then by id. Public for the preview.
static func ordered(notes: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = notes.duplicate()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa: bool = String(a.k) == BoardRules.STORY
		var sb: bool = String(b.k) == BoardRules.STORY
		return (sa and not sb) or (sa == sb and int(a.id) < int(b.id)))
	return out


## Draws up to six notes: [{k kind, id, a alpha, drop 1..0 how far above its place it still is}]. `seals` false draws the paper (lit), true only the seals of the story notices (on an unlit node).
static func paint(canvas: CanvasItem, notes: Array[Dictionary], time: float, flipped: bool, seals: bool, night: float) -> void:
	var sorted: Array[Dictionary] = ordered(notes)
	for slot: int in mini(sorted.size(), SLOTS.size()):
		var note: Dictionary = sorted[slot]
		var id: int = int(note.id)
		var tilt: int = (id + slot) % 3 - 1
		if sin(time * 1.3 + float(id) * 2.1) > 0.985: ## a gust lifts the corner for a moment
			tilt = -tilt if tilt != 0 else 1
		var at: Vector2 = SLOTS[slot] - Vector2(0.0, roundf(float(note.drop) * 7.0))
		if flipped:
			at.x = -at.x - float(W)
		var alpha: float = float(note.a) * (1.0 - float(note.drop) * 0.6)
		if seals:
			if String(note.k) == BoardRules.STORY:
				_seal(canvas, at, alpha, time, night, id)
		else:
			_paper(canvas, at, String(note.k), alpha, tilt, id)


static func _px(canvas: CanvasItem, x: float, y: float, color: Color, w: float = 1.0, h: float = 1.0) -> void:
	canvas.draw_rect(Rect2(roundf(x), roundf(y), w, h), color)


static func _paper(canvas: CanvasItem, at: Vector2, kind: String, alpha: float, tilt: int, id: int) -> void:
	var paper: Color = STORY_PAPER if kind == BoardRules.STORY else (KILL_PAPER if kind == BoardRules.KILL else FETCH_PAPER)
	var edge: Color = paper.darkened(0.35)
	_px(canvas, at.x + 1.0, at.y + 1.0, Color(0, 0, 0, 0.35 * alpha), W, H) ## the shadow on the planks
	for row: int in H:
		var shift: float = float(tilt) * (1.0 if row >= H - 2 else 0.0)
		var shade: Color = paper.lightened(0.12) if row == 0 else (edge if row == H - 1 else paper)
		_px(canvas, at.x + shift, at.y + float(row), Color(shade, alpha), W, 1.0)
	_px(canvas, at.x, at.y, Color(edge, alpha), 1.0, float(H) - 1.0) ## left edge in shade
	for line: int in 2: ## writing: two short dark strokes with air between, each paper its own
		var row: float = 2.0 + float(line) * 2.0
		if row >= float(H) - 1.0:
			break
		_px(canvas, at.x + 1.0, at.y + row, Color(INK, 0.75 * alpha), float(3 + (id * 5 + line * 3) % 3), 1.0)
	if kind == BoardRules.KILL: ## a red mark: this one is a hunt
		_px(canvas, at.x + float(W) - 3.0, at.y + float(H) - 3.0, Color(RED, alpha), 2.0, 2.0)
	_px(canvas, at.x + 3.0, at.y, Color(PIN, alpha)) ## the pin
	_px(canvas, at.x + 3.0, at.y - 1.0, Color(PIN.lightened(0.4), alpha * 0.8))


static func _seal(canvas: CanvasItem, at: Vector2, alpha: float, time: float, night: float, id: int) -> void:
	var pulse: float = 0.75 + 0.25 * sin(time * 2.4 + float(id))
	var strength: float = (0.55 + 0.45 * night) * alpha
	var centre: Vector2 = at + Vector2(float(W) / 2.0 - 0.5, float(H) - 2.0)
	_px(canvas, centre.x - 1.0, centre.y - 1.0, Color(SEAL, 0.18 * strength * pulse), 3.0, 3.0) ## a faint halo
	_px(canvas, centre.x, centre.y, Color(SEAL, strength))
	_px(canvas, centre.x, centre.y - 1.0, Color(SEAL, 0.45 * strength * pulse))
