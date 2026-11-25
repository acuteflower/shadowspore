class_name GameMenu
extends Control
## Unified In-Game Menu ('Der Feldcodex', 6 cohesive tabs).
## Standalone InventoryWindow lives independently on `I` (untouched organic vine overlay).
## Feldcodex opens on `Tab` (last tab) or direct hotkeys (`M`, `J`, `F`, `P`, `N`, `Esc`):
##   0: ATLAS    (MapWindow / AtlasView full-bleed with 16 px/tile Live Match-Cut)
##   1: AUFGABEN (QuestJournal leather book)
##   2: PFAD     (Native MenuChrome PathTab: TALENTE constellation + STUFEN road)
##   3: FRÜCHTE  (Native MenuChrome FruitCodexTab: Schattenfrüchte Herbarium & Sporen-Schwellen)
##   4: WELT     (Native MenuChrome WorldTab: CHRONIK, STADT, VÖGEL, FLUSSBUCH)
##   5: SYSTEM   (Native MenuChrome SystemTab: EINSTELLUNGEN, STEUERUNG, KOOP & SITZUNG + SocialSidebar)

const BACKDROP_SHADER: Shader = preload("res://assets/shaders/menu_backdrop.gdshader")
const OPEN_WAV: AudioStream = preload("res://assets/audio/board/rustle_a.wav")
const CLOSE_WAV: AudioStream = preload("res://assets/audio/board/rustle_b.wav")
const FLIP_WAV: AudioStream = preload("res://assets/audio/board/flip.wav")

const RAIL_H: float = 34.0
const FOOTER_H: float = 20.0
const OPEN_SEC: float = 0.22
const CLOSE_SEC: float = 0.14
const SLIDE_SEC: float = 0.17

const TABS: Array[Dictionary] = [
	{"id": "atlas", "label": "ATLAS", "icon": "atlas", "hint": "RAD ZOOM · R-KLICK PIN · TAB EBENE · LEERTASTE ZU MIR · B CHRONIK"},
	{"id": "quests", "label": "AUFGABEN", "icon": "quests", "hint": "W/S WÄHLEN · ENTER FOKUS · AUF ATLAS ZEIGEN"},
	{"id": "path", "label": "CHARAKTER", "icon": "path", "hint": "TALENTE & STUFEN · KLICK LERNEN ODER EINLÖSEN · RAD SCROLLEN"},
	{"id": "fruits", "label": "SCHATTENFRÜCHTE", "icon": "fruits", "hint": "KLICK FRUCHT ANHÖREN · SCHWELLEN EINLÖSEN · RAD SCROLLEN"},
	{"id": "world", "label": "WELT", "icon": "world", "hint": "CHRONIK · STADT & HOF · VÖGEL · FLUSSBUCH"},
	{"id": "system", "label": "SYSTEM", "icon": "system", "hint": "EINSTELLUNGEN · STEUERUNG · KOOP · TAB SOZIAL-LEISTE"},
]

const HUD_HIDE_NAMES: Array[String] = [
	"ClockVine", "PurseVine", "WayVine", "QuestVine", "HintCard",
	"NoticeLeaf", "NoticeLine", "HealthBar", "StaminaBar", "BlinkIcon",
	"StatusTags", "CompanionVine", "FishingHud", "HudNotices", "ZoneTitle", "Hotbar",
]

var _player: Node = null
var _hud: CanvasLayer = null

# References to existing HUD windows
var _inv_win: Control = null ## standalone on I — never embedded!
var _map_win: Control = null
var _quest_win: Control = null
var _skill_win: Control = null ## muted on F while unified_menu active
var _prog_win: Control = null ## muted on P while unified_menu active
var _pause_win: Control = null ## muted on Esc while unified_menu active (keeps Testwerkzeuge O)
var _river_win: Control = null

# Native MenuChrome tabs hosted inside `_stage`
var _quest_tab: QuestTab = null
var _path_tab: PathTab = null
var _fruits_tab: FruitCodexTab = null
var _world_tab: WorldTab = null
var _system_tab: SystemTab = null

# Visual chrome layers
var _backdrop: ColorRect = null
var _backdrop_mat: ShaderMaterial = null
var _stage: Control = null
var _chrome_layer: CanvasLayer = null
var _chrome_overlay: Control = null
var _rail_hit: Control = null

# State & animation clocks
var _opening: bool = false
var _open_t: float = 0.0
var _active_tab: int = 0
var _last_game_tab: int = 0
var _tab_t: float = 1.0
var _slide_dir: float = 1.0
var _time: float = 0.0
var _bloom_x: float = 320.0
var _hover_tab: int = -1
var _tab_hover_t: Array[float] = []
var _tab_rects: Array[Rect2] = []
var _q_rect: Rect2 = Rect2()
var _e_rect: Rect2 = Rect2()
var _paused_here: bool = false
var _hidden_hud_nodes: Dictionary = {} ## CanvasItem -> bool previous visibility
var _hidden_banner_layers: Dictionary = {} ## CanvasLayer -> bool previous visibility


func _ready() -> void:
	visible = false
	z_index = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tab_hover_t.resize(TABS.size())
	_tab_hover_t.fill(0.0)

	# 1. Living textured dark-glass backdrop shader (above world HUD vines z=0, behind embedded windows z=12..35)
	_backdrop = ColorRect.new()
	_backdrop.name = "MenuBackdrop"
	_backdrop.z_as_relative = false
	_backdrop.z_index = 9
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop_mat = ShaderMaterial.new()
	_backdrop_mat.shader = BACKDROP_SHADER
	_backdrop.material = _backdrop_mat
	add_child(_backdrop)

	# 2. Content stage container for our native MenuChrome tabs (strictly between Canopy Rail and Footer Rail)
	_stage = Control.new()
	_stage.name = "MenuStage"
	_stage.z_as_relative = false
	_stage.z_index = 35
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage.offset_top = RAIL_H
	_stage.offset_bottom = -FOOTER_H
	add_child(_stage)

	# 3. Top Canopy Rail + Bottom Footer Rail on its own CanvasLayer (layer 28: guaranteed above QuestJournal's layer 24!)
	_chrome_layer = CanvasLayer.new()
	_chrome_layer.name = "MenuChromeLayer"
	_chrome_layer.layer = 28
	_chrome_layer.visible = false
	add_child(_chrome_layer)

	_chrome_overlay = Control.new()
	_chrome_overlay.name = "MenuChromeOverlay"
	_chrome_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chrome_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_chrome_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_chrome_overlay.draw.connect(_draw_chrome)
	_chrome_layer.add_child(_chrome_overlay)

	_rail_hit = Control.new()
	_rail_hit.name = "MenuRailHit"
	_rail_hit.mouse_filter = Control.MOUSE_FILTER_PASS
	_rail_hit.anchor_left = 0.0
	_rail_hit.anchor_top = 0.0
	_rail_hit.anchor_right = 0.0
	_rail_hit.anchor_bottom = 0.0
	_rail_hit.position = Vector2(0.0, 0.0)
	_rail_hit.size = Vector2(640.0, RAIL_H)
	_rail_hit.gui_input.connect(_on_chrome_input)
	_rail_hit.mouse_exited.connect(func() -> void:
		_hover_tab = -1
		if _chrome_overlay != null:
			_chrome_overlay.queue_redraw())
	_chrome_layer.add_child(_rail_hit)
	resized.connect(_compute_tab_rects)


func bind(player: Node, hud: CanvasLayer) -> void:
	_player = player
	_hud = hud
	InputManager.unified_menu = true

	_inv_win = hud.get_node_or_null("InventoryWindow") as Control
	_map_win = hud.get_node_or_null("MapWindow") as Control
	_quest_win = hud.get_node_or_null("QuestJournal") as Control
	_skill_win = hud.get_node_or_null("SkillTreeWindow") as Control
	_prog_win = hud.get_node_or_null("ProgressWindow") as Control
	_pause_win = hud.get_node_or_null("PauseMenu") as Control
	_river_win = hud.get_node_or_null("RiverBook") as Control

	# Note: InventoryWindow intentionally stays standalone (`embedded_in_menu = false`) on `I`!
	for win: Control in [_map_win, _quest_win, _skill_win, _prog_win, _pause_win, _river_win]:
		if win != null and "embedded_in_menu" in win:
			win.set("embedded_in_menu", true)
	if _map_win != null and _map_win.has_signal("open_chronicle_requested"):
		_map_win.connect("open_chronicle_requested", _on_open_chronicle_from_atlas)

	# Build our 5 native MenuChrome tabs inside `_stage`
	_quest_tab = QuestTab.new()
	_quest_tab.name = "QuestTab"
	_quest_tab.visible = false
	_stage.add_child(_quest_tab)
	_quest_tab.bind(player)
	_quest_tab.jump_to_atlas.connect(_on_jump_to_atlas)

	_path_tab = PathTab.new()
	_path_tab.name = "PathTab"
	_path_tab.visible = false
	_stage.add_child(_path_tab)
	_path_tab.bind(player)

	_fruits_tab = FruitCodexTab.new()
	_fruits_tab.name = "FruitCodexTab"
	_fruits_tab.visible = false
	_stage.add_child(_fruits_tab)
	_fruits_tab.bind(player)
	_fruits_tab.jump_to_atlas.connect(_on_jump_to_atlas)

	_world_tab = WorldTab.new()
	_world_tab.name = "WorldTab"
	_world_tab.visible = false
	_stage.add_child(_world_tab)
	_world_tab.bind(player, _river_win)
	_world_tab.request_close_menu.connect(func() -> void: close(true))
	if _world_tab.has_signal("jump_to_atlas"):
		_world_tab.connect("jump_to_atlas", _on_jump_to_atlas)

	_system_tab = SystemTab.new()
	_system_tab.name = "SystemTab"
	_system_tab.visible = false
	_stage.add_child(_system_tab)
	_system_tab.bind(player, hud)
	_system_tab.request_close_menu.connect(func() -> void: close(true))


func is_open() -> bool:
	return _opening or _open_t > 0.01


func open_tab(tab_id: String, instant: bool = false, sub_id: String = "") -> void:
	# If standalone InventoryWindow is open, close it cleanly first so windows never overlap
	if _inv_win != null and bool(_inv_win.get("_opening")):
		_inv_win.call("_set_open", false)
	var idx: int = _index_of(tab_id)
	if idx < 0:
		idx = 0
	var was_open: bool = _opening
	if not was_open:
		_opening = true
		visible = true
		if _chrome_layer != null:
			_chrome_layer.visible = true
		_open_t = 1.0 if instant else 0.01
		InputManager.menu_open = true
		InputManager.ui_blocking = true
		_set_hud_chrome_hidden(true)
		_sync_pause(true)
		if not instant:
			_play_sound(OPEN_WAV, -6.0, 0.96)
	else:
		if idx == _active_tab and sub_id.is_empty():
			return
		_slide_dir = 1.0 if idx >= _active_tab else -1.0
		_tab_t = 1.0 if instant else 0.0
		if not instant:
			_play_sound(FLIP_WAV, -7.0, 0.94 + float(idx) * 0.025)

	_deactivate_all_tabs()
	_active_tab = idx
	if idx < 5:
		_last_game_tab = idx
	_activate_tab(idx, sub_id, not was_open and not instant)
	_compute_tab_rects()
	if not was_open or instant:
		if idx < _tab_rects.size():
			_bloom_x = _tab_rects[idx].get_center().x
	_chrome_overlay.queue_redraw()


func close(instant: bool = false) -> void:
	if not _opening and _open_t <= 0.0:
		return
	_opening = false
	_deactivate_all_tabs()
	_set_hud_chrome_hidden(false)
	InputManager.menu_open = false
	InputManager.ui_blocking = false
	_sync_pause(false)
	if instant:
		_open_t = 0.0
		visible = false
		if _chrome_layer != null:
			_chrome_layer.visible = false
	else:
		_play_sound(CLOSE_WAV, -8.0, 1.05)


func switch_tab(step: int) -> void:
	if not _opening:
		return
	var next_i: int = posmod(_active_tab + step, TABS.size())
	_slide_dir = 1.0 if step > 0 else -1.0
	_tab_t = 0.0
	_deactivate_all_tabs()
	_active_tab = next_i
	if next_i < 5:
		_last_game_tab = next_i
	_activate_tab(next_i, "", false)
	_play_sound(FLIP_WAV, -7.0, 0.94 + float(next_i) * 0.025)
	_chrome_overlay.queue_redraw()


func _index_of(tab_id: String) -> int:
	for i: int in TABS.size():
		if String(TABS[i]["id"]) == tab_id:
			return i
	return -1


func _sync_pause(want_pause: bool) -> void:
	if not is_inside_tree():
		return
	if want_pause:
		var solo: bool = multiplayer.get_peers().is_empty()
		if solo and not get_tree().paused:
			get_tree().paused = true
			_paused_here = true
	elif _paused_here:
		_paused_here = false
		get_tree().paused = false


func _set_hud_chrome_hidden(hide_it: bool) -> void:
	if _hud == null or not is_instance_valid(_hud):
		return
	if hide_it:
		for n_name: String in HUD_HIDE_NAMES:
			var node: CanvasItem = _hud.get_node_or_null(n_name) as CanvasItem
			if node != null and not _hidden_hud_nodes.has(node):
				_hidden_hud_nodes[node] = node.visible
				node.visible = false
		if is_inside_tree():
			for bn: Node in get_tree().get_nodes_in_group("world_banners"):
				var cl: CanvasLayer = bn as CanvasLayer
				if cl != null and not _hidden_banner_layers.has(cl):
					_hidden_banner_layers[cl] = cl.visible
					cl.visible = false
	else:
		for node_v: Variant in _hidden_hud_nodes.keys():
			var node: CanvasItem = node_v as CanvasItem
			if node != null and is_instance_valid(node):
				node.visible = bool(_hidden_hud_nodes[node_v])
		_hidden_hud_nodes.clear()
		for cl_v: Variant in _hidden_banner_layers.keys():
			var cl: CanvasLayer = cl_v as CanvasLayer
			if cl != null and is_instance_valid(cl):
				cl.visible = bool(_hidden_banner_layers[cl_v])
		_hidden_banner_layers.clear()


func _inventory_open_now() -> bool:
	return _inv_win != null and (bool(_inv_win.get("_opening")) or InputManager.inventory_open)


func _can_open_from_world() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	if InputManager.chat_open or InputManager.freecam_open or InputManager.mod_menu_open or InputManager.dungeons_open:
		return false
	var hp: HealthComponent = _player.get("health") as HealthComponent
	if hp != null and hp.current <= 0.0:
		return false
	if bool(_player.get("story_lock")) or _player.get("intro") != null:
		return false
	if get_tree().get_first_node_in_group("board_window") != null:
		return false
	if get_tree().get_first_node_in_group("dialogue") != null:
		var dlg: Node = get_tree().get_first_node_in_group("dialogue")
		if dlg != null and dlg.has_method("is_open") and bool(dlg.call("is_open")):
			return false
	return true


func _is_text_editing() -> bool:
	if _system_tab != null and _system_tab.visible and _system_tab.is_typing():
		return true
	if _world_tab != null and _world_tab.visible and _world_tab.is_typing():
		return true
	var focus_owner: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	return focus_owner is LineEdit or focus_owner is TextEdit


func _deactivate_all_tabs() -> void:
	if _map_win != null and _map_win.has_method("set_embedded_active"):
		_map_win.call("set_embedded_active", false, false)
	if _quest_tab != null:
		_quest_tab.close_embedded()
		_quest_tab.visible = false
	if _quest_win != null and _quest_win.has_method("set_embedded_active"):
		_quest_win.call("set_embedded_active", false)
	if _path_tab != null:
		_path_tab.close_embedded()
		_path_tab.visible = false
	if _fruits_tab != null:
		_fruits_tab.visible = false
	if _world_tab != null:
		_world_tab.close_embedded()
		_world_tab.visible = false
	if _system_tab != null:
		_system_tab.close_embedded()
		_system_tab.visible = false


func _activate_tab(idx: int, sub_id: String, with_match_cut: bool) -> void:
	var tid: String = String(TABS[idx]["id"])
	match tid:
		"atlas":
			if _map_win != null and _map_win.has_method("set_embedded_active"):
				_map_win.call("set_embedded_active", true, with_match_cut)
		"quests":
			if _quest_tab != null:
				_quest_tab.visible = true
				_quest_tab.on_tab_opened()
		"path":
			if _path_tab != null:
				_path_tab.visible = true
				_path_tab.show_sub(1 if sub_id == "progress" else 0)
		"fruits":
			if _fruits_tab != null:
				_fruits_tab.visible = true
				_fruits_tab.on_tab_opened()
		"world":
			if _world_tab != null:
				_world_tab.visible = true
				_world_tab.show_sub_id(sub_id if not sub_id.is_empty() else "chronicle")
		"system":
			if _system_tab != null:
				_system_tab.visible = true
				_system_tab.show_sub_id(sub_id if not sub_id.is_empty() else "settings")


func _on_jump_to_atlas(world_tile: Vector2, zone_id: StringName) -> void:
	open_tab("atlas", false)
	if _map_win != null and _map_win.has_method("focus_world_tile"):
		_map_win.call("focus_world_tile", world_tile, zone_id)


func _on_open_chronicle_from_atlas(zone_id: StringName) -> void:
	if _world_tab != null:
		_world_tab.set_chronicle_zone(zone_id)
	open_tab("world", false, "chronicle")


func _process(delta: float) -> void:
	_time += delta
	_poll_global_hotkeys()

	var target: float = 1.0 if _opening else 0.0
	var dur: float = OPEN_SEC if _opening else CLOSE_SEC
	_open_t = move_toward(_open_t, target, delta / maxf(dur, 0.01))
	visible = _open_t > 0.001
	if _chrome_layer != null:
		_chrome_layer.visible = visible
	if not visible:
		return

	_tab_t = minf(_tab_t + delta / maxf(SLIDE_SEC, 0.01), 1.0)
	var ease_slide: float = 1.0 - pow(1.0 - _tab_t, 3.0)
	_stage.position.x = roundf((1.0 - ease_slide) * 18.0 * _slide_dir)
	_stage.modulate.a = clampf(ease_slide * _open_t, 0.0, 1.0)

	var on_atlas: bool = String(TABS[_active_tab]["id"]) == "atlas"
	_backdrop.visible = not on_atlas
	if _backdrop.visible and _backdrop_mat != null:
		var mood_c: Color = ZoneMood.now.get("hud_bark", Color("3b2c40")) as Color if not ZoneMood.now.is_empty() else Color("3b2c40")
		_backdrop_mat.set_shader_parameter("time", _time)
		_backdrop_mat.set_shader_parameter("open_t", _open_t)
		_backdrop_mat.set_shader_parameter("night", TimeManager.night_amount())
		_backdrop_mat.set_shader_parameter("zone_tint", Vector3(mood_c.r, mood_c.g, mood_c.b))
		_backdrop_mat.set_shader_parameter("view_size", size)

	_compute_tab_rects()
	if _active_tab >= 0 and _active_tab < _tab_rects.size():
		var goal_x: float = _tab_rects[_active_tab].get_center().x
		_bloom_x = lerpf(_bloom_x, goal_x, 1.0 - exp(-20.0 * delta))
	for i: int in TABS.size():
		_tab_hover_t[i] = lerpf(_tab_hover_t[i], 1.0 if i == _hover_tab else 0.0, 1.0 - exp(-16.0 * delta))

	_chrome_overlay.queue_redraw()


func _poll_global_hotkeys() -> void:
	if InputManager.chat_open or InputManager.chat_closed_recently() or _is_text_editing():
		return

	# If standalone InventoryWindow is open, let Escape close InventoryWindow (not open GameMenu over it!)
	if _inventory_open_now():
		# Allow direct jumps from Inventory -> Atlas / Quests / Path / RiverBook seamlessly!
		if InputManager.map_pressed():
			open_tab("atlas")
		elif Input.is_action_just_pressed("quest_journal") if InputMap.has_action("quest_journal") else false:
			open_tab("quests")
		elif InputManager.skills_pressed():
			open_tab("path", false, "skills")
		elif InputManager.progress_pressed():
			open_tab("path", false, "progress")
		elif Input.is_action_just_pressed("fish_book") if InputMap.has_action("fish_book") else false:
			open_tab("world", false, "river")
		return

	# Pressing I while GameMenu is open closes GameMenu and switches smoothly to standalone InventoryWindow!
	if _opening and InputManager.inventory_pressed():
		close(true)
		if _inv_win != null and _inv_win.has_method("_set_open"):
			_inv_win.call("_set_open", true)
		return

	# Escape (ui_cancel)
	if Input.is_action_just_pressed("ui_cancel"):
		if _opening:
			close()
			return
		elif _can_open_from_world():
			open_tab("system")
			return

	# Direct Feldcodex hotkeys (open target tab; toggle close if already on it!)
	var direct_map: Array[Dictionary] = [
		{"pressed": InputManager.map_pressed(), "tab": "atlas", "sub": ""},
		{"pressed": Input.is_action_just_pressed("quest_journal") if InputMap.has_action("quest_journal") else false, "tab": "quests", "sub": ""},
		{"pressed": InputManager.skills_pressed(), "tab": "path", "sub": "skills"},
		{"pressed": InputManager.progress_pressed(), "tab": "path", "sub": "progress"},
		{"pressed": Input.is_action_just_pressed("fish_book") if InputMap.has_action("fish_book") else false, "tab": "world", "sub": "river"},
	]
	for dm: Dictionary in direct_map:
		if not bool(dm["pressed"]):
			continue
		var target_tab: String = String(dm["tab"])
		var target_sub: String = String(dm["sub"])
		if _opening:
			var cur_id: String = String(TABS[_active_tab]["id"])
			if cur_id == target_tab and target_sub.is_empty():
				close()
			else:
				open_tab(target_tab, false, target_sub)
			return
		elif _can_open_from_world():
			open_tab(target_tab, false, target_sub)
			return

	if _opening:
		var prev_p: bool = Input.is_action_just_pressed("menu_tab_prev") if InputMap.has_action("menu_tab_prev") else false
		var next_p: bool = Input.is_action_just_pressed("menu_tab_next") if InputMap.has_action("menu_tab_next") else false
		if prev_p:
			switch_tab(-1)
		elif next_p:
			switch_tab(1)


func _input(event: InputEvent) -> void:
	if InputManager.chat_open or InputManager.chat_closed_recently() or _is_text_editing():
		return
	if event is InputEventKey:
		var ke: InputEventKey = event as InputEventKey
		if ke.pressed and not ke.echo:
			# TAB opens Feldcodex from world (when inventory is not open), or closes it on non-Atlas/System tabs
			if ke.physical_keycode == KEY_TAB:
				if not _opening:
					if not _inventory_open_now() and _can_open_from_world():
						open_tab(String(TABS[_last_game_tab]["id"]))
						get_viewport().set_input_as_handled()
					return
				else:
					var cur_t: String = String(TABS[_active_tab]["id"])
					if cur_t != "atlas" and cur_t != "system":
						close()
						get_viewport().set_input_as_handled()
					return
			if not _opening:
				return
			if ke.keycode == KEY_Q:
				switch_tab(-1)
				get_viewport().set_input_as_handled()
			elif ke.keycode == KEY_E:
				switch_tab(1)
				get_viewport().set_input_as_handled()
			elif ke.keycode == KEY_J and not InputMap.has_action("quest_journal"):
				if String(TABS[_active_tab]["id"]) == "quests":
					close()
				else:
					open_tab("quests")
				get_viewport().set_input_as_handled()
	elif _opening and event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var mp: Vector2 = mb.position
			if mp.y <= RAIL_H:
				if _q_rect.has_point(mp):
					switch_tab(-1)
					get_viewport().set_input_as_handled()
					return
				if _e_rect.has_point(mp):
					switch_tab(1)
					get_viewport().set_input_as_handled()
					return
				for i: int in _tab_rects.size():
					if _tab_rects[i].has_point(mp):
						if i != _active_tab:
							open_tab(String(TABS[i]["id"]))
						get_viewport().set_input_as_handled()
						return
	elif _opening and event is InputEventJoypadButton:
		var jb: InputEventJoypadButton = event as InputEventJoypadButton
		if jb.pressed:
			if jb.button_index == JOY_BUTTON_LEFT_SHOULDER:
				switch_tab(-1)
				get_viewport().set_input_as_handled()
			elif jb.button_index == JOY_BUTTON_RIGHT_SHOULDER:
				switch_tab(1)
				get_viewport().set_input_as_handled()


func _compute_tab_rects() -> void:
	_tab_rects.clear()
	var vw: float = size.x
	var widths: Array[float] = []
	var total_w: float = 0.0
	var gap: float = 4.0
	for i: int in TABS.size():
		var lbl: String = String(TABS[i]["label"])
		var pw: float = float(PixelText.width(lbl)) + 24.0
		widths.append(pw)
		total_w += pw
	total_w += gap * float(TABS.size() - 1)
	var x: float = roundf((vw - total_w) * 0.5)
	var rail_slide: float = roundf((1.0 - _open_t) * -12.0)
	_q_rect = Rect2(x - 22.0, 6.0 + rail_slide, 18.0, 20.0)
	for i: int in TABS.size():
		_tab_rects.append(Rect2(x, 5.0 + rail_slide, widths[i], 22.0))
		x += widths[i] + gap
	_e_rect = Rect2(x, 6.0 + rail_slide, 18.0, 20.0)
	if _rail_hit != null:
		var left_x: float = maxf(_q_rect.position.x - 6.0, 0.0)
		var right_x: float = minf(_e_rect.end.x + 6.0, vw)
		_rail_hit.anchor_left = 0.0
		_rail_hit.anchor_right = 0.0
		_rail_hit.position = Vector2(left_x, 0.0)
		_rail_hit.size = Vector2(maxf(right_x - left_x, 32.0), RAIL_H)


func _on_chrome_input(event: InputEvent) -> void:
	if not _opening:
		return
	var off: Vector2 = _rail_hit.position if _rail_hit != null else Vector2.ZERO
	if event is InputEventMouseMotion:
		var mp: Vector2 = (event as InputEventMouseMotion).position + off
		_hover_tab = -1
		for i: int in _tab_rects.size():
			if _tab_rects[i].has_point(mp):
				_hover_tab = i
				break
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var mp: Vector2 = mb.position + off
			if _q_rect.has_point(mp):
				switch_tab(-1)
				if _rail_hit != null:
					_rail_hit.accept_event()
				return
			if _e_rect.has_point(mp):
				switch_tab(1)
				if _rail_hit != null:
					_rail_hit.accept_event()
				return
			for i: int in _tab_rects.size():
				if _tab_rects[i].has_point(mp):
					if i != _active_tab:
						open_tab(String(TABS[i]["id"]))
					if _rail_hit != null:
						_rail_hit.accept_event()
					return


func _has_tab_badge(tab_id: String) -> bool:
	if tab_id == "quests" and _player != null and is_instance_valid(_player):
		var tr: TrackedQuests = _player.get("tracked") as TrackedQuests
		if tr != null:
			for row: Dictionary in tr.entries():
				if bool(row.get("ready", false)):
					return true
		return false
	if tab_id == "fruits":
		var vt: VeilThreads = VeilThreads.of(get_tree()) if is_inside_tree() else null
		return vt != null and vt.has_unclaimed_milestone()
	if tab_id == "path" and _player != null and is_instance_valid(_player):
		var sk: SkillTreeComponent = _player.get_node_or_null("SkillTreeComponent") as SkillTreeComponent
		if sk != null and sk.points_free() > 0:
			for nid: String in sk.definitions():
				if sk.can_learn(nid):
					return true
		var pr: ProgressComponent = _player.get("progress") as ProgressComponent
		if pr != null and pr.claimable() > 0:
			return true
	return false


func _current_zone_label() -> String:
	if _player is Node2D and is_instance_valid(_player):
		var zid: StringName = Atlas.shared().zone_at(&"main", (_player as Node2D).global_position)
		if zid != &"":
			var z: Atlas.Zone = Atlas.shared().zone(zid)
			if z != null:
				return z.name.to_upper()
	return "ALTMARK"


func _draw_chrome() -> void:
	if _open_t <= 0.01:
		return
	var vw: float = size.x
	var vh: float = size.y
	var a: float = clampf(_open_t * 1.25, 0.0, 1.0)
	var rail_y: float = roundf((1.0 - _open_t) * -12.0)

	# 1. Top Canopy Rail
	var rail_rect: Rect2 = Rect2(0.0, rail_y, vw, RAIL_H)
	MenuChrome.draw_canopy_rail(_chrome_overlay, rail_rect, a)

	# Left/Right subtle Q / E shoulder key caps
	MenuChrome.draw_tab_pill(_chrome_overlay, _q_rect, false, 0.0, a * 0.9)
	MenuChrome.draw_text(_chrome_overlay, "Q", _q_rect.position + Vector2(7.0, 6.0), MenuChrome.COL_GOLD, a)
	MenuChrome.draw_tab_pill(_chrome_overlay, _e_rect, false, 0.0, a * 0.9)
	MenuChrome.draw_text(_chrome_overlay, "E", _e_rect.position + Vector2(7.0, 6.0), MenuChrome.COL_GOLD, a)

	# 6 Tab Medallions
	for i: int in TABS.size():
		if i >= _tab_rects.size():
			break
		var r: Rect2 = _tab_rects[i]
		var active: bool = (i == _active_tab)
		MenuChrome.draw_tab_pill(_chrome_overlay, r, active, _tab_hover_t[i], a)
		if active:
			MenuChrome.draw_shimmer(_chrome_overlay, r, _time, MenuChrome.COL_GOLD_HOT, a)
		var icon_k: String = String(TABS[i]["icon"])
		MenuChrome.draw_icon(_chrome_overlay, icon_k, Vector2(r.position.x + 5.0, r.position.y + 5.0), active or _tab_hover_t[i] > 0.35, a)
		var lbl: String = String(TABS[i]["label"])
		var txt_col: Color = MenuChrome.COL_GOLD_HOT if active else MenuChrome.COL_TEXT_SOFT.lerp(MenuChrome.COL_TEXT, _tab_hover_t[i])
		MenuChrome.draw_text(_chrome_overlay, lbl, Vector2(r.position.x + 19.0, r.position.y + 8.0), txt_col, a)
		if _has_tab_badge(String(TABS[i]["id"])):
			MenuChrome.draw_badge(_chrome_overlay, Vector2(r.end.x - 6.0, r.position.y - 2.0), _time, a)

	# Living sliding bloom under active tab + delicate trailing spore sparks
	MenuChrome.draw_bloom_slider(_chrome_overlay, _bloom_x, rail_y + RAIL_H - 4.0, a)
	var sp_phase: float = sin(_time * 4.5) * 0.5 + 0.5
	_chrome_overlay.draw_rect(Rect2(roundf(_bloom_x - 16.0), roundf(rail_y + RAIL_H - 2.0), 1.0, 1.0), Color(MenuChrome.COL_TEAL, (0.35 + 0.45 * sp_phase) * a))
	_chrome_overlay.draw_rect(Rect2(roundf(_bloom_x + 16.0), roundf(rail_y + RAIL_H - 2.0), 1.0, 1.0), Color(MenuChrome.COL_GOLD_HOT, (0.35 + 0.45 * (1.0 - sp_phase)) * a))

	# Left balanced Zone crest on Canopy Rail
	var z_lbl: String = _current_zone_label()
	if _q_rect.position.x > float(PixelText.width(z_lbl)) + 26.0:
		_chrome_overlay.draw_rect(Rect2(10.0, rail_y + 14.0, 3.0, 3.0), Color(MenuChrome.COL_TEAL, 0.9 * a))
		MenuChrome.draw_text(_chrome_overlay, z_lbl, Vector2(16.0, rail_y + 12.0), MenuChrome.COL_TEXT_SOFT, a * 0.92)

	# Right subtle Sun/Moon phase glyph + Day indicator on Canopy Rail
	var day_str: String = "TAG %d" % (TimeManager.day + 1)
	var dw: float = float(PixelText.width(day_str))
	var is_night: bool = TimeManager.night_at(TimeManager.time_of_day) > 0.35
	MenuChrome.draw_day_phase_glyph(_chrome_overlay, Vector2(vw - dw - 24.0, rail_y + 11.0), is_night, a * 0.95)
	MenuChrome.draw_text(_chrome_overlay, day_str, Vector2(vw - dw - 10.0, rail_y + 12.0), MenuChrome.COL_GOLD if not is_night else MenuChrome.COL_VIOLET, a * 0.92)

	# 2. Bottom Dynamic Footer Rail
	var foot_y: float = roundf(vh - FOOTER_H + (1.0 - _open_t) * 10.0)
	var foot_rect: Rect2 = Rect2(0.0, foot_y, vw, FOOTER_H)
	MenuChrome.draw_footer_rail(_chrome_overlay, foot_rect, a)

	var hint_str: String = String(TABS[_active_tab]["hint"])
	MenuChrome.draw_text(_chrome_overlay, "Q/E REITER · " + hint_str, Vector2(10.0, foot_y + 7.0), MenuChrome.COL_TEXT_SOFT, a * 0.92)

	# Right compact status strip: Level + Copper + I Inventar + Esc Zu
	var right_info: String = "I TASCHE · ESC ZU"
	if _player != null and is_instance_valid(_player):
		var pr: ProgressComponent = _player.get("progress") as ProgressComponent
		if pr != null:
			right_info = "ST. %d · %d K · I TASCHE · ESC ZU" % [pr.level, pr.copper]
	var rw: float = float(PixelText.width(right_info))
	MenuChrome.draw_text(_chrome_overlay, right_info, Vector2(vw - rw - 10.0, foot_y + 7.0), MenuChrome.COL_GOLD, a * 0.92)


func _play_sound(stream: AudioStream, db: float, pitch: float) -> void:
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
