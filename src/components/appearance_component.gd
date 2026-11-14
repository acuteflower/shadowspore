class_name AppearanceComponent
extends Node
## Modular cosmetic layer controller for Ellie (`res://data/hero_cosmetics.json`).
## Keeps her Base Body (`assets/characters/player*.png`), Outfit (`assets/characters/outfits/<folder>/player*.png`),
## and Hair (`assets/characters/hair/<folder>/player*.png` + `*_back.png`) separated for runtime customization,
## synced across multiplayer peers via `MultiplayerSynchronizer`, and composited cleanly in `hit_flash.gdshader`.

signal changed
signal unlocked(kind: String, id: String)

const TABLE_NAME: String = "hero_cosmetics"
const OUTFITS_ROOT: String = "res://assets/characters/outfits/"
const HAIR_ROOT: String = "res://assets/characters/hair/"

@export var outfit_id: String = "default":
	set = set_outfit
@export var hair_id: String = "default":
	set = set_hair

var unlocked_hair_styles: Array[String] = []
var unlocked_hair_colors: Array[String] = []
var unlocked_outfits: Array[String] = []
var unlocked_outfit_colors: Array[String] = []

var _preview_outfit: String = ""
var _preview_hair: String = ""
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


func effective_outfit_id() -> String:
	return _preview_outfit if _preview_outfit != "" else outfit_id


func effective_hair_id() -> String:
	return _preview_hair if _preview_hair != "" else hair_id


## Local-only salon mirror preview (does not touch replicated `outfit_id` / `hair_id` until confirmed).
func set_preview(preview_outfit: String = "", preview_hair: String = "") -> void:
	var next_outfit: String = preview_outfit if (preview_outfit != "" and is_valid_outfit(preview_outfit)) else ""
	var next_hair: String = preview_hair if (preview_hair != "" and is_valid_hair(preview_hair)) else ""
	if _preview_outfit == next_outfit and _preview_hair == next_hair:
		return
	_preview_outfit = next_outfit
	_preview_hair = next_hair
	_sync_material()


func clear_preview() -> void:
	if _preview_outfit == "" and _preview_hair == "":
		return
	_preview_outfit = ""
	_preview_hair = ""
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


## Host-authoritative unlock for world-discovered hairstyles, dyes, and outfits.
func unlock_cosmetic(kind: String, id: String) -> bool:
	if not _is_unlockable(kind, id):
		return false
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		return false
	if _has_unlock(kind, id):
		return false
	if multiplayer.multiplayer_peer == null:
		return _apply_unlock(kind, id)
	_rpc_apply_unlock.rpc(kind, id)
	return true


func unlock_hair_style(style_id: String) -> bool:
	return unlock_cosmetic("hair_style", style_id)


func unlock_hair_color(color_id: String) -> bool:
	return unlock_cosmetic("hair_color", color_id)


func unlock_outfit(id: String) -> bool:
	return unlock_cosmetic("outfit", id)


func unlock_outfit_style(style_id: String) -> bool:
	return unlock_cosmetic("outfit", style_id)


func unlock_outfit_color(color_id: String) -> bool:
	return unlock_cosmetic("outfit_color", color_id)


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


@rpc("authority", "call_local", "reliable")
func _rpc_apply_unlock(kind: String, id: String) -> void:
	_apply_unlock(kind, id)


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


func salon_hair_styles() -> PackedStringArray:
	return _salon_table_ids(_hair_styles_table(), is_hair_style_unlocked, true)


func salon_hair_colors() -> PackedStringArray:
	return _salon_table_ids(_hair_colors_table(), is_hair_color_unlocked, true)


func salon_outfit_styles() -> PackedStringArray:
	return _salon_table_ids(_outfit_styles_table(), is_outfit_unlocked, true)


func salon_outfit_colors() -> PackedStringArray:
	return _salon_table_ids(_outfit_colors_table(), is_outfit_color_unlocked, true)


func salon_outfits() -> PackedStringArray:
	var via_styles: PackedStringArray = salon_outfit_styles()
	if not via_styles.is_empty():
		return via_styles
	return _salon_table_ids(_outfits_table(), is_outfit_unlocked, false)


func is_hair_style_unlocked(style_id: String) -> bool:
	return _entry_unlocked(_hair_styles_table(), unlocked_hair_styles, style_id)


func is_hair_color_unlocked(color_id: String) -> bool:
	return _entry_unlocked(_hair_colors_table(), unlocked_hair_colors, color_id)


func is_outfit_unlocked(id: String) -> bool:
	var styles: Dictionary = _outfit_styles_table()
	if styles.has(id):
		return _entry_unlocked(styles, unlocked_outfits, id)
	return _entry_unlocked(_outfits_table(), unlocked_outfits, id)


func is_outfit_color_unlocked(color_id: String) -> bool:
	return _entry_unlocked(_outfit_colors_table(), unlocked_outfit_colors, color_id)


func is_valid_outfit(id: String) -> bool:
	var outfits: Dictionary = _outfits_table()
	var styles: Dictionary = _outfit_styles_table()
	var colors: Dictionary = _outfit_colors_table()
	if outfits.has(id) or styles.has(id) or colors.has(id):
		return true
	if id.contains(":"):
		var parts: PackedStringArray = id.split(":", false)
		return parts.size() == 2 and styles.has(parts[0]) and colors.has(parts[1])
	return outfits.is_empty() and styles.is_empty() and id == "default"


func is_valid_hair(id: String) -> bool:
	var hairs: Dictionary = _hairs_table()
	var styles: Dictionary = _hair_styles_table()
	var colors: Dictionary = _hair_colors_table()
	if hairs.has(id) or styles.has(id) or colors.has(id):
		return true
	if id.contains(":"):
		var parts: PackedStringArray = id.split(":", false)
		return parts.size() == 2 and styles.has(parts[0]) and colors.has(parts[1])
	return hairs.is_empty() and id == "default"


func parse_outfit_id(id: String = "") -> Dictionary:
	var key: String = id if id != "" else effective_outfit_id()
	return _parse_layered_id(key, _outfit_styles_table(), _outfit_colors_table())


func compose_outfit_id(style_id: String, color_id: String) -> String:
	return _compose_layered_id(style_id, color_id, _outfit_styles_table(), _outfit_colors_table())


func parse_hair_id(id: String = "") -> Dictionary:
	var key: String = id if id != "" else effective_hair_id()
	return _parse_layered_id(key, _hair_styles_table(), _hair_colors_table())


func compose_hair_id(style_id: String, color_id: String) -> String:
	return _compose_layered_id(style_id, color_id, _hair_styles_table(), _hair_colors_table())


func outfit_style_entry(style_id: String = "") -> Dictionary:
	var key: String = style_id if style_id != "" else String(parse_outfit_id().get("style", "default"))
	var styles: Dictionary = _outfit_styles_table()
	if styles.has(key):
		return styles[key] as Dictionary
	var outfits: Dictionary = _outfits_table()
	if outfits.has(key):
		return outfits[key] as Dictionary
	return {"name": "Reisegewand", "folder": "default", "arm_style": "default", "starter": true, "info": ""}


func outfit_color_entry(color_id: String = "") -> Dictionary:
	var key: String = color_id if color_id != "" else String(parse_outfit_id().get("color", "default"))
	var colors: Dictionary = _outfit_colors_table()
	if colors.has(key):
		return colors[key] as Dictionary
	return {"name": "Original", "tint": "#ffffff", "arm_tint": "#ffffff", "swatch": ["#281d3d", "#4a3870", "#7c64a8", "#f0c878"], "starter": true, "info": ""}


func outfit_entry(id: String = "") -> Dictionary:
	var key: String = id if id != "" else effective_outfit_id()
	var outfits: Dictionary = _outfits_table()
	if key == "none" and outfits.has("none"):
		return outfits["none"] as Dictionary
	var styles: Dictionary = _outfit_styles_table()
	var colors: Dictionary = _outfit_colors_table()
	if key.contains(":") or styles.has(key) or colors.has(key):
		var parts: Dictionary = parse_outfit_id(key)
		var style_cfg: Dictionary = outfit_style_entry(String(parts.get("style", "default")))
		var color_cfg: Dictionary = outfit_color_entry(String(parts.get("color", "default")))
		return {
			"name": String(style_cfg.get("name", "Reisegewand")),
			"folder": String(style_cfg.get("folder", "default")),
			"tint": String(color_cfg.get("tint", "#ffffff")),
			"arm_style": String(style_cfg.get("arm_style", "default")),
			"arm_tint": String(color_cfg.get("arm_tint", color_cfg.get("tint", "#ffffff"))),
			"info": String(style_cfg.get("info", "")),
		}
	if outfits.has(key):
		return outfits[key] as Dictionary
	return {"name": "Reisegewand", "folder": "default", "tint": "#ffffff", "arm_style": "default", "arm_tint": "#ffffff"}


func hair_style_entry(style_id: String = "") -> Dictionary:
	var key: String = style_id if style_id != "" else String(parse_hair_id().get("style", "default"))
	var styles: Dictionary = _hair_styles_table()
	if styles.has(key):
		return styles[key] as Dictionary
	return {"name": "Silberwellen", "folder": "default", "starter": true, "info": ""}


func hair_color_entry(color_id: String = "") -> Dictionary:
	var key: String = color_id if color_id != "" else String(parse_hair_id().get("color", "default"))
	var colors: Dictionary = _hair_colors_table()
	if colors.has(key):
		return colors[key] as Dictionary
	return {"name": "Silberflieder", "tint": "#ffffff", "swatch": ["#3e3152", "#8e79a8", "#d6cbe6", "#f4f0ff"], "starter": true, "info": ""}


func hair_entry(id: String = "") -> Dictionary:
	var key: String = id if id != "" else effective_hair_id()
	var hairs: Dictionary = _hairs_table()
	if hairs.has(key):
		return hairs[key] as Dictionary
	var parts: Dictionary = parse_hair_id(key)
	var style_cfg: Dictionary = hair_style_entry(String(parts.get("style", "default")))
	var color_cfg: Dictionary = hair_color_entry(String(parts.get("color", "default")))
	return {
		"name": String(color_cfg.get("name", style_cfg.get("name", "Silberflieder"))),
		"folder": String(style_cfg.get("folder", "default")),
		"tint": String(color_cfg.get("tint", "#ffffff")),
	}


func arm_style() -> String:
	return String(outfit_entry().get("arm_style", "default"))


func arm_tint() -> Color:
	return Color.html(String(outfit_entry().get("arm_tint", "#ffffff")))


## Stable numeric key for `AttackComponent._arm_pose_key()` so changing outfit triggers an immediate arm redraw.
func arm_pose_token() -> float:
	return float((effective_outfit_id().hash() & 0xFFFF))


func export_data() -> Dictionary:
	return {
		"outfit": outfit_id,
		"hair": hair_id,
		"unlocked_hair_styles": unlocked_hair_styles.duplicate(),
		"unlocked_hair_colors": unlocked_hair_colors.duplicate(),
		"unlocked_outfits": unlocked_outfits.duplicate(),
		"unlocked_outfit_colors": unlocked_outfit_colors.duplicate(),
	}


func import_data(data: Dictionary) -> void:
	unlocked_hair_styles.clear()
	for item: Variant in data.get("unlocked_hair_styles", []) as Array:
		var s: String = String(item)
		if _hair_styles_table().has(s) and not unlocked_hair_styles.has(s):
			unlocked_hair_styles.append(s)
	unlocked_hair_colors.clear()
	for item: Variant in data.get("unlocked_hair_colors", []) as Array:
		var c: String = String(item)
		if _hair_colors_table().has(c) and not unlocked_hair_colors.has(c):
			unlocked_hair_colors.append(c)
	unlocked_outfits.clear()
	for item: Variant in data.get("unlocked_outfits", []) as Array:
		var o: String = String(item)
		if (_outfits_table().has(o) or _outfit_styles_table().has(o)) and not unlocked_outfits.has(o):
			unlocked_outfits.append(o)
	unlocked_outfit_colors.clear()
	for item: Variant in data.get("unlocked_outfit_colors", []) as Array:
		var oc: String = String(item)
		if _outfit_colors_table().has(oc) and not unlocked_outfit_colors.has(oc):
			unlocked_outfit_colors.append(oc)
	set_outfit(String(data.get("outfit", default_outfit_id())))
	set_hair(String(data.get("hair", default_hair_id())))


func _is_unlockable(kind: String, id: String) -> bool:
	match kind:
		"hair_style":
			return _hair_styles_table().has(id)
		"hair_color":
			return _hair_colors_table().has(id)
		"outfit":
			return _outfits_table().has(id) or _outfit_styles_table().has(id)
		"outfit_color":
			return _outfit_colors_table().has(id)
	return false


func _has_unlock(kind: String, id: String) -> bool:
	match kind:
		"hair_style":
			return is_hair_style_unlocked(id)
		"hair_color":
			return is_hair_color_unlocked(id)
		"outfit":
			return is_outfit_unlocked(id)
		"outfit_color":
			return is_outfit_color_unlocked(id)
	return true


func _apply_unlock(kind: String, id: String) -> bool:
	match kind:
		"hair_style":
			if not _hair_styles_table().has(id) or unlocked_hair_styles.has(id):
				return false
			unlocked_hair_styles.append(id)
		"hair_color":
			if not _hair_colors_table().has(id) or unlocked_hair_colors.has(id):
				return false
			unlocked_hair_colors.append(id)
		"outfit":
			if (not _outfits_table().has(id) and not _outfit_styles_table().has(id)) or unlocked_outfits.has(id):
				return false
			unlocked_outfits.append(id)
		"outfit_color":
			if not _outfit_colors_table().has(id) or unlocked_outfit_colors.has(id):
				return false
			unlocked_outfit_colors.append(id)
		_:
			return false
	unlocked.emit(kind, id)
	changed.emit()
	return true


func _salon_table_ids(table: Dictionary, unlock_fn: Callable, default_salon: bool) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for k: Variant in table.keys():
		var id: String = String(k)
		var cfg: Dictionary = table[k] as Dictionary
		if bool(cfg.get("salon", default_salon)) and bool(unlock_fn.call(id)):
			out.append(id)
	return out


func _entry_unlocked(table: Dictionary, unlocked_list: Array[String], id: String) -> bool:
	if not table.has(id):
		return false
	var cfg: Dictionary = table[id] as Dictionary
	return bool(cfg.get("starter", false)) or unlocked_list.has(id)


func _parse_layered_id(key: String, styles: Dictionary, colors: Dictionary) -> Dictionary:
	if key == "none":
		return {"style": "none", "color": "default"}
	if key.contains(":"):
		var parts: PackedStringArray = key.split(":", false)
		if parts.size() == 2:
			var s: String = parts[0] if styles.has(parts[0]) else "default"
			var c: String = parts[1] if colors.has(parts[1]) else "default"
			return {"style": s, "color": c}
	if styles.has(key):
		return {"style": key, "color": "default"}
	if colors.has(key):
		return {"style": "default", "color": key}
	return {"style": "default", "color": "default"}


func _compose_layered_id(style_id: String, color_id: String, styles: Dictionary, colors: Dictionary) -> String:
	var s: String = style_id if styles.has(style_id) else "default"
	var c: String = color_id if colors.has(color_id) else "default"
	if s == "default":
		return c
	if c == "default":
		return s
	return "%s:%s" % [s, c]


func _outfits_table() -> Dictionary:
	return DataRegistry.table(TABLE_NAME).get("outfits", {}) as Dictionary


func _outfit_styles_table() -> Dictionary:
	return DataRegistry.table(TABLE_NAME).get("outfit_styles", {}) as Dictionary


func _outfit_colors_table() -> Dictionary:
	return DataRegistry.table(TABLE_NAME).get("outfit_colors", {}) as Dictionary


func _hairs_table() -> Dictionary:
	return DataRegistry.table(TABLE_NAME).get("hairs", {}) as Dictionary


func _hair_styles_table() -> Dictionary:
	return DataRegistry.table(TABLE_NAME).get("hair_styles", {}) as Dictionary


func _hair_colors_table() -> Dictionary:
	return DataRegistry.table(TABLE_NAME).get("hair_colors", {}) as Dictionary


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
