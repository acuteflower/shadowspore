class_name MeadowDetails
extends MultiMeshInstance2D
## Tiny decorative ground cover. One batched draw per streamed chunk, no physics,
## interaction, loot, individual processing or persistent state.
const SIZE: Vector2i = Vector2i(16, 20)
const COUNT: int = 30 ## 0-23 grass, flowers, ferns, straw; 24-25 shade moss (forest floors, north slopes, cliff feet); 26-29 the Hexenwald's floor (witch-hair moss, dead leaves, a root arch, bone-white toadstools)
const MEADOW_COUNT: int = 26 ## what the meadow draws from (the Hexenwald's kinds are chosen on purpose, see WorldLevel._detail_candidate)
const WIND: Shader = preload("res://assets/shaders/meadow_details.gdshader")
static var _atlas: ImageTexture
var _wind: ShaderMaterial
var _field: Image
var _contact_texture: ImageTexture
var _bends: Dictionary = {}
var _occupied: Dictionary = {}
var sources: Array[Vector2] = []
var source_kinds: Array[int] = []
var _origin: Vector2
var _hidden: Dictionary = {} ## instance index -> true: plants the town's ground has no room for
var _dirty: bool = false
var _contact_timer: float = 0.0
const CONTACT_UPDATE_INTERVAL: float = 0.12 ## Throttle texture upload to ~8 updates/sec max during active contacts

func setup(points: Array[Dictionary], origin: Vector2 = Vector2.ZERO) -> void:
	_origin = origin
	position = origin
	if _atlas == null:
		_atlas = _make_atlas()
	_wind = ShaderMaterial.new()
	_wind.shader = WIND
	_field = Image.create(64,64,false,Image.FORMAT_RGBA8)
	_field.fill(Color(0.5,0.5,0,1))
	_contact_texture = ImageTexture.create_from_image(_field)
	_wind.set_shader_parameter("contacts",_contact_texture)
	_wind.set_shader_parameter("chunk_origin",origin)
	texture = _atlas
	material = _wind
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = -8 # above ground decals, below characters, props and drops
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(SIZE)
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	multimesh.instance_count = points.size()
	for i: int in points.size():
		var p: Dictionary = points[i]
		var at: Vector2 = p.pos as Vector2
		sources.append(at)
		source_kinds.append(int(p.kind))
		_occupied[Vector2i((at-origin)/8.0)] = true
		multimesh.set_instance_transform_2d(i, Transform2D(0.0, at - origin - Vector2(0, 9)))
		multimesh.set_instance_color(i, p.tint as Color)
		multimesh.set_instance_custom_data(i, Color(float(p.kind) / COUNT, float(p.phase), float(p.sway), float(p.get("exposure",1.0))))

func _ready() -> void:
	add_to_group("meadow_details")
	apply_wear(get_tree().get_first_node_in_group("town") as TownManager)

## The town's trodden ground grows no small plants (docs/town_ausbau.md A5): a plant whose cell is worn enough is not drawn (which ones: a fixed hash of its place, so the edge
## frays). Called for every chunk as it appears and whenever the town's ground changes.
func apply_wear(town: TownManager) -> void:
	if multimesh == null or town == null:
		return
	for i: int in sources.size():
		var at: Vector2 = sources[i]
		var value: float = town.wear_at(at)
		var hide: bool = value > 0.30 + 0.5 * fposmod(sin(at.x * 12.9898 + at.y * 78.233) * 43758.5453, 1.0)
		if hide == _hidden.has(i):
			continue
		var feet: Vector2 = at - _origin - Vector2(0, 9)
		if hide:
			_hidden[i] = true
			multimesh.set_instance_transform_2d(i, Transform2D(Vector2.ZERO, Vector2.ZERO, feet))
		else:
			_hidden.erase(i)
			multimesh.set_instance_transform_2d(i, Transform2D(0.0, feet))

## Wind now comes from the shader globals that WorldWind publishes every frame. Kept as a no-op for old callers.
func set_wind(_clock: float, _direction: Vector2, _gust: float) -> void:
	pass

func stamp_segment(from: Vector2, to: Vector2, force: float) -> bool:
	if not Rect2(_origin-Vector2(20,20),Vector2(552,552)).intersects(Rect2(from,Vector2.ZERO).expand(to).grow(16)):
		return false
	var touched: bool = false
	var direction: Vector2 = (to-from).normalized()
	var steps: int = maxi(1,ceili(from.distance_to(to)/8.0))
	for step: int in steps+1:
		var at: Vector2 = from.lerp(to,float(step)/steps)
		var cell: Vector2i = Vector2i(((at-_origin)/8.0).floor())
		for dy: int in range(-2,3):
			for dx: int in range(-2,3):
				var c: Vector2i = cell+Vector2i(dx,dy)
				if c.x<0 or c.y<0 or c.x>=64 or c.y>=64: continue
				var cell_center: Vector2 = Vector2(c)*8.0+Vector2(4,4)+_origin
				var d_sq: float = cell_center.distance_squared_to(at)
				if d_sq > 289.0: continue ## 17.0 * 17.0
				var distance: float = sqrt(d_sq)
				var amount: float = (1.0-distance/20.0)*force
				_bends[c] = Vector3(direction.x*amount,direction.y*amount,0.0)
				_dirty = true
				if _occupied.has(c): touched = true
	return touched

func advance_contacts(delta: float) -> void:
	if _bends.is_empty() and not _dirty:
		return
	_contact_timer += delta
	var should_update: bool = _dirty or _contact_timer >= CONTACT_UPDATE_INTERVAL
	if not _bends.is_empty():
		for cell: Vector2i in _bends.keys():
			var impulse: Vector3 = _bends[cell]
			impulse.z += delta
			if impulse.z > 0.9:
				_field.set_pixelv(cell,Color(0.5,0.5,0,1))
				_bends.erase(cell)
				should_update = true
				continue
			_bends[cell] = impulse
			if should_update:
				var fade: float = exp(-impulse.z*5.0)*cos(impulse.z*10.0)
				_field.set_pixelv(cell,Color(0.5+impulse.x*fade*0.25,0.5+impulse.y*fade*0.25,0,1))
		if _bends.is_empty():
			should_update = true
	if should_update:
		_contact_texture.update(_field)
		_contact_timer = 0.0
		_dirty = false

static func _pixel(im: Image, variant: int, x: int, y: int, color: Color) -> void:
	if x >= 0 and x < SIZE.x and y >= 0 and y < SIZE.y:
		im.set_pixel(variant * SIZE.x + x, y, color)

static func _line(im: Image, v: int, a: Vector2i, b: Vector2i, color: Color) -> void:
	var steps: int = maxi(absi(b.x - a.x), absi(b.y - a.y))
	for i: int in steps + 1:
		var p: Vector2i = Vector2i(Vector2(a).lerp(Vector2(b), float(i) / maxf(steps, 1)).round())
		_pixel(im, v, p.x, p.y, color)

static func _make_atlas() -> ImageTexture:
	var im: Image = Image.create(SIZE.x * COUNT, SIZE.y, false, Image.FORMAT_RGBA8)
	im.fill(Color.TRANSPARENT)
	var dark: Color = Color("264b43")
	var stem: Color = Color("48845b")
	var leaf: Color = Color("78ab70")
	var tip: Color = Color("b0c88b")
	for v: int in COUNT:
		# Small broken contact shadows, never a broad dark sticker.
		for x: int in range(5, 11):
			_pixel(im, v, x, 19, Color(0.08, 0.16, 0.16, 0.23))
		if v >= 12:
			_extra_plant(im,v,dark,stem,leaf,tip)
			continue
		if v < 4: # fine grass, curled blades and seed-bearing stems
			for blade: int in 5:
				var root: Vector2i = Vector2i(6 + blade % 4, 18)
				var top: Vector2i = Vector2i(2 + blade * 2 + v % 2, 7 + (blade * 3 + v * 2) % 8)
				var mid: Vector2i = Vector2i((root.x + top.x) / 2, top.y + 4)
				_line(im, v, root, mid, dark)
				_line(im, v, mid, top, stem if blade % 2 == 0 else leaf)
				_pixel(im, v, top.x, top.y, tip)
			if v == 3:
				_line(im, v, Vector2i(8,18), Vector2i(9,4), stem)
				for y: int in [4, 6, 8]:
					_pixel(im, v, 9, y, Color("c2b78b"))
					_pixel(im, v, 10, y + 1, Color("8d946a"))
		elif v < 9: # a few irregular wildflowers, restrained cream/lilac/blush
			var petals: Array[Color] = [Color("d8d4ab"), Color("ad9ccc"), Color("d3a4bd"), Color("a7c9c0"), Color("cbbd83")]
			var petal: Color = petals[v - 4]
			for sprig: int in (2 if v % 2 == 0 else 3):
				var x: int = 4 + sprig * 4
				var y: int = 7 + (sprig * 3 + v) % 6
				_line(im, v, Vector2i(8,18), Vector2i(x,y), stem)
				_line(im, v, Vector2i(x, y+6), Vector2i(x-2,y+4), leaf)
				_pixel(im, v, x+1, y+3, leaf)
				for d: Vector2i in [Vector2i(-1,0),Vector2i(1,0),Vector2i(0,-1),Vector2i(0,1)]:
					_pixel(im, v, x+d.x, y+d.y, petal.darkened(0.18) if d.y > 0 else petal)
				_pixel(im, v, x, y, Color("dac287"))
		else: # low fern fans, sorrel and a little rounded leaf rosette
			for branch: int in 5:
				var top: Vector2i = Vector2i(2+branch*3, 11+absi(branch-2)*2)
				_line(im, v, Vector2i(8,18), top, stem)
				if v == 9:
					for t: int in [1,2,3]:
						var p: Vector2i = Vector2i(Vector2(8,18).lerp(Vector2(top), t / 4.0))
						_line(im,v,p,p+Vector2i(-2,-1),leaf)
						_pixel(im,v,p.x+1,p.y-1,stem)
				else:
					_pixel(im,v,top.x,top.y,leaf)
					_pixel(im,v,top.x-1,top.y,stem)
					_pixel(im,v,top.x,top.y+1,stem)
					_pixel(im,v,top.x+1,top.y,tip if v == 11 else leaf)
	return ImageTexture.create_from_image(im)

static func _extra_plant(im: Image,v: int,dark: Color,stem: Color,leaf: Color,tip: Color) -> void:
	if v < 15: # curled grass, short meadow clump, slender nodding seed stems
		for i: int in (7 if v==13 else 4):
			var x: int = 1+i*2
			var height: int = 5+(i*3+v)%8 if v!=13 else 4+i%3
			var end: Vector2i = Vector2i(x,18-height)
			_line(im,v,Vector2i(6+i%3,18),Vector2i(x,15),dark)
			_line(im,v,Vector2i(x,15),end,leaf if i%2==0 else stem)
			_pixel(im,v,end.x+1,end.y,tip)
			if v==14:
				for k: int in 3:
					_pixel(im,v,end.x+k%2,end.y-k,Color("b6bb84"))
	elif v < 18: # cream stars, hanging lilac bells, scattered dusty rose blossoms
		var petal: Color = [Color("d9d6af"),Color("a79bc7"),Color("c99bab")][v-15]
		for i: int in 3:
			var x: int = 3+i*4
			var y: int = 5+(i*3+v)%6
			_line(im,v,Vector2i(8,18),Vector2i(x,y+2),stem)
			_line(im,v,Vector2i(x,y+7),Vector2i(x-2,y+5),leaf)
			if v==16:
				_line(im,v,Vector2i(x,y+2),Vector2i(x+2,y),stem)
				_pixel(im,v,x+2,y+1,petal)
				_line(im,v,Vector2i(x+1,y+2),Vector2i(x+3,y+2),petal)
				_pixel(im,v,x+2,y+3,petal.darkened(0.2))
			else:
				for d: Vector2i in [Vector2i(-1,0),Vector2i(1,0),Vector2i(0,-1),Vector2i(0,1)]:
					_pixel(im,v,x+d.x,y+d.y,petal)
				_pixel(im,v,x,y,Color("bfa16c"))
	elif v < 20: # unfurling fern and broad asymmetrical fern fan
		for i: int in (3 if v==18 else 5):
			var end: Vector2i = Vector2i(2+i*3,5+i%3*3)
			_line(im,v,Vector2i(8,18),end,stem)
			for k: int in range(1,5):
				var p: Vector2i = Vector2i(Vector2(8,18).lerp(Vector2(end),k/5.0))
				_line(im,v,p,p+Vector2i(-2,-1),leaf)
				_line(im,v,p,p+Vector2i(2,-2),stem)
			if v==18:
				_line(im,v,end,end+Vector2i(2,0),tip)
				_pixel(im,v,end.x+2,end.y+1,leaf)
	elif v < 22: # broad ground leaves / loose sorrel hearts
		for i: int in 5:
			var x: int = 2+i*3
			var y: int = 12+absi(i-2)
			_line(im,v,Vector2i(8,18),Vector2i(x,y),dark)
			for dx: int in range(-1,2):
				_line(im,v,Vector2i(x+dx,y),Vector2i(x+dx,y+2),leaf if dx<1 else stem)
			_pixel(im,v,x-1,y-1,tip)
			if v==21: _pixel(im,v,x+1,y-1,leaf)
	elif v < 24: # sparse straw and spent dark seed heads
		for i: int in 4:
			var x: int = 3+i*3
			var y: int = 7+(i*3+v)%6
			_line(im,v,Vector2i(8,18),Vector2i(x,y),Color("777d5a"))
			_pixel(im,v,x,y-1,Color("b3ae7b") if v==22 else Color("655c64"))
			if v==23:
				_pixel(im,v,x-1,y-1,Color("6f6269"))
				_pixel(im,v,x,y-2,Color("9c927a"))
	elif v >= 26:
		_witch_floor(im, v)
	else: # shade moss: 24 low cushions in dark teal-green lit from the top left, 25 a flat mat with thin spore stalks
		var moss: Array[Color] = [Color("1d3d34"),Color("28503f"),Color("346b49"),Color("55985f"),Color("86bc7a")]
		if v == 24:
			for mound: Vector2i in [Vector2i(5,16),Vector2i(10,15),Vector2i(8,17)]:
				for dy: int in range(-3,2):
					for dx: int in range(-4,5):
						if pow(dx/4.2,2.0)+pow(dy/3.0,2.0) > 1.0: continue
						var lit: float = -0.5*dx-0.9*dy
						_pixel(im,v,mound.x+dx,mound.y+dy,moss[1 if lit < -1.5 else (4 if lit > 3.2 else (3 if lit > 1.2 else 2))])
		else:
			for x: int in range(1,15):
				var h: int = 1+(x*5+3)%3
				for y: int in range(18-h,19):
					_pixel(im,v,x,y,moss[1 if y == 18 else (2 if x%3 else 3)])
			for stalk: Vector2i in [Vector2i(4,9),Vector2i(8,7),Vector2i(12,10)]:
				_line(im,v,Vector2i(stalk.x,17),stalk,moss[2])
				_pixel(im,v,stalk.x,stalk.y-1,Color("c4cc9a"))


## The Hexenwald's ground cover (docs/hexenwald_leben_konzept.md), in its own cold colours (WorldLevel tints them only a little):
## 26 a cushion of grey witch-hair moss with violet shade, 27 a drift of dead leaves (wine, rust, umber), 28 a black root arching out of
## the ground, 29 three tiny bone-white toadstools.
static func _witch_floor(im: Image, v: int) -> void:
	match v:
		26:
			var moss: Array[Color] = [Color("26124a"), Color("1e3038"), Color("34504e"), Color("557468"), Color("86a08a")]
			for mound: Vector2i in [Vector2i(5,17),Vector2i(10,16),Vector2i(8,18)]:
				for dy: int in range(-3,2):
					for dx: int in range(-4,5):
						if pow(dx/4.4,2.0)+pow(dy/2.6,2.0) > 1.0: continue
						var lit: float = -0.5*dx-0.9*dy+float((dx*7+dy*3+mound.x)%3)*0.4
						_pixel(im,v,mound.x+dx,mound.y+dy,moss[0 if lit < -1.8 else (4 if lit > 3.0 else (3 if lit > 1.2 else (2 if lit > -0.6 else 1)))])
			for strand: Vector2i in [Vector2i(3,15),Vector2i(12,14)]: ## a few hairs stand up from it
				_line(im,v,Vector2i(strand.x,strand.y+2),strand,Color("557468"))
		27:
			var leaves: Array[Color] = [Color("5a2430"), Color("8e3a3a"), Color("6a4e42"), Color("927460"), Color("5a4a6a")]
			for i: int in 9:
				var at: Vector2i = Vector2i(2 + (i * 5) % 12, 15 + (i * 3) % 4)
				var c: Color = leaves[(i * 2 + 1) % leaves.size()]
				_pixel(im,v,at.x,at.y,c)
				_pixel(im,v,at.x+1,at.y,c.darkened(0.25))
				_pixel(im,v,at.x,at.y-1,c.lightened(0.18))
			_line(im,v,Vector2i(4,18),Vector2i(9,16),Color("2c2236")) ## a twig
		28:
			var root: Array[Color] = [Color("0c0812"), Color("1a1322"), Color("2c2236"), Color("44344c")]
			for x: int in range(2, 15):
				var t: float = float(x - 2) / 12.0
				var y: int = 18 - int(round(sin(t * PI) * 5.0))
				_pixel(im,v,x,y,root[2] if t < 0.5 else root[1])
				_pixel(im,v,x,y+1,root[0])
				if t > 0.2 and t < 0.6:
					_pixel(im,v,x,y-1,root[3])
			_pixel(im,v,8,13,Color("7a9488")) ## lichen on its back
		29:
			for cap: Vector3i in [Vector3i(5,14,2),Vector3i(9,12,3),Vector3i(12,15,2)]:
				_line(im,v,Vector2i(cap.x,18),Vector2i(cap.x,cap.y+1),Color("b8b4b8"))
				for dx: int in range(-cap.z/2, cap.z/2+1):
					_pixel(im,v,cap.x+dx,cap.y,Color("dedacc") if dx <= 0 else Color("8a8698"))
				_pixel(im,v,cap.x,cap.y-1,Color("f6f2e0"))
