class_name StoryGustav
extends Node2D
## Gustav on his way to the town (quest `gustav_rescue`): stands at the wagon, follows Ellie on the escort and walks up to the light. Not a `Settler` (he is no resident yet) and not a
## network object (story scenes are solo / host only): a figure with the clips of data/gustav_rig.json (idle, walk, run, work). The scenes steer him (`play`, `global_position`); the
## `work` clip doubles as the hammer swing of the escort (signal `struck` on its strike frame). Group `quest_actors`: `actor_position("gustav_escort")` is where he stands.
## PLACEHOLDER clips: the art agent still owes `peek`, `stumble_out`, `duck`, `pant`, `carry_chest` (docs/gustav_quest_konzept.md section 9); until then idle / walk / work stand in.

signal struck ## the hammer frame of the `work` clip

const SECTORS: int = 8
const ACTOR_ID: String = "gustav_escort"

var _rig: Dictionary = {}
var _sprite: Sprite2D
var _clip: String = "idle"
var _clip_time: float = 0.0
var _last_frame: int = -1
var _sector: int = 2
var invulnerable: bool = true


func _ready() -> void:
	add_to_group("quest_actors")
	add_to_group("story_gustav")
	_rig = DataRegistry.table("gustav_rig")
	var sheet: String = "res://assets/characters/gustav.png"
	if not _rig.is_empty() and ResourceLoader.exists(sheet):
		_sprite = Sprite2D.new()
		_sprite.texture = load(sheet) as Texture2D
		_sprite.hframes = int(_rig.get("frames", 1))
		_sprite.vframes = SECTORS
		var frame: Array = _rig.get("frame", [72, 76]) as Array
		var feet: Array = _rig.get("feet", [36, 62]) as Array
		_sprite.offset = Vector2(0.0, float(frame[1]) * 0.5 - float(feet[1]))
		add_child(_sprite)
	_show()


func actor_position(id: String) -> Vector2:
	return global_position if id == ACTOR_ID and visible else Vector2.INF


static func sector_of(direction: Vector2) -> int:
	return posmod(roundi(direction.angle() / (PI / 4.0)), SECTORS)


## Plays `clip` facing `toward` (keeps the stride phase when only the direction changes).
func play(clip: String, toward: Vector2 = Vector2.ZERO) -> void:
	if toward != Vector2.ZERO:
		_sector = sector_of(toward)
	if clip != _clip:
		_clip = clip if (_rig.get("clips", {}) as Dictionary).has(clip) else "idle"
		_clip_time = 0.0
		_last_frame = -1
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
	var frame: int = int(_clip_time * float(clip.get("fps", 8))) % count
	_sprite.frame = _sector * int(_rig.get("frames", 1)) + int(clip.get("start", 0)) + frame
	if _clip == "work" and frame == int(clip.get("strike", 3)) and frame != _last_frame:
		struck.emit()
	_last_frame = frame


func _draw() -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in 25:
		pts.append(Vector2.from_angle(TAU * i / 24.0) * Vector2(10.0, 3.0))
	draw_colored_polygon(pts, Color(0, 0, 0, 0.26))
	if _sprite == null: ## no art on disk: the same plain stand-in as an unfinished settler
		draw_rect(Rect2(-5, -24, 10, 16), Color("5a4a6e"))
		draw_rect(Rect2(-4, -17, 8, 10), Color("6b4a32"))
		draw_rect(Rect2(-5, -8, 4, 8), Color("2a2438"))
		draw_rect(Rect2(1, -8, 4, 8), Color("2a2438"))
		draw_circle(Vector2(0, -29), 5.0, Color("c8946a"))
