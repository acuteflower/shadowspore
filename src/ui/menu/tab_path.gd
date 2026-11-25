class_name PathTab
extends Control
## Native Feldcodex 'PFAD' tab crafted in the 1:1 MenuChrome obsidian/cosmos/gold aesthetic.
## Combines:
##   0: TALENTE — 3-branch astral Schleiergeflecht (KAMPF · BEWEGUNG · LEERE) with live twinkling starfield,
##                branch mastery counters, shockwave burst FX, hover upgrade previews, fixed Echo UX, & WASD nav
##   1: STUFEN  — Character ledger with Ellie portrait medallion, live XP numbers, Sporen-Boni, Moon-Phase Nacht-Druck,
##                6-card milestone-crowned level road, interactive 30-level scrubber bar & direct-claim burst FX.

const SUB_LABELS: Array[String] = ["TALENTE", "STUFEN"]
const AVATAR_DAY: Texture2D = preload("res://assets/ui/avatars/avatar_lichtung.png")
const AVATAR_NIGHT: Texture2D = preload("res://assets/ui/avatars/avatar_leere.png")
const MEDALLIONS_TEX: Texture2D = preload("res://assets/ui/skill_medallions.png")
const LEARN_WAV: AudioStream = preload("res://assets/audio/waystone/chime_b.wav")
const CLICK_WAV: AudioStream = preload("res://assets/audio/sfx/item_pickup.wav")

# Hand-crafted sprite regions in assets/ui/skill_medallions.png (256x144)
const MED_LOCKED: Rect2 = Rect2(4, 4, 36, 36)
const MED_READY: Rect2 = Rect2(44, 4, 36, 36)
const MED_COMBAT: Rect2 = Rect2(84, 4, 36, 36)
const MED_MOVE: Rect2 = Rect2(124, 4, 36, 36)
const MED_SHADOW: Rect2 = Rect2(164, 4, 36, 36)
const MED_HALO: Rect2 = Rect2(204, 2, 44, 44)

const ECHO_HIDDEN: Rect2 = Rect2(4, 50, 24, 24)
const ECHO_READY: Rect2 = Rect2(32, 50, 24, 24)
const ECHO_COMBAT: Rect2 = Rect2(60, 50, 24, 24)
const ECHO_MOVE: Rect2 = Rect2(88, 50, 24, 24)
const ECHO_SHADOW: Rect2 = Rect2(116, 50, 24, 24)
const HUB_CORE: Rect2 = Rect2(148, 48, 32, 32)
const SOUTH_SEAL: Rect2 = Rect2(188, 50, 24, 24)

const GEM_LOCKED: Rect2 = Rect2(4, 118, 8, 8)
const GEM_READY: Rect2 = Rect2(16, 118, 8, 8)
const GEM_LEARNED: Rect2 = Rect2(28, 118, 8, 8)

const ICON_RECTS: Dictionary = {
	"combo3": Rect2(4, 90, 18, 18),
	"stride": Rect2(26, 90, 18, 18),
	"sneak": Rect2(48, 90, 18, 18),
	"climb": Rect2(70, 90, 18, 18),
	"rift": Rect2(92, 90, 18, 18),
	"light_step": Rect2(114, 90, 18, 18),
	"combo4": Rect2(136, 90, 18, 18),
	"combo5": Rect2(158, 90, 18, 18),
	"echo": Rect2(180, 90, 18, 18),
}

const COL_COMBAT: Color = Color("e6c468")
const COL_MOVE: Color = Color("78f4e6")
const COL_SHADOW: Color = Color("b98cff")
const COL_HEALTH: Color = Color("eb6b82")
const COL_STAMINA: Color = Color("78f4e6")
const COL_ARMOR: Color = Color("9ab0d8")
const COL_OVERHEAL: Color = Color("82f0be")

## Sacred Center Diamond (Raute) + 4 Cardinal Branches (West=KAMPF, North=BEWEGUNG, East=LEERE, South=Sealed 4th Path)
const HUB_NORM: Vector2 = Vector2(0.50, 0.64)
const SOUTH_SEAL_NORM: Vector2 = Vector2(0.50, 0.88)

const NODE_LAYOUT: Dictionary = {
	# WEST arm — KAMPF (starts at West diamond vertex, expands West)
	"sword_combo": Vector2(0.29, 0.64),
	"combat_echo_b": Vector2(0.10, 0.64),
	# NORTH arm — BEWEGUNG (starts at North diamond vertex, fans North)
	"sprint": Vector2(0.50, 0.40),
	"sneak": Vector2(0.28, 0.27),
	"wall_climb": Vector2(0.72, 0.27),
	"movement_echo_a": Vector2(0.50, 0.21),
	"movement_echo_b": Vector2(0.50, 0.06),
	# EAST arm — LEERE (starts at East diamond vertex, expands East)
	"shadow_step": Vector2(0.71, 0.64),
	"shadow_echo_a": Vector2(0.85, 0.44),
	"shadow_echo_b": Vector2(0.85, 0.80),
	"shadow_echo_c": Vector2(0.94, 0.64),
}

var _player: Node = null
var _skills: SkillTreeComponent = null
var _progress: ProgressComponent = null
var _sub: int = 0 ## 0 = TALENTE, 1 = STUFEN
var _time: float = 0.0
var _bursts: Array[Dictionary] = []

# Talente state
var _selected_skill: String = "sword_combo"
var _hover_skill: String = ""
var _hover_action: bool = false
var _skill_rects: Array[Dictionary] = [] ## {rect, id, center}
var _upgrade_rects: Array[Dictionary] = [] ## {rect, id}
var _action_rect: Rect2 = Rect2()
var _south_seal_rect: Rect2 = Rect2()
var _hover_south_seal: bool = false
var _node_centers: Dictionary = {} ## nid -> Vector2

# Stufen state
var _selected_level: int = 2
var _level_offset: int = 1
var _hover_level: int = -1
var _hover_claim_all: bool = false
var _hover_prev: bool = false
var _hover_next: bool = false
var _level_rects: Array[Dictionary] = [] ## {rect, level}
var _claim_rect: Rect2 = Rect2()
var _prev_rect: Rect2 = Rect2()
var _next_rect: Rect2 = Rect2()
var _scrubber_rect: Rect2 = Rect2()

# Sub-tab bar
var _sub_rects: Array[Rect2] = []
var _hover_sub: int = -1


func bind(player: Node) -> void:
	_player = player
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if player != null and is_instance_valid(player):
		_skills = player.get_node_or_null("SkillTreeComponent") as SkillTreeComponent
		_progress = player.get("progress") as ProgressComponent
		if _skills != null and not _skills.changed.is_connected(queue_redraw):
			_skills.changed.connect(queue_redraw)
		if _progress != null and not _progress.changed.is_connected(queue_redraw):
			_progress.changed.connect(queue_redraw)


func show_sub(index: int) -> void:
	_sub = clampi(index, 0, 1)
	if _sub == 1 and _progress != null:
		var focus_lv: int = clampi(_progress.claimed + 1 if _progress.claimable() > 0 else _progress.level, 1, Levels.max_level())
		_selected_level = focus_lv
		_level_offset = clampi(focus_lv - 1, 1, maxi(1, Levels.max_level() - 5))
	queue_redraw()


func close_embedded() -> void:
	_hover_skill = ""
	_hover_level = -1
	_hover_action = false
	_hover_claim_all = false


func _spawn_burst(pos: Vector2, col: Color) -> void:
	_bursts.append({"pos": pos, "age": 0.0, "max_age": 0.62, "col": col})


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	for i: int in range(_bursts.size() - 1, -1, -1):
		_bursts[i]["age"] = float(_bursts[i]["age"]) + delta
		if float(_bursts[i]["age"]) >= float(_bursts[i]["max_age"]):
			_bursts.remove_at(i)
	queue_redraw()


# --- Input -----------------------------------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion:
		_update_hover((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if not mb.pressed:
			return
		if _sub == 1 and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var step: int = -1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1
			_level_offset = clampi(_level_offset + step, 1, maxi(1, Levels.max_level() - 5))
			queue_redraw()
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_handle_click(mb.position)
			accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var ke: InputEventKey = event as InputEventKey
	if ke == null or not ke.pressed or ke.echo:
		return
	if _sub == 0:
		var dir: Vector2 = Vector2.ZERO
		if ke.keycode == KEY_LEFT or ke.keycode == KEY_A:
			dir = Vector2.LEFT
		elif ke.keycode == KEY_RIGHT or ke.keycode == KEY_D:
			dir = Vector2.RIGHT
		elif ke.keycode == KEY_UP or ke.keycode == KEY_W:
			dir = Vector2.UP
		elif ke.keycode == KEY_DOWN or ke.keycode == KEY_S:
			dir = Vector2.DOWN
		elif ke.keycode == KEY_ENTER or ke.keycode == KEY_SPACE:
			_trigger_skill_action()
			get_viewport().set_input_as_handled()
			return
		if dir != Vector2.ZERO:
			_navigate_constellation(dir)
			get_viewport().set_input_as_handled()
	else:
		var max_lv: int = Levels.max_level()
		if ke.keycode == KEY_LEFT or ke.keycode == KEY_A:
			_selected_level = maxi(1, _selected_level - 1)
			if _selected_level < _level_offset:
				_level_offset = _selected_level
			Sfx.ui(self, "ui_click", -6.0)
			queue_redraw()
			get_viewport().set_input_as_handled()
		elif ke.keycode == KEY_RIGHT or ke.keycode == KEY_D:
			_selected_level = mini(max_lv, _selected_level + 1)
			if _selected_level > _level_offset + 5:
				_level_offset = _selected_level - 5
			Sfx.ui(self, "ui_click", -6.0)
			queue_redraw()
			get_viewport().set_input_as_handled()
		elif ke.keycode == KEY_ENTER or ke.keycode == KEY_SPACE:
			if _progress != null and _progress.claimable() > 0:
				_claim_levels(_progress.level, _claim_rect.get_center() if _claim_rect.has_area() else size * 0.5)
				get_viewport().set_input_as_handled()


func _navigate_constellation(dir: Vector2) -> void:
	if not _node_centers.has(_selected_skill):
		return
	var cur_p: Vector2 = _node_centers[_selected_skill] as Vector2
	var best_id: String = ""
	var best_score: float = INF
	for nid: String in _node_centers:
		if nid == _selected_skill:
			continue
		var delta_v: Vector2 = (_node_centers[nid] as Vector2) - cur_p
		var along: float = delta_v.dot(dir)
		if along <= 8.0:
			continue
		var perp: float = absf(delta_v.cross(dir))
		var score: float = along + perp * 1.85
		if score < best_score:
			best_score = score
			best_id = nid
	if not best_id.is_empty():
		_selected_skill = best_id
		Sfx.ui(self, "ui_click", -6.0)
		queue_redraw()


func _update_hover(mp: Vector2) -> void:
	_hover_sub = -1
	for i: int in _sub_rects.size():
		if _sub_rects[i].has_point(mp):
			_hover_sub = i
			break
	if _sub == 0:
		_hover_skill = ""
		for d: Dictionary in _skill_rects:
			if (d["rect"] as Rect2).has_point(mp):
				_hover_skill = String(d["id"])
				break
		if _hover_skill.is_empty():
			for d2: Dictionary in _upgrade_rects:
				if (d2["rect"] as Rect2).has_point(mp):
					_hover_skill = String(d2["id"])
					break
		_hover_action = _action_rect.has_area() and _action_rect.has_point(mp)
		_hover_south_seal = _south_seal_rect.has_area() and _south_seal_rect.has_point(mp)
	else:
		_hover_level = -1
		for d3: Dictionary in _level_rects:
			if (d3["rect"] as Rect2).has_point(mp):
				_hover_level = int(d3["level"])
				break
		_hover_claim_all = _claim_rect.has_area() and _claim_rect.has_point(mp)
		_hover_prev = _prev_rect.has_area() and _prev_rect.has_point(mp)
		_hover_next = _next_rect.has_area() and _next_rect.has_point(mp)


func _handle_click(mp: Vector2) -> void:
	for i: int in _sub_rects.size():
		if _sub_rects[i].has_point(mp):
			if i != _sub:
				show_sub(i)
				Sfx.ui(self, "ui_click", -5.0)
			return
	if _sub == 0:
		for d: Dictionary in _skill_rects:
			if (d["rect"] as Rect2).has_point(mp):
				var nid: String = String(d["id"])
				if nid == _selected_skill and _skills != null and (_skills.can_explore(nid) or _skills.can_learn(nid)):
					_trigger_skill_action()
				else:
					_selected_skill = nid
					Sfx.ui(self, "ui_click", -5.0)
				queue_redraw()
				return
		for d2: Dictionary in _upgrade_rects:
			if (d2["rect"] as Rect2).has_point(mp):
				var uid: String = String(d2["id"])
				if _skills != null and _skills.can_learn(uid):
					_skills.request_learn(uid)
					var bp: Vector2 = _node_centers.get(_selected_skill, (d2["rect"] as Rect2).get_center()) as Vector2
					_spawn_burst(bp, MenuChrome.COL_GOLD_HOT)
					_spawn_burst((d2["rect"] as Rect2).get_center(), MenuChrome.COL_TEAL)
					Sfx.ui_stream(self, LEARN_WAV, -4.0, 0.04)
				else:
					Sfx.ui(self, "ui_click", -6.0)
				queue_redraw()
				return
		if _action_rect.has_area() and _action_rect.has_point(mp):
			_trigger_skill_action()
	else:
		if _prev_rect.has_area() and _prev_rect.has_point(mp):
			_level_offset = maxi(1, _level_offset - 2)
			Sfx.ui(self, "ui_click", -6.0)
			queue_redraw()
			return
		if _next_rect.has_area() and _next_rect.has_point(mp):
			_level_offset = mini(maxi(1, Levels.max_level() - 5), _level_offset + 2)
			Sfx.ui(self, "ui_click", -6.0)
			queue_redraw()
			return
		if _scrubber_rect.has_area() and _scrubber_rect.grow(3.0).has_point(mp):
			var u: float = clampf((mp.x - _scrubber_rect.position.x) / maxf(_scrubber_rect.size.x, 1.0), 0.0, 1.0)
			var pick_lv: int = clampi(1 + roundi(u * float(Levels.max_level() - 1)), 1, Levels.max_level())
			_selected_level = pick_lv
			_level_offset = clampi(pick_lv - 2, 1, maxi(1, Levels.max_level() - 5))
			Sfx.ui(self, "ui_click", -6.0)
			queue_redraw()
			return
		for d3: Dictionary in _level_rects:
			if (d3["rect"] as Rect2).has_point(mp):
				var lv_i: int = int(d3["level"])
				if _progress != null and lv_i > _progress.claimed and lv_i <= _progress.level and lv_i == _selected_level:
					_claim_levels(lv_i, (d3["rect"] as Rect2).get_center())
				else:
					_selected_level = lv_i
					Sfx.ui(self, "ui_click", -5.0)
				queue_redraw()
				return
		if _claim_rect.has_area() and _claim_rect.has_point(mp):
			if _progress != null and _progress.claimable() > 0:
				_claim_levels(_progress.level, _claim_rect.get_center())


func _claim_levels(up_to: int, fx_pos: Vector2) -> void:
	if _progress == null:
		return
	_progress.request_claim(up_to)
	_spawn_burst(fx_pos, MenuChrome.COL_GOLD_HOT)
	Sfx.ui_stream(self, LEARN_WAV, -3.0, 0.05)
	queue_redraw()


func _trigger_skill_action() -> void:
	if _skills == null:
		return
	var bp: Vector2 = _node_centers.get(_selected_skill, _action_rect.get_center()) as Vector2
	if _skills.can_explore(_selected_skill):
		_skills.request_explore(_selected_skill)
		_spawn_burst(bp, MenuChrome.COL_TEAL)
		Sfx.ui_stream(self, CLICK_WAV, -4.0, 0.04)
		return
	if _skills.can_learn(_selected_skill):
		_skills.request_learn(_selected_skill)
		_spawn_burst(bp, MenuChrome.COL_GOLD_HOT)
		Sfx.ui_stream(self, LEARN_WAV, -4.0, 0.04)
		return
	for up_id: String in _skills.upgrade_chain(_selected_skill):
		if _skills.can_learn(up_id):
			_skills.request_learn(up_id)
			_spawn_burst(bp, MenuChrome.COL_GOLD_HOT)
			Sfx.ui_stream(self, LEARN_WAV, -4.0, 0.04)
			return


# --- Drawing ---------------------------------------------------------------------------------------------------------

func _has_ready_skill() -> bool:
	if _skills == null:
		return false
	for nid: String in _skills.definitions():
		if _skills.can_learn(nid) or _skills.can_explore(nid):
			return true
	return false


func _draw() -> void:
	if not visible:
		return
	var vw: float = size.x if size.x > 16.0 else 640.0
	var vh: float = size.y if size.y > 16.0 else 306.0
	_draw_sub_bar(vw)
	if _sub == 0:
		_draw_talents(vw, vh)
	else:
		_draw_levels(vw, vh)
	MenuChrome.draw_burst_rings(self, _bursts)


func _draw_sub_bar(vw: float) -> void:
	_sub_rects.clear()
	var widths: Array[float] = []
	var total_w: float = 0.0
	for lbl: String in SUB_LABELS:
		var w: float = float(PixelText.width(lbl)) + 24.0
		widths.append(w)
		total_w += w
	total_w += 6.0
	var x: float = roundf((vw - total_w) * 0.5)
	for i: int in SUB_LABELS.size():
		var r: Rect2 = Rect2(x, 4.0, widths[i], 19.0)
		_sub_rects.append(r)
		var active: bool = (i == _sub)
		MenuChrome.draw_tab_pill(self, r, active, 1.0 if i == _hover_sub else 0.0)
		if active:
			MenuChrome.draw_shimmer(self, r, _time, MenuChrome.COL_GOLD_HOT)
		MenuChrome.draw_text_centered(self, SUB_LABELS[i], r.get_center().x, r.position.y + 6.0, MenuChrome.COL_GOLD_HOT if active else MenuChrome.COL_TEXT_SOFT)
		var badge: bool = (_has_ready_skill() if i == 0 else (_progress != null and _progress.claimable() > 0))
		if badge:
			MenuChrome.draw_badge(self, Vector2(r.end.x - 6.0, r.position.y - 2.0), _time)
		x += widths[i] + 6.0


# --- Sub-Tab 0: TALENTE ----------------------------------------------------------------------------------------------

func _branch_color(branch_id: String, node_id: String = "") -> Color:
	if node_id == "shadow_step" and _player != null and bool(_player.get("light_step")):
		return COL_COMBAT
	match branch_id:
		"combat":
			return COL_COMBAT
		"movement":
			return COL_MOVE
		_:
			return COL_SHADOW


func _branch_tally(branch_id: String) -> Vector2i:
	var done_n: int = 0
	var tot_n: int = 0
	if _skills == null:
		return Vector2i.ZERO
	var defs: Dictionary = _skills.definitions()
	for nid: String in NODE_LAYOUT:
		if not defs.has(nid):
			continue
		var def: Dictionary = defs[nid] as Dictionary
		if String(def.get("branch", "shadow")) != branch_id:
			continue
		tot_n += 1
		if _skills.is_awake(nid) or _skills.is_explored(nid):
			done_n += 1
	return Vector2i(done_n, tot_n)


func _draw_talents(vw: float, vh: float) -> void:
	_skill_rects.clear()
	_upgrade_rects.clear()
	_node_centers.clear()
	_action_rect = Rect2()
	_south_seal_rect = Rect2()
	if _skills == null:
		return

	var top_y: float = 28.0
	var pan_h: float = vh - top_y - 8.0
	var left_r: Rect2 = Rect2(12.0, top_y, 412.0, pan_h)
	var right_r: Rect2 = Rect2(432.0, top_y, vw - 444.0, pan_h)

	# --- Left Astral Compass & Diamond Constellation Panel ---
	MenuChrome.draw_slate(self, left_r)
	MenuChrome.draw_corners(self, left_r)
	MenuChrome.draw_text(self, "SCHLEIERGEFLECHT", left_r.position + Vector2(12.0, 9.0), MenuChrome.COL_GOLD)

	var free_pts: int = _skills.points_free()
	var pts_txt: String = "%d PUNKTE FREI" % free_pts if free_pts != 1 else "1 PUNKT FREI"
	var chip_w: float = float(PixelText.width(pts_txt)) + 14.0
	var pts_r: Rect2 = Rect2(left_r.end.x - chip_w - 10.0, left_r.position.y + 6.0, chip_w, 13.0)
	MenuChrome.draw_chip(
		self, pts_r, pts_txt,
		Color("2c2210") if free_pts > 0 else Color("171326"),
		MenuChrome.COL_GOLD if free_pts > 0 else Color("3d3358"),
		MenuChrome.COL_GOLD_HOT if free_pts > 0 else MenuChrome.COL_TEXT_DIM
	)

	# Nocturnal astral Schleier-Samt canvas (1:1 tiled cosmos!)
	var canvas_r: Rect2 = Rect2(left_r.position.x + 8.0, left_r.position.y + 23.0, left_r.size.x - 16.0, left_r.size.y - 31.0)
	MenuChrome.draw_cosmos(self, canvas_r)

	var inner_r: Rect2 = Rect2(canvas_r.position.x + 12.0, canvas_r.position.y + 8.0, canvas_r.size.x - 24.0, canvas_r.size.y - 16.0)
	var hub_pos: Vector2 = (inner_r.position + Vector2(HUB_NORM.x * inner_r.size.x, HUB_NORM.y * inner_r.size.y)).round()
	var south_pos: Vector2 = (inner_r.position + Vector2(SOUTH_SEAL_NORM.x * inner_r.size.x, SOUTH_SEAL_NORM.y * inner_r.size.y)).round()

	# Faint concentric pixel astrolabe rings around the Center Diamond Hub
	for ring_spec: Array in [[58.0, 44, Color("3c2f66", 0.24)], [102.0, 64, Color("342859", 0.18)], [146.0, 84, Color("2b214a", 0.14)]]:
		var rr: float = float(ring_spec[0])
		var segs: int = int(ring_spec[1])
		var rc: Color = ring_spec[2] as Color
		for si: int in segs:
			var ang: float = float(si) * TAU / float(segs) + _time * (0.04 if rr < 80.0 else -0.025)
			var rp: Vector2 = (hub_pos + Vector2(cos(ang), sin(ang)) * rr).round()
			if canvas_r.grow(-3.0).has_point(rp):
				draw_rect(Rect2(rp, Vector2.ONE), rc)

	# Faint cardinal compass guide axes extending from Hub to edges of canvas
	draw_line(Vector2(canvas_r.position.x + 6.0, hub_pos.y), Vector2(hub_pos.x - 18.0, hub_pos.y), Color(COL_COMBAT.r, COL_COMBAT.g, COL_COMBAT.b, 0.14), 1.0)
	draw_line(Vector2(hub_pos.x + 18.0, hub_pos.y), Vector2(canvas_r.end.x - 6.0, hub_pos.y), Color(COL_SHADOW.r, COL_SHADOW.g, COL_SHADOW.b, 0.14), 1.0)
	draw_line(Vector2(hub_pos.x, canvas_r.position.y + 6.0), Vector2(hub_pos.x, hub_pos.y - 18.0), Color(COL_MOVE.r, COL_MOVE.g, COL_MOVE.b, 0.14), 1.0)
	draw_line(Vector2(hub_pos.x, hub_pos.y + 18.0), Vector2(hub_pos.x, canvas_r.end.y - 6.0), Color("5b4d7c", 0.16), 1.0)

	# Live twinkling starfield & drifting astral motes
	MenuChrome.draw_panel_spores(self, canvas_r, _time, 19, MenuChrome.COL_VIOLET, 14, 0.72)

	# Compute node screen positions inside inner_r
	var defs: Dictionary = _skills.definitions()
	for nid: String in NODE_LAYOUT:
		if not defs.has(nid) or not _skills.is_visible(nid):
			continue
		var norm: Vector2 = NODE_LAYOUT[nid] as Vector2
		var drift: Vector2 = Vector2(0.0, sin(_time * 1.45 + norm.x * 7.0 + norm.y * 5.0) * 1.0)
		_node_centers[nid] = (inner_r.position + Vector2(norm.x * inner_r.size.x, norm.y * inner_r.size.y) + drift).round()

	# Sacred Center Diamond (Raute) connecting the 4 cardinal vertices: W <-> N <-> E <-> S <-> W
	var v_w: Vector2 = _node_centers.get("sword_combo", (inner_r.position + Vector2(0.29 * inner_r.size.x, HUB_NORM.y * inner_r.size.y)).round()) as Vector2
	var v_n: Vector2 = _node_centers.get("sprint", (inner_r.position + Vector2(0.50 * inner_r.size.x, 0.40 * inner_r.size.y)).round()) as Vector2
	var v_e: Vector2 = _node_centers.get("shadow_step", (inner_r.position + Vector2(0.71 * inner_r.size.x, HUB_NORM.y * inner_r.size.y)).round()) as Vector2
	var v_s: Vector2 = south_pos

	# Diamond perimeter threads (delicate brass & twilight starlight frame)
	for edge: Array in [[v_w, v_n, COL_COMBAT.lerp(COL_MOVE, 0.5)], [v_n, v_e, COL_MOVE.lerp(COL_SHADOW, 0.5)], [v_e, v_s, COL_SHADOW.darkened(0.35)], [v_s, v_w, COL_COMBAT.darkened(0.35)]]:
		var ea: Vector2 = edge[0] as Vector2
		var eb: Vector2 = edge[1] as Vector2
		var ec: Color = edge[2] as Color
		draw_line(ea, eb, Color(MenuChrome.COL_OUTLINE, 0.55), 3.0)
		draw_line(ea, eb, Color(ec.r, ec.g, ec.b, 0.34), 1.0)

	# 4 Glowing Cardinal Spokes radiating from the Center Veil Core to each vertex of the Raute
	for spoke: Array in [
		[v_w, COL_COMBAT, true],
		[v_n, COL_MOVE, true],
		[v_e, COL_SHADOW, true],
		[v_s, Color("685b8a"), false],
	]:
		var st: Vector2 = spoke[0] as Vector2
		var sc: Color = spoke[1] as Color
		var active_sp: bool = bool(spoke[2])
		draw_line(hub_pos, st, Color(MenuChrome.COL_OUTLINE, 0.85), 5.0)
		draw_line(hub_pos, st, Color(sc.r, sc.g, sc.b, 0.25 if active_sp else 0.12), 3.0)
		draw_line(hub_pos, st, Color(sc.r, sc.g, sc.b, 0.88 if active_sp else 0.32), 1.0)
		if active_sp:
			var sp_u: float = fposmod(_time * 0.52 + st.x * 0.005, 1.0)
			var orb_p: Vector2 = hub_pos.lerp(st, sp_u).round()
			draw_rect(Rect2(orb_p - Vector2(1.0, 1.0), Vector2(3.0, 3.0)), Color(sc.r, sc.g, sc.b, 0.92))
			draw_rect(Rect2(orb_p, Vector2.ONE), Color("ffffff", 0.90))

	# Branch Constellation Energy Leylines (Parent -> Child)
	for nid: String in _node_centers:
		var def: Dictionary = defs[nid] as Dictionary
		var pid: String = String(def.get("parent", ""))
		if pid.is_empty() or not _node_centers.has(pid):
			continue
		var a: Vector2 = _node_centers[pid] as Vector2
		var b: Vector2 = _node_centers[nid] as Vector2
		var bcol: Color = _branch_color(String(def.get("branch", "shadow")), nid)
		var awake: bool = _skills.is_awake(nid)
		var explored: bool = _skills.is_explored(nid)
		var can_act: bool = _skills.can_learn(nid) or _skills.can_explore(nid)
		var link_sel: bool = (nid == _selected_skill or pid == _selected_skill)
		draw_line(a, b, Color(MenuChrome.COL_OUTLINE, 0.85), 5.0)
		if awake or can_act or link_sel:
			draw_line(a, b, Color(bcol.r, bcol.g, bcol.b, 0.28), 3.0)
		var line_col: Color = Color(bcol.r, bcol.g, bcol.b, 0.95 if (awake or link_sel) else (0.58 if explored else 0.28))
		draw_line(a, b, line_col, 1.0)
		if awake or can_act or explored:
			var u: float = fposmod(_time * (0.78 if can_act else 0.46) + a.x * 0.01, 1.0)
			var pt: Vector2 = a.lerp(b, u).round()
			var dot_c: Color = MenuChrome.COL_GOLD_HOT if can_act else bcol
			draw_rect(Rect2(pt - Vector2(1.0, 1.0), Vector2(3.0, 3.0)), Color(dot_c.r, dot_c.g, dot_c.b, 0.95 if (awake or can_act) else 0.60))
			draw_rect(Rect2(pt, Vector2.ONE), Color("ffffff", 0.88 if (awake or can_act) else 0.45))

	# Center Sacred Veil Core (32x32 ornate astrolabe crystal heart)
	if MEDALLIONS_TEX != null:
		var hub_pulse: float = 0.72 + 0.28 * sin(_time * 2.8)
		draw_rect(Rect2(hub_pos - Vector2(17.0, 17.0), Vector2(34.0, 34.0)), Color(MenuChrome.COL_VIOLET.r, MenuChrome.COL_VIOLET.g, MenuChrome.COL_VIOLET.b, 0.10 * hub_pulse))
		draw_texture_rect_region(MEDALLIONS_TEX, Rect2((hub_pos - Vector2(16.0, 16.0)).round(), Vector2(32.0, 32.0)), HUB_CORE)
		# Dormant 4th Cardinal South Seal (24x24)
		_south_seal_rect = Rect2((south_pos - Vector2(12.0, 12.0)).round(), Vector2(24.0, 24.0))
		draw_texture_rect_region(MEDALLIONS_TEX, _south_seal_rect, SOUTH_SEAL, Color(1.12, 1.12, 1.2, 1.0) if _hover_south_seal else Color.WHITE)
		if _hover_south_seal:
			var stxt: String = "4. PFAD · VERBORGEN"
			var stw: float = float(PixelText.width(stxt)) + 12.0
			MenuChrome.draw_chip(self, Rect2(roundf(south_pos.x - stw * 0.5), south_pos.y - 25.0, stw, 12.0), stxt, Color("17132a"), Color("6c5c94"), MenuChrome.COL_TEXT_SOFT)

	# Cardinal Branch Legend Badges tucked cleanly into their compass quadrants
	var c_t: Vector2i = _branch_tally("combat")
	var m_t: Vector2i = _branch_tally("movement")
	var s_t: Vector2i = _branch_tally("shadow")
	_draw_branch_badge(Vector2(canvas_r.position.x + 8.0, canvas_r.end.y - 18.0), "KAMPF %d/%d" % [c_t.x, c_t.y], COL_COMBAT, false)
	_draw_branch_badge(Vector2(canvas_r.position.x + 8.0, canvas_r.position.y + 6.0), "BEWEGUNG %d/%d" % [m_t.x, m_t.y], COL_MOVE, false)
	_draw_branch_badge(Vector2(canvas_r.end.x - 8.0, canvas_r.end.y - 18.0), "LEERE %d/%d" % [s_t.x, s_t.y], COL_SHADOW, true)

	# Draw Ornate Octagonal Major Ability Medallions & Faceted Diamond Echo Crystals!
	for nid: String in _node_centers:
		var def: Dictionary = defs[nid] as Dictionary
		var center: Vector2 = _node_centers[nid] as Vector2
		var branch_id: String = String(def.get("branch", "shadow"))
		var bcol: Color = _branch_color(branch_id, nid)
		var awake: bool = _skills.is_awake(nid)
		var can_exp: bool = _skills.can_explore(nid)
		var ready: bool = _skills.can_learn(nid) or _skills.has_ready_upgrade(nid) or can_exp
		var is_ph: bool = bool(def.get("placeholder", false))
		var explored: bool = _skills.is_explored(nid)
		var sel: bool = (nid == _selected_skill)
		var hov: bool = (nid == _hover_skill)
		var hit_r: float = 18.0 if (not is_ph) else 13.0
		var hit: Rect2 = Rect2(center - Vector2(hit_r, hit_r), Vector2(hit_r * 2.0, hit_r * 2.0))
		_skill_rects.append({"rect": hit, "id": nid, "center": center})

		# Soft breathing radial starlight aura behind awake / ready nodes
		if ready or awake or sel:
			var pulse: float = 0.62 + 0.38 * sin(_time * (4.4 if ready else 2.2) + center.x * 0.03)
			var aura_c: Color = MenuChrome.COL_TEAL if can_exp else (MenuChrome.COL_GOLD_HOT if ready else bcol)
			var aura_sz: float = (20.0 if not is_ph else 13.0) + (2.0 if sel else 0.0)
			draw_circle(center, aura_sz, Color(aura_c.r, aura_c.g, aura_c.b, (0.18 if ready else (0.12 if sel else 0.07)) * pulse))

		# Render hand-pixelated Medallion / Diamond Crystal from skill_medallions.png
		if is_ph:
			var echo_reg: Rect2 = ECHO_HIDDEN
			if can_exp:
				echo_reg = ECHO_READY
			elif explored:
				echo_reg = ECHO_COMBAT if branch_id == "combat" else (ECHO_MOVE if branch_id == "movement" else ECHO_SHADOW)
			var tint_e: Color = Color(1.16, 1.16, 1.22, 1.0) if (sel or hov) else Color.WHITE
			if MEDALLIONS_TEX != null:
				draw_texture_rect_region(MEDALLIONS_TEX, Rect2((center - Vector2(12.0, 12.0)).round(), Vector2(24.0, 24.0)), echo_reg, tint_e)
			if sel or hov:
				var s_col: Color = MenuChrome.COL_GOLD_HOT if sel else MenuChrome.COL_TEAL
				# Crisp rotated diamond highlight tips around Echo
				for off: Vector2 in [Vector2(0, -14), Vector2(0, 14), Vector2(-14, 0), Vector2(14, 0)]:
					draw_rect(Rect2((center + off - Vector2(1.0, 1.0)).round(), Vector2(2.0, 2.0)), s_col)
			if can_exp:
				MenuChrome.draw_badge(self, Vector2(center.x + 7.0, center.y - 13.0), _time)
		else:
			var med_reg: Rect2 = _medallion_region(branch_id, nid, awake, ready)
			var tint_m: Color = Color(1.14, 1.14, 1.18, 1.0) if (sel or hov) else Color.WHITE
			if MEDALLIONS_TEX != null:
				draw_texture_rect_region(MEDALLIONS_TEX, Rect2((center - Vector2(18.0, 18.0)).round(), Vector2(36.0, 36.0)), med_reg, tint_m)
			_draw_skill_icon_sprite(_resolved_icon(nid, def), center, awake or ready, 1.0 if (awake or ready) else 0.65)
			if sel and MEDALLIONS_TEX != null:
				var h_pulse: float = 0.85 + 0.15 * sin(_time * 4.5)
				draw_texture_rect_region(MEDALLIONS_TEX, Rect2((center - Vector2(22.0, 22.0)).round(), Vector2(44.0, 44.0)), MED_HALO, Color(1.0, 1.0, 1.0, h_pulse))
			elif hov and MEDALLIONS_TEX != null:
				draw_texture_rect_region(MEDALLIONS_TEX, Rect2((center - Vector2(22.0, 22.0)).round(), Vector2(44.0, 44.0)), MED_HALO, Color(MenuChrome.COL_TEAL.r, MenuChrome.COL_TEAL.g, MenuChrome.COL_TEAL.b, 0.72))

			# Faceted 8x8 upgrade gem pips orbiting the top crown of the medallion
			var chain: Array[String] = _skills.upgrade_chain(nid)
			if not chain.is_empty() and MEDALLIONS_TEX != null:
				var px0: float = center.x - float(chain.size() - 1) * 5.0
				for ui: int in chain.size():
					var st: StringName = _skills.upgrade_state(chain[ui])
					var g_reg: Rect2 = GEM_LEARNED if st == &"learned" else (GEM_READY if st == &"ready" else GEM_LOCKED)
					draw_texture_rect_region(MEDALLIONS_TEX, Rect2(roundf(px0 + float(ui) * 10.0) - 4.0, roundf(center.y - 23.0), 8.0, 8.0), g_reg)
			elif ready:
				MenuChrome.draw_badge(self, Vector2(center.x + 12.0, center.y - 18.0), _time)

		# Clean node label (placed cleanly below medallion, or above if near bottom edge)
		if not is_ph or sel or hov:
			var nm: String = String(def.get("name", nid)).to_upper()
			if nid == "shadow_step" and _player != null and bool(_player.get("light_step")):
				nm = "LICHTSCHRITT"
			elif is_ph:
				nm = "ECHO ?" if not explored else "ECHO"
			var lcol: Color = MenuChrome.COL_GOLD_HOT if sel else (bcol if awake else (MenuChrome.COL_TEAL if can_exp else (MenuChrome.COL_GOLD if ready else MenuChrome.COL_TEXT_DIM)))
			var ly_off: float = (20.0 if not is_ph else 14.0)
			if center.y + ly_off + 8.0 > canvas_r.end.y - 4.0:
				ly_off = -(26.0 if not is_ph else 21.0)
			var nm_w: float = float(PixelText.width(nm))
			var lbl_r: Rect2 = Rect2(roundf(center.x - nm_w * 0.5) - 3.0, roundf(center.y + ly_off) - 1.0, nm_w + 6.0, 9.0)
			draw_rect(lbl_r, Color("0d0a1a", 0.82))
			MenuChrome.draw_text_centered(self, nm, center.x, center.y + ly_off, lcol)

	_draw_skill_detail(right_r)


func _draw_branch_badge(anchor: Vector2, label: String, col: Color, align_right: bool) -> void:
	var tw: float = float(PixelText.width(label)) + 12.0
	var bx: float = (anchor.x - tw) if align_right else anchor.x
	var r: Rect2 = Rect2(roundf(bx), roundf(anchor.y), tw, 12.0)
	MenuChrome.draw_chip(self, r, label, Color("130f22", 0.90), Color(col.r, col.g, col.b, 0.72), col)


func _medallion_region(branch_id: String, nid: String, awake: bool, ready: bool) -> Rect2:
	if ready and not awake:
		return MED_READY
	if not awake:
		return MED_LOCKED
	if nid == "shadow_step" and _player != null and bool(_player.get("light_step")):
		return MED_COMBAT
	match branch_id:
		"combat":
			return MED_COMBAT
		"movement":
			return MED_MOVE
		_:
			return MED_SHADOW


func _resolved_icon(nid: String, def: Dictionary) -> String:
	if nid == "shadow_step" and _player != null and bool(_player.get("light_step")):
		return "light_step"
	return String(def.get("icon", "echo"))


func _draw_skill_icon_sprite(icon_key: String, center: Vector2, lit: bool = true, alpha: float = 1.0) -> void:
	if MEDALLIONS_TEX == null:
		return
	var reg: Rect2 = ICON_RECTS.get(icon_key, ICON_RECTS["echo"]) as Rect2
	var tint: Color = Color(1.0, 1.0, 1.0, alpha) if lit else Color(0.62, 0.58, 0.78, alpha)
	draw_texture_rect_region(MEDALLIONS_TEX, Rect2((center - Vector2(9.0, 9.0)).round(), Vector2(18.0, 18.0)), reg, tint)


func _draw_skill_detail(r: Rect2) -> void:
	MenuChrome.draw_slate(self, r)
	MenuChrome.draw_corners(self, r)
	if _skills == null:
		return
	var def: Dictionary = _skills.node(_selected_skill)
	if def.is_empty():
		return
	var branch_id: String = String(def.get("branch", "shadow"))
	var bcol: Color = _branch_color(branch_id, _selected_skill)
	var bname: String = String((DataRegistry.get_entry("skills", "branches").get(branch_id, {}) as Dictionary).get("name", branch_id)).to_upper()
	var awake: bool = _skills.is_awake(_selected_skill)
	var is_ph: bool = bool(def.get("placeholder", false))
	var explored: bool = _skills.is_explored(_selected_skill)
	var lstate: StringName = _skills.learn_state(_selected_skill)
	var ready_now: bool = _skills.can_learn(_selected_skill) or _skills.can_explore(_selected_skill)

	var x: float = r.position.x + 11.0
	var w: float = r.size.x - 22.0
	var y: float = r.position.y + 9.0

	# Ornate showcase medallion box on the top-left of the detail card
	var icon_box: Rect2 = Rect2(x, y, 40.0, 40.0)
	MenuChrome.draw_cosmos(self, icon_box)
	if MEDALLIONS_TEX != null:
		if is_ph:
			var er: Rect2 = ECHO_READY if _skills.can_explore(_selected_skill) else ((ECHO_COMBAT if branch_id == "combat" else (ECHO_MOVE if branch_id == "movement" else ECHO_SHADOW)) if explored else ECHO_HIDDEN)
			draw_texture_rect_region(MEDALLIONS_TEX, Rect2((icon_box.get_center() - Vector2(12.0, 12.0)).round(), Vector2(24.0, 24.0)), er)
		else:
			var mr: Rect2 = _medallion_region(branch_id, _selected_skill, awake, ready_now)
			draw_texture_rect_region(MEDALLIONS_TEX, Rect2((icon_box.get_center() - Vector2(18.0, 18.0)).round(), Vector2(36.0, 36.0)), mr)
			_draw_skill_icon_sprite(_resolved_icon(_selected_skill, def), icon_box.get_center(), true, 1.0)

	var tx: float = x + 46.0
	var tw: float = w - 46.0
	var title_txt: String = String(def.get("name", _selected_skill)).to_upper()
	if _selected_skill == "shadow_step" and _player != null and bool(_player.get("light_step")):
		title_txt = "LICHTSCHRITT"
	MenuChrome.draw_text(self, MenuChrome.fit_text(title_txt, tw), Vector2(tx, y + 3.0), bcol)

	var status_lbl: String = "ERLERNT"
	var st_fill: Color = Color("143634")
	var st_rim: Color = MenuChrome.COL_TEAL
	var st_txt: Color = MenuChrome.COL_TEAL
	if is_ph:
		status_lbl = "PFAD OFFEN" if explored else "BEREIT · FREI" if _skills.can_explore(_selected_skill) else "VERBORG. ECHO"
		st_fill = Color("163038") if explored else (Color("2c2210") if _skills.can_explore(_selected_skill) else Color("1c162b"))
		st_rim = MenuChrome.COL_TEAL if explored else (MenuChrome.COL_GOLD if _skills.can_explore(_selected_skill) else Color("4a3e6b"))
		st_txt = MenuChrome.COL_TEAL if explored else (MenuChrome.COL_GOLD_HOT if _skills.can_explore(_selected_skill) else MenuChrome.COL_TEXT_DIM)
	elif not awake:
		if lstate == &"ready":
			status_lbl = "BEREIT · %d PKT" % _skills.cost(_selected_skill)
			st_fill = Color("332510")
			st_rim = MenuChrome.COL_GOLD
			st_txt = MenuChrome.COL_GOLD_HOT
		elif lstate == &"locked":
			status_lbl = "AB STUFE %d" % _skills.required_level(_selected_skill)
			st_fill = Color("1c162b")
			st_rim = Color("524670")
			st_txt = MenuChrome.COL_TEXT_DIM
		else:
			status_lbl = "%d PKT NÖTIG" % _skills.cost(_selected_skill)
			st_fill = Color("2a1622")
			st_rim = Color("8b4254")
			st_txt = Color("e898a6")
	MenuChrome.draw_text(self, bname, Vector2(tx, y + 14.0), MenuChrome.COL_TEXT_DIM)
	var cw: float = minf(float(PixelText.width(status_lbl)) + 10.0, tw)
	MenuChrome.draw_chip(self, Rect2(tx, y + 25.0, cw, 11.0), status_lbl, st_fill, st_rim, st_txt)

	y += 45.0
	MenuChrome.draw_divider(self, r.get_center().x, y, w)
	y += 11.0

	# Context-accurate description
	var desc: String = String(def.get("description", ""))
	if is_ph:
		if explored:
			desc = "Dieser Knoten des Schleiergeflechts ist enthüllt. Seine Fäden tragen die Kraft dieses Zweigs weiter — wähle ein angrenzendes Talent oder das nächste Echo."
		elif _skills.can_explore(_selected_skill):
			desc = "Ein leises Echo im Schleiergeflecht. Erwecke es kostenlos, um tieferliegende Pfade dieses Zweigs sichtbar zu machen."
		else:
			desc = "Ein fernes Echo hinter unberührten Fäden. Erkunde zuerst den vorgelagerten Knoten."
	for line: String in MenuChrome.wrap_lines(desc, w):
		MenuChrome.draw_text(self, line, Vector2(x, y), MenuChrome.COL_TEXT)
		y += 10.0

	var detail: String = String(def.get("detail", ""))
	if not detail.is_empty():
		if detail.contains("%s"):
			detail = detail % VineStyle.key_name("interact", "E")
		y += 3.0
		var d_lines: Array[String] = MenuChrome.wrap_lines(detail, w - 10.0)
		var d_box: Rect2 = Rect2(x, y, w, float(d_lines.size()) * 10.0 + 8.0)
		MenuChrome.draw_inset(self, d_box)
		for li: int in d_lines.size():
			MenuChrome.draw_text(self, d_lines[li], Vector2(x + 5.0, y + 4.0 + float(li) * 10.0), MenuChrome.COL_TEAL)
		y += d_box.size.y + 6.0

	var chain: Array[String] = _skills.upgrade_chain(_selected_skill)
	if not chain.is_empty():
		MenuChrome.draw_section_header(self, Vector2(x, y + 1.0), w, "AUFWERTUNGEN", MenuChrome.COL_GOLD)
		y += 13.0
		for uid: String in chain:
			var udef: Dictionary = _skills.node(uid)
			var ust: StringName = _skills.upgrade_state(uid)
			var ur: Rect2 = Rect2(x, y, w, 34.0)
			_upgrade_rects.append({"rect": ur, "id": uid})
			var u_hov: bool = (_hover_skill == uid)
			if ust == &"ready":
				MenuChrome.draw_gold(self, ur)
				MenuChrome.draw_shimmer(self, ur, _time, MenuChrome.COL_GOLD_HOT)
			else:
				MenuChrome.draw_inset(self, ur)
			if u_hov and ust == &"ready":
				draw_rect(ur.grow(-2.0), Color(MenuChrome.COL_GOLD, 0.14))
			_draw_skill_icon_sprite(String(udef.get("icon", "combo4")), Vector2(ur.position.x + 14.0, ur.get_center().y), ust != &"locked", 1.0 if ust != &"locked" else 0.55)
			var utx: float = ur.position.x + 26.0
			var unm: String = String(udef.get("name", uid)).to_upper()
			var badge_t: String = "AKTIV" if ust == &"learned" else ("LERNEN!" if ust == &"ready" else ("ST. %d · %dP" % [_skills.required_level(uid), _skills.cost(uid)]))
			var bw: float = float(PixelText.width(badge_t))
			MenuChrome.draw_text(self, MenuChrome.fit_text(unm, ur.end.x - utx - bw - 12.0), Vector2(utx, ur.position.y + 6.0), MenuChrome.COL_TEAL if ust == &"learned" else (MenuChrome.COL_GOLD_HOT if ust == &"ready" else MenuChrome.COL_TEXT_SOFT))
			MenuChrome.draw_text(self, badge_t, Vector2(ur.end.x - bw - 6.0, ur.position.y + 6.0), MenuChrome.COL_TEAL if ust == &"learned" else (MenuChrome.COL_GOLD_HOT if ust == &"ready" else MenuChrome.COL_TEXT_DIM))
			var udesc: String = MenuChrome.fit_text(String(udef.get("detail", udef.get("description", ""))), ur.end.x - utx - 8.0)
			MenuChrome.draw_text(self, udesc, Vector2(utx, ur.position.y + 18.0), MenuChrome.COL_TEXT_DIM)
			y += 37.0

	var btn_r: Rect2 = Rect2(x, r.end.y - 29.0, w, 21.0)
	var ready_up: String = ""
	for uid2: String in chain:
		if _skills.can_learn(uid2):
			ready_up = uid2
			break
	if _skills.can_explore(_selected_skill):
		_action_rect = btn_r
		MenuChrome.draw_button(self, btn_r, "ECHO ERWECKEN (FREI)", _hover_action, true)
		MenuChrome.draw_shimmer(self, btn_r, _time, MenuChrome.COL_TEAL)
	elif _skills.can_learn(_selected_skill):
		_action_rect = btn_r
		MenuChrome.draw_button(self, btn_r, "LERNEN · %d PKT" % _skills.cost(_selected_skill), _hover_action, true)
		MenuChrome.draw_shimmer(self, btn_r, _time, MenuChrome.COL_GOLD_HOT)
	elif not ready_up.is_empty():
		_action_rect = btn_r
		var up_name: String = MenuChrome.fit_text(String(_skills.node(ready_up).get("name", "UPGRADE")), w - 58.0)
		MenuChrome.draw_button(self, btn_r, "%s · %dP" % [up_name, _skills.cost(ready_up)], _hover_action, true)
		MenuChrome.draw_shimmer(self, btn_r, _time, MenuChrome.COL_GOLD_HOT)
	else:
		var idle_lbl: String = "BEREITS AKTIV" if awake else ("PFAD OFFEN" if (is_ph and explored) else "NOCH GESPERRT")
		MenuChrome.draw_button(self, btn_r, idle_lbl, false, false, false, true)


# --- Sub-Tab 1: STUFEN -----------------------------------------------------------------------------------------------

func _draw_levels(vw: float, vh: float) -> void:
	_level_rects.clear()
	_claim_rect = Rect2()
	_prev_rect = Rect2()
	_next_rect = Rect2()
	_scrubber_rect = Rect2()
	if _progress == null:
		return

	var top_y: float = 28.0
	var pan_h: float = vh - top_y - 8.0
	var left_r: Rect2 = Rect2(12.0, top_y, 198.0, pan_h)
	var right_x: float = 218.0
	var right_w: float = vw - right_x - 12.0
	var track_r: Rect2 = Rect2(right_x, top_y, right_w, 144.0)
	var detail_r: Rect2 = Rect2(right_x, top_y + 150.0, right_w, pan_h - 150.0)

	# --- Left Stats Panel with Ellie Portrait Medallion ---
	MenuChrome.draw_slate(self, left_r)
	MenuChrome.draw_corners(self, left_r)
	var lx: float = left_r.position.x + 11.0
	var lw: float = left_r.size.x - 22.0
	var ly: float = left_r.position.y + 9.0

	var lv: int = _progress.level
	var max_lv: int = Levels.max_level()
	var claimed_lv: int = _progress.claimed
	var frac: float = Levels.fraction(_progress.xp)
	var xp_now: int = Levels.xp_into(_progress.xp)
	var xp_need: int = Levels.xp_to_next(lv)

	# Mini Ellie portrait medallion (28x28 — day Lichtung portrait / night Leere portrait) + Level & XP bar
	var pbox: Rect2 = Rect2(lx, ly - 1.0, 28.0, 28.0)
	var is_night_avatar: bool = TimeManager.night_amount() >= 0.45
	var avatar_tex: Texture2D = AVATAR_NIGHT if is_night_avatar else AVATAR_DAY
	draw_rect(pbox, MenuChrome.COL_OUTLINE)
	var rim_top: Color = MenuChrome.COL_VIOLET if is_night_avatar else MenuChrome.COL_GOLD
	var rim_bot: Color = MenuChrome.COL_VIOLET.darkened(0.45) if is_night_avatar else MenuChrome.COL_GOLD.darkened(0.45)
	draw_rect(Rect2(pbox.position.x + 1.0, pbox.position.y + 1.0, pbox.size.x - 2.0, 1.0), rim_top)
	draw_rect(Rect2(pbox.position.x + 1.0, pbox.end.y - 2.0, pbox.size.x - 2.0, 1.0), rim_bot)
	draw_rect(Rect2(pbox.position.x + 1.0, pbox.position.y + 1.0, 1.0, pbox.size.y - 2.0), rim_top)
	draw_rect(Rect2(pbox.end.x - 2.0, pbox.position.y + 1.0, 1.0, pbox.size.y - 2.0), rim_bot)
	if avatar_tex != null:
		draw_texture_rect(avatar_tex, pbox.grow(-2.0), false)
	draw_rect(Rect2(pbox.position.x + 1.0, pbox.position.y + 1.0, 2.0, 2.0), MenuChrome.COL_GOLD_HOT)

	var hx: float = lx + 33.0
	var hw: float = lw - 33.0
	MenuChrome.draw_text(self, "STUFE %d / %d" % [lv, max_lv], Vector2(hx, ly + 1.0), MenuChrome.COL_GOLD_HOT)
	var xp_txt: String = "MAX" if lv >= max_lv else "%d/%d EP" % [xp_now, xp_need]
	MenuChrome.draw_text(self, xp_txt, Vector2(hx, ly + 11.0), MenuChrome.COL_TEAL)
	MenuChrome.draw_bar(self, Rect2(hx, ly + 20.0, hw, 5.0), frac, MenuChrome.COL_GOLD)
	ly += 33.0

	MenuChrome.draw_section_header(self, Vector2(lx, ly), lw, "DEIN STAND", MenuChrome.COL_GOLD)
	ly += 13.0
	var cur_st: Dictionary = LevelRewards.stats_at(claimed_lv)
	var max_st: Dictionary = LevelRewards.stats_at(lv)
	var rows: Array[Array] = [
		["health", "LEBEN", COL_HEALTH, false],
		["stamina", "AUSDAUER", COL_STAMINA, false],
		["armor", "RÜSTUNG", COL_ARMOR, false],
		["overheal", "ÜBERHEILUNG", COL_OVERHEAL, true],
		["talismans", "TALISMANE", MenuChrome.COL_GOLD, false],
	]
	for row: Array in rows:
		var k: String = String(row[0])
		var lbl: String = String(row[1])
		var col: Color = row[2] as Color
		var is_pct: bool = bool(row[3])
		draw_rect(Rect2(lx, ly + 2.0, 4.0, 4.0), MenuChrome.COL_OUTLINE)
		draw_rect(Rect2(lx + 1.0, ly + 3.0, 2.0, 2.0), col)
		MenuChrome.draw_text(self, lbl, Vector2(lx + 8.0, ly), MenuChrome.COL_TEXT_SOFT)
		var now_v: float = float(cur_st.get(k, 0.0)) * (100.0 if is_pct else 1.0)
		var goal_v: float = float(max_st.get(k, 0.0)) * (100.0 if is_pct else 1.0)
		var pend_v: float = goal_v - now_v
		var v_txt: String = ("%d%%" % roundi(now_v)) if is_pct else str(roundi(now_v))
		var vx: float = left_r.end.x - 11.0 - float(PixelText.width(v_txt))
		if pend_v > 0.01:
			var p_txt: String = ("+%d%%" % roundi(pend_v)) if is_pct else ("+%d" % roundi(pend_v))
			var pw: float = float(PixelText.width(p_txt))
			var pulse: float = 0.70 + 0.30 * sin(_time * 3.8)
			MenuChrome.draw_text(self, p_txt, Vector2(left_r.end.x - 11.0 - pw, ly), Color(MenuChrome.COL_GOLD_HOT, pulse))
			vx = left_r.end.x - 15.0 - pw - float(PixelText.width(v_txt))
		MenuChrome.draw_text(self, v_txt, Vector2(vx, ly), MenuChrome.COL_TEXT)
		ly += 13.0

	var vt: VeilThreads = VeilThreads.of(get_tree()) if is_inside_tree() else null
	if vt != null:
		ly += 3.0
		MenuChrome.draw_section_header(self, Vector2(lx, ly), lw, "SPOREN-BONI", MenuChrome.COL_TEAL)
		ly += 12.0
		var bag_b: int = vt.bag_bonus_slots()
		var stam_b: int = roundi(vt.stamina_max_bonus())
		var lit_b: int = roundi(vt.night_light_bonus() * 100.0)
		var parts: PackedStringArray = []
		if bag_b > 0:
			parts.append("+%d TASCHE" % bag_b)
		if stam_b > 0:
			parts.append("+%d AD" % stam_b)
		if lit_b > 0:
			parts.append("+%d%% LICHT" % lit_b)
		var sb_txt: String = " · ".join(parts) if not parts.is_empty() else "SAMMLE SCHATTENFRÜCHTE"
		MenuChrome.draw_text(self, MenuChrome.fit_text(sb_txt, lw), Vector2(lx, ly), MenuChrome.COL_TEAL if not parts.is_empty() else MenuChrome.COL_TEXT_DIM)

	# Night scaling box at bottom with Moon Glyph
	var night_r: Rect2 = Rect2(lx, left_r.end.y - 42.0, lw, 33.0)
	MenuChrome.draw_inset(self, night_r)
	var more: int = roundi((NightRules.budget(lv, 1, 1) / NightRules.budget(1, 1, 1) - 1.0) * 100.0)
	var tougher: int = roundi((NightRules.strength(lv, 0.0) - 1.0) * 100.0)
	MenuChrome.draw_day_phase_glyph(self, night_r.position + Vector2(6.0, 4.0), true)
	MenuChrome.draw_text(self, "NACHT-DRUCK", night_r.position + Vector2(19.0, 6.0), MenuChrome.COL_VIOLET)
	MenuChrome.draw_text(self, "GEGNER +%d%% · ZÄHER +%d%%" % [more, tougher], night_r.position + Vector2(6.0, 18.0), MenuChrome.COL_TEXT_SOFT)

	# --- Top Right: 6-Card Level Track + 30-Level Interactive Scrubber ---
	MenuChrome.draw_slate(self, track_r)
	MenuChrome.draw_corners(self, track_r)
	MenuChrome.draw_text(self, "DER WACHSENDE WEG", track_r.position + Vector2(12.0, 9.0), MenuChrome.COL_GOLD)

	var end_vis: int = mini(_level_offset + 5, max_lv)
	_prev_rect = Rect2(track_r.end.x - 94.0, track_r.position.y + 6.0, 16.0, 14.0)
	_next_rect = Rect2(track_r.end.x - 26.0, track_r.position.y + 6.0, 16.0, 14.0)
	MenuChrome.draw_button(self, _prev_rect, "<", _hover_prev, false, false, _level_offset <= 1)
	MenuChrome.draw_text_centered(self, "%d-%d" % [_level_offset, end_vis], track_r.end.x - 52.0, track_r.position.y + 9.0, MenuChrome.COL_TEXT_SOFT)
	MenuChrome.draw_button(self, _next_rect, ">", _hover_next, false, false, end_vis >= max_lv)

	var card_w: float = 60.0
	var card_gap: float = 5.0
	var cards_total: float = 6.0 * card_w + 5.0 * card_gap
	var start_x: float = roundf(track_r.position.x + (track_r.size.x - cards_total) * 0.5)
	var card_y: float = track_r.position.y + 25.0
	var card_h: float = 96.0

	# Luminous progress road spine behind the 6 cards
	draw_rect(Rect2(start_x + 12.0, card_y + 26.0, cards_total - 24.0, 2.0), Color("3c305e", 0.85))
	var lit_cards: int = clampi(lv - _level_offset, 0, 5)
	if lit_cards > 0:
		var lit_w: float = float(lit_cards) * (card_w + card_gap)
		draw_rect(Rect2(start_x + 12.0, card_y + 26.0, minf(lit_w, cards_total - 24.0), 2.0), Color(MenuChrome.COL_TEAL, 0.85))

	for idx: int in 6:
		var n: int = _level_offset + idx
		if n > max_lv:
			break
		var cr: Rect2 = Rect2(start_x + float(idx) * (card_w + card_gap), card_y, card_w, card_h)
		_level_rects.append({"rect": cr, "level": n})
		var is_claimed: bool = n <= claimed_lv
		var is_ready: bool = n > claimed_lv and n <= lv
		var is_mile: bool = LevelRewards.is_milestone(n)
		var is_sel: bool = (n == _selected_level)
		var is_hov: bool = (n == _hover_level)

		if is_ready:
			MenuChrome.draw_gold(self, cr)
			MenuChrome.draw_shimmer(self, cr, _time, MenuChrome.COL_GOLD_HOT)
		else:
			MenuChrome.draw_inset(self, cr)

		if is_sel or is_hov:
			var sc: Color = MenuChrome.COL_GOLD_HOT if is_sel else MenuChrome.COL_TEAL
			draw_rect(Rect2(cr.position + Vector2(1.0, 1.0), Vector2(cr.size.x - 2.0, 1.0)), sc)
			draw_rect(Rect2(cr.position + Vector2(1.0, cr.size.y - 2.0), Vector2(cr.size.x - 2.0, 1.0)), sc)
			draw_rect(Rect2(cr.position + Vector2(1.0, 1.0), Vector2(1.0, cr.size.y - 2.0)), sc)
			draw_rect(Rect2(Vector2(cr.end.x - 2.0, cr.position.y + 1.0), Vector2(1.0, cr.size.y - 2.0)), sc)

		var cc: Vector2 = Vector2(cr.get_center().x, cr.position.y + 26.0)
		var ncol: Color = MenuChrome.COL_TEAL if is_claimed else (MenuChrome.COL_GOLD_HOT if is_ready else MenuChrome.COL_VIOLET)
		var nbox: Rect2 = Rect2(cc - Vector2(10.0, 10.0), Vector2(20.0, 20.0))
		draw_rect(nbox, MenuChrome.COL_OUTLINE)
		draw_rect(nbox.grow(-1.0), Color("163634") if is_claimed else (Color("382812") if is_ready else Color("1d1533")))
		draw_rect(Rect2(nbox.position + Vector2(1.0, 1.0), Vector2(18.0, 1.0)), ncol)
		MenuChrome.draw_text_centered(self, str(n), cc.x, cc.y - 3.0, ncol)
		if is_mile:
			MenuChrome.draw_crown(self, Vector2(cc.x - 6.0, cr.position.y + 3.0))

		var lines: Array[Dictionary] = LevelRewards.lines(n)
		var gy: float = cr.position.y + 44.0
		if n == 1:
			MenuChrome.draw_text_centered(self, "DER KEIM", cc.x, gy + 4.0, MenuChrome.COL_TEAL)
		elif n <= lv + 1 or is_mile:
			for li: int in mini(lines.size(), 2):
				var short_t: String = String(lines[li]["text"]).replace("LEBEN", "LP").replace("AUSDAUER", "AD").replace("RÜSTUNG", "RÜ").replace("TALISMANPLATZ", "+TALISMAN").replace("ÜBERHEILUNG ", "ÜH ")
				MenuChrome.draw_text_centered(self, MenuChrome.fit_text(short_t, card_w - 8.0), cc.x, gy + float(li) * 10.0, MenuChrome.COL_TEXT if (is_claimed or is_ready) else MenuChrome.COL_TEXT_DIM)
		else:
			MenuChrome.draw_text_centered(self, "???", cc.x, gy + 4.0, MenuChrome.COL_TEXT_DIM)

		var stag: String = "AKTIV" if is_claimed else ("BEREIT!" if is_ready else "ST. %d" % n)
		var scol: Color = MenuChrome.COL_TEAL if is_claimed else (MenuChrome.COL_GOLD_HOT if is_ready else MenuChrome.COL_TEXT_DIM)
		MenuChrome.draw_text_centered(self, stag, cc.x, cr.end.y - 13.0, scol)

	# Interactive 30-level Overview Scrubber Rail
	_scrubber_rect = Rect2(start_x, track_r.end.y - 14.0, cards_total, 7.0)
	var step_px: float = _scrubber_rect.size.x / float(max_lv)
	draw_rect(Rect2(_scrubber_rect.position.x, _scrubber_rect.position.y + 2.0, _scrubber_rect.size.x, 3.0), Color("110d1f"))
	for ln: int in range(1, max_lv + 1):
		var sx: float = _scrubber_rect.position.x + float(ln - 1) * step_px + 1.0
		var dot_c: Color = MenuChrome.COL_TEAL if ln <= claimed_lv else (MenuChrome.COL_GOLD_HOT if ln <= lv else (Color("5a4c7c") if LevelRewards.is_milestone(ln) else Color("2a2244")))
		var dh: float = 5.0 if LevelRewards.is_milestone(ln) else 3.0
		draw_rect(Rect2(roundf(sx), _scrubber_rect.position.y + (3.0 - floorf(dh * 0.5)), maxf(floorf(step_px) - 2.0, 3.0), dh), dot_c)
	# Visible window bracket on scrubber
	var win_x: float = _scrubber_rect.position.x + float(_level_offset - 1) * step_px
	var win_w: float = float(mini(6, max_lv - _level_offset + 1)) * step_px
	draw_rect(Rect2(roundf(win_x), _scrubber_rect.position.y - 1.0, roundf(win_w), 1.0), MenuChrome.COL_GOLD)
	draw_rect(Rect2(roundf(win_x), _scrubber_rect.end.y, roundf(win_w), 1.0), MenuChrome.COL_GOLD)

	# --- Bottom Right: Selected Level Detail & Claim All ---
	var claimable_n: int = _progress.claimable()
	if claimable_n > 0:
		MenuChrome.draw_gold(self, detail_r)
	else:
		MenuChrome.draw_slate(self, detail_r)
	MenuChrome.draw_corners(self, detail_r)

	var dx: float = detail_r.position.x + 12.0
	var dy: float = detail_r.position.y + 10.0
	var sn: int = clampi(_selected_level, 1, max_lv)
	var m_info: Dictionary = LevelRewards.milestone(sn)
	var st_title: String = String(m_info.get("name", "STUFE %d" % sn)).to_upper()
	if sn == 1:
		st_title = "STUFE 1 · DER KEIM"
	elif not m_info.is_empty():
		st_title = "STUFE %d · %s" % [sn, st_title]
	MenuChrome.draw_text(self, st_title, Vector2(dx, dy), MenuChrome.COL_GOLD_HOT if sn <= lv else MenuChrome.COL_TEXT_SOFT)
	var st_sub: String = "EINGELÖST" if sn <= claimed_lv else ("BEREIT ZUM EINSAMMELN" if sn <= lv else "ERREICHE STUFE %d" % sn)
	MenuChrome.draw_text(self, st_sub, Vector2(dx, dy + 12.0), MenuChrome.COL_TEAL if sn <= claimed_lv else (MenuChrome.COL_GOLD if sn <= lv else MenuChrome.COL_TEXT_DIM))

	var chip_x: float = dx
	var chip_y: float = dy + 28.0
	var max_cx: float = detail_r.end.x - 152.0
	var slines: Array[Dictionary] = LevelRewards.lines(sn)
	if slines.is_empty():
		MenuChrome.draw_text(self, "DEIN STARTPUNKT AUF ALTMARK.", Vector2(dx, chip_y + 2.0), MenuChrome.COL_TEXT_SOFT)
	else:
		for entry: Dictionary in slines:
			var etxt: String = String(entry["text"])
			var ew: float = float(PixelText.width(etxt)) + 12.0
			if chip_x + ew > max_cx and chip_x > dx:
				chip_x = dx
				chip_y += 18.0
			var k2: String = String(entry["kind"])
			var ec: Color = COL_HEALTH if k2 == "health" else (COL_STAMINA if k2 == "stamina" else (COL_ARMOR if k2 == "armor" else (COL_OVERHEAL if k2 == "overheal" else MenuChrome.COL_GOLD)))
			MenuChrome.draw_chip(self, Rect2(chip_x, chip_y, ew, 14.0), etxt, Color("171328"), ec, ec)
			chip_x += ew + 5.0

	var cbox: Rect2 = Rect2(detail_r.end.x - 144.0, detail_r.position.y + 10.0, 132.0, detail_r.size.y - 20.0)
	MenuChrome.draw_inset(self, cbox)
	if claimable_n > 0:
		MenuChrome.draw_text_centered(self, "%d BELOHNUNG%s" % [claimable_n, "" if claimable_n == 1 else "EN"], cbox.get_center().x, cbox.position.y + 8.0, MenuChrome.COL_GOLD_HOT)
		MenuChrome.draw_text_centered(self, "STUFE %d BIS %d" % [claimed_lv + 1, lv], cbox.get_center().x, cbox.position.y + 19.0, MenuChrome.COL_TEXT_SOFT)
		_claim_rect = Rect2(cbox.position.x + 8.0, cbox.end.y - 28.0, cbox.size.x - 16.0, 21.0)
		MenuChrome.draw_button(self, _claim_rect, "ALLE EINLÖSEN", _hover_claim_all, true)
		MenuChrome.draw_shimmer(self, _claim_rect, _time, MenuChrome.COL_GOLD_HOT)
	else:
		MenuChrome.draw_text_centered(self, "ALLES EINGELÖST", cbox.get_center().x, cbox.position.y + 20.0, MenuChrome.COL_TEAL)
		MenuChrome.draw_text_centered(self, "NÄCHSTE: ST. %d" % mini(lv + 1, max_lv), cbox.get_center().x, cbox.position.y + 34.0, MenuChrome.COL_TEXT_DIM)
