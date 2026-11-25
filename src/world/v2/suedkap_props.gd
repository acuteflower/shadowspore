class_name SuedkapProps
extends RefCounted
## Atmospheric coastal harbor architecture for Zone 2: SÜDKAP (Sturmhafen).
## Places the stone breakwater causeway on Die Alte Mole framing the DungeonEntrance
## ("Das Fluttor von Sturmhafen"), the Hafenfeuer stone beacon tower, mooring bollards,
## weathered brass harbor lanterns, and the ruined stone walls of Die Alten Lagerhäuser.


class HarborBeacon extends Node2D:
	## Landmark beacon tower ("Hafenfeuer der Alten Mole") at [354, 256]
	var _time: float = 0.0
	var _light: NightLight = null

	func _ready() -> void:
		name = "SturmhafenBeacon"
		y_sort_enabled = true
		var body: StaticBody2D = StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cs: CollisionShape2D = CollisionShape2D.new()
		var rect: RectangleShape2D = RectangleShape2D.new()
		rect.size = Vector2(36.0, 20.0)
		cs.shape = rect
		cs.position = Vector2(0.0, -8.0)
		body.add_child(cs)
		add_child(body)

		_light = NightLight.new()
		_light.position = Vector2(0.0, -76.0)
		_light.radius = 135.0
		_light.squash = 0.72
		_light.base_energy = 0.95
		_light.pulse = 0.22
		_light.glow_color = Color("ffd27a")
		add_child(_light)

		var glow_node: _BeaconFlame = _BeaconFlame.new()
		glow_node.position = Vector2(0.0, -76.0)
		add_child(glow_node)

	func _process(delta: float) -> void:
		_time += delta

	func _draw() -> void:
		## Ground shadow (cool violet, never pure black)
		draw_rect(Rect2(-24.0, -6.0, 48.0, 12.0), Color(Color("141022"), 0.55))
		## Stepped Steinsetzer basalt base
		draw_rect(Rect2(-20.0, -24.0, 40.0, 24.0), Color("161a26"))
		draw_rect(Rect2(-19.0, -23.0, 38.0, 22.0), Color("283446"))
		draw_rect(Rect2(-19.0, -23.0, 38.0, 4.0), Color("465a74"))
		## Mid tapered stone shaft with moss & salt cracks
		draw_rect(Rect2(-15.0, -58.0, 30.0, 36.0), Color("161a26"))
		draw_rect(Rect2(-14.0, -57.0, 28.0, 34.0), Color("2e3c52"))
		draw_rect(Rect2(-14.0, -57.0, 10.0, 34.0), Color("3c4e68"))
		draw_rect(Rect2(6.0, -57.0, 8.0, 34.0), Color("202a3b"))
		## Turquoise Steinsetzer sea-rune bands
		draw_rect(Rect2(-11.0, -44.0, 22.0, 2.0), Color("357d8a"))
		draw_rect(Rect2(-11.0, -34.0, 22.0, 2.0), Color("357d8a"))
		## Crown gallery & iron fire-cage
		draw_rect(Rect2(-18.0, -66.0, 36.0, 9.0), Color("161a26"))
		draw_rect(Rect2(-17.0, -65.0, 34.0, 7.0), Color("41536b"))
		draw_rect(Rect2(-17.0, -65.0, 34.0, 2.0), Color("677f9e"))
		## Iron tripod bars around fire bowl
		draw_rect(Rect2(-10.0, -82.0, 2.0, 17.0), Color("1e2230"))
		draw_rect(Rect2(8.0, -82.0, 2.0, 17.0), Color("1e2230"))
		draw_rect(Rect2(-11.0, -84.0, 22.0, 3.0), Color("2d3448"))


class _BeaconFlame extends Node2D:
	var _t: float = 0.0

	func _ready() -> void:
		material = Unlit.material()
		z_index = 6

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var fl: float = 0.86 + 0.14 * sin(_t * 6.5)
		var sway: float = roundf(sin(_t * 4.2) * 1.5)
		draw_circle(Vector2(0.0, 0.0), 10.0 * fl, Color(Color("ffae42"), 0.25))
		draw_rect(Rect2(-5.0 + sway * 0.5, -5.0, 10.0, 9.0), Color("ff9e3d"))
		draw_rect(Rect2(-3.0 + sway, -9.0, 6.0, 11.0), Color("ffd97a"))
		draw_rect(Rect2(-1.0 + sway, -7.0, 2.0, 6.0), Color("fff7dc"))


class HarborLantern extends Node2D:
	var _t: float = 0.0
	var _light: NightLight = null
	var turquoise: bool = false

	func _ready() -> void:
		y_sort_enabled = true
		var body: StaticBody2D = StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cs: CollisionShape2D = CollisionShape2D.new()
		var rect: RectangleShape2D = RectangleShape2D.new()
		rect.size = Vector2(8.0, 8.0)
		cs.shape = rect
		cs.position = Vector2(0.0, -4.0)
		body.add_child(cs)
		add_child(body)

		_light = NightLight.new()
		_light.position = Vector2(4.0, -26.0)
		_light.radius = 78.0
		_light.squash = 0.72
		_light.base_energy = 0.72
		_light.pulse = 0.14
		_light.glow_color = Color("4df2e0") if turquoise else Color("ffcb72")
		add_child(_light)

		var orb: _LanternOrb = _LanternOrb.new()
		orb.position = Vector2(4.0, -24.0)
		orb.col = Color("4df2e0") if turquoise else Color("ffd980")
		add_child(orb)

	func _draw() -> void:
		draw_rect(Rect2(-5.0, -3.0, 10.0, 5.0), Color(Color("141022"), 0.5))
		draw_rect(Rect2(-3.0, -32.0, 6.0, 32.0), Color("161a26"))
		draw_rect(Rect2(-2.0, -31.0, 4.0, 30.0), Color("3c322c"))
		draw_rect(Rect2(-2.0, -31.0, 2.0, 30.0), Color("57493f"))
		draw_rect(Rect2(-1.0, -30.0, 8.0, 3.0), Color("283446"))


class _LanternOrb extends Node2D:
	var col: Color = Color("ffd980")
	var _t: float = 0.0

	func _ready() -> void:
		material = Unlit.material()
		z_index = 4

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var p: float = 0.85 + 0.15 * sin(_t * 4.5 + position.x)
		draw_circle(Vector2.ZERO, 6.0 * p, Color(col, 0.25))
		draw_rect(Rect2(-2.0, -2.0, 4.0, 5.0), col)
		draw_rect(Rect2(-1.0, -1.0, 2.0, 3.0), Color("fffaf0"))


class MoleBollard extends Node2D:
	func _ready() -> void:
		y_sort_enabled = true
		var body: StaticBody2D = StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cs: CollisionShape2D = CollisionShape2D.new()
		var rect: RectangleShape2D = RectangleShape2D.new()
		rect.size = Vector2(12.0, 10.0)
		cs.shape = rect
		cs.position = Vector2(0.0, -4.0)
		body.add_child(cs)
		add_child(body)

	func _draw() -> void:
		draw_rect(Rect2(-7.0, -3.0, 14.0, 6.0), Color(Color("141022"), 0.5))
		draw_rect(Rect2(-6.0, -14.0, 12.0, 14.0), Color("161a26"))
		draw_rect(Rect2(-5.0, -13.0, 10.0, 12.0), Color("36465c"))
		draw_rect(Rect2(-6.0, -16.0, 12.0, 4.0), Color("536985"))
		draw_rect(Rect2(-3.0, -8.0, 6.0, 2.0), Color("7d6442")) ## weathered rope coil


class MolePaving extends Node2D:
	## Flat ground flagstones along Die Alte Mole leading to the Fluttor
	var rect_size: Vector2 = Vector2(240.0, 120.0)

	func _ready() -> void:
		z_index = -2

	func _draw() -> void:
		var half: Vector2 = rect_size * 0.5
		draw_rect(Rect2(-half.x, -half.y, rect_size.x, rect_size.y), Color(Color("1c2434"), 0.72))
		var tile: float = 16.0
		var cols: int = int(rect_size.x / tile)
		var rows: int = int(rect_size.y / tile)
		for gy: int in rows:
			for gx: int in cols:
				var h: int = (gx * 73 + gy * 139) % 11
				if h == 0:
					continue
				var x: float = -half.x + float(gx) * tile + 1.0
				var y: float = -half.y + float(gy) * tile + 1.0
				var shade: Color = Color("314056") if (h % 3 == 0) else (Color("29364a") if (h % 2 == 0) else Color("3a4b63"))
				draw_rect(Rect2(x, y, tile - 2.0, tile - 2.0), Color(shade, 0.88))
				draw_rect(Rect2(x, y, tile - 2.0, 1.0), Color(Color("5d7391"), 0.42))


static func attach(stage: ZoneStage) -> void:
	if stage == null or stage.zone == null or stage.zone.id != &"suedkap":
		return
	var origin: Vector2 = Vector2(stage.zone.origin)
	var to_px := func(lx: float, ly: float) -> Vector2:
		return Atlas.px_of(origin + Vector2(lx, ly)).round()

	## 1. Stone breakwater flagstones on Die Alte Mole leading to Das Fluttor [372, 272]
	var paving: MolePaving = MolePaving.new()
	paving.name = "AlteMolePaving"
	paving.rect_size = Vector2(288.0, 160.0)
	paving.position = to_px.call(368.0, 274.0)
	stage.props_root.add_child(paving)

	## 2. Hafenfeuer der Alten Mole (lighthouse landmark at [354, 256])
	var beacon: HarborBeacon = HarborBeacon.new()
	beacon.position = to_px.call(354.0, 256.0)
	stage.props_root.add_child(beacon)

	## 3. Mooring bollards & harbor lanterns framing the approach to the Dungeon Gate [372, 272]
	var gate_px: Vector2 = to_px.call(372.0, 272.0)
	var lanterns: Array = [
		[gate_px + Vector2(-64.0, 14.0), true],
		[gate_px + Vector2(64.0, 14.0), true],
		[gate_px + Vector2(-92.0, 48.0), false],
		[gate_px + Vector2(46.0, 56.0), false],
		[to_px.call(246.0, 190.0) + Vector2(-46.0, 0.0), false],
		[to_px.call(246.0, 190.0) + Vector2(46.0, 0.0), false],
	]
	for i: int in lanterns.size():
		var lt: HarborLantern = HarborLantern.new()
		lt.name = "HarborLantern_%d" % i
		lt.position = (lanterns[i][0] as Vector2).round()
		lt.turquoise = bool(lanterns[i][1])
		stage.props_root.add_child(lt)

	var bollards: Array[Vector2] = [
		gate_px + Vector2(-52.0, 40.0),
		gate_px + Vector2(52.0, 40.0),
		gate_px + Vector2(-108.0, 10.0),
		gate_px + Vector2(88.0, -8.0),
		gate_px + Vector2(-24.0, 72.0),
		gate_px + Vector2(24.0, 72.0),
	]
	for i: int in bollards.size():
		var bol: MoleBollard = MoleBollard.new()
		bol.name = "MoleBollard_%d" % i
		bol.position = bollards[i].round()
		stage.props_root.add_child(bol)

	## 4. Ruined Stone-Setter walls at Die Alten Lagerhäuser ([346, 106]) & Alte Mole
	var ruins: Array = [
		["LagerParapetN", "sanctuary_parapet", to_px.call(344.0, 102.0), 0, false],
		["LagerParapetE", "sanctuary_parapet", to_px.call(354.0, 108.0), 0, true],
		["LagerColumn", "fallen_column_drum", to_px.call(340.0, 112.0), 1, false],
		["MoleWaymarker", "sanctuary_waymarker", gate_px + Vector2(-120.0, -24.0), 0, false],
	]
	for spec: Array in ruins:
		var sr: SanctuaryRuin = SanctuaryRuin.new()
		sr.name = String(spec[0])
		sr.setup_ruin(String(spec[1]), spec[2] as Vector2, int(spec[3]), bool(spec[4]))
		stage.props_root.add_child(sr)
