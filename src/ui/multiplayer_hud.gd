class_name MultiplayerHud
extends Control
## Compact in-game multiplayer badge in the bottom-left corner of the HUD.
## Shows the room Code, LAN IP (click to copy invite or cycle adapters), and an expandable
## live Player List with colored spore gems matching `MapWindow.PLAYER_TONES`.
## Only visible during active ENet multiplayer sessions.

const PLAYER_TONES: Array[Color] = [Color("b9f3ee"), Color("ffd98a"), Color("ff7fd8"), Color("a6e68f")]
const PANEL_W: float = 112.0
const COLLAPSED_H: float = 42.0
const PLAYER_ROW_H: float = 11.0
const ICONS_PATH: String = "res://assets/ui/menu_icons.png"

var _expanded: bool = false ## the player list lives in the CompanionVine now; this stays the room badge (click to unfold)
var _ip_index: int = 0
var _toast_text: String = ""
var _toast_timer: float = 0.0
var _toast_color: Color = Color("7fe3da")
var _hover_zone: String = ""
var _time: float = 0.0
var _icons: Texture2D = null
var _code_rect: Rect2 = Rect2()
var _ip_rect: Rect2 = Rect2()
var _toggle_rect: Rect2 = Rect2()
var _panel_rect: Rect2 = Rect2()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 6.0
	offset_right = 6.0 + PANEL_W
	offset_bottom = -6.0
	offset_top = -6.0 - 110.0
	if ResourceLoader.exists(ICONS_PATH):
		_icons = load(ICONS_PATH) as Texture2D
	NetworkManager.session_changed.connect(_on_session_changed)
	NetworkManager.peer_joined.connect(_on_peer_joined)
	NetworkManager.peer_left.connect(_on_peer_left)
	_sync_visibility()


func _on_session_changed() -> void:
	_sync_visibility()
	queue_redraw()


func _on_peer_joined(id: int) -> void:
	var pname: String = NetworkManager.player_name_for(id)
	_show_toast("%s BEIGETRETEN" % pname, Color("a6e68f"))
	queue_redraw()


func _on_peer_left(id: int) -> void:
	var pname: String = NetworkManager.player_name_for(id)
	_show_toast("%s GEGANGEN" % pname, Color("ffb4a8"))
	queue_redraw()


func _sync_visibility() -> void:
	var has_peers: bool = not multiplayer.get_peers().is_empty()
	visible = NetworkManager.is_multiplayer_session() and (NetworkManager.transport_mode != "relay" or has_peers or NetworkManager.explicit_coop_hud)


func _show_toast(msg: String, color: Color = Color("7fe3da")) -> void:
	_toast_text = msg
	_toast_color = color
	_toast_timer = 2.6


func _process(delta: float) -> void:
	_sync_visibility()
	if not visible:
		return
	_time += delta
	if _toast_timer > 0.0:
		_toast_timer = maxf(_toast_timer - delta, 0.0)
	queue_redraw()


func _has_point(point: Vector2) -> bool:
	return visible and modulate.a > 0.05 and _panel_rect.has_point(point)


func _current_ip() -> String:
	var ips: PackedStringArray = NetworkManager.local_ips()
	if ips.is_empty():
		return "127.0.0.1"
	_ip_index = posmod(_ip_index, ips.size())
	return ips[_ip_index]


func _copy_code() -> void:
	var code: String = NetworkManager.active_room_code
	var text: String = code if not code.is_empty() else ("%s:%d" % [_current_ip(), NetworkManager.active_port])
	DisplayServer.clipboard_set(text)
	Sfx.ui(self, "ui_confirm", -4.0)
	_show_toast("CODE KOPIERT" if not code.is_empty() else "IP KOPIERT", Color("ffd98a"))


func _copy_invite() -> void:
	var ip_str: String = "%s:%d" % [_current_ip(), NetworkManager.active_port]
	var invite: String = ip_str if NetworkManager.active_room_code.is_empty() else ("%s %s" % [ip_str, NetworkManager.active_room_code])
	DisplayServer.clipboard_set(invite)
	Sfx.ui(self, "ui_confirm", -4.0)
	_show_toast("EINLADUNG KOPIERT", Color("7fe3da"))


func _gui_input(event: InputEvent) -> void:
	if not visible or modulate.a <= 0.05:
		return
	if event is InputEventMouseMotion:
		var pos: Vector2 = (event as InputEventMouseMotion).position
		var next_zone: String = ""
		if _code_rect.has_point(pos):
			next_zone = "code"
		elif _ip_rect.has_point(pos):
			next_zone = "ip"
		elif _toggle_rect.has_point(pos):
			next_zone = "toggle"
		if next_zone != _hover_zone:
			_hover_zone = next_zone
			queue_redraw()
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and _panel_rect.has_point(mb.position):
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if _code_rect.has_point(mb.position):
					_copy_code()
				elif _ip_rect.has_point(mb.position) and NetworkManager.transport_mode != "relay":
					_copy_invite()
				elif _toggle_rect.has_point(mb.position):
					_expanded = not _expanded
					Sfx.ui(self, "ui_click", -4.0)
					queue_redraw()
				else:
					_expanded = not _expanded
					queue_redraw()
				accept_event()
			elif mb.button_index == MOUSE_BUTTON_RIGHT and _ip_rect.has_point(mb.position) and NetworkManager.transport_mode != "relay":
				var ips: PackedStringArray = NetworkManager.local_ips()
				if ips.size() > 1:
					_ip_index = posmod(_ip_index + 1, ips.size())
					_show_toast("IP GEWECHSELT", Color("b9f3ee"))
					queue_redraw()
				accept_event()


func _draw() -> void:
	if not visible:
		return
	var crew: Array[Dictionary] = NetworkManager.roster()
	var roster_h: float = (float(crew.size()) * PLAYER_ROW_H + 5.0) if (_expanded and not crew.is_empty()) else 0.0
	var total_h: float = COLLAPSED_H + roster_h
	_panel_rect = Rect2(0.0, size.y - total_h, PANEL_W, total_h)
	var px: float = _panel_rect.position.x
	var py: float = _panel_rect.position.y

	# Toast banner above panel
	if _toast_timer > 0.0 and not _toast_text.is_empty():
		var ta: float = clampf(_toast_timer / 0.5, 0.0, 1.0)
		var tw: float = float(PixelText.width(_toast_text) + 10)
		var tr: Rect2 = Rect2(px, py - 14.0, tw, 12.0)
		draw_rect(tr, Color(VineStyle.OUTLINE, 0.92 * ta))
		draw_rect(tr.grow(-1.0), Color("1e1a36", 0.94 * ta))
		draw_rect(Rect2(tr.position.x + 1.0, tr.position.y + 1.0, tr.size.x - 2.0, 1.0), Color(_toast_color, 0.5 * ta))
		PixelText.draw(self, _toast_text, Vector2i(int(tr.position.x) + 5, int(tr.position.y) + 2), Color(_toast_color, ta), Color(VineStyle.OUTLINE, ta))

	# Panel body (compact nocturnal slate with subtle vine outline & top accent)
	draw_rect(_panel_rect, Color(VineStyle.OUTLINE, 0.92))
	draw_rect(_panel_rect.grow(-1.0), Color("19152c", 0.88))
	draw_rect(Rect2(px + 2.0, py + 2.0, PANEL_W - 4.0, 1.0), Color("4a4180", 0.55))

	var y: float = py + 4.0

	# Header / Roster toggle + world count
	_toggle_rect = Rect2(px + 2.0, y - 1.0, PANEL_W - 4.0, 11.0)
	var online_col: Color = Color("7fe3da")
	draw_rect(Rect2(px + 5.0, y + 3.0, 3.0, 3.0), online_col)
	var pulse: float = 0.5 + 0.5 * sin(_time * 3.0)
	VineStyle.glow(self, Vector2(px + 6.5, y + 4.5), 5.0, online_col, 0.25 + 0.15 * pulse)
	var title: String = "KOOP %d/%d" % [maxi(crew.size(), 1), NetworkManager.active_max_players]
	PixelText.draw(self, title, Vector2i(int(px) + 11, int(y) + 1), Color("e8e4f4"), Color(VineStyle.OUTLINE))
	if not multiplayer.is_server() and NetworkManager.last_ping_ms > 0:
		var ping_str: String = "%dMS" % mini(NetworkManager.last_ping_ms, 999)
		var ping_col: Color = Color("a6e68f") if NetworkManager.last_ping_ms < 90 else (Color("ffd98a") if NetworkManager.last_ping_ms < 180 else Color("ff7a7a"))
		PixelText.draw(self, ping_str, Vector2i(int(px + PANEL_W - 14.0 - PixelText.width(ping_str)), int(y) + 1), ping_col, Color(VineStyle.OUTLINE))
	var toggle_char: String = "-" if _expanded else "+"
	var tog_col: Color = Color("ffd98a") if _hover_zone == "toggle" else Color("8a84ad")
	PixelText.draw(self, toggle_char, Vector2i(int(px + PANEL_W - 9.0), int(y) + 1), tog_col, Color(VineStyle.OUTLINE))
	y += 11.0

	# Room Code row (click copies code)
	_code_rect = Rect2(px + 2.0, y, PANEL_W - 4.0, 12.0)
	var code_bg: Color = Color("2a2548") if _hover_zone == "code" else Color("211c3a")
	draw_rect(_code_rect, Color(code_bg, 0.92))
	_draw_icon(6, Vector2(px + 4.0, y), 10)
	var code_val: String = NetworkManager.active_room_code if not NetworkManager.active_room_code.is_empty() else "OFFEN"
	var code_col: Color = Color("ffd98a") if not NetworkManager.active_room_code.is_empty() else Color("8a84ad")
	PixelText.draw(self, "CODE:", Vector2i(int(px) + 16, int(y) + 2), Color("8a84ad"), Color(VineStyle.OUTLINE))
	PixelText.draw(self, code_val, Vector2i(int(px) + 39, int(y) + 2), code_col, Color(VineStyle.OUTLINE))
	_draw_icon(7, Vector2(px + PANEL_W - 14.0, y + 1.0), 10, 0.95 if _hover_zone == "code" else 0.65)
	y += 13.0

	# IP:Port row (LAN/ENet) or Join-Mode row (Nakama Relay)
	_ip_rect = Rect2(px + 2.0, y, PANEL_W - 4.0, 11.0)
	if NetworkManager.transport_mode == "relay":
		var jm: String = NetworkManager.active_join_mode
		var jm_disp: String = "PRIVAT" if jm == "private" else ("OFFEN" if jm == "open" else "ANFRAGE")
		var jm_col: Color = Color("ffb4a8") if jm == "private" else (Color("a6e68f") if jm == "open" else Color("7fe3da"))
		PixelText.draw(self, "MODUS:", Vector2i(int(px) + 5, int(y) + 2), Color("8a84ad"), Color(VineStyle.OUTLINE))
		PixelText.draw(self, jm_disp, Vector2i(int(px) + 39, int(y) + 2), jm_col, Color(VineStyle.OUTLINE))
	else:
		if _hover_zone == "ip":
			draw_rect(_ip_rect, Color("2a2548", 0.85))
		var ip_disp: String = _current_ip()
		var full_ip: String = ip_disp if NetworkManager.active_port == NetworkManager.DEFAULT_PORT else ("%s:%d" % [ip_disp, NetworkManager.active_port])
		if PixelText.width(full_ip) > int(PANEL_W - 20.0):
			full_ip = ip_disp
		PixelText.draw(self, "IP:", Vector2i(int(px) + 5, int(y) + 2), Color("8a84ad"), Color(VineStyle.OUTLINE))
		PixelText.draw(self, full_ip, Vector2i(int(px) + 18, int(y) + 2), Color("b9f3ee") if _hover_zone == "ip" else Color("c8c3df"), Color(VineStyle.OUTLINE))
	y += 12.0

	# Player List (when expanded)
	if _expanded and not crew.is_empty():
		draw_rect(Rect2(px + 5.0, y + 1.0, PANEL_W - 10.0, 1.0), Color("4a4180", 0.45))
		y += 4.0
		for entry: Dictionary in crew:
			var slot: int = clampi(int(entry.get("slot", 0)), 0, PLAYER_TONES.size() - 1)
			var pcol: Color = PLAYER_TONES[slot]
			var is_host: bool = bool(entry.get("is_host", false))
			var is_me: bool = int(entry.get("id", 0)) == multiplayer.get_unique_id()
			var pname: String = String(entry.get("name", "SPIELER"))
			if pname.length() > 13:
				pname = pname.substr(0, 13)
			if is_host:
				_draw_icon(8, Vector2(px + 4.0, y - 1.0), 10)
			else:
				_draw_icon(9, Vector2(px + 4.0, y - 1.0), 10, 1.0, pcol)
			PixelText.draw(self, pname, Vector2i(int(px) + 16, int(y) + 1), pcol if is_me else Color("e8e4f4"), Color(VineStyle.OUTLINE))
			if is_host:
				var tag: String = "HOST"
				PixelText.draw(self, tag, Vector2i(int(px + PANEL_W - 5.0 - PixelText.width(tag)), int(y) + 1), Color("ffd98a", 0.8), Color(VineStyle.OUTLINE))
			y += PLAYER_ROW_H


func _draw_icon(frame: int, pos: Vector2, draw_size: int = 12, alpha: float = 1.0, tint: Color = Color.WHITE) -> void:
	if _icons == null:
		draw_rect(Rect2(pos + Vector2(2, 2), Vector2(6, 6)), Color(tint, alpha))
		return
	var src: Rect2 = Rect2(float(frame * 12), 0.0, 12.0, 12.0)
	draw_texture_rect_region(_icons, Rect2(pos, Vector2(float(draw_size), float(draw_size))), src, Color(tint, alpha))
