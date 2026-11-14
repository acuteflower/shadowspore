class_name HallgratPlan
extends Node2D
## Developer view of Hallgrat's ground plan (data/hallgrat.json) drawn straight onto the world: districts as tinted outlines, places as frames
## with their names, the ways as dotted lines, gates as rings, the guide stones (Leitsteine) as dots in the colour of their note. Unlit, above
## the ground, below everything that stands. Switched by ENTWICKLER -> HALLGRAT: PLAN (`Hallgrat.show_plan`).
const TONES: Array[Color] = [Color("e7d27a"), Color("78f4e6"), Color("c79bff"), Color("ff9f7a")]
const T: float = 16.0

var _data: Dictionary


func _ready() -> void:
	z_index = -7
	material = Unlit.material()
	_data = DataRegistry.table("hallgrat")
	queue_redraw()


func _p(at: Array) -> Vector2:
	return Vector2(float(at[0]), float(at[1])) * T


func _draw() -> void:
	for d: Dictionary in _data.get("districts", []) as Array:
		var col: Color = Color(String(d.color))
		var poly: PackedVector2Array = PackedVector2Array()
		for at: Array in d.poly as Array:
			poly.append(_p(at))
		draw_colored_polygon(poly, Color(col, 0.10))
		poly.append(poly[0])
		draw_polyline(poly, Color(col, 0.85), 3.0)
		var mid: Vector2 = Vector2.ZERO
		for i: int in poly.size() - 1:
			mid += poly[i]
		mid /= float(poly.size() - 1)
		PixelText.draw(self, String(d.name), Vector2i(mid) - Vector2i(PixelText.width(String(d.name)) / 2, 40), col, Color(0, 0, 0, 0.8))
	for way: Dictionary in _data.get("ways", []) as Array:
		var line: Array = way.get("line", []) as Array
		for i: int in range(line.size() - 1):
			var a: Vector2 = _p(line[i] as Array) + Vector2(8, 8)
			var b: Vector2 = _p(line[i + 1] as Array) + Vector2(8, 8)
			var n: int = maxi(1, int(a.distance_to(b) / 10.0))
			for k: int in n:
				draw_line(a.lerp(b, float(k) / n), a.lerp(b, (float(k) + 0.5) / n), Color(1.0, 0.93, 0.75, 0.9), 2.0)
	for place: Dictionary in _data.get("places", []) as Array:
		var r: Array = place.rect as Array
		var rect: Rect2 = Rect2(_p([r[0], r[1]]), Vector2(float(r[2]), float(r[3])) * T)
		var stable: bool = String(place.kind) == "stable"
		var col: Color = Color("ff9a5a") if stable else Color("ffd696")
		draw_rect(rect, Color(col, 0.08))
		draw_rect(rect, col, false, 3.0 if stable else 2.0)
		PixelText.draw(self, String(place.name), Vector2i(rect.position) + Vector2i(4, 4), col, Color(0, 0, 0, 0.8))
		if place.has("paddock"):
			var q: Array = place.paddock as Array
			var pad: Rect2 = Rect2(_p([q[0], q[1]]), Vector2(float(q[2]), float(q[3])) * T)
			draw_rect(pad, Color(col, 0.6), false, 1.0)
			PixelText.draw(self, "KOPPEL", Vector2i(pad.position) + Vector2i(4, 4), Color(col, 0.8), Color(0, 0, 0, 0.8))
	for gate: Dictionary in _data.get("gates", []) as Array:
		var at: Vector2 = _p(gate.tile as Array) + Vector2(8, 8)
		draw_arc(at, 26.0, 0.0, TAU, 32, Color("ff5a8c") if bool(gate.get("sealed", false)) else Color.WHITE, 2.0)
		PixelText.draw(self, String(gate.name), Vector2i(at) + Vector2i(30, -3), Color.WHITE, Color(0, 0, 0, 0.8))
		for h: Array in gate.get("houses", []) as Array:
			draw_rect(Rect2(_p([h[0], h[1]]), Vector2(float(h[2]), float(h[3])) * T), Color(0.75, 0.7, 0.85, 0.5))
	for stone: Dictionary in _data.get("leitsteine", []) as Array:
		var at: Vector2 = _p(stone.tile as Array) + Vector2(8, 8)
		var col: Color = Color("785a78") if bool(stone.get("dead", false)) else TONES[int(stone.tone) % 4]
		draw_circle(at, 6.0, Color(0.05, 0.04, 0.1))
		draw_circle(at, 4.0, col)
