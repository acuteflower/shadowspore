extends Node
## Day/night clock. The host advances it and tells everyone every few seconds; clients keep counting
## in between. One day is 40 minutes: 28 of day/twilight and 12 of night (21:00 - 04:12).
## `ambient_color()` is the tint of the world, `night_amount()` how strongly night lights shine.
## A new day (`day`, `day_started`) begins at sunrise; things that grow back count in days.

signal day_started(day: int)
signal sleep_state_changed()

const DAY_LENGTH_SEC: float = 2400.0 ## 40 real minutes per full 24h cycle (100 s = 1 in-game hour)
const NIGHT_START: float = 0.875 ## 21:00; fully dark from here ...
const NIGHT_END: float = 0.175 ## 04:12; ... until here (0.30 span = 12 min = 7.2 in-game hours)
const DAY_START: float = 0.25 ## sunrise (06:00): a new day begins when the clock passes it
const SYNC_INTERVAL: float = 2.0
const DEBUG_STEP: float = 1.0 / 24.0 ## F4: one in-game hour

## Tint keys (time, color) between the end of the night and its start; night itself is NIGHT_COLOR.
const NIGHT_COLOR: Color = Color(0.30, 0.29, 0.50) ## dark, cold and only a little violet: the grass is multiplied by this
const KEY_TIMES: Array[float] = [0.175, 0.208, 0.242, 0.28, 0.5, 0.72, 0.78, 0.835, 0.875]
const KEY_COLORS: Array[Color] = [
	Color(0.30, 0.29, 0.50), ## night (04:12)
	Color(0.62, 0.48, 0.72), ## violet dawn (~05:00)
	Color(1.00, 0.80, 0.70), ## sunrise (~05:48)
	Color(1.00, 0.96, 0.90), ## morning (~06:43)
	Color(1.00, 0.99, 0.95), ## noon (12:00)
	Color(1.00, 0.97, 0.90), ## afternoon (~17:17)
	Color(0.98, 0.88, 0.82), ## golden hour (~18:43)
	Color(0.76, 0.52, 0.68), ## dusk (~20:02)
	Color(0.30, 0.29, 0.50), ## night (21:00)
]

var time_of_day: float = 0.3 ## 0..1, 0.5 = noon
var day: int = 0 ## days started so far; the host's value wins every sync

## Rolling sleep debt / threshold tracking (host-authoritative, synced to clients).
var sleep_fatigue: float = SleepRules.DEFAULT_FATIGUE
var nights_awake: int = 0
var slept_night_id: int = -1

## The story holds the clock (the opening happens at midnight until she reaches the town); the host sets it, everyone follows.
var locked: bool = false

var _sync_timer: float = 0.0


func is_night() -> bool:
	return time_of_day >= NIGHT_START or time_of_day < NIGHT_END


## The tint multiplied over the world (CanvasModulate).
func ambient_color() -> Color:
	var t: float = time_of_day
	if t >= NIGHT_START or t <= NIGHT_END:
		return NIGHT_COLOR
	for i: int in KEY_TIMES.size() - 1:
		if t < KEY_TIMES[i + 1]:
			return KEY_COLORS[i].lerp(KEY_COLORS[i + 1], inverse_lerp(KEY_TIMES[i], KEY_TIMES[i + 1], t))
	return NIGHT_COLOR


## 0 by day, 1 at night: how strongly night lights (flowers, crystal, eyes) shine.
func night_amount() -> float:
	return night_at(time_of_day)


## The same for any time of day 0..1 (the HUD clock draws the whole day).
func night_at(t: float) -> float:
	if t >= NIGHT_START or t <= NIGHT_END:
		return 1.0
	if t < 0.242:
		return 1.0 - smoothstep(NIGHT_END, 0.242, t)
	if t > 0.78:
		return smoothstep(0.78, NIGHT_START, t)
	return 0.0


## The moon of this night (the night belongs to the day that began at sunrise): 0 new .. 0.5 full .. 1, a cycle of eight days.
func moon_phase() -> float:
	return float(posmod(day, 8)) / 8.0


## 0.65 (new moon) .. 1 (full moon): how bright the moonlight is tonight. Multiply with `night_amount()`.
func moon_light() -> float:
	return 0.65 + 0.175 * (1.0 - cos(TAU * moon_phase()))


## 0 at night, 1 across midday: how high the sun stands. The day-side counterpart of `night_amount()`;
## every sunlight effect (ground, SunGlow, motes, glints) asks this instead of keeping its own curve.
func sun_amount() -> float:
	return sun_at(time_of_day)


func sun_at(t: float) -> float:
	return smoothstep(0.208, 0.35, t) * (1.0 - smoothstep(0.68, 0.85, t))


## 0..1, peaks at sunrise (06:00) and sunset (about 18:10): low, warm, back-lit light.
func golden_amount() -> float:
	return golden_at(time_of_day)


func golden_at(t: float) -> float:
	var evening_peak: float = 1.0 - maxf(absf(t - 0.778) - 0.022, 0.0) / 0.055
	return smoothstep(0.0, 1.0, maxf(1.0 - absf(t - 0.25) / 0.065, evening_peak))


## 0..1: morning dew on the blades, peaking at dawn/early morning and fading toward 09:30.
func dew_amount() -> float:
	var t: float = time_of_day
	return smoothstep(0.21, 0.26, t) * (1.0 - smoothstep(0.33, 0.40, t))


func night_span() -> float:
	return SleepRules.night_span(NIGHT_START, NIGHT_END)


func night_hours() -> float:
	return night_span() * 24.0


func night_progress_at(t: float) -> float:
	return SleepRules.night_progress(t, NIGHT_START, NIGHT_END)


func night_progress() -> float:
	return night_progress_at(time_of_day)


func sleep_threshold() -> float:
	return SleepRules.unlock_progress(sleep_fatigue)


func sleep_unlock_time() -> float:
	return SleepRules.unlock_time_of_day(sleep_fatigue, NIGHT_START, NIGHT_END)


func can_sleep_now() -> bool:
	return SleepRules.can_sleep(time_of_day, sleep_fatigue, NIGHT_START, NIGHT_END)


## "HH:MM" on a 24 hour clock (noon = 12:00).
func clock_text() -> String:
	var minutes: int = int(time_of_day * 1440.0)
	return "%02d:%02d" % [minutes / 60, minutes % 60]


## Escape menu (dev tab) and F4: sets the time of day. The host applies it; clients ask the host.
func set_time(time: float) -> void:
	time = fposmod(time, 1.0)
	if multiplayer.is_server():
		var before: float = time_of_day
		time_of_day = time
		var advanced: bool = _check_day(before)
		if NetworkManager.rpc_ready(self):
			_rpc_time_jump.rpc(time_of_day, day, locked, advanced)
		elif advanced:
			day_started.emit(day)
	elif NetworkManager.rpc_ready(self):
		_request_time.rpc_id(1, time)


@rpc("any_peer", "call_remote", "reliable")
func _request_time(time: float) -> void:
	if multiplayer.is_server():
		set_time(time)


func _process(delta: float) -> void:
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	var before: float = time_of_day
	if not locked:
		time_of_day = fposmod(time_of_day + delta / DAY_LENGTH_SEC, 1.0)
		_check_day(before)
	if not multiplayer.is_server():
		return
	if InputManager.debug_time_pressed():
		before = time_of_day
		time_of_day = fposmod(time_of_day + DEBUG_STEP, 1.0)
		_check_day(before)
		if NetworkManager.rpc_ready(self):
			_sync_time.rpc(time_of_day, day, locked)
	_sync_timer += delta
	if _sync_timer >= SYNC_INTERVAL:
		_sync_timer = 0.0
		if NetworkManager.rpc_ready(self):
			_sync_time.rpc(time_of_day, day, locked)


## Counts a new day when the clock moved forward past sunrise.
func _check_day(before: float) -> bool:
	var moved: float = fposmod(time_of_day - before, 1.0)
	var to_sunrise: float = fposmod(DAY_START - before, 1.0)
	if moved > 0.0 and to_sunrise > 0.0 and to_sunrise <= moved:
		var finished_night: int = day
		day += 1
		if multiplayer.is_server() and not locked and finished_night >= 1 and slept_night_id < finished_night:
			sleep_fatigue = SleepRules.fatigue_after_all_nighter(sleep_fatigue)
			nights_awake += 1
			_broadcast_sleep_state()
			sleep_state_changed.emit()
		day_started.emit(day)
		return true
	return false


func record_sleep(sleep_progress: float) -> void:
	if not multiplayer.is_server():
		return
	slept_night_id = day
	nights_awake = 0
	sleep_fatigue = SleepRules.fatigue_after_sleep(sleep_fatigue, sleep_progress)
	_broadcast_sleep_state()
	sleep_state_changed.emit()


## Story / opening sleeps keep default fatigue and mark the opening night as rested so day 1 starts fresh.
func mark_story_rested() -> void:
	if not multiplayer.is_server():
		return
	slept_night_id = day
	nights_awake = 0
	sleep_fatigue = SleepRules.DEFAULT_FATIGUE
	_broadcast_sleep_state()
	sleep_state_changed.emit()


func reset_sleep_state() -> void:
	sleep_fatigue = SleepRules.DEFAULT_FATIGUE
	nights_awake = 0
	slept_night_id = -1
	_broadcast_sleep_state()
	sleep_state_changed.emit()


func export_sleep_state() -> Dictionary:
	return {
		"fatigue": sleep_fatigue,
		"nights_awake": nights_awake,
		"slept_night_id": slept_night_id,
	}


func import_sleep_state(data: Dictionary) -> void:
	sleep_fatigue = clampf(float(data.get("fatigue", SleepRules.DEFAULT_FATIGUE)), 0.0, 1.0)
	nights_awake = maxi(int(data.get("nights_awake", 0)), 0)
	slept_night_id = int(data.get("slept_night_id", -1))
	_broadcast_sleep_state()
	sleep_state_changed.emit()


func _broadcast_sleep_state() -> void:
	if multiplayer.is_server() and NetworkManager.rpc_ready(self):
		_sync_sleep_state.rpc(sleep_fatigue, nights_awake, slept_night_id)


@rpc("authority", "call_remote", "unreliable")
func _sync_time(time: float, host_day: int, host_locked: bool) -> void:
	time_of_day = time
	day = host_day
	locked = host_locked


@rpc("authority", "call_remote", "reliable")
func _rpc_time_jump(time: float, host_day: int, host_locked: bool, day_advanced: bool) -> void:
	time_of_day = time
	day = host_day
	locked = host_locked
	if day_advanced:
		day_started.emit(day)


@rpc("authority", "call_remote", "reliable")
func _sync_sleep_state(host_fatigue: float, host_nights_awake: int, host_slept_night: int) -> void:
	sleep_fatigue = clampf(host_fatigue, 0.0, 1.0)
	nights_awake = maxi(host_nights_awake, 0)
	slept_night_id = host_slept_night
	sleep_state_changed.emit()


## Host: stops the clock at `time` (or lets it run again with `unlock`).
func lock_at(time: float) -> void:
	locked = true
	time_of_day = fposmod(time, 1.0)
	day = 0
	if multiplayer.is_server() and NetworkManager.rpc_ready(self):
		_sync_time.rpc(time_of_day, day, locked)


func unlock() -> void:
	locked = false
