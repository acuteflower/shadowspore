class_name DungeonHud
extends Control
## Live in-dungeon HUD overlay (docs/dungeon_konzept.md Section 5.3):
## Top-left: carved Steinsetzer plaque with elapsed clear timer + 3 shared Group Veil Sparks.
## Top-right: dungeon name, active section objective, and optional 0..100% progress bar (swarm).

const BG_DARK: Color = Color("101524")
const BG_SLATE: Color = Color("1c2538")
const INK: Color = Color("05070e")
const TEAL: Color = Color("4df2e0")
const GOLD: Color = Color("ffd98a")
const TEXT: Color = Color("e8f2f7")
const MUTED: Color = Color("6b7c96")

var _manager: DungeonManager = null
var _state: Dictionary = {}
var _time: float = 0.0
var _covered: bool = false


func bind(_player: Player) -> void:
	_hook_manager.call_deferred()


func _ready() -> void:
	name = "DungeonHud"
	process_mode = Node.PROCESS_MODE_ALWAYS
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func _hook_manager() -> void:
	_manager = DungeonManager.of(get_tree())
	if _manager == null:
		return
	if not _manager.hud_state_changed.is_connected(_on_state):
		_manager.hud_state_changed.connect(_on_state)
	var cur: Dictionary = _manager.local_hud_state()
	if not cur.is_empty():
		_on_state(cur)


func _on_state(st: Dictionary) -> void:
	_state = st
	visible = not _state.is_empty()
	queue_redraw()


func set_covered(cov: bool) -> void:
	_covered = cov
	modulate.a = 0.0 if _covered else 1.0


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	if not bool(_state.get("completed", false)):
		_state["elapsed"] = float(_state.get("elapsed", 0.0)) + delta
	queue_redraw()


func _draw() -> void:
	if not visible or _state.is_empty() or _covered or InputManager.dungeons_open:
		return
	var vw: float = get_viewport_rect().size.x
	var pulse: float = 0.78 + 0.22 * sin(_time * 4.2)

	## Top-left plaque: Elapsed clear timer + 3 shared Group Veil Sparks
	var lp: Rect2 = Rect2(10, 8, 126, 36)
	draw_rect(lp, INK)
	draw_rect(lp.grow(-1), BG_DARK)
	draw_rect(lp.grow(-2), BG_SLATE)
	draw_rect(Rect2(lp.position.x + 2, lp.position.y + 2, lp.size.x - 4, 1), Color(TEAL, 0.75))

	var elapsed_str: String = DungeonRules.format_time(float(_state.get("elapsed", 0.0)))
	PixelText.draw(self, "ZEIT  %s" % elapsed_str, Vector2i(18, 14), GOLD, INK)

	var sparks: int = int(_state.get("sparks", 0))
	var max_sparks: int = int(_state.get("max_sparks", 3))
	PixelText.draw(self, "FUNKEN", Vector2i(18, 28), MUTED, INK)
	for i: int in max_sparks:
		var sx: float = 64.0 + float(i) * 18.0
		var sy: float = 27.0
		var alive: bool = i < sparks
		## Diamond Veil Spark glyph
		draw_rect(Rect2(sx - 1, sy - 1, 10, 10), INK)
		if alive:
			draw_rect(Rect2(sx, sy, 8, 8), Color(TEAL, 0.9 * pulse))
			draw_rect(Rect2(sx + 2, sy + 2, 4, 4), Color("e8ffff"))
		else:
			draw_rect(Rect2(sx, sy, 8, 8), Color("181c2c"))
			draw_rect(Rect2(sx + 2, sy + 2, 4, 4), Color("36283e"))

	## Top-right objective card (sits high in top-right corner, well above BossBar!)
	var obj: String = String(_state.get("objective", ""))
	var dname: String = String(_state.get("name", "GEWÖLBE"))
	var prog: float = float(_state.get("progress", -1.0))
	var rw: float = 192.0
	var rh: float = 42.0 if prog >= 0.0 else 32.0
	var rp: Rect2 = Rect2(vw - rw - 10.0, 8.0, rw, rh)
	draw_rect(rp, INK)
	draw_rect(rp.grow(-1), BG_DARK)
	draw_rect(rp.grow(-2), BG_SLATE)
	draw_rect(Rect2(rp.position.x + 2, rp.position.y + 2, rp.size.x - 4, 1), Color(GOLD, 0.7))

	PixelText.draw(self, dname.left(28), Vector2i(int(rp.position.x) + 8, int(rp.position.y) + 6), GOLD, INK)
	var shown_obj: String = obj if not obj.is_empty() else "ERKUNDE DAS GEWÖLBE"
	PixelText.draw(self, shown_obj.left(30), Vector2i(int(rp.position.x) + 8, int(rp.position.y) + 19), TEXT, INK)

	if prog >= 0.0:
		var bx: float = rp.position.x + 8.0
		var by: float = rp.position.y + 33.0
		var bw: float = rw - 16.0
		draw_rect(Rect2(bx, by, bw, 6), INK)
		draw_rect(Rect2(bx + 1, by + 1, (bw - 2.0) * clampf(prog, 0.0, 1.0), 4), TEAL)
		PixelText.draw(self, "%d%%" % int(round(prog * 100.0)), Vector2i(int(rp.end.x) - 28, int(rp.position.y) + 6), TEAL, INK)
