extends SceneTree
## Production normalization only: alpha bounds, proportional nearest-neighbor fit,
## binary transparency and the game's 30-color knight material ramps.
## Godot --headless --path . --script tools/prepare_dialogue_portrait.gd -- SOURCE OUTPUT
const COLORS: Array[String] = ["120c1c","09060f","151021","1f1d30","292840","3d3d5a","474a6a","5e587b","787ea0","aeb4cc","e9e3f7","26111d","3a1729","4a1d31","582c42","70304a","85455f","985470","b8728a","0d0912","1a1222","2c2038","443654","6f5020","b48a38","e6c468","fff0b0","7a5cd0","b9a0ff","ffffff"]
func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("Provide SOURCE and OUTPUT")
		quit(1)
		return
	var image: Image = Image.load_from_file(args[0])
	if image == null:
		quit(1)
		return
	image.convert(Image.FORMAT_RGBA8)
	for y: int in image.get_height():
		for x: int in image.get_width():
			var c: Color = image.get_pixel(x,y)
			c.a = 1.0 if c.a >= 0.5 else 0.0
			image.set_pixel(x,y,c)
	var bounds: Rect2i = image.get_used_rect()
	if not bounds.has_area():
		quit(1)
		return
	image = image.get_region(bounds)
	var fit: float = minf(99.0/image.get_width(),150.0/image.get_height())
	image.resize(roundi(image.get_width()*fit),roundi(image.get_height()*fit),Image.INTERPOLATE_NEAREST)
	var palette: Array[Color] = []
	for hex: String in COLORS: palette.append(Color(hex))
	for y: int in image.get_height():
		for x: int in image.get_width():
			var c: Color = image.get_pixel(x,y)
			if c.a < 0.5:
				image.set_pixel(x,y,Color.TRANSPARENT)
				continue
			var nearest: Color = palette[0]
			var best: float = INF
			for p: Color in palette:
				var distance: float = Vector3(c.r-p.r,c.g-p.g,c.b-p.b).length_squared()
				if distance < best:
					best = distance
					nearest = p
			image.set_pixel(x,y,nearest)
	var result: Image = Image.create(103,153,false,Image.FORMAT_RGBA8)
	result.fill(Color.TRANSPARENT)
	result.blit_rect(image,Rect2i(Vector2i.ZERO,image.get_size()),Vector2i((103-image.get_width())/2,153-image.get_height()))
	var error: Error = result.save_png(args[1])
	print("PORTRAIT: ",result.get_size()," bounds ",result.get_used_rect()," save ",error)
	quit(0 if error == OK else 1)
