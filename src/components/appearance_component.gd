class_name AppearanceComponent
extends Node
## Modular cosmetic layer controller for Ellie (`res://data/hero_cosmetics.json`).
## Keeps her Base Body (`assets/characters/player*.png`), Outfit (`assets/characters/outfits/<folder>/player*.png`),
## and Hair (`assets/characters/hair/<folder>/player*.png` + `*_back.png`) separated for runtime customization,
## synced across multiplayer peers via `MultiplayerSynchronizer`, and composited cleanly in `hit_flash.gdshader`.

signal changed

const TABLE_NAME: String = "hero_cosmetics"
const OUTFITS_ROOT: String = "res://assets/characters/outfits/"
const HAIR_ROOT: String = "res://assets/characters/hair/"

@export var outfit_id: String = "default":
	set = set_outfit
@export var hair_id: String = "default":
	set = set_hair

var _sprite: Sprite2D = null
var _tex_cache: Dictionary = {} ## String resource path -> Texture2D or false sentinel


func _ready() -> void:
	if _sprite == null:
		var sibling: Sprite2D = get_node_or_null("../Sprite2D") as Sprite2D
		if sibling != null:
			bind_sprite(sibling)


## Binds this component to the player's main `Sprite2D` and stays synced across all sheet switches (`texture_changed`).
func bind_sprite(sprite: Sprite2D) -> void:
	if _sprite == sprite:
		_sync_material()
		return
	if _sprite != null and _sprite.texture_changed.is_connected(_sync_material):
		_sprite.texture_changed.disconnect(_sync_material)
	_sprite = sprite
	if _sprite != null and not _sprite.texture_changed.is_connected(_sync_material):
		_sprite.texture_changed.connect(_sync_material)
	_sync_material()


func set_outfit(id: String) -> void:
	var target: String = id if is_valid_outfit(id) else default_outfit_id()
	if outfit_id == target:
		_sync_material()
		return
	outfit_id = target
	_sync_material()
	changed.emit()


func set_hair(id: String) -> void:
	var target: String = id if is_valid_hair(id) else default_hair_id()
	if hair_id == target:
		_sync_material()
		return
	hair_id = target
	_sync_material()
	changed.emit()


## Multiplayer-safe request from the local player or UI to equip an outfit.
func request_outfit(id: String) -> void:
	if not is_valid_outfit(id):
		return
	var parent_node: Node = get_parent()
	if multiplayer.multiplayer_peer == null or (parent_node != null and parent_node.is_multiplayer_authority()):
		set_outfit(id)
	elif multiplayer.is_server():
		set_outfit(id)
	else:
		_rpc_set_outfit.rpc_id(1, id)


## Multiplayer-safe request from the local player or UI to equip a hairstyle/color.
func request_hair(id: String) -> void:
	if not is_valid_hair(id):
		return
	var parent_node: Node = get_parent()
	if multiplayer.multiplayer_peer == null or (parent_node != null and parent_node.is_multiplayer_authority()):
		set_hair(id)
	elif multiplayer.is_server():
		set_hair(id)
	else:
		_rpc_set_hair.rpc_id(1, id)


@rpc("any_peer", "call_local", "reliable")
func _rpc_set_outfit(id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var parent_node: Node = get_parent()
	if sender != 0 and parent_node != null and sender != parent_node.get_multiplayer_authority():
		return
	if is_valid_outfit(id):
		_rpc_apply_outfit.rpc(id)


@rpc("authority", "call_local", "reliable")
func _rpc_apply_outfit(id: String) -> void:
	set_outfit(id)


@rpc("any_peer", "call_local", "reliable")
func _rpc_set_hair(id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var parent_node: Node = get_parent()
	if sender != 0 and parent_node != null and sender != parent_node.get_multiplayer_authority():
		return
	if is_valid_hair(id):
		_rpc_apply_hair.rpc(id)


@rpc("authority", "call_local", "reliable")
func _rpc_apply_hair(id: String) -> void:
	set_hair(id)


func default_outfit_id() -> String:
	var tbl: Dictionary = DataRegistry.table(TABLE_NAME)
	return String(tbl.get("default_outfit", "default"))


func default_hair_id() -> String:
	var tbl: Dictionary = DataRegistry.table(TABLE_NAME)
	return String(tbl.get("default_hair", "default"))


func outfit_ids() -> PackedStringArray:
	var outfits: Dictionary = _outfits_table()
	var out: PackedStringArray = PackedStringArray()
	for k: Variant in outfits.keys():
		out.append(String(k))
	return out


func hair_ids() -> PackedStringArray:
	var hairs: Dictionary = _hairs_table()
	var out: PackedStringArray = PackedStringArray()
	for k: Variant in hairs.keys():
		out.append(String(k))
	return out


func is_valid_outfit(id: String) -> bool:
	var outfits: Dictionary = _outfits_table()
	return outfits.is_empty() and id == "default" or outfits.has(id)


func is_valid_hair(id: String) -> bool:
	var hairs: Dictionary = _hairs_table()
	return hairs.is_empty() and id == "default" or hairs.has(id)


func outfit_entry(id: String = "") -> Dictionary:
	var key: String = id if id != "" else outfit_id
	var outfits: Dictionary = _outfits_table()
	if outfits.has(key):
		return outfits[key] as Dictionary
	return {"name": "Reisegewand", "folder": "default", "tint": "#ffffff", "arm_style": "default", "arm_tint": "#ffffff"}


func hair_entry(id: String = "") -> Dictionary:
	var key: String = id if id != "" else hair_id
	var hairs: Dictionary = _hairs_table()
	if hairs.has(key):
		return hairs[key] as Dictionary
	return {"name": "Silberflieder", "folder": "default", "tint": "#ffffff"}


func arm_style() -> String:
	return String(outfit_entry().get("arm_style", "default"))


func arm_tint() -> Color:
	return Color.html(String(outfit_entry().get("arm_tint", "#ffffff")))


## Stable numeric key for `AttackComponent._arm_pose_key()` so changing outfit triggers an immediate arm redraw.
func arm_pose_token() -> float:
	return float((outfit_id.hash() & 0xFFFF))


func export_data() -> Dictionary:
	return {
		"outfit": outfit_id,
		"hair": hair_id,
	}


func import_data(data: Dictionary) -> void:
	set_outfit(String(data.get("outfit", default_outfit_id())))
	set_hair(String(data.get("hair", default_hair_id())))


func _outfits_table() -> Dictionary:
	return DataRegistry.table(TABLE_NAME).get("outfits", {}) as Dictionary


func _hairs_table() -> Dictionary:
	return DataRegistry.table(TABLE_NAME).get("hairs", {}) as Dictionary


func _load_cached(path: String) -> Texture2D:
	if path == "":
		return null
	if _tex_cache.has(path):
		var cached: Variant = _tex_cache[path]
		return cached as Texture2D if cached is Texture2D else null
	if not ResourceLoader.exists(path):
		_tex_cache[path] = false
		return null
	var tex: Texture2D = load(path) as Texture2D
	_tex_cache[path] = tex if tex != null else false
	return tex


func _sync_material() -> void:
	if _sprite == null:
		return
	var mat: ShaderMaterial = _sprite.material as ShaderMaterial
	if mat == null:
		return
	var base_tex: Texture2D = _sprite.texture
	if base_tex == null or base_tex.resource_path == "":
		mat.set_shader_parameter("use_cosmetics", false)
		return
	var stem: String = base_tex.resource_path.get_file().get_basename()
	if not stem.begins_with("player"):
		mat.set_shader_parameter("use_cosmetics", false)
		return

	var o_cfg: Dictionary = outfit_entry()
	var h_cfg: Dictionary = hair_entry()
	var o_folder: String = String(o_cfg.get("folder", "default"))
	var h_folder: String = String(h_cfg.get("folder", "default"))
	var o_tint: Color = Color.html(String(o_cfg.get("tint", "#ffffff")))
	var h_tint: Color = Color.html(String(h_cfg.get("tint", "#ffffff")))

	var o_tex: Texture2D = _load_cached("%s%s/%s.png" % [OUTFITS_ROOT, o_folder, stem]) if o_folder != "" else null
	var hf_tex: Texture2D = _load_cached("%s%s/%s.png" % [HAIR_ROOT, h_folder, stem]) if h_folder != "" else null
	var hb_tex: Texture2D = _load_cached("%s%s/%s_back.png" % [HAIR_ROOT, h_folder, stem]) if h_folder != "" else null

	mat.set_shader_parameter("use_cosmetics", true)
	mat.set_shader_parameter("has_outfit", o_tex != null)
	mat.set_shader_parameter("has_hair_front", hf_tex != null)
	mat.set_shader_parameter("has_hair_back", hb_tex != null)
	if o_tex != null:
		mat.set_shader_parameter("outfit_tex", o_tex)
	if hf_tex != null:
		mat.set_shader_parameter("hair_front_tex", hf_tex)
	if hb_tex != null:
		mat.set_shader_parameter("hair_back_tex", hb_tex)
	mat.set_shader_parameter("outfit_tint", o_tint)
	mat.set_shader_parameter("hair_tint", h_tint)
