class_name BoardNotes
extends Node2D
## The notices of the quest board, seen from outside (docs/questtafel_konzept.md, docs/questtafel_ausbau_konzept.md): every notice that hangs is a small paper pinned to the panel of
## the built board, so a passer-by sees at once whether there is something new. Six places on the panel (a notice keeps its place), a new notice drops into place and is pinned with
## a tack, a paper the local player has already taken or finished hangs faded, a story notice is gold with a glowing teal seal (the unlit pass).
## **Life of the board:** papers age (fresh and smooth, then yellowing, dog-eared, on the last day crooked and the ink half gone, `BoardRules.age`), flutter in the wind and soften in the
## rain; the bud on the post breathes, and pulses (with a rising mote, a small light further out) while notices hang that the local player has not read; a notice that ran out at sunrise
## stays up as a ghost for a while: a crow that lands on the board's roof pulls it off, otherwise the wind takes it. Cosmetic and local: every peer plays its own.
## Two nodes per board: the lit one (`Notes`) owns the state and draws the paper; the unlit one (`SealNotes`, `source` = the lit one) draws the seals, the bud and the glints on top.
## The drawing is static (`paint`) so a preview can use it without a world. The panel of art_quest_board.py spans x -14..14, y -30..-15 from the feet (frame 56x56, feet row 50).

## **Memory of the town** (docs/questtafel_ausbau_konzept.md 2.7, 2.8): a wanted poster for the marked creature hangs over the left post (its own place, never one of the six), a cord under the
## panel carries a small thank-you paper for each finished notice of the town (the last twelve; the newest still swings), and the board grows at 25 / 50 / 100 finished notices: a lantern,
## a second pair of shingles, an honour shield.

const SLOTS: Array[Vector2] = [Vector2(-13, -29), Vector2(-4, -29), Vector2(5, -29), Vector2(-13, -21), Vector2(-4, -21), Vector2(5, -21)] ## top left of each 7x6 paper
const W: int = 7
const H: int = 6
const BUD: Vector2 = Vector2(20, -34) ## the 2x2 bud on the right post, from the feet
const FETCH_PAPER: Color = Color("e8dcc0")
const KILL_PAPER: Color = Color("e6c9b4")
const STORY_PAPER: Color = Color("e9c76a")
const OLD_PAPER: Color = Color("c9a24a")
const WET_PAPER: Color = Color("8f9bb0")
const INK: Color = Color("3a2c3e")
const RED: Color = Color("b8465a")
const PIN: Color = Color("8a8296")
const SEAL: Color = Color("78f4e6")
const GOLD: Color = Color("e9c76a")
const WAX: Color = Color("d0384e") ## the red seal of a rush notice
const MARK: Color = Color("d640c8") ## the magenta of the marked ones
const POSTER: Vector2 = Vector2(-22, -32) ## top left of the 8x14 wanted poster
const POSTER_W: int = 8
const POSTER_H: int = 14
const SKETCH: Dictionary = {
	"shadow_spider": ["#.##.#", ".####.", "######", ".####.", "#.##.#"],
	"void_listener": ["..##..", ".####.", "######", "#.##.#", "..##.."],
	"void_crusher": ["#....#", "######", "######", ".####.", ".#..#."],
}
const THANKS: Array[Color] = [Color("e8dcc0"), Color("e6c9b4"), Color("d9e0c4"), Color("e9d9a0")]
const DROP_TIME: float = 0.55
const GHOST_LIFE: float = 28.0 ## seconds a fallen notice may still hang for a crow before the wind takes it
const BLOW_TIME: float = 1.4
const CARRY_TIME: float = 0.55
const TUG_TIME: float = 0.9
const READ_TIME: float = 2.0 ## seconds beside the board that count as reading it

var board: BoardManager
var structure: TownStructure
var unlit: bool = false
var source: BoardNotes ## the lit node (set on the unlit one)
var notes: Array[Dictionary] = [] ## what is drawn this frame (see `paint`), kept by the lit node
var beacon: Dictionary = {"unread": 0, "story": false} ## what the bud shows: unread notices, one of them a story notice
var _time: float = 0.0
var _ages: Dictionary = {} ## offer id -> seconds it has hung on this peer (new ones drop in)
var _slot_of: Dictionary = {} ## offer id -> place on the panel
var _ghosts: Array[Dictionary] = [] ## notices that ran out and still hang for a moment: {id, k, slot, t, phase "hang" | "tug" | "carry" | "blow", p, bird}
var _seen_first: bool = false
var _wet: float = 0.0
var _reading: float = 0.0
var _attention: float = 0.0
var _sounds: Array[Dictionary] = [] ## {t seconds to go, name, db}
var _last_ids: Dictionary = {}
var _poster: Dictionary = {} ## the wanted poster as drawn: {t species, nights, a, drop} (empty = none hangs)
var _done_seen: int = -1
var _swing: float = 0.0 ## the newest thank-you paper swings for a while


func _ready() -> void:
	z_index = 1 if unlit else 0
	if unlit:
		material = Unlit.material()
	elif board != null:
		board.changed.connect(queue_redraw)


func _exit_tree() -> void:
	if board != null and board.changed.is_connected(queue_redraw):
		board.changed.disconnect(queue_redraw)


func _process(delta: float) -> void:
	_time += delta
	var built: bool = structure != null and structure.progress >= TownManager.PROGRESS_FULL
	visible = built
	if unlit:
		if source != null:
			_time = source._time
			notes = source.notes
			beacon = source.beacon
		queue_redraw()
		return
	if not built or board == null:
		return
	_update_world(delta)
	_update_notes(delta)
	_update_reading(delta)
	_update_sounds(delta)
	queue_redraw()


func _draw() -> void:
	if unlit:
		if source != null:
			BoardNotes.paint(self, notes, _time, structure.is_flipped() if structure != null else false, true, TimeManager.night_amount(), beacon)
		return
	if board == null or structure == null:
		return
	BoardNotes.paint(self, notes, _time, structure.is_flipped(), false, TimeManager.night_amount(), beacon)


# ---------- state of the lit node ----------

## Rain on the paper (eased: wet within half a minute, dry again in under a minute).
func _update_world(delta: float) -> void:
	var target: float = 0.0
	if WeatherManager.current != null and structure != null:
		target = clampf(WeatherManager.current.exposure_at(structure.global_position) * 1.5, 0.0, 1.0)
	_wet = move_toward(_wet, target, delta / (25.0 if target > _wet else 40.0))


func _gust() -> float:
	return WorldWind.sample(structure.global_position).length() if structure != null and is_instance_valid(WorldWind.current) else 0.12


func _update_notes(delta: float) -> void:
	var peer: int = multiplayer.get_unique_id()
	var player: Player = board.town.local_player()
	var tracked: TrackedQuests = player.tracked if player != null else null
	var day: int = TimeManager.day
	var tod: float = TimeManager.time_of_day
	var gust: float = _gust()
	var present: Dictionary = {}
	var fresh: Array[int] = []
	var rush_new: bool = false
	for offer: Dictionary in board.hanging():
		var id: int = int(offer.id)
		present[id] = true
		if not _ages.has(id):
			_ages[id] = 99.0 if not _seen_first else 0.0 ## what already hangs when the board comes into view does not drop in
			if _seen_first:
				fresh.append(id)
				rush_new = rush_new or BoardRules.is_urgent(offer)
		else:
			_ages[id] = float(_ages[id]) + delta
		if not _slot_of.has(id) and not BoardRules.is_bounty(offer):
			_slot_of[id] = _free_slot()
	for id: Variant in _ages.keys():
		if not present.has(id):
			_ages.erase(id)
	for id: Variant in _last_ids.keys():
		if not present.has(id) and _seen_first:
			_make_ghost(int(id))
	for id: Variant in _slot_of.keys():
		if not present.has(id) and not _ghost_has(int(id)):
			_slot_of.erase(id)
	_last_ids = present
	_seen_first = true
	if not fresh.is_empty() and _near_local(300.0):
		_sounds.append({"t": 0.0, "name": "rustle_a", "db": -8.0}) ## a rustle as the papers come in, then a tack for each
		for i: int in fresh.size():
			_sounds.append({"t": 0.45 + 0.4 * float(i), "name": "tack", "db": -6.0})
		if rush_new:
			_sounds.append({"t": 0.4, "name": "bell", "db": -3.0})
	var out: Array[Dictionary] = []
	var unread: int = 0
	var story_unread: bool = false
	var wanted: bool = false
	_poster = {}
	for offer: Dictionary in board.hanging():
		var id: int = int(offer.id)
		var mine: bool = not board.entry_of(id, peer).is_empty()
		var age: float = float(_ages.get(id, 99.0))
		var is_new: bool = tracked != null and not mine and not tracked.is_seen(id)
		if is_new:
			unread += 1
			story_unread = story_unread or String(offer.k) == BoardRules.STORY
		if BoardRules.is_bounty(offer): ## the marked one's poster has its own place
			wanted = wanted or is_new
			_poster = {"t": String(offer.t), "nights": int(offer.get("bh", 1)), "a": 0.55 if mine else 1.0, "drop": 1.0 - clampf(age / DROP_TIME, 0.0, 1.0), "new": is_new, "id": id}
			continue
		out.append({
			"k": String(offer.k), "id": id, "slot": int(_slot_of.get(id, 0)), "a": 0.5 if mine else 1.0,
			"drop": 1.0 - clampf(age / DROP_TIME, 0.0, 1.0), "age": BoardRules.age(offer, day, tod),
			"wet": _wet, "gust": gust, "new": is_new, "u": BoardRules.is_urgent(offer),
		})
	_step_ghosts(delta, out, gust)
	notes = out
	var done: int = board.honor_done()
	if _done_seen >= 0 and done > _done_seen:
		_swing = 1.0
	_done_seen = done
	_swing = maxf(0.0, _swing - delta / 3.0)
	beacon = {"unread": unread, "story": story_unread, "wanted": wanted, "poster": _poster, "done": done, "swing": _swing}
	_attention = move_toward(_attention, clampf(float(unread) * 0.5, 0.0, 1.0), delta * 0.8)
	if structure != null:
		structure.attention = _attention


func _free_slot() -> int:
	var used: Dictionary = {}
	for slot: Variant in _slot_of.values():
		used[int(slot)] = true
	for i: int in SLOTS.size():
		if not used.has(i):
			return i
	return SLOTS.size() - 1


func _ghost_has(id: int) -> bool:
	for ghost: Dictionary in _ghosts:
		if int(ghost.id) == id:
			return true
	return false


## A notice left the board (ran out at sunrise): its paper stays up until a crow takes it or the wind does.
func _make_ghost(id: int) -> void:
	if _ghosts.size() >= 6 or not _slot_of.has(id):
		return
	var kind: String = BoardRules.FETCH
	var offer: Dictionary = board.offer_of(id)
	if not offer.is_empty():
		kind = String(offer.k)
	_ghosts.append({"id": id, "k": kind, "slot": int(_slot_of[id]), "t": 0.0, "phase": "hang", "p": 0.0})


func _step_ghosts(delta: float, out: Array[Dictionary], gust: float) -> void:
	for i: int in range(_ghosts.size() - 1, -1, -1):
		var ghost: Dictionary = _ghosts[i]
		ghost["t"] = float(ghost.t) + delta
		var phase: String = String(ghost.phase)
		var note: Dictionary = {"k": String(ghost.k), "id": int(ghost.id), "slot": int(ghost.slot), "a": 1.0, "drop": 0.0, "age": 1.0, "wet": _wet, "gust": gust, "new": false, "off": Vector2.ZERO}
		if phase == "hang":
			var bird: WildCorvid = _bird_on_roof()
			if bird != null:
				ghost["phase"] = "tug"
				ghost["p"] = 0.0
				_play("rustle_a", -4.0)
			elif float(ghost.t) > GHOST_LIFE:
				ghost["phase"] = "blow"
				ghost["p"] = 0.0
		elif phase == "tug":
			ghost["p"] = float(ghost.p) + delta / TUG_TIME
			note["tug"] = float(ghost.p)
			if float(ghost.p) >= 1.0:
				ghost["phase"] = "carry"
				ghost["p"] = 0.0
				_play("tear", -2.0)
		elif phase == "carry":
			ghost["p"] = float(ghost.p) + delta / CARRY_TIME
			var u: float = clampf(float(ghost.p), 0.0, 1.0)
			var from: Vector2 = SLOTS[int(ghost.slot)]
			var perch: Vector2 = _perch_local()
			note["off"] = (perch - from - Vector2(3, 0)) * u * u - Vector2(0, 4.0 * sin(u * PI))
			note["a"] = 1.0 - u * 0.5
			note["scrap"] = u
		elif phase == "blow":
			ghost["p"] = float(ghost.p) + delta / BLOW_TIME
			var v: float = clampf(float(ghost.p), 0.0, 1.0)
			var dir: Vector2 = WorldWind.sample(structure.global_position).normalized() if is_instance_valid(WorldWind.current) else Vector2.RIGHT
			note["off"] = Vector2(dir.x * 26.0 * v, 6.0 + 24.0 * v * v) + Vector2(sin(v * 9.0) * 2.0, 0.0)
			note["a"] = 1.0 - v
			if float(ghost.p) <= delta / BLOW_TIME * 1.5:
				_play("rustle_b", -6.0)
		_ghosts[i] = ghost
		if (phase == "carry" or phase == "blow") and float(ghost.p) >= 1.0:
			_ghosts.remove_at(i)
			continue
		out.append(note)


## A crow (or other bird) sitting on this board's roof perch, if there is one.
func _bird_on_roof() -> WildCorvid:
	if structure == null:
		return null
	var perch: Vector2 = structure.global_position + _perch_local()
	for node: Node in get_tree().get_nodes_in_group("corvids"):
		var bird: WildCorvid = node as WildCorvid
		if bird != null and bird.state != WildCorvid.State.FLY and bird.global_position.distance_to(perch) < 18.0:
			return bird
	return null


func _perch_local() -> Vector2:
	for child: Node in structure.get_children():
		var perch: RoofPerch = child as RoofPerch
		if perch != null:
			return perch.position - Vector2(0.0, perch.perch_height)
	return Vector2(-9.0, -31.0)


func _near_local(distance: float) -> bool:
	var player: Player = board.town.local_player() if board != null and board.town != null else null
	return player != null and structure != null and player.global_position.distance_to(structure.global_position) <= distance


## Standing by the board for a moment reads what hangs there: the bud calms down.
func _update_reading(delta: float) -> void:
	var player: Player = board.town.local_player() if board.town != null else null
	if player == null or player.tracked == null or structure == null:
		return
	if player.global_position.distance_to(structure.global_position) <= BoardRules.reach() * 0.8:
		_reading += delta
	else:
		_reading = 0.0
	if int(beacon.get("unread", 0)) > 0 and player.global_position.distance_to(structure.global_position) <= 90.0:
		get_tree().call_group("hint_card", "notify_board")
	if _reading >= READ_TIME:
		var ids: Array = []
		for offer: Dictionary in board.hanging():
			ids.append(int(offer.id))
		player.tracked.mark_seen(ids)


# ---------- sound ----------

func _update_sounds(delta: float) -> void:
	for i: int in range(_sounds.size() - 1, -1, -1):
		_sounds[i]["t"] = float(_sounds[i].t) - delta
		if float(_sounds[i].t) <= 0.0:
			_play(String(_sounds[i].name), float(_sounds[i].db))
			_sounds.remove_at(i)


func _play(sound: String, volume: float) -> void:
	var path: String = "res://assets/audio/board/%s.wav" % sound
	if not ResourceLoader.exists(path) or structure == null:
		return
	var player: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	player.stream = load(path) as AudioStream
	player.volume_db = volume
	player.max_distance = 260.0
	player.position = Vector2(0, -22)
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


# ---------- drawing ----------

## The places: stable per notice (`slot` in the note); notes without one take the places in order (story first, then by id). Public for the preview.
static func ordered(list: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = list.duplicate()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa: bool = String(a.k) == BoardRules.STORY
		var sb: bool = String(b.k) == BoardRules.STORY
		return (sa and not sb) or (sa == sb and int(a.id) < int(b.id)))
	for i: int in out.size():
		if not out[i].has("slot"):
			out[i]["slot"] = i
	return out


## Draws up to six notes: [{k kind, id, slot, a alpha, drop 1..0 how far above its place it still is, age 0..1, wet 0..1, gust, new, off (a ghost's way), tug, scrap}].
## `seals` false draws the paper (lit), true the seals, the unread glints and the bud on an unlit node. `beacon` {unread, story}.
static func paint(canvas: CanvasItem, list: Array[Dictionary], time: float, flipped: bool, seals: bool, night: float, beacon: Dictionary = {}) -> void:
	var sorted: Array[Dictionary] = ordered(list)
	for note: Dictionary in sorted:
		var slot: int = clampi(int(note.slot), 0, SLOTS.size() - 1)
		var id: int = int(note.id)
		var age: float = float(note.get("age", 0.0))
		var stage: int = BoardRules.age_stage(age)
		var gust: float = float(note.get("gust", 0.12))
		var tilt: int = (id + slot) % 3 - 1
		var rate: float = 1.3 + gust * 2.2
		var lift: float = sin(time * rate + float(id) * 2.1)
		if lift > 0.985 - minf(gust, 1.4) * 0.09: ## a gust lifts a corner for a moment, in a storm all the time
			tilt = -tilt if tilt != 0 else 1
		if gust > 1.2 and int(time * 6.0 + float(id)) % 2 == 0:
			tilt = -tilt if tilt != 0 else 1
		if stage >= 3:
			tilt += 1 if (id % 2 == 0) else -1 ## the last day: it hangs by one corner
		var off: Vector2 = note.get("off", Vector2.ZERO) as Vector2
		var tug: float = float(note.get("tug", 0.0))
		var shake: Vector2 = Vector2(roundf(sin(time * 40.0) * tug), roundf(-tug)) if tug > 0.0 else Vector2.ZERO
		var at: Vector2 = SLOTS[slot] - Vector2(0.0, roundf(float(note.get("drop", 0.0)) * 7.0)) + off.round() + shake
		if flipped:
			at.x = -at.x - float(W)
		var alpha: float = float(note.a) * (1.0 - float(note.get("drop", 0.0)) * 0.6)
		if seals:
			if String(note.k) == BoardRules.STORY:
				_seal(canvas, at, alpha, time, night, id)
			if bool(note.get("u", false)):
				_wax(canvas, at, alpha, time, id)
			if bool(note.get("new", false)):
				_glint(canvas, at, alpha, time, id)
		else:
			_paper(canvas, at, String(note.k), alpha, tilt, id, age, float(note.get("wet", 0.0)))
	_memory(canvas, flipped, time, night, seals, beacon)
	if seals:
		_bud(canvas, flipped, time, night, beacon)


static func _px(canvas: CanvasItem, x: float, y: float, color: Color, w: float = 1.0, h: float = 1.0) -> void:
	canvas.draw_rect(Rect2(roundf(x), roundf(y), w, h), color)


## A rectangle at board coordinates (x from the middle, y from the feet), mirrored when the piece is.
static func _mx(canvas: CanvasItem, flipped: bool, x: float, y: float, color: Color, w: float = 1.0, h: float = 1.0) -> void:
	canvas.draw_rect(Rect2(roundf(-x - w if flipped else x), roundf(y), w, h), color)


## The memory of the town: the wanted poster over the left post, the thank-you cord under the panel and what the board has grown (milestones).
static func _memory(canvas: CanvasItem, flipped: bool, time: float, night: float, seals: bool, beacon: Dictionary) -> void:
	var done: int = int(beacon.get("done", 0))
	var level: int = BoardRules.milestones_reached(done)
	if level >= 1:
		_lantern(canvas, flipped, time, night, seals)
	if not seals:
		if level >= 2:
			_shingles(canvas, flipped)
		if level >= 3:
			_shield(canvas, flipped)
		_cord(canvas, flipped, done, float(beacon.get("swing", 0.0)), time)
	var poster: Dictionary = beacon.get("poster", {}) as Dictionary
	if not poster.is_empty():
		_wanted(canvas, flipped, poster, time, night, seals)


## The wanted poster of a marked creature: bone paper over the left post, a small ink sketch of its kind, a line for the name, a tally mark for every night it survived, a magenta seal.
static func _wanted(canvas: CanvasItem, flipped: bool, poster: Dictionary, time: float, night: float, seals: bool) -> void:
	var alpha: float = float(poster.a)
	var drop: float = float(poster.get("drop", 0.0))
	var at: Vector2 = POSTER - Vector2(0.0, roundf(drop * 8.0))
	alpha *= 1.0 - drop * 0.6
	var sway: float = roundf(sin(time * 1.3 + float(int(poster.get("id", 0)))) * 0.6)
	if seals:
		var pulse: float = 0.6 + 0.4 * sin(time * 2.6)
		var centre: Vector2 = at + Vector2(float(POSTER_W) - 1.0, float(POSTER_H) - 2.0)
		_mx(canvas, flipped, centre.x - 1.0, centre.y - 1.0, Color(MARK, 0.25 * alpha * pulse), 3.0, 3.0)
		_mx(canvas, flipped, centre.x, centre.y, Color(MARK, alpha * (0.55 + 0.45 * night)), 1.0, 1.0)
		return
	var paper: Color = Color("d8c9a8")
	var edge: Color = paper.darkened(0.4)
	_mx(canvas, flipped, at.x + 1.0, at.y + 1.0, Color(0, 0, 0, 0.35 * alpha), float(POSTER_W), float(POSTER_H))
	for row: int in POSTER_H:
		var width: float = float(POSTER_W) - (1.0 if (row == 0 or row == POSTER_H - 1) else 0.0)
		var shade: Color = paper.lightened(0.1) if row == 0 else (edge if row == POSTER_H - 1 else paper)
		_mx(canvas, flipped, at.x + sway * (1.0 if row > POSTER_H - 4 else 0.0), at.y + float(row), Color(shade, alpha), width, 1.0)
	_mx(canvas, flipped, at.x, at.y, Color(edge, alpha), 1.0, float(POSTER_H) - 1.0)
	_mx(canvas, flipped, at.x + 1.0, at.y + 2.0, Color(INK, 0.9 * alpha), 6.0, 1.0) ## the heading
	_mx(canvas, flipped, at.x + 2.0, at.y + 4.0, Color(INK, 0.55 * alpha), 4.0, 1.0)
	var rows: Array = SKETCH.get(String(poster.get("t", "")), SKETCH.void_crusher) as Array
	for y: int in rows.size():
		var line: String = String(rows[y])
		for x: int in line.length():
			if line[x] == "#":
				_mx(canvas, flipped, at.x + 1.0 + float(x), at.y + 6.0 + float(y), Color(INK, 0.95 * alpha))
	for n: int in clampi(int(poster.get("nights", 1)), 1, 3): ## a red tally for every night it came through
		_mx(canvas, flipped, at.x + 1.0 + float(n) * 2.0, at.y + 11.0, Color(RED, alpha), 1.0, 2.0)
	_mx(canvas, flipped, at.x + 1.0, at.y - 1.0, Color(PIN, alpha))
	_mx(canvas, flipped, at.x + float(POSTER_W) - 2.0, at.y - 1.0, Color(PIN, alpha))


## The thank-you cord: a sagging thread under the panel, a small paper hangs from it for every finished notice of the town (the last twelve); the newest still swings.
static func _cord(canvas: CanvasItem, flipped: bool, done: int, swing: float, time: float) -> void:
	if done <= 0:
		return
	var count: int = mini(done, int((BoardRules.honor_cfg()).get("dankband", 12)))
	for i: int in 28:
		var x: float = -14.0 + float(i)
		var sag: float = roundf(sin(float(i) / 27.0 * PI) * 1.4)
		_mx(canvas, flipped, x, -14.0 + sag, Color(INK.lightened(0.15), 0.9))
	for k: int in count:
		var u: float = (float(k) + 0.5) / float(maxi(count, 1))
		var x: float = -13.0 + u * 26.0
		var sag: float = roundf(sin(u * PI) * 1.4)
		var newest: bool = k == count - 1
		var sway: float = roundf(sin(time * 3.0) * 1.0 * swing) if newest else 0.0
		var paper: Color = THANKS[(done - count + k) % THANKS.size()]
		_mx(canvas, flipped, x + sway, -13.0 + sag, Color(paper.darkened(0.1), 0.95), 2.0, 1.0)
		_mx(canvas, flipped, x + sway, -12.0 + sag, paper, 2.0, 2.0)
		_mx(canvas, flipped, x + sway, -10.0 + sag, Color(paper.darkened(0.3), 0.9), 1.0, 1.0)


## 25 notices: a small lantern on the left post (its light is drawn in the unlit pass).
static func _lantern(canvas: CanvasItem, flipped: bool, time: float, night: float, seals: bool) -> void:
	var x: float = -19.0
	var y: float = -39.0
	var swing: float = roundf(sin(time * 1.4) * 0.5)
	if seals:
		var glow: float = 0.45 + 0.4 * night + 0.1 * sin(time * 7.0)
		_mx(canvas, flipped, x - 1.0 + swing, y - 1.0, Color("ffc86a", 0.2 * glow), 5.0, 6.0)
		_mx(canvas, flipped, x + swing, y, Color("ffd88a", clampf(0.7 + 0.3 * glow, 0.0, 1.0)), 3.0, 3.0)
		return
	_mx(canvas, flipped, x + 1.0, y - 3.0, INK, 1.0, 3.0) ## the hook
	_mx(canvas, flipped, x - 0.0 + swing, y - 1.0, INK, 3.0, 1.0)
	_mx(canvas, flipped, x + swing, y + 3.0, INK, 3.0, 1.0)


## 50 notices: a second pair of shingles over the posts.
static func _shingles(canvas: CanvasItem, flipped: bool) -> void:
	var dark: Color = Color("4a3a5c")
	var light: Color = Color("6a5a7c")
	for side: float in [-23.0, 17.0]:
		_mx(canvas, flipped, side, -47.0, dark, 7.0, 2.0)
		_mx(canvas, flipped, side + 1.0, -48.0, light, 5.0, 1.0)
		_mx(canvas, flipped, side + 1.0, -45.0, Color(0, 0, 0, 0.3), 5.0, 1.0)


## 100 notices: an honour shield on the top beam, the town's mark in gold.
static func _shield(canvas: CanvasItem, flipped: bool) -> void:
	_mx(canvas, flipped, -3.0, -43.0, INK, 7.0, 8.0)
	_mx(canvas, flipped, -2.0, -42.0, Color("6a5a7c"), 5.0, 6.0)
	_mx(canvas, flipped, 0.0, -41.0, GOLD, 1.0, 1.0) ## a small diamond: the town's mark
	_mx(canvas, flipped, -1.0, -40.0, GOLD, 3.0, 1.0)
	_mx(canvas, flipped, 0.0, -39.0, GOLD, 1.0, 1.0)
	_mx(canvas, flipped, -1.0, -36.0, INK, 3.0, 1.0)


static func _paper(canvas: CanvasItem, at: Vector2, kind: String, alpha: float, tilt: int, id: int, age: float, wet: float) -> void:
	var paper: Color = STORY_PAPER if kind == BoardRules.STORY else (KILL_PAPER if kind == BoardRules.KILL else FETCH_PAPER)
	var yellow: float = float((BoardRules.config().get("age", {}) as Dictionary).get("yellow", 0.4))
	if kind != BoardRules.STORY:
		paper = paper.lerp(OLD_PAPER, yellow * smoothstep(0.25, 1.0, age))
	paper = paper.lerp(WET_PAPER, 0.45 * wet)
	var edge: Color = paper.darkened(0.35)
	var stage: int = BoardRules.age_stage(age)
	var droop: bool = wet > 0.3 or stage >= 1
	_px(canvas, at.x + 1.0, at.y + 1.0, Color(0, 0, 0, 0.35 * alpha), W, H) ## the shadow on the planks
	for row: int in H:
		var shift: float = float(tilt) * (1.0 if row >= H - 2 else 0.0)
		var low: float = 1.0 if (droop and row == H - 1 and (id + row) % 2 == 0) else 0.0 ## the lower edge sags or waves
		var shade: Color = paper.lightened(0.12) if row == 0 else (edge if row == H - 1 else paper)
		_px(canvas, at.x + shift, at.y + float(row) + (low if wet > 0.3 else 0.0), Color(shade, alpha), W - (1.0 if (low > 0.0 and wet <= 0.3) else 0.0), 1.0)
	_px(canvas, at.x, at.y, Color(edge, alpha), 1.0, float(H) - 1.0) ## left edge in shade
	var ink: float = 0.75 * (1.0 - 0.5 * smoothstep(0.6, 1.0, age)) ## the ink fades with the days
	for line: int in 2: ## writing: two short dark strokes with air between, each paper its own
		var row: float = 2.0 + float(line) * 2.0
		if row >= float(H) - 1.0:
			break
		var length: float = float(3 + (id * 5 + line * 3) % 3)
		_px(canvas, at.x + 1.0, at.y + row, Color(INK, ink * alpha), length, 1.0)
		if wet > 0.8: ## the ink runs
			_px(canvas, at.x + 1.0 + float((id + line) % 3), at.y + row + 1.0, Color(INK, 0.35 * alpha), 1.0, 1.0)
	if kind == BoardRules.KILL: ## a red mark: this one is a hunt
		_px(canvas, at.x + float(W) - 3.0, at.y + float(H) - 3.0, Color(RED, alpha), 2.0, 2.0)
	if stage >= 2: ## a dog-ear in the lower right corner
		var corner: Vector2 = Vector2(at.x + float(W) - 2.0, at.y + float(H) - 2.0)
		_px(canvas, corner.x, corner.y, Color(paper.lightened(0.18), alpha), 1.0, 1.0)
		_px(canvas, corner.x + 1.0, corner.y, Color(edge, alpha), 1.0, 1.0)
		_px(canvas, corner.x, corner.y + 1.0, Color(edge, alpha), 1.0, 1.0)
		_px(canvas, corner.x + 1.0, corner.y + 1.0, Color(0, 0, 0, 0.5 * alpha), 1.0, 1.0)
	_px(canvas, at.x + 3.0, at.y, Color(PIN, alpha)) ## the pin
	_px(canvas, at.x + 3.0, at.y - 1.0, Color(PIN.lightened(0.4), alpha * 0.8))


static func _seal(canvas: CanvasItem, at: Vector2, alpha: float, time: float, night: float, id: int) -> void:
	var pulse: float = 0.75 + 0.25 * sin(time * 2.4 + float(id))
	var strength: float = (0.55 + 0.45 * night) * alpha
	var centre: Vector2 = at + Vector2(float(W) / 2.0 - 0.5, float(H) - 2.0)
	_px(canvas, centre.x - 1.0, centre.y - 1.0, Color(SEAL, 0.18 * strength * pulse), 3.0, 3.0) ## a faint halo
	_px(canvas, centre.x, centre.y, Color(SEAL, strength))
	_px(canvas, centre.x, centre.y - 1.0, Color(SEAL, 0.45 * strength * pulse))


## The red wax of a rush notice: a round blob with a bright edge that throbs quicker than the story seal and is never dimmed by day.
static func _wax(canvas: CanvasItem, at: Vector2, alpha: float, time: float, id: int) -> void:
	var pulse: float = 0.7 + 0.3 * sin(time * 6.0 + float(id))
	var centre: Vector2 = at + Vector2(float(W) / 2.0 - 1.0, float(H) - 3.0)
	_px(canvas, centre.x, centre.y, Color(WAX.darkened(0.25), alpha), 3.0, 3.0)
	_px(canvas, centre.x + 1.0, centre.y - 1.0, Color(WAX.darkened(0.25), alpha), 1.0, 1.0)
	_px(canvas, centre.x, centre.y, Color(WAX, alpha * pulse), 2.0, 2.0)
	_px(canvas, centre.x, centre.y, Color(Color.WHITE, 0.55 * alpha * pulse), 1.0, 1.0)
	_px(canvas, centre.x - 1.0, centre.y - 1.0, Color(WAX, 0.22 * alpha * pulse), 5.0, 5.0)


## A tiny blinking light in the corner of a paper nobody has read yet.
static func _glint(canvas: CanvasItem, at: Vector2, alpha: float, time: float, id: int) -> void:
	var blink: float = 0.5 + 0.5 * sin(time * 5.0 + float(id) * 1.7)
	_px(canvas, at.x + float(W) - 1.0, at.y, Color(Color.WHITE, (0.35 + 0.6 * blink) * alpha))


## The bud on the right post: it breathes slowly; with unread notices it pulses fast, shines further and sheds a mote now and then (gold when one is a story notice).
static func _bud(canvas: CanvasItem, flipped: bool, time: float, night: float, beacon: Dictionary) -> void:
	var unread: int = int(beacon.get("unread", 0))
	var tone: Color = GOLD if bool(beacon.get("story", false)) else SEAL
	var x: float = BUD.x
	if flipped:
		x = -BUD.x - 2.0
	var strong: float = maxf(0.55 + 0.45 * night, 0.8 if unread > 0 else 0.0)
	var level: float
	if unread > 0:
		level = 0.65 + 0.35 * sin(time * 6.0)
	else:
		level = 0.6 + 0.18 * sin(time * 1.1)
	var halo: float = (0.22 + 0.2 * minf(float(unread), 3.0)) * level * strong
	_px(canvas, x - 1.0, BUD.y - 1.0, Color(tone, halo), 4.0, 4.0)
	if unread > 0:
		_px(canvas, x - 2.0, BUD.y, Color(tone, halo * 0.5), 6.0, 2.0)
		_px(canvas, x, BUD.y - 2.0, Color(tone, halo * 0.5), 2.0, 6.0)
	_px(canvas, x, BUD.y, Color(tone, clampf(level * strong + 0.2, 0.0, 1.0)), 2.0, 2.0)
	_px(canvas, x, BUD.y, Color(Color.WHITE, 0.5 * level * strong), 1.0, 1.0)
	if unread > 0: ## a mote rises from the bud
		for k: int in mini(unread, 2):
			var u: float = fposmod(time * 0.8 + float(k) * 0.5, 1.0)
			_px(canvas, x + 0.5 + sin(u * 6.0 + float(k)) * 1.5, BUD.y - 2.0 - u * 9.0, Color(tone, (1.0 - u) * 0.8 * strong), 1.0, 1.0)
