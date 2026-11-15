class_name WildlifeShelter
extends Node2D
## Fixed den entrance, spawned by the host and reserved with its resident family's home.

const TEXTURES: Dictionary = {
	"badger_den": "res://assets/wildlife/badger_den.png",
	"desert_burrow": "res://assets/wildlife/desert_burrow.png",
}

static var _tex_cache: Dictionary = {}

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
	var cached: Variant = _tex_cache.get(path)
	if cached is Texture2D:
		sprite.texture = cached as Texture2D
		return
	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path) as Texture2D
		if tex != null:
			_tex_cache[path] = tex
		sprite.texture = tex
