class_name LeafCritterVisual
extends RefCounted

# Coordinates are whole pixels around the animal's foot anchor. Mirroring the
# anatomy keeps the head in the direction of travel; light stays upper-left.
static func _pixel(canvas: Node2D, x: int, y: int, color: Color, fade: float) -> void:
	color.a *= clampf(fade, 0.0, 1.0)
	canvas.draw_rect(Rect2(x, y, 1, 1), color)

static func _part(canvas: Node2D, x: int, y: int, color: Color, direction: int, fade: float) -> void:
	_pixel(canvas, x * direction, y, color, fade)

static func draw_animal(canvas: Node2D, species: String, facing: float, clock: float, gait: float, flying: bool, withdraw: float, fade: float) -> void:
	var direction: int = 1 if facing >= 0.0 else -1
	var dark: Color = Color("283b3c")
	var gesture: bool = fmod(clock, 7.0) < 0.35
	var cleaning: bool = fmod(clock + 3.0, 13.0) < 0.55
	match species:
		"beetle":
			# Legs and feelers frame a six-pixel shell.
			for x: int in [-2, 0]:
				_part(canvas, x, 0, dark, direction, fade)
			if cleaning:
				_part(canvas, 2, -3, dark, direction, fade)
				_part(canvas, 3, -3, dark, direction, fade)
			else:
				_part(canvas, 2, 0, dark, direction, fade)
			_part(canvas, 3, -2, dark, direction, fade)
			_part(canvas, 4, -3 if gesture else -2, dark, direction, fade)
			if flying:
				var wing_pose: int = posmod(floori(clock * 12.0), 3)
				var wings: Array[Vector2i] = []
				match wing_pose:
					0:
						wings = [Vector2i(-3, -4), Vector2i(-4, -5), Vector2i(-3, -6), Vector2i(-2, -5), Vector2i(0, -5), Vector2i(1, -6), Vector2i(2, -5), Vector2i(2, -4)]
					1:
						wings = [Vector2i(-3, -4), Vector2i(-4, -4), Vector2i(-4, -5), Vector2i(-2, -4), Vector2i(1, -4), Vector2i(2, -4), Vector2i(3, -5), Vector2i(3, -4)]
					_:
						wings = [Vector2i(-3, -3), Vector2i(-4, -3), Vector2i(-4, -4), Vector2i(-2, -4), Vector2i(1, -4), Vector2i(2, -3), Vector2i(3, -4), Vector2i(3, -3)]
				for p: Vector2i in wings:
					_part(canvas, p.x, p.y, Color(0.58, 0.75, 0.72, 0.62), direction, fade)
				_part(canvas, -3, -3, Color("476b67"), direction, fade)
				_part(canvas, 2, -3, Color("476b67"), direction, fade)
			for x: int in range(-2, 3):
				_part(canvas, x, -2, Color("315c58"), direction, fade)
				_part(canvas, x, -1, Color("294b49"), direction, fade)
			_pixel(canvas, -1, -2, Color("78a99c"), fade)
			_pixel(canvas, 0, -2, Color("568b80"), fade)
		"caterpillar":
			var contraction: int = 1 if gait > 0.15 and sin(gait * TAU) > 0.2 else 0
			var hidden: int = roundi(clampf(withdraw, 0.0, 1.0) * 2.0)
			var tail: int = -4 + contraction + hidden
			for x: int in range(tail, 4 - hidden):
				_part(canvas, x, -2, Color("57724e"), direction, fade)
				_part(canvas, x, -1, Color("405c43"), direction, fade)
				if posmod(x + contraction, 3) == 0:
					_part(canvas, x, 0, dark, direction, fade)
			for x: int in range(tail + 1, 3 - hidden, 2):
				_part(canvas, x, -3 if contraction == 1 else -2, Color("829769"), direction, fade)
			_part(canvas, 3 - hidden, -3, dark, direction, fade)
			if gesture and hidden == 0:
				_part(canvas, 4, -4, dark, direction, fade)
		"snail":
			var retract: float = clampf(withdraw, 0.0, 1.0)
			var head: int = 3 - roundi(retract * 2.0)
			for x: int in range(-3, head + 1):
				_part(canvas, x, -1, Color("806b70"), direction, fade)
			_part(canvas, head, -2, Color("a18a8b"), direction, fade)
			if retract < 0.65:
				_part(canvas, head, -3, dark, direction, fade)
				_part(canvas, head + 1, -3 if gesture else -2, dark, direction, fade)
			for p: Vector2i in [Vector2i(-3, -2), Vector2i(-3, -3), Vector2i(-2, -4), Vector2i(-1, -4), Vector2i(0, -3), Vector2i(0, -2), Vector2i(-1, -1), Vector2i(-2, -1)]:
				_part(canvas, p.x, p.y, Color("69545e"), direction, fade)
			_pixel(canvas, -2, -3, Color("aa8991"), fade)
			_pixel(canvas, -1, -2, Color("8d717b"), fade)
