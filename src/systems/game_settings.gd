class_name GameSettings
extends RefCounted
## Player settings (user://settings.cfg). Values live in a Dictionary; `apply()` pushes the ones the
## engine can use (master volume, fullscreen, vsync) and the game reads the rest (`shake_factor`,
## damage numbers, the position display; music = volume of the bus "Music"). Effects and language are stored but have no effect yet.

const PATH: String = "user://settings.cfg"
const DEFAULTS: Dictionary = {
	"master": 80, "music": 70, "sfx": 80,
	"fullscreen": false, "vsync": true, "shake": 100,
	"numbers": true, "language": "de", "position": true, "cursor": true,
	"weather_fx": 2, "flash_soft": false,
}

static var _values: Dictionary = {}
static var _loaded: bool = false


static func get_value(key: String) -> Variant:
	_load()
	return _values.get(key, DEFAULTS.get(key))


static func set_value(key: String, value: Variant) -> void:
	_load()
	_values[key] = value
	apply()


static func shake_factor() -> float:
	return float(get_value("shake")) / 100.0


static func apply() -> void:
	_load()
	var master: int = int(get_value("master"))
	AudioServer.set_bus_mute(0, master <= 0)
	if master > 0:
		AudioServer.set_bus_volume_db(0, linear_to_db(master / 100.0))
	var bus: int = AudioServer.get_bus_index(&"Music") ## the music's own bus (MusicDirector), made on first use
	if bus < 0:
		AudioServer.add_bus()
		bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, &"Music")
	var music: int = int(get_value("music"))
	AudioServer.set_bus_mute(bus, music <= 0)
	if music > 0:
		AudioServer.set_bus_volume_db(bus, linear_to_db(music / 100.0))
	var fullscreen: bool = bool(get_value("fullscreen"))
	var is_fullscreen: bool = DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	if fullscreen != is_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(get_value("vsync")) else DisplayServer.VSYNC_DISABLED)


static func save() -> void:
	_load()
	var file: ConfigFile = ConfigFile.new()
	for key: String in _values:
		file.set_value("settings", key, _values[key])
	file.save(PATH)


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var file: ConfigFile = ConfigFile.new()
	if file.load(PATH) != OK:
		return
	for key: String in DEFAULTS:
		if file.has_section_key("settings", key):
			_values[key] = file.get_value("settings", key)
