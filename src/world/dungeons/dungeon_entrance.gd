class_name DungeonEntrance
extends Interactable
## Physical Dungeon Gate placed in an ALTMARK zone (e.g. Das Fluttor von Sturmhafen in SÜDKAP).
## Automatically discovers the dungeon when approached, registers in group `dungeon_entrances`
## for `MapMarkers`, and opens the Steinsetzer-Prüfungstafel focused on `dungeon_id` on E.

const DISCOVER_RANGE_PX: float = 165.0

@export var dungeon_id: String = "suedkap_gezeitenkammern"
@export var zone_id: StringName = &"suedkap"

var _time: float = 0.0
var _discovered_local: bool = false
var _light: NightLight = null
var _body: StaticBody2D = null
var _gate_tex: Texture2D = null
var _glow_tex: Texture2D = null


var _prompt_text: String = "GEWÖLBE"


func _ready() -> void:
	add_to_group("dungeon_entrances")
	add_to_group("night_lights")
	var def: Dictionary = DungeonRules.by_id(dungeon_id)
	var dname: String = String(def.get("name", "GEWÖLBE"))
	var min_lv: int = int(def.get("min_level", 1))
	_prompt_text = "%s (ST. %d)" % [dname, min_lv]
	y_sort_enabled = true

	var tex_path: String = "res://assets/props/sturmhafen_gate.png"
	var glow_path: String = "res://assets/props/sturmhafen_gate_glow.png"
	if ResourceLoader.exists(tex_path):
		_gate_tex = load(tex_path) as Texture2D
	if ResourceLoader.exists(glow_path):
		_glow_tex = load(glow_path) as Texture2D

	if _gate_tex != null:
		var spr: Sprite2D = Sprite2D.new()
		spr.name = "Sprite"
		spr.texture = _gate_tex
		spr.offset = Vector2(0.0, -float(_gate_tex.get_height()) * 0.5 + 14.0)
		add_child(spr)
	if _glow_tex != null:
		var gspr: Sprite2D = Sprite2D.new()
		gspr.name = "Glow"
		gspr.texture = _glow_tex
		gspr.material = Unlit.material()
		gspr.offset = Vector2(0.0, -float(_glow_tex.get_height()) * 0.5 + 14.0)
		add_child(gspr)

	## Compact stone pillars collision flanking the arch so the player can walk up to the threshold
	_body = StaticBody2D.new()
	_body.collision_layer = 1
	_body.collision_mask = 0
	for sx: float in [-34.0, 34.0]:
		var cs: CollisionShape2D = CollisionShape2D.new()
		var rect: RectangleShape2D = RectangleShape2D.new()
		rect.size = Vector2(18.0, 16.0)
		cs.shape = rect
		cs.position = Vector2(sx, -8.0)
		_body.add_child(cs)
	add_child(_body)

	_light = NightLight.new()
	_light.position = Vector2(0.0, -24.0)
	_light.radius = 96.0
	_light.squash = 0.72
	_light.base_energy = 0.72
	_light.pulse = 0.16
	_light.glow_color = Color(String(def.get("accent", "4df2e0")))
	add_child(_light)


func _process(delta: float) -> void:
	_time += delta
	if _gate_tex == null:
		queue_redraw()
	if not _discovered_local:
		var local_p: Player = SaveGame._local_player(get_tree())
		if local_p != null and local_p.global_position.distance_to(global_position) <= DISCOVER_RANGE_PX:
			_discovered_local = true
			if local_p.dungeons != null and not local_p.dungeons.is_discovered(dungeon_id):
				local_p.dungeons.request_discover(dungeon_id)
				var def: Dictionary = DungeonRules.by_id(dungeon_id)
				var box: SpeechBox = get_tree().get_first_node_in_group("speech_box") as SpeechBox
				if box != null:
					box.speak("GEWÖLBE ENTDECKT", "%s — ab Stufe %d." % [String(def.get("name", "")), int(def.get("min_level", 1))], 3.5)


func prompt() -> String:
	return _prompt_text


func reach_distance(from: Vector2) -> float:
	return maxf(0.0, global_position.distance_to(from) - 44.0)


func prompt_position() -> Vector2:
	return Vector2(0.0, -68.0)


func interact(player: Player) -> void:
	if player != null and player.dungeons != null:
		player.dungeons.request_discover(dungeon_id)
	var dm: DungeonManager = DungeonManager.of(get_tree())
	if dm != null:
		dm.open_gate_window(dungeon_id, global_position)


func _draw() -> void:
	if _gate_tex != null:
		return
	## Crisp procedural Steinsetzer Sea-Arch fallback before M6 bakes the full sprite
	var pulse: float = 0.75 + 0.25 * sin(_time * 3.0)
	draw_rect(Rect2(-44, -54, 18, 56), Color("283448"))
	draw_rect(Rect2(26, -54, 18, 56), Color("283448"))
	draw_rect(Rect2(-48, -64, 96, 16), Color("364860"))
	draw_rect(Rect2(-26, -48, 52, 48), Color("0a0d18"))
	## 4 glowing Resonance Runes in the lintel
	for i: int in 4:
		var rx: float = -24.0 + float(i) * 15.0
		draw_rect(Rect2(rx, -58, 5, 5), Color(Color("4df2e0"), 0.85 * pulse))
	## Shimmering turquoise-violet threshold
	draw_rect(Rect2(-22, -44, 44, 42), Color(Color("2a8c94"), 0.35 * pulse))
	draw_rect(Rect2(-14, -38, 28, 34), Color(Color("4df2e0"), 0.25 * pulse))
