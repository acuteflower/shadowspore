class_name HallgratExtra
extends HallgratResident
## One of Hallgrat's nameless townsfolk (docs/hallgrat_bewohner_konzept.md 3), made by `HallgratExtras` from the seed: a role, a body sheet
## (`py -3 tools/art_hallgrat_extras.py` -> assets/characters/hallgrat_extra_<kind>.png, one rig data/hallgrat_extra_rig.json) and a palette
## the `hallgrat_extra.gdshader` swaps into the sheet's KEY colours. Moved like the core figures. E = ANSPRECHEN gives a line from the role's
## pool (and the night's), nothing more: no trust, no shop, no notices.

var role: String = ""
var kind: int = 0


func setup(resident_id: String, data: Dictionary) -> void:
	id = resident_id
	spec = data
	role = String(data.get("role", ""))
	kind = int(data.get("kind", 0))
	name = "Extra_" + id
	var rig_path: String = "res://data/hallgrat_extra_rig.json"
	if not FileAccess.file_exists(rig_path):
		return
	_rig = JSON.parse_string(FileAccess.get_file_as_string(rig_path)) as Dictionary
	var info: Dictionary = ((_rig.get("kinds", []) as Array)[kind] as Dictionary) if kind < (_rig.get("kinds", []) as Array).size() else {}
	_rig["height"] = int(info.get("height", 56))
	if String(info.get("load", "")) not in ["", "wache"]:
		walk_clip = "carry"
	var art: String = "hallgrat_extra_%d" % kind
	_sprite = _sheet("res://assets/characters/%s.png" % art)
	_sprite.material = _palette(data)
	if String(info.get("load", "")) == "wache" and ResourceLoader.exists("res://assets/characters/%s_glow.png" % art):
		_glow = _sheet("res://assets/characters/%s_glow.png" % art)
		_glow.material = Unlit.material()


## The townsperson's own colours for the three KEY ramps of the sheet.
func _palette(data: Dictionary) -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/hallgrat_extra.gdshader") as Shader
	var keys: Dictionary = _rig.get("keys", {}) as Dictionary
	var palettes: Dictionary = (DataRegistry.table("hallgrat_people").get("extras", {}) as Dictionary).get("palettes", {}) as Dictionary
	var pal: Array = data.get("pal", [0, 0, 0]) as Array
	var slots: Array[String] = ["a", "b", "h"]
	for k: int in 3:
		var slot: String = slots[k]
		var key: Array = keys.get(slot, []) as Array
		var list: Array = palettes.get(slot, []) as Array
		var ramp: Array = (list[int(pal[k]) % list.size()] as Array) if not list.is_empty() else key
		var from: PackedColorArray = PackedColorArray()
		var to: PackedColorArray = PackedColorArray()
		for j: int in 4:
			from.append(Color(String(key[j])) if j < key.size() else Color.TRANSPARENT)
			to.append(Color(String(ramp[j])) if j < ramp.size() else Color.TRANSPARENT)
		mat.set_shader_parameter("key_" + slot, from)
		mat.set_shader_parameter("new_" + slot, to)
	return mat


func _meet_town() -> void:
	pass ## nobody the town trades with


func _exit_tree() -> void:
	pass


func prompt() -> String:
	if inside or _talking or InputManager.ui_blocking:
		return ""
	return "ANSPRECHEN"


func interact(player: Player) -> void:
	if _talking:
		return
	_talking = true
	_turned = 4.0
	_sector = Adventurer.sector_of(player.global_position - global_position)
	var runner: BubbleRunner = BubbleRunner.find(player)
	var line: String = chat_line()
	if runner != null and line != "":
		await runner.say_line(_title(), line, self)
	_talking = false


func sound_role() -> String:
	return role


func _title() -> String:
	var names: Dictionary = {"wache": "WACHE", "haendler": "HÄNDLERIN" if kind in [1, 5, 10] else "HÄNDLER", "traeger": "TRÄGER",
		"steinsetzer": "STEINSETZER", "marktgaenger": "STÄDTERIN" if kind in [1, 5, 10] else "STÄDTER", "alte": "ALTE" if kind == 5 else "ALTER",
		"waescherin": "WÄSCHERIN"}
	return String(names.get(role, "STÄDTER"))


func actor_position(_who: String) -> Vector2:
	return Vector2.INF


## A line of the role's pool, the night's, or anything (placeholders for the dialogue writer); never the same twice in a row.
func chat_line() -> String:
	var lines: Dictionary = (DataRegistry.table("hallgrat_people").get("extras", {}) as Dictionary).get("lines", {}) as Dictionary
	var pool: Array = []
	pool.append_array(lines.get(role, []) as Array)
	if TimeManager.is_night():
		pool.append_array(lines.get("night", []) as Array)
	pool.append_array(lines.get("any", []) as Array)
	if pool.is_empty():
		return ""
	var line: String = String(pool[randi() % pool.size()])
	if pool.size() > 1 and line == _last_line:
		line = String(pool[(pool.find(line) + 1) % pool.size()])
	_last_line = line
	return line
