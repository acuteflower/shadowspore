extends Node
## Day/night clock. The host advances it and tells everyone every few seconds; clients keep counting
## in between. One day is 12 minutes: 8 of day (with a one minute dawn and dusk) and 4 of night.
## `ambient_color()` is the tint of the world, `night_amount()` how strongly night lights shine.
## A new day (`day`, `day_started`) begins at sunrise; things that grow back count in days.

signal day_started(day: int)

const DAY_LENGTH_SEC: float = 720.0
const NIGHT_START: float = 5.0 / 6.0 ## 0..1, 0.5 = noon; fully dark from here ...
const NIGHT_END: float = 1.0 / 6.0 ## ... until here
const DAY_START: float = 0.25 ## sunrise (06:00): a new day begins when the clock passes it
const SYNC_INTERVAL: float = 2.0
const DEBUG_STEP: float = 1.0 / 12.0 ## F4: one hour (a twelfth of the day)

## Tint keys (time, color) between the end of the night and its start; night itself is NIGHT_COLOR.
const NIGHT_COLOR: Color = Color(0.30, 0.29, 0.50) ## dark, cold and only a little violet: the grass is multiplied by this
const KEY_TIMES: Array[float] = [1.0 / 6.0, 0.2, 0.23, 0.28, 0.5, 0.72, 0.76, 0.795, 5.0 / 6.0]
const KEY_COLORS: Array[Color] = [
	Color(0.30, 0.29, 0.50), ## night
	Color(0.62, 0.48, 0.72), ## violet dawn
	Color(1.00, 0.80, 0.70), ## sunrise
	Color(1.00, 0.96, 0.90), ## morning
	Color(1.00, 0.99, 0.95), ## noon (a touch warm; the brightness comes from the ground shader and SunGlow)
	Color(1.00, 0.97, 0.90), ## afternoon
	Color(1.00, 0.76, 0.52), ## golden hour
	Color(0.76, 0.52, 0.68), ## dusk
	Color(0.30, 0.29, 0.50), ## night
]

var time_of_day: float = 0.3 ## 0..1, 0.5 = noon
var day: int = 0 ## days started so far; the host's value wins every sync

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
	if t < 0.23:
		return 1.0 - smoothstep(NIGHT_END, 0.23, t)
	if t > 0.76:
		return smoothstep(0.76, NIGHT_START, t)
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
	return smoothstep(0.2, 0.36, t) * (1.0 - smoothstep(0.64, 0.8, t))


## 0..1, peaks at sunrise (06:00) and sunset (about 18:10): low, warm, back-lit light.
func golden_amount() -> float:
	return golden_at(time_of_day)


func golden_at(t: float) -> float:
	return smoothstep(0.0, 1.0, maxf(1.0 - absf(t - 0.25) / 0.07, 1.0 - absf(t - 0.757) / 0.07))


## 0..1: morning dew on the blades, from first light until about 08:30.
func dew_amount() -> float:
	var t: float = time_of_day
	return smoothstep(0.21, 0.26, t) * (1.0 - smoothstep(0.31, 0.38, t))


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
		_check_day(before)
		_sync_time.rpc(time, day, locked)
	else:
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
		_sync_time.rpc(time_of_day, day, locked)
	_sync_timer += delta
	if _sync_timer >= SYNC_INTERVAL:
		_sync_timer = 0.0
		_sync_time.rpc(time_of_day, day, locked)


## Counts a new day when the clock moved forward past sunrise.
func _check_day(before: float) -> void:
	var moved: float = fposmod(time_of_day - before, 1.0)
	var to_sunrise: float = fposmod(DAY_START - before, 1.0)
	if moved > 0.0 and to_sunrise > 0.0 and to_sunrise <= moved:
		day += 1
		day_started.emit(day)


@rpc("authority", "call_remote", "unreliable")
func _sync_time(time: float, host_day: int, host_locked: bool) -> void:
	time_of_day = time
	day = host_day
	locked = host_locked


## Host: stops the clock at `time` (or lets it run again with `unlock`).
func lock_at(time: float) -> void:
	locked = true
	time_of_day = fposmod(time, 1.0)
	day = 0
	if multiplayer.is_server() and multiplayer.multiplayer_peer != null:
		_sync_time.rpc(time_of_day, day, locked)


func unlock() -> void:
	locked = false
