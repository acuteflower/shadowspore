class_name MineNote
extends Interactable
## A scrap of someone's last days in the mine, lying on the floor or a table (E reads it). The text is picked by the note's place from data/mine_notes.json
## (the zone's list), shown in the speech box; nothing pauses. All texts are placeholders.

var _text: String = ""
var _speaker: String = ""
var _sprite: Sprite2D


func setup(zone_id: String, seed_value: int, texture_path: String, feet: int) -> void:
	var texts: Array = (DataRegistry.table("mine_notes").get(zone_id, []) as Array)
	if not texts.is_empty():
		var entry: Dictionary = texts[absi(seed_value) % texts.size()] as Dictionary
		_speaker = String(entry.get("speaker", "NOTIZ"))
		_text = String(entry.text)
	var texture: Texture2D = load(texture_path) as Texture2D
	_sprite = Sprite2D.new()
	_sprite.texture = texture
	_sprite.offset = Vector2(0.0, texture.get_height() / 2.0 - feet)
	add_child(_sprite)
	var glow_path: String = texture_path.replace(".png", "_glow.png")
	if ResourceLoader.exists(glow_path):
		var glow: Sprite2D = Sprite2D.new()
		glow.texture = load(glow_path) as Texture2D
		glow.offset = _sprite.offset
		glow.material = Unlit.material()
		_sprite.add_child(glow)


func prompt() -> String:
	return "LESEN" if _text != "" else ""


func reach_distance(from: Vector2) -> float:
	return from.distance_to(global_position) - 6.0


func prompt_position() -> Vector2:
	return Vector2(0, -16)


func interact(_player: Player) -> void:
	var box: Node = get_tree().get_first_node_in_group("speech_box")
	if box != null and _text != "":
		box.call("speak", _speaker, _text)
