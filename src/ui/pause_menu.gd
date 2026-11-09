class_name PauseMenu
extends Control
## Escape menu, in the vine style. A root drops from the top of the screen and spreads into a
## branch; the tabs hang from it like wooden tags (Q / E or click; a bloom on the branch marks the
## open one). The town tag shows and manages the player's town (docs/town.md); the map tag is still sealed. The skill graph opens with F / Start or from the settings page. The page grows out of
## the dark: settings as sliders on vines and flower buds that open. Whatever tab is open, the
## branch growing from the right edge carries "save", "save & quit" and "quit without saving".
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
const FOOT_LEN: float = 300.0
const VALUE_X: float = 104.0 ## where a row's control starts, from the column's left
const SLIDER_W: float = 86.0
const ACCENT_WARM: Color = Color("ffd98a")
const DANGER: Color = Color("e0556e")
const TABS: Array[Dictionary] = [
	{"id": "settings", "name": "EINSTELLUNGEN", "x": -92.0, "sealed": false},
	{"id": "map", "name": "KARTE", "x": -34.0, "sealed": true},
	{"id": "town", "name": "STADT", "x": 52.0, "sealed": false}, ## the skill graph stays on F / Start (and the settings page lists its key)
	{"id": "dev", "name": "ENTWICKLER", "x": 120.0, "sealed": false},
]
const CONTROLS: Array[Array] = [
	["BEWEGEN", "", "WASD"], ["SPRINTEN", "sprint", ""], ["BLINKEN", "blink", ""],
	["SCHLEICHEN", "sneak", ""], ["INVENTAR", "inventory", ""], ["KARTE", "map", ""], ["BENUTZEN", "interact", ""],
]

var _player: Node
var _open_t: float = 0.0
var _opening: bool = false
var _time: float = 0.0
var _tab: int = 0
var _tab_t: float = 1.0 ## 0 -> 1 after switching: the page grows again
var _bloom_x: float = 0.0
var _tab_lift: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _tab_deny: Array[float] = [0.0, 0.0, 0.0, 0.0] ## a sealed tag shivers when clicked
var _hover_tab: int = -1
var _items: Array[Dictionary] = []
var _cursor: Array[float] = [0.0, 0.0]
var _focus: int = -1
var _drag: int = -1
var _footer: Array[Dictionary] = []
var _foot_lift: Array[float] = [0.0, 0.0, 0.0]
var _hover_foot: int = -1
var _armed: String = "" ## a risky action waiting for a second click
var _armed_left: float = 0.0
var _saved_flash: float = 0.0
var _failed_flash: float = 0.0
var _save_info: Dictionary = {}
var _quit_t: float = -1.0
var _dirty: bool = false
var _paused_here: bool = false
var _vignette: GradientTexture2D
var _tp_text: String = "" ## the teleport field of the developer tab: "x, y" in tiles
var _scroll: float = 0.0 ## the page is taller than the screen: how far it is scrolled up (px)
var _editing: bool = false ## the teleport field takes the keys


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_vignette = VineStyle.make_vignette()


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
	if _quit_t >= 0.0:
		_quit_t += delta
		if _quit_t >= QUIT_DELAY:
			get_tree().quit()
	queue_redraw()


func _set_open(open: bool) -> void:
	if open == _opening:
		return
	_opening = open
	InputManager.ui_blocking = open
	InputManager.menu_open = open
	if open:
		_tab = 0
		_tab_t = 0.0
		_editing = false
		_scroll = 0.0
		_tp_text = ""
		_bloom_x = float(TABS[0]["x"])
		_armed = ""
		_save_info = SaveGame.info()
		_refresh_footer()
		_build_items()
		_paused_here = multiplayer.get_peers().is_empty() ## alone: time stands still
		get_tree().paused = _paused_here
	else:
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
	if _can_save():
		_footer.append({"id": "discard", "text": "OHNE SPEICHERN", "from_right": 213.0, "len": 13.0})
		_footer.append({"id": "quit", "text": "SPEICHERN & BEENDEN", "from_right": 128.0, "len": 17.0})
		_footer.append({"id": "save", "text": "SPEICHERN", "from_right": 52.0, "len": 11.0})
	else:
		_footer.append({"id": "quit", "text": "SPIEL VERLASSEN", "from_right": 52.0, "len": 15.0})


func _select_tab(index: int) -> void:
	if index == _tab:
		return
	if bool(TABS[index]["sealed"]):
		_tab_deny[index] = 1.0
		return
	_tab = index
	_tab_t = 0.0
	_drag = -1
	_scroll = 0.0
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


func _build_items() -> void:
	_items.clear()
	_cursor = [TOP_Y, TOP_Y]
	_focus = -1
	match String(TABS[_tab]["id"]):
		"settings":
			_add(0, "heading", "TON")
			_add(0, "slider", "GESAMT", "master")
			_add(0, "slider", "MUSIK", "music", {"soon": true})
			_add(0, "slider", "EFFEKTE", "sfx", {"soon": true})
			_add(0, "heading", "BILD")
			_add(0, "toggle", "VOLLBILD", "fullscreen")
			_add(0, "toggle", "VSYNC", "vsync")
			_add(0, "slider", "SCHÜTTELN", "shake")
			_add(0, "button", "FÄHIGKEITEN (%s)" % _key_of("skills"), "", {"action": "skills"}) ## the skill graph: the same view as F / Start
			_add(1, "heading", "SPIEL")
			_add(1, "toggle", "SCHADENSZAHLEN", "numbers")
			_add(1, "toggle", "POSITION", "position")
			_add(1, "toggle", "EIGENER CURSOR", "cursor") ## the pixel cursor (GameCursor); off = the system pointer
			_add(1, "choice", "SPRACHE", "language", {"soon": true, "text": "DEUTSCH"})
			_add(1, "heading", "STEUERUNG")
			for row: Array in CONTROLS:
				_add(1, "info", String(row[0]), "", {"text": String(row[2]) if String(row[2]) != "" else _key_of(String(row[1]))})
		"town":
			_build_town_page()
		"dev":
			_add(0, "heading", "ZEIT")
			_add(0, "button", "TAG", "", {"action": "day"})
			_add(0, "button", "NACHT", "", {"action": "night"})
			if multiplayer.is_server() and get_tree().get_first_node_in_group("world") is WorldLevel:
				_add(0, "button", "VORSTOSS AUSLÖSEN", "", {"action": "raid"})
			_add(0, "heading", "SPIELER")
			_add(0, "button", "TITELKARTE ZEIGEN", "", {"action": "title_card"})
			_add(0, "button", "HEILEN", "", {"action": "heal"})
			if multiplayer.is_server() and _player is Player:
				_add(0, "button", "GODMODE: %s" % ("AN" if (_player as Player).health.god_mode else "AUS"), "", {"action": "godmode"})
			_add(0, "button", "AUF 5 HP SETZEN", "", {"action": "hurt5"})
			if multiplayer.is_server():
				_add(0, "button", "STARKES SCHWERT", "", {"action": "strong_sword"})
				for lvl: int in [0, 5, 10, 15]:
					_add(0, "button", "WAFFE +%d" % lvl, "", {"action": "refine_%d" % lvl}) ## sets the refinement of the weapon in her hand
			if multiplayer.is_server():
				_add(0, "heading", "ANGELN")
				_add(0, "button", "ANGEL + KÖDER", "", {"action": "fish_kit"})
				if get_tree().get_first_node_in_group("world") is WorldLevel:
					_add(0, "button", "ZUM NÄCHSTEN UFER", "", {"action": "fish_bank"})
			var story_world: WorldLevel = get_tree().get_first_node_in_group("world") as WorldLevel
			if story_world != null and story_world.debug_can_return_home():
				_add(0, "heading", "STORY-SPRUNG")
				_add(0, "button", "ZURÜCK MIT DER AXT", "", {"action": "return_home"})
				_add(0, "button", "FERTIGE STADT", "", {"action": "town_jump"})
				_add(0, "button", "GUSTAV GERETTET", "", {"action": "gustav_jump"})
				_add(0, "button", "ALLES FERTIG + TORBEN", "", {"action": "all_jump"})
			if story_world != null and multiplayer.is_server() and multiplayer.get_peers().is_empty():
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
			_add(1, "heading", "WELTWERKSTATT")
			if multiplayer.is_server() and multiplayer.get_peers().is_empty() and get_tree().get_first_node_in_group("world") is WorldLevel:
				_add(1, "button", "MAP-EDITOR ÖFFNEN", "", {"action": "editor"})
			else:
				_add(1, "info", "NUR IN DER SOLO-WELT", "", {"text": ""})
			_add(1, "info", "", "", {"text": "SOLO · OBJEKTE & TERRAIN"})
			if multiplayer.is_server() and multiplayer.get_peers().is_empty():
				_add(1, "heading", "KOCHPLATZ")
				_add(1, "button", "LIES DEN KESSEL", "", {"action": "cook"})
			_add(1, "heading", "SPIELSTAND")
			_add(1, "button", "SPEICHERSTAND LÖSCHEN & START", "", {"action": "reset", "risky": true})
	_scroll = clampf(_scroll, 0.0, _max_scroll())
	for item: Dictionary in _items:
		if _focus < 0 and _interactive(item):
			_focus = int(item["idx"])


func _town() -> TownManager:
	return get_tree().get_first_node_in_group("town") as TownManager


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
	_add(0, "info", "STUFE", "", {"text": town.level_label()})
	_add(0, "info", "WERT", "", {"text": "%d / %d" % [int(town.worth()), int(next_worth)] if next_worth >= 0.0 else "%d" % int(town.worth())})
	_add(0, "info", "EINWOHNER", "", {"text": str(town.population())})
	_add(0, "info", "BAUTEN", "", {"text": "%d" % finished + (" + %d IM BAU" % sites if sites > 0 else "")})
	var reach: float = 0.0
	for c: Vector3 in town.circles():
		reach = maxf(reach, Vector2(c.x, c.y).distance_to(town.center) + c.z)
	_add(0, "info", "LICHT REICHT", "", {"text": "%d KACHELN" % int(reach / 16.0)})
	_add(0, "info", "GEGRÜNDET", "", {"text": "TAG %d" % (town.founded_day + 1)})
	_add(0, "heading", "VERWALTUNG")
	_add(0, "button", "BAUEN", "", {"action": "town_build"})
	_add(0, "button", "ABREISSEN", "", {"action": "town_demolish"})
	_add(0, "choice", "NAME", "town_name", {"text": town.town_name()})
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


func _column_x(col: int) -> float:
	return _origin_x() + COLUMN_X[col]


func _item_rect(item: Dictionary) -> Rect2:
	return Rect2(_column_x(int(item["col"])), float(item["y"]) - _scroll, COLUMN_W, float(item["h"]))


func _view_bottom() -> float:
	return size.y - 14.0


## A row is shown and can be hit only while it lies wholly inside the page area.
func _row_visible(item: Dictionary) -> bool:
	var rect: Rect2 = _item_rect(item)
	return rect.position.y >= TOP_Y - 4.0 and rect.end.y <= _view_bottom()


func _max_scroll() -> float:
	return maxf(maxf(_cursor[0], _cursor[1]) + 6.0 - _view_bottom(), 0.0)


func _scroll_by(amount: float) -> void:
	_scroll = clampf(_scroll + amount, 0.0, _max_scroll())


## Scrolls so that the focused row is inside the page area.
func _reveal(item: Dictionary) -> void:
	var rect: Rect2 = _item_rect(item)
	if rect.position.y < TOP_Y - 4.0:
		_scroll_by(rect.position.y - (TOP_Y - 4.0))
	elif rect.end.y > _view_bottom():
		_scroll_by(rect.end.y - _view_bottom())


func _slider_rect(item: Dictionary) -> Rect2:
	var rect: Rect2 = _item_rect(item)
	return Rect2(rect.position.x + VALUE_X - 3.0, rect.position.y, SLIDER_W + 6.0, rect.size.y)


# ---------- actions ----------

func _change(item: Dictionary, direction: int) -> void:
	var key: String = String(item["key"])
	match String(item["kind"]):
		"slider":
			GameSettings.set_value(key, clampi(int(GameSettings.get_value(key)) + direction * 5, 0, 100))
			_dirty = true
		"toggle":
			if direction != 0:
				_toggle(item)
		"choice":
			var town: TownManager = _town()
			if key == "town_name" and town != null and direction != 0:
				town.request_name(posmod(town.name_index + direction, TownRules.town_names().size()))


func _toggle(item: Dictionary) -> void:
	GameSettings.set_value(String(item["key"]), not bool(GameSettings.get_value(String(item["key"]))))
	_dirty = true


func _activate(item: Dictionary) -> void:
	match String(item["kind"]):
		"toggle":
			_toggle(item)
		"choice":
			_change(item, 1)
		"field":
			_editing = true
		"button":
			_run_action(String(item["action"]))


func _run_action(action: String) -> void:
	match action:
		"skills":
			var skills: SkillTreeWindow = get_parent().get_node("SkillTreeWindow") as SkillTreeWindow
			_set_open(false)
			skills._set_open(true)
			if not skills._opening:
				_set_open(true)
				_failed_flash = 2.5
		"town_build", "town_demolish":
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
				builder.demolish = true
		"cook":
			if _player==null or not multiplayer.is_server() or not multiplayer.get_peers().is_empty() or _player.get("intro")!=null or bool(_player.get("story_lock")):
				_failed_flash = 2.5
				return
			var health: HealthComponent = _player.get_node_or_null("HealthComponent") as HealthComponent
			if health==null or health.current<=0.0:
				_failed_flash = 2.5
				return
			_set_open(false)
			_open_t = 0.0
			visible = false
			var layer: CanvasLayer = CanvasLayer.new()
			layer.name = "CookingLayer"
			layer.layer = 40
			var kitchen: CookingWindow = CookingWindow.new()
			get_tree().root.add_child(layer)
			layer.add_child(kitchen)
			kitchen.start(_player)
		"title_card":
			_set_open(false)
			_open_t = 0.0
			visible = false
			TitleCard.show_card(self)
		"town_jump":
			var town_world: WorldLevel = get_tree().get_first_node_in_group("world") as WorldLevel
			if town_world == null or not town_world.debug_can_return_home():
				_failed_flash = 2.5
				return
			_set_open(false)
			_open_t = 0.0
			visible = false
			town_world.debug_jump_town()
		"all_jump":
			var all_world: WorldLevel = get_tree().get_first_node_in_group("world") as WorldLevel
			if all_world == null or not all_world.debug_can_return_home():
				_failed_flash = 2.5
				return
			_set_open(false)
			_open_t = 0.0
			visible = false
			all_world.debug_jump_town(true)
		"gustav_jump":
			var gustav_world: WorldLevel = get_tree().get_first_node_in_group("world") as WorldLevel
			if gustav_world == null or not gustav_world.debug_can_return_home():
				_failed_flash = 2.5
				return
			_set_open(false)
			_open_t = 0.0
			visible = false
			gustav_world.debug_jump_gustav()
		"return_home":
			var world: WorldLevel = get_tree().get_first_node_in_group("world") as WorldLevel
			if world == null or not world.debug_can_return_home():
				_failed_flash = 2.5
				return
			_set_open(false)
			_open_t = 0.0
			visible = false
			world.debug_return_home()
		"editor":
			var world: WorldLevel = get_tree().get_first_node_in_group("world") as WorldLevel
			if world == null or not multiplayer.is_server() or not multiplayer.get_peers().is_empty():
				_failed_flash = 2.5
				return
			_set_open(false)
			_open_t = 0.0
			visible = false
			var editor: WorldEditor = WorldEditor.new()
			world.add_child(editor)
			editor.start(world)
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
		"day":
			TimeManager.set_time(0.4)
		"night":
			TimeManager.set_time(0.0)
		"raid": ## the lure is full: the next tick of the night director gathers a raid (needs night creatures nearby and a founded town)
			var level: WorldLevel = get_tree().get_first_node_in_group("world") as WorldLevel
			if level == null or level.night == null or not level.night.active():
				_failed_flash = 2.5
				return
			level.night.debug_force_raid()
		"heal":
			if _player != null:
				_player.call("request_heal")
		"godmode": ## host only: damage, burn and kills do nothing to the local player
			var god: Player = _player as Player
			if god == null or not multiplayer.is_server():
				_failed_flash = 2.5
				return
			god.health.god_mode = not god.health.god_mode
			var keep_focus: int = _focus
			_build_items()
			if keep_focus >= 0 and keep_focus < _items.size() and _interactive(_items[keep_focus]):
				_focus = keep_focus
		"hurt5":
			if _player != null:
				_player.call("request_set_health", 5.0)
		"refine_0", "refine_5", "refine_10", "refine_15":
			var smith: Player = _player as Player
			if smith == null or not multiplayer.is_server() or not smith.inventory.debug_set_refine(action.trim_prefix("refine_").to_int()):
				_failed_flash = 2.5
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
		"reset":
			if _armed != action:
				_arm(action)
			else:
				_reset_and_restart()


func _reset_and_restart() -> void:
	_armed = ""
	SaveGame.delete()
	_set_open(false)
	get_tree().paused = false
	InputManager.ui_blocking = false
	InputManager.menu_open = false
	InputManager.build_open = false
	InputManager.map_open = false
	InputManager.skills_open = false
	Terrain.relief = null
	if not (multiplayer.multiplayer_peer is ENetMultiplayerPeer and multiplayer.is_server() and multiplayer.get_peers().is_empty()):
		NetworkManager.leave()
	get_tree().change_scene_to_file.call_deferred("res://src/world/main.tscn")


func _arm(action: String) -> void:
	_armed = action
	_armed_left = 2.5


func _footer_click(index: int) -> void:
	var id: String = String(_footer[index]["id"])
	match id:
		"save":
			_do_save(false)
		"quit":
			if not _can_save():
				_begin_quit()
			else:
				_do_save(true)
		"discard":
			if _armed != id:
				_arm(id)
			else:
				_begin_quit()


func _do_save(then_quit: bool) -> void:
	if SaveGame.save(get_tree()):
		_save_info = SaveGame.info()
		_saved_flash = 2.0
		if then_quit:
			_begin_quit()
	else:
		_failed_flash = 2.5


func _begin_quit() -> void:
	if _dirty:
		GameSettings.save()
		_dirty = false
	_quit_t = 0.0


# ---------- input ----------

func _unhandled_input(event: InputEvent) -> void:
	if _editing and _opening:
		var typed: InputEventKey = event as InputEventKey
		if typed != null:
			if typed.pressed:
				_type_into_field(typed)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ui_cancel"):
		if _opening:
			if _quit_t < 0.0:
				_set_open(false)
			get_viewport().set_input_as_handled()
		elif not InputManager.ui_blocking: ## the inventory takes its own Escape first
			_set_open(true)
			get_viewport().set_input_as_handled()
		return
	if not _opening or _quit_t >= 0.0:
		return
	var key: InputEventKey = event as InputEventKey
	var pad: InputEventJoypadButton = event as InputEventJoypadButton
	if key != null and key.pressed and not key.echo and key.physical_keycode in [KEY_Q, KEY_E]:
		_step_tab(-1 if key.physical_keycode == KEY_Q else 1)
	elif pad != null and pad.pressed and pad.button_index in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
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


## Keys for the teleport field: digits, minus, comma and space; Backspace, Ctrl+V, Enter goes, Escape leaves the field.
func _type_into_field(key: InputEventKey) -> void:
	match key.physical_keycode:
		KEY_ESCAPE:
			_editing = false
		KEY_ENTER, KEY_KP_ENTER:
			_editing = false
			_run_action("teleport")
		KEY_BACKSPACE:
			_tp_text = _tp_text.substr(0, _tp_text.length() - 1)
		_:
			var text: String = ""
			if key.ctrl_pressed and key.physical_keycode == KEY_V:
				text = DisplayServer.clipboard_get()
			elif key.unicode > 0:
				text = char(key.unicode)
			for c: String in text:
				if c in "0123456789-, " and _tp_text.length() < 18:
					_tp_text += c


func _teleport_to_field() -> void:
	var found: Array[RegExMatch] = RegEx.create_from_string("-?[0-9]+").search_all(_tp_text)
	if found.size() < 2 or _player == null:
		_failed_flash = 2.5
		return
	var tile: Vector2i = Vector2i(found[0].get_string().to_int(), found[1].get_string().to_int())
	var world: WorldLevel = get_tree().get_first_node_in_group("world") as WorldLevel
	if world != null:
		tile = Vector2i(clampi(tile.x, 0, RegionMap.WORLD_TILES - 1), clampi(tile.y, 0, RegionMap.WORLD_TILES - 1))
		if not bool(world.call("_land_at", tile.x, tile.y)):
			var land: Vector2i = Vector2i(-1, -1) ## open sea or void: the nearest dry tile (rings up to 16 tiles)
			for r: int in range(1, 17):
				for dy: int in range(-r, r + 1):
					for dx: int in range(-r, r + 1):
						if maxi(absi(dx), absi(dy)) == r and land.x < 0 and bool(world.call("_land_at", tile.x + dx, tile.y + dy)):
							land = tile + Vector2i(dx, dy)
			if land.x < 0:
				_failed_flash = 2.5
				return
			tile = land
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
		_scroll_by(-26.0 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 26.0)
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
	var tab: int = _tab_at(point)
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
	var value: int = clampi(roundi((mouse_x - left) / SLIDER_W * 20.0) * 5, 0, 100)
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
	var anchor: Vector2 = _tab_anchor(i)
	var width: float = _tab_width(i)
	var drop: float = 10.0 * _back_out(_p(0.3 + i * 0.07, 0.3)) - _tab_lift[i]
	var shiver: float = roundf(sin(_time * 50.0) * 2.0 * _tab_deny[i])
	return Rect2(roundf(anchor.x - width / 2.0 + sin(_time * 1.2 + i * 1.5) * 0.8 + shiver), roundf(anchor.y + drop), width, 13.0)


func _tab_at(point: Vector2) -> int:
	for i: int in TABS.size():
		if _tab_rect(i).grow(2.0).has_point(point):
			return i
	return -1


func _foot_anchor_y(x: float) -> float:
	return FOOT_Y + 5.0 * pow((size.x - x) / FOOT_LEN, 1.3) + sin(x * 0.08) * 1.2


func _foot_rect(i: int) -> Rect2:
	var x: float = size.x - float(_footer[i]["from_right"])
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
	var open: float = _p(0.45 + int(item["col"]) * 0.06 + int(item["idx"]) * 0.025, 0.3)
	return minf(open, clampf((_tab_t - int(item["idx"]) * 0.04) / 0.35, 0.0, 1.0))


# ---------- drawing ----------

func _draw() -> void:
	var void_level: float = VineStyle.void_amount()
	var fade: float = _open_t
	draw_texture_rect(_vignette, Rect2(Vector2.ZERO, size), false, Color(1, 1, 1, fade))
	if void_level > 0.01:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.18, 0.05, 0.4, 0.14 * void_level * fade))
	VineStyle.motes(self, size, _time, fade, void_level)
	_draw_tab_branch(void_level)
	_draw_page(void_level)
	_draw_footer(void_level)
	for i: int in TABS.size():
		_draw_tab(i)
	var hint_p: float = _p(0.6, 0.3) * 0.6 ## Q and E flip through the tabs
	_text("Q", Vector2(_tab_rect(0).position.x - 10.0, _tab_rect(0).position.y + 3.0), UiStyle.TEXT_DIM, hint_p)
	_text("E", Vector2(_tab_rect(TABS.size() - 1).end.x + 6.0, _tab_rect(TABS.size() - 1).position.y + 3.0), UiStyle.TEXT_DIM, hint_p)
	if _paused_here:
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
		last[int(item["col"])] = maxf(last[int(item["col"])], float(item["y"]) + float(item["h"]) - _scroll)
	for col: int in 2:
		if last[col] > 0.0:
			_draw_column_vine(_column_x(col) + 2.0, TOP_Y - 10.0, minf(last[col], _view_bottom()), reach, void_level)
	for item: Dictionary in _items:
		var p: float = _row_p(item)
		if p > 0.0 and _row_visible(item):
			_draw_row(item, p, void_level)
	_draw_scrollbar(reach, void_level)


## A thin thread with a bud on it at the right of the page while the page is taller than the screen.
func _draw_scrollbar(reach: float, void_level: float) -> void:
	var max_scroll: float = _max_scroll()
	if max_scroll <= 0.0:
		return
	var x: float = _column_x(1) + COLUMN_W + 6.0
	var top: float = TOP_Y
	var length: float = (_view_bottom() - top) * reach
	var taken: float = _taken(x)
	var tone: Color = ACCENT_WARM.lerp(VineStyle.VOID_GLOW, taken)
	for i: int in int(length):
		draw_rect(Rect2(x, top + i, 1, 1), Color(VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, taken), 0.7 if i % 3 != 1 else 0.35))
	var handle: float = top + (length - 12.0) * (_scroll / max_scroll)
	draw_rect(Rect2(x - 1.0, handle, 3, 12), Color(VineStyle.OUTLINE, reach))
	draw_rect(Rect2(x, handle + 1.0, 1, 10), Color(tone, reach))
	VineStyle.glow(self, Vector2(x, handle + 6.0), 9.0, tone, 0.5 * reach)
	if _scroll < max_scroll - 1.0:
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
			_text(String(item["text"]), Vector2(control_x, rect.position.y + 5.0), UiStyle.TEXT_DIM, p)
		"field":
			var box: Rect2 = Rect2(control_x, rect.position.y + 2.0, 112.0, 13.0)
			draw_rect(box, Color(VineStyle.OUTLINE, p))
			draw_rect(box.grow(-1.0), Color(VineStyle.BARK_VOID.lerp(VineStyle.BARK, 0.35), p))
			if _editing:
				draw_rect(Rect2(box.position.x, box.end.y - 1.0, box.size.x, 1.0), Color(tone, p)) ## a lit lower edge while it takes the keys
				VineStyle.glow(self, box.get_center(), 50.0, tone, 0.12 * p)
			var shown: String = _tp_text if (_tp_text != "" or _editing) else "X, Y"
			_text(shown, Vector2(box.position.x + 4.0, box.position.y + 3.0), UiStyle.TEXT if _tp_text != "" else Color(UiStyle.TEXT_DIM, 0.6), p)
			if _editing and int(_time * 2.0) % 2 == 0:
				draw_rect(Rect2(box.position.x + 4.0 + PixelText.width(_tp_text) + 2.0, box.position.y + 2.0, 1.0, 8.0), Color(tone, p))
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
	if kind == "button" and bool(item.get("risky", false)) and not SaveGame.exists():
		var plate_w: float = PixelText.width(String(item["label"])) + 12.0
		_text("KEIN SPIELSTAND", Vector2(base + 14.0 + plate_w + 6.0, rect.position.y + 5.0), Color(UiStyle.TEXT_DIM, 0.5), p)


func _draw_slider(item: Dictionary, at: Vector2, p: float, tone: Color, focused: bool) -> void:
	var value: float = float(int(GameSettings.get_value(String(item["key"])))) / 100.0
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
	var number: String = str(int(value * 100.0))
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
	var foot: Callable = func(x: float) -> float: return _foot_anchor_y(x)
	VineStyle.branch(self, size.x, size.x - FOOT_LEN, foot, 5, void_level, 20.0, _time, reach)
	VineStyle.foliage(self, size.x, size.x - FOOT_LEN, foot, 9, 410, void_level, 20.0, _time, reach)
	for i: int in _footer.size():
		var p: float = _p(0.55 + i * 0.07, 0.3)
		if p <= 0.0:
			continue
		var id: String = String(_footer[i]["id"])
		var x: float = size.x - float(_footer[i]["from_right"])
		var anchor: Vector2 = Vector2(x, _foot_anchor_y(x))
		var rect: Rect2 = _foot_rect(i)
		var taken: float = _taken(x)
		for y: int in range(int(anchor.y) + 1, int(rect.position.y)):
			draw_rect(Rect2(anchor.x + roundf((rect.get_center().x - anchor.x) * float(y - anchor.y) / maxf(rect.position.y - anchor.y, 1.0)), y, 1, 1), Color(VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, taken) if y % 2 == 0 else VineStyle.BARK.lerp(VineStyle.BARK_VOID, taken), p))
		var tone: Color = ACCENT_WARM.lerp(VineStyle.VOID_GLOW, taken)
		var text: String = String(_footer[i]["text"])
		var text_color: Color = UiStyle.TEXT
		match id:
			"save":
				if _saved_flash > 0.0:
					tone = Color("7fe3a8")
					text = "GESPEICHERT"
					text_color = Color("c8ffd8")
				elif _failed_flash > 0.0:
					tone = DANGER
					text = "FEHLER"
			"discard":
				text_color = UiStyle.TEXT_DIM
				if _armed == id:
					tone = DANGER
					text = "SICHER?"
					text_color = DANGER.lightened(0.3)
			"quit":
				text_color = VineStyle.PETAL
				if _failed_flash > 0.0:
					tone = DANGER
		var hovered: bool = i == _hover_foot
		var main: bool = id == "quit"
		VineStyle.glow(self, rect.get_center(), 26.0 if (hovered or main) else 18.0, tone, (0.45 if main else 0.16) * p + (0.35 if hovered else 0.0) + (0.5 if (id == "save" and _saved_flash > 0.0) else 0.0))
		var width: float = PixelText.width(text) + 12.0
		var drawn: Rect2 = Rect2(rect.get_center().x - width / 2.0, rect.position.y, width, rect.size.y)
		_draw_plate(drawn, text, tone, text_color, p, taken)
		if _saved_flash > 0.0 and id == "save": ## sparks leap off the plate
			for k: int in 6:
				var angle: float = k * TAU / 6.0 + _time * 2.0
				var r: float = (1.0 - _saved_flash / 2.0) * 14.0 + 6.0
				draw_rect(Rect2(roundf(drawn.get_center().x + cos(angle) * r * 1.6), roundf(drawn.get_center().y + sin(angle) * r * 0.8), 1, 1), Color(tone, minf(_saved_flash, 1.0)))
	var info: String = _save_text()
	var info_p: float = _p(0.7, 0.3)
	_text(info, Vector2(_origin_x() + 64.0, FOOT_Y + 14.0), UiStyle.TEXT_DIM, info_p * 0.8)
	VineStyle.leaf(self, Vector2(_origin_x() + 58.0, FOOT_Y + 18.0), 1, -1, 3, Color(VineStyle.LEAF, info_p), Color(VineStyle.LEAF_LIGHT, info_p))


func _save_text() -> String:
	if not _can_save():
		return "NUR DER HOST SPEICHERT"
	if _save_info.is_empty():
		return "NOCH NICHT GESPEICHERT"
	var minutes: int = maxi(int((Time.get_unix_time_from_system() - float(_save_info["saved_at"])) / 60.0), 0)
	var ago: String = "GERADE EBEN" if minutes < 1 else ("VOR %d MIN" % minutes if minutes < 60 else "VOR %d STD" % (minutes / 60))
	var clock: int = int(float(_save_info["time"]) * 1440.0)
	return "GESPEICHERT: TAG %d, %02d:%02d - %s" % [int(_save_info["day"]) + 1, clock / 60, clock % 60, ago]


## Quitting: the room sinks into the void and says goodbye.
func _draw_outro() -> void:
	var q: float = clampf(_quit_t / QUIT_DELAY, 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.01, 0.08, q * q))
	for k: int in 40: ## spores rush upwards
		var x: float = VineStyle.rand(k + 900) * size.x
		var y: float = size.y - fposmod(q * (1.5 + VineStyle.rand(k + 950)) + VineStyle.rand(k), 1.0) * size.y
		draw_rect(Rect2(roundf(x), roundf(y), 1, 1), Color(VineStyle.VOID_GLOW, q))
	var word: String = "BIS BALD"
	var fade: float = clampf((q - 0.35) / 0.4, 0.0, 1.0)
	draw_set_transform(Vector2(size.x / 2.0 - PixelText.width(word), size.y / 2.0 - 7.0), 0.0, Vector2(2, 2))
	PixelText.draw(self, word, Vector2i.ZERO, Color(VineStyle.PETAL, fade), Color(VineStyle.BARK_VOID_LIGHT, fade))
	draw_set_transform(Vector2.ZERO)
