class_name WildlifeShelter
extends Node2D
## Fixed den entrance, spawned by the host and reserved with its resident family's home.

const TEXTURES: Dictionary = {
	"badger_den": "res://assets/wildlife/badger_den.png",
	"desert_burrow": "res://assets/wildlife/desert_burrow.png",
}

@export var shelter_kind: String = "badger_den":
	set(value):
		shelter_kind = value
		if is_node_ready():
			_apply_texture()


func _ready() -> void:
	_apply_texture()


func _apply_texture() -> void:
	var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null:
		return
	var path: String = String(TEXTURES.get(shelter_kind, TEXTURES["badger_den"]))
	if ResourceLoader.exists(path):
		sprite.texture = load(path) as Texture2D
