class_name Signpost
extends Interactable
## The standard signpost (art: tools/art_signpost.py). E reads it: Ellie speaks the boards (a dialogue from data/dialogue.json) and the quest flag
## named in the entry is set when the conversation ends. Placed from data/ground.json "signposts": {tile, variant, dialogue, flag}.
const ART: Texture2D = preload("res://assets/props/signpost.png")
const GLOW: Texture2D = preload("res://assets/props/signpost_glow.png") ## only the emissive pixels, drawn unlit
const FRAME: Vector2i = Vector2i(56, 64)

var variant: int = 0
var dialogue_id: String = ""
var flag: String = ""
var _glow: Sprite2D
var _time: float = 0.0


func _ready() -> void:
	for tex: Texture2D in [ART, GLOW]:
		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture = tex
		sprite.hframes = tex.get_width() / FRAME.x
		sprite.frame = variant
		sprite.offset = Vector2(0, -(58 - FRAME.y / 2))
		if tex == GLOW:
			sprite.material = Unlit.material()
			_glow = sprite
		add_child(sprite)
	var light: NightLight = NightLight.new()
	light.position = Vector2(0, -10)
	light.radius = 24
	light.base_energy = 0.4
	light.glow_color = Color("78f4e6")
	add_child(light)
	var body: StaticBody2D = StaticBody2D.new() ## the post and its heap of stones
	var shape: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = Vector2(10, 5)
	shape.shape = box
	shape.position = Vector2(0, -2)
	body.add_child(shape)
	add_child(body)


func _process(delta: float) -> void:
	_time += delta
	_glow.modulate.a = lerpf(0.45, 1.0, TimeManager.night_amount()) * (0.8 + 0.2 * sin(_time * 1.3 + position.x))


func prompt() -> String:
	return "LESEN"


func reach_distance(from: Vector2) -> float:
	return from.distance_to(global_position) - 8.0


func prompt_position() -> Vector2:
	return Vector2(0, -52)


func interact(player: Player) -> void:
	var box: DialogueBox = get_tree().get_first_node_in_group("dialogue") as DialogueBox
	if box == null or box.is_active():
		return
	if flag != "" and player.quests != null:
		box.finished.connect(func() -> void: player.quests.set_flag(flag), CONNECT_ONE_SHOT)
	box.start(dialogue_id)
