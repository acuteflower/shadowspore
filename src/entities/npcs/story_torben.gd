class_name StoryTorben
extends Node2D
## Torben at his overworld iron outcrop (quest `torben_smithy`): hammers iron rock, fights off
## ambushers alongside Ellie with sledge/swat blows, and talks before moving into town.

signal struck
signal clip_finished

const SECTORS: int = 8
const ACTOR_ID: String = "story_torben"

var actor_id: String = ACTOR_ID
var camp: Node2D = null
var can_talk: bool = false
var busy: bool = false
var invulnerable: bool = true

var _rig: Dictionary = {}
var _sprite: Sprite2D = null
var _glow: Sprite2D = null
var _bubble: SettlerBubble = null
var _clip: String = "idle"
var _clip_time: float = 0.0
var _last_frame: int = -1
var _sector: int = 4
var _loop: bool = true
var _emitted_done: bool = false


func _ready() -> void:
	add_to_group("quest_actors")
	add_to_group("story_torben")
	add_to_group("interactable")
	_rig = DataRegistry.table("torben_rig")
	var sheet: String = "res://assets/characters/torben.png"
	var glow_path: String = "res://assets/characters/torben_glow.png"
	if not _rig.is_empty() and ResourceLoader.exists(sheet):
		var frame: Array = _rig.get("frame", [88, 104]) as Array
		var feet: Array = _rig.get("feet", [44, 88]) as Array
		var off: Vector2 = Vector2(0.0, float(frame[1]) * 0.5 - float(feet[1]))
		_sprite = Sprite2D.new()
		_sprite.texture = load(sheet) as Texture2D
		_sprite.hframes = int(_rig.get("frames", 100))
		_sprite.vframes = SECTORS
		_sprite.offset = off
		add_child(_sprite)
		if ResourceLoader.exists(glow_path):
			_glow = Sprite2D.new()
			_glow.texture = load(glow_path) as Texture2D
			_glow.hframes = _sprite.hframes
			_glow.vframes = SECTORS
			_glow.offset = off
			_glow.material = Unlit.material()
			add_child(_glow)
	_show()


func actor_position(who: String) -> Vector2:
	return global_position if who == ACTOR_ID and visible else Vector2.INF


static func sector_of(direction: Vector2) -> int:
	return posmod(roundi(direction.angle() / (PI / 4.0)), SECTORS)


func say(text: String, seconds: float = 2.4) -> void:
	if text == "" or not visible:
		return
	if _bubble == null:
		_bubble = SettlerBubble.new()
		_bubble.position = prompt_position() + Vector2(0.0, 2.0)
		add_child(_bubble)
	_bubble.show_text(text, seconds)


func play(clip: String, toward: Vector2 = Vector2.ZERO) -> void:
	if toward != Vector2.ZERO:
		_sector = sector_of(toward)
	var clips: Dictionary = _rig.get("clips", {}) as Dictionary
	var next_clip: String = clip if clips.has(clip) else "idle"
	if next_clip != _clip or not _loop:
		_clip = next_clip
		_clip_time = 0.0
		_last_frame = -1
		_emitted_done = false
		_loop = bool((clips.get(_clip, {}) as Dictionary).get("loop", true))
	_show()


func _process(delta: float) -> void:
	_clip_time += delta
	_show()


func _show() -> void:
	if _sprite == null:
		return
	var clips: Dictionary = _rig.get("clips", {}) as Dictionary
	var clip: Dictionary = clips.get(_clip, clips.get("idle", {})) as Dictionary
	var count: int = maxi(int(clip.get("count", 1)), 1)
	var raw_step: int = int(_clip_time * float(clip.get("fps", 7)))
	var frame: int = raw_step % count if _loop else mini(raw_step, count - 1)
	var idx: int = _sector * int(_rig.get("frames", 100)) + int(clip.get("start", 0)) + frame
	_sprite.frame = idx
	if _glow != null:
		_glow.frame = idx
	if (_clip == "work" or _clip == "sledge") and frame == int(clip.get("strike", 4)) and frame != _last_frame:
		struck.emit()
	if not _loop and frame == count - 1 and not _emitted_done:
		_emitted_done = true
		clip_finished.emit()
	_last_frame = frame


func _draw() -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in 25:
		pts.append(Vector2.from_angle(TAU * i / 24.0) * Vector2(12.0, 3.5))
	draw_colored_polygon(pts, Color(0, 0, 0, 0.28))
	if _sprite == null:
		draw_rect(Rect2(-6, -26, 12, 18), Color("3c342e"))
		draw_circle(Vector2(0, -32), 5.5, Color("c8946a"))


func prompt() -> String:
	return "ANSPRECHEN" if visible and can_talk and not busy else ""


func reach_distance(from: Vector2) -> float:
	return from.distance_to(global_position) - 10.0


func prompt_position() -> Vector2:
	return Vector2(0.0, -float(_rig.get("height", 55)) - 8.0)


func interact(player: Player) -> void:
	if can_talk and not busy and camp != null and camp.has_method("meet_torben"):
		camp.call("meet_torben", player)
