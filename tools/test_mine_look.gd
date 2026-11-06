extends Node
## The mine's light and look: always the night's tint (also at noon), night lights on, enemy warnings above the floor, rails that join up, the mine's own rocks.

var _ok: bool = true
const EDGES: Dictionary = { ## rail piece -> open edges (1 N, 2 E, 4 S, 8 W)
	0: 10, 1: 5, 2: 12, 3: 9, 4: 3, 5: 6, 6: 8, 7: 1,
}


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		print("MINE LOOK FAILED: ", what)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_rails()
	var rock: Dictionary = DataRegistry.get_entry("plants", "mine_rock")
	_check(String(rock.texture).contains("assets/mine/props/mine_rocks") and not rock.has("glow") and not rock.has("light"), "mine rocks use their own sheet, no glow of the world's crystals")
	var texture: Texture2D = load(String(rock.texture)) as Texture2D
	_check(texture != null and texture.get_size() == Vector2(512.0, 224.0), "the sheet has 8 x 4 frames of 64 x 56")
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await get_tree().process_frame
	var mines: MineManager = world.get_node("Mines") as MineManager
	var player: Player = world._players.get_child(0) as Player
	var dn: DayNight = world.get_node("DayNight") as DayNight
	TimeManager.set_time(0.5)
	await get_tree().process_frame
	_check(dn.color.is_equal_approx(Color.WHITE), "outside at noon the world is bright")
	mines.enter(player, 1)
	for i: int in 30:
		await get_tree().process_frame
	_check(dn.color.is_equal_approx(MineManager.ambient_of(1)), "in the mine it is the zone's dark tint at noon (%s)" % dn.color)
	var lights: int = 0
	for node: Node in get_tree().get_nodes_in_group("night_lights"):
		if node is NightLight and MineManager.in_mine((node as Node2D).global_position):
			lights += 1
			_check((node as NightLight).enabled, "a night light in the mine shines at noon")
	print("night lights in the mine: ", lights)
	var spider: ShadowSpider = world.spawn_species("shadow_spider", player.global_position + Vector2(40, 0), 0.0) as ShadowSpider
	var listener: VoidListener = world.spawn_species("void_listener", player.global_position + Vector2(-40, 0), 0.0) as VoidListener
	await get_tree().process_frame
	_check(spider != null and (spider.get_node("Zone") as Node2D).z_index == -3, "the spider's attack warning lies above the mine's ground")
	_check(listener != null and (listener.get_node("Zone") as Node2D).z_index == -3, "the listener's attack warning lies above the mine's ground")
	print("MINE LOOK: ", "ok" if _ok else "FAILED")
	get_tree().quit(0 if _ok else 1)


## Every piece of rail touches a neighbour with an open edge towards it (no stray pieces); a track's two ends may hang loose (at a room's middle).
func _rails() -> void:
	for level: int in [1, 3, 5]:
		for s: int in 4:
			var l: MineLayout = MineGenerator.new().generate(300 + s * 977, level)
			var pieces: Dictionary = {} ## Vector2i -> edges mask
			for c: Vector2i in l.chunk_rails:
				for r: Vector3i in l.chunk_rails[c] as Array:
					pieces[Vector2i(r.x, r.y)] = int(pieces.get(Vector2i(r.x, r.y), 0)) | int(EDGES[r.z])
			var stray: int = 0
			var loose: int = 0
			for t: Vector2i in pieces:
				var mask: int = int(pieces[t])
				var joined: bool = false
				for e: Array in [[1, Vector2i(0, -1), 4], [2, Vector2i(1, 0), 8], [4, Vector2i(0, 1), 1], [8, Vector2i(-1, 0), 2]]:
					if mask & int(e[0]) != 0:
						if int(pieces.get(t + (e[1] as Vector2i), 0)) & int(e[2]) != 0:
							joined = true
						else:
							loose += 1
				if not joined:
					stray += 1
			_check(pieces.size() > 20, "level %d seed %d has a rail line (%d tiles)" % [level, s, pieces.size()])
			_check(stray == 0, "level %d seed %d: %d stray pieces of rail" % [level, s, stray])
			_check(loose < 10 + pieces.size() / 5, "level %d seed %d: only the ends of a track hang loose (%d of %d tiles)" % [level, s, loose, pieces.size()])
