extends SceneTree
## Trampled ways without a world: a hut, a few buildings, trunks and stones on plain grass; the ways are routed (TownWays) and drawn (TownPathArt) in the order the buildings
## are placed. `Godot --headless --path . --script tools/preview_ways.gd -- /abs/out.png [scale]` writes a picture (default scale 3).

const GRASS: Color = Color("3f7a45")


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp/ways.png"
	var scale: int = int(args[1]) if args.size() > 1 else 3
	var size: Vector2i = Vector2i(420, 300)
	var ground: Image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.frequency = 0.04
	for y: int in size.y:
		for x: int in size.x:
			ground.set_pixel(x, y, GRASS.lerp(Color("2f6238"), 0.5 + 0.5 * noise.get_noise_2d(float(x), float(y))))
	var hut: Rect2 = Rect2(190, 40, 120, 28)
	var solids: Array[Rect2] = [hut]
	var trunks: Array[Vector2] = [Vector2(150, 150), Vector2(260, 130), Vector2(70, 110), Vector2(330, 205), Vector2(210, 215)]
	for t: Vector2 in trunks:
		solids.append(Rect2(t - Vector2(5, 3), Vector2(10, 6)))
	var door: Vector2 = Vector2(250, 74)
	var buildings: Array[Rect2] = [Rect2(80, 190, 64, 28), Rect2(300, 140, 96, 40), Rect2(150, 250, 64, 28), Rect2(40, 60, 64, 28)]
	var walkable: Callable = func(_p: Vector2) -> bool: return true
	var trails: Array[PackedVector2Array] = []
	var ends: Array[bool] = []
	var doors: Array[Vector2] = [door]
	var index: int = 0
	for b: Rect2 in buildings:
		var start: Vector2 = Vector2(b.position.x + b.size.x / 2.0, b.end.y + 9.0)
		solids.append(b)
		var best: Vector2 = door
		for d: Vector2 in doors:
			if start.distance_to(d) < start.distance_to(best):
				best = d
		var made: Dictionary = TownWays.route(start, best, solids, walkable, trails, 7919 * (index + 1))
		var pts: PackedVector2Array = made.p as PackedVector2Array
		print("way ", index, ": ", pts.size(), " points, joined ", made.joined, ", length ", _length(pts))
		if pts.size() > 1:
			trails.append(pts)
			ends.append(not bool(made.joined))
		doors.append(start)
		index += 1
	for i: int in trails.size():
		var made: Dictionary = TownPathArt.image(trails[i], 31 * (i + 1), ends[i])
		var at: Vector2i = Vector2i(made.origin as Vector2)
		ground.blend_rect(made.image as Image, Rect2i(Vector2i.ZERO, (made.image as Image).get_size()), at)
	for s: Rect2 in solids:
		ground.fill_rect(Rect2i(s), Color("5a4a3a"))
	for t: Vector2 in trunks:
		ground.fill_rect(Rect2i(Vector2i(t) - Vector2i(5, 3), Vector2i(10, 6)), Color("2a1f2a"))
	ground.resize(size.x * scale, size.y * scale, Image.INTERPOLATE_NEAREST)
	ground.save_png(out)
	print("saved ", out)
	quit()


func _length(p: PackedVector2Array) -> int:
	var total: float = 0.0
	for i: int in range(1, p.size()):
		total += p[i - 1].distance_to(p[i])
	return int(total)
