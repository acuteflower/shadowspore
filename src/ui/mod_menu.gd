extends Control
## Host-side developer menu for the player, items and the world.

enum Section { CHEATS, ITEMS, WORLD }

const CATEGORIES: Dictionary = {
	"weapon": "Waffen",
	"tool": "Werkzeuge",
	"talisman": "Talismane",
	"consumable": "Verbrauchsgegenstände",
	"potion": "Tränke",
	"material": "Materialien",
	"crystal": "Kristalle",
	"gem": "Edelsteine",
}

var _player: Player
var _hud: CanvasLayer
var _god_mode: Button
var _infinite_stamina: Button
var _level_up: Button
var _map_unlock: Button
var _section: Section = Section.ITEMS
var _weather_ids: Array[String] = [""]
@onready var _list: VBoxContainer = %ItemList
@onready var _status: Label = %Status
@onready var _search: LineEdit = %ItemSearch
@onready var _weather: OptionButton = %WeatherChoice


func bind(player: Node) -> void:
	_player = player as Player
	_hud = get_parent() as CanvasLayer
	_hud.visibility_changed.connect(_on_hud_visibility_changed)
	%Close.pressed.connect(close)
	%CheatsTab.pressed.connect(_show_section.bind(Section.CHEATS))
	%ItemsTab.pressed.connect(_show_section.bind(Section.ITEMS))
	%WorldTab.pressed.connect(_show_section.bind(Section.WORLD))
	%ToolsTab.pressed.connect(_open_test_tools)
	_search.text_changed.connect(_filter_items)
	_search.text_submitted.connect(func(_text: String) -> void: _search.release_focus())
	_god_mode = _add_cheat("Godmode", _toggle_god_mode)
	_infinite_stamina = _add_cheat("Unendliche Ausdauer", _toggle_stamina)
	_add_cheat("Leben und Ausdauer auffüllen", _heal)
	_add_cheat("+1 Gold", _award.bind(Currency.GOLD, 0, "+1 Gold"))
	_add_cheat("+100 XP", _award.bind(0, 100, "+100 XP"))
	_level_up = _add_cheat("+1 Level", _raise_level)
	_level_up.tooltip_text = "Stufenbelohnungen holst du im Fortschrittsmenü (P) ab."
	_map_unlock = _add_cheat("Ganze Karte aufdecken", _toggle_map)
	_add_cheat("Stufenbelohnungen öffnen", _open_level_rewards)
	_setup_world()


func close() -> void:
	if visible:
		_set_open(false)


func reopen() -> void:
	if _can_open():
		_set_open(true)


func _open_test_tools() -> void:
	if not visible or not _can_use():
		return
	var tools: PauseMenu = _hud.get_node("PauseMenu") as PauseMenu
	close()
	tools.open_test_tools()


func _on_hud_visibility_changed() -> void:
	if not _hud.visible:
		close()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("mod_menu"):
		if visible and _search.has_focus():
			return
		if visible or _can_open():
			_set_open(not visible)
			get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("ui_cancel"):
		if _search.has_focus():
			_search.release_focus()
		else:
			_set_open(false)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if visible and (not _can_use() or get_tree().paused):
		_set_open(false)


func _exit_tree() -> void:
	if visible:
		_release_input()


func _can_open() -> bool:
	return _hud != null and _hud.visible and _can_use() and not get_tree().paused \
		and not InputManager.ui_blocking and not InputManager.build_open and not InputManager.freecam_open


func _can_use() -> bool:
	return multiplayer.is_server() and is_instance_valid(_player) and _player.health.current > 0.0 \
		and _player.intro == null and not _player.story_lock


func _set_open(open: bool) -> void:
	if open:
		_show_section(_section)
		InputManager.ui_blocking = true
		InputManager.menu_open = true
		InputManager.mod_menu_open = true
	else:
		_release_input()
	visible = open


func _release_input() -> void:
	InputManager.mod_menu_open = false
	InputManager.menu_open = false
	InputManager.ui_blocking = is_instance_valid(_player) and (_player.story_lock or _player.intro != null or (is_instance_valid(_player.health) and _player.health.current <= 0.0))


func _show_section(section: Section) -> void:
	_section = section
	%CheatsPage.visible = section == Section.CHEATS
	%ItemsPage.visible = section == Section.ITEMS
	%WorldPage.visible = section == Section.WORLD
	_status.text = ""
	match section:
		Section.CHEATS:
			%Title.text = "Cheats"
			_refresh_cheats()
		Section.ITEMS:
			%Title.text = "Alle Items"
			if _list.get_child_count() == 0:
				_build_list()
			_filter_items(_search.text, false)
		Section.WORLD:
			%Title.text = "Welt"
			_refresh_weather()


func _add_cheat(label: String, action: Callable) -> Button:
	return _add_action(%CheatList, label, action)


func _add_action(list: VBoxContainer, label: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = label
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 22
	button.pressed.connect(action)
	list.add_child(button)
	return button


func _setup_world() -> void:
	var time_buttons: VBoxContainer = %TimeButtons
	_add_action(time_buttons, "Morgen (06:00)", _set_time.bind(0.25))
	_add_action(time_buttons, "Mittag (12:00)", _set_time.bind(0.5))
	_add_action(time_buttons, "Abend (18:00)", _set_time.bind(0.75))
	_add_action(time_buttons, "Mitternacht (00:00)", _set_time.bind(0.0))
	_weather.add_item("Automatisch")
	var states: Dictionary = DataRegistry.table("weather").get("states", {})
	for id: String in states:
		_weather_ids.append(id)
		_weather.add_item(WeatherRules.display_name(id).capitalize())
	_weather.item_selected.connect(_set_weather)


func _set_time(time: float) -> void:
	if visible and _can_use():
		TimeManager.set_time(time)
		_status.text = "Uhrzeit auf %s gesetzt" % TimeManager.clock_text()


func _refresh_weather() -> void:
	var weather: WeatherManager = WeatherManager.current
	_weather.disabled = weather == null
	_weather.select(maxi(0, _weather_ids.find(weather.override_id)) if weather != null else 0)
	_weather.tooltip_text = "In dieser Welt gibt es kein Wettersystem." if weather == null else ""


func _set_weather(index: int) -> void:
	var weather: WeatherManager = WeatherManager.current
	if not visible or not _can_use() or weather == null:
		return
	var id: String = _weather_ids[index]
	if id.is_empty():
		weather.release()
		_status.text = "Wetter läuft wieder automatisch"
	else:
		weather.force(id)
		_status.text = "Wetter auf %s gesetzt" % _weather.get_item_text(index)


func _open_level_rewards() -> void:
	if not visible or not _can_use():
		return
	var rewards: ProgressWindow = _hud.get_node("ProgressWindow") as ProgressWindow
	close()
	rewards.open_window()
	if not InputManager.progress_open:
		_set_open(true)
		_status.text = "Fortschritt ist noch nicht verfügbar."


func _refresh_cheats() -> void:
	_god_mode.text = "Godmode · %s" % ("An" if _player.health.god_mode else "Aus")
	_infinite_stamina.text = "Unendliche Ausdauer · %s" % ("An" if _player.stamina.infinite else "Aus")
	_level_up.disabled = _player.progress.level >= Levels.max_level()
	var fog: MapDiscovery = _map_discovery()
	_map_unlock.disabled = fog == null
	_map_unlock.text = "Kartennebel wiederherstellen" if fog != null and fog.is_reveal_all() else "Ganze Karte aufdecken"
	_map_unlock.tooltip_text = "In dieser Welt gibt es keine Weltkarte." if fog == null else ""


func _toggle_god_mode() -> void:
	if visible and _can_use():
		_player.health.god_mode = not _player.health.god_mode
		_refresh_cheats()


func _toggle_stamina() -> void:
	if visible and _can_use():
		_player.stamina.infinite = not _player.stamina.infinite
		_refresh_cheats()


func _heal() -> void:
	if visible and _can_use():
		_player.request_heal()
		_status.text = "Leben und Ausdauer aufgefüllt"


func _award(copper: int, xp: int, feedback: String) -> void:
	if visible and _can_use():
		_player.progress.award(copper, xp)
		_status.text = feedback
		_refresh_cheats()


func _raise_level() -> void:
	if not visible or not _can_use():
		return
	var progress: ProgressComponent = _player.progress
	if progress.level < Levels.max_level():
		var next_level: int = progress.level + 1
		_award(0, Levels.xp_at(next_level) - progress.xp, "Level %d erreicht" % next_level)


func _map_discovery() -> MapDiscovery:
	return get_tree().get_first_node_in_group("map_discovery") as MapDiscovery


func _toggle_map() -> void:
	if not visible or not _can_use():
		return
	var fog: MapDiscovery = _map_discovery()
	if fog == null:
		return
	if fog.is_reveal_all():
		fog.reset_reveal()
		_status.text = "Kartennebel wiederhergestellt"
	else:
		fog.reveal_all()
		_status.text = "Ganze Karte aufgedeckt"
	_refresh_cheats()


func _build_list() -> void:
	var items: Dictionary = DataRegistry.table("items")
	var groups: Dictionary = {}
	for id: String in items:
		var kind: String = String(items[id].get("kind", ""))
		if not groups.has(kind):
			groups[kind] = []
		(groups[kind] as Array).append(id)

	var kinds: Array = CATEGORIES.keys()
	for kind: String in groups:
		if not CATEGORIES.has(kind):
			kinds.append(kind)
	for kind: String in kinds:
		if not groups.has(kind):
			continue
		var ids: Array = groups[kind]
		ids.sort_custom(func(a: String, b: String) -> bool:
			return String(items[a].get("name", a)).nocasecmp_to(String(items[b].get("name", b))) < 0)
		var group: VBoxContainer = VBoxContainer.new()
		_list.add_child(group)
		var heading: Label = Label.new()
		heading.text = String(CATEGORIES.get(kind, kind.capitalize() if not kind.is_empty() else "Sonstiges"))
		heading.add_theme_color_override("font_color", UiStyle.ACCENT)
		heading.add_theme_font_size_override("font_size", 11)
		heading.custom_minimum_size.y = 24
		heading.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		group.add_child(heading)
		for id: String in ids:
			var stack: Dictionary = {"id": id, "count": 1}
			var row: Button = Button.new()
			row.text = String(items[id].get("name", id))
			row.icon = Items.icon(stack)
			row.tooltip_text = id
			row.alignment = HORIZONTAL_ALIGNMENT_LEFT
			row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			row.expand_icon = true
			row.add_theme_constant_override("icon_max_width", 15)
			row.add_theme_color_override("font_color", Items.rarity_color(stack))
			row.custom_minimum_size.y = 22
			row.pressed.connect(_drop.bind(id))
			group.add_child(row)


func _filter_items(query: String, reset_scroll: bool = true) -> void:
	var needle: String = query.strip_edges()
	var matches: int = 0
	for group: VBoxContainer in _list.get_children():
		var found: bool = false
		for child: Control in group.get_children():
			var row: Button = child as Button
			if row == null:
				continue
			row.visible = needle.is_empty() or row.text.containsn(needle) or row.tooltip_text.containsn(needle)
			if row.visible:
				found = true
				matches += 1
		group.visible = found
	if reset_scroll:
		%ItemScroll.set_deferred("scroll_vertical", 0)
	if needle.is_empty():
		_status.text = "Klick auf ein Item, um es zu droppen."
	else:
		_status.text = "%d passende Items" % matches if matches > 0 else "Keine passenden Items"


func _drop(id: String) -> void:
	if not visible or not _can_use() or get_tree().get_first_node_in_group("drops") == null:
		return
	var stack: Dictionary = {"id": id, "count": 1}
	var count: int = maxi(1, Items.max_stack(stack)) if %FullStack.button_pressed else 1
	DropComponent.spawn_thrown(get_tree(), id, count, _player.global_position, _player.facing)
	_status.text = "%d× %s gedroppt" % [count, Items.title(stack)]
