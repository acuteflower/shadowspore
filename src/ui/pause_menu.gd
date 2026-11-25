class_name PauseMenu
extends Control
## Escape menu, in the vine style. A root drops from the top of the screen and spreads into a
## branch; the tabs hang from it like wooden tags (Q / E or click; a bloom on the branch marks the
## open one). The town tag shows and manages the player's town (docs/town.md); the map tag is still sealed. The skill graph opens with F / Start or from the settings page. The page grows out of
## the dark: settings as sliders on vines and flower buds that open. Whatever tab is open, the
## branch growing from the right edge carries "main menu" and "quit game" (all progress auto-saves online).
## In singleplayer the game stands still while the menu is open. By night the void creeps in.

const OPEN_SECONDS: float = 0.85
const CLOSE_SECONDS: float = 0.28
const QUIT_DELAY: float = 1.2
const ARM_Y: float = 32.0
const ARM_LEN: float = 152.0
const COLUMN_X: Array[float] = [64.0, 352.0]
const COLUMN_W: float = 224.0
const TOP_Y: float = 90.0
const ROW_H: float = 17.0
const HEAD_H: float = 15.0
const INFO_H: float = 12.0
const FOOT_Y: float = 268.0
const FOOT_LEN: float = 346.0
const VALUE_X: float = 104.0 ## where a row's control starts, from the column's left
const SLIDER_W: float = 86.0
const ACCENT_WARM: Color = Color("ffd98a")
const DANGER: Color = Color("e0556e")
const SocialSidebarScript := preload("res://src/ui/pause_social_sidebar.gd")
const TABS: Array[Dictionary] = [
	{"id": "settings", "name": "EINSTELLUNGEN", "x": -118.0, "sealed": false},
	{"id": "map", "name": "KARTE", "x": -56.0, "sealed": true},
	{"id": "town", "name": "STADT", "x": 16.0, "sealed": false}, ## the skill graph stays on F / Start (and the settings page lists its key)
	{"id": "pets", "name": "VÖGEL", "x": 66.0, "sealed": false}, ## the book of the named crows and ravens (docs/pet_konzept.md)
	{"id": "coop", "name": "KOOP", "x": 118.0, "sealed": false}, ## multiplayer session info, code, IP and player roster
]
const CONTROLS: Array[Array] = [
	["BEWEGEN", "", "WASD"], ["SPRINTEN", "sprint", ""], ["SCHATTENSCHRITT", "shadow_step", ""],
	["SCHLEICHEN", "sneak", ""], ["INVENTAR", "inventory", ""], ["KARTE", "map", ""], ["GEWÖLBE", "dungeons", ""], ["TAGEBUCH", "quest_journal", ""], ["BENUTZEN", "interact", ""],
]

var _player: Node
var _open_t: float = 0.0
var _opening: bool = false
var _time: float = 0.0
var _tab: int = 0
var _test_tools: bool = false
var _tab_t: float = 1.0 ## 0 -> 1 after switching: the page grows again
var _bloom_x: float = 0.0
var _tab_lift: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
var _tab_deny: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0] ## a sealed tag shivers when clicked
var _hover_tab: int = -1
var _items: Array[Dictionary] = []
var _cursor: Array[float] = [0.0, 0.0]
var _focus: int = -1
var _drag: int = -1
var _footer: Array[Dictionary] = []
var _foot_lift: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _hover_foot: int = -1
var _armed: String = "" ## a risky action waiting for a second click
var _armed_left: float = 0.0
var _saved_flash: float = 0.0
var _failed_flash: float = 0.0
var _save_info: Dictionary = {}
var _quit_t: float = -1.0
var _quit_to_menu: bool = false
var _dirty: bool = false
var _paused_here: bool = false
var _vignette: GradientTexture2D
var _tp_text: String = "" ## the test tools' teleport field: "x, y" in tiles
var _scrolls: Array[float] = [0.0, 0.0] ## per column: how far it is scrolled up (px); a column taller than the screen scrolls on its own
var _editing: bool = false ## a text field takes the keys
var _field: String = "tp" ## which one: "tp", "pet", or "name"
var _pet_sel: String = "" ## the bird whose page is open in the VÖGEL tab
var _pet_text: String = "" ## the new name being typed
var _name_text: String = "" ## the player display name being typed
var _coop_toast: String = "" ## feedback flash inside KOOP tab
var _coop_toast_t: float = 0.0
var _saving_cloud: bool = false
var _coop_last_fetch_msec: int = 0
var _pending_invites: Dictionary = {} ## match_id -> {match_id, room_code, world_name, notif_id}
var _sidebar: SocialSidebarScript = null
var embedded_in_menu: bool = false
var _embedded_sys_sub_rects: Array[Rect2] = []


func set_embedded_tab(tab_id: String) -> void:
	if tab_id.is_empty():
		_opening = false
		_open_t = 0.0
		_editing = false
		visible = false
		if _sidebar != null:
			_sidebar.on_pause_closing()
			_sidebar.visible = false
		if _dirty:
			GameSettings.save()
			_dirty = false
		_drag = -1
		return
	var target_idx: int = 0
	for i: int in TABS.size():
		if String(TABS[i]["id"]) == tab_id:
			target_idx = i
			break
	_opening = true
	_test_tools = false
	_open_t = 1.0
	_tab = target_idx
	_tab_t = 1.0
	_editing = false
	_scrolls = [0.0, 0.0]
	_armed = ""
	_focus = -1
	_drag = -1
	_bloom_x = float(TABS[_tab]["x"])
	_save_info = _read_save_info() if _can_save() else {}
	_refresh_footer()
	_maybe_refresh_coop_cloud(true)
	_build_items()
	visible = true
	if _sidebar != null:
		_sidebar.top_inset = GameMenu.RAIL_H if embedded_in_menu else 0.0
		_sidebar.bottom_inset = GameMenu.FOOTER_H if embedded_in_menu else 0.0
		if tab_id == "settings" or tab_id == "coop":
			_sidebar.on_pause_opened(true)
		else:
			_sidebar.on_pause_closing()
			_sidebar.visible = false
	queue_redraw()


func _ready() -> void:
	visible = false
	z_index = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	_vignette = VineStyle.make_vignette()
	_name_text = String(GameSettings.get_value("player_name"))
	_sidebar = SocialSidebarScript.new() as SocialSidebarScript
	_sidebar.name = "SocialSidebar"
	_sidebar.visible = false
	_sidebar.request_host_relay.connect(_coop_start_host_relay)
	_sidebar.request_join_match.connect(_on_sidebar_join_match)
	add_child(_sidebar)
	NetworkManager.session_changed.connect(_on_session_changed)
	NetworkManager.peer_joined.connect(func(_id: int) -> void:
		if _paused_here and not multiplayer.get_peers().is_empty():
			_paused_here = false
			get_tree().paused = false
		_on_session_changed()
	)
	CloudSession.friends_changed.connect(_on_session_changed)
	CloudSession.notifications_changed.connect(_on_session_changed)
	CloudSession.profile_loaded.connect(func(_p: Dictionary) -> void: _on_session_changed())
	CloudSession.auto_save_finished.connect(_on_auto_save_finished)


## `player` is untyped on purpose (the player scene preloads the HUD).
func bind(player: Node) -> void:
	_player = player


# ---------- state ----------

func _process(delta: float) -> void:
	_time += delta
	_open_t = move_toward(_open_t, 1.0 if _opening else 0.0, delta / (OPEN_SECONDS if _opening else CLOSE_SECONDS))
	visible = _open_t > 0.0
	if not visible:
		return
	_tab_t = minf(_tab_t + delta / 0.5, 1.0)
	_saved_flash = maxf(_saved_flash - delta, 0.0)
	_failed_flash = maxf(_failed_flash - delta, 0.0)
	_coop_toast_t = maxf(_coop_toast_t - delta, 0.0)
	if _armed != "":
		_armed_left -= delta
		if _armed_left <= 0.0:
			_armed = ""
	var ease_in: float = 1.0 - exp(-14.0 * delta)
	for i: int in TABS.size():
		_tab_lift[i] = lerpf(_tab_lift[i], 3.0 if i == _tab else (2.0 if i == _hover_tab and not bool(TABS[i]["sealed"]) else 0.0), ease_in)
		_tab_deny[i] = maxf(_tab_deny[i] - 3.0 * delta, 0.0)
	for i: int in _footer.size():
		_foot_lift[i] = lerpf(_foot_lift[i], 2.0 if i == _hover_foot else 0.0, ease_in)
	_bloom_x = lerpf(_bloom_x, float(TABS[_tab]["x"]), 1.0 - exp(-12.0 * delta))
	if _opening and not _test_tools:
		_maybe_refresh_coop_cloud()
		if _sidebar != null and _sidebar.is_typing():
			_editing = false
	if _sidebar != null:
		_sidebar.advance(delta, _open_t, _test_tools or _quit_t >= 0.0)
	if _quit_t >= 0.0:
		_quit_t += delta
		if _quit_t >= QUIT_DELAY:
			if _quit_to_menu:
				_quit_to_menu = false
				_quit_t = -1.0
				_set_open(false)
				GameLauncher.launch(get_tree(), {})
				return
			CloudSession.graceful_quit()
	queue_redraw()


func open_test_tools() -> void:
	if not CloudSession.is_admin():
		return
	if not _opening:
		_set_open(true, true)


func _set_open(open: bool, test_tools: bool = false) -> void:
	if open and test_tools and not CloudSession.is_admin():
		return
	if open == _opening:
		return
	_opening = open
	InputManager.ui_blocking = open
	InputManager.menu_open = open
	if open:
		_test_tools = test_tools
		_tab = 0
		_tab_t = 0.0
		_editing = false
		_scrolls = [0.0, 0.0]
		_tp_text = ""
		_bloom_x = float(TABS[0]["x"])
		_armed = ""
		_save_info = _read_save_info() if _can_save() else {}
		if _test_tools:
			_footer.clear()
		else:
			_refresh_footer()
			_maybe_refresh_coop_cloud(true)
		_build_items()
		if _sidebar != null:
			if _test_tools:
				_sidebar.visible = false
			else:
				_sidebar.on_pause_opened(true)
		_paused_here = multiplayer.get_peers().is_empty() ## alone: time stands still
		get_tree().paused = _paused_here
	else:
		if _sidebar != null:
			_sidebar.on_pause_closing()
		if _paused_here:
			get_tree().paused = false
		if _dirty:
			GameSettings.save()
			_dirty = false
		_drag = -1


func _can_save() -> bool:
	return multiplayer.is_server() and get_tree().get_first_node_in_group("world") != null


func _refresh_footer() -> void:
	_footer.clear()
	_footer.append({"id": "menu", "text": "HAUPTMENÜ", "from_right": 156.0, "len": 11.0})
	_footer.append({"id": "quit", "text": "SPIEL BEENDEN", "from_right": 56.0, "len": 15.0})


func _select_tab(index: int) -> void:
	if index == _tab:
		return
	if bool(TABS[index]["sealed"]):
		_tab_deny[index] = 1.0
		return
	Sfx.ui(self, "ui_click", -2.0)
	_tab = index
	_tab_t = 0.0
	_drag = -1
	_scrolls = [0.0, 0.0]
	_build_items()


func _step_tab(direction: int) -> void:
	var index: int = _tab
	for _i: int in TABS.size():
		index = posmod(index + direction, TABS.size())
		if not bool(TABS[index]["sealed"]):
			_select_tab(index)
			return


# ---------- pages ----------

func _add(col: int, kind: String, label: String, key: String = "", extra: Dictionary = {}) -> void:
	var height: float = HEAD_H if kind == "heading" else (INFO_H if kind == "info" else ROW_H)
	var item: Dictionary = {"kind": kind, "label": label, "key": key, "col": col, "y": _cursor[col], "h": height, "idx": _items.size()}
	item.merge(extra)
	_items.append(item)
	_cursor[col] += height


func _build_test_tools() -> void:
	_add(0, "heading", "SPIELER")
	_add(0, "button", "TITELKARTE ZEIGEN", "", {"action": "title_card"})
	_add(0, "button", "AUF 5 HP SETZEN", "", {"action": "hurt5"})
	var disc_dev: MapDiscovery = get_tree().get_first_node_in_group("map_discovery") as MapDiscovery
	if disc_dev != null:
		var cont_open: bool = disc_dev.is_continent_unlocked()
		_add(0, "button", "ATLAS: KONTINENT & WELT VERRIEGELN" if cont_open else "ATLAS: KONTINENT & WELT FREISCHALTEN", "", {"action": "atlas_unlock_continent"})
	var world_node: Node = get_tree().get_first_node_in_group("world")
	if multiplayer.is_server():
		if world_node != null and world_node.get("night") != null:
			_add(0, "button", "VORSTOSS AUSLÖSEN", "", {"action": "raid"})
		_add(0, "button", "STARKES SCHWERT", "", {"action": "strong_sword"})
		_add(0, "button", "HIMMELSRISS BEKOMMEN", "", {"action": "rift_sword"})
		for lvl: int in [0, 5, 10, 15]:
			_add(0, "button", "WAFFE +%d" % lvl, "", {"action": "refine_%d" % lvl}) ## sets the refinement of the weapon in her hand
		_add(0, "button", "TALISMANE ANLEGEN", "", {"action": "talismans_on"})
		_add(0, "button", "TALISMANE ABLEGEN", "", {"action": "talismans_off"})
		_add(0, "button", "ALLE TALISMANE", "", {"action": "talismans_all"})
		_add(0, "button", "ALLE TRÄNKE (ALLE STUFEN)", "", {"action": "potions_all"})
		_add(0, "button", "ZAUBERSTÄBE + ALLE KRISTALLE", "", {"action": "magic_all"}) ## docs/magie_konzept.md: the Hexenulmenstab and every crystal of every tier
		_add(0, "button", "RISSFEDER BEKOMMEN", "", {"action": "rissfeder"})
		_add(0, "button", "OHRRINGE DER KLARHEIT", "", {"action": "clarity"}) ## the witch's earrings against the Hexenwald's mist
		_add(0, "button", "FESSEL DES SCHMELZERS", "", {"action": "aurelith_relic"})
		_add(0, "button", "ZUM AUSSICHTSPUNKT", "", {"action": "vista_next"})
		_add(0, "button", "IN DEN STERNENSAAL", "", {"action": "starhall_go"})
		_add(0, "button", "GÖTTIN: RETTUNG AUSLÖSEN", "", {"action": "starhall_rescue"})
		_add(0, "button", "LICHTSCHRITT EIN/AUS", "", {"action": "starhall_light_step"})
		_add(0, "button", "GÖTTIN ZURÜCKSETZEN", "", {"action": "starhall_reset"})
		_add(0, "button", "KRÄHENFUTTER BEKOMMEN", "", {"action": "food:crow"}) ## 20 of every loved food, 10 of every liked one (host)
		_add(0, "button", "RABENFUTTER BEKOMMEN", "", {"action": "food:raven"})
		_add(0, "button", "MORNATH: ERSTER KILL", "", {"action": "relics_reset"}) ## the next Mornath kill counts as the first again (100 % Rissfeder)
		_add(0, "button", "TRUHE: GEWÖHNLICH", "", {"action": "chest:common"}) ## a test chest in front of her (docs/beutetruhen_konzept.md, not saved)
		_add(0, "button", "TRUHE: SELTEN", "", {"action": "chest:rare"})
		_add(0, "button", "TRUHE: LEGENDÄR", "", {"action": "chest:legendary"})
		_add(0, "button", "TRUHE: BOSS-ANKUNFT", "", {"action": "chest:legendary:arrive"}) ## falls out of a pillar of light like a boss's chest
		_add(0, "button", "IRRLICHT: ZUR SCHALE", "", {"action": "wisp_go"}) ## to the wisp trail's bowl (docs/raetsel_konzept.md 1)
		_add(0, "button", "IRRLICHT ZURÜCKSETZEN", "", {"action": "wisp_reset"}) ## host: the trail open again, its chest gone
		_add(0, "button", "HORTKRÄHE: ZUM BAUM", "", {"action": "crow_go"}) ## to the crow's hoard snag (docs/raetsel_konzept.md 4)
		_add(0, "button", "HORTKRÄHE ZURÜCKSETZEN", "", {"action": "crow_reset"}) ## host: the hoard hidden again, its chest gone
		_add(0, "button", "SONNENKERNE + HACKE", "", {"action": "crow_kit"}) ## host: crow food and a hoe for the hoard
		_add(0, "button", "RABE: ZUM BAUM", "", {"action": "raven_go"}) ## to the raven's snag (docs/raetsel_konzept.md 4, rare)
		_add(0, "button", "RABE ZURÜCKSETZEN", "", {"action": "raven_reset"})
		_add(0, "button", "GLIMMER + STEIN FÜR DEN RABEN", "", {"action": "raven_kit"}) ## host: a pawn it likes and a plain stone it refuses
		_add(0, "button", "WURZELGEFLECHT: ZUM HERZ", "", {"action": "weave_go"}) ## to the first root weave's heart (docs/raetsel_konzept.md 6a)
		_add(0, "button", "WURZELGEFLECHT ZURÜCKSETZEN", "", {"action": "weave_reset"})
		_add(0, "button", "STERNENSPIEGEL: ZUM TEICH", "", {"action": "stars_go"}) ## to the first star mirror's pond (docs/raetsel_konzept.md 6b)
		_add(0, "button", "STERNENSPIEGEL ZURÜCKSETZEN", "", {"action": "stars_reset"})
		_add(0, "button", "MOND: VOLL", "", {"action": "moon:4"}) ## host: tonight's moon (the star mirror reads it)
		_add(0, "button", "MOND: NEU", "", {"action": "moon:0"})
		if get_tree().get_first_node_in_group("sandbox") != null:
			_add(0, "button", "ZURÜCK IN DIE WELT", "", {"action": "trials_leave"}) ## the save is loaded again
		else:
			_add(0, "button", "RÄTSELWELT BETRETEN", "", {"action": "trials_enter"}) ## the flat test world with every trial (unsaved progress here is lost)
	if multiplayer.is_server():
		_add(0, "heading", "ANGELN")
		_add(0, "button", "ANGEL + KÖDER", "", {"action": "fish_kit"})
		if _town() != null and _town().caravan != null: ## the travelling merchant (docs/haendler_konzept.md)
			_add(0, "heading", "KARAWANE")
			_add(0, "button", "KARAWANE: JETZT HOLEN", "", {"action": "caravan_come"})
			_add(0, "button", "KARAWANE: 2 TAGE", "", {"action": "caravan_come2"})
			_add(0, "button", "KARAWANE: ABREISEN", "", {"action": "caravan_leave"})
		if world_node != null and world_node.has_method("water_depth"):
			_add(0, "button", "ZUM NÄCHSTEN UFER", "", {"action": "fish_bank"})
	var west: Hallgrat = get_tree().get_first_node_in_group("hallgrat") as Hallgrat
	if west != null: ## the stone town in the west, stage 1: its ground plan and the Westweg (docs/stadt_westen_konzept.md)
		_add(0, "heading", "HALLGRAT")
		_add(0, "button", "HALLGRAT: PLAN VERBERGEN" if west.plan_shown() else "HALLGRAT: PLAN ZEIGEN", "", {"action": "hallgrat_plan"})
		_add(0, "button", "HALLGRAT: ZUM OSTTOR", "", {"action": "hallgrat_gate"})
		_add(0, "button", "WESTWEG: ZUR GABELUNG", "", {"action": "hallgrat_fork"})
	var story_world: Node = world_node
	if story_world != null and story_world.has_method("debug_can_return_home") and bool(story_world.call("debug_can_return_home")):
		_add(0, "heading", "STORY-SPRUNG")
		_add(0, "button", "ZURÜCK MIT DER AXT", "", {"action": "return_home"})
		_add(0, "button", "FERTIGE STADT", "", {"action": "town_jump"})
		_add(0, "button", "GUSTAV GERETTET", "", {"action": "gustav_jump"})
		_add(0, "button", "ALLES FERTIG + TORBEN", "", {"action": "all_jump"})
	if story_world != null and _player != null and story_world.has_method("has_arena_story") and bool(story_world.call("has_arena_story")):
		_add(0, "heading", "BOSS-QUEST")
		_add(0, "button", "MORNATH-QUEST STARTEN", "", {"action": "mornath_quest"})
		_add(0, "button", "ZUR SÄULENEBENE", "", {"action": "mornath_arena"})
	if story_world != null and _player != null and story_world.get("witch_arena") != null:
		_add(0, "heading", "MORWENNA")
		_add(0, "button", "ZUM RABENBAUM", "", {"action": "morwenna_tree"})
		_add(0, "button", "MORWENNA SOFORT", "", {"action": "morwenna_fight"})
		_add(0, "button", "SPIEGELHEXE-QUEST", "", {"action": "morwenna_quest"})
	if story_world != null and _player != null and story_world.get("aurelith_arena") != null:
		_add(0, "heading", "AURELITH")
		_add(0, "button", "ZUM SINGENDEN BECKEN", "", {"action": "aurelith_basin"})
		_add(0, "button", "AURELITH SOFORT", "", {"action": "aurelith_fight"})
		_add(0, "button", "STAGE 2 (PRISMA)", "", {"action": "aurelith_stage2"})
		_add(0, "button", "STAGE 3 (SCHMELZE)", "", {"action": "aurelith_stage3"})
		if multiplayer.is_server():
			_add(0, "button", "FESSEL DES SCHMELZERS", "", {"action": "aurelith_relic"})
	if get_tree().get_first_node_in_group("dungeons") != null and multiplayer.is_server():
		_add(0, "heading", "GEWÖLBE (DUNGEON)")
		_add(0, "button", "STUFE 5 SETZEN", "", {"action": "dungeon_lv5"})
		_add(0, "button", "RESONANZ +4 · GLUT +4 · ECHO +100", "", {"action": "dungeon_fill"})
		_add(0, "button", "ZUM FLUTTOR (SÜDKAP)", "", {"action": "dungeon_goto_gate"})
		_add(0, "button", "STURMHAFEN-DUNGEON BETRETEN", "", {"action": "dungeon_enter_sturmhafen"})
		_add(0, "button", "DUNGEON VERLASSEN", "", {"action": "dungeon_leave"})
	if get_tree().get_first_node_in_group("mines") != null and multiplayer.is_server() and multiplayer.get_peers().is_empty():
		_add(0, "heading", "MINE")
		for lvl: int in [1, 5, 10, 20]:
			_add(0, "button", "EBENE %d" % lvl, "", {"action": "mine_%d" % lvl})
		_add(0, "button", "ZURÜCK NACH OBEN", "", {"action": "mine_out"})
	if _player != null:
		_add(1, "heading", "TELEPORT")
		if _tp_text == "":
			var feet: Vector2 = (_player as Node2D).global_position
			_tp_text = "%d, %d" % [int(floorf(feet.x / 16.0)), int(floorf(feet.y / 16.0))]
		_add(1, "field", "KOORDINATEN", "tp")
		_add(1, "button", "ZUM ZIEL", "", {"action": "teleport"})
	_add(1, "heading", "SPIELSTAND")
	_add(1, "button", "SPEICHERSTAND LÖSCHEN & START", "", {"action": "reset", "risky": true})


func _build_items() -> void:
	_items.clear()
	_cursor = [TOP_Y, TOP_Y]
	_focus = -1
	if _test_tools:
		_build_test_tools()
	else:
		_build_tab()
	for col: int in 2:
		_scrolls[col] = clampf(_scrolls[col], 0.0, _max_scroll(col))
	for item: Dictionary in _items:
		if _focus < 0 and _interactive(item):
			_focus = int(item["idx"])


func _build_tab() -> void:
	match String(TABS[_tab]["id"]):
		"settings":
			_add(0, "heading", "TON")
			_add(0, "slider", "GESAMT", "master")
			_add(0, "slider", "MUSIK", "music")
			_add(0, "slider", "EFFEKTE", "sfx", {"soon": true})
			_add(0, "heading", "BILD")
			_add(0, "toggle", "VOLLBILD", "fullscreen")
			_add(0, "toggle", "VSYNC", "vsync")
			_add(0, "button", "GRAFIK: %s" % Quality.label("quality"), "", {"action": "cycle:quality"}) ## graphics level (src/autoload/quality.gd)
			_add(0, "toggle", "ADAPTIVE GRAFIK", "adaptive") ## lowers the level for a while when frames run long
			_add(0, "button", "BILDRATE: %s" % Quality.label("fps_cap"), "", {"action": "cycle:fps_cap"})
			_add(0, "toggle", "PIXEL-AUFLÖSUNG", "pixel_res") ## draw at 640x360 and scale up (cheap on weak GPUs)
			_add(0, "slider", "SCHÜTTELN", "shake")
			_add(0, "button", "FÄHIGKEITEN (%s)" % _key_of("skills"), "", {"action": "skills"}) ## the skill graph: the same view as F / Start
			_add(0, "button", "FORTSCHRITT (%s)" % _key_of("progress"), "", {"action": "progress"}) ## the road of levels: the same view as P
			_add(0, "button", "GEWÖLBE (%s)" % _key_of("dungeons"), "", {"action": "dungeons"}) ## Steinsetzer-Prüfungstafel (G)
			_add(0, "button", "ELLIES TAGEBUCH", "", {"action": "journal"})
			_add(1, "heading", "SPIEL")
			_add(1, "toggle", "SCHADENSZAHLEN", "numbers")
			_add(1, "toggle", "POSITION (ENTWICKLER)", "position") ## continent and zone tile under the clock (docs/hud_v2_konzept.md 3.A)
			_add(1, "toggle", "HUD-KONTRAST", "hud_contrast") ## a full ink rim round every HUD word (HudText)
			_add(1, "toggle", "GROSSE SCHRIFT", "hud_big_text") ## the 5x7 face for HUD words (HudText)
			_add(1, "toggle", "ZONEN-TÖNUNG", "hud_tint") ## the zone's mood tints the HUD's bark a little
			_add(1, "slider", "CHAT-SICHTBARKEIT", "chat_opacity", {"min": GameSettings.CHAT_OPACITY_MIN, "max": GameSettings.CHAT_OPACITY_MAX})
			_add(1, "toggle", "EIGENER CURSOR", "cursor") ## the pixel cursor (GameCursor); off = the system pointer
			_add(1, "button", "WETTER-EFFEKTE: %s" % ["AUS", "REDUZIERT", "VOLL"][clampi(int(GameSettings.get_value("weather_fx")), 0, 2)], "", {"action": "weather_fx"})
			_add(1, "toggle", "BLITZE SANFT", "flash_soft") ## accessibility: weaker flashes, no bolt drawing
			_add(1, "toggle", "WASSERSPIEGELUNG", "reflections") ## mirror images in water and puddles (WaterReflections)
			_add(1, "toggle", "SCHATTEN", "sun_shadows") ## cast shadows from sun and moon (SunShadows)
			_add(1, "toggle", "TAGEBUCH OHNE BEWEGUNG", "journal_still")
			if _player is Player and (_player as Player).appearance != null:
				_add(1, "choice", "TITEL", "player_title", {"text": (_player as Player).appearance.title_label()})
			_add(1, "choice", "SPRACHE", "language", {"soon": true, "text": "DEUTSCH"})
			_add(1, "heading", "STEUERUNG")
			for row: Array in CONTROLS:
				_add(1, "info", String(row[0]), "", {"text": String(row[2]) if String(row[2]) != "" else _key_of(String(row[1]))})
		"town":
			_build_town_page()
		"pets":
			_build_pets_page()
		"coop":
			_build_coop_page()


func _on_session_changed() -> void:
	if _sidebar != null:
		_sidebar.mark_dirty()
	if _opening and String(TABS[_tab]["id"]) == "coop" and not _editing:
		_build_items()


static func _join_mode_label(mode: String) -> String:
	match mode:
		"private":
			return "PRIVAT"
		"open":
			return "OFFEN"
		_:
			return "AUF ANFRAGE"


static func _next_join_mode(mode: String) -> String:
	match mode:
		"private":
			return "ask"
		"ask":
			return "open"
		_:
			return "private"


func _maybe_refresh_coop_cloud(force: bool = false) -> void:
	if not CloudSession.is_logged_in():
		return
	var now: int = Time.get_ticks_msec()
	var cooldown: int = 1800 if force else 5000
	if _coop_last_fetch_msec > 0 and now - _coop_last_fetch_msec < cooldown:
		return
	_coop_last_fetch_msec = now
	if CloudSession.uid.is_empty():
		CloudSession.fetch_my_profile()
	CloudSession.refresh_friends()
	CloudSession.fetch_notifications()


func _build_coop_notifications(col: int) -> void:
	_pending_invites.clear()
	var added_hdr: bool = false
	for notif: Dictionary in CloudSession.notifications:
		var code: int = int(notif.get("code", 0))
		var content: Dictionary = notif.get("content", {}) as Dictionary
		if (code == 101 or code == 103) and not String(content.get("match_id", "")).is_empty():
			if not added_hdr:
				_add(col, "heading", "EINLADUNGEN")
				added_hdr = true
			var mid: String = String(content.get("match_id", ""))
			var hname: String = String(content.get("host_name", "FREUND")).to_upper()
			var wname: String = String(content.get("world_name", "KOOP-WELT")).to_upper()
			_pending_invites[mid] = {
				"match_id": mid,
				"room_code": String(content.get("room_code", "")),
				"world_name": wname,
				"notif_id": String(notif.get("id", "")),
			}
			var prefix: String = "EINLADUNG" if code == 101 else "FREIGABE"
			_add(col, "info", "%s: %s" % [prefix, hname], "", {"text": wname})
			_add(col, "button", "WELT BETRETEN", "", {"action": "coop_accept_invite:%s" % mid})
		elif code == 102 and multiplayer.is_server():
			if not added_hdr:
				_add(col, "heading", "BEITRITTSANFRAGEN")
				added_hdr = true
			var req_uid: String = String(content.get("requester_user_id", ""))
			var req_name: String = String(content.get("requester_name", "SPIELER")).to_upper()
			_add(col, "info", "ANFRAGE", "", {"text": req_name})
			_add(col, "button", "%s ANNEHMEN" % req_name, "", {"action": "coop_req_accept:%s" % req_uid})
			_add(col, "button", "%s ABLEHNEN" % req_name, "", {"action": "coop_req_decline:%s" % req_uid, "risky": true})


func _build_coop_page() -> void:
	_maybe_refresh_coop_cloud()
	var jmode: String = NetworkManager.active_join_mode if NetworkManager.is_multiplayer_session() else CloudSession.world_join_mode
	if not NetworkManager.is_multiplayer_session():
		if CloudSession.is_logged_in():
			_add(0, "heading", "ONLINE-KOOP (NAKAMA)")
			_add(0, "info", "DEINE UID", "", {"text": CloudSession.uid if not CloudSession.uid.is_empty() else "---"})
			_add(0, "button", "BEITRITT: %s" % _join_mode_label(jmode), "", {"action": "coop_cycle_join_mode"})
			if get_tree().get_first_node_in_group("world") != null:
				_add(0, "button", "WELT FÜR KOOP ÖFFNEN", "", {"action": "coop_host_relay"})
			_build_coop_notifications(0)
			if _coop_toast_t > 0.0 and not _coop_toast.is_empty():
				_add(0, "info", _coop_toast, "", {"text": ""})
			_add(0, "button", "AKTUALISIEREN", "", {"action": "coop_refresh_cloud"})
			_add(0, "button", "ZUM HAUPTMENÜ", "", {"action": "coop_to_menu"})
			_add(1, "heading", "FREUNDE")
			var any_friend: bool = false
			for fr: Dictionary in CloudSession.friends_cache:
				if int(fr.get("state", 0)) != 0:
					continue
				any_friend = true
				var dname: String = String(fr.get("display_name", fr.get("username", "FREUND"))).to_upper()
				var is_online: bool = bool(fr.get("online", false))
				var is_hosting: bool = bool(fr.get("coop_active", false))
				if is_hosting:
					var count_txt: String = "%d/%d · %s" % [int(fr.get("coop_players", 1)), int(fr.get("coop_max_players", 4)), _join_mode_label(String(fr.get("coop_join_mode", "ask")))]
					_add(1, "info", dname, "", {"text": count_txt})
					var f_mode: String = String(fr.get("coop_join_mode", "ask"))
					var btn_txt: String = "BEITRETEN" if f_mode == "open" else ("ANFRAGEN" if f_mode == "ask" else "PRIVAT")
					_add(1, "button", "%s · %s" % [dname, btn_txt], "", {"action": "coop_join_friend:%s" % String(fr.get("user_id", ""))})
				else:
					_add(1, "info", dname, "", {"text": "ONLINE" if is_online else "OFFLINE"})
			if not any_friend:
				_add(1, "info", "KEINE FREUNDE GELISTET", "", {"text": ""})
		else:
			_add(0, "heading", "EINZELSPIELER")
			_add(0, "info", "KEINE KOOP-SITZUNG AKTIV", "", {"text": ""})
			_add(0, "info", "FREUNDE & KOOP WERDEN", "", {"text": ""})
			_add(0, "info", "ÜBER DEN LAUNCHER VERWALTET", "", {"text": ""})
			_add(0, "button", "ZUM HAUPTMENÜ", "", {"action": "coop_to_menu"})
		_add(1, "heading", "SPIELERNAME")
		_add(1, "field", "NAME", "player_name", {"hint": "ELLIE"})
		_add(1, "button", "NAME ÜBERNEHMEN", "", {"action": "coop_apply_name"})
		if _player is Player and (_player as Player).appearance != null:
			_add(1, "choice", "TITEL", "player_title", {"text": (_player as Player).appearance.title_label()})
		return
	var code: String = NetworkManager.active_room_code if not NetworkManager.active_room_code.is_empty() else "OFFEN"
	_add(0, "heading", NetworkManager.active_world_name)
	_add(0, "info", "TRANSPORT", "", {"text": "NAKAMA-RELAY" if NetworkManager.transport_mode == "relay" else "LAN / ENET"})
	_add(0, "info", "JOIN-CODE", "", {"text": code})
	_add(0, "button", "CODE KOPIEREN", "", {"action": "coop_copy_code"})
	if NetworkManager.transport_mode != "relay":
		_add(0, "button", "EINLADUNG KOPIEREN", "", {"action": "coop_copy_invite"})
	if multiplayer.is_server():
		if NetworkManager.transport_mode == "enet":
			_add(0, "button", "NEUEN CODE ERZEUGEN", "", {"action": "coop_new_code"})
		if CloudSession.is_logged_in():
			_add(0, "button", "BEITRITT: %s" % _join_mode_label(jmode), "", {"action": "coop_cycle_join_mode"})
			_build_coop_notifications(0)
			_add(0, "heading", "FREUNDE EINLADEN")
			var inv_count: int = 0
			for fr: Dictionary in CloudSession.friends_cache:
				if int(fr.get("state", 0)) != 0 or not bool(fr.get("online", false)):
					continue
				inv_count += 1
				var fname: String = String(fr.get("display_name", fr.get("username", "FREUND"))).to_upper()
				_add(0, "button", "EINLADEN: %s" % fname, "", {"action": "coop_invite:%s" % String(fr.get("user_id", ""))})
			if inv_count == 0:
				_add(0, "info", "KEINE FREUNDE ONLINE", "", {"text": ""})
	if NetworkManager.transport_mode != "relay":
		_add(0, "heading", "HOST-ADRESSE")
		var ips: PackedStringArray = NetworkManager.local_ips()
		for i: int in mini(ips.size(), 2):
			var label_str: String = "LAN-IP" if i == 0 else "WEITERE IP"
			var addr_str: String = "%s:%d" % [ips[i], NetworkManager.active_port]
			_add(0, "info", label_str, "", {"text": addr_str})
		_add(0, "button", "IP KOPIEREN", "", {"action": "coop_copy_ip"})
	if _coop_toast_t > 0.0 and not _coop_toast.is_empty():
		_add(0, "info", _coop_toast, "", {"text": ""})
	var crew: Array[Dictionary] = NetworkManager.roster()
	_add(1, "heading", "SPIELER %d/%d" % [maxi(crew.size(), 1), NetworkManager.active_max_players])
	for entry: Dictionary in crew:
		var pid: int = int(entry.get("id", 0))
		var is_host: bool = bool(entry.get("is_host", false))
		var pname: String = String(entry.get("name", "SPIELER"))
		for p_node: Player in Player.all:
			if is_instance_valid(p_node) and p_node.name.to_int() == pid and p_node.appearance != null:
				pname = p_node.appearance.display_name_with_title(pname)
				break
		var role_txt: String = "HOST" if is_host else ("%d MS" % NetworkManager.last_ping_ms if pid == multiplayer.get_unique_id() and NetworkManager.last_ping_ms > 0 else "ONLINE")
		_add(1, "info", pname, "", {"text": role_txt})
		if multiplayer.is_server() and not is_host:
			_add(1, "button", "%s ENTFERNEN" % String(entry.get("name", "SPIELER")), "", {"action": "coop_kick:%d" % pid, "risky": true})
	_add(1, "button", "WELT VERLASSEN" if multiplayer.get_peers().is_empty() else "KOOP VERLASSEN", "", {"action": "coop_to_menu", "risky": true})
	_add(1, "heading", "DEIN NAME")
	_add(1, "field", "NAME", "player_name", {"hint": "ELLIE"})
	_add(1, "button", "NAME ÜBERNEHMEN", "", {"action": "coop_apply_name"})
	if _player is Player and (_player as Player).appearance != null:
		_add(1, "choice", "TITEL", "player_title", {"text": (_player as Player).appearance.title_label()})


func _on_pets_changed(_key: String = "") -> void:
	if _opening and String(TABS[_tab]["id"]) == "pets" and not _editing:
		var keep: int = _focus
		_build_items()
		if keep >= 0 and keep < _items.size() and _interactive(_items[keep]):
			_focus = keep


## The VÖGEL tab: the book of the named crows and ravens (docs/pet_konzept.md 9.4). Left the birds, right the page of the chosen one: kind, bond, where it
## was last seen and the name, which can be changed here.
func _build_pets_page() -> void:
	var registry: PetRegistry = PetRegistry.of(get_tree())
	_add(0, "heading", "GEFIEDERTE")
	if registry == null or registry.records().is_empty():
		_add(0, "info", "NOCH KEINER BEKANNT", "", {"text": ""})
		_add(0, "info", "SCHLEICH DICH MIT FUTTER", "", {"text": ""})
		_add(0, "info", "AN KRÄHEN UND RABEN", "", {"text": ""})
		_add(0, "info", "UND FÜTTERE SIE", "", {"text": ""})
		return
	if not registry.pet_changed.is_connected(_on_pets_changed):
		registry.pet_changed.connect(_on_pets_changed)
	if not registry.companion_changed.is_connected(_on_pets_changed):
		registry.companion_changed.connect(_on_pets_changed)
	var me: int = multiplayer.get_unique_id()
	var list: Array[Dictionary] = registry.records()
	var found: bool = false
	for entry: Dictionary in list:
		found = found or String(entry["key"]) == _pet_sel
	if not found:
		_pet_sel = String(list[0]["key"])
	for entry: Dictionary in list:
		var mark: String = "> " if String(entry["key"]) == _pet_sel else ""
		_add(0, "button", mark + String(entry["n"]), "", {"action": "pet_sel:" + String(entry["key"])})
	var rec: Dictionary = registry.record(_pet_sel)
	var bp: float = registry.bp_of(_pet_sel, me)
	var stage: int = PetRules.stage_of(bp)
	var seen: Vector3 = registry.seen_of(_pet_sel)
	var ago: int = maxi(0, TimeManager.day - int(seen.z))
	var next_line: String = "%d" % int(bp) if stage >= 5 else "%d / %d" % [int(bp), int(PetRules.stage_start(stage + 1))]
	var rings: Array = (PetRules.table()["register"] as Dictionary)["ring_names"] as Array
	_add(1, "heading", String(rec["n"]))
	_add(1, "info", "ART", "", {"text": "KRÄHE" if String(rec["sp"]) == "crow" else "RABE"})
	_add(1, "info", "STUFE", "", {"text": PetRules.stage_name(stage)})
	_add(1, "info", "BINDUNG", "", {"text": next_line})
	_add(1, "info", "RING", "", {"text": String(rings[int(rec["ring"]) % rings.size()])})
	_add(1, "info", "BEKANNT SEIT", "", {"text": "TAG %d" % (int(rec["rd"]) + 1)})
	_add(1, "info", "GESEHEN", "", {"text": "HEUTE" if ago == 0 else "VOR %d TAGEN" % ago})
	_add(1, "info", "ORT", "", {"text": "%d, %d" % [int(seen.x / 16.0), int(seen.y / 16.0)]})
	var companion_cfg: Dictionary = PetRules.table()["companion"] as Dictionary
	if stage >= int(companion_cfg["stage"]):
		_add(1, "heading", "GEFÄHRTE")
		if registry.companion_of(me) == _pet_sel:
			_add(1, "info", "MODUS", "", {"text": registry.mode_name(me)})
			_add(1, "button", "MODUS WECHSELN", "", {"action": "pet_mode"})
			_add(1, "button", "ENTLASSEN", "", {"action": "pet_release"})
			_add(1, "info", "PFIFF", "", {"text": "V RUFT, V HALTEN WECHSELT"})
		elif registry.peer_of_companion(_pet_sel) == 0:
			_add(1, "button", "MITNEHMEN", "", {"action": "pet_take"})
	_add(1, "heading", "UMBENENNEN")
	_add(1, "field", "NAME", "pet")
	_add(1, "button", "NAMEN ÜBERNEHMEN", "", {"action": "pet_rename"})


func _town() -> TownManager:
	return get_tree().get_first_node_in_group("town") as TownManager


## The STADT tab's line about the travelling merchant: here and for how long, or roughly when (never the exact day: docs/haendler_konzept.md 3.5).
func _caravan_text(caravan: CaravanManager) -> String:
	if CaravanRules.present(caravan.state()) and not caravan.visit.is_empty():
		var days_left: int = int(floorf(float(caravan.visit.l))) - TimeManager.day
		return "IN DER STADT · " + ("REIST HEUTE AB" if days_left <= 0 else "NOCH %d TAG%s" % [days_left, "" if days_left == 1 else "E"])
	if caravan.first_day < 0:
		return "NOCH NIE GESEHEN"
	var next: Vector2i = caravan.next_arrival_days()
	if next.x < 0:
		return "UNTERWEGS"
	var low: int = maxi(next.x - 1, 0)
	var high: int = next.x + 2
	return "MORGEN ODER BALD" if high <= 1 else "ERWARTET IN %d BIS %d TAGEN" % [maxi(low, 1), high]


## The STADT tab: what the town is (name, level, people, buildings, light, stock, residents, pieces) and what the group can do (build, demolish, name).
func _build_town_page() -> void:
	var town: TownManager = _town()
	if town != null and not town.changed.is_connected(_on_town_changed):
		town.changed.connect(_on_town_changed)
	if town == null or not town.founded:
		_add(0, "heading", "STADT")
		_add(0, "info", "NOCH KEINE STADT", "", {"text": ""})
		_add(0, "info", "ERNEUERE DIE HÜTTE,", "", {"text": ""})
		_add(0, "info", "DANN BEGINNT SIE", "", {"text": ""})
		return
	var finished: int = 0
	var sites: int = 0
	var counts: Dictionary = {}
	for id: int in town.structures:
		var data: Dictionary = town.structures[id] as Dictionary
		if bool(TownRules.piece(String(data.p)).get("builtin", false)):
			continue
		if int(data.g) >= TownManager.PROGRESS_FULL:
			finished += 1
			counts[String(data.p)] = int(counts.get(String(data.p), 0)) + 1
		else:
			sites += 1
	var level: int = town.level()
	var next_worth: float = TownRules.next_worth(level)
	_add(0, "heading", town.town_name())
	if not town.has_heart():
		_add(0, "info", "NOCH NICHT GEGRÜNDET", "", {"text": "BAUE DEN BRUNNENPLATZ"})
	_add(0, "info", "STUFE", "", {"text": town.level_label()})
	_add(0, "info", "WERT", "", {"text": "%d / %d" % [int(town.worth()), int(next_worth)] if next_worth >= 0.0 else "%d" % int(town.worth())})
	_add(0, "info", "EINWOHNER", "", {"text": str(town.population())})
	_add(0, "info", "BAUTEN", "", {"text": "%d" % finished + (" + %d IM BAU" % sites if sites > 0 else "")})
	var reach: float = 0.0
	for c: Vector3 in town.circles():
		reach = maxf(reach, Vector2(c.x, c.y).distance_to(town.center) + c.z)
	_add(0, "info", "LICHT REICHT", "", {"text": "%d KACHELN" % int(reach / 16.0)})
	_add(0, "info", "GEGRÜNDET", "", {"text": "TAG %d" % (town.founded_day + 1)})
	if town.caravan != null and town.has_heart():
		_add(0, "info", "KARAWANE", "", {"text": _caravan_text(town.caravan)})
	if town.board != null: ## what the quest board remembers (docs/questtafel_ausbau_konzept.md 2.8)
		var me: int = multiplayer.get_unique_id()
		_add(0, "info", "ERLEDIGTE ZETTEL", "", {"text": str(town.board.honor_done())})
		var title: String = town.board.title_name(me)
		if title != "":
			_add(0, "info", "TITEL", "", {"text": title})
	_add(0, "heading", "VERWALTUNG")
	_add(0, "button", "BAUEN", "", {"action": "town_build"})
	_add(0, "button", "ABREISSEN", "", {"action": "town_demolish"})
	_add(0, "button", "VERSETZEN", "", {"action": "town_move"})
	_add(0, "choice", "NAME", "town_name", {"text": town.town_name()})
	_add(0, "choice", "FARBE", "town_color", {"text": TownEmblems.COLOR_NAMES[town.look_color]})
	_add(0, "choice", "WAPPEN", "town_emblem", {"text": TownEmblems.NAMES[town.look_emblem]})
	_add(1, "heading", "LAGER")
	var shown: int = 0
	for item: String in town.stock:
		if shown >= 4:
			_add(1, "info", "…", "", {"text": ""})
			break
		_add(1, "info", String(DataRegistry.get_entry("items", item).get("name", item)).to_upper(), "", {"text": str(int(town.stock[item]))})
		shown += 1
	if town.stock.is_empty():
		_add(1, "info", "LEER", "", {"text": ""})
	_add(1, "heading", "BEWOHNER")
	if town.residents.is_empty():
		_add(1, "info", "NOCH NIEMAND", "", {"text": ""})
	for sid: String in town.residents:
		var spec: Dictionary = town.settler_spec(sid)
		if bool(spec.get("away", false)): ## lives elsewhere (the witch)
			continue
		_add(1, "info", "%s  %s" % [String(spec.name), String(spec.title)], "", {"text": "VERTRAUEN %d" % town.trust_of(sid)})
	_add(1, "heading", "BAUTEN")
	shown = 0
	for piece: String in counts:
		if shown >= 4:
			_add(1, "info", "…", "", {"text": ""})
			break
		_add(1, "info", String(TownRules.piece(piece).get("name", piece)), "", {"text": "%d" % int(counts[piece])})
		shown += 1
	if counts.is_empty():
		_add(1, "info", "NOCH KEINE", "", {"text": ""})


func _on_town_changed() -> void:
	if _opening and String(TABS[_tab]["id"]) == "town":
		var keep: int = _focus
		_build_items()
		if keep >= 0 and keep < _items.size() and _interactive(_items[keep]):
			_focus = keep


func _interactive(item: Dictionary) -> bool:
	return String(item["kind"]) in ["slider", "toggle", "choice", "button", "field"]


func _key_of(action: String) -> String:
	for event: InputEvent in InputMap.action_get_events(action):
		var key: InputEventKey = event as InputEventKey
		if key != null:
			var code: Key = key.keycode if key.keycode != KEY_NONE else DisplayServer.keyboard_get_keycode_from_physical(key.physical_keycode)
			return OS.get_keycode_string(code).to_upper()
	return "?"


func _origin_x() -> float:
	return (size.x - 640.0) / 2.0


func _column_w() -> float:
	if _sidebar != null and _sidebar.occupied_width() > 60.0 and not _test_tools:
		return 204.0
	return COLUMN_W


func _column_x(col: int) -> float:
	if _sidebar != null and _sidebar.occupied_width() > 60.0 and not _test_tools:
		var t: float = clampf((_sidebar.occupied_width() - 28.0) / (PauseSocialSidebar.EXPANDED_W - 28.0), 0.0, 1.0)
		var base_x: float = _origin_x() + COLUMN_X[col]
		var compact_x: float = 16.0 if col == 0 else 236.0
		return roundf(lerpf(base_x, compact_x, t))
	return _origin_x() + COLUMN_X[col]


func _item_rect(item: Dictionary) -> Rect2:
	return Rect2(_column_x(int(item["col"])), float(item["y"]) - _scrolls[int(item["col"])], _column_w(), float(item["h"]))


func _view_bottom() -> float:
	return minf(size.y - 14.0, FOOT_Y - 6.0) ## the footer (save text, save buttons) lives below the page area


## A row is shown and can be hit only while it lies wholly inside the page area.
func _row_visible(item: Dictionary) -> bool:
	var rect: Rect2 = _item_rect(item)
	return rect.position.y >= TOP_Y - 4.0 and rect.end.y <= _view_bottom()


func _max_scroll(col: int) -> float:
	return maxf(_cursor[col] + 6.0 - _view_bottom(), 0.0)


func _scroll_by(amount: float, col: int) -> void:
	_scrolls[col] = clampf(_scrolls[col] + amount, 0.0, _max_scroll(col))


## The column the mouse is over (the one the wheel scrolls): the right one from a little left of its vine on.
func _column_at(x: float) -> int:
	return 1 if x >= _column_x(1) - 24.0 else 0


## Scrolls so that the focused row is inside the page area.
func _reveal(item: Dictionary) -> void:
	var rect: Rect2 = _item_rect(item)
	var col: int = int(item["col"])
	if rect.position.y < TOP_Y - 4.0:
		_scroll_by(rect.position.y - (TOP_Y - 4.0), col)
	elif rect.end.y > _view_bottom():
		_scroll_by(rect.end.y - _view_bottom(), col)


func _slider_rect(item: Dictionary) -> Rect2:
	var rect: Rect2 = _item_rect(item)
	return Rect2(rect.position.x + VALUE_X - 3.0, rect.position.y, SLIDER_W + 6.0, rect.size.y)


# ---------- actions ----------

func _change(item: Dictionary, direction: int) -> void:
	var key: String = String(item["key"])
	match String(item["kind"]):
		"slider":
			var lo: int = int(item.get("min", 0))
			var hi: int = int(item.get("max", 100))
			GameSettings.set_value(key, clampi(int(GameSettings.get_value(key)) + direction * 5, lo, hi))
			_dirty = true
		"toggle":
			if direction != 0:
				_toggle(item)
		"choice":
			var town: TownManager = _town()
			if key == "town_name" and town != null and direction != 0:
				town.request_name(posmod(town.name_index + direction, TownRules.town_names().size()))
			elif key == "town_color" and town != null and direction != 0:
				town.request_look(town.look_color + direction, town.look_emblem)
			elif key == "town_emblem" and town != null and direction != 0:
				town.request_look(town.look_color, town.look_emblem + direction)
			elif key == "player_title" and _player is Player and (_player as Player).appearance != null and direction != 0:
				var app: AppearanceComponent = (_player as Player).appearance
				if app.unlocked_title_ids().size() > 1:
					var keep_idx: int = _focus
					app.cycle_title(direction)
					_build_items()
					if keep_idx >= 0 and keep_idx < _items.size() and _interactive(_items[keep_idx]):
						_focus = keep_idx


func _toggle(item: Dictionary) -> void:
	GameSettings.set_value(String(item["key"]), not bool(GameSettings.get_value(String(item["key"]))))
	_dirty = true


func _activate(item: Dictionary) -> void:
	Sfx.ui(self, "ui_confirm", -3.0)
	match String(item["kind"]):
		"toggle":
			_toggle(item)
		"choice":
			_change(item, 1)
		"field":
			_editing = true
			_field = String(item["key"])
		"button":
			_run_action(String(item["action"]))


func _run_action(action: String) -> void:
	if action.begins_with("food:"):
		var feeder: Player = _player as Player
		if feeder == null or not multiplayer.is_server():
			_failed_flash = 2.5
			return
		var species: String = action.trim_prefix("food:")
		var foods: Dictionary = PetRules.table()["foods"] as Dictionary
		for item: String in foods:
			var kind: String = String((foods[item] as Dictionary).get(species, ""))
			if kind == "loves" or kind == "likes":
				feeder.inventory.give(item, 20 if kind == "loves" else 10)
		return
	if action.begins_with("chest:"): ## dev: a loot chest a little in front of her (host decides)
		var chests: LootChests = LootChests.of(get_tree())
		if chests == null or not (_player is Player):
			_failed_flash = 2.5
			return
		var hero: Player = _player as Player
		var parts: PackedStringArray = action.split(":")
		var ahead: Vector2 = Vector2.from_angle(hero.facing.angle()) if hero.facing.length() > 0.1 else Vector2.DOWN
		chests.request_dev(parts[1], hero.global_position + ahead * 40.0, parts.size() > 2)
		_set_open(false)
		return
	if action.begins_with("cycle:"): ## choices shared with the main menu (graphics level, frame cap)
		Quality.cycle(action.trim_prefix("cycle:"), 1)
		_dirty = true
		_build_items()
		return
	if action == "weather_fx":
		GameSettings.set_value("weather_fx", (int(GameSettings.get_value("weather_fx")) + 2) % 3) ## 2 full -> 1 reduced -> 0 off -> 2
		_dirty = true
		_build_items()
		return
	if action.begins_with("pet_sel:"):
		_pet_sel = action.trim_prefix("pet_sel:")
		_pet_text = ""
		_build_items()
		return
	if action in ["pet_take", "pet_release", "pet_mode"]:
		var comp_registry: PetRegistry = PetRegistry.of(get_tree())
		if comp_registry != null:
			comp_registry.ask({"pet_take": "take", "pet_release": "release", "pet_mode": "mode"}[action], _pet_sel)
		return
	if action == "pet_rename":
		var registry: PetRegistry = PetRegistry.of(get_tree())
		if registry != null and _pet_sel != "" and PetRegistry.clean_name(_pet_text) != "":
			registry.request_rename(_pet_sel, _pet_text)
			_pet_text = ""
			_editing = false
		else:
			_failed_flash = 2.5
		return
	if action == "coop_copy_code":
		var code_txt: String = NetworkManager.active_room_code if not NetworkManager.active_room_code.is_empty() else ("%s:%d" % [NetworkManager.primary_ip(), NetworkManager.active_port])
		DisplayServer.clipboard_set(code_txt)
		_coop_toast = "CODE KOPIERT"
		_coop_toast_t = 2.4
		_build_items()
		return
	if action == "coop_copy_ip":
		DisplayServer.clipboard_set("%s:%d" % [NetworkManager.primary_ip(), NetworkManager.active_port])
		_coop_toast = "IP KOPIERT"
		_coop_toast_t = 2.4
		_build_items()
		return
	if action == "coop_copy_invite":
		var ip_txt: String = "%s:%d" % [NetworkManager.primary_ip(), NetworkManager.active_port]
		var inv: String = ip_txt if NetworkManager.active_room_code.is_empty() else ("%s %s" % [ip_txt, NetworkManager.active_room_code])
		DisplayServer.clipboard_set(inv)
		_coop_toast = "EINLADUNG KOPIERT"
		_coop_toast_t = 2.4
		_build_items()
		return
	if action == "coop_new_code":
		NetworkManager.set_room_code("")
		_coop_toast = "NEUER CODE: %s" % NetworkManager.active_room_code
		_coop_toast_t = 2.6
		_build_items()
		return
	if action == "coop_apply_name":
		var clean_name: String = MultiplayerWorlds.sanitize_name(_name_text, "ELLIE")
		_name_text = clean_name
		GameSettings.set_value("player_name", clean_name)
		GameSettings.save()
		NetworkManager.refresh_local_name()
		_coop_toast = "NAME GESPEICHERT"
		_coop_toast_t = 2.2
		_editing = false
		_build_items()
		return
	if action == "coop_to_menu":
		_do_flush_and_quit(true)
		return
	if action == "coop_cycle_join_mode":
		var curr_mode: String = NetworkManager.active_join_mode if NetworkManager.is_multiplayer_session() else CloudSession.world_join_mode
		var next_mode: String = _next_join_mode(curr_mode)
		_coop_set_join_mode(next_mode)
		return
	if action == "coop_refresh_cloud":
		_coop_last_fetch_msec = 0
		_coop_toast = "AKTUALISIERT"
		_coop_toast_t = 1.6
		_build_items()
		return
	if action == "coop_host_relay":
		_coop_start_host_relay()
		return
	if action.begins_with("coop_invite:"):
		_coop_send_invite(action.trim_prefix("coop_invite:"))
		return
	if action.begins_with("coop_join_friend:"):
		_coop_request_friend_join(action.trim_prefix("coop_join_friend:"))
		return
	if action.begins_with("coop_accept_invite:"):
		var mid: String = action.trim_prefix("coop_accept_invite:")
		_coop_join_invite(mid)
		return
	if action.begins_with("coop_req_accept:"):
		_coop_respond_join_req(action.trim_prefix("coop_req_accept:"), true)
		return
	if action.begins_with("coop_req_decline:"):
		_coop_respond_join_req(action.trim_prefix("coop_req_decline:"), false)
		return
	if action.begins_with("coop_kick:"):
		var target_id: int = action.trim_prefix("coop_kick:").to_int()
		if _armed != action:
			_arm(action)
		else:
			_armed = ""
			NetworkManager.kick_peer(target_id)
			_build_items()
		return
	match action:
		"skills":
			var skills: SkillTreeWindow = get_parent().get_node("SkillTreeWindow") as SkillTreeWindow
			_set_open(false)
			skills._set_open(true)
			if not skills._opening:
				_set_open(true)
				_failed_flash = 2.5
		"progress":
			var road: ProgressWindow = get_parent().get_node("ProgressWindow") as ProgressWindow
			_set_open(false)
			road._set_open(true)
			if not road._opening:
				_set_open(true)
				_failed_flash = 2.5
		"dungeons":
			var dw: DungeonWindow = get_parent().get_node_or_null("DungeonWindow") as DungeonWindow
			if dw == null:
				_failed_flash = 2.5
				return
			_set_open(false)
			dw.open_remote()
		"dungeon_lv5":
			var dp: Player = _player as Player
			if dp == null or not multiplayer.is_server() or dp.progress == null:
				_failed_flash = 2.5
				return
			var need_xp: int = maxi(0, Levels.xp_at(5) - dp.progress.xp)
			if need_xp > 0:
				dp.progress.award(0, need_xp)
			dp.progress.request_claim(5)
		"dungeon_fill":
			var dp2: Player = _player as Player
			if dp2 == null or not multiplayer.is_server() or dp2.dungeons == null:
				_failed_flash = 2.5
				return
			dp2.dungeons.debug_refill(4, 4, 100)
			dp2.dungeons.mark_discovered("suedkap_gezeitenkammern")
		"dungeon_goto_gate":
			var dp3: Player = _player as Player
			if dp3 == null:
				_failed_flash = 2.5
				return
			var def_g: Dictionary = DungeonRules.by_id("suedkap_gezeitenkammern")
			var z_g: Atlas.Zone = Atlas.shared().zone(&"suedkap")
			var et_g: Array = def_g.get("entrance_tile", [358.0, 266.0]) as Array
			if z_g != null and et_g.size() >= 2:
				var gate_px: Vector2 = Atlas.px_of(Vector2(z_g.origin) + Vector2(float(et_g[0]), float(et_g[1]))) + Vector2(0.0, 32.0)
				dp3.request_teleport(gate_px)
				_set_open(false)
			else:
				_failed_flash = 2.5
		"dungeon_enter_sturmhafen":
			var dm_dev: DungeonManager = DungeonManager.of(get_tree())
			var dp4: Player = _player as Player
			if dm_dev == null or dp4 == null or not multiplayer.is_server():
				_failed_flash = 2.5
				return
			if dp4.progress != null and dp4.progress.level < 5:
				dp4.progress.award(0, maxi(0, Levels.xp_at(5) - dp4.progress.xp))
				dp4.progress.request_claim(5)
			if dp4.dungeons != null:
				dp4.dungeons.mark_discovered("suedkap_gezeitenkammern")
			_set_open(false)
			_open_t = 0.0
			visible = false
			dm_dev.request_enter_solo("suedkap_gezeitenkammern", true)
		"dungeon_leave":
			var dm_l: DungeonManager = DungeonManager.of(get_tree())
			if dm_l == null:
				_failed_flash = 2.5
				return
			_set_open(false)
			dm_l.request_leave_dungeon()
		"journal":
			var journal: QuestJournal = get_parent().get_node("QuestJournal") as QuestJournal
			_set_open(false)
			journal.open()
			if not InputManager.journal_open:
				_set_open(true)
				_failed_flash = 2.5
		"town_build", "town_demolish", "town_move":
			var town: TownManager = _town()
			var builder: BuildMode = town.build_mode() if town != null else null
			if builder == null or _player == null or not town.founded:
				_failed_flash = 2.5
				return
			_set_open(false)
			_open_t = 0.0
			visible = false
			builder.set_active(true)
			if builder.active and action == "town_demolish":
				builder.set_demolish(true)
			elif builder.active and action == "town_move":
				builder.set_moving(true)
		"title_card":
			_set_open(false)
			_open_t = 0.0
			visible = false
			TitleCard.show_card(self)
		"caravan_come", "caravan_come2", "caravan_leave": ## dev, host: the caravan drives in now / packs up now
			var caravan: CaravanManager = _town().caravan if _town() != null else null
			if caravan == null or not multiplayer.is_server() or not _town().has_heart():
				_failed_flash = 2.5
				return
			if action == "caravan_leave":
				caravan.debug_leave()
			else:
				caravan.debug_come(2 if action == "caravan_come2" else 1)
			_set_open(false)
		"town_jump":
			var town_world: Node = get_tree().get_first_node_in_group("world")
			if town_world == null or not town_world.has_method("debug_can_return_home") or not bool(town_world.call("debug_can_return_home")):
				_failed_flash = 2.5
				return
			_set_open(false)
			_open_t = 0.0
			visible = false
			town_world.call("debug_jump_town")
		"all_jump":
			var all_world: Node = get_tree().get_first_node_in_group("world")
			if all_world == null or not all_world.has_method("debug_can_return_home") or not bool(all_world.call("debug_can_return_home")):
				_failed_flash = 2.5
				return
			_set_open(false)
			_open_t = 0.0
			visible = false
			all_world.call("debug_jump_town", true)
		"gustav_jump":
			var gustav_world: Node = get_tree().get_first_node_in_group("world")
			if gustav_world == null or not gustav_world.has_method("debug_can_return_home") or not bool(gustav_world.call("debug_can_return_home")):
				_failed_flash = 2.5
				return
			_set_open(false)
			_open_t = 0.0
			visible = false
			gustav_world.call("debug_jump_gustav")
		"mornath_quest", "mornath_arena":
			var boss_world: Node = get_tree().get_first_node_in_group("world")
			if boss_world == null or _player == null or not boss_world.has_method("has_arena_story") or not bool(boss_world.call("has_arena_story")):
				_failed_flash = 2.5
				return
			_set_open(false)
			_open_t = 0.0
			visible = false
			boss_world.call("debug_mornath", _player as Player, action == "mornath_arena")
		"morwenna_quest":
			var quest_world: Node = get_tree().get_first_node_in_group("world")
			var w_arena_q: Node = quest_world.get("witch_arena") as Node if quest_world != null else null
			if quest_world == null or _player == null or w_arena_q == null:
				_failed_flash = 2.5
				return
			_set_open(false)
			_open_t = 0.0
			visible = false
			w_arena_q.call("debug_quest", _player as Player)
		"morwenna_tree", "morwenna_fight":
			var witch_world: Node = get_tree().get_first_node_in_group("world")
			if witch_world == null or _player == null or witch_world.get("witch_arena") == null or not witch_world.has_method("debug_morwenna"):
				_failed_flash = 2.5
				return
			_set_open(false)
			_open_t = 0.0
			visible = false
			witch_world.call("debug_morwenna", _player as Player, action == "morwenna_fight")
		"aurelith_basin", "aurelith_fight", "aurelith_stage2", "aurelith_stage3":
			var aur_world: Node = get_tree().get_first_node_in_group("world")
			if aur_world == null or _player == null or aur_world.get("aurelith_arena") == null or not aur_world.has_method("debug_aurelith"):
				_failed_flash = 2.5
				return
			_set_open(false)
			_open_t = 0.0
			visible = false
			var stg: int = 2 if action == "aurelith_stage2" else (3 if action == "aurelith_stage3" else 1)
			aur_world.call("debug_aurelith", _player as Player, action != "aurelith_basin", stg)
		"aurelith_relic":
			var aur_wearer: Player = _player as Player
			if aur_wearer == null or not multiplayer.is_server():
				_failed_flash = 2.5
				return
			if aur_wearer.inventory.count_item("fessel_des_schmelzers") == 0 and not TalismanRules.worn_ids(aur_wearer.inventory.equipment).has("fessel_des_schmelzers"):
				aur_wearer.inventory.give("fessel_des_schmelzers", 1)
		"mine_1", "mine_5", "mine_10", "mine_20", "mine_out":
			var mines: MineManager = get_tree().get_first_node_in_group("mines") as MineManager
			if mines == null or _player == null or not multiplayer.is_server() or not multiplayer.get_peers().is_empty():
				_failed_flash = 2.5
				return
			_set_open(false)
			_open_t = 0.0
			visible = false
			if action == "mine_out":
				mines.leave(_player as Player)
			else:
				mines.enter(_player as Player, action.trim_prefix("mine_").to_int())
		"teleport":
			_teleport_to_field()
		"raid": ## the lure is full: the next tick of the night director gathers a raid (needs night creatures nearby and a founded town)
			var level: Node = get_tree().get_first_node_in_group("world")
			var night_dir: NightDirector = level.get("night") as NightDirector if level != null else null
			if night_dir == null or not night_dir.active():
				_failed_flash = 2.5
				return
			night_dir.debug_force_raid()
		"hurt5":
			if _player != null:
				_player.call("request_set_health", 5.0)
		"refine_0", "refine_5", "refine_10", "refine_15":
			var smith: Player = _player as Player
			if smith == null or not multiplayer.is_server() or not smith.inventory.debug_set_refine(action.trim_prefix("refine_").to_int()):
				_failed_flash = 2.5
		"talismans_on", "talismans_off": ## the three first talismans on (given when missing) or off again; a slot opens only with its level (host)
			var wearer: Player = _player as Player
			if wearer == null or not multiplayer.is_server():
				_failed_flash = 2.5
				return
			for slot_name: String in wearer.inventory.equipment:
				if action == "talismans_off" and slot_name.begins_with(TalismanRules.SLOT_PREFIX):
					wearer.inventory.request("unequip", [slot_name, -1])
			if action == "talismans_on":
				for id: String in ["silver_chain", "wuchtreif", "schweigtropfen"]:
					if wearer.inventory.count_item(id) == 0 and not TalismanRules.worn_ids(wearer.inventory.equipment).has(id):
						wearer.inventory.give(id, 1)
					for i: int in wearer.inventory.slots.size():
						if not wearer.inventory.slots[i].is_empty() and String(wearer.inventory.slots[i]["id"]) == id:
							wearer.inventory.request("equip", [i, ""])
							break
		"talismans_all": ## one of every talisman there is into the bag (host); what she already has is not given twice
			var collector: Player = _player as Player
			if collector == null or not multiplayer.is_server():
				_failed_flash = 2.5
				return
			var items: Dictionary = DataRegistry.table("items")
			for id: String in items:
				var def: Dictionary = items[id] as Dictionary
				if String(def.get("kind", "")) == "talisman" and collector.inventory.count_item(id) == 0 and not TalismanRules.worn_ids(collector.inventory.equipment).has(id):
					collector.inventory.give(id, 1)
		"magic_all": ## the Hexenulmenstab (once) and two of every crystal and gem of every tier into the bag (host)
			var mage: Player = _player as Player
			if mage == null or not multiplayer.is_server():
				_failed_flash = 2.5
				return
			for staff_id: String in ["staff_hag_elm", "staff_bone_fork"]: ## the Hexenulmenstab and the Bleichgabel (docs/magie_konzept.md 17)
				if not mage.inventory.has_item(staff_id):
					mage.inventory.give(staff_id, 1)
			var all_items: Dictionary = DataRegistry.table("items")
			for id: String in all_items:
				var kind: String = String((all_items[id] as Dictionary).get("kind", ""))
				if kind == "crystal" or kind == "gem":
					mage.inventory.give(id, 2)
		"potions_all": ## every potion of every tier into the bag (host), 5 of each
			var brewer: Player = _player as Player
			if brewer == null or not multiplayer.is_server():
				_failed_flash = 2.5
				return
			for type: String in AlchemyRules.TYPES:
				for level: int in range(1, AlchemyRules.tier_count(type) + 1):
					brewer.inventory.give(AlchemyRules.item_id(type, level), 5)
		"rissfeder": ## the Rissfeder into the bag (host); not twice when she has it or wears it
			var keeper: Player = _player as Player
			if keeper == null or not multiplayer.is_server():
				_failed_flash = 2.5
				return
			if keeper.inventory.count_item("rissfeder") == 0 and not TalismanRules.worn_ids(keeper.inventory.equipment).has("rissfeder"):
				keeper.inventory.give("rissfeder", 1)
		"clarity": ## the Ohrringe der Klarheit into the bag (host), not twice
			var wearer: Player = _player as Player
			if wearer == null or not multiplayer.is_server():
				_failed_flash = 2.5
				return
			if wearer.inventory.count_item("clarity_earrings") == 0 and not TalismanRules.worn_ids(wearer.inventory.equipment).has("clarity_earrings"):
				wearer.inventory.give("clarity_earrings", 1)
		"trials_enter", "trials_leave": ## the trials' test world (TrialLevel) and back
			_set_open(false)
			GameLauncher.launch(get_tree(), {"mode": "new", "world": "trials"} if action == "trials_enter" else {"mode": "continue"})
		"moon:4", "moon:0": ## dev, host: the day moves on to the next one with that moon (the clock keeps its time)
			if not multiplayer.is_server():
				_failed_flash = 2.5
				return
			var want: int = int(action.get_slice(":", 1))
			TimeManager.day += posmod(want - posmod(TimeManager.day, 8), 8)
			_set_open(false)
		"wisp_go", "wisp_reset", "crow_go", "crow_reset", "crow_kit", "raven_go", "raven_reset", "raven_kit", "weave_go", "weave_reset", "stars_go", "stars_reset": ## the trials (docs/raetsel_konzept.md)
			var trials: Puzzles = Puzzles.of(get_tree())
			var kinds: Dictionary = {"wisp": "wisp", "crow": "crow_hoard", "raven": "raven_trade", "weave": "root_weave", "stars": "star_mirror"}
			var first: String = "" if trials == null else trials.first_of(String(kinds[action.get_slice("_", 0)]))
			if first == "" or not (_player is Player):
				_failed_flash = 2.5
				return
			if action.ends_with("_reset") or action.ends_with("_kit"):
				if not multiplayer.is_server():
					_failed_flash = 2.5
					return
				if action == "raven_kit":
					(_player as Player).inventory.give("lake_glimmer", 2)
					(_player as Player).inventory.give("stone", 3)
				elif action == "crow_kit":
					(_player as Player).inventory.give("sun_seed", 10)
					if not (_player as Player).inventory.has_item("hoe_basic"):
						(_player as Player).inventory.give("hoe_basic", 1)
				else:
					trials.debug_reset(first)
			else:
				(_player as Player).request_teleport(trials.trial_spot(first))
			_set_open(false)
		"hallgrat_plan", "hallgrat_gate", "hallgrat_fork": ## dev: Hallgrat's ground plan on the ground / to the east gate / to the Westweg's fork
			var west: Hallgrat = get_tree().get_first_node_in_group("hallgrat") as Hallgrat
			if west == null or not (_player is Player):
				_failed_flash = 2.5
				return
			if action == "hallgrat_plan":
				west.show_plan(not west.plan_shown())
				_build_items()
				return
			var to: Vector2 = west.gate_point() if action == "hallgrat_gate" else west.fork_point()
			if not to.is_finite():
				_failed_flash = 2.5
				return
			(_player as Player).request_teleport(to)
			_set_open(false)
		"vista_next": ## jump to the next zone vista's approach spot
			var vistas: Vistas = Vistas.of(get_tree())
			if vistas == null or not (_player is Player):
				_failed_flash = 2.5
				return
			var list: Array[Dictionary] = vistas.entries()
			if list.is_empty():
				_failed_flash = 2.5
				return
			var pick_idx: int = int(get_meta("vista_idx", 0)) % list.size()
			set_meta("vista_idx", (pick_idx + 1) % list.size())
			var spec: Dictionary = list[pick_idx]
			var pt: VistaPoint = vistas.point_node(String(spec.id))
			var dest: Vector2 = pt.approach_position() if pt != null else Vector2(float((spec.tile as Array)[0]), float((spec.tile as Array)[1])) * 16.0 + Vector2(8.0, 8.0)
			(_player as Player).request_teleport(dest)
			_set_open(false)
		"starhall_go", "starhall_rescue", "starhall_light_step", "starhall_reset":
			var gs: GoddessSystem = GoddessSystem.of(get_tree())
			var dev_p: Player = _player as Player
			if gs == null or dev_p == null or not multiplayer.is_server():
				_failed_flash = 2.5
				return
			if action == "starhall_go":
				gs.debug_enter_starhall(dev_p)
				_set_open(false)
			elif action == "starhall_rescue":
				_set_open(false)
				gs.debug_trigger_rescue(dev_p)
			elif action == "starhall_light_step":
				gs.debug_grant_light_step(dev_p, not dev_p.light_step)
			else:
				gs.debug_reset(dev_p)
		"relics_reset": ## forget the boss kills of every player: the next kill of Mornath drops the Rissfeder for certain again (host)
			var ledger: BossRelics = BossRelics.of(get_tree())
			if ledger == null or not multiplayer.is_server():
				_failed_flash = 2.5
				return
			ledger.forget("boss_sky_cleaver")
		"rift_sword": ## the Himmelsriss into the bag and into her hand (host); for the Rissfeder synergy get the feather too
			var rifter: Player = _player as Player
			if rifter == null or not multiplayer.is_server():
				_failed_flash = 2.5
				return
			if not rifter.inventory.has_item("sword_rift"):
				rifter.inventory.give("sword_rift", 1)
			for i: int in rifter.inventory.slots.size():
				if not rifter.inventory.slots[i].is_empty() and String(rifter.inventory.slots[i]["id"]) == "sword_rift":
					rifter.inventory.request("equip", [i, ""])
					break
		"strong_sword": ## the void blade (30 damage) into the bag and into her hand (host)
			var fighter: Player = _player as Player
			if fighter == null or not multiplayer.is_server():
				_failed_flash = 2.5
				return
			if not fighter.inventory.has_item("sword_void"):
				fighter.inventory.give("sword_void", 1)
			for i: int in fighter.inventory.slots.size():
				if not fighter.inventory.slots[i].is_empty() and String(fighter.inventory.slots[i]["id"]) == "sword_void":
					fighter.inventory.request("equip", [i, ""])
					break
		"fish_kit": ## the rod, every bait and the two materials of the floats; the rod is selected (host)
			var angler: Player = _player as Player
			if angler == null or not multiplayer.is_server():
				_failed_flash = 2.5
				return
			if not angler.inventory.has_item("rod_basic"):
				angler.inventory.give("rod_basic", 1)
			for kit: Array in [["dusk_berry", 10], ["ember_berry", 5], ["brook_mint", 10], ["marsh_gold", 10], ["glow_cap", 10], ["void_splinter", 3]]:
				angler.inventory.give(String(kit[0]), int(kit[1]))
			for i: int in InventoryComponent.HOTBAR_SIZE:
				if not angler.inventory.slots[i].is_empty() and String(angler.inventory.slots[i]["id"]) == "rod_basic":
					angler.inventory.select(i)
			angler.inventory.changed.emit()
		"fish_bank":
			var walker: Player = _player as Player
			var bank: Vector2 = FishingComponent.nearest_bank(get_tree(), walker.global_position) if walker != null else Vector2.INF
			if walker == null or bank == Vector2.INF or walker.intro != null or walker.story_lock:
				_failed_flash = 2.5
				return
			walker.request_teleport(bank)
			_set_open(false)
		"atlas_unlock_continent":
			var fog_dev: MapDiscovery = get_tree().get_first_node_in_group("map_discovery") as MapDiscovery
			if fog_dev == null:
				_failed_flash = 2.5
				return
			var next_u: bool = not fog_dev.is_continent_unlocked()
			if multiplayer.is_server():
				fog_dev.set_continent_unlocked(next_u)
			else:
				fog_dev.request_continent_unlocked(next_u)
			if _player is Player and (_player as Player).quests != null:
				if next_u:
					(_player as Player).quests.set_flag("atlas_continent_unlocked")
				else:
					(_player as Player).quests.flags.erase("atlas_continent_unlocked")
					(_player as Player).quests.changed.emit()
			var mw_dev: MapWindow = get_tree().get_first_node_in_group("map_window") as MapWindow
			if mw_dev != null and mw_dev.has_method("set_continent_unlocked_instant"):
				mw_dev.call("set_continent_unlocked_instant", next_u)
			_build_items()
		"reset":
			if _armed != action:
				_arm(action)
			else:
				_reset_and_restart()


func _reset_and_restart() -> void:
	_armed = ""
	if not _can_save():
		return
	CloudSession.set_autosave_suppressed(true)
	CloudSession.reset_autosave_state()
	var path: String = SaveGame.path_for(get_tree())
	if CloudSession.is_logged_in():
		await CloudSession.wipe_cloud_save()
		if not is_inside_tree():
			return
	if not CloudSession.is_strict_release():
		SaveGame.delete(path)
	_set_open(false)
	if NetworkManager.is_multiplayer_session():
		GameLauncher.launch(get_tree(), {
			"mode": "host",
			"port": NetworkManager.active_port,
			"code": NetworkManager.active_room_code,
			"max_players": NetworkManager.active_max_players,
			"world_id": NetworkManager.active_world_id,
			"world_name": NetworkManager.active_world_name,
			"save_path": NetworkManager.active_save_path,
			"skip_autosave": true,
		})
	else:
		GameLauncher.launch(get_tree(), {"mode": "new", "skip_autosave": true})


func _arm(action: String) -> void:
	_armed = action
	_armed_left = 2.5


func _footer_click(index: int) -> void:
	var id: String = String(_footer[index]["id"])
	match id:
		"quit":
			_do_flush_and_quit(false)
		"menu":
			_do_flush_and_quit(true)


func _coop_set_join_mode(next_mode: String) -> void:
	var res: Dictionary = await CloudSession.set_world_join_mode(next_mode)
	if not is_inside_tree():
		return
	_coop_toast = "MODUS: %s" % _join_mode_label(next_mode) if bool(res.get("ok", false)) else String(res.get("error", "FEHLER"))
	_coop_toast_t = 2.4
	_build_items()


func _coop_start_host_relay() -> void:
	if _saving_cloud:
		return
	if _can_save():
		_saving_cloud = true
		await CloudSession.flush_cloud_save_now(get_tree())
		_saving_cloud = false
		if not is_inside_tree():
			return
	_set_open(false)
	GameLauncher.launch(get_tree(), {
		"mode": "host_relay",
		"world_name": "KOOP-WELT",
		"join_mode": CloudSession.world_join_mode,
	})


func _coop_send_invite(target_user_id: String) -> void:
	var res: Dictionary = await CloudSession.coop_invite_friend(target_user_id)
	if not is_inside_tree():
		return
	_coop_toast = "EINLADUNG GESENDET" if bool(res.get("ok", false)) else String(res.get("error", "FEHLER"))
	_coop_toast_t = 2.5
	_build_items()


func _coop_request_friend_join(host_user_id: String) -> void:
	var res: Dictionary = await CloudSession.coop_request_join(host_user_id)
	if not is_inside_tree():
		return
	if not bool(res.get("ok", false)):
		_coop_toast = String(res.get("error", "BEITRITT FEHLGESCHLAGEN"))
		_coop_toast_t = 2.6
		_build_items()
		return
	if String(res.get("status", "")) == "requested":
		_coop_toast = "ANFRAGE AN %s GESENDET" % String(res.get("host_name", "FREUND")).to_upper()
		_coop_toast_t = 3.0
		_build_items()
		return
	var mid: String = String(res.get("match_id", ""))
	if not mid.is_empty():
		_pending_invites[mid] = {
			"match_id": mid,
			"room_code": String(res.get("room_code", "")),
			"world_name": String(res.get("world_name", "KOOP-WELT")),
			"notif_id": "",
		}
		_coop_join_invite(mid)


func _on_sidebar_join_match(info: Dictionary) -> void:
	var mid: String = String(info.get("match_id", ""))
	if mid.is_empty():
		return
	_pending_invites[mid] = {
		"match_id": mid,
		"room_code": String(info.get("room_code", "")),
		"world_name": String(info.get("world_name", "KOOP-WELT")),
		"notif_id": String(info.get("notif_id", "")),
	}
	_coop_join_invite(mid)


func _sidebar_footer_shift() -> float:
	if _sidebar == null or _test_tools:
		return 0.0
	return _sidebar.occupied_width()


func _coop_join_invite(match_id: String) -> void:
	var info: Dictionary = _pending_invites.get(match_id, {}) as Dictionary
	var nid: String = String(info.get("notif_id", ""))
	if not nid.is_empty():
		CloudSession.delete_notification(nid)
	if CloudSession.is_logged_in() and (_can_save() or NetworkManager.is_coop_session()):
		await CloudSession.flush_cloud_save_now(get_tree())
	if not is_inside_tree():
		return
	_set_open(false)
	GameLauncher.launch(get_tree(), {
		"mode": "join_relay",
		"match_id": match_id,
		"code": String(info.get("room_code", "")),
		"world_name": String(info.get("world_name", "KOOP-WELT")),
	})


func _coop_respond_join_req(requester_user_id: String, accept: bool) -> void:
	var res: Dictionary = await CloudSession.coop_respond_join_request(requester_user_id, accept)
	if not is_inside_tree():
		return
	if bool(res.get("ok", false)):
		_coop_toast = "ANFRAGE ANGENOMMEN" if accept else "ANFRAGE ABGELEHNT"
	else:
		_coop_toast = String(res.get("error", "FEHLER"))
	_coop_toast_t = 2.4
	_build_items()


func _read_save_info() -> Dictionary:
	if CloudSession.is_strict_release():
		return CloudSession.cloud_save_info() if CloudSession.is_logged_in() else {}
	if CloudSession.is_logged_in() and not NetworkManager.is_multiplayer_session():
		var cloud_info: Dictionary = CloudSession.cloud_save_info()
		if not cloud_info.is_empty():
			return cloud_info
	return SaveGame.info(SaveGame.path_for(get_tree()))


func _on_auto_save_finished(ok: bool) -> void:
	if not is_inside_tree():
		return
	if ok:
		_save_info = _read_save_info()
		_saved_flash = 1.6


func _do_flush_and_quit(to_menu: bool = false) -> void:
	if _saving_cloud or _quit_t >= 0.0:
		return
	_saving_cloud = true
	CloudSession.capture_live_snapshot(get_tree(), true)
	var should_save: bool = _can_save() or (CloudSession.is_logged_in() and NetworkManager.is_coop_session())
	if should_save:
		var ok: bool = await CloudSession.flush_cloud_save_now(get_tree())
		if not is_inside_tree():
			_saving_cloud = false
			return
		if ok:
			_save_info = _read_save_info()
			_saved_flash = 1.6
	_saving_cloud = false
	_begin_quit(to_menu)


func _begin_quit(to_menu: bool = false) -> void:
	if _dirty:
		GameSettings.save()
		_dirty = false
	_quit_to_menu = to_menu
	_quit_t = 0.0


# ---------- input ----------

func _unhandled_input(event: InputEvent) -> void:
	if _opening and not _test_tools and _sidebar != null and _sidebar.is_typing():
		var sb_key: InputEventKey = event as InputEventKey
		if sb_key != null:
			if sb_key.pressed:
				_sidebar.handle_key_input(sb_key)
			get_viewport().set_input_as_handled()
			return
	if _editing and _opening:
		var typed: InputEventKey = event as InputEventKey
		if typed != null:
			if typed.pressed:
				_type_into_field(typed)
			get_viewport().set_input_as_handled()
			return
	if InputManager.chat_open or InputManager.chat_closed_recently():
		return
	if event.is_action_pressed("ui_cancel") or (_opening and _test_tools and event.is_action_pressed("mod_menu")):
		if embedded_in_menu and not _test_tools:
			return
		if _opening:
			if _quit_t < 0.0:
				_set_open(false)
				if _test_tools:
					_open_t = 0.0
					hide()
					get_parent().get_node("ModMenu").call("reopen")
				Sfx.ui(self, "ui_back", -3.0)
			get_viewport().set_input_as_handled()
		elif not InputManager.ui_blocking: ## the inventory takes its own Escape first
			_set_open(true)
			get_viewport().set_input_as_handled()
		return
	if not _opening or _quit_t >= 0.0:
		return
	var key: InputEventKey = event as InputEventKey
	var pad: InputEventJoypadButton = event as InputEventJoypadButton
	if not embedded_in_menu and not _test_tools and key != null and key.pressed and not key.echo and key.physical_keycode in [KEY_Q, KEY_E]:
		_step_tab(-1 if key.physical_keycode == KEY_Q else 1)
	elif not _test_tools and _sidebar != null and _sidebar.visible and key != null and key.pressed and not key.echo and key.physical_keycode == KEY_TAB:
		_sidebar.toggle_expanded()
	elif not embedded_in_menu and not _test_tools and pad != null and pad.pressed and pad.button_index in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
		_step_tab(-1 if pad.button_index == JOY_BUTTON_LEFT_SHOULDER else 1)
	elif event.is_action_pressed("ui_down"):
		_move_focus(1)
	elif event.is_action_pressed("ui_up"):
		_move_focus(-1)
	elif event.is_action_pressed("ui_left"):
		_nudge(-1)
	elif event.is_action_pressed("ui_right"):
		_nudge(1)
	elif event.is_action_pressed("ui_accept"):
		if _focus >= 0:
			_activate(_items[_focus])
	else:
		return
	get_viewport().set_input_as_handled()


## Keys for a text field. The teleport field takes digits, minus, comma and space; the name of a bird letters, digits, space and dash. Backspace, Ctrl+V,
## Enter confirms (goes / renames), Escape leaves the field.
func _type_into_field(key: InputEventKey) -> void:
	var pet: bool = _field == "pet"
	var name_field: bool = _field == "player_name"
	var text_now: String = _pet_text if pet else (_name_text if name_field else _tp_text)
	match key.physical_keycode:
		KEY_ESCAPE:
			_editing = false
			return
		KEY_ENTER, KEY_KP_ENTER:
			_editing = false
			_run_action("pet_rename" if pet else ("coop_apply_name" if name_field else "teleport"))
			return
		KEY_BACKSPACE:
			text_now = text_now.substr(0, text_now.length() - 1)
		_:
			var text: String = ""
			if key.ctrl_pressed and key.physical_keycode == KEY_V:
				text = DisplayServer.clipboard_get()
			elif key.unicode > 0:
				text = char(key.unicode)
			var limit: int = int(((PetRules.table()["register"] as Dictionary)["max_name"])) if pet else 18
			for c: String in text:
				var is_word_char: bool = (c.to_upper() >= "A" and c.to_upper() <= "Z") or c in "ÄÖÜäöüß0123456789 -"
				var allowed: bool = is_word_char if (pet or name_field) else c in "0123456789-, "
				if allowed and text_now.length() < limit:
					text_now += c.to_upper() if (pet or name_field) else c
	if pet:
		_pet_text = text_now
	elif name_field:
		_name_text = text_now
	else:
		_tp_text = text_now


func _teleport_to_field() -> void:
	var found: Array[RegExMatch] = RegEx.create_from_string("-?[0-9]+").search_all(_tp_text)
	if found.size() < 2 or _player == null:
		_failed_flash = 2.5
		return
	var tile: Vector2i = Vector2i(found[0].get_string().to_int(), found[1].get_string().to_int())
	var world: Node = get_tree().get_first_node_in_group("world")
	if world != null and world.has_method("director"):
		var dir: ZoneDirector = world.call("director") as ZoneDirector
		if dir != null and dir.atlas != null:
			var cont: Atlas.Continent = dir.atlas.continent(dir.continent_id)
			if cont != null:
				tile = Vector2i(clampi(tile.x, 0, maxi(cont.size.x - 1, 0)), clampi(tile.y, 0, maxi(cont.size.y - 1, 0)))
	_set_open(false)
	_open_t = 0.0
	visible = false
	_player.call("request_teleport", Vector2(tile) * 16.0 + Vector2(8.0, 8.0))


func _move_focus(direction: int) -> void:
	var index: int = _focus
	for _i: int in _items.size():
		index = posmod(index + direction, _items.size())
		if _interactive(_items[index]):
			_focus = index
			_reveal(_items[index])
			return


func _nudge(direction: int) -> void:
	if _focus >= 0:
		_change(_items[_focus], direction)


func _gui_input(event: InputEvent) -> void:
	if embedded_in_menu and not _test_tools:
		var mb_top: InputEventMouseButton = event as InputEventMouseButton
		if mb_top != null and mb_top.position.y < GameMenu.RAIL_H:
			return
	if _quit_t >= 0.0:
		accept_event()
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	var button: InputEventMouseButton = event as InputEventMouseButton
	if motion != null:
		_hover_tab = _tab_at(motion.position)
		_hover_foot = _foot_at(motion.position)
		var over: bool = (_hover_tab >= 0 and not bool(TABS[_hover_tab]["sealed"])) or _hover_foot >= 0 ## for the cursor: something clickable
		if _drag >= 0:
			_set_slider(_items[_drag], motion.position.x)
			over = true
		else:
			for item: Dictionary in _items:
				if _interactive(item) and _row_visible(item) and _item_rect(item).has_point(motion.position):
					_focus = int(item["idx"])
					over = true
		GameCursor.set_hint(self, &"click" if over else &"")
	elif button != null and button.pressed and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_scroll_by(-26.0 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 26.0, _column_at(button.position.x))
	elif button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_click(button.position)
		else:
			_drag = -1
			if _dirty:
				GameSettings.save()
				_dirty = false
	accept_event()


func _click(point: Vector2) -> void:
	_editing = false
	if _sidebar != null:
		_sidebar.cancel_typing()
	if embedded_in_menu and not _test_tools:
		for si: int in _embedded_sys_sub_rects.size():
			if _embedded_sys_sub_rects[si].has_point(point):
				set_embedded_tab("settings" if si == 0 else "coop")
				Sfx.ui(self, "ui_click", -4.0)
				return
		# Skip legacy top-branch hit testing while embedded in GameMenu
		var tab_skip: bool = true
		if tab_skip:
			pass
	var tab: int = -1 if (embedded_in_menu and not _test_tools) else _tab_at(point)
	if tab >= 0:
		_select_tab(tab)
		return
	var foot: int = _foot_at(point)
	if foot >= 0:
		_footer_click(foot)
		return
	for item: Dictionary in _items:
		if not _interactive(item) or not _row_visible(item) or not _item_rect(item).has_point(point):
			continue
		_focus = int(item["idx"])
		if String(item["kind"]) == "slider":
			if _slider_rect(item).has_point(point):
				_drag = int(item["idx"])
				_set_slider(item, point.x)
		else:
			_activate(item)
		return


func _set_slider(item: Dictionary, mouse_x: float) -> void:
	var left: float = _item_rect(item).position.x + VALUE_X
	var lo: int = int(item.get("min", 0))
	var hi: int = int(item.get("max", 100))
	var ratio: float = clampf((mouse_x - left) / SLIDER_W, 0.0, 1.0)
	var value: int = clampi(roundi((float(lo) + ratio * float(maxi(hi - lo, 1))) / 5.0) * 5, lo, hi)
	GameSettings.set_value(String(item["key"]), value)
	_dirty = true


# ---------- geometry ----------

func _arm_y(x: float) -> float:
	var dx: float = absf(x - size.x / 2.0)
	return ARM_Y + 5.0 * sin(dx / ARM_LEN * PI * 0.9) + sin(x * 0.08) * 1.0


func _tab_anchor(i: int) -> Vector2:
	var x: float = size.x / 2.0 + float(TABS[i]["x"])
	return Vector2(x, _arm_y(x))


func _tab_width(i: int) -> float:
	return PixelText.width(String(TABS[i]["name"])) + 10.0 + (6.0 if bool(TABS[i]["sealed"]) else 0.0)


func _tab_rect(i: int) -> Rect2:
	if embedded_in_menu and not _test_tools and _embedded_sys_sub_rects.size() >= 2:
		if i == 0:
			return _embedded_sys_sub_rects[0]
		if i == 4:
			return _embedded_sys_sub_rects[1]
	var anchor: Vector2 = _tab_anchor(i)
	var width: float = _tab_width(i)
	var drop: float = 10.0 * _back_out(_p(0.3 + i * 0.07, 0.3)) - _tab_lift[i]
	var shiver: float = roundf(sin(_time * 50.0) * 2.0 * _tab_deny[i])
	return Rect2(roundf(anchor.x - width / 2.0 + sin(_time * 1.2 + i * 1.5) * 0.8 + shiver), roundf(anchor.y + drop), width, 13.0)


func _tab_at(point: Vector2) -> int:
	if _test_tools:
		return -1
	for i: int in TABS.size():
		if _tab_rect(i).grow(2.0).has_point(point):
			return i
	return -1


func _foot_anchor_y(x: float) -> float:
	var right_edge: float = size.x - _sidebar_footer_shift()
	return FOOT_Y + 5.0 * pow(maxf(right_edge - x, 0.0) / FOOT_LEN, 1.3) + sin(x * 0.08) * 1.2


func _foot_rect(i: int) -> Rect2:
	var x: float = size.x - _sidebar_footer_shift() - float(_footer[i]["from_right"])
	var width: float = PixelText.width(String(_footer[i]["text"])) + 12.0
	var drop: float = float(_footer[i]["len"]) * _back_out(_p(0.55 + i * 0.07, 0.3)) - _foot_lift[i]
	return Rect2(roundf(x - width / 2.0 + sin(_time * 1.1 + i * 2.0) * 0.8), roundf(_foot_anchor_y(x) + drop), width, 13.0)


func _foot_at(point: Vector2) -> int:
	for i: int in _footer.size():
		if _foot_rect(i).grow(2.0).has_point(point):
			return i
	return -1


func _p(delay: float, duration: float) -> float:
	return clampf((_open_t - delay) / duration, 0.0, 1.0)


func _back_out(p: float) -> float:
	var c: float = 2.2
	return 1.0 + (c + 1.0) * pow(p - 1.0, 3.0) + c * pow(p - 1.0, 2.0)


func _taken(x: float) -> float:
	return VineStyle.infection(maxf(x, size.x - x) * 0.55, VineStyle.void_amount(), int(x / 5.0))


func _row_p(item: Dictionary) -> float:
	## The stagger is capped: long pages must still be fully shown once
	## _open_t and _tab_t reach 1, or the rows with a high index would never appear.
	var idx: int = int(item["idx"])
	var open: float = _p(0.45 + int(item["col"]) * 0.06 + minf(idx * 0.025, 0.18), 0.3)
	return minf(open, clampf((_tab_t - minf(idx * 0.04, 0.5)) / 0.35, 0.0, 1.0))


# ---------- drawing ----------

func _draw() -> void:
	var void_level: float = VineStyle.void_amount()
	var fade: float = _open_t
	if not embedded_in_menu or _test_tools:
		draw_texture_rect(_vignette, Rect2(Vector2.ZERO, size), false, Color(1, 1, 1, fade))
		if void_level > 0.01:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.18, 0.05, 0.4, 0.14 * void_level * fade))
		VineStyle.motes(self, size, _time, fade, void_level)
	_draw_page(void_level)
	if _test_tools:
		var heading: String = "TESTWERKZEUGE"
		var back: String = "ESC / O ZURÜCK"
		_text(heading, Vector2((size.x - PixelText.width(heading)) * 0.5, 32.0), UiStyle.TEXT, fade)
		_text(back, Vector2((size.x - PixelText.width(back)) * 0.5, 48.0), UiStyle.TEXT_DIM, fade)
	elif embedded_in_menu:
		var cur_id: String = String(TABS[_tab]["id"])
		if cur_id == "settings" or cur_id == "coop":
			_draw_footer(void_level)
			_embedded_sys_sub_rects.clear()
			var sub_labels: Array[String] = ["EINSTELLUNGEN", "KOOP & SITZUNG"]
			var sx: float = 14.0
			for si: int in sub_labels.size():
				var sw: float = float(PixelText.width(sub_labels[si])) + 18.0
				var sr: Rect2 = Rect2(sx, GameMenu.RAIL_H + 6.0, sw, 19.0)
				_embedded_sys_sub_rects.append(sr)
				var active_sub: bool = (si == 0 and cur_id == "settings") or (si == 1 and cur_id == "coop")
				MenuChrome.draw_tab_pill(self, sr, active_sub, 0.0, fade)
				MenuChrome.draw_text(self, sub_labels[si], Vector2(sr.position.x + 9.0, sr.position.y + 6.0), MenuChrome.COL_GOLD_HOT if active_sub else MenuChrome.COL_TEXT_SOFT, fade)
				sx += sw + 6.0
	else:
		_draw_tab_branch(void_level)
		_draw_footer(void_level)
		for i: int in TABS.size():
			_draw_tab(i)
		var hint_p: float = _p(0.6, 0.3) * 0.6 ## Q and E flip through the tabs
		_text("Q", Vector2(_tab_rect(0).position.x - 10.0, _tab_rect(0).position.y + 3.0), UiStyle.TEXT_DIM, hint_p)
		_text("E", Vector2(_tab_rect(TABS.size() - 1).end.x + 6.0, _tab_rect(TABS.size() - 1).position.y + 3.0), UiStyle.TEXT_DIM, hint_p)
	if _paused_here and not embedded_in_menu:
		var word: String = "ZEIT STEHT STILL"
		PixelText.draw(self, word, Vector2i(roundi(size.x / 2.0) - PixelText.width(word) / 2, 66), Color(UiStyle.TEXT_DIM, 0.55 * fade), Color(VineStyle.OUTLINE, 0.55 * fade))
	if _quit_t >= 0.0:
		_draw_outro()


func _draw_tab_branch(void_level: float) -> void:
	var cx: float = size.x / 2.0
	var stem: float = _arm_y(cx) * _p(0.0, 0.25)
	for y: int in int(stem) + 1: ## the root drops from the top of the screen
		var thick: int = 6 if y < 8 else 5
		var taken: float = VineStyle.infection(ARM_LEN + (stem - y) * 0.5, void_level, y)
		draw_rect(Rect2(cx - thick / 2.0 - 1.0, y, thick + 2, 1), VineStyle.OUTLINE.lerp(VineStyle.BARK_VOID_LIGHT, taken))
		draw_rect(Rect2(cx - thick / 2.0, y, thick, 1), VineStyle.BARK.lerp(VineStyle.BARK_VOID, taken))
		if y % 3 != 1:
			draw_rect(Rect2(cx - thick / 2.0, y, 1, 1), VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, taken))
	var reach: float = _p(0.15, 0.4)
	var arm: Callable = func(x: float) -> float: return _arm_y(x)
	for side: int in [-1, 1]:
		VineStyle.branch(self, cx, cx + side * ARM_LEN, arm, 5, void_level, 0.0, _time, reach)
		VineStyle.foliage(self, cx, cx + side * ARM_LEN, arm, 8, 300 + side * 40, void_level, 0.0, _time, reach)
	var active: Vector2 = Vector2(roundf(cx + _bloom_x), roundf(_arm_y(cx + _bloom_x)) - 4.0) ## the open tab's bloom
	var open: int = 1 + int(1.5 + 1.5 * sin(_time * 3.0))
	var tone: Color = ACCENT_WARM.lerp(VineStyle.VOID_GLOW, _taken(active.x))
	VineStyle.glow(self, active, 9.0, tone, 0.9 * _p(0.4, 0.3))
	for o: Vector2 in [Vector2(-open, 0), Vector2(open, 0), Vector2(0, -open), Vector2(0, open)]:
		draw_rect(Rect2(active + o, Vector2.ONE), Color(VineStyle.PETAL, _p(0.4, 0.3)))
	draw_rect(Rect2(active, Vector2.ONE), Color(ACCENT_WARM, _p(0.4, 0.3)))


func _draw_plate(rect: Rect2, text: String, tone: Color, text_color: Color, alpha: float, taken: float) -> void:
	draw_rect(rect, Color(VineStyle.OUTLINE, alpha))
	draw_rect(rect.grow(-1.0), Color(VineStyle.BARK.lerp(VineStyle.BARK_VOID, taken).lerp(tone, 0.3), alpha))
	draw_rect(Rect2(rect.position + Vector2(1, 1), Vector2(rect.size.x - 2.0, 1)), Color(VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, taken).lerp(tone, 0.55), alpha))
	var left: float = rect.position.x + (rect.size.x - PixelText.width(text)) / 2.0
	PixelText.draw(self, text, Vector2i(int(left), int(rect.position.y) + 2), Color(text_color, alpha), Color(VineStyle.OUTLINE, alpha))


func _draw_tab(i: int) -> void:
	var p: float = _p(0.3 + i * 0.07, 0.3)
	if p <= 0.0:
		return
	var anchor: Vector2 = _tab_anchor(i)
	var rect: Rect2 = _tab_rect(i)
	var sealed: bool = bool(TABS[i]["sealed"])
	var taken: float = _taken(anchor.x)
	for y: int in range(int(anchor.y) + 1, int(rect.position.y)): ## thread
		draw_rect(Rect2(anchor.x + roundf((rect.get_center().x - anchor.x) * float(y - anchor.y) / maxf(rect.position.y - anchor.y, 1.0)), y, 1, 1), Color(VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, taken) if y % 2 == 0 else VineStyle.BARK.lerp(VineStyle.BARK_VOID, taken), p))
	var active: bool = i == _tab
	var tone: Color = ACCENT_WARM.lerp(VineStyle.VOID_GLOW, taken)
	if active:
		VineStyle.glow(self, rect.get_center(), 24.0, tone, 0.55 * p)
	elif i == _hover_tab and not sealed:
		VineStyle.glow(self, rect.get_center(), 20.0, tone, 0.3 * p)
	var text_color: Color = VineStyle.PETAL if active else (UiStyle.TEXT if not sealed else UiStyle.TEXT_DIM.darkened(0.2))
	_draw_plate(rect, String(TABS[i]["name"]), tone if active else (Color.TRANSPARENT if sealed else tone * 0.35), text_color, p, taken + (0.4 if sealed else 0.0))
	if sealed: ## a closed bud: this one opens later
		var bud: Vector2 = rect.position + Vector2(4, 6)
		draw_rect(Rect2(bud + Vector2(-1, -1), Vector2(3, 3)), Color(VineStyle.BARK_VOID, p))
		draw_rect(Rect2(bud, Vector2.ONE), Color(VineStyle.BARK_VOID_LIGHT, p))


func _draw_page(void_level: float) -> void:
	var reach: float = minf(_p(0.4, 0.45), clampf(_tab_t / 0.4, 0.0, 1.0))
	var last: Array[float] = [0.0, 0.0]
	for item: Dictionary in _items:
		last[int(item["col"])] = maxf(last[int(item["col"])], float(item["y"]) + float(item["h"]) - _scrolls[int(item["col"])])
	for col: int in 2:
		if last[col] > 0.0:
			if String(TABS[_tab]["id"]) == "coop":
				var card: Rect2 = Rect2(_column_x(col) - 4.0, TOP_Y - 6.0, _column_w() + 10.0, minf(last[col], _view_bottom()) - TOP_Y + 12.0)
				draw_rect(card, Color(VineStyle.OUTLINE, 0.72 * reach))
				draw_rect(card.grow(-1.0), Color(0.08, 0.06, 0.14, 0.72 * reach))
				draw_rect(Rect2(card.position + Vector2(2.0, 2.0), Vector2(card.size.x - 4.0, 1.0)), Color("4a4180", 0.55 * reach))
			_draw_column_vine(_column_x(col) + 2.0, TOP_Y - 10.0, minf(last[col], _view_bottom()), reach, void_level)
	for item: Dictionary in _items:
		var p: float = _row_p(item)
		if p > 0.0 and _row_visible(item):
			_draw_row(item, p, void_level)
	for col: int in 2:
		_draw_scrollbar(col, reach, void_level)


## A thin thread with a bud on it at the right of the page while the page is taller than the screen.
func _draw_scrollbar(col: int, reach: float, void_level: float) -> void:
	var max_scroll: float = _max_scroll(col)
	if max_scroll <= 0.0:
		return
	var x: float = _column_x(col) + COLUMN_W + 6.0
	var top: float = TOP_Y
	var length: float = (_view_bottom() - top) * reach
	var taken: float = _taken(x)
	var tone: Color = ACCENT_WARM.lerp(VineStyle.VOID_GLOW, taken)
	for i: int in int(length):
		draw_rect(Rect2(x, top + i, 1, 1), Color(VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, taken), 0.7 if i % 3 != 1 else 0.35))
	var handle: float = top + (length - 12.0) * (_scrolls[col] / max_scroll)
	draw_rect(Rect2(x - 1.0, handle, 3, 12), Color(VineStyle.OUTLINE, reach))
	draw_rect(Rect2(x, handle + 1.0, 1, 10), Color(tone, reach))
	VineStyle.glow(self, Vector2(x, handle + 6.0), 9.0, tone, 0.5 * reach)
	if _scrolls[col] < max_scroll - 1.0:
		_text("v", Vector2(x - 1.0, _view_bottom() - 5.0), Color(tone, 0.8), reach)


## The vine each column hangs on: thick at the top, thin at the bottom, with a twig per row.
func _draw_column_vine(x: float, y0: float, y1: float, reach: float, void_level: float) -> void:
	var span: float = y1 - y0
	for i: int in int(span * reach) + 1:
		var t: float = i / span
		var thick: int = 3 if t < 0.5 else (2 if t < 0.85 else 1)
		var y: float = y0 + i
		var taken: float = VineStyle.infection(span - i + 40.0, void_level, i / 2)
		draw_rect(Rect2(x - thick / 2.0 - 1.0, y, thick + 2, 1), VineStyle.OUTLINE.lerp(VineStyle.BARK_VOID_LIGHT, taken))
		draw_rect(Rect2(x - thick / 2.0, y, thick, 1), VineStyle.BARK.lerp(VineStyle.BARK_VOID, taken))
		if i % 3 != 1:
			draw_rect(Rect2(x - thick / 2.0, y, 1, 1), VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, taken))


func _draw_row(item: Dictionary, p: float, void_level: float) -> void:
	var rect: Rect2 = _item_rect(item)
	var kind: String = String(item["kind"])
	var taken: float = _taken(rect.position.x)
	var focused: bool = int(item["idx"]) == _focus
	var tone: Color = ACCENT_WARM.lerp(VineStyle.VOID_GLOW, taken)
	var base: float = rect.position.x
	var mid: float = rect.position.y + rect.size.y / 2.0
	if kind == "heading":
		_text(String(item["label"]), Vector2(base + 14.0, rect.position.y + 4.0), tone, p)
		var from: float = base + 14.0 + PixelText.width(String(item["label"])) + 5.0
		for x: int in range(int(from), int(base + COLUMN_W)): ## a thread that fades out
			draw_rect(Rect2(x, mid + 1.0, 1, 1), Color(tone, 0.5 * p * (1.0 - (x - from) / (base + COLUMN_W - from))))
		return
	if _interactive(item) or kind == "info": ## the twig from the column vine to the label
		for x: int in range(int(base) + 2, int(base) + 12):
			draw_rect(Rect2(x, mid, 1, 1), Color(VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, taken) if x % 2 == 0 else VineStyle.BARK.lerp(VineStyle.BARK_VOID, taken), p))
		if kind != "info":
			VineStyle.leaf(self, Vector2(base + 9.0, mid), 1, -1, 2, Color(VineStyle.LEAF.lerp(VineStyle.LEAF_VOID, taken), p), Color(VineStyle.LEAF_LIGHT.lerp(VineStyle.LEAF_VOID_LIGHT, taken), p))
	if focused and kind != "info":
		VineStyle.glow(self, Vector2(base + 60.0, mid), 52.0, tone, 0.09 * p)
		draw_rect(Rect2(base + 3.0, mid - 1.0, 3, 3), Color(tone, p * (0.6 + 0.4 * sin(_time * 6.0)))) ## the bud that marks the row
	var label_color: Color = UiStyle.TEXT if focused else UiStyle.TEXT_DIM
	if bool(item.get("soon", false)):
		label_color = label_color.darkened(0.25)
	_text(String(item["label"]), Vector2(base + 14.0, rect.position.y + (rect.size.y - 7.0) / 2.0 + 0.0), label_color, p)
	var control_x: float = base + VALUE_X
	match kind:
		"slider":
			_draw_slider(item, Vector2(control_x, mid), p, tone, focused)
		"toggle":
			_draw_toggle(Vector2(control_x + 4.0, mid), bool(GameSettings.get_value(String(item["key"]))), p, tone, focused)
			var on: String = "AN" if bool(GameSettings.get_value(String(item["key"]))) else "AUS"
			_text(on, Vector2(control_x + 16.0, rect.position.y + 5.0), UiStyle.TEXT if bool(GameSettings.get_value(String(item["key"]))) else UiStyle.TEXT_DIM, p)
		"choice":
			var town_now: TownManager = _town() if String(item["key"]).begins_with("town_") else null
			if town_now != null and String(item["key"]) == "town_color":
				draw_rect(Rect2(control_x - 1.0, rect.position.y + 3.0, 12.0, 10.0), Color(TownEmblems.INK, p))
				draw_rect(Rect2(control_x, rect.position.y + 4.0, 10.0, 8.0), Color(TownEmblems.color(town_now.look_color), p))
				draw_rect(Rect2(control_x + 1.0, rect.position.y + 4.0, 1.0, 8.0), Color(TownEmblems.GOLD, p))
				control_x += 16.0
			elif town_now != null and String(item["key"]) == "town_emblem":
				TownEmblems.draw(self, town_now.look_emblem, Vector2(control_x, rect.position.y + 2.0), 1.0, p)
				control_x += 16.0
			_text(String(item["text"]), Vector2(control_x, rect.position.y + 5.0), UiStyle.TEXT_DIM, p)
		"field":
			var box: Rect2 = Rect2(control_x, rect.position.y + 2.0, 112.0, 13.0)
			draw_rect(box, Color(VineStyle.OUTLINE, p))
			draw_rect(box.grow(-1.0), Color(VineStyle.BARK_VOID.lerp(VineStyle.BARK, 0.35), p))
			if _editing and _field == String(item["key"]):
				draw_rect(Rect2(box.position.x, box.end.y - 1.0, box.size.x, 1.0), Color(tone, p)) ## a lit lower edge while it takes the keys
				VineStyle.glow(self, box.get_center(), 50.0, tone, 0.12 * p)
			var field_key: String = String(item["key"])
			var typed: String = _pet_text if field_key == "pet" else (_name_text if field_key == "player_name" else _tp_text)
			var placeholder: String = String(item.get("hint", "NEUER NAME")) if (field_key == "pet" or field_key == "player_name") else "X, Y"
			var shown: String = typed if (typed != "" or (_editing and _field == field_key)) else placeholder
			_text(shown, Vector2(box.position.x + 4.0, box.position.y + 3.0), UiStyle.TEXT if typed != "" else Color(UiStyle.TEXT_DIM, 0.6), p)
			if _editing and _field == String(item["key"]) and int(_time * 2.0) % 2 == 0:
				draw_rect(Rect2(box.position.x + 4.0 + PixelText.width(typed) + 2.0, box.position.y + 2.0, 1.0, 8.0), Color(tone, p))
		"info":
			var text: String = String(item["text"])
			if text != "": ## a row that only says something (no value) has no plate
				var plate: Rect2 = Rect2(control_x, rect.position.y + 1.0, PixelText.width(text) + 8.0, 10.0)
				draw_rect(plate, Color(VineStyle.OUTLINE, p))
				draw_rect(plate.grow(-1.0), Color(VineStyle.BARK.lerp(VineStyle.BARK_VOID, taken), p))
				_text(text, Vector2(plate.position.x + 4.0, plate.position.y), UiStyle.TEXT, p)
		"button":
			var risky: bool = bool(item.get("risky", false))
			var armed: bool = risky and _armed == String(item["action"])
			var text: String = "SICHER?" if armed else String(item["label"])
			var plate: Rect2 = Rect2(base + 14.0, rect.position.y + 2.0, PixelText.width(text) + 12.0, 13.0)
			var color: Color = DANGER if armed else tone
			_draw_plate(plate, text, color if (focused or armed) else Color.TRANSPARENT, (DANGER.lightened(0.3) if armed else (VineStyle.PETAL if focused else UiStyle.TEXT)), p, taken)
	if bool(item.get("soon", false)):
		var width: int = PixelText.width(String(item["label"]))
		_text("BALD", Vector2(base + 14.0 + width + 5.0, rect.position.y + (rect.size.y - 7.0) / 2.0), Color(UiStyle.TEXT_DIM, 0.45), p)
	var missing_save: bool = (not CloudSession.has_cloud_save) if CloudSession.is_strict_release() else (not CloudSession.has_cloud_save and not SaveGame.exists(SaveGame.path_for(get_tree())))
	if kind == "button" and String(item.get("action", "")) == "reset" and bool(item.get("risky", false)) and missing_save:
		var plate_w: float = PixelText.width(String(item["label"])) + 12.0
		_text("KEIN SPIELSTAND", Vector2(base + 14.0 + plate_w + 6.0, rect.position.y + 5.0), Color(UiStyle.TEXT_DIM, 0.5), p)


func _draw_slider(item: Dictionary, at: Vector2, p: float, tone: Color, focused: bool) -> void:
	var lo: int = int(item.get("min", 0))
	var hi: int = int(item.get("max", 100))
	var raw_int: int = clampi(int(GameSettings.get_value(String(item["key"]))), lo, hi)
	var value: float = float(raw_int - lo) / float(maxi(hi - lo, 1))
	var taken: float = _taken(at.x)
	for x: int in int(SLIDER_W) + 1: ## the track: a thin dark vine
		draw_rect(Rect2(at.x + x, at.y, 1, 1), Color(VineStyle.BARK.lerp(VineStyle.BARK_VOID, taken), p))
		if x % 4 == 0:
			draw_rect(Rect2(at.x + x, at.y + 1.0, 1, 1), Color(VineStyle.OUTLINE, p * 0.7))
	var fill: int = roundi(SLIDER_W * value)
	for x: int in fill + 1: ## the lit part, with a light running along it
		var phase: float = fposmod(_time * 30.0 - x, 40.0)
		var color: Color = tone.lerp(VineStyle.PETAL, 1.0 - phase / 4.0 if phase < 4.0 else 0.0)
		draw_rect(Rect2(at.x + x, at.y - 1.0, 1, 2), Color(color, p))
	var bud: Vector2 = Vector2(at.x + fill, at.y)
	VineStyle.glow(self, bud, 6.0 + (3.0 if focused else 0.0), tone, 0.7 * p)
	for o: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		draw_rect(Rect2(bud + o, Vector2.ONE), Color(VineStyle.PETAL, p))
	draw_rect(Rect2(bud, Vector2.ONE), Color(tone, p))
	var number: String = ("%d%%" % raw_int) if String(item["key"]) == "chat_opacity" else str(raw_int)
	_text(number, Vector2(at.x + SLIDER_W + 8.0, at.y - 3.0), UiStyle.TEXT if focused else UiStyle.TEXT_DIM, p)


## A flower bud: closed and dim when off, a blooming flower with turning petals when on.
func _draw_toggle(at: Vector2, on: bool, p: float, tone: Color, focused: bool) -> void:
	if not on:
		draw_rect(Rect2(at + Vector2(-1, -1), Vector2(3, 4)), Color(VineStyle.BARK_VOID, p))
		draw_rect(Rect2(at + Vector2(0, -1), Vector2(1, 2)), Color(VineStyle.BARK_LIGHT, p))
		if focused:
			VineStyle.glow(self, at, 6.0, tone, 0.25 * p)
		return
	VineStyle.glow(self, at, 8.0, tone, 0.8 * p)
	for k: int in 6:
		var angle: float = _time * 0.8 + k * TAU / 6.0
		draw_rect(Rect2(roundf(at.x + cos(angle) * 3.0), roundf(at.y + sin(angle) * 3.0), 1, 1), Color(VineStyle.PETAL, p))
	draw_rect(Rect2(at + Vector2(-1, -1), Vector2(2, 2)), Color(tone, p))


func _text(text: String, at: Vector2, color: Color, alpha: float) -> void:
	PixelText.draw(self, text, Vector2i(roundi(at.x), roundi(at.y)), Color(color, color.a * alpha), Color(VineStyle.OUTLINE, alpha))


func _draw_footer(void_level: float) -> void:
	var reach: float = _p(0.5, 0.45)
	var right_edge: float = size.x - _sidebar_footer_shift()
	var left_edge: float = maxf(right_edge - FOOT_LEN, 220.0)
	var foot: Callable = func(x: float) -> float: return _foot_anchor_y(x)
	VineStyle.branch(self, right_edge, left_edge, foot, 5, void_level, 20.0, _time, reach)
	VineStyle.foliage(self, right_edge, left_edge, foot, 9, 410, void_level, 20.0, _time, reach)
	for i: int in _footer.size():
		var p: float = _p(0.55 + i * 0.07, 0.3)
		if p <= 0.0:
			continue
		var id: String = String(_footer[i]["id"])
		var x: float = right_edge - float(_footer[i]["from_right"])
		var anchor: Vector2 = Vector2(x, _foot_anchor_y(x))
		var rect: Rect2 = _foot_rect(i)
		var taken: float = _taken(x)
		for y: int in range(int(anchor.y) + 1, int(rect.position.y)):
			draw_rect(Rect2(anchor.x + roundf((rect.get_center().x - anchor.x) * float(y - anchor.y) / maxf(rect.position.y - anchor.y, 1.0)), y, 1, 1), Color(VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, taken) if y % 2 == 0 else VineStyle.BARK.lerp(VineStyle.BARK_VOID, taken), p))
		var tone: Color = ACCENT_WARM.lerp(VineStyle.VOID_GLOW, taken)
		var text: String = String(_footer[i]["text"])
		var text_color: Color = UiStyle.TEXT
		if id == "quit":
			text_color = VineStyle.PETAL
			if _failed_flash > 0.0:
				tone = DANGER
		var hovered: bool = i == _hover_foot
		var main: bool = id == "quit"
		VineStyle.glow(self, rect.get_center(), 26.0 if (hovered or main) else 18.0, tone, (0.45 if main else 0.16) * p + (0.35 if hovered else 0.0))
		var width: float = PixelText.width(text) + 12.0
		var drawn: Rect2 = Rect2(rect.get_center().x - width / 2.0, rect.position.y, width, rect.size.y)
		_draw_plate(drawn, text, tone, text_color, p, taken)
	var info: String = _save_text()
	var info_p: float = _p(0.7, 0.3)
	_text(info, Vector2(_origin_x() + 64.0, FOOT_Y + 14.0), Color("96efc0") if _saved_flash > 0.0 else UiStyle.TEXT_DIM, info_p * (0.95 if _saved_flash > 0.0 else 0.8))
	VineStyle.leaf(self, Vector2(_origin_x() + 58.0, FOOT_Y + 18.0), 1, -1, 3, Color(VineStyle.LEAF, info_p), Color(VineStyle.LEAF_LIGHT, info_p))


func _save_text() -> String:
	if _saving_cloud or CloudSession.is_save_in_flight():
		return "ONLINE AUTO-SPEICHERUNG..."
	if not _can_save():
		return "CHARAKTER AUTOMATISCH ONLINE GESICHERT" if CloudSession.is_logged_in() else "NUR DER HOST SPEICHERT"
	if _save_info.is_empty():
		return "AUTO-SPEICHERN AKTIV"
	var minutes: int = maxi(int((Time.get_unix_time_from_system() - float(_save_info["saved_at"])) / 60.0), 0)
	var ago: String = "GERADE EBEN" if minutes < 1 else ("VOR %d MIN" % minutes if minutes < 60 else "VOR %d STD" % (minutes / 60))
	var clock: int = int(float(_save_info["time"]) * 1440.0)
	return "AUTO-GESPEICHERT: TAG %d, %02d:%02d - %s" % [int(_save_info["day"]) + 1, clock / 60, clock % 60, ago]


## Quitting: the room sinks into the void and says goodbye.
func _draw_outro() -> void:
	var q: float = clampf(_quit_t / QUIT_DELAY, 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.01, 0.08, q * q))
	for k: int in 40: ## spores rush upwards
		var x: float = VineStyle.rand(k + 900) * size.x
		var y: float = size.y - fposmod(q * (1.5 + VineStyle.rand(k + 950)) + VineStyle.rand(k), 1.0) * size.y
		draw_rect(Rect2(roundf(x), roundf(y), 1, 1), Color(VineStyle.VOID_GLOW, q))
	var word: String = "ZUM HAUPTMENÜ" if _quit_to_menu else "BIS BALD"
	var fade: float = clampf((q - 0.35) / 0.4, 0.0, 1.0)
	draw_set_transform(Vector2(size.x / 2.0 - PixelText.width(word), size.y / 2.0 - 7.0), 0.0, Vector2(2, 2))
	PixelText.draw(self, word, Vector2i.ZERO, Color(VineStyle.PETAL, fade), Color(VineStyle.BARK_VOID_LIGHT, fade))
	draw_set_transform(Vector2.ZERO)
