class_name PauseSocialSidebar
extends Control
## Valorant-style collapsible right social & profile drawer for PauseMenu (ESC).
## Morphs cleanly between a slim 28px docked rail (like the Launcher's left rail)
## and the full 186px Profile + Friends drawer using the muted "Nachtlichtung" palette.

signal request_host_relay()
signal request_join_match(info: Dictionary)

const COLLAPSED_W: float = 28.0
const EXPANDED_W: float = 186.0
const SLIDE_SECONDS: float = 0.22
const PAD_X: float = 8.0
const SCROLL_STEP: float = 24.0
const ARM_REMOVE_TIMEOUT: float = 3.0

const AVATAR_LICHTUNG: Texture2D = preload("res://assets/ui/avatars/avatar_lichtung.png")
const AVATAR_LEERE: Texture2D = preload("res://assets/ui/avatars/avatar_leere.png")

## Calm, low-glare "Nachtlichtung" palette matching launcher/src/styles.css
const COL_OUTLINE: Color = Color("120a22")
const COL_SEAM: Color = Color("2b1f4a")
const COL_EDGE_MID: Color = Color("3b2a6e")
const COL_EDGE_LIT: Color = Color("5a4696")
const COL_BARK: Color = Color("161021")
const COL_BARK_ALT: Color = Color("1e162e")
const COL_CARD: Color = Color("110c1c")
const COL_CARD_HOVER: Color = Color("1f1733")
const COL_WELL: Color = Color("0c0817")
const COL_TEXT: Color = Color("ece4ff")
const COL_MUTED: Color = Color("a99cc6")
const COL_FAINT: Color = Color("6f6390")
const COL_TEAL: Color = Color("4fe3c1")
const COL_TEAL_BTN: Color = Color("216c5d")
const COL_TEAL_TOP: Color = Color("4ba893")
const COL_TEAL_DEEP: Color = Color("123e35")
const COL_TEAL_TXT: Color = Color("e4fbf4")
const COL_GOLD: Color = Color("e0b565")
const COL_GOLD_DIM: Color = Color("7a5326")
const COL_GOLD_BG: Color = Color("241a12")
const COL_LILAC: Color = Color("bfa8f5")
const COL_RED: Color = Color("d97585")
const COL_RED_RIM: Color = Color("4a1d33")
const COL_RED_BG: Color = Color("6e2336")


class _FeedCanvas extends Control:
	var owner_sidebar: Control = null

	func _draw() -> void:
		if owner_sidebar != null:
			owner_sidebar.call("_draw_feed_content", self)


var _feed_viewport: _FeedCanvas = null
var top_inset: float = 0.0 ## vertical offset below GameMenu Canopy Rail when embedded
var bottom_inset: float = 0.0 ## vertical clearance above GameMenu Footer Rail when embedded
var codex_style: bool = false ## 1:1 tiled MenuChrome obsidian surface when docked in SystemTab
var _expanded: bool = true
var _slide_t: float = 0.0
var _fade: float = 0.0
var _time: float = 0.0
var _scroll_y: float = 0.0
var _content_h: float = 0.0
var _typing: bool = false
var _add_text: String = ""
var _hover_id: String = ""
var _arm_remove_id: String = ""
var _arm_remove_t: float = 0.0
var _busy: bool = false
var _toast: String = ""
var _toast_err: bool = false
var _toast_t: float = 0.0
var _last_refresh_msec: int = 0
var _fixed_hits: Array[Dictionary] = []
var _feed_hits: Array[Dictionary] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	process_mode = Node.PROCESS_MODE_ALWAYS
	_feed_viewport = _FeedCanvas.new()
	_feed_viewport.name = "FeedViewport"
	_feed_viewport.owner_sidebar = self
	_feed_viewport.clip_contents = true
	_feed_viewport.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed_viewport.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_feed_viewport)


func on_pause_opened(initial_expand_anim: bool = true) -> void:
	_typing = false
	_hover_id = ""
	_arm_remove_id = ""
	_arm_remove_t = 0.0
	if initial_expand_anim:
		_slide_t = 0.0
	else:
		_slide_t = 1.0 if _expanded else 0.0
	mark_dirty()


func on_pause_closing() -> void:
	_typing = false
	_hover_id = ""
	GameCursor.set_hint(self, &"")


func set_expanded(expand: bool, immediate: bool = false) -> void:
	_expanded = expand
	if not _expanded:
		_typing = false
	if immediate:
		_slide_t = 1.0 if _expanded else 0.0
	mark_dirty()


func toggle_expanded() -> void:
	Sfx.ui(self, "ui_click", -3.0)
	set_expanded(not _expanded, false)


func is_expanded() -> bool:
	return _expanded


func is_typing() -> bool:
	return _typing and visible and _fade > 0.05 and _expanded and _slide_t > 0.25


func cancel_typing() -> void:
	if _typing:
		_typing = false
		mark_dirty()


func mark_dirty() -> void:
	queue_redraw()
	if _feed_viewport != null:
		_feed_viewport.queue_redraw()


func occupied_width() -> float:
	if not visible or _fade <= 0.01:
		return 0.0
	return _current_width()


func advance(delta: float, fade: float, suppress: bool) -> void:
	_time += delta
	_fade = 0.0 if suppress else fade
	visible = _fade > 0.01
	if not visible:
		_hover_id = ""
		return
	var target_slide: float = 1.0 if _expanded else 0.0
	_slide_t = move_toward(_slide_t, target_slide, delta / SLIDE_SECONDS)
	if _toast_t > 0.0:
		_toast_t = maxf(_toast_t - delta, 0.0)
	if _arm_remove_t > 0.0:
		_arm_remove_t = maxf(_arm_remove_t - delta, 0.0)
		if _arm_remove_t <= 0.0:
			_arm_remove_id = ""
	_sync_feed_viewport_rect()
	queue_redraw()
	if _feed_viewport != null:
		_feed_viewport.queue_redraw()


func handle_key_input(key: InputEventKey) -> void:
	if not is_typing():
		return
	match key.physical_keycode:
		KEY_ESCAPE:
			_typing = false
			mark_dirty()
		KEY_ENTER, KEY_KP_ENTER:
			_submit_add_friend()
		KEY_BACKSPACE:
			if not _add_text.is_empty():
				_add_text = _add_text.substr(0, _add_text.length() - 1)
				mark_dirty()
		_:
			var incoming: String = ""
			if key.ctrl_pressed and key.physical_keycode == KEY_V:
				incoming = DisplayServer.clipboard_get()
			elif key.unicode > 0:
				incoming = char(key.unicode)
			for ch: String in incoming:
				var up: String = ch.to_upper()
				var allowed: bool = (up >= "A" and up <= "Z") or ch in "ÄÖÜäöüß0123456789-_#."
				if allowed and _add_text.length() < 28:
					_add_text += ch
			mark_dirty()


# ---------- geometry helpers ----------

func _view_size() -> Vector2:
	if size.x > 1.0 and size.y > 1.0:
		return size
	var p: Control = get_parent() as Control
	return p.size if p != null and p.size.x > 1.0 else Vector2(640.0, 360.0)


func _eased_slide() -> float:
	var t: float = clampf(_slide_t, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)


func _current_width() -> float:
	return lerpf(COLLAPSED_W, EXPANDED_W, _eased_slide())


func _drawer_x() -> float:
	return roundf(_view_size().x - _current_width())


func _feed_top_y() -> float:
	var base: float = (113.0 if CloudSession.is_logged_in() else 90.0) + top_inset
	return base + (14.0 if _toast_t > 0.0 else 0.0)


func _feed_clip_rect() -> Rect2:
	var vs: Vector2 = _view_size()
	var dx: float = _drawer_x()
	var top: float = _feed_top_y()
	var bottom: float = vs.y - bottom_inset - 18.0
	return Rect2(dx + 4.0, top, EXPANDED_W - 8.0, maxf(bottom - top, 24.0))


func _sync_feed_viewport_rect() -> void:
	if _feed_viewport == null:
		return
	var r: Rect2 = _feed_clip_rect()
	_feed_viewport.position = r.position
	_feed_viewport.size = r.size
	_feed_viewport.visible = _eased_slide() > 0.45


func _has_point(point: Vector2) -> bool:
	if not visible or _fade <= 0.02:
		return false
	return point.x >= _drawer_x()


# ---------- mouse input ----------

func _gui_input(event: InputEvent) -> void:
	if not visible or _fade <= 0.02:
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	var button: InputEventMouseButton = event as InputEventMouseButton
	if motion != null:
		_update_hover(motion.position)
		accept_event()
		return
	if button != null and button.pressed:
		if not _has_point(button.position):
			return
		if button.button_index == MOUSE_BUTTON_WHEEL_UP or button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _eased_slide() > 0.55 and _feed_viewport != null and _feed_clip_rect().has_point(button.position):
				var max_s: float = maxf(_content_h - _feed_clip_rect().size.y, 0.0)
				var delta_s: float = -SCROLL_STEP if button.button_index == MOUSE_BUTTON_WHEEL_UP else SCROLL_STEP
				_scroll_y = clampf(_scroll_y + delta_s, 0.0, max_s)
				mark_dirty()
			accept_event()
			return
		if button.button_index == MOUSE_BUTTON_LEFT:
			_handle_click(button.position)
			accept_event()


func _update_hover(point: Vector2) -> void:
	var next_hover: String = ""
	for entry: Dictionary in _fixed_hits:
		if (entry["rect"] as Rect2).has_point(point):
			next_hover = String(entry["id"])
	var feed_rect: Rect2 = _feed_clip_rect()
	if next_hover.is_empty() and _eased_slide() > 0.55 and feed_rect.has_point(point):
		var local: Vector2 = point - feed_rect.position
		for entry: Dictionary in _feed_hits:
			if (entry["rect"] as Rect2).has_point(local):
				next_hover = String(entry["id"])
	if next_hover != _hover_id:
		_hover_id = next_hover
		mark_dirty()
	GameCursor.set_hint(self, &"click" if not next_hover.is_empty() else &"")


func _handle_click(point: Vector2) -> void:
	for i: int in range(_fixed_hits.size() - 1, -1, -1):
		var entry: Dictionary = _fixed_hits[i]
		if (entry["rect"] as Rect2).has_point(point):
			var act: String = String(entry["action"])
			if act != "focus_add":
				_typing = false
			_dispatch_action(act, String(entry.get("arg", "")))
			return
	_typing = false
	var feed_rect: Rect2 = _feed_clip_rect()
	if _eased_slide() > 0.55 and feed_rect.has_point(point):
		var local: Vector2 = point - feed_rect.position
		for i: int in range(_feed_hits.size() - 1, -1, -1):
			var entry: Dictionary = _feed_hits[i]
			if (entry["rect"] as Rect2).has_point(local):
				_dispatch_action(String(entry["action"]), String(entry.get("arg", "")))
				return
	mark_dirty()


# ---------- actions ----------

func _show_toast(msg: String, is_err: bool = false, duration: float = 2.6) -> void:
	_toast = msg.to_upper()
	_toast_err = is_err
	_toast_t = duration
	mark_dirty()


func _dispatch_action(action: String, arg: String) -> void:
	match action:
		"toggle_drawer":
			toggle_expanded()
		"open_chat":
			get_tree().call_group("game_chat", "open_chat")
		"friend_dm":
			for friend: Dictionary in CloudSession.friends_cache:
				if String(friend.get("user_id", "")) == arg:
					get_tree().call_group("game_chat", "open_friend", arg, String(friend.get("username", "Spieler")))
					break
		"refresh_social":
			_do_refresh_now()
		"copy_uid":
			if not CloudSession.uid.is_empty():
				DisplayServer.clipboard_set(CloudSession.uid)
				Sfx.ui(self, "ui_click", -3.0)
				_show_toast("UID #%s KOPIERT" % CloudSession.uid)
		"copy_room_code":
			var code: String = _active_room_code()
			if not code.is_empty():
				DisplayServer.clipboard_set(code)
				Sfx.ui(self, "ui_click", -3.0)
				_show_toast("CODE %s KOPIERT" % code)
		"cycle_join_mode":
			_do_cycle_join_mode()
		"host_relay":
			Sfx.ui(self, "ui_click", -2.0)
			request_host_relay.emit()
		"focus_add":
			_typing = true
			Sfx.ui(self, "ui_click", -4.0)
			mark_dirty()
		"submit_add":
			_submit_add_friend()
		"notif_join":
			_do_join_notif(arg)
		"notif_dismiss":
			_do_dismiss_notif(arg)
		"join_req_accept":
			_do_respond_join_req(arg, true)
		"join_req_decline":
			_do_respond_join_req(arg, false)
		"friend_accept":
			_do_accept_friend(arg)
		"friend_decline":
			_do_remove_friend(arg, "ANFRAGE ABGELEHNT")
		"friend_cancel":
			_do_remove_friend(arg, "ANFRAGE ZURÜCKGEZOGEN")
		"friend_join":
			_do_request_join_friend(arg)
		"friend_invite":
			_do_invite_friend(arg)
		"friend_remove":
			if _arm_remove_id != arg:
				_arm_remove_id = arg
				_arm_remove_t = ARM_REMOVE_TIMEOUT
				Sfx.ui(self, "ui_click", -4.0)
				mark_dirty()
			else:
				_arm_remove_id = ""
				_arm_remove_t = 0.0
				_do_remove_friend(arg, "FREUND ENTFERNT")


func _do_refresh_now() -> void:
	if not CloudSession.is_logged_in():
		_show_toast("NICHT EINGELOGGT", true, 2.0)
		return
	var now: int = Time.get_ticks_msec()
	if now - _last_refresh_msec < 1000:
		return
	_last_refresh_msec = now
	Sfx.ui(self, "ui_click", -3.0)
	_show_toast("AKTUALISIERE...", false, 1.4)
	CloudSession.fetch_my_profile()
	CloudSession.refresh_friends()
	CloudSession.fetch_notifications()


func _submit_add_friend() -> void:
	var query: String = _add_text.strip_edges()
	if query.begins_with("#"):
		query = query.substr(1).strip_edges()
	if query.is_empty():
		_show_toast("UID ODER NAME EINGEBEN", true, 2.2)
		return
	if _busy:
		return
	_busy = true
	Sfx.ui(self, "ui_click", -2.0)
	var res: Dictionary = await CloudSession.add_friend_by_uid(query)
	_busy = false
	if not is_inside_tree():
		return
	if bool(res.get("ok", false)):
		_add_text = ""
		_typing = false
		_show_toast("ANFRAGE GESENDET", false, 2.6)
		CloudSession.refresh_friends()
	else:
		_show_toast(String(res.get("error", "FEHLGESCHLAGEN")), true, 2.8)


func _do_cycle_join_mode() -> void:
	if _busy or not CloudSession.is_logged_in():
		return
	var cur: String = NetworkManager.active_join_mode if NetworkManager.is_multiplayer_session() else CloudSession.world_join_mode
	var nxt: String = "ask"
	if cur == "ask":
		nxt = "open"
	elif cur == "open":
		nxt = "private"
	_busy = true
	Sfx.ui(self, "ui_click", -2.0)
	var res: Dictionary = await CloudSession.set_world_join_mode(nxt)
	_busy = false
	if not is_inside_tree():
		return
	if bool(res.get("ok", false)):
		_show_toast("BEITRITT: %s" % _join_mode_short(nxt))
	else:
		_show_toast(String(res.get("error", "FEHLER")), true)


func _do_accept_friend(target_uid: String) -> void:
	if _busy:
		return
	_busy = true
	Sfx.ui(self, "ui_click", -2.0)
	var ok: bool = await CloudSession.accept_friend(target_uid)
	_busy = false
	if not is_inside_tree():
		return
	_show_toast("FREUND ANGENOMMEN" if ok else CloudSession.last_error, not ok)
	CloudSession.refresh_friends()


func _do_remove_friend(target_uid: String, ok_msg: String) -> void:
	if _busy:
		return
	_busy = true
	Sfx.ui(self, "ui_click", -2.0)
	var ok: bool = await CloudSession.remove_friend(target_uid)
	_busy = false
	if not is_inside_tree():
		return
	_show_toast(ok_msg if ok else CloudSession.last_error, not ok)
	CloudSession.refresh_friends()


func _do_invite_friend(target_uid: String) -> void:
	if _busy:
		return
	_busy = true
	Sfx.ui(self, "ui_click", -2.0)
	var res: Dictionary = await CloudSession.coop_invite_friend(target_uid)
	_busy = false
	if not is_inside_tree():
		return
	var ok: bool = bool(res.get("ok", false))
	_show_toast("EINLADUNG GESENDET" if ok else String(res.get("error", "FEHLER")), not ok)


func _do_request_join_friend(host_uid: String) -> void:
	if _busy:
		return
	_busy = true
	Sfx.ui(self, "ui_click", -2.0)
	var res: Dictionary = await CloudSession.coop_request_join(host_uid)
	_busy = false
	if not is_inside_tree():
		return
	if not bool(res.get("ok", false)):
		_show_toast(String(res.get("error", "BEITRITT FEHLGESCHLAGEN")), true)
		return
	if String(res.get("status", "")) == "requested":
		_show_toast("ANFRAGE AN %s" % String(res.get("host_name", "FREUND")))
		return
	var mid: String = String(res.get("match_id", ""))
	if not mid.is_empty():
		request_join_match.emit({
			"match_id": mid,
			"room_code": String(res.get("room_code", "")),
			"world_name": String(res.get("world_name", "KOOP-WELT")),
			"notif_id": "",
		})


func _do_join_notif(notif_id: String) -> void:
	for n: Dictionary in CloudSession.notifications:
		if String(n.get("id", "")) == notif_id:
			var c: Dictionary = n.get("content", {}) as Dictionary
			var mid: String = String(c.get("match_id", ""))
			if not mid.is_empty():
				Sfx.ui(self, "ui_click", -2.0)
				request_join_match.emit({
					"match_id": mid,
					"room_code": String(c.get("room_code", "")),
					"world_name": String(c.get("world_name", "KOOP-WELT")),
					"notif_id": notif_id,
				})
				return


func _do_dismiss_notif(notif_id: String) -> void:
	Sfx.ui(self, "ui_click", -3.0)
	CloudSession.delete_notification(notif_id)


func _do_respond_join_req(requester_user_id: String, accept: bool) -> void:
	if _busy:
		return
	_busy = true
	Sfx.ui(self, "ui_click", -2.0)
	var res: Dictionary = await CloudSession.coop_respond_join_request(requester_user_id, accept)
	_busy = false
	if not is_inside_tree():
		return
	var ok: bool = bool(res.get("ok", false))
	_show_toast(("ANFRAGE ANGENOMMEN" if accept else "ABGELEHNT") if ok else String(res.get("error", "FEHLER")), not ok)


# ---------- derived state ----------

func _pending_counts() -> Dictionary:
	var incoming: int = 0
	var online_friends: int = 0
	var total_friends: int = 0
	for fr: Dictionary in CloudSession.friends_cache:
		var st: int = int(fr.get("state", 0))
		if st == 2:
			incoming += 1
		elif st == 0:
			total_friends += 1
			if bool(fr.get("online", false)):
				online_friends += 1
	return {
		"pending": incoming + CloudSession.notifications.size(),
		"online": online_friends,
		"total": total_friends,
	}


func _active_room_code() -> String:
	if NetworkManager.is_multiplayer_session() and not NetworkManager.active_room_code.is_empty():
		return NetworkManager.active_room_code
	return String(CloudSession.active_lobby.get("room_code", ""))


func _can_invite_friends() -> bool:
	if not CloudSession.is_logged_in():
		return false
	if NetworkManager.is_multiplayer_session() and NetworkManager.transport_mode == "relay" and multiplayer.is_server():
		return true
	return not String(CloudSession.active_lobby.get("match_id", "")).is_empty()


func _sorted_accepted_friends() -> Array[Dictionary]:
	var accepted: Array[Dictionary] = []
	for fr: Dictionary in CloudSession.friends_cache:
		if int(fr.get("state", 0)) == 0:
			accepted.append(fr)
	accepted.sort_custom(func(f1: Dictionary, f2: Dictionary) -> bool:
		var s1: int = (2 if bool(f1.get("coop_active", false)) else (1 if bool(f1.get("online", false)) else 0))
		var s2: int = (2 if bool(f2.get("coop_active", false)) else (1 if bool(f2.get("online", false)) else 0))
		if s1 != s2:
			return s1 > s2
		return String(f1.get("display_name", f1.get("username", ""))).to_lower() < String(f2.get("display_name", f2.get("username", ""))).to_lower()
	)
	return accepted


# ---------- drawing: main docked rail / drawer ----------

func _draw() -> void:
	_fixed_hits.clear()
	if not visible or _fade <= 0.01:
		return
	var vs: Vector2 = _view_size()
	var dx: float = _drawer_x()
	var es: float = _eased_slide()
	var a: float = _fade
	var y_top: float = top_inset
	var y_h: float = maxf(vs.y - top_inset - bottom_inset, 40.0)
	# Subtle soft dark feather to the left of the rail seam (Launcher-like separation, never heavy)
	for step: int in 4:
		var sx: float = dx - float(step + 1) * 3.0
		var sa: float = (0.24 - float(step) * 0.055) * a
		draw_rect(Rect2(sx, y_top, 3.0, y_h), Color(0.02, 0.01, 0.05, sa))
	# Bark surface (#161021) or 1:1 tiled obsidian weave when hosted inside Feldcodex SystemTab
	if codex_style:
		MenuChrome.draw_tiled_region(self, Rect2(dx, y_top, vs.x - dx, y_h), MenuChrome.TILE_INSET, Color(1.0, 1.0, 1.0, 0.96 * a))
		draw_rect(Rect2(dx, y_top, 1.0, y_h), Color(MenuChrome.COL_OUTLINE, 0.95 * a))
		draw_rect(Rect2(dx + 1.0, y_top, 1.0, y_h), Color(MenuChrome.COL_GOLD, 0.32 * a))
	else:
		draw_rect(Rect2(dx, y_top, vs.x - dx, y_h), Color(COL_BARK, 0.94 * a))
		for py: int in range(int(y_top) + 2, int(y_top) + 20, 4):
			var start_x: int = int(dx) + (4 if (py / 4) % 2 == 0 else 2)
			for px: int in range(start_x, int(vs.x) - 2, 6):
				draw_rect(Rect2(px, py, 2, 2), Color(COL_BARK_ALT, 0.35 * a))
		draw_rect(Rect2(dx, y_top, 1.0, y_h), Color(COL_OUTLINE, 0.9 * a))
		draw_rect(Rect2(dx + 1.0, y_top, 1.0, y_h), Color(COL_SEAM, 0.85 * a))
	var counts: Dictionary = _pending_counts()
	if es < 0.35:
		_draw_collapsed_rail(dx, vs, counts, a * (1.0 - clampf(es / 0.35, 0.0, 1.0)))
	else:
		var exp_a: float = a * clampf((es - 0.35) / 0.65, 0.0, 1.0)
		_draw_expanded_contents(dx, vs, counts, exp_a)


func _draw_collapsed_rail(dx: float, vs: Vector2, counts: Dictionary, a: float) -> void:
	if a <= 0.02:
		return
	var cx: float = dx + COLLAPSED_W * 0.5
	var logged_in: bool = CloudSession.is_logged_in()
	var pending: int = int(counts["pending"])
	var rail_hov: bool = _hover_id == "toggle_drawer"
	var ty: float = top_inset
	# Whole top toggle pill + expandable rail strip acts cleanly as one calm dock
	var tog_r: Rect2 = Rect2(dx + 5.0, ty + 6.0, 18.0, 13.0)
	_draw_box(tog_r, COL_CARD_HOVER if rail_hov else COL_WELL, COL_EDGE_MID if rail_hov else COL_SEAM, a)
	PixelText.draw(self, "<", Vector2i(roundi(cx - 1.0), roundi(ty + 8.0)), Color(COL_TEXT if rail_hov else COL_MUTED, a))
	# Your mini 18x18 profile avatar anchored near top
	var av_r: Rect2 = Rect2(dx + 5.0, ty + 24.0, 18.0, 18.0)
	_draw_avatar_on(self, av_r, CloudSession.avatar_url if logged_in else "", _local_display_name(), logged_in, NetworkManager.is_multiplayer_session(), a, true)
	# Subtle notification indicator right beside top avatar if invites/requests wait
	if pending > 0:
		var badge: Rect2 = Rect2(dx + 16.0, ty + 21.0, 9.0, 9.0)
		draw_rect(badge, Color(COL_OUTLINE, a))
		draw_rect(badge.grow(-1.0), Color(COL_GOLD, a))
		var btxt: String = str(mini(pending, 9))
		PixelText.draw(self, btxt, Vector2i(roundi(badge.position.x + 3.0), roundi(badge.position.y + 1.0)), Color(COL_OUTLINE, a))
	draw_rect(Rect2(dx + 6.0, ty + 47.0, 16.0, 1.0), Color(COL_SEAM, 0.7 * a))
	# Stack up to 5 online friends' mini 16x16 tiles cleanly down the rail (Valorant dock feel!)
	if logged_in:
		var fy: float = ty + 53.0
		var shown: int = 0
		for fr: Dictionary in _sorted_accepted_friends():
			if shown >= 5 or not bool(fr.get("online", false)):
				continue
			var fr_name: String = String(fr.get("display_name", fr.get("username", "?")))
			var in_coop: bool = bool(fr.get("coop_active", false))
			var tile: Rect2 = Rect2(dx + 6.0, fy, 16.0, 16.0)
			_draw_avatar_on(self, tile, String(fr.get("avatar_url", "")), fr_name, true, in_coop, a, true)
			fy += 20.0
			shown += 1
	# Bottom online summary
	var cnt_str: String = "%d" % int(counts["online"]) if logged_in else "-"
	var cy_txt: int = roundi(vs.y - bottom_inset - 16.0)
	draw_rect(Rect2(cx - 2.0, float(cy_txt - 5), 4.0, 3.0), Color(COL_TEAL_TOP if int(counts["online"]) > 0 else COL_FAINT, a))
	PixelText.draw(self, cnt_str, Vector2i(roundi(cx - float(PixelText.width(cnt_str)) * 0.5), cy_txt), Color(COL_MUTED, a))
	_fixed_hits.append({"id": "toggle_drawer", "rect": Rect2(dx, ty, COLLAPSED_W, maxf(vs.y - ty - bottom_inset, 40.0)), "action": "toggle_drawer", "arg": ""})


func _draw_expanded_contents(dx: float, vs: Vector2, counts: Dictionary, a: float) -> void:
	if a <= 0.02:
		return
	_draw_header(dx, a)
	_draw_profile_card(dx, a)
	if CloudSession.is_logged_in():
		_draw_add_friend_row(dx, a)
	if _toast_t > 0.0 and not _toast.is_empty():
		_draw_toast(dx, a)
	_draw_footer_bar(dx, vs, counts, a)


func _draw_header(dx: float, a: float) -> void:
	var ty: float = top_inset
	var x0: float = dx + PAD_X
	var dot_col: Color = COL_TEAL_TOP if CloudSession.is_logged_in() else COL_GOLD
	draw_rect(Rect2(x0, ty + 9.0, 3.0, 3.0), Color(dot_col, a))
	PixelText.draw(self, "SOZIAL", Vector2i(roundi(x0 + 6.0), roundi(ty + 7.0)), Color(COL_MUTED, a))
	_draw_pill_btn("open_chat", Rect2(dx + 100.0, ty + 5.0, 42.0, 13.0), "CHAT", COL_CARD, COL_EDGE_MID, COL_LILAC, a, _fixed_hits)
	# Refresh square button
	var ref_r: Rect2 = Rect2(dx + EXPANDED_W - 38.0, ty + 5.0, 14.0, 13.0)
	var ref_hov: bool = _hover_id == "hdr_refresh"
	_draw_box(ref_r, COL_CARD_HOVER if ref_hov else COL_CARD, COL_EDGE_MID if ref_hov else COL_SEAM, a)
	_draw_refresh_glyph(ref_r.position + Vector2(4.0, 4.0), Color(COL_TEXT if ref_hov else COL_MUTED, a))
	_fixed_hits.append({"id": "hdr_refresh", "rect": ref_r, "action": "refresh_social", "arg": ""})
	# Collapse ">" button
	var cls_r: Rect2 = Rect2(dx + EXPANDED_W - 22.0, ty + 5.0, 14.0, 13.0)
	var cls_hov: bool = _hover_id == "hdr_collapse"
	_draw_box(cls_r, COL_CARD_HOVER if cls_hov else COL_CARD, COL_EDGE_MID if cls_hov else COL_SEAM, a)
	PixelText.draw(self, ">", Vector2i(roundi(cls_r.position.x + 5.0), roundi(cls_r.position.y + 3.0)), Color(COL_TEXT if cls_hov else COL_MUTED, a))
	_fixed_hits.append({"id": "hdr_collapse", "rect": cls_r, "action": "toggle_drawer", "arg": ""})
	draw_rect(Rect2(x0, ty + 21.0, EXPANDED_W - PAD_X * 2.0, 1.0), Color(COL_SEAM, 0.7 * a))


func _draw_refresh_glyph(at: Vector2, col: Color) -> void:
	draw_rect(Rect2(at.x + 1.0, at.y, 3.0, 1.0), col)
	draw_rect(Rect2(at.x, at.y + 1.0, 1.0, 3.0), col)
	draw_rect(Rect2(at.x + 4.0, at.y + 1.0, 1.0, 1.0), col)
	draw_rect(Rect2(at.x + 1.0, at.y + 4.0, 3.0, 1.0), col)
	draw_rect(Rect2(at.x + 4.0, at.y + 3.0, 1.0, 1.0), col)


func _draw_profile_card(dx: float, a: float) -> void:
	var ty: float = top_inset
	var logged_in: bool = CloudSession.is_logged_in()
	var card_h: float = 61.0 if logged_in else 58.0
	var x0: float = dx + PAD_X
	var cw: float = EXPANDED_W - PAD_X * 2.0
	var card: Rect2 = Rect2(x0, ty + 25.0, cw, card_h)
	draw_rect(card, Color(COL_OUTLINE, a))
	draw_rect(card.grow(-1.0), Color(COL_BARK_ALT, 0.92 * a))
	draw_rect(Rect2(card.position.x + 1.0, card.position.y + 1.0, card.size.x - 2.0, 1.0), Color(COL_EDGE_MID, 0.75 * a))
	draw_rect(Rect2(card.position.x + 1.0, card.end.y - 2.0, card.size.x - 2.0, 1.0), Color(COL_SEAM, 0.65 * a))
	# Avatar box (30x30)
	var av_rect: Rect2 = Rect2(x0 + 5.0, ty + 30.0, 30.0, 30.0)
	var raw_name: String = _local_display_name()
	_draw_avatar_on(self, av_rect, CloudSession.avatar_url if logged_in else "", raw_name, logged_in, NetworkManager.is_multiplayer_session(), a, false)
	# Right info column
	var tx: float = x0 + 40.0
	var tw: float = cw - 45.0
	var role_str: String = _role_short(CloudSession.role) if logged_in else ""
	var badge_w: float = float(PixelText.width(role_str) + 6) if not role_str.is_empty() else 0.0
	var name_fit: String = _fit_text(raw_name, tw - (badge_w + 3.0 if badge_w > 0.0 else 0.0))
	PixelText.draw(self, name_fit, Vector2i(roundi(tx), roundi(ty + 29.0)), Color(COL_TEXT, a))
	if not role_str.is_empty():
		_draw_role_badge_on(self, Vector2(card.end.x - badge_w - 5.0, ty + 28.0), CloudSession.role, a)
	if not logged_in:
		PixelText.draw(self, "LOKAL · OFFLINE", Vector2i(roundi(tx), roundi(ty + 41.0)), Color(COL_GOLD, a))
		PixelText.draw(self, _fit_text("ÜBER LAUNCHER ANMELDEN", tw), Vector2i(roundi(tx), roundi(ty + 52.0)), Color(COL_MUTED, a))
		PixelText.draw(self, _fit_text("FÜR PROFIL & FREUNDE", cw - 12.0), Vector2i(roundi(x0 + 5.0), roundi(ty + 67.0)), Color(COL_FAINT, a))
		return
	# Clickable UID pill (12px height, generous bottom padding) + @username
	var uid_txt: String = "#%s" % (CloudSession.uid if not CloudSession.uid.is_empty() else "------")
	var uid_w: float = float(PixelText.width(uid_txt) + 8)
	var uid_r: Rect2 = Rect2(tx, ty + 39.0, uid_w, 12.0)
	var uid_hov: bool = _hover_id == "prof_uid"
	_draw_box(uid_r, COL_CARD_HOVER if uid_hov else COL_WELL, COL_EDGE_LIT if uid_hov else COL_SEAM, a)
	PixelText.draw(self, uid_txt, Vector2i(roundi(uid_r.position.x + 4.0), roundi(uid_r.position.y + 1.5)), Color(COL_TEXT if uid_hov else COL_LILAC, a))
	_fixed_hits.append({"id": "prof_uid", "rect": uid_r, "action": "copy_uid", "arg": ""})
	if not CloudSession.username.is_empty():
		var handle_max: float = card.end.x - 5.0 - (uid_r.end.x + 4.0)
		if handle_max >= 16.0:
			PixelText.draw(self, _fit_text("@%s" % CloudSession.username, handle_max), Vector2i(roundi(uid_r.end.x + 4.0), roundi(ty + 41.0)), Color(COL_FAINT, a))
	# World / Koop activity line
	var in_coop: bool = NetworkManager.is_multiplayer_session()
	var activity: String = ""
	if in_coop:
		activity = _fit_text("KOOP · %d/%d" % [maxi(NetworkManager.roster().size(), 1), NetworkManager.active_max_players], tw)
	elif CloudSession.cloud_save_day >= 0:
		activity = _fit_text("IM SPIEL · TAG %d" % [CloudSession.cloud_save_day + 1], tw)
	else:
		activity = _fit_text("ONLINE · BEREIT", tw)
	draw_rect(Rect2(tx, ty + 56.0, 3.0, 3.0), Color(COL_TEAL_TOP, a))
	PixelText.draw(self, activity, Vector2i(roundi(tx + 6.0), roundi(ty + 53.0)), Color(COL_MUTED, a))
	# Profile action row (14px height, balanced 4px top/bottom padding)
	var row_y: float = ty + 67.0
	var cur_mode: String = NetworkManager.active_join_mode if in_coop else CloudSession.world_join_mode
	var mode_txt: String = "MODUS: %s" % _join_mode_short(cur_mode)
	var mode_r: Rect2 = Rect2(x0 + 5.0, row_y, 81.0, 14.0)
	var mode_txt_col: Color = COL_TEAL_TXT if cur_mode == "open" else (COL_GOLD if cur_mode == "ask" else COL_MUTED)
	_draw_pill_btn("prof_mode", mode_r, _fit_text(mode_txt, 75.0), COL_CARD, COL_EDGE_MID, mode_txt_col, a, _fixed_hits)
	var right_r: Rect2 = Rect2(mode_r.end.x + 4.0, row_y, card.end.x - 5.0 - (mode_r.end.x + 4.0), 14.0)
	var rcode: String = _active_room_code()
	if in_coop and not rcode.is_empty():
		_draw_pill_btn("prof_code", right_r, _fit_text("CODE %s" % rcode, right_r.size.x - 6.0), COL_TEAL_DEEP, COL_TEAL_TOP, COL_TEAL_TXT, a, _fixed_hits)
	elif not in_coop and get_tree().get_first_node_in_group("world") != null:
		_draw_pill_btn("prof_host", right_r, _fit_text("KOOP START", right_r.size.x - 6.0), COL_TEAL_BTN, COL_TEAL_TOP, COL_TEAL_TXT, a, _fixed_hits, COL_TEAL_DEEP)
	else:
		_draw_box(right_r, COL_WELL, COL_SEAM, a)
		PixelText.draw(self, "BEREIT", Vector2i(roundi(right_r.position.x + (right_r.size.x - float(PixelText.width("BEREIT"))) * 0.5), roundi(right_r.position.y + 3.0)), Color(COL_FAINT, a))


func _draw_add_friend_row(dx: float, a: float) -> void:
	var x0: float = dx + PAD_X
	var y0: float = top_inset + 91.0
	var inp_w: float = 127.0
	var inp_r: Rect2 = Rect2(x0, y0, inp_w, 16.0)
	var inp_hov: bool = _hover_id == "add_input"
	_draw_box(inp_r, COL_WELL, COL_EDGE_LIT if (_typing or inp_hov) else COL_SEAM, a)
	if _typing:
		draw_rect(Rect2(inp_r.position.x + 1.0, inp_r.end.y - 2.0, inp_r.size.x - 2.0, 1.0), Color(COL_TEAL_TOP, a))
	var shown: String = _add_text.to_upper() if (not _add_text.is_empty() or _typing) else "UID ODER NAME..."
	var txt_col: Color = COL_TEXT if not _add_text.is_empty() else Color(COL_FAINT, 0.9)
	var clipped: String = _fit_tail(shown, inp_w - 10.0)
	PixelText.draw(self, clipped, Vector2i(roundi(inp_r.position.x + 4.0), roundi(inp_r.position.y + 4.0)), Color(txt_col, a))
	if _typing and int(_time * 2.2) % 2 == 0:
		var cx: float = inp_r.position.x + 5.0 + float(PixelText.width(clipped))
		if _add_text.is_empty():
			cx = inp_r.position.x + 5.0
		draw_rect(Rect2(minf(cx, inp_r.end.x - 4.0), inp_r.position.y + 4.0, 1.0, 7.0), Color(COL_TEAL_TOP, a))
	_fixed_hits.append({"id": "add_input", "rect": inp_r, "action": "focus_add", "arg": ""})
	var btn_r: Rect2 = Rect2(inp_r.end.x + 4.0, y0, dx + EXPANDED_W - PAD_X - (inp_r.end.x + 4.0), 16.0)
	_draw_pill_btn("add_submit", btn_r, "+ ADD", COL_TEAL_BTN, COL_TEAL_TOP, COL_TEAL_TXT, a, _fixed_hits, COL_TEAL_DEEP)


func _draw_toast(dx: float, a: float) -> void:
	var x0: float = dx + PAD_X
	var cw: float = EXPANDED_W - PAD_X * 2.0
	var tr: Rect2 = Rect2(x0, top_inset + 110.0, cw, 12.0)
	var bg: Color = COL_RED_BG if _toast_err else COL_TEAL_DEEP
	var rim: Color = COL_RED if _toast_err else COL_TEAL_TOP
	_draw_box(tr, bg, rim, a * clampf(_toast_t * 2.0, 0.0, 1.0))
	PixelText.draw(self, _fit_text(_toast, cw - 8.0), Vector2i(roundi(tr.position.x + 4.0), roundi(tr.position.y + 2.0)), Color(COL_TEXT, a))


func _draw_footer_bar(dx: float, vs: Vector2, counts: Dictionary, a: float) -> void:
	var y: float = vs.y - bottom_inset - 16.0
	var x0: float = dx + PAD_X
	draw_rect(Rect2(x0, y, EXPANDED_W - PAD_X * 2.0, 1.0), Color(COL_SEAM, 0.65 * a))
	var key_r: Rect2 = Rect2(x0, y + 3.0, 17.0, 11.0)
	_draw_box(key_r, COL_WELL, COL_SEAM, a)
	PixelText.draw(self, "TAB", Vector2i(roundi(key_r.position.x + 3.0), roundi(key_r.position.y + 1.5)), Color(COL_MUTED, a))
	PixelText.draw(self, "SCHLIESSEN", Vector2i(roundi(key_r.end.x + 4.0), roundi(y + 5.0)), Color(COL_FAINT, a))
	var summary: String = "%d/%d ONLINE" % [int(counts["online"]), int(counts["total"])] if CloudSession.is_logged_in() else "OFFLINE"
	var sx: int = roundi(dx + EXPANDED_W - PAD_X - float(PixelText.width(summary)))
	PixelText.draw(self, summary, Vector2i(sx, roundi(y + 5.0)), Color(COL_MUTED if int(counts["online"]) > 0 else COL_FAINT, a))


# ---------- drawing: clipped scrollable social feed ----------

func _draw_feed_content(canvas: CanvasItem) -> void:
	_feed_hits.clear()
	if not visible or _fade <= 0.01 or _eased_slide() < 0.45:
		return
	var a: float = _fade * clampf((_eased_slide() - 0.45) / 0.55, 0.0, 1.0)
	var vw: float = _feed_viewport.size.x
	var vh: float = _feed_viewport.size.y
	var cw: float = vw - 6.0

	if not CloudSession.is_logged_in():
		_scroll_y = 0.0
		_content_h = 54.0
		var empty_box: Rect2 = Rect2(4.0, 4.0, cw - 2.0, 44.0)
		_draw_box_on(canvas, empty_box, COL_CARD, COL_SEAM, a)
		PixelText.draw(canvas, "KEINE CLOUD-SITZUNG", Vector2i(10, 11), Color(COL_GOLD, a))
		PixelText.draw(canvas, "STARTE ÜBER DEN LAUNCHER,", Vector2i(10, 23), Color(COL_MUTED, a))
		PixelText.draw(canvas, "UM FREUNDE ZU SEHEN.", Vector2i(10, 33), Color(COL_MUTED, a))
		return

	var y: float = 2.0 - _scroll_y
	var notifs: Array[Dictionary] = CloudSession.notifications
	if not notifs.is_empty():
		y = _draw_section_header(canvas, "EINLADUNGEN · %d" % notifs.size(), 4.0, y, cw, COL_GOLD, a)
		for notif: Dictionary in notifs:
			y = _draw_notif_card(canvas, notif, 4.0, y, cw, a)
		y += 4.0

	var incoming: Array[Dictionary] = []
	var outgoing: Array[Dictionary] = []
	for fr: Dictionary in CloudSession.friends_cache:
		var st: int = int(fr.get("state", 0))
		if st == 2:
			incoming.append(fr)
		elif st == 1:
			outgoing.append(fr)
	var accepted: Array[Dictionary] = _sorted_accepted_friends()

	if not incoming.is_empty():
		y = _draw_section_header(canvas, "ANFRAGEN · %d" % incoming.size(), 4.0, y, cw, COL_GOLD, a)
		for fr: Dictionary in incoming:
			y = _draw_friend_card(canvas, fr, "incoming", 4.0, y, cw, a)
		y += 4.0

	var on_count: int = 0
	for fr: Dictionary in accepted:
		if bool(fr.get("online", false)):
			on_count += 1
	y = _draw_section_header(canvas, "FREUNDE · %d/%d" % [on_count, accepted.size()], 4.0, y, cw, COL_MUTED, a)
	if accepted.is_empty():
		var ebox: Rect2 = Rect2(4.0, y, cw - 1.0, 28.0)
		_draw_box_on(canvas, ebox, COL_WELL, COL_SEAM, a * 0.9)
		PixelText.draw(canvas, "NOCH KEINE FREUNDE", Vector2i(10, roundi(y + 6.0)), Color(COL_MUTED, a))
		PixelText.draw(canvas, "UID OBEN EINGEBEN", Vector2i(10, roundi(y + 16.0)), Color(COL_FAINT, a))
		y += 32.0
	else:
		for fr: Dictionary in accepted:
			y = _draw_friend_card(canvas, fr, "friend", 4.0, y, cw, a)

	if not outgoing.is_empty():
		y += 4.0
		y = _draw_section_header(canvas, "GESENDET · %d" % outgoing.size(), 4.0, y, cw, COL_FAINT, a)
		for fr: Dictionary in outgoing:
			y = _draw_friend_card(canvas, fr, "outgoing", 4.0, y, cw, a)

	_content_h = maxf(y + _scroll_y + 4.0, vh)
	_scroll_y = clampf(_scroll_y, 0.0, maxf(_content_h - vh, 0.0))
	if _content_h > vh + 1.0:
		_draw_scrollbar(canvas, vw - 3.0, vh, a)


func _draw_section_header(canvas: CanvasItem, title: String, x: float, y: float, w: float, col: Color, a: float) -> float:
	PixelText.draw(canvas, title, Vector2i(roundi(x + 1.0), roundi(y)), Color(col, a))
	var line_x: float = x + float(PixelText.width(title)) + 6.0
	if line_x < x + w - 4.0:
		canvas.draw_rect(Rect2(line_x, roundf(y + 4.0), x + w - line_x, 1.0), Color(COL_SEAM, 0.55 * a))
	return y + 11.0


func _draw_notif_card(canvas: CanvasItem, notif: Dictionary, x: float, y: float, w: float, a: float) -> float:
	var nid: String = String(notif.get("id", ""))
	var code: int = int(notif.get("code", 0))
	var c: Dictionary = notif.get("content", {}) as Dictionary
	var h: float = 38.0
	var card: Rect2 = Rect2(x, y, w - 1.0, h)
	var accent: Color = COL_TEAL_TOP if (code == 101 or code == 103) else (COL_GOLD if code == 102 else COL_RED)
	var rim: Color = COL_GOLD_DIM if code in [101, 102, 103] else COL_RED_RIM
	_draw_box_on(canvas, card, COL_GOLD_BG if code == 102 else COL_BARK_ALT, rim, a)
	canvas.draw_rect(Rect2(x + 1.0, y + 1.0, 2.0, h - 2.0), Color(accent, 0.85 * a))
	var head: String = ""
	var sub: String = ""
	if code == 101 or code == 103:
		head = "BEITRITT OK" if code == 103 else "KOOP-EINLADUNG"
		sub = "%s · %s" % [String(c.get("host_name", "FREUND")), String(c.get("world_name", "KOOP"))]
	elif code == 102:
		head = "BEITRITTSANFRAGE"
		sub = "%s #%s" % [String(c.get("requester_name", "SPIELER")), String(c.get("requester_uid", "?"))]
	else:
		head = "ABGELEHNT"
		sub = String(c.get("host_name", "HOST"))
	PixelText.draw(canvas, _fit_text(head, w - 12.0), Vector2i(roundi(x + 6.0), roundi(y + 4.0)), Color(accent, a))
	PixelText.draw(canvas, _fit_text(sub, w - 12.0), Vector2i(roundi(x + 6.0), roundi(y + 13.0)), Color(COL_TEXT, a))
	var by: float = y + 22.0
	if code == 101 or code == 103:
		_draw_pill_btn_on(canvas, "notif_join_%s" % nid, Rect2(x + 6.0, by, 56.0, 13.0), "BEITRETEN", COL_TEAL_BTN, COL_TEAL_TOP, COL_TEAL_TXT, a, _feed_hits, "notif_join", nid, "", COL_TEAL_DEEP)
		_draw_pill_btn_on(canvas, "notif_dis_%s" % nid, Rect2(x + 65.0, by, 16.0, 13.0), "X", COL_CARD, COL_SEAM, COL_MUTED, a, _feed_hits, "notif_dismiss", nid)
	elif code == 102:
		var req_uid: String = String(c.get("requester_user_id", ""))
		_draw_pill_btn_on(canvas, "req_acc_%s" % req_uid, Rect2(x + 6.0, by, 54.0, 13.0), "ANNEHMEN", COL_TEAL_BTN, COL_TEAL_TOP, COL_TEAL_TXT, a, _feed_hits, "join_req_accept", req_uid, "", COL_TEAL_DEEP)
		_draw_pill_btn_on(canvas, "req_dec_%s" % req_uid, Rect2(x + 63.0, by, 54.0, 13.0), "ABLEHNEN", COL_CARD, COL_RED_RIM, COL_RED, a, _feed_hits, "join_req_decline", req_uid)
	else:
		_draw_pill_btn_on(canvas, "notif_ok_%s" % nid, Rect2(x + 6.0, by, 32.0, 13.0), "OK", COL_CARD, COL_SEAM, COL_TEXT, a, _feed_hits, "notif_dismiss", nid)
	return y + h + 4.0


func _draw_friend_card(canvas: CanvasItem, fr: Dictionary, kind: String, x: float, y: float, w: float, a: float) -> float:
	var fuid: String = String(fr.get("user_id", ""))
	var fname: String = String(fr.get("display_name", fr.get("username", "SPIELER")))
	if fname.is_empty():
		fname = String(fr.get("username", "SPIELER"))
	var online: bool = bool(fr.get("online", false))
	var coop_active: bool = kind == "friend" and bool(fr.get("coop_active", false))
	var join_mode: String = String(fr.get("coop_join_mode", "ask"))
	var can_join: bool = coop_active and join_mode != "private"
	var can_inv: bool = kind == "friend" and online and _can_invite_friends()
	var h: float = 40.0
	var card: Rect2 = Rect2(x, y, w - 1.0, h)
	var card_alpha: float = a if (online or kind != "friend") else a * 0.72
	var is_hov: bool = _hover_id.ends_with(fuid) and not fuid.is_empty()
	var fill: Color = COL_CARD_HOVER if is_hov else (COL_GOLD_BG if kind == "incoming" else COL_CARD)
	canvas.draw_rect(card, Color(fill, card_alpha))
	canvas.draw_rect(Rect2(card.position, Vector2(card.size.x, 1.0)), Color(COL_SEAM, 0.55 * card_alpha))
	if coop_active:
		canvas.draw_rect(Rect2(card.position, Vector2(2.0, h)), Color(COL_TEAL_TOP, 0.7 * card_alpha))
	# Mini 18x18 avatar + status dot
	var av_r: Rect2 = Rect2(x + 4.0, y + 4.0, 18.0, 18.0)
	_draw_avatar_on(canvas, av_r, String(fr.get("avatar_url", "")), fname, online or kind != "friend", coop_active, card_alpha, false)
	# Line 1: Display name + role chip + quiet remove button [X]
	var tx: float = x + 26.0
	var rem_reserve: float = 16.0 if kind == "friend" else 2.0
	var role_str: String = _role_short(String(fr.get("role", "player")))
	var role_w: float = float(PixelText.width(role_str) + 6) if not role_str.is_empty() else 0.0
	var max_name_w: float = w - 29.0 - rem_reserve - (role_w + 3.0 if role_w > 0.0 else 0.0)
	PixelText.draw(canvas, _fit_text(fname, max_name_w), Vector2i(roundi(tx), roundi(y + 4.0)), Color(COL_TEXT if (online or kind != "friend") else COL_MUTED, card_alpha))
	if not role_str.is_empty():
		_draw_role_badge_on(canvas, Vector2(x + w - rem_reserve - role_w - 3.0, y + 3.0), String(fr.get("role", "")), card_alpha)
	if kind == "friend":
		var armed: bool = _arm_remove_id == fuid
		var rlbl: String = "?" if armed else "X"
		var rem_r: Rect2 = Rect2(x + w - 15.0, y + 3.0, 12.0, 12.0)
		_draw_pill_btn_on(canvas, "fr_rem_%s" % fuid, rem_r, rlbl, COL_RED_BG if armed else COL_CARD, COL_RED if armed else COL_SEAM, COL_TEXT if armed else COL_FAINT, card_alpha, _feed_hits, "friend_remove", fuid)
	# Line 2: subtle Launcher-style status subtext
	var sub_txt: String = ""
	var sub_col: Color = COL_FAINT
	if kind == "incoming":
		sub_txt = "MÖCHTE FREUND SEIN"
		sub_col = COL_GOLD
	elif kind == "outgoing":
		sub_txt = "ANFRAGE GESENDET"
		sub_col = COL_FAINT
	elif coop_active:
		sub_txt = "%s %d/%d" % [String(fr.get("coop_world_name", "KOOP")), int(fr.get("coop_players", 1)), int(fr.get("coop_max_players", 4))]
		sub_col = COL_GOLD if join_mode == "ask" else (COL_TEAL_TOP if can_join else COL_MUTED)
	elif online:
		sub_txt = "ONLINE · #%s" % String(fr.get("uid", "?"))
		sub_col = COL_TEAL_TOP
	else:
		sub_txt = "OFFLINE"
		sub_col = COL_FAINT
	PixelText.draw(canvas, _fit_text(sub_txt, w - 32.0), Vector2i(roundi(tx), roundi(y + 14.0)), Color(sub_col, card_alpha))
	# Line 3: spacious 13px action buttons (no bottom glyph clipping!)
	var by: float = y + 24.0
	var bx: float = tx
	if kind == "incoming":
		_draw_pill_btn_on(canvas, "fr_acc_%s" % fuid, Rect2(bx, by, 52.0, 13.0), "ANNEHMEN", COL_TEAL_BTN, COL_TEAL_TOP, COL_TEAL_TXT, a, _feed_hits, "friend_accept", fuid, "", COL_TEAL_DEEP)
		_draw_pill_btn_on(canvas, "fr_dec_%s" % fuid, Rect2(bx + 55.0, by, 50.0, 13.0), "ABLEHNEN", COL_CARD, COL_RED_RIM, COL_RED, a, _feed_hits, "friend_decline", fuid)
	elif kind == "outgoing":
		_draw_pill_btn_on(canvas, "fr_can_%s" % fuid, Rect2(bx, by, 52.0, 13.0), "STORNO", COL_CARD, COL_SEAM, COL_MUTED, a, _feed_hits, "friend_cancel", fuid)
	else:
		_draw_pill_btn_on(canvas, "fr_dm_%s" % fuid, Rect2(bx, by, 24.0, 13.0), "DM", COL_BARK_ALT, COL_EDGE_MID, COL_LILAC, a, _feed_hits, "friend_dm", fuid)
		bx += 27.0
		if can_join:
			var jlbl: String = "BEITRETEN" if join_mode == "open" else "ANFRAGEN"
			var jfill: Color = COL_TEAL_BTN if join_mode == "open" else COL_CARD
			var jrim: Color = COL_TEAL_TOP if join_mode == "open" else COL_EDGE_MID
			var jtxt: Color = COL_TEAL_TXT if join_mode == "open" else COL_MUTED
			var jbot: Color = COL_TEAL_DEEP if join_mode == "open" else Color(0, 0, 0, 0)
			_draw_pill_btn_on(canvas, "fr_join_%s" % fuid, Rect2(bx, by, 54.0, 13.0), jlbl, jfill, jrim, jtxt, a, _feed_hits, "friend_join", fuid, "", jbot)
			bx += 57.0
		if can_inv:
			_draw_pill_btn_on(canvas, "fr_inv_%s" % fuid, Rect2(bx, by, 52.0, 13.0), "EINLADEN", COL_CARD, COL_EDGE_MID, COL_LILAC, a, _feed_hits, "friend_invite", fuid)
	return y + h + 3.0


func _draw_scrollbar(canvas: CanvasItem, sx: float, vh: float, a: float) -> void:
	canvas.draw_rect(Rect2(sx, 2.0, 2.0, vh - 4.0), Color(COL_WELL, 0.7 * a))
	var ratio: float = clampf(vh / _content_h, 0.12, 1.0)
	var thumb_h: float = maxf((vh - 4.0) * ratio, 14.0)
	var max_s: float = maxf(_content_h - vh, 1.0)
	var thumb_y: float = 2.0 + ((vh - 4.0) - thumb_h) * (_scroll_y / max_s)
	canvas.draw_rect(Rect2(sx, roundf(thumb_y), 2.0, roundf(thumb_h)), Color(COL_EDGE_MID, a))


# ---------- shared primitive drawing helpers ----------

func _draw_box(r: Rect2, fill: Color, rim: Color, a: float) -> void:
	_draw_box_on(self, r, fill, rim, a)


func _draw_box_on(canvas: CanvasItem, r: Rect2, fill: Color, rim: Color, a: float, bottom_rim: Color = Color(0, 0, 0, 0)) -> void:
	canvas.draw_rect(r, Color(COL_OUTLINE, a))
	if r.size.x <= 2.0 or r.size.y <= 2.0:
		return
	var inner: Rect2 = r.grow(-1.0)
	canvas.draw_rect(inner, Color(fill, a))
	canvas.draw_rect(Rect2(inner.position, Vector2(inner.size.x, 1.0)), Color(rim, 0.78 * a))
	canvas.draw_rect(Rect2(inner.position, Vector2(1.0, inner.size.y)), Color(rim, 0.35 * a))
	var bcol: Color = bottom_rim if bottom_rim.a > 0.0 else Color(rim, 0.25)
	canvas.draw_rect(Rect2(inner.position.x, inner.end.y - 1.0, inner.size.x, 1.0), Color(bcol.r, bcol.g, bcol.b, bcol.a * a))


func _draw_pill_btn(id: String, r: Rect2, label: String, fill: Color, rim: Color, txt_col: Color, a: float, hits: Array[Dictionary], bottom_rim: Color = Color(0, 0, 0, 0)) -> void:
	_draw_pill_btn_on(self, id, r, label, fill, rim, txt_col, a, hits, "", "", id, bottom_rim)


func _draw_pill_btn_on(canvas: CanvasItem, id: String, r: Rect2, label: String, fill: Color, rim: Color, txt_col: Color, a: float, hits: Array[Dictionary], action: String, arg: String, override_action_id: String = "", bottom_rim: Color = Color(0, 0, 0, 0)) -> void:
	var hovered: bool = _hover_id == id
	_draw_box_on(canvas, r, fill.lightened(0.09) if hovered else fill, rim.lightened(0.12) if hovered else rim, a, bottom_rim)
	var lx: int = roundi(r.position.x + (r.size.x - float(PixelText.width(label))) * 0.5)
	# Subtract 1px to vertically center the 5px cap height (PixelText has 2px top umlaut headroom)
	var ly: int = roundi(r.position.y + (r.size.y - float(PixelText.HEIGHT)) * 0.5) - 1
	PixelText.draw(canvas, label, Vector2i(lx, ly), Color(txt_col, a))
	var resolved_action: String = action if not action.is_empty() else _fixed_action_for(override_action_id)
	if not resolved_action.is_empty():
		hits.append({"id": id, "rect": r, "action": resolved_action, "arg": arg})


func _fixed_action_for(id: String) -> String:
	match id:
		"prof_mode":
			return "cycle_join_mode"
		"prof_code":
			return "copy_room_code"
		"prof_host":
			return "host_relay"
		"add_submit":
			return "submit_add"
		_:
			return id


func _draw_avatar_on(canvas: CanvasItem, r: Rect2, avatar_id: String, display_str: String, online: bool, in_coop: bool, a: float, compact: bool) -> void:
	var rim: Color = COL_TEAL_TOP if in_coop else (COL_EDGE_MID if online else COL_SEAM)
	_draw_box_on(canvas, r, COL_WELL, rim, a)
	var tex: Texture2D = _resolve_avatar_texture(avatar_id)
	if tex != null:
		var tint: Color = Color(1, 1, 1, a) if online else Color(0.75, 0.72, 0.85, 0.72 * a)
		canvas.draw_texture_rect(tex, r.grow(-1.0), false, tint)
	else:
		var ch: String = display_str.strip_edges().substr(0, 1).to_upper()
		if ch.is_empty():
			ch = "?"
		var lx: int = roundi(r.get_center().x - float(PixelText.width(ch)) * 0.5)
		var ly: int = roundi(r.get_center().y - 3.5)
		PixelText.draw(canvas, ch, Vector2i(lx, ly), Color(COL_LILAC if online else COL_FAINT, a))
	var dot_col: Color = COL_GOLD if in_coop else (COL_TEAL if online else COL_FAINT)
	var ds: float = 4.0 if compact else 5.0
	var dr: Rect2 = Rect2(r.end.x - ds + 1.0, r.end.y - ds + 1.0, ds, ds)
	canvas.draw_rect(dr, Color(COL_OUTLINE, a))
	canvas.draw_rect(dr.grow(-1.0), Color(dot_col, a))


func _draw_role_badge_on(canvas: CanvasItem, at: Vector2, role_val: String, a: float) -> void:
	var lbl: String = _role_short(role_val)
	if lbl.is_empty():
		return
	var r: Rect2 = Rect2(at.x, at.y, float(PixelText.width(lbl) + 6), 11.0)
	var bg: Color = Color("24193c")
	var rim: Color = Color("3b2a6e")
	var txt: Color = COL_LILAC
	if role_val == "moderator":
		bg = Color("13342e")
		rim = COL_TEAL_BTN
		txt = COL_TEAL_TOP
	elif role_val == "tester":
		bg = Color("2b2012")
		rim = COL_GOLD_DIM
		txt = COL_GOLD
	_draw_box_on(canvas, r, bg, rim, a)
	PixelText.draw(canvas, lbl, Vector2i(roundi(r.position.x + 3.0), roundi(r.position.y + 1.0)), Color(txt, a))


static func _resolve_avatar_texture(avatar_id: String) -> Texture2D:
	match avatar_id:
		"ellie_leere":
			return AVATAR_LEERE
		"ellie_lichtung":
			return AVATAR_LICHTUNG
		_:
			return AVATAR_LICHTUNG if not avatar_id.is_empty() else null


static func _role_short(r: String) -> String:
	match r.strip_edges().to_lower():
		"admin":
			return "ADMIN"
		"moderator":
			return "MOD"
		"tester":
			return "TESTER"
		_:
			return ""


static func _join_mode_short(mode: String) -> String:
	match mode:
		"private":
			return "PRIVAT"
		"open":
			return "OFFEN"
		_:
			return "ANFRAGE"


func _local_display_name() -> String:
	if CloudSession.is_logged_in():
		if not CloudSession.display_name.is_empty():
			return CloudSession.display_name
		if not CloudSession.username.is_empty():
			return CloudSession.username
	var fallback: String = String(GameSettings.get_value("player_name"))
	return fallback if not fallback.is_empty() else "ELLIE"


static func _fit_text(text: String, max_w: float) -> String:
	var up: String = text.to_upper()
	var chars: int = maxi(int((max_w + 1.0) / float(PixelText.ADVANCE)), 1)
	if up.length() <= chars:
		return up
	if chars <= 2:
		return up.substr(0, chars)
	return up.substr(0, chars - 2) + ".."


static func _fit_tail(text: String, max_w: float) -> String:
	var up: String = text.to_upper()
	var chars: int = maxi(int((max_w + 1.0) / float(PixelText.ADVANCE)), 1)
	if up.length() <= chars:
		return up
	return up.substr(up.length() - chars, chars)
