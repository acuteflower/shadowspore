extends CanvasLayer
## Blocking fullscreen overlay for launcher/license gate errors and the 60s reconnect grace pause.

const OVERLAY_LAYER: int = 124 ## Above game transitions (120) and below GameCursor (128)

var _panel: _GatePanel = null


func _ready() -> void:
	layer = OVERLAY_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = _GatePanel.new()
	add_child(_panel)
	GameGuard.access_blocked.connect(_on_guard_changed)
	GameGuard.reconnect_state_changed.connect(_on_reconnect_changed)
	GameGuard.access_restored.connect(_on_guard_restored)
	if get_viewport() != null and not get_viewport().size_changed.is_connected(_on_viewport_resized):
		get_viewport().size_changed.connect(_on_viewport_resized)
	_sync_visibility()


func _on_viewport_resized() -> void:
	if _panel != null and visible:
		_panel.queue_redraw()


func _on_guard_changed(_title: String, _reason: String, _can_retry: bool) -> void:
	_sync_visibility()


func _on_reconnect_changed(_reconnecting: bool, _seconds_left: float, _msg: String) -> void:
	_sync_visibility()


func _on_guard_restored() -> void:
	_sync_visibility()


func _sync_visibility() -> void:
	var show_overlay: bool = GameGuard.locked or GameGuard.reconnecting
	visible = show_overlay
	if _panel != null:
		_panel.visible = show_overlay
		if show_overlay:
			_panel.queue_redraw()
		else:
			_panel.clear_hover()


class _GatePanel extends Control:
	var _retry_rect: Rect2 = Rect2()
	var _quit_rect: Rect2 = Rect2()
	var _hover: String = ""
	var _focus: String = "retry"
	var _retrying: bool = false

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func _exit_tree() -> void:
		clear_hover()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
			clear_hover()
		elif what == NOTIFICATION_MOUSE_EXIT:
			clear_hover()

	func clear_hover() -> void:
		GameCursor.set_hint(self, &"")
		if not _hover.is_empty():
			_hover = ""
			queue_redraw()

	func _draw() -> void:
		var vp: Vector2 = get_viewport_rect().size
		if vp.x <= 0.0 or vp.y <= 0.0:
			vp = Vector2(640.0, 360.0)
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0.04, 0.03, 0.08, 0.88))

		var box_w: float = 340.0
		var box_h: float = 132.0
		var box: Rect2 = Rect2((vp.x - box_w) * 0.5, (vp.y - box_h) * 0.5, box_w, box_h)
		draw_rect(box, Color("161226"))
		draw_rect(Rect2(box.position, Vector2(box.size.x, 1.0)), Color("7fe3da") if GameGuard.reconnecting else Color("ffb4a8"))
		draw_rect(Rect2(Vector2(box.position.x, box.end.y - 1.0), Vector2(box.size.x, 1.0)), Color("4a4180"))
		draw_rect(Rect2(box.position, Vector2(1.0, box.size.y)), Color("4a4180"))
		draw_rect(Rect2(Vector2(box.end.x - 1.0, box.position.y), Vector2(1.0, box.size.y)), Color("4a4180"))

		var title: String = "VERBINDUNG UNTERBROCHEN" if GameGuard.reconnecting else GameGuard.lock_title.to_upper()
		if title.is_empty():
			title = "ZUGANG GESPERRT"
		var title_col: Color = Color("ffd98a") if GameGuard.reconnecting else Color("ffb4a8")
		var tx: int = int(box.position.x + (box.size.x - float(PixelText.width(title))) * 0.5)
		PixelText.draw(self, title, Vector2i(tx, int(box.position.y + 14.0)), title_col, Color("120c1c"))

		var body: String = ""
		if GameGuard.reconnecting:
			body = "VERSUCHE WIEDERVERBINDUNG ZUM SERVER... (%ds)" % ceili(GameGuard.grace_remaining)
		elif _retrying:
			body = "PRUEFE VERBINDUNG ZUM SERVER..."
		else:
			body = GameGuard.lock_reason
		var lines: PackedStringArray = _wrap_text(body.to_upper(), int(box.size.x - 32.0))
		var ly: float = box.position.y + 34.0
		for ln: String in lines:
			var lx: int = int(box.position.x + (box.size.x - float(PixelText.width(ln))) * 0.5)
			PixelText.draw(self, ln, Vector2i(lx, int(ly)), Color("f3eef8"), Color("120c1c"))
			ly += 11.0
			if ly > box.end.y - 38.0:
				break

		_retry_rect = Rect2()
		_quit_rect = Rect2()
		if GameGuard.reconnecting:
			var sub: String = "SPIEL PAUSIERT AUTOMATISCH BIS ZUR RUECKKEHR"
			var sx: int = int(box.position.x + (box.size.x - float(PixelText.width(sub))) * 0.5)
			PixelText.draw(self, sub, Vector2i(sx, int(box.end.y - 24.0)), Color("7fe3da"), Color("120c1c"))
			return

		var btn_y: float = box.end.y - 28.0
		if GameGuard.lock_can_retry:
			_retry_rect = Rect2(box.position.x + 28.0, btn_y, 132.0, 18.0)
			_quit_rect = Rect2(box.end.x - 160.0, btn_y, 132.0, 18.0)
			var retry_label: String = "PRUEFE..." if _retrying else "ERNEUT PRUEFEN"
			var r_active: bool = _retrying or _hover == "retry" or (_hover.is_empty() and _focus == "retry")
			var r_tone: Color = Color("7fe3da") if r_active else Color("4a4180")
			VineStyle.plate(self, _retry_rect, retry_label, r_tone, Color("f3eef8"), 1.0, 0.25)
		else:
			_quit_rect = Rect2(box.position.x + (box.size.x - 140.0) * 0.5, btn_y, 140.0, 18.0)
		var q_active: bool = _hover == "quit" or (_hover.is_empty() and (_focus == "quit" or not GameGuard.lock_can_retry))
		var q_tone: Color = Color("ffb4a8") if q_active else Color("6e3d49")
		VineStyle.plate(self, _quit_rect, "SPIEL BEENDEN", q_tone, Color("f3eef8"), 1.0, 0.25)

	func _wrap_text(text: String, max_w: int) -> PackedStringArray:
		var out: PackedStringArray = []
		var cur: String = ""
		for word: String in text.split(" ", false):
			var candidate: String = word if cur.is_empty() else (cur + " " + word)
			if PixelText.width(candidate) <= max_w:
				cur = candidate
			else:
				if not cur.is_empty():
					out.append(cur)
				cur = word
		if not cur.is_empty():
			out.append(cur)
		return out

	func _hit_at(pos: Vector2) -> String:
		if not _retrying and _retry_rect.size.x > 0.0 and _retry_rect.has_point(pos):
			return "retry"
		if _quit_rect.size.x > 0.0 and _quit_rect.has_point(pos):
			return "quit"
		return ""

	func _input(event: InputEvent) -> void:
		if not visible or not is_visible_in_tree():
			return
		var vp_ctrl: Viewport = get_viewport()
		if event is InputEventMouseMotion:
			var local_motion: InputEventMouseMotion = make_input_local(event) as InputEventMouseMotion
			var pos: Vector2 = local_motion.position if local_motion != null else (event as InputEventMouseMotion).position
			var next_h: String = _hit_at(pos)
			if not next_h.is_empty():
				_focus = next_h
			GameCursor.set_hint(self, &"click" if not next_h.is_empty() else &"")
			if next_h != _hover:
				_hover = next_h
				queue_redraw()
			if vp_ctrl != null:
				vp_ctrl.set_input_as_handled()
		elif event is InputEventMouseButton:
			var local_btn: InputEventMouseButton = make_input_local(event) as InputEventMouseButton
			var mb: InputEventMouseButton = local_btn if local_btn != null else (event as InputEventMouseButton)
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
				var hit: String = _hit_at(mb.position)
				if hit == "retry":
					_on_retry_pressed()
				elif hit == "quit":
					get_tree().quit()
			if vp_ctrl != null:
				vp_ctrl.set_input_as_handled()
		elif event is InputEventKey:
			if GameGuard.lock_can_retry and (event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"ui_right") or (event as InputEventKey).keycode == KEY_TAB and (event as InputEventKey).pressed):
				_focus = "quit" if _focus == "retry" else "retry"
				_hover = ""
				queue_redraw()
			elif event.is_action_pressed(&"ui_accept") and not GameGuard.reconnecting:
				if GameGuard.lock_can_retry and _focus == "retry":
					_on_retry_pressed()
				else:
					get_tree().quit()
			elif event.is_action_pressed(&"ui_cancel") and not GameGuard.reconnecting:
				get_tree().quit()
			if vp_ctrl != null:
				vp_ctrl.set_input_as_handled()

	func _on_retry_pressed() -> void:
		if GameGuard.reconnecting or _retrying:
			return
		_retrying = true
		GameCursor.set_hint(self, &"")
		queue_redraw()
		await GameGuard.verify_startup_async()
		_retrying = false
		if visible:
			queue_redraw()
