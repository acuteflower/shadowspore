extends Node
## Grafikstufen und Laufzeit-Budgets (docs/performance.md, "Grafikstufen").
##
## Eine Stufe (NIEDRIG / MITTEL / HOCH / ULTRA) ist ein Satz Budgets, die die teuren Systeme lesen:
## Takt der prozeduralen Gegner-Rigs, Hardware-Lichter, Glühwürmchen, Partikel, Spiegelungen, Schatten,
## Wiesendetails, Tierbestand, Streaming-Budget und Worker-Threads. Systeme fragen `Quality.get_value(key)`
## bzw. `Quality.scaled(n, key)` ab; ändert sich die Stufe, kommt `changed`.
##
## Adaptiv (Einstellung "adaptive", Standard an): der Frame-Governor misst die echte Framezeit. Liegt sie
## mehrere Sekunden über dem Ziel (Bildratenlimit, sonst Bildschirmfrequenz), senkt er die WIRKSAME Stufe um
## eins; hat er lange Luft, hebt er sie wieder bis zur gewählten Stufe. Nichts davon wird gespeichert.
##
## Erste Ausführung: `detect()` schätzt die Stufe aus GPU-Typ, Kernen und Arbeitsspeicher.

signal changed

enum Level { LOW = 0, MEDIUM = 1, HIGH = 2, ULTRA = 3 }
const NAMES: Array[String] = ["NIEDRIG", "MITTEL", "HOCH", "ULTRA"]
const FPS_CAPS: Array[int] = [30, 60, 90, 120, 144, 165, 240, 0] ## 0 = unbegrenzt
const FPS_CAP_NAMES: Array[String] = ["30", "60", "90", "120", "144", "165", "240", "OFFEN"]

## Budgets je Stufe. Faktoren (`*_scale`) multiplizieren die bisherigen Werte (HOCH = 1.0 = der bisherige Look).
const PRESETS: Array[Dictionary] = [
	{ # NIEDRIG: schwache iGPUs / alte Laptops
		"rig_hz": 20.0, "rig_fast_hz": 30.0, ## Gegner-Rigs: Neuaufbau pro Sekunde (ruhig / schnell)
		"lights": 8, "lights_small_min": 2, ## gleichzeitige PointLight2D (Rest: unbeleuchtete Lichtpfütze)
		"light_breath_hz": 10.0, ## wie oft atmende Lichter ihre Energie nachführen
		"fireflies": 0.4, "day_motes": 0.4, "particles": 0.45,
		"wildlife": 0.55,
		"reflections": false, "reflection_items": 0.4, "shadow_items": 0.35,
		"weather_fx": 1, "tree_cover_hz": 5.0, "sway_hz": 20.0,
		"stream_usec": 1600, "prefetch": 3, "screen_fx": 0,
		"pixel_res": true, ## render the world at 640x360 and scale it up (screen shaders cost 1/9 at 1080p)
	},
	{ # MITTEL
		"rig_hz": 24.0, "rig_fast_hz": 45.0,
		"lights": 12, "lights_small_min": 3,
		"light_breath_hz": 20.0,
		"fireflies": 0.7, "day_motes": 0.7, "particles": 0.75,
		"wildlife": 0.8,
		"reflections": true, "reflection_items": 0.65, "shadow_items": 0.6,
		"weather_fx": 2, "tree_cover_hz": 8.0, "sway_hz": 30.0,
		"stream_usec": 2000, "prefetch": 4, "screen_fx": 1,
		"pixel_res": false,
	},
	{ # HOCH (= der bisherige Look)
		"rig_hz": 30.0, "rig_fast_hz": 60.0,
		"lights": 16, "lights_small_min": 4,
		"light_breath_hz": 30.0,
		"fireflies": 1.0, "day_motes": 1.0, "particles": 1.0,
		"wildlife": 1.0,
		"reflections": true, "reflection_items": 1.0, "shadow_items": 1.0,
		"weather_fx": 2, "tree_cover_hz": 10.0, "sway_hz": 60.0,
		"stream_usec": 2600, "prefetch": 6, "screen_fx": 2,
		"pixel_res": false,
	},
	{ # ULTRA: starke Rechner, mehr Kerne in Arbeit, flüssigere Rigs
		"rig_hz": 60.0, "rig_fast_hz": 60.0,
		"lights": 16, "lights_small_min": 4,
		"light_breath_hz": 60.0,
		"fireflies": 1.25, "day_motes": 1.0, "particles": 1.25,
		"wildlife": 1.0,
		"reflections": true, "reflection_items": 1.0, "shadow_items": 1.0,
		"weather_fx": 2, "tree_cover_hz": 15.0, "sway_hz": 60.0,
		"stream_usec": 3200, "prefetch": 8, "screen_fx": 2,
		"pixel_res": false,
	},
]

const GOVERN_WINDOW: float = 2.5 ## s Framezeit-Mittel, bevor der Governor urteilt
const GOVERN_DOWN_OVER: float = 1.18 ## Mittel > Ziel x dies -> eine Stufe runter
const GOVERN_UP_UNDER: float = 0.62 ## Mittel < Ziel x dies (lange genug) -> eine Stufe hoch
const GOVERN_UP_HOLD: float = 12.0 ## s Luft am Stück, bevor es wieder hochgeht
const GOVERN_COOLDOWN: float = 6.0 ## s nach jeder Änderung nichts tun (Streaming-Spitzen, Szenenwechsel)

var level: int = Level.HIGH ## die gewählte Stufe
var effective: int = Level.HIGH ## die wirksame Stufe (<= level, vom Governor gesenkt)
var adaptive: bool = true

var _frame_sum: float = 0.0
var _frame_count: int = 0
var _window: float = 0.0
var _cooldown: float = 3.0
var _headroom: float = 0.0
var _avg_ms: float = 0.0
var _syncing: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -90
	reload()
	get_tree().node_added.connect(_on_node_added)


## Liest die Einstellungen neu und wendet alles an (vom Einstellungsmenü nach jeder Änderung gerufen).
func reload() -> void:
	_syncing = true
	var stored: Variant = GameSettings.get_value("quality")
	if stored == null or int(stored) < 0:
		level = detect()
		GameSettings.set_value("quality", level)
		GameSettings.save()
	else:
		level = clampi(int(stored), Level.LOW, Level.ULTRA)
	adaptive = bool(GameSettings.get_value("adaptive"))
	if _forced():
		adaptive = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--quality="):
			level = clampi(int(arg.trim_prefix("--quality=")), Level.LOW, Level.ULTRA)
			adaptive = false
	_set_effective(level, true)
	apply_engine()
	_syncing = false


## Von `GameSettings.apply()` nach jeder Einstellungsänderung: übernimmt Stufe, Adaptiv und Bildratenlimit.
func sync_settings() -> void:
	if _syncing:
		return
	_syncing = true
	var stored: int = int(GameSettings.get_value("quality"))
	var want_adaptive: bool = bool(GameSettings.get_value("adaptive")) and not _forced()
	if _forced():
		stored = level
	if stored >= 0 and (stored != level or want_adaptive != adaptive):
		level = clampi(stored, Level.LOW, Level.ULTRA)
		adaptive = want_adaptive
		effective = -1 ## a new choice starts at the chosen level; the governor may lower it again
		_set_effective(level)
	apply_engine()
	_syncing = false


## Command line fixes the level (benchmarks, tests): `--quality=N`, `--quality-fixed`, or headless.
func _forced() -> bool:
	if DisplayServer.get_name() == "headless" or OS.get_cmdline_user_args().has("--quality-fixed"):
		return true
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--quality="):
			return true
	return false


## Engine-Seite: Bildratenlimit, Worker-Threads.
func apply_engine() -> void:
	var cap_index: int = clampi(int(GameSettings.get_value("fps_cap")), 0, FPS_CAPS.size() - 1)
	Engine.max_fps = FPS_CAPS[cap_index]
	var root: Window = get_tree().root if is_inside_tree() else null
	if root != null and DisplayServer.get_name() != "headless":
		## NIEDRIG: the whole picture at the art's own 640x360 (every full-screen shader runs on 230k pixels instead of
		## 2-8 million); the other levels draw at window resolution (smooth camera, crisp scaled UI).
		var pixel: bool = bool(PRESETS[level]["pixel_res"]) or bool(GameSettings.get_value("pixel_res")) ## the chosen level, never the governor (no sudden change of the picture)
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT if pixel else Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var cores: int = OS.get_processor_count()
	## Worker für Chunk-Bau, Wege, Pfade: niedrige Stufen lassen dem Main-/Render-Thread mehr Luft.
	var spare: int = [3, 2, 2, 1][effective]
	Jobs.max_running = clampi(cores - spare, 1, 12 if effective >= Level.ULTRA else 8)


func get_value(key: String) -> Variant:
	return PRESETS[effective].get(key)


func scale(key: String) -> float:
	return float(PRESETS[effective].get(key, 1.0))


## `count` mit dem Faktor `key` der wirksamen Stufe, nie unter `minimum`.
func scaled(count: int, key: String, minimum: int = 0) -> int:
	return maxi(minimum, int(round(count * scale(key))))


## Every particle emitter that enters the tree gets the graphics level's share of its particles (once, before it starts).
func _on_node_added(node: Node) -> void:
	if not (node is CPUParticles2D or node is GPUParticles2D):
		return
	var factor: float = scale("particles")
	if is_equal_approx(factor, 1.0) or node.has_meta(&"q_amount"):
		return
	var base: int = int(node.get(&"amount"))
	node.set_meta(&"q_amount", base)
	if base > 1:
		node.set(&"amount", maxi(1, int(round(base * factor))))


## Ziel-Framezeit in ms: Bildratenlimit, sonst die Bildschirmfrequenz (mindestens 60 Hz).
func target_ms() -> float:
	if Engine.max_fps > 0:
		return 1000.0 / Engine.max_fps
	var hz: float = DisplayServer.screen_get_refresh_rate()
	if hz <= 1.0:
		hz = 60.0
	return 1000.0 / clampf(hz, 60.0, 144.0)


func average_ms() -> float:
	return _avg_ms


## Schätzt eine Stufe für diesen Rechner (nur beim allerersten Start).
static func detect() -> int:
	var cores: int = OS.get_processor_count()
	var mem_gb: float = float(OS.get_memory_info().get("physical", 8 * 1024 * 1024 * 1024)) / (1024.0 * 1024.0 * 1024.0)
	var adapter: String = RenderingServer.get_video_adapter_name().to_lower()
	var device: int = RenderingServer.get_video_adapter_type()
	var integrated: bool = device == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU or adapter.contains("intel") or adapter.contains("uhd") or adapter.contains("vega") or adapter.contains("radeon(tm) graphics")
	if DisplayServer.get_name() == "headless":
		return Level.HIGH
	if cores <= 4 or mem_gb < 6.0:
		return Level.LOW
	if integrated:
		return Level.MEDIUM if cores >= 8 else Level.LOW
	if cores >= 12 and mem_gb >= 15.0:
		return Level.ULTRA
	return Level.HIGH


func _process(delta: float) -> void:
	if get_tree().paused or delta <= 0.0:
		return
	var ms: float = minf(delta * 1000.0, 250.0)
	_frame_sum += ms
	_frame_count += 1
	_window += delta
	if _window < GOVERN_WINDOW:
		return
	_avg_ms = _frame_sum / maxf(_frame_count, 1)
	_frame_sum = 0.0
	_frame_count = 0
	var span: float = _window
	_window = 0.0
	if not adaptive:
		return
	_cooldown -= span
	if _cooldown > 0.0:
		return
	var target: float = target_ms()
	if _avg_ms > target * GOVERN_DOWN_OVER and effective > Level.LOW:
		_headroom = 0.0
		_set_effective(effective - 1)
	elif _avg_ms < target * GOVERN_UP_UNDER and effective < level:
		_headroom += span
		if _headroom >= GOVERN_UP_HOLD:
			_headroom = 0.0
			_set_effective(effective + 1)
	else:
		_headroom = 0.0


func _set_effective(value: int, quiet: bool = false) -> void:
	value = clampi(value, Level.LOW, level)
	if value == effective and quiet:
		apply_static()
		return
	var moved: bool = value != effective
	effective = value
	_cooldown = GOVERN_COOLDOWN
	apply_static()
	if moved:
		apply_engine()
		if not quiet and OS.is_debug_build():
			print("[Quality] wirksame Stufe: %s (Mittel %.1f ms, Ziel %.1f ms)" % [NAMES[effective], _avg_ms, target_ms()])
	changed.emit()


## Budgets, die als statische Werte gelesen werden (heiße Pfade sollen kein Dictionary nachschlagen).
func apply_static() -> void:
	var preset: Dictionary = PRESETS[effective]
	RigClock.base_hz = float(preset["rig_hz"])
	RigClock.base_fast_hz = float(preset["rig_fast_hz"])
	NightLight.limit = int(preset["lights"])
	NightLight.small_min = int(preset["lights_small_min"])
	NightLight.breath_step = 1.0 / float(preset["light_breath_hz"])


## --- Einstellungs-Zeilen (Haupt- und Pausenmenü teilen sie) --------------------------------------------

## Die Schlüssel, die als Auswahl (links/rechts) durchgeschaltet werden.
const CYCLE_KEYS: Array[String] = ["quality", "fps_cap", "weather_fx"]


func is_cycle(key: String) -> bool:
	return CYCLE_KEYS.has(key)


## Text der aktuellen Auswahl.
func label(key: String) -> String:
	match key:
		"quality":
			var text: String = NAMES[level]
			if adaptive and effective < level:
				text += " (%s)" % NAMES[effective]
			return text
		"fps_cap":
			return FPS_CAP_NAMES[clampi(int(GameSettings.get_value("fps_cap")), 0, FPS_CAPS.size() - 1)]
		"weather_fx":
			return ["AUS", "REDUZIERT", "VOLL"][clampi(int(GameSettings.get_value("weather_fx")), 0, 2)]
	return str(GameSettings.get_value(key))


## Schaltet eine Auswahl weiter (dir +-1), speichert und wendet sie an.
func cycle(key: String, dir: int) -> void:
	match key:
		"quality":
			GameSettings.set_value("quality", posmod(level + dir, NAMES.size()))
		"fps_cap":
			GameSettings.set_value("fps_cap", posmod(int(GameSettings.get_value("fps_cap")) + dir, FPS_CAPS.size()))
		"weather_fx":
			GameSettings.set_value("weather_fx", posmod(int(GameSettings.get_value("weather_fx")) + dir, 3))
	GameSettings.save()
	sync_settings()
