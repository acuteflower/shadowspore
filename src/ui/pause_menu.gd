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
	{"id": "pets", "name": "VÖGEL", "x": 98.0, "sealed": false}, ## the book of the named crows and ravens (docs/pet_konzept.md)
	{"id": "dev", "name": "ENTWICKLER", "x": 150.0, "sealed": false},
]
const CONTROLS: Array[Array] = [
	["BEWEGEN", "", "WASD"], ["SPRINTEN", "sprint", ""], ["SCHATTENSCHRITT", "shadow_step", ""],
	["SCHLEICHEN", "sneak", ""], ["INVENTAR", "inventory", ""], ["KARTE", "map", ""], ["TAGEBUCH", "quest_journal", ""], ["BENUTZEN", "interact", ""],
]

var _player: Node
var _open_t: float = 0.0
var _opening: bool = false
var _time: float = 0.0
var _tab: int = 0
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
var _scrolls: Array[float] = [0.0, 0.0] ## per column: how far it is scrolled up (px); a column taller than the screen scrolls on its own
var _editing: bool = false ## a text field takes the keys
var _field: String = "tp" ## which one: "tp" (teleport, developer tab) or "pet" (the name of a bird)
var _pet_sel: String = "" ## the bird whose page is open in the VÖGEL tab
var _pet_text: String = "" ## the new name being typed


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
		_scrolls = [0.0, 0.0]
		_tp_text = ""
		_bloom_x = float(TABS[0]["x"])
		_armed = ""
		_save_info = SaveGame.info(SaveGame.path_for(get_tree())) if _can_save() else {}
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


func _build_items() -> void:
	_items.clear()
	_cursor = [TOP_Y, TOP_Y]
	_focus = -1
	match String(TABS[_tab]["id"]):
		"settings":
			_add(0, "heading", "TON")
			_add(0, "slider", "GESAMT", "master")
			_add(0, "slider", "MUSIK", "music")
			_add(0, "slider", "EFFEKTE", "sfx", {"soon": true})
			_add(0, "heading", "BILD")
			_add(0, "toggle", "VOLLBILD", "fullscreen")
			_add(0, "toggle", "VSYNC", "vsync")
			_add(0, "slider", "SCHÜTTELN", "shake")
			_add(0, "button", "FÄHIGKEITEN (%s)" % _key_of("skills"), "", {"action": "skills"}) ## the skill graph: the same view as F / Start
			_add(0, "button", "FORTSCHRITT (%s)" % _key_of("progress"), "", {"action": "progress"}) ## the road of levels: the same view as P
			_add(0, "button", "ELLIES TAGEBUCH", "", {"action": "journal"})
			_add(1, "heading", "SPIEL")
			_add(1, "toggle", "SCHADENSZAHLEN", "numbers")
			_add(1, "toggle", "POSITION", "position")
			_add(1, "toggle", "EIGENER CURSOR", "cursor") ## the pixel cursor (GameCursor); off = the system pointer
			_add(1, "button", "WETTER-EFFEKTE: %s" % ["AUS", "REDUZIERT", "VOLL"][clampi(int(GameSettings.get_value("weather_fx")), 0, 2)], "", {"action": "weather_fx"})
			_add(1, "toggle", "BLITZE SANFT", "flash_soft") ## accessibility: weaker flashes, no bolt drawing
			_add(1, "toggle", "TAGEBUCH OHNE BEWEGUNG", "journal_still")
			_add(1, "choice", "SPRACHE", "language", {"soon": true, "text": "DEUTSCH"})
			_add(1, "heading", "STEUERUNG")
			for row: Array in CONTROLS:
				_add(1, "info", String(row[0]), "", {"text": String(row[2]) if String(row[2]) != "" else _key_of(String(row[1]))})
		"town":
			_build_town_page()
		"pets":
			_build_pets_page()
		"dev":
			_add(0, "heading", "ZEIT")
			_add(0, "button", "TAG", "", {"action": "day"})
			_add(0, "button", "NACHT", "", {"action": "night"})
			_add(0, "heading", "WETTER: %s" % (WeatherManager.current.display_name() if WeatherManager.current != null else "-"))
			for pair: Array in [["KLAR", "clear"], ["WOLKIG", "broken"], ["BEDECKT", "overcast"], ["NIESELN", "drizzle"], ["REGEN", "rain"], ["STARKREGEN", "downpour"], ["GEWITTER", "storm"], ["STURMWIND", "gale"], ["NEBEL", "fog"], ["AUTOMATISCH", ""]]:
				_add(0, "button", String(pair[0]), "", {"action": "weather:" + String(pair[1])})
			if multiplayer.is_server() and get_tree().get_first_node_in_group("world") is WorldLevel:
				_add(0, "button", "VORSTOSS AUSLÖSEN", "", {"action": "raid"})
			_add(0, "heading", "SPIELER")
			_add(0, "button", "TITELKARTE ZEIGEN", "", {"action": "title_card"})
			_add(0, "button", "HEILEN", "", {"action": "heal"})
			if multiplayer.is_server() and _player is Player:
				_add(0, "button", "GODMODE: %s" % ("AN" if (_player as Player).health.god_mode else "AUS"), "", {"action": "godmode"})
			_add(0, "button", "AUF 5 HP SETZEN", "", {"action": "hurt5"})
			if multiplayer.is_server() and _player is Player:
				_add(0, "button", "+100 XP", "", {"action": "xp_100"})
				_add(0, "button", "+1 STUFE", "", {"action": "level_up"})
			if multiplayer.is_server():
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
				_add(0, "button", "IN DEN HEXENWALD", "", {"action": "hexenwald"})
				_add(0, "button", "IN DIE QUARZWÜSTE", "", {"action": "quartz_desert"})
				_add(0, "button", "ZUR SEEHEXE", "", {"action": "lake_witch"}) ## docs/seehexe_konzept.md: in front of her house at the Hexenwald lake
				_add(0, "button", "SEEHEXE: QUEST STARTEN", "", {"action": "lake_witch_quest"}) ## the entry quest from the start, the ring asleep (host)
				_add(0, "button", "SEEHEXE BEKANNT", "", {"action": "lake_witch_known"}) ## the ring awake, the quest done, the staff in the bag (host)
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
				var fog: MapDiscovery = get_tree().get_first_node_in_group("map_discovery") as MapDiscovery
				_add(0, "heading", "KARTE")
				if fog != null and fog.is_reveal_all():
					_add(0, "button", "NEBEL ZURÜCKSETZEN", "", {"action": "map_reset"}) ## the fog from before the whole-map reveal comes back
				else:
					_add(0, "button", "GANZE KARTE AUFDECKEN", "", {"action": "map_reveal_all"}) ## every part of the world counts as seen (M shows all of it)
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
			if story_world != null and _player != null and story_world.has_arena_story():
				_add(0, "heading", "BOSS-QUEST")
				_add(0, "button", "MORNATH-QUEST STARTEN", "", {"action": "mornath_quest"})
				_add(0, "button", "ZUR SÄULENEBENE", "", {"action": "mornath_arena"})
			if story_world != null and _player != null and story_world.witch_arena != null:
				_add(0, "heading", "MORWENNA")
				_add(0, "button", "ZUM RABENBAUM", "", {"action": "morwenna_tree"})
				_add(0, "button", "MORWENNA SOFORT", "", {"action": "morwenna_fight"})
				_add(0, "button", "SPIEGELHEXE-QUEST", "", {"action": "morwenna_quest"})
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
			_add(1, "heading", "SPIELSTAND")
			_add(1, "button", "SPEICHERSTAND LÖSCHEN & START", "", {"action": "reset", "risky": true})
	for col: int in 2:
		_scrolls[col] = clampf(_scrolls[col], 0.0, _max_scroll(col))
	for item: Dictionary in _items:
		if _focus < 0 and _interactive(item):
			_focus = int(item["idx"])


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
			_add(1, "info", "PFIFF", "", {"text": "G RUFT, G HALTEN WECHSELT"})
		elif registry.peer_of_companion(_pet_sel) == 0:
			_add(1, "button", "MITNEHMEN", "", {"action": "pet_take"})
	_add(1, "heading", "UMBENENNEN")
	_add(1, "field", "NAME", "pet")
	_add(1, "button", "NAMEN ÜBERNEHMEN", "", {"action": "pet_rename"})


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
	if town.board != null: ## what the quest board remembers (docs/questtafel_ausbau_konzept.md 2.8)
		var me: int = multiplayer.get_unique_id()
		_add(0, "info", "ERLEDIGTE ZETTEL", "", {"text": str(town.board.honor_done())})
		var title: String = town.board.title_name(me)
		if title != "":
			_add(0, "info", "TITEL", "", {"text": title})
	_add(0, "heading", "VERWALTUNG")
	_add(0, "button", "BAUEN", "", {"action": "town_build"})
	_add(0, "button", "ABREISSEN", "", {"action": "town_demolish"})
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


func _column_x(col: int) -> float:
	return _origin_x() + COLUMN_X[col]


func _item_rect(item: Dictionary) -> Rect2:
	return Rect2(_column_x(int(item["col"])), float(item["y"]) - _scrolls[int(item["col"])], COLUMN_W, float(item["h"]))


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
			GameSettings.set_value(key, clampi(int(GameSettings.get_value(key)) + direction * 5, 0, 100))
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
	if action.begins_with("weather:"):
		if WeatherManager.current == null or not multiplayer.is_server():
			_failed_flash = 2.5
			return
		var forced: String = action.trim_prefix("weather:")
		if forced == "":
			WeatherManager.current.release()
		else:
			WeatherManager.current.force(forced, 0.0)
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
		"journal":
			var journal: QuestJournal = get_parent().get_node("QuestJournal") as QuestJournal
			_set_open(false)
			journal.open()
			if not InputManager.journal_open:
				_set_open(true)
				_failed_flash = 2.5
		"xp_100", "level_up": ## dev: XP through the normal path (host); the reward still has to be collected in the Fortschritt window
			var earner: Player = _player as Player
			if earner == null or not multiplayer.is_server():
				_failed_flash = 2.5
				return
			var amount: int = 100
			if action == "level_up":
				amount = maxi(Levels.xp_at(earner.progress.level + 1) - earner.progress.xp, 1)
			earner.progress.award(0, amount)
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
		"mornath_quest", "mornath_arena":
			var boss_world: WorldLevel = get_tree().get_first_node_in_group("world") as WorldLevel
			if boss_world == null or _player == null or not boss_world.has_arena_story():
				_failed_flash = 2.5
				return
			_set_open(false)
			_open_t = 0.0
			visible = false
			boss_world.debug_mornath(_player as Player, action == "mornath_arena")
		"morwenna_quest":
			var quest_world: WorldLevel = get_tree().get_first_node_in_group("world") as WorldLevel
			if quest_world == null or _player == null or quest_world.witch_arena == null:
				_failed_flash = 2.5
				return
			_set_open(false)
			_open_t = 0.0
			visible = false
			quest_world.witch_arena.debug_quest(_player as Player)
		"morwenna_tree", "morwenna_fight":
			var witch_world: WorldLevel = get_tree().get_first_node_in_group("world") as WorldLevel
			if witch_world == null or _player == null or witch_world.witch_arena == null:
				_failed_flash = 2.5
				return
			_set_open(false)
			_open_t = 0.0
			visible = false
			witch_world.debug_morwenna(_player as Player, action == "morwenna_fight")
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
		"lake_witch_quest", "lake_witch_known": ## docs/seehexe_konzept.md 8: the entry quest from the start / all of it done
			var story: LakeWitchStory = get_tree().get_first_node_in_group("lake_witch_story") as LakeWitchStory
			if story == null or not multiplayer.is_server():
				_failed_flash = 2.5
				return
			if action == "lake_witch_quest":
				story.debug_start()
			else:
				story.debug_known()
			_set_open(false)
		"lake_witch": ## in front of the lake witch's door
			if _player is Player:
				(_player as Player).request_teleport(Vector2(738, 936) * 16.0 + Vector2(8, 40))
				_set_open(false)
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
		"hexenwald": ## into the middle of the Hexenwald
			if _player is Player:
				(_player as Player).request_teleport(Vector2(826, 880) * 16.0)
				_set_open(false)
		"quartz_desert": ## into the heart of the Sonnenquarz-Öde
			if _player is Player:
				(_player as Player).request_teleport(Vector2(842, 185) * 16.0)
				_set_open(false)
		"map_reveal_all", "map_reset": ## dev, host only: the whole map seen / the fog from before it back (kept in the save)
			var fog: MapDiscovery = get_tree().get_first_node_in_group("map_discovery") as MapDiscovery
			if fog == null or not multiplayer.is_server():
				_failed_flash = 2.5
				return
			if action == "map_reveal_all":
				fog.reveal_all()
			else:
				fog.reset_reveal()
			_build_items()
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
		"reset":
			if _armed != action:
				_arm(action)
			else:
				_reset_and_restart()


func _reset_and_restart() -> void:
	_armed = ""
	if not _can_save():
		return
	var path: String = SaveGame.path_for(get_tree())
	SaveGame.delete(path)
	_set_open(false)
	GameLauncher.launch(get_tree(), {"mode": "host" if path == SaveGame.COOP_PATH else "new"})


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
		_save_info = SaveGame.info(SaveGame.path_for(get_tree()))
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


## Keys for a text field. The teleport field takes digits, minus, comma and space; the name of a bird letters, digits, space and dash. Backspace, Ctrl+V,
## Enter confirms (goes / renames), Escape leaves the field.
func _type_into_field(key: InputEventKey) -> void:
	var pet: bool = _field == "pet"
	var text_now: String = _pet_text if pet else _tp_text
	match key.physical_keycode:
		KEY_ESCAPE:
			_editing = false
			return
		KEY_ENTER, KEY_KP_ENTER:
			_editing = false
			_run_action("pet_rename" if pet else "teleport")
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
				var allowed: bool = (c.to_upper() >= "A" and c.to_upper() <= "Z") or c in "ÄÖÜäöüß0123456789 -" if pet else c in "0123456789-, "
				if allowed and text_now.length() < limit:
					text_now += c.to_upper() if pet else c
	if pet:
		_pet_text = text_now
	else:
		_tp_text = text_now


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
	## The stagger is capped: long pages (the developer tab has 40+ rows) must still be fully shown once
	## _open_t and _tab_t reach 1, or the rows with a high index would never appear.
	var idx: int = int(item["idx"])
	var open: float = _p(0.45 + int(item["col"]) * 0.06 + minf(idx * 0.025, 0.18), 0.3)
	return minf(open, clampf((_tab_t - minf(idx * 0.04, 0.5)) / 0.35, 0.0, 1.0))


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
		last[int(item["col"])] = maxf(last[int(item["col"])], float(item["y"]) + float(item["h"]) - _scrolls[int(item["col"])])
	for col: int in 2:
		if last[col] > 0.0:
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
			var pet_field: bool = String(item["key"]) == "pet"
			var typed: String = _pet_text if pet_field else _tp_text
			var shown: String = typed if (typed != "" or (_editing and _field == String(item["key"]))) else (String(item.get("hint", "NEUER NAME")) if pet_field else "X, Y")
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
	if kind == "button" and bool(item.get("risky", false)) and not SaveGame.exists(SaveGame.path_for(get_tree())):
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
