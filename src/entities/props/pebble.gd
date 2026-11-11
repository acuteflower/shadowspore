class_name Pebble
extends WorldProp
## Something small lying in the meadow that E picks up (she bends down for it, like for berries): little
## stones, most of all along the shores, and glow caps (mushrooms in groups of 1 to 5, the variant is the
## amount) that glow at night. After a few days a new one lies there again. What it shows, gives and
## bursts into comes from the `pickup` block of its kind in data/plants.json.
## `night_only` (the lake's Seeglimmer, docs/seehexe_konzept.md 6): it only shows, glows and can be picked while the night is deep enough.

const NIGHT_SHOWN: float = 0.45 ## night_amount from which a night-only find is there

const PICK_BURST: Array[Color] = [Color("c4c2da"), Color("9a98b8")]
const REGROW_BURST: Array[Color] = [Color("d9c8ff"), Color("78f4e6")]


func apply_state(new_state: Dictionary, fx: String) -> void:
	state = new_state
	var gone: bool = bool(state.get("p", 0))
	_sprite.texture = load(String(_spec.texture)) as Texture2D
	_sprite.hframes = int(_spec.columns)
	_sprite.vframes = 1
	_sprite.frame = variant
	var there: bool = not gone and _shown_now()
	_sprite.visible = there
	_sync_glow(there)
	var light: Dictionary = _spec.get("light", {})
	if not light.is_empty():
		_set_light(there, Color(String(light.color)), int(light.radius), float(light.energy)) ## a pool of light while it stands
	if fx == "pick":
		Sfx.at(self, "item_pickup" if String(_spec.pickup.get("item", "")) == "stone" else "pluck", global_position, -3.0)
		_burst(4 + int(_spec.pickup.get("amount", [1])[variant] if _spec.pickup.has("amount") else 0), _burst_colors(), 30.0, Vector2(0, -_height * 0.5))
	elif fx == "regrow":
		_burst(4, REGROW_BURST, 0.0, Vector2(0, -_height * 0.5))
	if _prompt_node != null:
		set_focused(_prompt_node.visible)


func _shown_now() -> bool:
	return not bool(_spec.get("night_only", false)) or MineManager.night_at(self, TimeManager.night_amount()) >= NIGHT_SHOWN


var _was_shown: bool = true


func set_night(amount: float) -> void:
	super.set_night(amount)
	if bool(_spec.get("night_only", false)) and _sprite != null and _shown_now() != _was_shown:
		_was_shown = _shown_now()
		apply_state(state, "")


func prompt() -> String:
	if bool(state.get("p", 0)) or not _shown_now():
		return ""
	return String((_spec.pickup as Dictionary).prompt)


func reach_distance(from: Vector2) -> float:
	return from.distance_to(global_position + Vector2(0, -3)) - _radius * 0.5


func prompt_position() -> Vector2:
	return Vector2(0, -maxf(_height + 8.0, 16.0))


func interact(player: Player) -> void:
	var toward: Vector2 = global_position - player.global_position
	player.begin_pick(toward.normalized() if toward.length() > 1.0 else player.facing, func() -> void: level.request_pick(cell))


func _burst_colors() -> Array[Color]:
	var colors: Array[Color] = []
	for hex: String in (_spec.pickup as Dictionary).get("burst", []):
		colors.append(Color(hex))
	return colors if not colors.is_empty() else PICK_BURST
