class_name DungeonReadyBanner
extends Control
## Lost-Ark Coop Ready-Check banner pinned top-center (docs/dungeon_konzept.md Section 5.2).
## Appears for all level-eligible players across ALTMARK when someone starts a Coop call at a gate.

const W: float = 340.0
const H: float = 92.0
const BG_DARK: Color = Color("121726")
const BG_SLATE: Color = Color("1d263b")
const BORDER_INK: Color = Color("06080f")
const TEAL: Color = Color("4df2e0")
const GOLD: Color = Color("ffd98a")
const TEXT_LIGHT: Color = Color("e6f0f5")
const MUTED: Color = Color("8b9bb4")
const DANGER: Color = Color("ff5c7a")

var _player: Player = null
var _manager: DungeonManager = null
var _payload: Dictionary = {}
var _use_res: bool = true
var _responded: bool = false
var _time_left: float = 0.0
var _duration: float = 20.0
var _hover_btn: String = ""

var _accept_rect: Rect2 = Rect2()
var _decline_rect: Rect2 = Rect2()
var _res_rect: Rect2 = Rect2()


func bind(player: Player) -> void:
	_player = player
	_hook_manager.call_deferred()


func _ready() -> void:
	name = "DungeonReadyBanner"
	process_mode = Node.PROCESS_MODE_ALWAYS
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_KEEP_SIZE)
	custom_minimum_size = Vector2(W, H)
	size = Vector2(W, H)
	offset_left = -W * 0.5
	offset_right = W * 0.5
	offset_top = 26.0
	offset_bottom = 26.0 + H
	visible = false


func _hook_manager() -> void:
	_manager = DungeonManager.of(get_tree())
	if _manager == null:
		return
	if not _manager.ready_check_opened.is_connected(_on_opened):
		_manager.ready_check_opened.connect(_on_opened)
	if not _manager.ready_check_updated.is_connected(_on_updated):
		_manager.ready_check_updated.connect(_on_updated)
	if not _manager.ready_check_closed.is_connected(_on_closed):
		_manager.ready_check_closed.connect(_on_closed)


func _on_opened(payload: Dictionary) -> void:
	_payload = payload
	_time_left = float(payload.get("time_left", 20.0))
	_duration = maxf(float(payload.get("duration", 20.0)), 1.0)
	_use_res = _player.dungeons.prefer_resonance if (_player != null and _player.dungeons != null) else true
	var my_peer: int = multiplayer.get_unique_id()
	var responses: Dictionary = payload.get("responses", {}) as Dictionary
	_responded = bool(responses.get(my_peer, false))
	visible = true
	Sfx.ui(self, "skills/reveal", -4.0)
	queue_redraw()


func _on_updated(payload: Dictionary) -> void:
	_payload = payload
	_time_left = float(payload.get("time_left", _time_left))
	var my_peer: int = multiplayer.get_unique_id()
	var responses: Dictionary = payload.get("responses", {}) as Dictionary
	_responded = bool(responses.get(my_peer, false))
	queue_redraw()


func _on_closed(_reason: String) -> void:
	visible = false
	_payload = {}
	_responded = false


func _process(delta: float) -> void:
	if not visible:
		return
	_time_left = maxf(_time_left - delta, 0.0)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion:
		var pos: Vector2 = (event as InputEventMouseMotion).position
		var prev: String = _hover_btn
		if _accept_rect.has_point(pos):
			_hover_btn = "accept"
		elif _decline_rect.has_point(pos):
			_hover_btn = "decline"
		elif _res_rect.has_point(pos):
			_hover_btn = "res"
		else:
			_hover_btn = ""
		if prev != _hover_btn:
			queue_redraw()
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var pos: Vector2 = mb.position
			if _res_rect.has_point(pos) and not _responded:
				_use_res = not _use_res
				if _player != null and _player.dungeons != null:
					_player.dungeons.prefer_resonance = _use_res
				queue_redraw()
				accept_event()
			elif _accept_rect.has_point(pos) and not _responded and _manager != null:
				_responded = true
				_manager.respond_ready_check(int(_payload.get("id", 0)), true, _use_res)
				queue_redraw()
				accept_event()
			elif _decline_rect.has_point(pos) and _manager != null:
				_manager.respond_ready_check(int(_payload.get("id", 0)), false, false)
				accept_event()


func _draw() -> void:
	if not visible or _payload.is_empty():
		return
	var def: Dictionary = DungeonRules.by_id(String(_payload.get("dungeon_id", "")))
	var dname: String = String(def.get("name", "GEWÖLBE"))

	## Carved Steinsetzer panel frame
	draw_rect(Rect2(0, 0, W, H), BORDER_INK)
	draw_rect(Rect2(1, 1, W - 2, H - 2), BG_DARK)
	draw_rect(Rect2(3, 3, W - 6, H - 6), BG_SLATE)
	draw_rect(Rect2(2, 2, W - 4, 1), Color(TEAL, 0.7))

	## Header + countdown timer
	PixelText.draw(self, "SAMMELRUF: %s" % dname, Vector2i(10, 8), GOLD, BORDER_INK)
	var t_txt: String = "%ds" % ceili(_time_left)
	PixelText.draw(self, t_txt, Vector2i(int(W) - 28, 8), TEAL, BORDER_INK)

	## Shrinking turquoise countdown bar
	var ratio: float = clampf(_time_left / _duration, 0.0, 1.0)
	draw_rect(Rect2(10, 20, W - 20, 3), BORDER_INK)
	draw_rect(Rect2(10, 20, (W - 20) * ratio, 3), TEAL)

	## Peer status gems (P1..P4)
	var eligible: Array = _payload.get("eligible", []) as Array
	var responses: Dictionary = _payload.get("responses", {}) as Dictionary
	var names: Dictionary = _payload.get("names", {}) as Dictionary
	var gx: float = 12.0
	for i: int in eligible.size():
		var pid: int = int(eligible[i])
		var ok: bool = bool(responses.get(pid, false))
		var pcol: Color = MultiplayerHud.PLAYER_TONES[i % MultiplayerHud.PLAYER_TONES.size()]
		draw_rect(Rect2(gx, 30, 8, 8), BORDER_INK)
		draw_rect(Rect2(gx + 1, 31, 6, 6), pcol if ok else Color(pcol, 0.3))
		var short_name: String = String(names.get(pid, "P%d" % (i + 1))).left(8).to_upper()
		var mark: String = " OK" if ok else " ..."
		PixelText.draw(self, short_name + mark, Vector2i(int(gx) + 11, 31), TEXT_LIGHT if ok else MUTED, BORDER_INK)
		gx += 80.0

	## Personal resonance checkbox
	var charges: int = _player.dungeons.charges() if (_player != null and _player.dungeons != null) else 0
	_res_rect = Rect2(10, 46, W - 20, 14)
	var box_col: Color = TEAL if (_use_res and charges > 0) else MUTED
	draw_rect(Rect2(10, 48, 10, 10), BORDER_INK)
	draw_rect(Rect2(11, 49, 8, 8), Color("24344c") if _hover_btn == "res" else BG_DARK)
	if _use_res and charges > 0:
		draw_rect(Rect2(13, 51, 4, 4), TEAL)
	var res_lbl: String = "RESONANZ EINLÖSEN (%d/4)" % charges if charges > 0 else "KEINE RESONANZ (0/4 · BASISBEUTE)"
	PixelText.draw(self, res_lbl, Vector2i(24, 50), box_col, BORDER_INK)

	## Accept / Decline buttons
	_accept_rect = Rect2(10, 66, 154, 18)
	_decline_rect = Rect2(176, 66, 154, 18)
	var acc_bg: Color = Color("1c4a4e") if not _responded else Color("1c2e38")
	if _hover_btn == "accept" and not _responded:
		acc_bg = Color("286c70")
	draw_rect(_accept_rect, BORDER_INK)
	draw_rect(_accept_rect.grow(-1), acc_bg)
	PixelText.draw(self, "BEREIT — WARTE..." if _responded else "ANNEHMEN", Vector2i(int(_accept_rect.position.x) + (34 if _responded else 52), int(_accept_rect.position.y) + 6), TEAL if not _responded else MUTED, BORDER_INK)

	var dec_bg: Color = Color("4a1c2a") if _hover_btn == "decline" else Color("301520")
	draw_rect(_decline_rect, BORDER_INK)
	draw_rect(_decline_rect.grow(-1), dec_bg)
	PixelText.draw(self, "ABLEHNEN", Vector2i(int(_decline_rect.position.x) + 52, int(_decline_rect.position.y) + 6), DANGER, BORDER_INK)
