class_name HudToast
extends Control
## Non-blocking top-center notification pill in Nachtlichtung pixel style.
## Displays `EventBus.toast_requested` messages and live peer join/leave events.

const HOLD_SECONDS: float = 2.8
const FADE_IN_SECONDS: float = 0.14
const FADE_OUT_SECONDS: float = 0.36
const MAX_QUEUE: int = 4

const COL_BG: Color = Color(0.055, 0.047, 0.095, 0.90)
const COL_BORDER: Color = Color(0.24, 0.21, 0.34, 0.95)
const COL_TEXT: Color = Color(0.92, 0.90, 0.98, 1.0)
const COL_OUTLINE: Color = Color(0.03, 0.02, 0.06, 0.95)
const COL_TEAL: Color = Color(0.41, 0.91, 0.78, 1.0)
const COL_AMBER: Color = Color(0.94, 0.72, 0.31, 1.0)
const COL_CORAL: Color = Color(0.88, 0.42, 0.46, 1.0)
const COL_LAVENDER: Color = Color(0.75, 0.69, 0.92, 1.0)

var _queue: Array[Dictionary] = []
var _active: Dictionary = {}
var _elapsed: float = 0.0
var _known_peers: Dictionary = {} ## peer_id -> display_name
var _was_mp: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 40
	visible = false
	if EventBus != null and not EventBus.toast_requested.is_connected(_on_toast_requested):
		EventBus.toast_requested.connect(_on_toast_requested)
	if NetworkManager != null:
		if not NetworkManager.session_changed.is_connected(_sync_roster):
			NetworkManager.session_changed.connect(_sync_roster)
		if not NetworkManager.peer_left.is_connected(_on_peer_left):
			NetworkManager.peer_left.connect(_on_peer_left)
	_sync_roster(true)


func _process(delta: float) -> void:
	if _active.is_empty():
		if _queue.is_empty():
			visible = false
			return
		_active = _queue.pop_front() as Dictionary
		_elapsed = 0.0
		visible = true
	_elapsed += delta
	var total: float = FADE_IN_SECONDS + HOLD_SECONDS + FADE_OUT_SECONDS
	if _elapsed >= total:
		_active.clear()
		if _queue.is_empty():
			visible = false
			return
		_active = _queue.pop_front() as Dictionary
		_elapsed = 0.0
	queue_redraw()


func _draw() -> void:
	if _active.is_empty():
		return
	var text: String = String(_active.get("text", ""))
	if text.is_empty():
		return
	var accent: Color = _active.get("accent", COL_LAVENDER) as Color
	var total: float = FADE_IN_SECONDS + HOLD_SECONDS + FADE_OUT_SECONDS
	var alpha: float = 1.0
	if _elapsed < FADE_IN_SECONDS:
		alpha = clampf(_elapsed / FADE_IN_SECONDS, 0.0, 1.0)
	elif _elapsed > FADE_IN_SECONDS + HOLD_SECONDS:
		alpha = clampf((total - _elapsed) / FADE_OUT_SECONDS, 0.0, 1.0)

	var vw: float = size.x
	if vw <= 10.0:
		vw = 640.0
	var tw: int = PixelText.width(text)
	var pad_x: int = 8
	var w: int = mini(tw + pad_x * 2 + 4, int(vw) - 40)
	var h: int = 16
	var x: int = int(floor((vw - float(w)) * 0.5))
	var slide: int = int(round((1.0 - alpha) * -4.0))
	var y: int = 14 + slide

	var bg: Color = Color(COL_BG.r, COL_BG.g, COL_BG.b, COL_BG.a * alpha)
	var border: Color = Color(COL_BORDER.r, COL_BORDER.g, COL_BORDER.b, COL_BORDER.a * alpha)
	var stripe: Color = Color(accent.r, accent.g, accent.b, alpha)
	var ink: Color = Color(COL_TEXT.r, COL_TEXT.g, COL_TEXT.b, alpha)
	var outline: Color = Color(COL_OUTLINE.r, COL_OUTLINE.g, COL_OUTLINE.b, COL_OUTLINE.a * alpha)

	var rect: Rect2 = Rect2(Vector2(x, y), Vector2(w, h))
	draw_rect(rect, bg, true)
	draw_rect(rect, border, false, 1.0)
	draw_rect(Rect2(Vector2(x, y), Vector2(2, h)), stripe, true)
	var max_chars: int = maxi((w - pad_x * 2) / PixelText.ADVANCE, 4)
	var shown: String = text if text.length() <= max_chars else (text.substr(0, max_chars - 2) + "..")
	PixelText.draw(self, shown, Vector2i(x + pad_x + 1, y + 4), ink, outline)


func push_toast(message: String, accent: Color = Color(-1, -1, -1, 1)) -> void:
	var clean: String = message.strip_edges()
	if clean.is_empty():
		return
	var col: Color = accent if accent.r >= 0.0 else _accent_for(clean)
	if not _active.is_empty() and String(_active.get("text", "")) == clean:
		_elapsed = minf(_elapsed, FADE_IN_SECONDS)
		queue_redraw()
		return
	for item: Dictionary in _queue:
		if String(item.get("text", "")) == clean:
			return
	if _queue.size() >= MAX_QUEUE:
		_queue.pop_front()
	_queue.append({"text": clean, "accent": col})
	visible = true
	queue_redraw()


func _on_toast_requested(message: String) -> void:
	push_toast(message)


func _sync_roster(initial: bool = false) -> void:
	if NetworkManager == null:
		return
	var in_mp: bool = NetworkManager.is_multiplayer_session()
	if not in_mp:
		_known_peers.clear()
		_was_mp = false
		return
	var seed_only: bool = initial or not _was_mp
	_was_mp = true
	var my_id: int = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	var roster: Array[Dictionary] = NetworkManager.roster()
	for entry: Dictionary in roster:
		var pid: int = int(entry.get("id", 0))
		if pid <= 0 or pid == my_id:
			continue
		var pname: String = String(entry.get("name", "")).strip_edges()
		if pname.is_empty() or pname.begins_with("Spieler ") or pname.begins_with("Player "):
			continue
		if not _known_peers.has(pid):
			_known_peers[pid] = pname
			if not seed_only:
				push_toast("%s BEIGETRETEN" % pname.to_upper(), COL_TEAL)


func _on_peer_left(id: int) -> void:
	var prev_name: String = String(_known_peers.get(id, ""))
	_known_peers.erase(id)
	if not prev_name.is_empty() and NetworkManager != null and NetworkManager.is_multiplayer_session():
		push_toast("%s HAT WELT VERLASSEN" % prev_name.to_upper(), COL_CORAL)


static func _accent_for(text: String) -> Color:
	var low: String = text.to_lower()
	if low.contains("anfrage") or low.contains("einladung") or low.contains("möchte") or low.contains("request"):
		return COL_AMBER
	if low.contains("verlassen") or low.contains("getrennt") or low.contains("abgelehnt") or low.contains("gekickt") or low.contains("geschlossen") or low.contains("fehler"):
		return COL_CORAL
	if low.contains("beigetreten") or low.contains("angenommen") or low.contains("akzeptiert") or low.contains("kopiert") or low.contains("synchron"):
		return COL_TEAL
	return COL_LAVENDER
