extends Node
## Verifies the Freiluftsalon (`salon` recipe with `prism_shard`, `AppearanceComponent` hair styles/colors/preview/unlocks,
## `SalonSeat` sitting flow, and `SalonWindow` tabs, live preview, confirmation, and stand-up).

var _ok: bool = true
var _checks: int = 0


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_ok = false
		print("SALON FAILED: ", what)


func _frames(n: int) -> void:
	for i: int in n:
		get_tree().paused = false
		await get_tree().process_frame


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# 1. Recipe & cosmetics table checks
	var salon_spec: Dictionary = TownRules.piece("salon")
	var cost: Dictionary = salon_spec.get("cost", {}) as Dictionary
	_check(int(cost.get("prism_shard", 0)) >= 3, "salon recipe requires prism_shard from the desert (%s)" % str(cost))
	_check(cost.size() == 4 and int(cost.get("plank", 0)) > 0 and int(cost.get("iron_ingot", 0)) > 0 and int(cost.get("willow_thread", 0)) > 0, "salon recipe uses 4 fitting materials")
	_check(bool(salon_spec.get("salon", false)), "salon piece has salon=true")

	# 2. World + Town + SalonSeat + SalonWindow end-to-end
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await _frames(2)
	var player: Player = world._players.get_child(0) as Player
	var town: TownManager = world.town()
	await _frames(60)
	world.debug_jump_town()
	await _frames(90)

	var app: AppearanceComponent = player.appearance
	_check(app != null, "player has AppearanceComponent")
	_check(app.salon_hair_styles().size() == 6 and app.salon_hair_styles()[0] == "default", "salon lists all 6 hairstyles (%s)" % ",".join(app.salon_hair_styles()))
	_check(app.salon_hair_styles().has("moon_knot") and app.salon_hair_styles().has("storm_tail"), "salon includes Sternenschleier (moon_knot) and Sturmschweif (storm_tail)")
	_check(app.salon_outfit_styles().size() == 2 and app.salon_outfit_styles()[0] == "default" and app.salon_outfit_styles().has("perlenbluete"), "salon lists Reisegewand and Perlenblüte (%s)" % ",".join(app.salon_outfit_styles()))
	_check(app.salon_hair_colors().size() >= 8, "salon offers multiple hair color variants (%d)" % app.salon_hair_colors().size())
	_check(app.salon_outfit_colors().size() >= 8, "salon offers multiple outfit color variants (%d)" % app.salon_outfit_colors().size())

	# Preview does not mutate replicated hair_id/outfit_id, and clear_preview restores them
	app.set_preview("forest", "copper")
	_check(app.hair_id == "default" and app.effective_hair_id() == "copper", "live preview overrides effective_hair_id without changing hair_id")
	_check(app.outfit_id == "default" and app.effective_outfit_id() == "forest", "live preview overrides effective_outfit_id without changing outfit_id")
	var mat: ShaderMaterial = player.get_node("Sprite2D").material as ShaderMaterial
	var preview_hair_tint: Color = mat.get_shader_parameter("hair_tint") as Color
	var preview_outfit_tint: Color = mat.get_shader_parameter("outfit_tint") as Color
	_check(preview_hair_tint.is_equal_approx(Color.html("#c85436")), "shader hair_tint reflects previewed copper dye")
	_check(preview_outfit_tint.is_equal_approx(Color.html("#3e7d5e")), "shader outfit_tint reflects previewed forest dye")
	app.clear_preview()
	_check(app.effective_hair_id() == "default" and (mat.get_shader_parameter("hair_tint") as Color).is_equal_approx(Color.WHITE), "clear_preview restores default hair tint")
	_check(app.effective_outfit_id() == "default" and (mat.get_shader_parameter("outfit_tint") as Color).is_equal_approx(Color.WHITE), "clear_preview restores default outfit tint")

	# Build a salon in the town if not already present
	var salon_ids: Array[int] = town.built_ids("salon")
	if salon_ids.is_empty():
		var site: Vector2 = town._debug_site("salon", town.center + Vector2(60, 140))
		_check(site != Vector2.INF, "found free site for salon")
		var id: int = town.next_id
		town.next_id += 1
		town._rpc_added.rpc(id, {"p": "salon", "x": site.x, "y": site.y, "f": 0, "g": 0}, [])
		town._rpc_done.rpc(id)
		await _frames(10)
		salon_ids = town.built_ids("salon")
	_check(not salon_ids.is_empty(), "salon is built in town")

	var salon_seat: SalonSeat = null
	for seat: BenchSeat in town.seat_nodes():
		if seat is SalonSeat:
			salon_seat = seat as SalonSeat
			break
	_check(salon_seat != null, "salon spawned a SalonSeat")
	if salon_seat == null:
		print("SALON: FAILED (%d checks)" % _checks)
		get_tree().quit(1)
		return

	player.request_teleport(salon_seat.approach_position() + Vector2(0.0, 6.0))
	await _frames(30)
	_check(salon_seat.prompt() == "PLATZ NEHMEN", "salon seat prompt is PLATZ NEHMEN")

	var rest: RestComponent = player.get_node("RestComponent") as RestComponent
	rest.request_sit(salon_seat)
	var window: SalonWindow = null
	for i: int in 400:
		await get_tree().process_frame
		window = get_tree().get_first_node_in_group("salon_window") as SalonWindow
		if window != null and rest.state == RestComponent.State.IDLE:
			break
	_check(window != null and rest.state == RestComponent.State.IDLE, "sitting in salon opens SalonWindow")
	_check(InputManager.ui_blocking and player.story_lock, "InputManager.ui_blocking and story_lock active while seated in salon")

	if window != null:
		_check(window.tabs.size() == 3 and String(window.tabs[0].kind) == "hair" and String(window.tabs[1].kind) == "outfit" and String(window.tabs[2].kind) == "dye", "SalonWindow has FRISUR, OUTFIT, and FÄRBEN tabs")
		_check(window.rows.size() == 6 and String(window.rows[0].get("tag", "")) == "AKTIV", "FRISUR tab shows all 6 hairstyles with default AKTIV")

		# Preview and apply the special hairstyle Sternenschleier (moon_knot)
		var moon_idx: int = -1
		for idx_h: int in window.rows.size():
			if String(window.rows[idx_h].get("style_id", "")) == "moon_knot":
				moon_idx = idx_h
				_check(bool(window.rows[idx_h].get("special", false)) and String(window.rows[idx_h].get("sub", "")).contains("STERNENGLANZ"), "moon_knot row has STERNENGLANZ special badge")
				break
		_check(moon_idx > 0, "FRISUR tab contains moon_knot")
		if moon_idx > 0:
			window.focus = moon_idx
			await _frames(2)
			_check(app.effective_hair_id() == "moon_knot" and app.hair_id == "default", "focusing Sternenschleier previews moon_knot live")
			window._press("apply", false)
			await _frames(2)
			_check(app.hair_id == "moon_knot", "confirming ÜBERNEHMEN commits hair_id=moon_knot")

		# Switch to OUTFIT tab, verify Reisegewand + legendary Perlenblüte, preview & equip Perlenblüte, then restore default for dye check
		window._set_tab(1)
		await _frames(2)
		_check(window.rows.size() == 2 and String(window.rows[0].get("tag", "")) == "AKTIV", "OUTFIT tab shows Reisegewand (AKTIV) and Perlenblüte")
		_check(bool(window.rows[1].get("legendary", false)) and String(window.rows[1].get("sub", "")).contains("LEGENDÄR"), "Perlenblüte row has LEGENDÄR · FRÜHJAHR 2027 badge")
		window.focus = 1
		await _frames(2)
		_check(app.effective_outfit_id() == "perlenbluete" and app.outfit_id == "default", "focusing Perlenblüte previews perlenbluete live in mirror")
		window._press("apply", false)
		await _frames(2)
		_check(app.outfit_id == "perlenbluete", "confirming ÜBERNEHMEN commits outfit_id=perlenbluete")
		window.focus = 0
		await _frames(2)
		window._press("apply", false)
		await _frames(2)
		_check(app.outfit_id == "default", "switching back to Reisegewand commits outfit_id=default")

		# Switch to FÄRBEN tab and verify categorized sections (HAARE + OUTFIT)
		window._set_tab(2)
		await _frames(2)
		var expected_dye_rows: int = 2 + app.salon_hair_colors().size() + app.salon_outfit_colors().size()
		_check(window.rows.size() == expected_dye_rows, "FÄRBEN tab lists 2 category headers + hair and outfit colors (%d)" % window.rows.size())
		_check(window.focus == 1 and String(window.rows[window.focus].get("kind", "")) == "hair_color", "FÄRBEN skips section header on open and focuses first hair dye")

		# Find Sonnenblond hair dye, OUTFIT section header, and Waldläufer outfit dye
		var blonde_idx: int = -1
		var outfit_sec_idx: int = -1
		var forest_idx: int = -1
		for idx: int in window.rows.size():
			var k: String = String(window.rows[idx].get("kind", ""))
			var cid: String = String(window.rows[idx].get("color_id", ""))
			if k == "section" and String(window.rows[idx].get("section", "")) == "outfit":
				outfit_sec_idx = idx
			elif k == "hair_color" and cid == "blonde":
				blonde_idx = idx
			elif k == "outfit_color" and cid == "forest":
				forest_idx = idx
		_check(blonde_idx > 0 and outfit_sec_idx > blonde_idx and forest_idx > outfit_sec_idx, "both hair (Sonnenblond) and outfit (Waldläufer) dyes exist under their sections")
		if blonde_idx > 0:
			window.focus = blonde_idx
			await _frames(2)
			_check(app.effective_hair_id() == "moon_knot:blonde" and app.hair_id == "moon_knot", "focusing Sonnenblond previews moon_knot:blonde live without committing yet")
			window._press("apply", false)
			await _frames(2)
			_check(app.hair_id == "moon_knot:blonde", "confirming ÜBERNEHMEN commits hair_id=moon_knot:blonde")

		# Stepping across the OUTFIT section header lands on selectable outfit_color
		if outfit_sec_idx > 1 and forest_idx > outfit_sec_idx:
			window.focus = outfit_sec_idx - 1
			window._move(1)
			await _frames(2)
			_check(window.focus == outfit_sec_idx + 1 and String(window.rows[window.focus].get("kind", "")) == "outfit_color", "_move skips OUTFIT section header into outfit colors")
			window.focus = forest_idx
			await _frames(2)
			_check(app.effective_outfit_id() == "forest" and app.outfit_id == "default" and app.effective_hair_id() == "moon_knot:blonde", "focusing Waldläufer previews outfit dye while keeping hair moon_knot:blonde")
			window._press("apply", false)
			await _frames(2)
			_check(app.outfit_id == "forest" and app.hair_id == "moon_knot:blonde", "confirming ÜBERNEHMEN commits outfit_id=forest without altering hair")

		# Collapsing HAARE hides hair colors and shifts focus cleanly to outfit_color
		window._toggle_section("hair")
		await _frames(2)
		_check(window.rows.size() == 2 + app.salon_outfit_colors().size() and String(window.rows[window.focus].get("kind", "")) == "outfit_color", "collapsing HAARE section hides hair dyes and keeps valid focus")
		window._toggle_section("hair")
		await _frames(2)

		# Export/import roundtrip keeps both committed hair_id and outfit_id
		var saved: Dictionary = app.export_data()
		app.request_hair("default")
		app.request_outfit("default")
		app.import_data(saved)
		_check(app.hair_id == "moon_knot:blonde" and app.outfit_id == "forest", "appearance export/import keeps hairstyle + dye and outfit dye choices")

		# Closing SalonWindow stands Ellie back up cleanly
		window._close()
		for i: int in 300:
			await get_tree().process_frame
			if rest.state == RestComponent.State.FREE and not InputManager.ui_blocking and not player.story_lock:
				break
		_check(rest.state == RestComponent.State.FREE and not InputManager.ui_blocking and not player.story_lock, "closing SalonWindow stands Ellie up and unlocks input")

	print("SALON: ", "ok" if _ok else "FAILED", " (%d checks)" % _checks)
	get_tree().quit(0 if _ok else 1)
