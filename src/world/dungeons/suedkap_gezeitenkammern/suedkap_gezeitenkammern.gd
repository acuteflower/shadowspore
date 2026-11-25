class_name SuedkapGezeitenkammern
extends DungeonScene
## Dungeon #1: Die Gezeitenkammern von Sturmhafen (docs/dungeon_konzept.md Section 6).
## Archetype II (Expedition, min_level = 5, 4 sections, 1-4P scaled):
##   1. Gebrochene Einfahrt      (4 ShadowSpiders warmup, overlook of flooded boss dock)
##   2. Westliches Wrackbecken   (2 VoidListeners + 2 ShadowSpiders, Secret Smuggler Alcove behind
##                                smashable planks, West Tide Bell wrapped in 3 spore tendrils ->
##                                ringing lowers tide_level 1.0 -> 0.5 & opens stairs to Section 3)
##   3. Alter Kranhof/Trockendock(1 VoidCrusher + 2 ShadowSpiders, East Weight Stone carried to
##                                East Winch -> opens Floodgate + ignites Checkpoint Rest Brazier)
##   4. Das Große Schleusenbecken(3 indestructible Steinsetzer wave bollards + Endboss Vorgath)

const SPIDER_SCENE: PackedScene = preload("res://src/entities/enemies/shadow_spider.tscn")
const LISTENER_SCENE: PackedScene = preload("res://src/entities/enemies/void_listener.tscn")
const CRUSHER_SCENE: PackedScene = preload("res://src/entities/enemies/void_crusher.tscn")
const VORGATH_SCENE: PackedScene = preload("res://src/entities/enemies/dungeon_boss/vorgath_boss.tscn")
const TIDE_SHADER: Shader = preload("res://assets/shaders/tide_water.gdshader")

const TEX_BOLLARD: Texture2D = preload("res://assets/dungeons/sturmhafen/bollard.png")
const TEX_BOLLARD_GLOW: Texture2D = preload("res://assets/dungeons/sturmhafen/bollard_glow.png")
const TEX_BELL: Texture2D = preload("res://assets/dungeons/sturmhafen/tide_bell.png")
const TEX_BELL_GLOW: Texture2D = preload("res://assets/dungeons/sturmhafen/tide_bell_glow.png")
const TEX_STONE: Texture2D = preload("res://assets/dungeons/sturmhafen/weight_stone.png")
const TEX_STONE_GLOW: Texture2D = preload("res://assets/dungeons/sturmhafen/weight_stone_glow.png")
const TEX_WINCH: Texture2D = preload("res://assets/dungeons/sturmhafen/winch.png")
const TEX_WINCH_GLOW: Texture2D = preload("res://assets/dungeons/sturmhafen/winch_glow.png")
const TEX_BRAZIER: Texture2D = preload("res://assets/dungeons/sturmhafen/brazier.png")
const TEX_BRAZIER_GLOW: Texture2D = preload("res://assets/dungeons/sturmhafen/brazier_glow.png")
const TEX_PLANKS: Texture2D = preload("res://assets/dungeons/sturmhafen/planks.png")

const ARENA_CENTER_LOCAL: Vector2 = Vector2(0.0, -210.0)
const BOLLARD_LOCAL_POSITIONS: Array[Vector2] = [
	Vector2(-104.0, -225.0),
	Vector2(0.0, -255.0),
	Vector2(104.0, -225.0),
]

## Section state (host truth, mirrored to peers)
var tide_level: float = 1.0
var _target_tide: float = 1.0
var section1_cleared: bool = false
var tendrils_cut: int = 0
var bell_rung: bool = false
var stone_carrier_peer: int = 0
var floodgate_open: bool = false
var brazier_lit: bool = false
var boss_started: bool = false
var planks_broken: bool = false
var smuggler_looted: bool = false

var vorgath: VorgathBoss = null
var _water_mat: ShaderMaterial = null
var _water_rect: ColorRect = null
var _backdrop: _ChamberBackdrop = null
var _gate_west: StaticBody2D = null
var _gate_east_stairs: StaticBody2D = null
var _gate_flood: StaticBody2D = null
var _gate_boss_seal: StaticBody2D = null
var _gate_west_vis: _GateVisual = null
var _gate_stairs_vis: _GateVisual = null
var _gate_flood_vis: _GateVisual = null
var _gate_boss_vis: _GateVisual = null
var _tide_bell: _TideBellNode = null
var _weight_stone: _WeightStoneNode = null
var _east_winch: _EastWinchNode = null
var _brazier_node: _RestBrazierNode = null
var _planks_node: _SmugglerPlanks = null
var _smuggler_chest: _SmugglerChest = null
var _s1_enemies: Array[Node] = []
var _tendrils: Array[Node] = []
var _enemies_root: Node2D = null
var _props_root: Node2D = null


# --- Visual & Interactive Helper Classes -----------------------------------------------------------------------------

class _ChamberBackdrop extends Node2D:
	## Draws the entire carved basalt dungeon floorplan, wooden docks, ship ribs, arches & sea breach.
	var dungeon: SuedkapGezeitenkammern = null

	func _ready() -> void:
		z_index = -6

	func _draw() -> void:
		## Outer abyssal stone rim framing the tidal basin (leaves inner -680..-380..1360x980 open for TideWater!)
		var rim: Color = Color("0a0d18")
		draw_rect(Rect2(-960, -640, 1920, 260), rim)
		draw_rect(Rect2(-960, 600, 1920, 240), rim)
		draw_rect(Rect2(-960, -380, 280, 980), rim)
		draw_rect(Rect2(680, -380, 280, 980), rim)
		## Carved basalt cavern walls bordering the water
		var wall_c: Color = Color("1b2436")
		draw_rect(Rect2(-712, -412, 1424, 34), wall_c)
		draw_rect(Rect2(-712, 588, 1424, 34), wall_c)
		draw_rect(Rect2(-712, -412, 34, 1034), wall_c)
		draw_rect(Rect2(678, -412, 34, 1034), wall_c)

		## Section 1: Gebrochene Einfahrt (south stone platform)
		_draw_flagstones(Rect2(-340, 400, 680, 190), Color("2b384e"), Color("3a4b66"))
		## Central overlook balcony protruding slightly toward the flooded boss dock
		_draw_flagstones(Rect2(-120, 320, 240, 90), Color("32425c"), Color("485d7d"))

		## Section 2: Westliches Wrackbecken (weathered timber dock & bell pier)
		_draw_timber_deck(Rect2(-640, 120, 360, 310))
		## Connecting gangway S1 -> S2
		_draw_timber_deck(Rect2(-340, 360, 80, 80))
		## Secret Smuggler Alcove (SW corner behind planks)
		_draw_flagstones(Rect2(-650, 310, 100, 110), Color("242e42"), Color("36465e"))
		## West Tide Bell Stone Dais
		_draw_flagstones(Rect2(-530, 130, 120, 96), Color("33435c"), Color("4c6382"))

		## Flooded Center-East Causeway (Section 2 -> Section 3, revealed when tide drops to 0.5!)
		var causeway_col: Color = Color("364963") if (dungeon != null and dungeon.bell_rung) else Color("162b3d")
		_draw_flagstones(Rect2(-280, 180, 540, 84), causeway_col, causeway_col.lightened(0.15))

		## Section 3: Alter Kranhof & Trockendock (east basin)
		_draw_flagstones(Rect2(250, 120, 390, 310), Color("2c394f"), Color("3d4f6b"))
		## Broken ship hull ribs in drydock
		for ry: float in [200.0, 250.0, 300.0, 350.0]:
			draw_rect(Rect2(560, ry, 54, 10), Color("4a3234"))
			draw_rect(Rect2(560, ry, 54, 3), Color("7a564c"))
			draw_rect(Rect2(280, ry + 20, 42, 9), Color("4a3234"))

		## Approach Ramp & Checkpoint Landing (Center North, y: -60..190)
		_draw_flagstones(Rect2(-96, -70, 192, 260), Color("32425a"), Color("4c6282"))

		## Section 4: Das Große Schleusenbecken (360x280 Boss Arena centered at (0, -210))
		_draw_flagstones(Rect2(-190, -350, 380, 290), Color("26344a"), Color("394c68"))
		## Carved Steinsetzer boss arena floor emblem
		draw_arc(ARENA_CENTER_LOCAL, 96.0, 0.0, TAU, 48, Color(Color("4df2e0"), 0.22), 2.0)
		draw_arc(ARENA_CENTER_LOCAL, 52.0, 0.0, TAU, 36, Color(Color("4df2e0"), 0.16), 1.5)
		## Broken Northern Sea-Gate breach letting stormy ocean surf into the arena
		draw_rect(Rect2(-110, -405, 220, 60), Color("103045"))
		draw_rect(Rect2(-102, -395, 204, 45), Color(Color("2c8f9c"), 0.45))

	func _draw_flagstones(r: Rect2, base_col: Color, hi_col: Color) -> void:
		draw_rect(r, Color("141926"))
		draw_rect(r.grow(-2.0), base_col)
		var step: float = 24.0
		var y: float = r.position.y + 4.0
		while y < r.end.y - 6.0:
			var x: float = r.position.x + 4.0
			while x < r.end.x - 6.0:
				var h: int = (int(x) * 31 + int(y) * 57) % 7
				if h != 0:
					var c: Color = hi_col if h == 1 else base_col.lightened(0.05 if h % 2 == 0 else -0.05)
					draw_rect(Rect2(x, y, step - 3.0, step - 3.0), c)
					draw_rect(Rect2(x, y, step - 3.0, 1.0), Color(Color("7d98b8"), 0.22))
				x += step
			y += step

	func _draw_timber_deck(r: Rect2) -> void:
		draw_rect(r, Color("201520"))
		draw_rect(r.grow(-2.0), Color("4a3134"))
		var y: float = r.position.y + 3.0
		while y < r.end.y - 4.0:
			draw_rect(Rect2(r.position.x + 3.0, y, r.size.x - 6.0, 7.0), Color("5d3f3c"))
			draw_rect(Rect2(r.position.x + 3.0, y, r.size.x - 6.0, 1.0), Color("886153"))
			y += 9.0


class _GateVisual extends Node2D:
	var rect_size: Vector2 = Vector2(20, 80)
	var accent: Color = Color("4df2e0")
	var label_text: String = ""
	var open: bool = false

	func set_open(on: bool) -> void:
		open = on
		visible = not on
		queue_redraw()

	func _draw() -> void:
		if open:
			return
		var h: Vector2 = rect_size * 0.5
		draw_rect(Rect2(-h, rect_size), Color("161c2c"))
		draw_rect(Rect2(-h, rect_size).grow(-2.0), Color("2c3a50"))
		draw_rect(Rect2(-h.x + 2.0, -h.y + 2.0, rect_size.x - 4.0, 3.0), accent)
		if not label_text.is_empty():
			var w: int = PixelText.width(label_text)
			PixelText.draw(self, label_text, Vector2i(-w / 2, -4), Color("e8ffff"), Color("0a0d18"))


class _SporeTendril extends Node2D:
	signal severed()
	var health: HealthComponent = null
	var _t: float = 0.0

	func _ready() -> void:
		y_sort_enabled = true
		add_to_group("enemies")
		health = HealthComponent.new()
		health.name = "HealthComponent"
		health.max_health = 45.0
		health.current = 45.0
		add_child(health)
		health.died.connect(_on_died)

		var hb: HurtboxComponent = HurtboxComponent.new()
		hb.name = "HurtboxComponent"
		hb.health = health
		hb.collision_layer = 16
		hb.collision_mask = 0
		var cs: CollisionShape2D = CollisionShape2D.new()
		var circ: CircleShape2D = CircleShape2D.new()
		circ.radius = 16.0
		cs.shape = circ
		cs.position = Vector2(0.0, -10.0)
		hb.add_child(cs)
		add_child(hb)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _on_died() -> void:
		severed.emit()
		queue_free()

	func _draw() -> void:
		var sway: float = sin(_t * 4.5 + position.x) * 3.0
		draw_line(Vector2.ZERO, Vector2(sway, -22.0), Color("160b24"), 7.0)
		draw_line(Vector2.ZERO, Vector2(sway, -22.0), Color("5b288a"), 4.0)
		draw_circle(Vector2(sway, -22.0), 5.0, Color("ff4fd8"))
		draw_circle(Vector2(sway, -22.0), 2.5, Color("ffd6f8"))


class _SmugglerPlanks extends Node2D:
	signal broken()
	var health: HealthComponent = null

	func _ready() -> void:
		y_sort_enabled = true
		var body: StaticBody2D = StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cs: CollisionShape2D = CollisionShape2D.new()
		var rect: RectangleShape2D = RectangleShape2D.new()
		rect.size = Vector2(46.0, 22.0)
		cs.shape = rect
		cs.position = Vector2(0.0, -8.0)
		body.add_child(cs)
		add_child(body)

		var spr: Sprite2D = Sprite2D.new()
		spr.texture = TEX_PLANKS
		spr.offset = Vector2(0.0, -14.0)
		add_child(spr)

		health = HealthComponent.new()
		health.name = "HealthComponent"
		health.max_health = 35.0
		health.current = 35.0
		add_child(health)
		health.died.connect(_on_died)

		var hb: HurtboxComponent = HurtboxComponent.new()
		hb.name = "HurtboxComponent"
		hb.health = health
		hb.collision_layer = 16
		hb.collision_mask = 0
		var hcs: CollisionShape2D = CollisionShape2D.new()
		var hrect: RectangleShape2D = RectangleShape2D.new()
		hrect.size = Vector2(48.0, 28.0)
		hcs.shape = hrect
		hcs.position = Vector2(0.0, -10.0)
		hb.add_child(hcs)
		add_child(hb)

	func _on_died() -> void:
		broken.emit()
		queue_free()


class _SmugglerChest extends Interactable:
	var dungeon: SuedkapGezeitenkammern = null
	var opened: bool = false

	func _ready() -> void:
		y_sort_enabled = true

	func prompt() -> String:
		return "" if opened else "SCHMUGGLER-TRUHE ÖFFNEN"

	func reach_distance(from: Vector2) -> float:
		return maxf(0.0, global_position.distance_to(from) - 20.0)

	func interact(player: Player) -> void:
		if opened or dungeon == null:
			return
		dungeon.request_open_smuggler_chest(player)

	func _draw() -> void:
		draw_rect(Rect2(-12, -16, 24, 16), Color("161224"))
		draw_rect(Rect2(-11, -15, 22, 14), Color("5e452c") if not opened else Color("38291e"))
		draw_rect(Rect2(-11, -15, 22, 4), Color("c9a25e") if not opened else Color("5e452c"))
		if not opened:
			draw_rect(Rect2(-2, -10, 4, 4), Color("4df2e0"))


class _TideBellNode extends Interactable:
	var dungeon: SuedkapGezeitenkammern = null

	func _ready() -> void:
		y_sort_enabled = true
		var spr: Sprite2D = Sprite2D.new()
		spr.texture = TEX_BELL
		spr.offset = Vector2(0.0, -24.0)
		add_child(spr)
		var gspr: Sprite2D = Sprite2D.new()
		gspr.texture = TEX_BELL_GLOW
		gspr.material = Unlit.material()
		gspr.offset = Vector2(0.0, -24.0)
		add_child(gspr)
		var lt: NightLight = NightLight.new()
		lt.position = Vector2(0.0, -24.0)
		lt.radius = 90.0
		lt.base_energy = 0.75
		lt.glow_color = Color("4df2e0")
		add_child(lt)

	func prompt() -> String:
		if dungeon == null or dungeon.bell_rung:
			return ""
		if dungeon.tendrils_cut < 3:
			return "GEZEITENGLOCKE (ÜBERWUCHERT %d/3)" % dungeon.tendrils_cut
		return "GEZEITENGLOCKE LÄUTEN"

	func prompt_hint() -> String:
		if dungeon != null and not dungeon.bell_rung and dungeon.tendrils_cut < 3:
			return "ZERHACK DIE 3 SPORENRANKEN!"
		return ""

	func reach_distance(from: Vector2) -> float:
		return maxf(0.0, global_position.distance_to(from) - 28.0)

	func prompt_position() -> Vector2:
		return Vector2(0.0, -54.0)

	func interact(_player: Player) -> void:
		if dungeon != null and dungeon.tendrils_cut >= 3 and not dungeon.bell_rung:
			dungeon.request_ring_bell()


class _WeightStoneNode extends Interactable:
	var dungeon: SuedkapGezeitenkammern = null
	var slotted: bool = false

	func _ready() -> void:
		y_sort_enabled = true
		var spr: Sprite2D = Sprite2D.new()
		spr.texture = TEX_STONE
		spr.offset = Vector2(0.0, -10.0)
		add_child(spr)
		var gspr: Sprite2D = Sprite2D.new()
		gspr.texture = TEX_STONE_GLOW
		gspr.material = Unlit.material()
		gspr.offset = Vector2(0.0, -10.0)
		add_child(gspr)

	func prompt() -> String:
		if dungeon == null or slotted or dungeon.floodgate_open:
			return ""
		if dungeon.stone_carrier_peer != 0:
			return ""
		return "RESONANZ-GEWICHTSSTEIN AUFHEBEN"

	func reach_distance(from: Vector2) -> float:
		return maxf(0.0, global_position.distance_to(from) - 22.0)

	func interact(player: Player) -> void:
		if dungeon != null and player != null:
			dungeon.request_pickup_stone(player.get_multiplayer_authority())


class _EastWinchNode extends Interactable:
	var dungeon: SuedkapGezeitenkammern = null

	func _ready() -> void:
		y_sort_enabled = true
		var spr: Sprite2D = Sprite2D.new()
		spr.texture = TEX_WINCH
		spr.offset = Vector2(0.0, -20.0)
		add_child(spr)
		var gspr: Sprite2D = Sprite2D.new()
		gspr.texture = TEX_WINCH_GLOW
		gspr.material = Unlit.material()
		gspr.offset = Vector2(0.0, -20.0)
		add_child(gspr)
		var lt: NightLight = NightLight.new()
		lt.position = Vector2(0.0, -16.0)
		lt.radius = 78.0
		lt.base_energy = 0.65
		lt.glow_color = Color("4df2e0")
		add_child(lt)

	func prompt() -> String:
		if dungeon == null or dungeon.floodgate_open:
			return ""
		if dungeon.stone_carrier_peer != 0:
			return "GEWICHTSSTEIN IN OST-WINDE EINSETZEN"
		return "OST-WINDE (GEWICHTSSTEIN FEHLT)"

	func prompt_hint() -> String:
		if dungeon != null and not dungeon.floodgate_open and dungeon.stone_carrier_peer == 0:
			return "HOLE DEN RESONANZ-GEWICHTSSTEIN IM TROCKENDOCK"
		return ""

	func reach_distance(from: Vector2) -> float:
		return maxf(0.0, global_position.distance_to(from) - 30.0)

	func prompt_position() -> Vector2:
		return Vector2(0.0, -44.0)

	func interact(player: Player) -> void:
		if dungeon != null and player != null and dungeon.stone_carrier_peer == player.get_multiplayer_authority():
			dungeon.request_slot_stone()


class _RestBrazierNode extends Interactable:
	var dungeon: SuedkapGezeitenkammern = null
	var lit: bool = false
	var _light: NightLight = null
	var _glow: Sprite2D = null

	func _ready() -> void:
		y_sort_enabled = true
		var spr: Sprite2D = Sprite2D.new()
		spr.texture = TEX_BRAZIER
		spr.offset = Vector2(0.0, -16.0)
		add_child(spr)
		_glow = Sprite2D.new()
		_glow.texture = TEX_BRAZIER_GLOW
		_glow.material = Unlit.material()
		_glow.offset = Vector2(0.0, -16.0)
		_glow.visible = false
		add_child(_glow)
		_light = NightLight.new()
		_light.position = Vector2(0.0, -18.0)
		_light.radius = 110.0
		_light.base_energy = 0.0
		_light.glow_color = Color("ffcb72")
		add_child(_light)

	func set_lit(on: bool) -> void:
		lit = on
		if _glow != null:
			_glow.visible = on
		if _light != null:
			_light.base_energy = 0.88 if on else 0.0

	func prompt() -> String:
		return "AM RASTFEUER VERSCHNAUFEN" if lit else ""

	func reach_distance(from: Vector2) -> float:
		return maxf(0.0, global_position.distance_to(from) - 24.0)

	func interact(player: Player) -> void:
		if lit and player != null and dungeon != null:
			dungeon.request_heal_at_brazier(player.get_multiplayer_authority())


# --- DungeonScene Lifecycle ------------------------------------------------------------------------------------------

func _ready() -> void:
	dungeon_id = "suedkap_gezeitenkammern"
	boss_title = "VORGATH, BRUT DER MOLE"
	bounds_local = Rect2(-720.0, -420.0, 1440.0, 1060.0)
	start_spawn_local = Vector2(0.0, 510.0)
	checkpoint_local = start_spawn_local
	y_sort_enabled = true
	_build_chamber_geometry()
	_build_interactables_and_bollards()
	if multiplayer.is_server():
		_spawn_section1_pack()
		_spawn_section2_pack()
		_spawn_section3_pack()
		_spawn_vorgath()
		set_objective("RÄUME DIE GEBROCHENE EINFAHRT (0/4)", 0.0)


func _build_chamber_geometry() -> void:
	_backdrop = _ChamberBackdrop.new()
	_backdrop.dungeon = self
	add_child(_backdrop)

	## Animated tidal water sheet (covers flooded sub-basin)
	_water_rect = ColorRect.new()
	_water_rect.name = "TideWater"
	_water_rect.position = Vector2(-680.0, -380.0)
	_water_rect.size = Vector2(1360.0, 980.0)
	_water_rect.z_index = -8
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = TIDE_SHADER
	_water_mat.set_shader_parameter("tide_level", 1.0)
	_water_mat.set_shader_parameter("tex_size", Vector2(1360.0, 980.0))
	_water_rect.material = _water_mat
	add_child(_water_rect)

	## Perimeter collision walls (layer 1)
	var walls: StaticBody2D = StaticBody2D.new()
	walls.name = "ChamberWalls"
	walls.collision_layer = 1
	walls.collision_mask = 0
	var wall_boxes: Array[Rect2] = [
		Rect2(-720, -420, 1440, 68),   ## North wall
		Rect2(-720, 588, 1440, 52),    ## South wall
		Rect2(-720, -420, 64, 1060),   ## West wall
		Rect2(656, -420, 64, 1060),    ## East wall
		## Inner dividing piers framing the Boss Arena & Wings
		Rect2(-660, -360, 470, 480),   ## NW solid rock mass above West Wrackbecken
		Rect2(190, -360, 470, 480),    ## NE solid rock mass above East Kranhof
	]
	for wb: Rect2 in wall_boxes:
		var cs: CollisionShape2D = CollisionShape2D.new()
		var rshape: RectangleShape2D = RectangleShape2D.new()
		rshape.size = wb.size
		cs.shape = rshape
		cs.position = wb.get_center()
		walls.add_child(cs)
	add_child(walls)

	## Dynamic section gates (toggled open as player progresses)
	_gate_west = _make_gate("GateWest", Vector2(-318.0, 400.0), Vector2(18.0, 84.0), "EINFAHRT")
	_gate_west_vis = _gate_west.get_node("Vis") as _GateVisual
	_gate_east_stairs = _make_gate("GateStairs", Vector2(236.0, 222.0), Vector2(18.0, 88.0), "ÜBERFLUTET")
	_gate_stairs_vis = _gate_east_stairs.get_node("Vis") as _GateVisual
	_gate_flood = _make_gate("GateFlood", Vector2(0.0, 96.0), Vector2(196.0, 22.0), "SCHLEUSENTOR")
	_gate_flood_vis = _gate_flood.get_node("Vis") as _GateVisual
	_gate_boss_seal = _make_gate("GateBossSeal", Vector2(0.0, -64.0), Vector2(196.0, 18.0), "")
	_gate_boss_vis = _gate_boss_seal.get_node("Vis") as _GateVisual
	_set_gate_open(_gate_boss_seal, _gate_boss_vis, true) ## open until boss wakes

	## Ambient coastal chamber lanterns
	var lights: Array = [
		[Vector2(-120, 490), Color("ffcb72"), 120.0],
		[Vector2(120, 490), Color("ffcb72"), 120.0],
		[Vector2(-470, 240), Color("4df2e0"), 140.0],
		[Vector2(430, 250), Color("4df2e0"), 140.0],
		[Vector2(0, -210), Color("4df2e0"), 220.0],
		[Vector2(0, -340), Color("68d8ff"), 160.0],
	]
	for ls: Array in lights:
		var lt: NightLight = NightLight.new()
		lt.position = ls[0] as Vector2
		lt.glow_color = ls[1] as Color
		lt.radius = float(ls[2])
		lt.base_energy = 0.82
		lt.pulse = 0.12
		add_child(lt)

	_props_root = Node2D.new()
	_props_root.name = "Props"
	_props_root.y_sort_enabled = true
	add_child(_props_root)

	_enemies_root = Node2D.new()
	_enemies_root.name = "Enemies"
	_enemies_root.y_sort_enabled = true
	add_child(_enemies_root)


func _make_gate(gname: String, pos: Vector2, gsize: Vector2, lbl: String) -> StaticBody2D:
	var sb: StaticBody2D = StaticBody2D.new()
	sb.name = gname
	sb.position = pos
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs: CollisionShape2D = CollisionShape2D.new()
	cs.name = "Shape"
	var r: RectangleShape2D = RectangleShape2D.new()
	r.size = gsize
	cs.shape = r
	sb.add_child(cs)
	var vis: _GateVisual = _GateVisual.new()
	vis.name = "Vis"
	vis.rect_size = gsize
	vis.label_text = lbl
	sb.add_child(vis)
	add_child(sb)
	return sb


func _set_gate_open(sb: StaticBody2D, vis: _GateVisual, open: bool) -> void:
	if sb == null:
		return
	var cs: CollisionShape2D = sb.get_node_or_null("Shape") as CollisionShape2D
	if cs != null:
		cs.set_deferred("disabled", open)
	if vis != null:
		vis.set_open(open)


func _build_interactables_and_bollards() -> void:
	## Section 2: Secret Smuggler Alcove (planks + chest)
	_planks_node = _SmugglerPlanks.new()
	_planks_node.name = "SmugglerPlanks"
	_planks_node.position = Vector2(-556.0, 358.0)
	_planks_node.broken.connect(_on_planks_broken)
	_props_root.add_child(_planks_node)

	_smuggler_chest = _SmugglerChest.new()
	_smuggler_chest.name = "SmugglerChest"
	_smuggler_chest.dungeon = self
	_smuggler_chest.position = Vector2(-608.0, 368.0)
	_props_root.add_child(_smuggler_chest)

	## Section 2: West Tide Bell + 3 Spore Tendrils
	_tide_bell = _TideBellNode.new()
	_tide_bell.name = "WestTideBell"
	_tide_bell.dungeon = self
	_tide_bell.position = Vector2(-470.0, 178.0)
	_props_root.add_child(_tide_bell)

	var tendril_offs: Array[Vector2] = [Vector2(-26.0, 10.0), Vector2(26.0, 10.0), Vector2(0.0, 24.0)]
	for i: int in tendril_offs.size():
		var td: _SporeTendril = _SporeTendril.new()
		td.name = "SporeTendril_%d" % i
		td.position = _tide_bell.position + tendril_offs[i]
		td.severed.connect(_on_tendril_severed)
		_props_root.add_child(td)
		_tendrils.append(td)

	## Section 3: East Resonance Weight Stone & Winch
	_weight_stone = _WeightStoneNode.new()
	_weight_stone.name = "ResonanceWeightStone"
	_weight_stone.dungeon = self
	_weight_stone.position = Vector2(510.0, 316.0)
	_props_root.add_child(_weight_stone)

	_east_winch = _EastWinchNode.new()
	_east_winch.name = "EastWinch"
	_east_winch.dungeon = self
	_east_winch.position = Vector2(365.0, 174.0)
	_props_root.add_child(_east_winch)

	## Checkpoint Rest Brazier right before Floodgate / Boss Arena
	_brazier_node = _RestBrazierNode.new()
	_brazier_node.name = "CheckpointBrazier"
	_brazier_node.dungeon = self
	_brazier_node.position = Vector2(0.0, 148.0)
	_props_root.add_child(_brazier_node)

	## Section 4: 3 Indestructible Steinsetzer Wave-Bollards!
	for i: int in BOLLARD_LOCAL_POSITIONS.size():
		var b: Node2D = Node2D.new()
		b.name = "SteinsetzerBollard_%d" % i
		b.position = BOLLARD_LOCAL_POSITIONS[i]
		b.y_sort_enabled = true
		var sb: StaticBody2D = StaticBody2D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		var cs: CollisionShape2D = CollisionShape2D.new()
		var circ: CircleShape2D = CircleShape2D.new()
		circ.radius = 12.0
		cs.shape = circ
		cs.position = Vector2(0.0, -5.0)
		sb.add_child(cs)
		b.add_child(sb)
		var spr: Sprite2D = Sprite2D.new()
		spr.texture = TEX_BOLLARD
		spr.offset = Vector2(0.0, -18.0)
		b.add_child(spr)
		var gspr: Sprite2D = Sprite2D.new()
		gspr.texture = TEX_BOLLARD_GLOW
		gspr.material = Unlit.material()
		gspr.offset = Vector2(0.0, -18.0)
		b.add_child(gspr)
		_props_root.add_child(b)


# --- Enemy Spawning & Section Progression (Host-Authoritative) -------------------------------------------------------

func _spawn_enemy(scene: PackedScene, local_pos: Vector2, track_arr: Array[Node] = []) -> Node2D:
	if scene == null:
		return null
	var n: Node2D = scene.instantiate() as Node2D
	if n == null:
		return null
	n.position = local_pos
	_enemies_root.add_child(n)
	var hp_c: HealthComponent = n.get_node_or_null("HealthComponent") as HealthComponent
	if hp_c != null:
		var scale: float = DungeonRules.hp_scale(player_count)
		hp_c.max_health = roundf(hp_c.max_health * scale)
		hp_c.current = hp_c.max_health
	if not track_arr.is_empty() or track_arr == _s1_enemies:
		track_arr.append(n)
	return n


func _spawn_section1_pack() -> void:
	var pts: Array[Vector2] = [Vector2(-110, 460), Vector2(-35, 440), Vector2(45, 445), Vector2(120, 465)]
	for pt: Vector2 in pts:
		var sp: Node2D = _spawn_enemy(SPIDER_SCENE, pt, _s1_enemies)
		if sp != null:
			var hc: HealthComponent = sp.get_node_or_null("HealthComponent") as HealthComponent
			if hc != null:
				hc.died.connect(_on_s1_enemy_died)


func _spawn_section2_pack() -> void:
	_spawn_enemy(LISTENER_SCENE, Vector2(-430, 320))
	_spawn_enemy(LISTENER_SCENE, Vector2(-510, 260))
	_spawn_enemy(SPIDER_SCENE, Vector2(-380, 240))
	_spawn_enemy(SPIDER_SCENE, Vector2(-490, 350))


func _spawn_section3_pack() -> void:
	_spawn_enemy(CRUSHER_SCENE, Vector2(420, 270))
	_spawn_enemy(SPIDER_SCENE, Vector2(340, 310))
	_spawn_enemy(SPIDER_SCENE, Vector2(490, 220))


func _spawn_vorgath() -> void:
	vorgath = VORGATH_SCENE.instantiate() as VorgathBoss
	vorgath.position = ARENA_CENTER_LOCAL + Vector2(0.0, -48.0)
	_enemies_root.add_child(vorgath)
	var world_bollards: Array[Vector2] = []
	for lp: Vector2 in BOLLARD_LOCAL_POSITIONS:
		world_bollards.append(global_position + lp)
	vorgath.setup_encounter(global_position + ARENA_CENTER_LOCAL, world_bollards, self, player_count)
	vorgath.boss_defeated.connect(_on_vorgath_defeated)


func _on_s1_enemy_died() -> void:
	if section1_cleared or not multiplayer.is_server():
		return
	var dead_cnt: int = 0
	for n: Node in _s1_enemies:
		if not is_instance_valid(n):
			dead_cnt += 1
		else:
			var hc: HealthComponent = n.get_node_or_null("HealthComponent") as HealthComponent
			if hc == null or hc.current <= 0.0:
				dead_cnt += 1
	if dead_cnt >= _s1_enemies.size():
		section1_cleared = true
		_sync_gate_state("west", true)
		set_objective("LÄUTE DIE WEST-GEZEITENGLOCKE (0/3 RANKEN)", 0.20)
	else:
		set_objective("RÄUME DIE GEBROCHENE EINFAHRT (%d/%d)" % [dead_cnt, _s1_enemies.size()], float(dead_cnt) / float(maxi(_s1_enemies.size(), 1)) * 0.2)


func _on_planks_broken() -> void:
	planks_broken = true
	_play_sfx("vorgath_slam", -4.0)


func request_open_smuggler_chest(player: Player) -> void:
	if not multiplayer.is_server() or smuggler_looted:
		return
	smuggler_looted = true
	if _smuggler_chest != null:
		_smuggler_chest.opened = true
		_smuggler_chest.queue_redraw()
	if player != null and player.inventory != null:
		player.inventory.give("iron_ingot", 2)
		player.inventory.give("ember_berry", 3)
		player.inventory.give("void_splinter", 4)
	if player != null and player.progress != null:
		player.progress.award(45, 35)
	_play_sfx("victory_fanfare", -5.0)
	_announce("SCHMUGGLERVERSTECK GEPLÜNDERT!")


func _on_tendril_severed() -> void:
	if not multiplayer.is_server():
		return
	tendrils_cut += 1
	if tendrils_cut >= 3 and not bell_rung:
		## Ambush when the bell is freed!
		_spawn_enemy(SPIDER_SCENE, Vector2(-520, 210))
		_spawn_enemy(SPIDER_SCENE, Vector2(-420, 210))
		_spawn_enemy(SPIDER_SCENE, Vector2(-470, 250))
		set_objective("LÄUTE DIE WEST-GEZEITENGLOCKE [E]", 0.40)
		_announce("DIE RANKEN SIND DURCHTRENNT! LÄUTE DIE GEZEITENGLOCKE!")
	elif not bell_rung:
		set_objective("DURCHTRENNE DIE SPORENRANKEN (%d/3)" % tendrils_cut, 0.20 + float(tendrils_cut) * 0.06)


func request_ring_bell() -> void:
	if not multiplayer.is_server() or bell_rung or tendrils_cut < 3:
		return
	bell_rung = true
	_target_tide = 0.5
	_sync_gate_state("stairs", true)
	_play_sfx("tide_bell", 1.5)
	for p: Player in Player.all:
		if p.is_multiplayer_authority():
			p.add_shake(5.0)
	set_objective("BRINGE DEN GEWICHTSSTEIN ZUR OST-WINDE", 0.55)
	_announce("DER PEGEL SINKT! DER WEG ZUM OST-TROCKENDOCK IST FREI!")


func request_pickup_stone(peer_id: int) -> void:
	if not multiplayer.is_server() or floodgate_open or stone_carrier_peer != 0:
		return
	stone_carrier_peer = peer_id
	## Small escort pressure wave
	var wave_n: int = 2 if player_count == 1 else 3
	for i: int in wave_n:
		_spawn_enemy(SPIDER_SCENE, Vector2(410.0 + float(i) * 45.0, 240.0))
	set_objective("TRAGE DEN GEWICHTSSTEIN ZUR OST-WINDE [E]", 0.68)


func request_slot_stone() -> void:
	if not multiplayer.is_server() or floodgate_open or stone_carrier_peer == 0:
		return
	stone_carrier_peer = 0
	floodgate_open = true
	brazier_lit = true
	if _weight_stone != null:
		_weight_stone.slotted = true
		_weight_stone.position = _east_winch.position + Vector2(0.0, 14.0)
	if _brazier_node != null:
		_brazier_node.set_lit(true)
	set_checkpoint(Vector2(0.0, 165.0))
	_sync_gate_state("flood", true)
	_play_sfx("floodgate_open", 1.5)
	## Heal every player in the dungeon by 40% HP + full stamina on Checkpoint ignition!
	for p: Player in Player.all:
		if is_instance_valid(p) and p.global_position.distance_to(global_position) < 900.0:
			if p.health != null and p.health.current > 0.0:
				p.health.heal(p.health.max_health * 0.40)
			if p.stamina != null:
				p.stamina.current = p.stamina.max_stamina
	set_objective("BETRITT DAS SCHLEUSENBECKEN — STELLE DICH VORGATH", 0.80)
	_announce("DAS SCHLEUSENTOR ÖFFNET SICH! RASTFEUER ENTZÜNDET (CHECKPOINT)!")


func request_heal_at_brazier(peer_id: int) -> void:
	if not multiplayer.is_server() or not brazier_lit:
		return
	for p: Player in Player.all:
		if is_instance_valid(p) and p.get_multiplayer_authority() == peer_id and p.health != null and p.health.current > 0.0:
			p.health.heal(p.health.max_health * 0.40)
			if p.stamina != null:
				p.stamina.current = p.stamina.max_stamina


func _process(delta: float) -> void:
	## Smooth animated water level draining after West Tide Bell
	if not is_equal_approx(tide_level, _target_tide):
		tide_level = move_toward(tide_level, _target_tide, delta * 0.25)
		if _water_mat != null:
			_water_mat.set_shader_parameter("tide_level", tide_level)
		if _backdrop != null:
			_backdrop.queue_redraw()

	## Carry Weight Stone visually above the carrier's head
	if stone_carrier_peer != 0 and _weight_stone != null:
		var found_carrier: bool = false
		for p: Player in Player.all:
			if is_instance_valid(p) and p.get_multiplayer_authority() == stone_carrier_peer:
				if p.health != null and p.health.current > 0.0:
					_weight_stone.global_position = p.global_position + Vector2(0.0, -24.0)
					found_carrier = true
				break
		if not found_carrier and multiplayer.is_server():
			## Carrier died -> drop stone cleanly on the dock
			stone_carrier_peer = 0

	## Boss arena trigger once players cross the open floodgate threshold (local y < -65)
	if multiplayer.is_server() and floodgate_open and not boss_started and not completed and vorgath != null:
		for p: Player in Player.all:
			if is_instance_valid(p) and p.health != null and p.health.current > 0.0:
				var lp: Vector2 = p.global_position - global_position
				if lp.y < -70.0 and absf(lp.x) < 190.0:
					_start_boss_fight()
					break


func _start_boss_fight() -> void:
	boss_started = true
	_sync_gate_state("boss", false)
	if vorgath != null:
		vorgath.activate_fight()
	set_objective("BESIEGE VORGATH, BRUT DER MOLE", -1.0)


func _on_vorgath_defeated() -> void:
	if completed:
		return
	_sync_gate_state("boss", true)
	set_objective("PRÜFUNG BESTANDEN! BENUTZE DAS RÜCKKEHRSIEGEL [E]", 1.0)
	finish_victory(ARENA_CENTER_LOCAL, ARENA_CENTER_LOCAL + Vector2(0.0, 28.0))


func on_boss_reset() -> void:
	boss_started = false
	_sync_gate_state("boss", true)
	if vorgath != null:
		vorgath.reset_encounter()
	if floodgate_open:
		set_objective("BETRITT DAS SCHLEUSENBECKEN — NEUER VERSUCH", 0.80)


func _sync_gate_state(which: String, open: bool) -> void:
	if NetworkManager.rpc_ready(self) and not multiplayer.get_peers().is_empty():
		_rpc_set_gate.rpc(which, open)
	else:
		_rpc_set_gate(which, open)


@rpc("authority", "call_local", "reliable")
func _rpc_set_gate(which: String, open: bool) -> void:
	match which:
		"west":
			_set_gate_open(_gate_west, _gate_west_vis, open)
		"stairs":
			_set_gate_open(_gate_east_stairs, _gate_stairs_vis, open)
			_target_tide = 0.5
		"flood":
			_set_gate_open(_gate_flood, _gate_flood_vis, open)
			if _brazier_node != null:
				_brazier_node.set_lit(true)
		"boss":
			_set_gate_open(_gate_boss_seal, _gate_boss_vis, open)


func _announce(msg: String) -> void:
	if not is_inside_tree():
		return
	var box: SpeechBox = get_tree().get_first_node_in_group("speech_box") as SpeechBox
	if box != null:
		box.speak("GEZEITENKAMMERN", msg, 3.2)


func _play_sfx(id: String, db: float) -> void:
	var path: String = "res://assets/audio/dungeon/%s.wav" % id
	if ResourceLoader.exists(path) and is_inside_tree():
		var stream: AudioStream = load(path) as AudioStream
		if stream != null:
			var asp: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
			asp.stream = stream
			asp.volume_db = db
			asp.max_distance = 900.0
			add_child(asp)
			asp.finished.connect(asp.queue_free)
			asp.play()
