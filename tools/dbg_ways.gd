extends Node
func _ready() -> void:
	var relief: Relief = Relief.new()
	var w: HallgratWays = HallgratWays.build(relief, DataRegistry.table("hallgrat"), DataRegistry.table("hallgrat_art"), DataRegistry.table("ground_baked"))
	var img: Image = Image.create(w.cols, w.rows, false, Image.FORMAT_RGB8)
	for y: int in w.rows:
		for x: int in w.cols:
			var c: float = w.cost[y * w.cols + x]
			var p: Vector2 = w.center_of(Vector2i(x, y))
			var lv: int = relief.level(int(p.x / 16), int(p.y / 16))
			img.set_pixel(x, y, Color(0.1, 0.05, 0.1) if c <= 0.0 else (Color(0.9, 0.85, 0.6) if c < 1.5 else Color(0.3, 0.55 + lv * 0.1, 0.3)))
	var gate: Vector2 = w.snap(Vector2(2988, 5470))
	var a: Vector2i = w.cell_of(gate)
	var seen: Dictionary = {a: true}
	var q: Array[Vector2i] = [a]
	while not q.is_empty():
		var c2: Vector2i = q.pop_back()
		for d: Vector2i in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]:
			var n: Vector2i = c2 + d
			if w.inside(n) and not seen.has(n) and w.cost[n.y * w.cols + n.x] > 0.0:
				seen[n] = true
				q.append(n)
	for c3: Vector2i in seen:
		img.set_pixel(c3.x, c3.y, img.get_pixel(c3.x, c3.y).lerp(Color(1, 0.2, 0.2), 0.5))
	img.set_pixel(a.x, a.y, Color(0, 0, 1))
	print("gate ", gate, " reach ", seen.size())
	img.resize(w.cols * 3, w.rows * 3, Image.INTERPOLATE_NEAREST)
	img.save_png("C:/Users/levin/AppData/Local/Temp/claude/5fd023d60ea8387f/30f838a0-2a0a-417c-aa4e-0d3269b3877e/scratchpad/net.png")
	get_tree().quit()
