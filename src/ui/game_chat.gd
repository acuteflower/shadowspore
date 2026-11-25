extends CanvasLayer
## Shadowspore Whisper Vine Chat ("Die Flüsterranke").
## Organic living-vine & bark-vellum chat rooted to the bottom-left screen edge:
##   - Textured 1:1 pixel-art bark-vellum & recessed obsidian input well (ChatChrome)
##   - Proportional mixed-case pixel bitmap typography (ChatFont, zero blurry vector text)
##   - Living VineStyle top/bottom branches with day moss leaves & night creeping void tendrils
##   - Feathered atmospheric backdrop shader (chat_veil.gdshader) & bioluminescent spore FX
##   - Inline channel ribbon (SPIEL, GRUPPE, active DMs, +), sliding bloom & unread pips
##   - Slash-command & player-name autocomplete, /ort, /me, /g, /s, /msg, /r, /clear, /help
##   - Ambient boxless floating whisper feed + unread spore bud when closed
##   - Rock-solid ESC handling (closes chat cleanly without leaking to GameMenu / PauseMenu)

const VEIL_SHADER: Shader = preload("res://assets/shaders/chat_veil.gdshader")
const OPEN_WAV: AudioStream = preload("res://assets/audio/board/rustle_a.wav")
const CLOSE_WAV: AudioStream = preload("res://assets/audio/board/rustle_b.wav")

# Palette aligned with docs/design_guide.md & VineStyle
const COL_TEXT: Color = Color("ede8f8")
const COL_TEXT_SOFT: Color = Color("c8c0dc")
const COL_MUTED: Color = Color("968eb4")
const COL_DIM: Color = Color("6e668c")
const COL_TEAL: Color = Color("78f4e6")
const COL_GOLD: Color = Color("ffd98a")
const COL_LILAC: Color = Color("cbaaff")
const COL_ROSE: Color = Color("f082a4")
const COL_ME: Color = Color("d8c8f4")
const COL_OUTLINE: Color = Color("0b0716")

const PANEL_LEFT: float = 8.0
const PANEL_W: float = 266.0
const HEADER_H: float = 21.0
const INPUT_H: float = 20.0
const LOG_MIN_H: float = 26.0
const LOG_MAX_COMPACT: float = 80.0
const LOG_MAX_EXPANDED: float = 152.0
const HINT_H: float = 15.0
const OPEN_SEC: float = 0.24
const CLOSE_SEC: float = 0.16
const AMBIENT_HOLD: float = 8.5
const AMBIENT_FADE: float = 1.6
const AMBIENT_MAX: int = 4
const HISTORY_LIMIT: int = 30
const SUGGEST_MAX: int = 6

const COMMANDS: Array[Dictionary] = [
	{"cmd": "/msg", "usage": "/msg <Name> [Text]", "desc": "Direktnachricht senden"},
	{"cmd": "/r", "usage": "/r [Text]", "desc": "Letzter Direktnachricht antworten"},
	{"cmd": "/g", "usage": "/g [Text]", "desc": "In Gruppenchat schreiben"},
	{"cmd": "/s", "usage": "/s [Text]", "desc": "In Spielchat schreiben"},
	{"cmd": "/ort", "usage": "/ort", "desc": "Aktuelle Zone & Ort teilen"},
	{"cmd": "/me", "usage": "/me <Aktion>", "desc": "Handlung beschreiben"},
	{"cmd": "/clear", "usage": "/clear", "desc": "Ansicht lokal leeren"},
	{"cmd": "/help", "usage": "/help", "desc": "Befehle anzeigen"},
]


class _DrawProxy extends Control:
	var owner_chat: Node = null
	var method_name: StringName = &""

	func _draw() -> void:
		if owner_chat != null and method_name != &"":
			owner_chat.call(method_name, self)


# Public-compatible fields used by tools/test_chat.gd
var _shell: Control = Control.new()
var _log: RichTextLabel = RichTextLabel.new()
var _field: LineEdit = LineEdit.new()
var _hint: Label = Label.new()
var _key: String = "game"

# Visual layers & interactive controls
var _ambient_canvas: _DrawProxy = _DrawProxy.new()
var _bud_hit: Control = Control.new()
var _veil: ColorRect = ColorRect.new()
var _veil_mat: ShaderMaterial = ShaderMaterial.new()
var _frame_canvas: _DrawProxy = _DrawProxy.new()
var _overlay_canvas: _DrawProxy = _DrawProxy.new()
var _hit_layer: Control = Control.new()
var _suggest_hit: Control = Control.new()
var _jump_hit: Control = Control.new()

# State & animation clocks
var _is_open: bool = false
var _open_t: float = 0.0
var _time: float = 0.0
var _accent: Color = COL_TEAL
var _accent_live: Color = COL_TEAL
var _bloom_x: float = 34.0
var _bloom_ready: bool = false
var _panel_h: float = 82.0
var _panel_h_target: float = 82.0
var _panel_rect: Rect2 = Rect2()
var _input_rect: Rect2 = Rect2()
var _send_rect: Rect2 = Rect2()
var _admin_rect: Rect2 = Rect2()
var _expand_rect: Rect2 = Rect2()
var _close_rect: Rect2 = Rect2()
var _suggest_rect: Rect2 = Rect2()
var _jump_rect: Rect2 = Rect2()
var _bud_rect: Rect2 = Rect2()

var _expanded: bool = false
var _busy: bool = false
var _hover_id: String = ""
var _tab_hits: Array[Dictionary] = [] ## {id, key, rect, label, icon, accent, unread}
var _tab_hover: Dictionary = {} ## key -> float 0..1
var _drafts: Dictionary = {}
var _unread: Dictionary = {} ## key -> int count
var _cleared_order: Dictionary = {} ## key -> int order threshold
var _local_notes: Dictionary = {} ## key -> Array[Dictionary] local /help & status notices

# Validation hint strip animation
var _hint_visible: bool = false
var _hint_is_error: bool = true
var _hint_shake: float = 0.0
var _hint_timer: float = 0.0

# Sent message history (Up/Down)
var _sent_history: Array[String] = []
var _hist_idx: int = -1
var _hist_saved_draft: String = ""

# Slash-command / player-name autocomplete
var _suggestions: Array[Dictionary] = [] ## {insert, label, desc, kind}
var _suggest_sel: int = 0
var _suggest_hover: int = -1
var _suggest_t: float = 0.0

# Scroll-to-bottom dewdrop
var _scrolled_up: bool = false
var _scrolled_unread: bool = false

# Ambient closed whisper feed & spore particles
var _ambient_rows: Array[Dictionary] = [] ## {key, author, text, own, born, accent}
var _spores: Array[Dictionary] = [] ## {pos, vel, age, life, col, size}
var _last_chime_msec: int = 0
var _redraw_accum: float = 0.0


func _ready() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("game_chat")

	# 1. Ambient closed whisper layer (floating boxless lines + unread spore bud)
	_ambient_canvas.name = "AmbientWhisper"
	_ambient_canvas.owner_chat = self
	_ambient_canvas.method_name = &"_draw_ambient"
	_ambient_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ambient_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ambient_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_ambient_canvas)

	_bud_hit.name = "UnreadBudHit"
	_bud_hit.mouse_filter = Control.MOUSE_FILTER_STOP
	_bud_hit.visible = false
	_bud_hit.gui_input.connect(_on_bud_input)
	_bud_hit.mouse_entered.connect(func() -> void:
		_hover_id = "ambient_bud"
		GameCursor.set_hint(self, &"click")
		_ambient_canvas.queue_redraw())
	_bud_hit.mouse_exited.connect(func() -> void:
		if _hover_id == "ambient_bud":
			_hover_id = ""
		GameCursor.set_hint(self, &"")
		_ambient_canvas.queue_redraw())
	add_child(_bud_hit)

	# 2. Active Whisper Vine shell
	_shell.name = "ChatShell"
	_shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shell.mouse_filter = Control.MOUSE_FILTER_STOP
	_shell.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_shell.visible = false
	_shell.gui_input.connect(_on_shell_input)
	add_child(_shell)

	# Atmospheric feathered backdrop shader
	_veil.name = "ChatVeil"
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_veil_mat.shader = VEIL_SHADER
	_veil.material = _veil_mat
	_shell.add_child(_veil)

	# Hand-crafted pixel chrome + living vine canvas
	_frame_canvas.name = "ChatFrame"
	_frame_canvas.owner_chat = self
	_frame_canvas.method_name = &"_draw_open"
	_frame_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_shell.add_child(_frame_canvas)

	# Interactive hit layer for header tabs, expand, close, send button, and outside-clicks
	_hit_layer.name = "ChatHits"
	_hit_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hit_layer.mouse_filter = Control.MOUSE_FILTER_PASS
	_hit_layer.gui_input.connect(_on_hit_input)
	_shell.add_child(_hit_layer)

	# Pixel-crisp RichTextLabel transcript
	var chat_theme: Theme = _build_chat_theme()
	_log.name = "ChatLog"
	_log.theme = chat_theme
	_log.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.bbcode_enabled = false
	_log.fit_content = false
	_log.meta_underlined = false
	_log.add_theme_font_override("normal_font", ChatFont.bitmap_font())
	_log.add_theme_font_override("bold_font", ChatFont.bitmap_font())
	_log.add_theme_font_override("italics_font", ChatFont.bitmap_font())
	_log.add_theme_font_size_override("normal_font_size", ChatFont.SIZE)
	_log.add_theme_color_override("default_color", COL_TEXT)
	_log.add_theme_color_override("font_shadow_color", Color("090512", 0.92))
	_log.add_theme_constant_override("shadow_offset_x", 1)
	_log.add_theme_constant_override("shadow_offset_y", 1)
	_log.add_theme_constant_override("line_separation", 2)
	_log.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_log.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_log.meta_clicked.connect(_on_meta_clicked)
	_shell.add_child(_log)

	# Hidden logical hint store (preserved for test_chat.gd compatibility; drawn as textured ribbon)
	_hint.name = "ChatHint"
	_hint.visible = false
	_shell.add_child(_hint)

	# Pixel-crisp LineEdit inside our recessed obsidian well
	_field.name = "ChatField"
	_field.theme = chat_theme
	_field.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_field.expand_to_text_length = false
	_field.keep_editing_on_text_submit = true
	_field.max_length = Chat.LIMIT + 64
	_field.caret_blink = true
	_field.caret_blink_interval = 0.52
	_field.add_theme_font_override("font", ChatFont.bitmap_font())
	_field.add_theme_font_size_override("font_size", ChatFont.SIZE)
	_field.add_theme_color_override("font_color", COL_TEXT)
	_field.add_theme_color_override("font_placeholder_color", COL_DIM)
	_field.add_theme_color_override("caret_color", COL_TEAL)
	_field.add_theme_color_override("selection_color", Color(COL_TEAL, 0.28))
	var field_pad: StyleBoxEmpty = StyleBoxEmpty.new()
	field_pad.content_margin_left = 1.0
	field_pad.content_margin_right = 1.0
	field_pad.content_margin_top = 1.0
	field_pad.content_margin_bottom = 0.0
	_field.add_theme_stylebox_override("normal", field_pad)
	_field.add_theme_stylebox_override("focus", field_pad)
	_field.text_submitted.connect(_submit)
	_field.text_changed.connect(_on_field_changed)
	_shell.add_child(_field)

	# Floating jump-to-bottom hit box (above _log)
	_jump_hit.name = "JumpBottomHit"
	_jump_hit.mouse_filter = Control.MOUSE_FILTER_STOP
	_jump_hit.visible = false
	_jump_hit.gui_input.connect(_on_jump_input)
	_jump_hit.mouse_entered.connect(func() -> void:
		_hover_id = "jump_bottom"
		GameCursor.set_hint(self, &"click")
		_frame_canvas.queue_redraw())
	_jump_hit.mouse_exited.connect(func() -> void:
		if _hover_id == "jump_bottom":
			_hover_id = ""
		GameCursor.set_hint(self, &"")
		_frame_canvas.queue_redraw())
	_shell.add_child(_jump_hit)

	# Floating autocomplete hit box (above _log & _field)
	_suggest_hit.name = "SuggestHit"
	_suggest_hit.mouse_filter = Control.MOUSE_FILTER_STOP
	_suggest_hit.visible = false
	_suggest_hit.gui_input.connect(_on_suggest_input)
	_suggest_hit.mouse_exited.connect(func() -> void:
		_suggest_hover = -1
		GameCursor.set_hint(self, &"")
		_overlay_canvas.queue_redraw())
	_shell.add_child(_suggest_hit)

	# Foreground overlay canvas (always drawn ABOVE _log and _field: autocomplete leaf, jump pill, spores, corner vines)
	_overlay_canvas.name = "ChatOverlay"
	_overlay_canvas.owner_chat = self
	_overlay_canvas.method_name = &"_draw_overlay"
	_overlay_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_shell.add_child(_overlay_canvas)

	Chat.changed.connect(_on_chat_changed)
	Chat.incoming.connect(_incoming)
	Chat.admin_reply.connect(_on_admin_reply)
	Chat.system_broadcast.connect(_on_system_broadcast)
	CloudSession.auth_changed.connect(_account_changed)
	NetworkManager.session_changed.connect(_check_target)


func _build_chat_theme() -> Theme:
	var th: Theme = Theme.new()
	th.default_font = ChatFont.bitmap_font()
	th.default_font_size = ChatFont.SIZE
	th.set_stylebox("scroll", "VScrollBar", ChatChrome.scroll_style("rail"))
	th.set_stylebox("grabber", "VScrollBar", ChatChrome.scroll_style("idle"))
	th.set_stylebox("grabber_highlight", "VScrollBar", ChatChrome.scroll_style("lit"))
	th.set_stylebox("grabber_pressed", "VScrollBar", ChatChrome.scroll_style("lit"))
	var empty_step: StyleBoxEmpty = StyleBoxEmpty.new()
	th.set_stylebox("scroll_focus", "VScrollBar", empty_step)
	var blank_icon: ImageTexture = ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	th.set_icon("increment", "VScrollBar", blank_icon)
	th.set_icon("increment_highlight", "VScrollBar", blank_icon)
	th.set_icon("increment_pressed", "VScrollBar", blank_icon)
	th.set_icon("decrement", "VScrollBar", blank_icon)
	th.set_icon("decrement_highlight", "VScrollBar", blank_icon)
	th.set_icon("decrement_pressed", "VScrollBar", blank_icon)
	return th


# ------------------------------------------------------------------ Public API

func open_chat() -> void:
	var was_open: bool = _is_open
	_is_open = true
	_shell.visible = true
	_shell.mouse_filter = Control.MOUSE_FILTER_STOP
	InputManager.chat_open = true
	if not was_open:
		_open_t = maxf(_open_t, 0.02)
		_bloom_ready = false
		_play_rustle(OPEN_WAV, -14.5, 1.02)
	_select(_key)
	_sync_layout(true)
	if not was_open:
		_spawn_spores(Vector2(_panel_rect.position.x + 18.0, _panel_rect.position.y + 4.0), _accent, 7)


func open_friend(id: String, title: String) -> void:
	open_chat()
	_direct("dm/" + id, title)


func close_chat() -> void:
	if not _is_open and not InputManager.chat_open:
		return
	_drafts[_key] = _field.text
	_is_open = false
	InputManager.chat_open = false
	InputManager.mark_chat_closed()
	_field.release_focus()
	_shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_suggestions.clear()
	_suggest_hit.visible = false
	_jump_hit.visible = false
	_hover_id = ""
	GameCursor.set_hint(self, &"")
	_play_rustle(CLOSE_WAV, -15.5, 1.06)


func _exit_tree() -> void:
	if _is_open or InputManager.chat_open:
		InputManager.chat_open = false
		InputManager.mark_chat_closed()
	GameCursor.set_hint(self, &"")


# ------------------------------------------------------------------ Process & Animation

func _process(delta: float) -> void:
	_time += delta
	var target_open: float = 1.0 if _is_open else 0.0
	var dur: float = OPEN_SEC if _is_open else CLOSE_SEC
	_open_t = move_toward(_open_t, target_open, delta / maxf(dur, 0.01))

	if not _is_open and _open_t <= 0.001:
		if _shell.visible:
			_shell.visible = false
	elif _open_t > 0.001:
		_shell.visible = true

	# Prune expired ambient whisper lines
	var ambient_alive: bool = false
	for i: int in range(_ambient_rows.size() - 1, -1, -1):
		var age: float = _time - float(_ambient_rows[i]["born"])
		if age >= AMBIENT_HOLD + AMBIENT_FADE:
			_ambient_rows.remove_at(i)
		else:
			ambient_alive = true

	# Update spore particles
	for i: int in range(_spores.size() - 1, -1, -1):
		var sp: Dictionary = _spores[i]
		sp["age"] = float(sp["age"]) + delta
		if float(sp["age"]) >= float(sp["life"]):
			_spores.remove_at(i)
		else:
			var vel: Vector2 = sp["vel"] as Vector2
			sp["pos"] = (sp["pos"] as Vector2) + vel * delta
			sp["vel"] = vel * maxf(1.0 - delta * 1.8, 0.0) + Vector2(sin(_time * 4.0 + float(i)) * 4.0, -6.0) * delta

	# Hint banner shake & auto-fade (for soft non-error hints)
	if _hint_shake > 0.0:
		_hint_shake = maxf(_hint_shake - delta * 4.5, 0.0)
	if _hint_visible and _hint_timer > 0.0:
		_hint_timer -= delta
		if _hint_timer <= 0.0:
			_hide_hint()

	# Smoothly morph channel accent, bloom position, height, and tab hovers
	var k_fast: float = 1.0 - exp(-16.0 * delta)
	_accent_live = _accent_live.lerp(_accent, k_fast)
	_panel_h = lerpf(_panel_h, _panel_h_target, 1.0 - exp(-18.0 * delta))
	_suggest_t = move_toward(_suggest_t, 1.0 if not _suggestions.is_empty() and _is_open else 0.0, delta / 0.14)

	for tab: Dictionary in _tab_hits:
		var tk: String = String(tab["key"])
		var hovered: bool = _hover_id == "tab:" + tk
		var cur_h: float = float(_tab_hover.get(tk, 0.0))
		_tab_hover[tk] = lerpf(cur_h, 1.0 if hovered else 0.0, k_fast)
		if tk == _key:
			var goal_x: float = (tab["rect"] as Rect2).get_center().x
			_bloom_x = goal_x if not _bloom_ready else lerpf(_bloom_x, goal_x, 1.0 - exp(-18.0 * delta))
			_bloom_ready = true

	if _shell.visible:
		_sync_layout(false)
		_update_scroll_state()
		_update_veil_shader()
		_frame_canvas.queue_redraw()
		_overlay_canvas.queue_redraw()

	# Ambient canvas redraw (throttled when idle, responsive when animating)
	var has_unread_bud: bool = _unread_priority_count() > 0
	var show_ambient: bool = not _is_open and _open_t < 0.85 and not _ambient_suppressed()
	_ambient_canvas.visible = show_ambient and (ambient_alive or has_unread_bud)
	_sync_bud_hit(show_ambient and has_unread_bud)
	if _ambient_canvas.visible:
		_redraw_accum += delta
		if _redraw_accum >= 0.04:
			_redraw_accum = 0.0
			_ambient_canvas.queue_redraw()


func _ambient_suppressed() -> bool:
	if get_tree().paused or InputManager.menu_open or InputManager.map_open or InputManager.journal_open or InputManager.skills_open or InputManager.progress_open or InputManager.dungeons_open or InputManager.inventory_open:
		return true
	var parent_hud: Node = get_parent()
	if parent_hud != null:
		var director: HudDirector = parent_hud.get_node_or_null("Director") as HudDirector
		if director != null:
			for ctx: String in ["boss", "dialogue", "vista", "cutscene", "menu"]:
				if director.is_on(ctx):
					return true
	return false


func _update_scroll_state() -> void:
	if not _log.visible:
		_scrolled_up = false
		_scrolled_unread = false
		_jump_hit.visible = false
		return
	var sb: VScrollBar = _log.get_v_scroll_bar()
	if sb == null or not sb.visible:
		_scrolled_up = false
		_scrolled_unread = false
		_jump_hit.visible = false
		return
	var at_bottom: bool = sb.value + sb.page >= sb.max_value - 4.0
	_scrolled_up = not at_bottom
	if at_bottom:
		_scrolled_unread = false
	_jump_hit.visible = _is_open and _scrolled_up and _open_t > 0.7
	if _jump_hit.visible:
		_jump_hit.position = _jump_rect.position
		_jump_hit.size = _jump_rect.size


func _chat_opacity() -> float:
	return GameSettings.chat_opacity()


func _chat_opacity_norm(op: float) -> float:
	return clampf((op - 0.30) / 0.70, 0.0, 1.0)


func _update_veil_shader() -> void:
	var ease_t: float = 1.0 - pow(1.0 - clampf(_open_t, 0.0, 1.0), 3.0)
	var op: float = _chat_opacity()
	var veil_pad_l: float = 8.0
	var veil_pad_r: float = 20.0
	var veil_pad_t: float = 14.0
	var veil_pad_b: float = 12.0
	var vr: Rect2 = Rect2(
		maxf(_panel_rect.position.x - veil_pad_l, 0.0),
		_panel_rect.position.y - veil_pad_t,
		_panel_rect.size.x + veil_pad_l + veil_pad_r,
		_panel_rect.size.y + veil_pad_t + veil_pad_b
	)
	_veil.position = vr.position.round()
	_veil.size = vr.size.round()
	_veil_mat.set_shader_parameter("time", _time)
	_veil_mat.set_shader_parameter("open_t", ease_t)
	_veil_mat.set_shader_parameter("night", VineStyle.void_amount())
	_veil_mat.set_shader_parameter("accent_col", Vector3(_accent_live.r, _accent_live.g, _accent_live.b))
	_veil_mat.set_shader_parameter("panel_size", vr.size)
	_veil_mat.set_shader_parameter("opacity_scale", op)


# ------------------------------------------------------------------ Layout Math

func _viewport_size() -> Vector2:
	var vp: Viewport = get_viewport()
	if vp != null:
		var sz: Vector2 = vp.get_visible_rect().size
		if sz.x > 1.0 and sz.y > 1.0:
			return sz
	return Vector2(640.0, 360.0)


func _bottom_anchor_y() -> float:
	var vh: float = _viewport_size().y
	var bottom_y: float = vh - 60.0
	var parent_node: Node = get_parent()
	if parent_node != null:
		var mp: MultiplayerHud = parent_node.get_node_or_null("MultiplayerHud") as MultiplayerHud
		if mp != null and mp.is_visible_in_tree():
			var mp_top: float = vh + mp.offset_bottom - mp._panel_rect.size.y
			bottom_y = minf(bottom_y, mp_top - 8.0)
	return roundf(bottom_y)


func _compute_target_height() -> float:
	var max_log: float = LOG_MAX_EXPANDED if _expanded else LOG_MAX_COMPACT
	var log_h: float = LOG_MIN_H
	if _log.visible:
		var parsed: String = _log.get_parsed_text()
		var inner_w: float = PANEL_W - 24.0
		var content_h: float = 0.0
		for para: String in parsed.split("\n"):
			if para.is_empty():
				content_h += float(ChatFont.LINE_HEIGHT)
			else:
				var wrapped: PackedStringArray = ChatFont.wrap_lines(para, inner_w)
				content_h += float(maxi(wrapped.size(), 1)) * float(ChatFont.LINE_HEIGHT + 1)
		log_h = clampf(content_h + 4.0, LOG_MIN_H, max_log)
	var extra_hint: float = (HINT_H + 3.0) if _hint_visible else 0.0
	return roundf(HEADER_H + 6.0 + log_h + extra_hint + INPUT_H + 8.0)


func _sync_layout(snap: bool) -> void:
	_panel_h_target = _compute_target_height()
	if snap:
		_panel_h = _panel_h_target
	var ease_t: float = 1.0 - pow(1.0 - clampf(_open_t, 0.0, 1.0), 3.0)
	var slide_y: float = roundf((1.0 - ease_t) * 8.0)
	var bottom_y: float = _bottom_anchor_y() + slide_y
	var h: float = roundf(_panel_h)
	_panel_rect = Rect2(PANEL_LEFT, bottom_y - h, PANEL_W, h)

	# Header buttons (right-aligned)
	var hdr_y: float = _panel_rect.position.y + 5.0
	_close_rect = Rect2(_panel_rect.end.x - 19.0, hdr_y, 14.0, 14.0)
	_expand_rect = Rect2(_close_rect.position.x - 16.0, hdr_y, 14.0, 14.0)
	var badge: String = AdminCommands.mode_badge()
	if not badge.is_empty():
		var bw: float = float(PixelText.width(badge)) + 10.0
		_admin_rect = Rect2(_expand_rect.position.x - bw - 3.0, hdr_y, bw, 14.0)
	else:
		_admin_rect = Rect2()
	_build_tab_rects()

	# Recessed input trough at bottom
	_input_rect = Rect2(_panel_rect.position.x + 8.0, _panel_rect.end.y - INPUT_H - 6.0, _panel_rect.size.x - 16.0, INPUT_H)
	_send_rect = Rect2(_input_rect.end.x - 18.0, _input_rect.position.y + 2.0, 15.0, 15.0)

	# Content & frame opacity scaled harmoniously with GameSettings.chat_opacity() (30%..100%)
	var op: float = _chat_opacity()
	var op_n: float = _chat_opacity_norm(op)
	var frame_mod: float = lerpf(0.62, 1.0, op_n)
	var text_op: float = lerpf(0.84, 1.0, op_n)
	_frame_canvas.modulate.a = frame_mod
	var content_a: float = clampf((ease_t - 0.22) / 0.78, 0.0, 1.0)

	# Position RichTextLabel
	var log_top: float = _panel_rect.position.y + HEADER_H + 6.0
	var hint_space: float = (HINT_H + 3.0) if _hint_visible else 0.0
	var log_bottom: float = _input_rect.position.y - 3.0 - hint_space
	_log.position = Vector2(_panel_rect.position.x + 10.0, log_top)
	_log.size = Vector2(_panel_rect.size.x - 18.0, maxf(log_bottom - log_top, 14.0))
	_log.modulate.a = content_a * text_op

	# Jump-to-bottom pill
	var jump_w: float = 36.0
	_jump_rect = Rect2(_log.position.x + _log.size.x - jump_w - 8.0, _log.position.y + _log.size.y - 14.0, jump_w, 12.0)

	# Position LineEdit cleanly centered inside recessed input well
	var char_pad: float = 28.0 if _field.text.length() > int(float(Chat.LIMIT) * 0.72) else 0.0
	_field.position = Vector2(_input_rect.position.x + 19.0, _input_rect.position.y + 1.0)
	_field.size = Vector2(maxf(_input_rect.size.x - 40.0 - char_pad, 40.0), INPUT_H - 3.0)
	_field.modulate.a = content_a * text_op

	# Position Autocomplete leaf above input well
	if not _suggestions.is_empty() and _suggest_t > 0.02:
		var rows_n: int = mini(_suggestions.size(), SUGGEST_MAX)
		var sh: float = float(rows_n) * 14.0 + 10.0
		var sw: float = _input_rect.size.x
		var sy: float = _input_rect.position.y - sh - 3.0 + roundf((1.0 - _suggest_t) * 4.0)
		_suggest_rect = Rect2(_input_rect.position.x, sy, sw, sh)
		_suggest_hit.visible = _is_open
		_suggest_hit.position = _suggest_rect.position
		_suggest_hit.size = _suggest_rect.size
	else:
		_suggest_rect = Rect2()
		_suggest_hit.visible = false


func _build_tab_rects() -> void:
	_tab_hits.clear()
	var x: float = _panel_rect.position.x + 7.0
	var y: float = _panel_rect.position.y + 4.0
	var right_edge: float = _admin_rect.position.x if _admin_rect.size.x > 0.0 else _expand_rect.position.x
	var max_x: float = right_edge - 20.0
	var entries: Array[Dictionary] = _channel_entries()
	for entry: Dictionary in entries:
		var lbl: String = String(entry["label"])
		var w: float = float(PixelText.width(lbl)) + 21.0
		if int(entry["unread"]) > 0 and String(entry["key"]) != _key:
			w += 7.0
		if x + w > max_x and not _tab_hits.is_empty():
			break
		_tab_hits.append({
			"key": String(entry["key"]),
			"label": lbl,
			"icon": String(entry["icon"]),
			"accent": entry["accent"] as Color,
			"unread": int(entry["unread"]),
			"rect": Rect2(roundf(x), roundf(y), roundf(w), 16.0),
		})
		x += w + 3.0
	# '+' New Whisper button right after tabs
	if x + 15.0 <= right_edge - 3.0:
		_tab_hits.append({
			"key": "direct",
			"label": "",
			"icon": "plus",
			"accent": COL_LILAC,
			"unread": 0,
			"rect": Rect2(roundf(x), roundf(y), 15.0, 16.0),
		})


func _channel_entries() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	list.append({
		"key": "game",
		"label": "SPIEL",
		"icon": "game",
		"accent": COL_TEAL,
		"unread": int(_unread.get("game", 0)),
	})
	var crew_n: int = NetworkManager.roster().size() if NetworkManager.is_multiplayer_session() else 0
	var grp_label: String = ("GRUPPE %d" % crew_n) if crew_n > 1 else "GRUPPE"
	list.append({
		"key": "group",
		"label": grp_label,
		"icon": "group",
		"accent": COL_GOLD,
		"unread": int(_unread.get("group", 0)),
	})
	# Put active DM first if any, then other known DM contacts (up to 2 pills so header stays crisp)
	var dm_keys: Array[String] = []
	if _key != "game" and _key != "group" and _key != "direct":
		dm_keys.append(_key)
	for ck: Variant in Chat.contacts.keys():
		var k: String = String(ck)
		if not dm_keys.has(k):
			dm_keys.append(k)
	for idx: int in mini(dm_keys.size(), 2):
		var dk: String = dm_keys[idx]
		var cname: String = String(Chat.contacts.get(dk, "DIREKT")).left(8).to_upper()
		list.append({
			"key": dk,
			"label": cname,
			"icon": "direct",
			"accent": COL_LILAC,
			"unread": int(_unread.get(dk, 0)),
		})
	return list


func _sync_bud_hit(show_bud: bool) -> void:
	if not show_bud:
		_bud_hit.visible = false
		return
	var by: float = _bottom_anchor_y() - 22.0
	_bud_rect = Rect2(4.0, by, 34.0, 18.0)
	_bud_hit.position = _bud_rect.position
	_bud_hit.size = _bud_rect.size
	_bud_hit.visible = true


# ------------------------------------------------------------------ Input Handling

func _input(event: InputEvent) -> void:
	if _is_open:
		if event.is_action_pressed("ui_cancel"):
			close_chat()
			get_viewport().set_input_as_handled()
			return
		var key: InputEventKey = event as InputEventKey
		if key != null and key.pressed:
			if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
				close_chat()
				get_viewport().set_input_as_handled()
				return
			if key.keycode == KEY_TAB or key.physical_keycode == KEY_TAB:
				if not _suggestions.is_empty():
					_accept_suggestion(_suggest_sel)
				else:
					_cycle_channel(-1 if key.shift_pressed else 1)
				get_viewport().set_input_as_handled()
				return
			if key.keycode == KEY_UP or key.physical_keycode == KEY_UP:
				if not _suggestions.is_empty():
					_suggest_sel = posmod(_suggest_sel - 1, _suggestions.size())
					Sfx.ui(self, "ui_click", -12.0)
					_overlay_canvas.queue_redraw()
				else:
					_step_history(-1)
				get_viewport().set_input_as_handled()
				return
			if key.keycode == KEY_DOWN or key.physical_keycode == KEY_DOWN:
				if not _suggestions.is_empty():
					_suggest_sel = posmod(_suggest_sel + 1, _suggestions.size())
					Sfx.ui(self, "ui_click", -12.0)
					_overlay_canvas.queue_redraw()
				else:
					_step_history(1)
				get_viewport().set_input_as_handled()
				return
			if key.keycode == KEY_PAGEUP or key.physical_keycode == KEY_PAGEUP:
				_scroll_log(-36.0)
				get_viewport().set_input_as_handled()
				return
			if key.keycode == KEY_PAGEDOWN or key.physical_keycode == KEY_PAGEDOWN:
				_scroll_log(36.0)
				get_viewport().set_input_as_handled()
				return
			if (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER) and not key.echo:
				if _field.text.strip_edges().is_empty() and not _busy:
					close_chat()
					get_viewport().set_input_as_handled()
					return
		return

	# Closed state: Enter or '/' opens the Whisper Vine
	var open_key: InputEventKey = event as InputEventKey
	if open_key == null or not open_key.pressed or open_key.echo:
		return
	if InputManager.ui_blocking or InputManager.build_open or InputManager.freecam_open or get_tree().paused:
		return
	if open_key.keycode in [KEY_ENTER, KEY_KP_ENTER] or open_key.unicode == 47:
		open_chat()
		var target_unread: String = _pick_priority_unread()
		if not target_unread.is_empty():
			_select(target_unread)
		if open_key.unicode == 47:
			_field.text = "/"
			_field.caret_column = 1
			_on_field_changed("/")
		get_viewport().set_input_as_handled()


func _unhandled_input(_event: InputEvent) -> void:
	if _is_open:
		get_viewport().set_input_as_handled()


func _on_shell_input(event: InputEvent) -> void:
	if not _is_open:
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = _shell.get_global_mouse_position()
		var inside_panel: bool = _panel_rect.has_point(p)
		var inside_suggest: bool = not _suggestions.is_empty() and _suggest_rect.has_point(p)
		if not inside_panel and not inside_suggest:
			_shell.accept_event()
			close_chat()


func _on_hit_input(event: InputEvent) -> void:
	if not _is_open:
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		var p: Vector2 = motion.position
		var next_hover: String = ""
		if _close_rect.has_point(p):
			next_hover = "close"
		elif _expand_rect.has_point(p):
			next_hover = "expand"
		elif _admin_rect.size.x > 0.0 and _admin_rect.has_point(p):
			next_hover = "admin"
		elif _send_rect.has_point(p):
			next_hover = "send"
		else:
			for tab: Dictionary in _tab_hits:
				if (tab["rect"] as Rect2).has_point(p):
					next_hover = "tab:" + String(tab["key"])
					break
		if next_hover != _hover_id:
			_hover_id = next_hover
			GameCursor.set_hint(self, &"click" if not next_hover.is_empty() else &"")
			_frame_canvas.queue_redraw()
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.pressed:
		var p: Vector2 = mb.position
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and _panel_rect.has_point(p):
			_scroll_log(-24.0)
			_hit_layer.accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and _panel_rect.has_point(p):
			_scroll_log(24.0)
			_hit_layer.accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if _close_rect.has_point(p):
				_hit_layer.accept_event()
				close_chat()
				return
			if _expand_rect.has_point(p):
				_expanded = not _expanded
				Sfx.ui(self, "ui_click", -8.0)
				_hit_layer.accept_event()
				_sync_layout(false)
				_frame_canvas.queue_redraw()
				return
			if _admin_rect.size.x > 0.0 and _admin_rect.has_point(p):
				Sfx.ui(self, "ui_click", -8.0)
				_spawn_spores(_admin_rect.get_center(), COL_GOLD, 6)
				_hit_layer.accept_event()
				_submit("/admin")
				return
			if _send_rect.has_point(p):
				_hit_layer.accept_event()
				_submit(_field.text)
				return
			for tab: Dictionary in _tab_hits:
				if (tab["rect"] as Rect2).has_point(p):
					var tk: String = String(tab["key"])
					Sfx.ui(self, "ui_click", -9.0)
					_select(tk)
					_spawn_spores((tab["rect"] as Rect2).get_center(), _accent, 5)
					_hit_layer.accept_event()
					return
			if _input_rect.has_point(p):
				_field.grab_focus()
				_hit_layer.accept_event()
				return
			if not _panel_rect.has_point(p) and (not _suggest_hit.visible or not _suggest_rect.has_point(p)):
				_hit_layer.accept_event()
				close_chat()


func _on_suggest_input(event: InputEvent) -> void:
	if not _is_open or _suggestions.is_empty():
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		var row: int = clampi(int((motion.position.y - 5.0) / 14.0), 0, mini(_suggestions.size(), SUGGEST_MAX) - 1)
		if row != _suggest_hover:
			_suggest_hover = row
			_suggest_sel = row
			GameCursor.set_hint(self, &"click")
			_overlay_canvas.queue_redraw()
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		var row: int = clampi(int((mb.position.y - 5.0) / 14.0), 0, mini(_suggestions.size(), SUGGEST_MAX) - 1)
		_accept_suggestion(row)
		_suggest_hit.accept_event()


func _on_jump_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_scroll_to_bottom()
		Sfx.ui(self, "ui_click", -10.0)
		_jump_hit.accept_event()


func _on_bud_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		var target_key: String = _pick_priority_unread()
		open_chat()
		if not target_key.is_empty():
			_select(target_key)
		_bud_hit.accept_event()


func _on_meta_clicked(meta: Variant) -> void:
	var tag: String = String(meta)
	if tag.begins_with("whisper:"):
		var target_name: String = tag.trim_prefix("whisper:")
		if not target_name.is_empty():
			_field.text = "/msg %s " % target_name
			_field.grab_focus()
			_field.caret_column = _field.text.length()
			_on_field_changed(_field.text)
			Sfx.ui(self, "ui_click", -10.0)


func _scroll_log(delta_px: float) -> void:
	var sb: VScrollBar = _log.get_v_scroll_bar()
	if sb != null and sb.visible:
		sb.value = clampf(sb.value + delta_px, 0.0, maxf(sb.max_value - sb.page, 0.0))
		_update_scroll_state()
		_frame_canvas.queue_redraw()


func _scroll_to_bottom() -> void:
	var sb: VScrollBar = _log.get_v_scroll_bar()
	if sb != null:
		sb.value = sb.max_value
	_scrolled_up = false
	_scrolled_unread = false
	_jump_hit.visible = false
	_frame_canvas.queue_redraw()


# ------------------------------------------------------------------ Channels, History & Autocomplete

func _cycle_channel(dir: int) -> void:
	var keys: Array[String] = []
	for entry: Dictionary in _channel_entries():
		keys.append(String(entry["key"]))
	if keys.is_empty():
		return
	var idx: int = keys.find(_key)
	var next_i: int = posmod((0 if idx < 0 else idx) + dir, keys.size())
	Sfx.ui(self, "ui_click", -9.0)
	_select(keys[next_i])


func _direct(key: String, title: String) -> void:
	Chat.contacts[key] = title
	_select(key)
	if key.begins_with("dm/"):
		Chat.join_channel(key)


func _select(key: String) -> void:
	_hide_hint()
	_drafts[_key] = _field.text
	_key = key
	_unread.erase(key)
	_hist_idx = -1
	_field.text = String(_drafts.get(key, ""))
	if key == "direct" and _field.text.is_empty():
		_field.text = "/msg "
	_field.grab_focus()
	_field.caret_column = _field.text.length()
	_on_field_changed(_field.text)
	_refresh()
	_scroll_to_bottom.call_deferred()


func _step_history(dir: int) -> void:
	if _sent_history.is_empty():
		return
	if _hist_idx < 0:
		if dir > 0:
			return
		_hist_saved_draft = _field.text
		_hist_idx = _sent_history.size() - 1
	else:
		_hist_idx += dir
	if _hist_idx < 0:
		_hist_idx = 0
	elif _hist_idx >= _sent_history.size():
		_hist_idx = -1
		_field.text = _hist_saved_draft
		_field.caret_column = _field.text.length()
		_on_field_changed(_field.text)
		return
	_field.text = _sent_history[_hist_idx]
	_field.caret_column = _field.text.length()
	_on_field_changed(_field.text)


func _on_field_changed(text: String) -> void:
	_rebuild_suggestions(text)
	_frame_canvas.queue_redraw()


func _rebuild_suggestions(text: String) -> void:
	_suggestions.clear()
	_suggest_hover = -1
	var trimmed: String = text.lstrip(" ")
	if trimmed.begins_with("/"):
		var parts: PackedStringArray = trimmed.split(" ", true, 1)
		var cmd: String = parts[0].to_lower()
		var admin_ok: bool = AdminCommands.can_use_local()
		if parts.size() == 1:
			if cmd == "/":
				var base_limit: int = SUGGEST_MAX - 1 if admin_ok else SUGGEST_MAX
				for idx: int in mini(COMMANDS.size(), base_limit):
					var spec: Dictionary = COMMANDS[idx]
					var c: String = String(spec["cmd"])
					_suggestions.append({
						"insert": c + ("" if c in ["/ort", "/clear", "/help"] else " "),
						"label": String(spec["usage"]),
						"desc": String(spec["desc"]),
						"kind": "cmd",
					})
				if admin_ok:
					_suggestions.append({
						"insert": "/admin ",
						"label": "/admin [spieler|welt|multiplayer]",
						"desc": "Admin-Befehle",
						"kind": "admin",
					})
			else:
				for spec: Dictionary in COMMANDS:
					var c: String = String(spec["cmd"])
					if c.begins_with(cmd) and c != cmd:
						_suggestions.append({
							"insert": c + ("" if c in ["/ort", "/clear", "/help"] else " "),
							"label": String(spec["usage"]),
							"desc": String(spec["desc"]),
							"kind": "cmd",
						})
				if admin_ok:
					_append_unique_suggestions(AdminCommands.autocomplete(trimmed, get_tree()))
		elif cmd in ["/msg", "/dm", "/w", "/message", "/mesage"]:
			var query: String = parts[1].strip_edges().to_lower()
			if not query.contains(" "):
				for candidate: Dictionary in _known_players():
					var pname: String = String(candidate["name"])
					if query.is_empty() or pname.to_lower().begins_with(query):
						_suggestions.append({
							"insert": cmd + " " + pname + " ",
							"label": pname,
							"desc": String(candidate["source"]),
							"kind": "player",
						})
		elif admin_ok:
			_append_unique_suggestions(AdminCommands.autocomplete(trimmed, get_tree()))
	else:
		# Support @Name mention autocomplete at end of message
		var at_pos: int = text.rfind("@")
		if at_pos >= 0 and (at_pos == 0 or text[at_pos - 1] == " "):
			var mention_q: String = text.substr(at_pos + 1)
			if not mention_q.contains(" "):
				var qlow: String = mention_q.to_lower()
				for candidate: Dictionary in _known_players():
					var pname: String = String(candidate["name"])
					if qlow.is_empty() or pname.to_lower().begins_with(qlow):
						_suggestions.append({
							"insert": text.left(at_pos) + "@" + pname + " ",
							"label": "@" + pname,
							"desc": String(candidate["source"]),
							"kind": "player",
						})
	if _suggestions.size() > SUGGEST_MAX:
		_suggestions.resize(SUGGEST_MAX)
	_suggest_sel = clampi(_suggest_sel, 0, maxi(_suggestions.size() - 1, 0))


func _append_unique_suggestions(items: Array[Dictionary]) -> void:
	var seen: Dictionary = {}
	for existing: Dictionary in _suggestions:
		seen[String(existing.get("label", "")).to_lower()] = true
	for item: Dictionary in items:
		var lbl_key: String = String(item.get("label", "")).to_lower()
		if not lbl_key.is_empty() and not seen.has(lbl_key):
			seen[lbl_key] = true
			_suggestions.append(item)


func _known_players() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen: Dictionary = {}
	var my_id: int = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	for player: Dictionary in NetworkManager.roster():
		if int(player.get("id", 0)) == my_id:
			continue
		var pname: String = String(player.get("name", ""))
		if not pname.is_empty() and not seen.has(pname.to_lower()):
			seen[pname.to_lower()] = true
			out.append({"name": pname, "source": "Gruppe"})
	for fr: Dictionary in CloudSession.friends_cache:
		if int(fr.get("state", 0)) != 0:
			continue
		var fname: String = String(fr.get("username", ""))
		if not fname.is_empty() and not seen.has(fname.to_lower()):
			seen[fname.to_lower()] = true
			var online: bool = bool(fr.get("online", false))
			out.append({"name": fname, "source": "Freund · Online" if online else "Freund"})
	for ck: Variant in Chat.contacts.keys():
		var cname: String = String(Chat.contacts[ck])
		if not cname.is_empty() and not seen.has(cname.to_lower()):
			seen[cname.to_lower()] = true
			out.append({"name": cname, "source": "Flüstern"})
	return out


func _accept_suggestion(index: int) -> void:
	if index < 0 or index >= _suggestions.size():
		return
	var chosen: Dictionary = _suggestions[index]
	_field.text = String(chosen["insert"])
	_field.grab_focus()
	_field.caret_column = _field.text.length()
	Sfx.ui(self, "ui_click", -10.0)
	_on_field_changed(_field.text)


# ------------------------------------------------------------------ Rendering Messages

func _accent_for(key: String) -> Color:
	if key == "game":
		return COL_TEAL
	if key == "group":
		return COL_GOLD
	return COL_LILAC


func _author_color(key: String, author: String, own: bool) -> Color:
	if own:
		return COL_TEXT_SOFT
	if key == "group":
		for entry: Dictionary in NetworkManager.roster():
			if String(entry.get("name", "")).nocasecmp_to(author) == 0:
				var slot: int = clampi(int(entry.get("slot", 0)), 0, MultiplayerHud.PLAYER_TONES.size() - 1)
				return MultiplayerHud.PLAYER_TONES[slot]
	return _accent_for(key)


func _format_stamp(stamp: String) -> String:
	var t_idx: int = stamp.find("T")
	if t_idx >= 0 and stamp.length() >= t_idx + 6:
		return stamp.substr(t_idx + 1, 5)
	return ""


func _is_mention(text: String) -> bool:
	var my_name: String = String(GameSettings.get_value("player_name"))
	var folded: String = text.to_lower()
	if not my_name.is_empty() and folded.contains("@" + my_name.to_lower()):
		return true
	if not CloudSession.username.is_empty() and folded.contains("@" + CloudSession.username.to_lower()):
		return true
	return false


func _on_chat_changed() -> void:
	if _scrolled_up and _is_open:
		_scrolled_unread = true
	_refresh()


func _refresh() -> void:
	var direct: bool = _key != "group" and _key != "game"
	_accent = _accent_for(_key)
	_field.add_theme_color_override("caret_color", _accent)
	_field.add_theme_color_override("selection_color", Color(_accent, 0.28))

	var recipient: String = String(Chat.contacts.get(_key, ""))
	if _key == "direct":
		_field.placeholder_text = "/msg Name Nachricht …"
	elif not recipient.is_empty():
		_field.placeholder_text = "An %s flüstern …" % recipient.left(16)
	elif _key == "group":
		_field.placeholder_text = "An Gruppe … (/ Befehle · TAB · ESC)"
	else:
		_field.placeholder_text = "Schreiben … (/ Befehle · TAB · ESC)"

	if not _is_open and not _shell.visible:
		return

	_log.clear()
	var cleared_min: int = int(_cleared_order.get(_key, 0))
	var rows: Array[Dictionary] = Chat.lines.filter(func(row: Dictionary) -> bool:
		return String(row.key) == _key and int(row.order) > cleared_min
	)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.order) < int(b.order) if String(a.stamp) == String(b.stamp) else String(a.stamp) < String(b.stamp)
	)

	var line_count: int = 0
	var last_author: String = ""
	for row: Dictionary in rows:
		if line_count > 0:
			_log.add_text("\n")
		var own: bool = bool(row.own)
		var author: String = String(row.author)
		var body: String = String(row.text)
		var time_str: String = _format_stamp(String(row.stamp))
		var is_action: bool = body.begins_with("* ") and body.ends_with(" *") and body.length() > 4
		var is_loc: bool = body.begins_with("[Ort] ")
		var mentioned: bool = not own and _is_mention(body)

		if not time_str.is_empty():
			_log.push_color(COL_DIM)
			_log.add_text(time_str + " ")
			_log.pop()

		if mentioned:
			_log.push_color(COL_GOLD)
			_log.add_text("★ ")
			_log.pop()

		if is_action:
			_log.push_color(COL_ME.lerp(_accent, 0.25))
			_log.add_text("* %s %s *" % ["Du" if own else author, body.substr(2, body.length() - 4)])
			_log.pop()
		else:
			var display_author: String = "Du" if own else author
			var a_col: Color = _author_color(_key, author, own)
			var grouped: bool = display_author == last_author and not mentioned
			if not grouped:
				if not own:
					_log.push_meta("whisper:" + author)
				_log.push_color(a_col)
				_log.add_text(display_author)
				_log.pop()
				if not own:
					_log.pop()
				_log.push_color(COL_MUTED)
				_log.add_text(" · ")
				_log.pop()
			else:
				_log.push_color(Color(a_col, 0.45))
				_log.add_text("  · ")
				_log.pop()
			if is_loc:
				_log.push_color(COL_TEAL)
				_log.add_text("→ ")
				_log.pop()
				_log.push_color(COL_GOLD)
				_log.add_text(body.trim_prefix("[Ort] "))
				_log.pop()
			else:
				_log.push_color(COL_GOLD.lerp(COL_TEXT, 0.45) if mentioned else COL_TEXT)
				_log.add_text(body)
				_log.pop()
			last_author = display_author
		line_count += 1

	# Append any local /help or status notes for this channel
	var notes: Array = _local_notes.get(_key, []) as Array
	for note: Variant in notes:
		var nd: Dictionary = note as Dictionary
		if line_count > 0:
			_log.add_text("\n")
		_log.push_color(nd.get("color", COL_GOLD) as Color)
		_log.add_text(String(nd.get("text", "")))
		_log.pop()
		line_count += 1

	if line_count == 0:
		_log.push_color(COL_MUTED)
		if _key == "direct":
			_log.add_text("/msg Name öffnet ein Flüstergespräch.")
		elif _key == "group" and not NetworkManager.is_multiplayer_session():
			_log.add_text("Tritt einer Koop-Runde bei, um mit Gefährten zu sprechen.")
		elif _key == "game" and not CloudSession.is_logged_in():
			_log.add_text("Melde dich im Launcher an, um im Spielchat mitzuschreiben.")
		else:
			_log.add_text("Noch still hier … tippe eine Nachricht oder /help.")
		_log.pop()

	_log.visible = not _log.get_parsed_text().is_empty()
	_sync_layout.call_deferred(false)
	_frame_canvas.queue_redraw()


# ------------------------------------------------------------------ Commands & Submit

func _recipient_args(value: String) -> PackedStringArray:
	var longest: String = ""
	var folded: String = value.to_lower()
	for player: Dictionary in NetworkManager.roster():
		var candidate: String = String(player.name).to_lower()
		if candidate.length() > longest.length() and (folded == candidate or folded.begins_with(candidate + " ")):
			longest = candidate
	if longest.is_empty():
		return value.split(" ", false, 1)
	return PackedStringArray([value.left(longest.length()), value.substr(longest.length()).strip_edges()])


func _current_location_text() -> String:
	var tree: SceneTree = get_tree()
	var world: Node = tree.get_first_node_in_group("world") if tree != null else null
	var director: ZoneDirector = world.call("director") as ZoneDirector if world != null and world.has_method("director") else null
	var local_player: Node2D = null
	for p: Player in Player.all:
		if is_instance_valid(p) and p.is_inside_tree() and p.is_multiplayer_authority():
			local_player = p
			break
	var label: String = "Altmark"
	if director != null and director.atlas != null and local_player != null:
		var peer: int = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
		var zone_id: StringName = director.player_zone.get(peer, &"") as StringName
		if zone_id == &"":
			zone_id = director.atlas.zone_at(director.continent_id, local_player.global_position)
		var zone: Atlas.Zone = director.atlas.zone(zone_id)
		if zone != null:
			label = zone.name
			var here: StringName = director.atlas.place_at(director.continent_id, local_player.global_position)
			for place: Atlas.Place in zone.places:
				if place.id == here:
					label += " · " + place.name
					break
	var total_mins: int = int(TimeManager.time_of_day * 1440.0) % 1440
	var hh: int = total_mins / 60
	var mm: int = total_mins % 60
	return "[Ort] %s (Tag %d, %02d:%02d)" % [label, TimeManager.day + 1, hh, mm]


func _show_hint(msg: String, is_error: bool = true, auto_hide: float = 0.0) -> void:
	_hint.text = msg
	_hint_visible = not msg.is_empty()
	_hint_is_error = is_error
	_hint_shake = 1.0 if is_error else 0.0
	_hint_timer = auto_hide
	if is_error and _is_open:
		Sfx.ui(self, "ui_back", -10.0)
	_sync_layout(false)
	_frame_canvas.queue_redraw()


func _hide_hint() -> void:
	_hint.text = ""
	_hint_visible = false
	_hint_shake = 0.0
	_hint_timer = 0.0


func _push_local_note(key: String, text: String, color: Color = COL_GOLD) -> void:
	var arr: Array = _local_notes.get(key, []) as Array
	arr.append({"text": text, "color": color})
	if arr.size() > 16:
		arr = arr.slice(arr.size() - 16)
	_local_notes[key] = arr


func _record_sent_history(raw: String) -> void:
	if raw.is_empty():
		return
	if _sent_history.is_empty() or _sent_history[_sent_history.size() - 1] != raw:
		_sent_history.append(raw)
		if _sent_history.size() > HISTORY_LIMIT:
			_sent_history.pop_front()
	_hist_idx = -1


func _submit(raw: String) -> void:
	if _busy or raw.strip_edges().is_empty():
		return
	_busy = true
	var trimmed_raw: String = raw.strip_edges()
	_record_sent_history(trimmed_raw)
	var key: String = _key
	var body: String = trimmed_raw
	var error: String = ""
	var local_only: bool = false

	if body.begins_with("/"):
		var split: PackedStringArray = body.split(" ", false, 1)
		var cmd: String = split[0].to_lower()
		body = split[1].strip_edges() if split.size() > 1 else ""
		if cmd == "/r":
			key = Chat.reply_to
			if key.is_empty():
				error = "Du hast noch keine Direktnachricht erhalten."
		elif cmd in ["/msg", "/mesage", "/message", "/dm", "/w"]:
			var args: PackedStringArray = _recipient_args(body)
			if args.is_empty():
				error = "Gib /msg Name oder /msg Name Nachricht ein."
			else:
				var target: Dictionary = await Chat.resolve(args[0])
				error = String(target.get("error", ""))
				key = String(target.get("key", ""))
				if error.is_empty():
					Chat.contacts[key] = String(target.name)
				body = args[1].strip_edges() if args.size() > 1 else ""
		elif cmd in ["/g", "/gruppe"]:
			key = "group"
		elif cmd in ["/s", "/spiel"]:
			key = "game"
		elif cmd in ["/ort", "/pos"]:
			body = _current_location_text()
		elif cmd == "/me":
			if body.is_empty():
				error = "Gib /me <Aktion> ein, z.B. /me winkt."
			else:
				body = "* %s *" % body
		elif cmd == "/clear":
			var max_order: int = 0
			for row: Dictionary in Chat.lines:
				if String(row.key) == _key:
					max_order = maxi(max_order, int(row.order))
			_cleared_order[_key] = max_order
			_local_notes.erase(_key)
			local_only = true
		elif cmd in ["/help", "/hilfe"]:
			_push_local_note(_key, "Befehle: /msg Name · /r · /g · /s · /ort · /me · /clear", COL_GOLD)
			_push_local_note(_key, "Tasten: TAB Kanal/Vorschlag · ↑↓ Verlauf · ESC Zu", COL_TEAL)
			if AdminCommands.can_use_local():
				_push_local_note(_key, "★ Admin: /admin für Spieler-, Welt- & Koop-Befehle.", COL_GOLD)
			local_only = true
		elif AdminCommands.is_admin_command(cmd) and AdminCommands.can_use_local():
			var adm_res: Dictionary = Chat.run_admin_command(trimmed_raw)
			if not bool(adm_res.get("pending", false)):
				var adm_lines: PackedStringArray = adm_res.get("lines", PackedStringArray()) as PackedStringArray
				if bool(adm_res.get("ok", false)):
					_on_admin_reply(true, adm_lines)
				else:
					error = adm_lines[0] if not adm_lines.is_empty() else "Befehl fehlgeschlagen."
					if adm_lines.size() > 1:
						for idx: int in range(1, adm_lines.size()):
							_push_local_note(_key, adm_lines[idx], COL_ROSE)
						_refresh()
			local_only = true
		else:
			error = "Unbekannter Befehl. Verwende /msg, /r, /ort, /me oder /help."
	elif key == "direct":
		error = "Wähle zuerst einen Empfänger mit /msg Name."

	if error.is_empty() and not local_only:
		if key != _key:
			_field.clear()
			_select(key)
		if not body.is_empty():
			error = await Chat.send(key, body)
			if error.is_empty():
				Sfx.ui(self, "ui_confirm", -12.0)
				_spawn_spores(_send_rect.get_center(), _accent, 9)
				_push_ambient_line(key, "Du", body, true)
		elif key.begins_with("dm/"):
			Chat.join_channel(key)

	if error.is_empty():
		_hide_hint()
		_suggestions.clear()
		if local_only:
			_field.clear()
			_refresh()
		elif _key == key and (_field.text == raw or _field.text.is_empty()):
			_field.clear()
		_sync_layout.call_deferred(false)
		_scroll_to_bottom.call_deferred()
	else:
		_show_hint(error, true, 5.0)
		if _field.text.is_empty():
			_field.text = body
	_busy = false
	if _is_open:
		_field.grab_focus()
		_field.caret_column = _field.text.length()


func _on_admin_reply(ok: bool, out_lines: PackedStringArray) -> void:
	if out_lines.is_empty():
		return
	if ok:
		for line: String in out_lines:
			_push_local_note(_key, line, COL_GOLD)
		Sfx.ui(self, "ui_confirm", -11.0)
		if _is_open:
			_spawn_spores(_send_rect.get_center(), COL_GOLD, 9)
		_refresh()
		_scroll_to_bottom.call_deferred()
	else:
		_show_hint(out_lines[0], true, 5.0)
		if out_lines.size() > 1:
			for i: int in range(1, out_lines.size()):
				_push_local_note(_key, out_lines[i], COL_ROSE)
			_refresh()


func _on_system_broadcast(kind: String, text: String) -> void:
	var clean: String = text.strip_edges()
	if clean.is_empty():
		return
	var is_announce: bool = kind == "announce"
	var col: Color = COL_GOLD if is_announce else COL_TEAL
	var formatted: String = ("★ [ANKÜNDIGUNG] " + clean) if is_announce else ("· " + clean)
	_push_local_note(_key, formatted, col)
	if _key != "group" and NetworkManager.is_multiplayer_session():
		_push_local_note("group", formatted, col)
	_push_ambient_line("group" if is_announce else _key, "★ ANKÜNDIGUNG" if is_announce else "SYSTEM", clean, false)
	if is_announce:
		Sfx.ui(self, "ui_confirm", -9.0)
		var tree: SceneTree = get_tree()
		if tree != null:
			HudNotices.post(tree, "big", "admin_announce", {
				"header": "ANKÜNDIGUNG",
				"title": clean.left(44).to_upper(),
				"sub": "",
				"color": TownBanner.NIGHT_CLOTH,
			})
	_refresh()
	_ambient_canvas.queue_redraw()


# ------------------------------------------------------------------ Incoming & Ambient Feed

func _incoming(key: String, author: String) -> void:
	var latest_text: String = ""
	for i: int in range(Chat.lines.size() - 1, -1, -1):
		if String(Chat.lines[i].key) == key:
			latest_text = String(Chat.lines[i].text)
			break
	if not latest_text.is_empty():
		_push_ambient_line(key, author, latest_text, false)

	if _is_open and key == _key:
		if _scrolled_up:
			_scrolled_unread = true
		_frame_canvas.queue_redraw()
		return

	_unread[key] = int(_unread.get(key, 0)) + 1
	if not _is_open and key != "game":
		var now_ms: int = Time.get_ticks_msec()
		if now_ms - _last_chime_msec >= 1400:
			_last_chime_msec = now_ms
			Sfx.ui(self, "ui_click", -11.0)
	_refresh()
	_ambient_canvas.queue_redraw()


func _push_ambient_line(key: String, author: String, text: String, own: bool) -> void:
	_ambient_rows.append({
		"key": key,
		"author": author,
		"text": text,
		"own": own,
		"born": _time,
		"accent": _accent_for(key),
	})
	while _ambient_rows.size() > AMBIENT_MAX:
		_ambient_rows.pop_front()


func _unread_priority_count() -> int:
	var total: int = 0
	for k: Variant in _unread.keys():
		var ks: String = String(k)
		if ks != "game":
			total += int(_unread[k])
	return total


func _pick_priority_unread() -> String:
	if not Chat.reply_to.is_empty() and int(_unread.get(Chat.reply_to, 0)) > 0:
		return Chat.reply_to
	for k: Variant in _unread.keys():
		var ks: String = String(k)
		if ks != "game" and ks != "group" and int(_unread[k]) > 0:
			return ks
	if int(_unread.get("group", 0)) > 0:
		return "group"
	return ""


func _check_target() -> void:
	if _key.begins_with("peer/") and not Chat.contacts.has(_key):
		_select("group")


func _account_changed(_logged_in: bool) -> void:
	_key = "game"
	_field.clear()
	_drafts.clear()
	_unread.clear()
	_cleared_order.clear()
	_local_notes.clear()
	_ambient_rows.clear()
	_refresh()


# ------------------------------------------------------------------ Spore Particles & Audio

func _spawn_spores(origin: Vector2, col: Color, count: int) -> void:
	for i: int in count:
		var ang: float = randf_range(-PI * 0.92, -PI * 0.08)
		var spd: float = randf_range(12.0, 34.0)
		_spores.append({
			"pos": origin + Vector2(randf_range(-4.0, 4.0), randf_range(-2.0, 2.0)),
			"vel": Vector2(cos(ang) * spd, sin(ang) * spd),
			"age": 0.0,
			"life": randf_range(0.45, 0.95),
			"col": col.lerp(Color.WHITE, randf_range(0.0, 0.35)),
			"size": 2.0 if i % 3 == 0 else 1.0,
		})
	if _spores.size() > 36:
		_spores = _spores.slice(_spores.size() - 36)


func _play_rustle(stream: AudioStream, db: float, pitch: float) -> void:
	if stream == null or not is_inside_tree():
		return
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	p.pitch_scale = pitch
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


# ------------------------------------------------------------------ Drawing: Active Whisper Vine

func _draw_open(canvas: Control) -> void:
	if _open_t <= 0.01 or _panel_rect.size.x < 16.0:
		return
	var ease_t: float = 1.0 - pow(1.0 - clampf(_open_t, 0.0, 1.0), 3.0)
	var night: float = VineStyle.void_amount()
	var r: Rect2 = _panel_rect

	# 1. Left-edge organic root anchors tying the parchment into the screen margin (like HintCard / ClockVine)
	var bark_c: Color = VineStyle.BARK.lerp(VineStyle.BARK_VOID, night)
	var bark_l: Color = VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, night)
	for ry_off: float in [24.0, r.size.y - 16.0]:
		var ry: float = roundf(r.position.y + ry_off)
		var span_x: int = int(roundf(r.position.x * ease_t)) + 2
		for xi: int in span_x:
			var wy: float = roundf(ry + sin(float(xi) * 0.45 + ry_off) * 0.8)
			canvas.draw_rect(Rect2(float(xi), wy - 1.0, 1.0, 3.0), Color(COL_OUTLINE, ease_t))
			canvas.draw_rect(Rect2(float(xi), wy, 1.0, 1.0), Color(bark_l if xi % 2 == 0 else bark_c, ease_t))

	# 2. Textured 1:1 Organic Ragged Bark-Vellum Body (scaled cleanly to user's Chat-Sichtbarkeit 30..100%)
	var op: float = _chat_opacity()
	var fill_scale: float = clampf(op / maxf(_frame_canvas.modulate.a, 0.01), 0.30, 1.0)
	var body_a: float = clampf((ease_t - 0.08) / 0.92, 0.0, 1.0)
	ChatChrome.draw_vellum_body(canvas, r, body_a * fill_scale, night, _accent_live)

	# 3. Living Arching Crown Vine growing gracefully from x=0 across the top of the parchment
	var crown_y: float = r.position.y - 2.0
	var crown_end: float = r.end.x + 12.0
	var top_curve: Callable = func(x: float) -> float:
		var u: float = clampf(x / maxf(crown_end, 1.0), 0.0, 1.0)
		return crown_y - sin(u * PI) * 2.2 + sin(x * 0.055 + 0.5) * 1.1
	VineStyle.branch(canvas, 0.0, crown_end, top_curve, 4, night, 22.0, _time, ease_t)
	VineStyle.foliage(canvas, 0.0, crown_end - 4.0, top_curve, 7, 41, night, 22.0, _time, ease_t)

	# Delicate hanging bark threads from crown vine down into the parchment corners
	if body_a > 0.2:
		for tx: float in [r.position.x + 14.0, r.end.x - 16.0]:
			var cy: int = int(roundf(float(top_curve.call(tx)))) + 1
			for ty: int in range(cy, int(r.position.y) + 3):
				canvas.draw_rect(Rect2(roundf(tx), float(ty), 1.0, 1.0), Color(bark_l if ty % 2 == 0 else bark_c, body_a))

	# Organic tapering lower root curl (only ~58% of width, fading naturally into a tiny leaf sprout!)
	var low_y: float = r.end.y + 1.0
	var low_end: float = r.position.x + r.size.x * 0.56
	var low_curve: Callable = func(x: float) -> float:
		return low_y + sin(x * 0.06 + 2.3) * 1.2
	VineStyle.branch(canvas, 0.0, low_end, low_curve, 3, night, 42.0, _time, ease_t)
	VineStyle.foliage(canvas, 0.0, low_end - 4.0, low_curve, 3, 83, night, 42.0, _time, ease_t)

	# Soft glowing blossom tip at the crown vine's end
	var tip_x: float = crown_end * ease_t
	var tip_top: Vector2 = Vector2(roundf(tip_x), roundf(float(top_curve.call(tip_x))))
	VineStyle.glow(canvas, tip_top, 6.0, _accent_live, 0.62 * ease_t)
	canvas.draw_rect(Rect2(tip_top, Vector2.ONE), Color(VineStyle.PETAL, ease_t))

	if body_a <= 0.05:
		return

	# Delicate moss / void leaf sprigs on the bottom-right & top-right organic corners
	var lf_dark: Color = VineStyle.LEAF.lerp(VineStyle.LEAF_VOID, night)
	var lf_lit: Color = VineStyle.LEAF_LIGHT.lerp(VineStyle.LEAF_VOID_LIGHT, night)
	VineStyle.leaf(canvas, Vector2(r.end.x - 3.0, r.end.y - 3.0), 1, 1, 3, Color(lf_dark, body_a), Color(lf_lit, body_a))
	VineStyle.leaf(canvas, Vector2(r.position.x + 4.0, r.end.y - 4.0), -1, 1, 3, Color(lf_dark, body_a), Color(lf_lit, body_a))

	# 4. Inline Channel Ribbon Header
	var content_a: float = clampf((ease_t - 0.18) / 0.82, 0.0, 1.0)
	if content_a > 0.02:
		for tab: Dictionary in _tab_hits:
			var tr: Rect2 = tab["rect"] as Rect2
			var tk: String = String(tab["key"])
			var active: bool = tk == _key
			var hov: float = float(_tab_hover.get(tk, 0.0))
			var t_acc: Color = tab["accent"] as Color
			ChatChrome.draw_tab_pill(canvas, tr, active, hov, t_acc, content_a)
			var ic_x: float = tr.position.x + (2.0 if String(tab["label"]).is_empty() else 3.0)
			ChatChrome.draw_icon(canvas, String(tab["icon"]), Vector2(ic_x, tr.position.y + 2.0), active or hov > 0.35, content_a)
			var lbl: String = String(tab["label"])
			if not lbl.is_empty():
				var txt_c: Color = Color(t_acc.lerp(Color.WHITE, 0.35) if active else COL_MUTED.lerp(COL_TEXT, hov), content_a)
				PixelText.draw(canvas, lbl, Vector2i(int(tr.position.x + 15.0), int(tr.position.y + 4.0)), txt_c, Color(COL_OUTLINE, content_a))
			var unread_n: int = int(tab["unread"])
			if unread_n > 0 and not active:
				var pulse: float = 0.65 + 0.35 * sin(_time * 5.0)
				var pip: Vector2 = Vector2(tr.end.x - 5.0, tr.position.y + 6.0)
				VineStyle.glow(canvas, pip, 4.0, t_acc, 0.6 * pulse * content_a)
				canvas.draw_rect(Rect2(pip - Vector2(1, 1), Vector2(3, 3)), Color(COL_OUTLINE, content_a))
				canvas.draw_rect(Rect2(pip, Vector2(2, 2)), Color(t_acc.lightened(0.25), content_a))

		# Subtle dotted organic divider hairline + sliding glowing channel bloom
		var div_y: float = r.position.y + HEADER_H + 1.0
		canvas.draw_rect(Rect2(r.position.x + 8.0, div_y, r.size.x - 16.0, 1.0), Color(VineStyle.BARK_LIGHT, 0.32 * content_a))
		canvas.draw_rect(Rect2(r.position.x + 8.0, div_y + 1.0, r.size.x - 16.0, 1.0), Color(COL_OUTLINE, 0.48 * content_a))
		if _bloom_ready:
			ChatChrome.draw_bloom(canvas, _bloom_x, div_y - 3.0, _accent_live, 0.92 * content_a)

		# Right controls: optional Admin/Dev badge, Expand toggle & Close blossom
		var badge: String = AdminCommands.mode_badge()
		if not badge.is_empty() and _admin_rect.size.x > 4.0:
			var adm_hov: bool = _hover_id == "admin"
			var adm_col: Color = COL_GOLD if badge == "ADM" else COL_LILAC
			ChatChrome.draw_tab_pill(canvas, _admin_rect, adm_hov, 1.0 if adm_hov else 0.35, adm_col, content_a * 0.94)
			var pulse_a: float = 0.65 + 0.35 * sin(_time * 3.4)
			var dot_p: Vector2 = Vector2(_admin_rect.position.x + 3.0, _admin_rect.position.y + 6.0)
			canvas.draw_rect(Rect2(dot_p, Vector2(2.0, 2.0)), Color(adm_col.lightened(0.25), pulse_a * content_a))
			PixelText.draw(canvas, badge, Vector2i(int(_admin_rect.position.x + 7.0), int(_admin_rect.position.y + 4.0)), Color(adm_col.lerp(Color.WHITE, 0.35 if adm_hov else 0.15), content_a), Color(COL_OUTLINE, content_a))

		var exp_hov: bool = _hover_id == "expand"
		ChatChrome.draw_tab_pill(canvas, _expand_rect, false, 1.0 if exp_hov else 0.0, COL_GOLD, content_a * 0.88)
		ChatChrome.draw_icon(canvas, "expand", _expand_rect.position + Vector2(1.0, 1.0), _expanded, content_a)

		var cls_hov: bool = _hover_id == "close"
		ChatChrome.draw_tab_pill(canvas, _close_rect, cls_hov, 1.0 if cls_hov else 0.0, COL_ROSE, content_a * 0.92)
		ChatChrome.draw_icon(canvas, "close", _close_rect.position + Vector2(1.0, 1.0), cls_hov, content_a)

		# 5. Validation / Hint Ribbon (with subtle micro-shake on error)
		if _hint_visible and not _hint.text.is_empty():
			var shake_x: float = roundf(sin(_time * 48.0) * 2.5 * _hint_shake)
			var hr: Rect2 = Rect2(r.position.x + 8.0 + shake_x, _input_rect.position.y - HINT_H - 2.0, r.size.x - 16.0, HINT_H)
			var h_col: Color = COL_ROSE if _hint_is_error else COL_GOLD
			canvas.draw_rect(hr, Color(COL_OUTLINE, 0.90 * content_a))
			canvas.draw_rect(hr.grow(-1.0), Color(h_col.darkened(0.76), 0.92 * content_a))
			canvas.draw_rect(Rect2(hr.position.x + 1.0, hr.position.y + 1.0, 2.0, hr.size.y - 2.0), Color(h_col, 0.9 * content_a))
			ChatFont.draw_ink(canvas, _hint.text, hr.position + Vector2(6.0, 2.0), Color(h_col.lightened(0.25), content_a), Color(COL_OUTLINE, 0.9 * content_a))

		# 6. Recessed Textured Input Well + Active Emblem + Char Counter + Send Crystal
		var focused: bool = _field.has_focus()
		ChatChrome.draw_input_well(canvas, _input_rect, content_a * fill_scale, focused, _accent_live, _time)
		var chan_icon: String = "game" if _key == "game" else ("group" if _key == "group" else "direct")
		ChatChrome.draw_icon(canvas, chan_icon, _input_rect.position + Vector2(4.0, 4.0), focused, content_a)

		var char_len: int = _field.text.length()
		if char_len > int(float(Chat.LIMIT) * 0.72):
			var c_str: String = "%d/%d" % [char_len, Chat.LIMIT]
			var c_col: Color = COL_ROSE if char_len > Chat.LIMIT else COL_GOLD
			PixelText.draw(canvas, c_str, Vector2i(int(_send_rect.position.x - float(PixelText.width(c_str)) - 4.0), int(_input_rect.position.y + 6.0)), Color(c_col, content_a), Color(COL_OUTLINE, content_a))

		var can_send: bool = not _field.text.strip_edges().is_empty() and not _busy
		var send_hov: bool = _hover_id == "send"
		if can_send:
			VineStyle.glow(canvas, _send_rect.get_center(), 6.0, _accent_live, (0.45 if send_hov else 0.25) * content_a)
		ChatChrome.draw_icon(canvas, "send", _send_rect.position + Vector2(2.0, 2.0), can_send or send_hov, content_a, _accent_live.lerp(Color.WHITE, 0.35) if can_send else Color.WHITE)


## Foreground overlay drawn strictly ABOVE _log and _field (autocomplete leaf, ↓ NEU dewdrop, spore FX).
func _draw_overlay(canvas: Control) -> void:
	if _open_t <= 0.01:
		return
	var ease_t: float = 1.0 - pow(1.0 - clampf(_open_t, 0.0, 1.0), 3.0)
	var content_a: float = clampf((ease_t - 0.18) / 0.82, 0.0, 1.0)
	var night: float = VineStyle.void_amount()

	if content_a > 0.02:
		# 1. Scroll-to-bottom '↓ NEU' dewdrop pill
		if _scrolled_up and _jump_rect.size.x > 4.0:
			var jhov: bool = _hover_id == "jump_bottom"
			var jcol: Color = _accent_live if _scrolled_unread else COL_TEXT_SOFT
			canvas.draw_rect(_jump_rect, Color(COL_OUTLINE, 0.92 * content_a))
			canvas.draw_rect(_jump_rect.grow(-1.0), Color("1b1430" if not jhov else "2a2048", 0.95 * content_a))
			canvas.draw_rect(Rect2(_jump_rect.position.x + 1.0, _jump_rect.position.y + 1.0, _jump_rect.size.x - 2.0, 1.0), Color(jcol, 0.75 * content_a))
			var jtxt: String = "↓ NEU" if _scrolled_unread else "↓ UNTEN"
			PixelText.draw(canvas, jtxt, Vector2i(int(_jump_rect.position.x + (_jump_rect.size.x - float(PixelText.width(jtxt))) * 0.5), int(_jump_rect.position.y + 3.0)), Color(jcol, content_a), Color(COL_OUTLINE, content_a))

		# 2. Floating Autocomplete Suggestion Leaf (guaranteed on top of _log!)
		if not _suggestions.is_empty() and _suggest_t > 0.02 and _suggest_rect.size.y > 8.0:
			var op_n: float = _chat_opacity_norm(_chat_opacity())
			var sa: float = _suggest_t * content_a * lerpf(0.76, 1.0, op_n)
			ChatChrome.draw_suggest_leaf(canvas, _suggest_rect, sa, night)
			# Crisp framed TAB / ADMIN badge tucked cleanly on the top-right edge of the suggestion leaf
			var has_admin_row: bool = String(_suggestions[0].get("kind", "")) == "admin"
			var badge_str: String = AdminCommands.mode_badge()
			var tab_lbl: String = ("%s · TAB" % badge_str) if (has_admin_row and not badge_str.is_empty()) else "TAB"
			var tw: int = PixelText.width(tab_lbl)
			var pill_r: Rect2 = Rect2(roundf(_suggest_rect.end.x - float(tw) - 10.0), roundf(_suggest_rect.position.y - 9.0), float(tw) + 8.0, 10.0)
			canvas.draw_rect(pill_r, Color(COL_OUTLINE, 0.94 * sa))
			canvas.draw_rect(pill_r.grow(-1.0), Color("19122c", 0.96 * sa))
			canvas.draw_rect(Rect2(pill_r.position.x + 1.0, pill_r.position.y + 1.0, pill_r.size.x - 2.0, 1.0), Color(COL_GOLD, 0.65 * sa))
			PixelText.draw(canvas, tab_lbl, Vector2i(int(pill_r.position.x + 4.0), int(pill_r.position.y + 2.0)), Color(COL_GOLD, 0.95 * sa), Color(COL_OUTLINE, 0.95 * sa))
			for i: int in mini(_suggestions.size(), SUGGEST_MAX):
				var item: Dictionary = _suggestions[i]
				var is_adm: bool = String(item.get("kind", "")) == "admin"
				var row_acc: Color = COL_GOLD if is_adm else _accent_live
				var ry: float = _suggest_rect.position.y + 5.0 + float(i) * 14.0
				var row_r: Rect2 = Rect2(_suggest_rect.position.x + 4.0, ry, _suggest_rect.size.x - 8.0, 13.0)
				var sel: bool = i == _suggest_sel
				if sel:
					canvas.draw_rect(row_r, Color(row_acc, 0.20 * sa))
					canvas.draw_rect(Rect2(row_r.position.x, row_r.position.y + 1.0, 2.0, row_r.size.y - 2.0), Color(row_acc, 0.95 * sa))
				var raw_lbl: String = String(item["label"])
				var lbl: String = ("★ " + raw_lbl) if is_adm else raw_lbl
				var desc: String = String(item["desc"])
				var lbl_col: Color = row_acc.lerp(Color.WHITE, 0.35) if sel else (COL_GOLD.lerp(COL_TEXT, 0.32) if is_adm else COL_TEXT)
				ChatFont.draw_ink(canvas, lbl, row_r.position + Vector2(6.0, 1.0), Color(lbl_col, sa), Color(COL_OUTLINE, 0.9 * sa))
				if not desc.is_empty():
					var dw: float = ChatFont.measure_width(desc)
					var dx: float = row_r.end.x - dw - 4.0
					if dx > row_r.position.x + ChatFont.measure_width(lbl) + 12.0:
						ChatFont.draw_ink(canvas, desc, Vector2(dx, row_r.position.y + 1.0), Color(COL_MUTED if not sel else COL_TEXT_SOFT, sa), Color(COL_OUTLINE, 0.85 * sa))

	# 3. Living Bioluminescent Spore Particles
	for sp: Dictionary in _spores:
		var life: float = maxf(float(sp["life"]), 0.01)
		var p: float = clampf(float(sp["age"]) / life, 0.0, 1.0)
		var alpha: float = (1.0 - p) * sin(minf(p * 4.0, 1.0) * PI * 0.5)
		var pos: Vector2 = (sp["pos"] as Vector2).round()
		var sz: float = float(sp["size"])
		canvas.draw_rect(Rect2(pos, Vector2(sz, sz)), Color(sp["col"] as Color, alpha * 0.92))


# ------------------------------------------------------------------ Drawing: Ambient Closed Whisper Feed

func _draw_ambient(canvas: Control) -> void:
	var vis_fade: float = clampf(1.0 - _open_t * 2.0, 0.0, 1.0)
	if vis_fade <= 0.02:
		return
	var night: float = VineStyle.void_amount()
	var base_y: float = _bottom_anchor_y() - 6.0

	# Unread Whisper Spore Bud on a small living root twig (when Group/DM unread messages wait)
	var unread_n: int = _unread_priority_count()
	if unread_n > 0:
		var by: float = _bud_rect.position.y
		var hov: bool = _hover_id == "ambient_bud"
		var prio_key: String = _pick_priority_unread()
		var b_acc: Color = _accent_for(prio_key)
		var pulse: float = 0.65 + 0.35 * sin(_time * 4.2)
		# Tiny root twig from screen left edge x=0..11 with a tiny moss/void leaf
		var twig_y: float = by + 9.0
		for xi: int in 12:
			canvas.draw_rect(Rect2(float(xi), twig_y - 1.0, 1.0, 3.0), Color(COL_OUTLINE, vis_fade))
			canvas.draw_rect(Rect2(float(xi), twig_y, 1.0, 1.0), Color(VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, night), vis_fade))
		VineStyle.leaf(canvas, Vector2(4.0, twig_y - 2.0), 1, -1, 3, Color(VineStyle.LEAF.lerp(VineStyle.LEAF_VOID, night), vis_fade), Color(VineStyle.LEAF_LIGHT.lerp(VineStyle.LEAF_VOID_LIGHT, night), vis_fade))
		VineStyle.glow(canvas, Vector2(14.0, by + 9.0), 8.0 if hov else 6.0, b_acc, (0.65 if hov else 0.42) * pulse * vis_fade)
		ChatChrome.draw_icon(canvas, "bud", Vector2(9.0, by + 3.0), true, vis_fade, b_acc.lerp(Color.WHITE, 0.25))
		var cnt_txt: String = str(mini(unread_n, 99))
		HudText.ink(canvas, cnt_txt, Vector2i(22, int(by + 6.0)), Color(b_acc.lightened(0.25), vis_fade), Color(COL_OUTLINE, vis_fade))
		if hov:
			HudText.ink(canvas, "ENTER", Vector2i(36, int(by + 6.0)), Color(COL_TEXT_SOFT, vis_fade), Color(COL_OUTLINE, vis_fade))
		base_y = minf(base_y, by - 4.0)

	# Floating boxless whisper lines (recent messages gently rising & fading)
	var amb_op: float = _chat_opacity()
	var amb_txt_scale: float = lerpf(0.68, 1.0, _chat_opacity_norm(amb_op))
	var max_w: float = 216.0
	var y: float = base_y
	for i: int in range(_ambient_rows.size() - 1, -1, -1):
		var row: Dictionary = _ambient_rows[i]
		var age: float = _time - float(row["born"])
		if age >= AMBIENT_HOLD + AMBIENT_FADE:
			continue
		var enter_t: float = clampf(age / 0.22, 0.0, 1.0)
		var fade_out: float = 1.0 - clampf((age - AMBIENT_HOLD) / AMBIENT_FADE, 0.0, 1.0)
		var base_a: float = enter_t * fade_out * vis_fade
		if base_a <= 0.02:
			continue
		var a: float = base_a * amb_txt_scale
		var slide: float = roundf((1.0 - enter_t) * 5.0)
		var acc: Color = row["accent"] as Color
		var author: String = String(row["author"])
		var body: String = String(row["text"])
		var prefix: String = author + " · "
		var full_line: String = prefix + body
		var wrapped: PackedStringArray = ChatFont.wrap_lines(full_line, max_w)
		var line_h: float = float(wrapped.size()) * float(ChatFont.LINE_HEIGHT)
		y -= line_h + 3.0
		var draw_y: float = roundf(y + slide)

		# Feathered 3-band mist cushion (dissolves gently on the right, scaled by Chat-Sichtbarkeit!)
		var text_w: float = minf(ChatFont.measure_width(full_line) + 12.0, max_w + 12.0)
		for band: int in 3:
			var bw: float = text_w * (0.68 + float(band) * 0.16)
			var ba: float = (0.14 - float(band) * 0.035) * base_a * amb_op
			canvas.draw_rect(Rect2(6.0, draw_y + float(band), roundf(bw), maxf(line_h - float(band) * 1.5, 4.0)), Color("090514", ba))

		# Tiny glowing channel spore dot on the left
		var dot_pos: Vector2 = Vector2(9.0, draw_y + 5.0)
		VineStyle.glow(canvas, dot_pos, 4.0, acc, 0.45 * a)
		canvas.draw_rect(Rect2(dot_pos - Vector2(1, 1), Vector2(3, 3)), Color(COL_OUTLINE, a))
		canvas.draw_rect(Rect2(dot_pos, Vector2(2, 2)), Color(acc, a))

		# Draw wrapped lines with colored author prefix on line 0
		for li: int in wrapped.size():
			var ly: float = draw_y + float(li * ChatFont.LINE_HEIGHT)
			var ltxt: String = wrapped[li]
			if li == 0 and ltxt.begins_with(prefix):
				var aw: float = ChatFont.measure_width(author)
				var dotw: float = ChatFont.measure_width(" · ")
				ChatFont.draw_ink(canvas, author, Vector2(15.0, ly), Color(COL_TEXT_SOFT if bool(row["own"]) else acc, a), Color(COL_OUTLINE, 0.92 * a), true)
				ChatFont.draw_ink(canvas, " · ", Vector2(15.0 + aw, ly), Color(COL_MUTED, a), Color(COL_OUTLINE, 0.85 * a), false)
				ChatFont.draw_ink(canvas, ltxt.substr(prefix.length()), Vector2(15.0 + aw + dotw, ly), Color(COL_TEXT, a), Color(COL_OUTLINE, 0.92 * a), true)
			else:
				ChatFont.draw_ink(canvas, ltxt, Vector2(15.0, ly), Color(COL_TEXT, a), Color(COL_OUTLINE, 0.92 * a), true)
