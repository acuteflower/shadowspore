extends Node2D
## Automated verification for Ellie's modular Hair & Outfit customization system (`AppearanceComponent`,
## `data/hero_cosmetics.json`, `hit_flash.gdshader`, `ArmPainter`, and all 25 separated sprite sheets).

const PLAYER_SCENE: PackedScene = preload("res://src/entities/player/player.tscn")
const STEMS: Array[String] = [
	"player", "player_attack", "player_pick", "player_eat", "player_pull",
	"player_feed", "player_drink", "player_touch", "player_combo", "player_heavy",
	"player_cast", "player_step", "player_climb", "player_fish", "player_standby",
	"player_swim", "player_emerge", "player_wake", "player_faint", "player_sit",
	"player_rest", "player_carry", "player_stumble", "player_wardrobe", "player_carry_stone",
]


func _ready() -> void:
	_run()


func _fail(msg: String) -> void:
	push_error("TEST_APPEARANCE FAILED: " + msg)
	print("FAIL: " + msg)
	get_tree().quit(1)


func _assert_true(cond: bool, msg: String) -> void:
	if not cond:
		_fail(msg)


func _run() -> void:
	# 1. Verify DataRegistry loaded hero_cosmetics.json
	var tbl: Dictionary = DataRegistry.table("hero_cosmetics")
	_assert_true(not tbl.is_empty(), "hero_cosmetics.json loaded in DataRegistry")
	var outfits: Dictionary = tbl.get("outfits", {}) as Dictionary
	var hairs: Dictionary = tbl.get("hairs", {}) as Dictionary
	_assert_true(outfits.has("default") and outfits.has("none") and outfits.has("crimson"), "outfits table contains default, none, crimson")
	_assert_true(hairs.has("default") and hairs.has("none") and hairs.has("obsidian") and hairs.has("blonde"), "hairs table contains default, none, obsidian, blonde")

	# 2. Verify all 25 player sheets have matching Base Body, Outfit, Hair Front & Hair Back textures of identical dimensions
	for stem: String in STEMS:
		var base_path: String = "res://assets/characters/%s.png" % stem
		var outfit_path: String = "res://assets/characters/outfits/default/%s.png" % stem
		var hf_path: String = "res://assets/characters/hair/default/%s.png" % stem
		var hb_path: String = "res://assets/characters/hair/default/%s_back.png" % stem
		var base_tex: Texture2D = load(base_path) as Texture2D
		var outfit_tex: Texture2D = load(outfit_path) as Texture2D
		var hf_tex: Texture2D = load(hf_path) as Texture2D
		var hb_tex: Texture2D = load(hb_path) as Texture2D
		_assert_true(base_tex != null, "Base sheet exists: " + base_path)
		_assert_true(outfit_tex != null, "Outfit sheet exists: " + outfit_path)
		_assert_true(hf_tex != null, "Hair front sheet exists: " + hf_path)
		_assert_true(hb_tex != null, "Hair back sheet exists: " + hb_path)
		var sz: Vector2 = base_tex.get_size()
		_assert_true(outfit_tex.get_size() == sz, "Outfit size matches base for " + stem)
		_assert_true(hf_tex.get_size() == sz, "Hair front size matches base for " + stem)
		_assert_true(hb_tex.get_size() == sz, "Hair back size matches base for " + stem)

	# 3. Spawn Player and test live shader & ArmPainter synchronization across sheet switches and preset switches
	NetworkManager.host_singleplayer()
	var player: Player = PLAYER_SCENE.instantiate() as Player
	player.name = "2"
	add_child(player)
	player.set_multiplayer_authority(1)
	await get_tree().process_frame

	var app: AppearanceComponent = player.appearance
	_assert_true(app != null, "Player has AppearanceComponent")
	var sprite: Sprite2D = player.get_node("Sprite2D") as Sprite2D
	var mat: ShaderMaterial = sprite.material as ShaderMaterial
	_assert_true(bool(mat.get_shader_parameter("use_cosmetics")), "use_cosmetics enabled on Player Sprite2D")
	_assert_true(bool(mat.get_shader_parameter("has_outfit")), "default outfit bound")
	_assert_true(bool(mat.get_shader_parameter("has_hair_front")), "default hair front bound")
	_assert_true(bool(mat.get_shader_parameter("has_hair_back")), "default hair back bound")

	# Test switching Sprite2D.texture updates cosmetic layer textures via texture_changed signal
	var sit_tex: Texture2D = load("res://assets/characters/player_sit.png") as Texture2D
	sprite.texture = sit_tex
	var bound_outfit: Texture2D = mat.get_shader_parameter("outfit_tex") as Texture2D
	var bound_hf: Texture2D = mat.get_shader_parameter("hair_front_tex") as Texture2D
	var bound_hb: Texture2D = mat.get_shader_parameter("hair_back_tex") as Texture2D
	_assert_true(bound_outfit != null and bound_outfit.resource_path.ends_with("outfits/default/player_sit.png"), "texture_changed updated outfit_tex to player_sit")
	_assert_true(bound_hf != null and bound_hf.resource_path.ends_with("hair/default/player_sit.png"), "texture_changed updated hair_front_tex to player_sit")
	_assert_true(bound_hb != null and bound_hb.resource_path.ends_with("hair/default/player_sit_back.png"), "texture_changed updated hair_back_tex to player_sit_back")

	# Test switching outfit to "none" (bare mannequin) & hair to "blonde"
	app.request_outfit("none")
	app.request_hair("blonde")
	_assert_true(app.outfit_id == "none" and app.hair_id == "blonde", "request_outfit/request_hair applied")
	_assert_true(not bool(mat.get_shader_parameter("has_outfit")), "has_outfit is false when outfit_id == none")
	_assert_true(bool(mat.get_shader_parameter("has_hair_front")), "has_hair_front stays true for blonde")
	_assert_true(app.arm_style() == "bare", "arm_style switches to bare when outfit_id == none")

	# Verify ArmPainter bare arm vs crimson dyed arm rasterizes cleanly
	var sh: Vector3 = Vector3(-4.0, 0.0, 32.0)
	var el: Vector3 = Vector3(-6.0, 2.0, 26.0)
	var wr: Vector3 = Vector3(-4.0, 5.0, 22.0)
	var fi: Vector3 = Vector3(-3.5, 6.0, 21.0)
	var bare_img: Dictionary = ArmPainter.raster(sh, el, wr, fi, {"arm_style": "bare"})
	var def_img: Dictionary = ArmPainter.raster(sh, el, wr, fi, {"arm_style": "default", "arm_tint": Color.html("#c43658")})
	_assert_true((bare_img["filled"] as PackedByteArray).count(1) > 15, "ArmPainter bare arm renders solid pixels")
	_assert_true((def_img["filled"] as PackedByteArray).count(1) > 15, "ArmPainter dyed outfit arm renders solid pixels")

	# Test SaveGame / export_data & import_data roundtrip
	app.request_outfit("crimson")
	app.request_hair("obsidian")
	var exported: Dictionary = app.export_data()
	app.request_outfit("default")
	app.request_hair("default")
	app.import_data(exported)
	_assert_true(app.outfit_id == "crimson" and app.hair_id == "obsidian", "export_data/import_data roundtrip preserved crimson + obsidian")

	print("ALL 25 LAYERED SHEETS & APPEARANCE TESTS PASSED!")
	get_tree().quit(0)
