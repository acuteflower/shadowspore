class_name CookingWindow
extends Control
## Developer kitchen: decisions, a timing gesture, and a persistent recipe journal.
signal closed
const ROOTS: Texture2D = preload("res://assets/ui/cooking/roots.png")
const BOOK_ART: Texture2D = preload("res://assets/ui/cooking/book.png")
const STATION: Texture2D = preload("res://assets/ui/cooking/station.png")
const BASE: Texture2D = preload("res://assets/ui/cooking/station_base.png")
const CAULDRON: Texture2D = preload("res://assets/ui/cooking/cauldron.png")
const FIRE: Texture2D = preload("res://assets/interior/hut/fire.png")
const HERBS: Texture2D = preload("res://assets/interior/hut/herbs.png")
const BOWL: Texture2D = preload("res://assets/ui/cooking/bowl.png")
const GOLD: Color = Color("ffd98a")
const TEXT: Color = Color("e8e4f4")
const DIM: Color = Color("aaa0b8")
const TEAL: Color = Color("7fe3da")
const SOUND: Dictionary = {
 "simmer":preload("res://assets/audio/cooking/simmer.wav"),
 "sizzle":preload("res://assets/audio/cooking/sizzle.wav"),
 "pour":preload("res://assets/audio/cooking/pour.wav"),
 "spoon":preload("res://assets/audio/cooking/spoon.wav"),
 "finish":preload("res://assets/audio/cooking/finish.wav")}
enum Page { PREPARE, MOMENT, MOVING, RESULT, SKILL_READY, SKILL }
var timing: CookingTiming = CookingTiming.new()
var _book_selection: int = 0
var session: CookingSession
var page: Page = Page.PREPARE
var book_path: String = CookingBook.PATH
var _time: float = 0.0
var _open: float = 0.0
var _beat: float = 0.0
var _motion: String = ""
var _feedback: String = ""
var _sense: String = "look"
var _focus: int = 0
var _hover: int = -1
var _batch: int = 0
var _book_open: bool = false
var _remembered: bool = false
var _book: Dictionary = {}
var _player: Node
var _hud: CanvasLayer
var _hud_visible: bool
var _paused_before: bool
var _blocking_before: bool
var _menu_before: bool
var _restored: bool = false
var _loop: AudioStreamPlayer
var _voice: AudioStreamPlayer
var _ingredients: Array[Texture2D] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	focus_mode = Control.FOCUS_ALL
	_loop = AudioStreamPlayer.new()
	_loop.stream = SOUND.simmer as AudioStream
	_loop.volume_db = -29.0
	add_child(_loop)
	_loop.finished.connect(func() -> void:
		if page in [Page.MOMENT,Page.MOVING,Page.SKILL_READY,Page.SKILL]: _loop.play())
	_voice = AudioStreamPlayer.new()
	_voice.volume_db = -16.0
	add_child(_voice)

func start(player: Node,path: String = CookingBook.PATH) -> void:
	_player = player
	book_path = path
	_paused_before = get_tree().paused
	_blocking_before = InputManager.ui_blocking
	_menu_before = InputManager.menu_open
	_hud = player.get("_hud") as CanvasLayer
	if _hud != null:
		_hud_visible = _hud.visible
		_hud.hide()
	InputManager.ui_blocking = true
	InputManager.menu_open = true
	get_tree().paused = true
	_book = CookingBook.read(book_path)
	new_pot()
	grab_focus()

func new_pot() -> void:
	session = CookingSession.new("glimmer_pot",_batch%2==1)
	_batch += 1
	page = Page.PREPARE
	_focus = 0
	_sense = "look"
	_motion = ""
	_book_open = false
	_beat = 0.0
	_ingredients.clear()
	for ingredient: Dictionary in session.recipe.ingredients as Array:
		_ingredients.append(load(String(ingredient.icon)) as Texture2D)
	if _loop != null: _loop.stop()

func begin_cooking() -> void:
	if page != Page.PREPARE: return
	session.begin()
	page = Page.MOVING
	_motion = "ignite"
	_feedback = "Die Glut erwacht. Auf deinem Brett liegen Pilz und Beeren bereit."
	_beat = 1.1
	_play("sizzle")
	_loop.play()

func choose(index: int) -> void:
	if page != Page.MOMENT or _book_open: return
	var action: Dictionary = session.choose(index)
	if action.is_empty(): return
	_animate_action(action)

func _animate_action(action: Dictionary) -> void:
	_motion = String(action.motion)
	_feedback = String(action.feedback)
	_sense = "look"
	page = Page.MOVING
	_beat = 1.4
	_play("pour" if _motion=="pour" else ("sizzle" if _motion=="fan" else "spoon"))

func start_skill() -> void:
	if page!=Page.SKILL_READY or _book_open: return
	timing.begin()
	page = Page.SKILL

func hit_skill() -> void:
	if page!=Page.SKILL or _book_open: return
	var hit: Dictionary = timing.hit()
	if hit.is_empty(): return
	var action: Dictionary = session.resolve_timing(float(hit.position))
	if not action.is_empty(): _animate_action(action)

func _enter_moment() -> void:
	page = Page.SKILL_READY if session.stage==1 else Page.MOMENT
	_focus = 0

func _show_result() -> void:
	page = Page.RESULT
	_loop.stop()
	_remembered = CookingBook.remember(session.result(),book_path)
	_book = CookingBook.read(book_path)
	_play("finish")

func _play(id: String) -> void:
	_voice.stream = SOUND[id] as AudioStream
	_voice.pitch_scale = 1.0
	_voice.play()

func close() -> void:
	if _restored: return
	_restore()
	closed.emit()
	var layer: Node = get_parent()
	if layer is CanvasLayer: layer.queue_free()
	else: queue_free()

func _restore() -> void:
	if _restored: return
	_restored = true
	if is_instance_valid(_hud): _hud.visible = _hud_visible
	InputManager.ui_blocking = _blocking_before
	InputManager.menu_open = _menu_before
	get_tree().paused = _paused_before
	if _loop != null: _loop.stop()
	if _voice != null: _voice.stop()

func _exit_tree() -> void:
	if _player != null and is_inside_tree(): _restore()

func _process(delta: float) -> void:
	if session==null: return
	_time += delta
	_open = minf(1.0,_open+delta*2.5)
	if page==Page.MOVING:
		_beat -= delta
		if _beat<=0.0:
			if session.done(): _show_result()
			else: _enter_moment()
	if page==Page.SKILL and not _book_open: timing.advance(delta)
	if _loop != null:
		_loop.volume_db = lerpf(-33.0,-27.0,clampf(float(session.traits.heat)/3.0,0,1))
	queue_redraw()

func _origin() -> Vector2:
	return ((size-Vector2(640,360))*0.5).round()
func _choice_rect(i: int) -> Rect2:
	return Rect2(318,210+i*34,288,30)
func _input(event: InputEvent) -> void:
	if session==null or _restored: return
	if event.is_action_pressed("ui_cancel"):
		if _book_open: _book_open = false
		else: close()
		get_viewport().set_input_as_handled()
		return
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo:
		match key.keycode:
			KEY_B: _book_open = not _book_open
			KEY_R: _sense = "smell"
			KEY_T: _sense = "taste"
			KEY_Q: _cycle_sense(-1)
			KEY_E: _cycle_sense(1)
			KEY_1,KEY_2,KEY_3:
				choose(int(key.keycode)-int(KEY_1))
			_: pass
	var pad: InputEventJoypadButton = event as InputEventJoypadButton
	if pad != null and pad.pressed:
		if pad.button_index==JOY_BUTTON_LEFT_SHOULDER: _cycle_sense(-1)
		elif pad.button_index==JOY_BUTTON_RIGHT_SHOULDER: _cycle_sense(1)
		elif pad.button_index==JOY_BUTTON_Y: _book_open = not _book_open
	if _book_open and (event.is_action_pressed("ui_down") or event.is_action_pressed("ui_right")):
		_book_selection = posmod(_book_selection+1,maxi(1,_book.size()))
	if _book_open and (event.is_action_pressed("ui_up") or event.is_action_pressed("ui_left")):
		_book_selection = posmod(_book_selection-1,maxi(1,_book.size()))
	if event.is_action_pressed("ui_down"): _focus = posmod(_focus+1,3)
	if event.is_action_pressed("ui_up"): _focus = posmod(_focus-1,3)
	if event.is_action_pressed("ui_accept") or (key!=null and key.pressed and not key.echo and key.keycode==KEY_SPACE):
		if not _book_open:
			if page==Page.PREPARE: begin_cooking()
			elif page==Page.RESULT: new_pot()
			elif page==Page.SKILL_READY: start_skill()
			elif page==Page.SKILL: hit_skill()
			else: choose(_focus)
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		var point: Vector2 = get_local_mouse_position()-_origin()
		_hover = -1
		for i: int in 3:
			if _choice_rect(i).has_point(point):
				_hover = i
				_focus = i
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse != null and mouse.button_index==MOUSE_BUTTON_LEFT and mouse.pressed:
		_click(get_local_mouse_position()-_origin())
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		get_viewport().set_input_as_handled()

func _cycle_sense(direction: int) -> void:
	var modes: Array[String] = ["look","smell","taste"]
	_sense = modes[posmod(modes.find(_sense)+direction,3)]

func _click(point: Vector2) -> void:
	if Rect2(548,320,68,22).has_point(point): close(); return
	if Rect2(24,320,150,22).has_point(point): _book_open = not _book_open; return
	if _book_open:
		for i: int in mini(6,_book.size()):
			if Rect2(326,123+i*27,126,25).has_point(point): _book_selection=i
		return
	if page in [Page.SKILL_READY,Page.SKILL] and Rect2(318,210,288,100).has_point(point):
		if page==Page.SKILL_READY: start_skill()
		else: hit_skill()
		return
	if page in [Page.PREPARE,Page.RESULT] and _choice_rect(2 if page==Page.RESULT else 1).has_point(point):
		if page==Page.PREPARE: begin_cooking()
		else: new_pot()
		return
	if page!=Page.MOMENT: return
	for i: int in 3:
		if Rect2(318+i*96,91,92,18).has_point(point): _sense = ["look","smell","taste"][i]
		if _choice_rect(i).has_point(point): choose(i)

func _text(text: String,at: Vector2,color: Color = TEXT,scale_value: int = 1) -> void:
	draw_set_transform(_origin()+at,0,Vector2.ONE*scale_value)
	PixelText.draw(self,text.to_upper(),Vector2i.ZERO,color)
	draw_set_transform(_origin())

func _wrap(text: String,width: int) -> Array[String]:
	var lines: Array[String] = []
	var line: String = ""
	for word: String in text.to_upper().split(" "):
		if line.length()+word.length()+1>width and not line.is_empty():
			lines.append(line)
			line = ""
		line += (" " if not line.is_empty() else "")+word
	if not line.is_empty(): lines.append(line)
	return lines
func _paragraph(text: String,at: Vector2,width: int,scale_value: int = 1,color: Color = TEXT) -> void:
	var row: int = 0
	for line: String in _wrap(text,width):
		_text(line,at+Vector2(0,row*(14 if scale_value==2 else 10)),color,scale_value)
		row += 1

func _draw() -> void:
	if session==null: return
	draw_rect(Rect2(Vector2.ZERO,size),Color(0.018,0.012,0.03,0.92*_open))
	draw_set_transform(_origin())
	VineStyle.paper(self,Rect2(12,18,616,327),_open,0.18,92)
	draw_texture_rect(ROOTS,Rect2(0,0,640,48),false)
	_text("LIES DEN KESSEL",Vector2(30,42),GOLD,2)
	_text("GLIMMERBEEREN-TÖPFCHEN",Vector2(30,64),TEXT)
	_draw_steps()
	_draw_station()
	if _book_open:
		_draw_book()
	elif page==Page.PREPARE:
		_text("EIN KLEINES WALDGERICHT",Vector2(330,112),GOLD)
		_paragraph("Zwei Zutaten. Drei Kochmomente. Beobachte den Kessel und gib dem Gericht deinen eigenen Charakter.",Vector2(330,136),33,2)
		_button(_choice_rect(1),"FEUER ENTZÜNDEN","ENTER ODER KLICK",true)
		_text("ZWEI ENTSCHEIDUNGEN. EIN GUTER MOMENT.",Vector2(330,286),DIM)
	elif page==Page.RESULT:
		_draw_result()
	else:
		for i: int in 3:
			var active: bool = _sense==["look","smell","taste"][i]
			VineStyle.paper(self,Rect2(318+i*96,91,92,17),1.0,0.1,300+i)
			_text(["ANSEHEN","RIECHEN [R]","PROBIEREN [T]"][i],Vector2(324+i*96,96),TEAL if active else DIM)
		VineStyle.paper(self,Rect2(318,113,288,86),1.0,0.08,137)
		_text("DER KESSEL VERÄNDERT SICH" if page==Page.MOVING else session.moment_name(),Vector2(330,123),GOLD)
		var observation: String = _feedback if page==Page.MOVING else session.observation(_sense)
		if page in [Page.SKILL_READY,Page.SKILL]:
			observation = "Lass die Beeren im goldenen Moment hineinfallen. Starte selbst, dann triff die Mitte. Der Marker pendelt so lange du möchtest."
			if page==Page.SKILL: observation = "Jetzt: die Beeren bereit halten und im goldenen Moment loslassen. LEERTASTE, ENTER oder Klick."
		_paragraph(observation,Vector2(330,140),33 if _wrap(observation,33).size()<=4 else 61,2 if _wrap(observation,33).size()<=4 else 1)
		if page==Page.MOMENT:
			var choices: Array[Dictionary] = session.choices()
			for i: int in choices.size():
				_button(_choice_rect(i),String(choices[i].name),String(choices[i].hint),_focus==i,i+1)
		elif page in [Page.SKILL_READY,Page.SKILL]:
			_draw_skill()
		else:
			_text("DER DUFT ENTFALTET SICH ...",Vector2(346,242),DIM)
			if session.stage==2: _draw_hit_stamp()
	_draw_footer()
	draw_set_transform(Vector2.ZERO)

func _button(rect: Rect2,title: String,hint: String,active: bool,number: int = 0) -> void:
	VineStyle.paper(self,rect,1.0,0.0 if active else 0.35,310+number*7)
	if active:
		draw_rect(Rect2(rect.position+Vector2(3,3),rect.size-Vector2(6,6)),Color(0.65,0.52,0.31,0.09))
		VineStyle.leaf(self,rect.position+Vector2(5,rect.size.y*0.5),1,-1,3,VineStyle.LEAF,VineStyle.LEAF_LIGHT)
	draw_rect(Rect2(rect.position+Vector2(rect.size.x-7,5),Vector2(2,2)),Color("85697a"))
	if number>0: _text(str(number),rect.position+Vector2(13,9),GOLD)
	_text(title,rect.position+Vector2(28,5),GOLD if active else TEXT,2)
	_text(hint,rect.position+Vector2(29,21),DIM)

func _draw_station() -> void:
	var result: bool = page==Page.RESULT
	var herbs_pos: Vector2 = Vector2(211+roundf(sin(_time*0.7)*0.6),76)
	draw_texture_rect(HERBS,Rect2(herbs_pos,Vector2(88,92)),false,Color(1,1,1,0.7))
	VineStyle.glow(self,Vector2(152,204),66,Color("ce7244"),0.18 if session.started and not result else 0.04)
	draw_texture_rect_region(BASE,Rect2(0,88,304,216),Rect2(36,100,152,108),Color(1,1,1,0.65 if result else 1.0))
	if session.started and not result: _draw_fire()
	draw_texture_rect_region(CAULDRON,Rect2(0,88,304,216),Rect2(36,100,152,108),Color(1,1,1,0.3 if result else 1.0))
	var center: Vector2 = Vector2(152,162)
	if result:
		draw_texture_rect(BOWL,Rect2(88,136,128,96),false)
		center = Vector2(152,186)
	_draw_broth(center,Vector2(31,12) if result else Vector2(47,13))
	_draw_steam(center,result)
	if page==Page.MOVING: _draw_action(center)
	if not result:
		for i: int in _ingredients.size():
			var at: Vector2 = Vector2(17 if i==0 else 250,224)
			var used: bool = session.started and ((i==1 and session.stage>0) or (i==0 and session.stage>1 and int(session.traits.late)==0))
			draw_texture_rect(_ingredients[i],Rect2(at,Vector2(32,32)),false,Color(1,1,1,0.25 if used else 1.0))
			_text("IM KESSEL" if used else ("2X BEEREN" if i==0 else "1X PILZ"),at+Vector2(-1,36),DIM)
		_text("GLIMMKAPPE: TROCKEN" if session.dry_batch else "GLIMMKAPPE: SAFTIG",Vector2(61,293),TEAL)
	if session.started and not session.history.is_empty():
		_text("DEINE HANDGRIFFE",Vector2(52,307),DIM)

func _draw_broth(center: Vector2,radius: Vector2) -> void:
	var active: bool = session.started
	var fruit: bool = int(session.traits.fruit)>0
	var base: Color = Color("593b4e") if fruit else Color("635644")
	if int(session.traits.bitter)>=2: base = Color("372b37")
	if not active or session.stage==0: base = Color("161322")
	elif int(session.traits.broth)==0 and not fruit: base = Color("3d3038")
	for y: int in range(-int(radius.y),int(radius.y)+1):
		var span: int = int(radius.x*sqrt(maxf(0.0,1.0-pow(y/radius.y,2))))
		var shade: Color = base.lightened(0.09 if y<0 else 0.0)
		draw_rect(Rect2(center+Vector2(-span,y),Vector2(span*2,1)),shade)
	if not active or session.stage==0: return
	var clock: float = floor(_time*10.0)/10.0
	for i: int in 8:
		var angle: float = i*2.399+clock*0.16
		var at: Vector2 = center+Vector2(cos(angle)*radius.x*0.7,sin(angle)*radius.y*0.6)
		var color: Color = Color("ad86bc") if fruit and i%2==0 else Color("aa927e")
		draw_rect(Rect2(at.round(),Vector2(3,2)),color)
		if i%3==0:
			draw_rect(Rect2(at.round()+Vector2(1,1),Vector2(4,2)),Color("66525f"))
	for i: int in 6:
		var t: float = fposmod(clock*(0.3 if page==Page.RESULT else 0.7)+i*0.163,1.0)
		var at: Vector2 = center+Vector2(sin(i*7.3)*radius.x*0.75,cos(i*3.1)*radius.y*0.65)
		if t<0.22:
			draw_rect(Rect2(at.round(),Vector2(2,1)),Color("d4bfa2"))
		if fruit and t>0.8:
			draw_rect(Rect2(at.round()+Vector2(2,-1),Vector2.ONE),Color("b69cdd"))
	if fruit:
		for strand: int in 3:
			var points: PackedVector2Array = []
			for i: int in 15:
				points.append((center+Vector2((i-7)*radius.x/10.0,sin(i*0.45+clock+strand*2)*radius.y*0.35)).round())
			draw_polyline(points,Color(0.55,0.39,0.68,0.32),1.0)

func _draw_steam(center: Vector2,result: bool) -> void:
	if not session.started or session.stage==0: return
	var clock: float = floor(_time*10.0)/10.0
	for i: int in 4:
		var t: float = fposmod(clock*0.20+i*0.257,1.0)
		var x: float = sin(clock*0.6+i*2.2)*8.0+(i-1.5)*13
		for k: int in 5:
			var at: Vector2 = center+Vector2(x+sin(k*0.6+clock+i)*3,-8-t*46-k*2)
			var alpha: float = sin(t*PI)*0.13*(0.5 if result else 1.0)
			draw_rect(Rect2(at.round(),Vector2(3,2)),Color(0.77,0.73,0.83,alpha))

func _draw_fire() -> void:
	if _motion=="rest" and page!=Page.MOVING: return
	var frame: int = int(_time*8.0)%6
	var intensity: float = 0.65+0.35*clampf(float(session.traits.heat)/2.0,0,1)
	draw_texture_rect_region(FIRE,Rect2(118,200,68,56),Rect2(frame*34,0,34,28),Color(1,1,1,intensity))

func _draw_action(center: Vector2) -> void:
	var t: float = clampf(1.0-_beat/1.4,0,1)
	if _motion in ["stir","crush"]:
		var tip: Vector2 = center+Vector2(sin(t*TAU*1.5)*27,cos(t*TAU*1.5)*9)
		var grip: Vector2 = center+Vector2(35,-50)
		draw_line(grip.round(),tip.round(),Color("21172a"),5)
		draw_line((grip-Vector2(1,0)).round(),tip.round(),Color("ad8a7e"),3)
		draw_rect(Rect2(tip.round()-Vector2(4,2),Vector2(7,4)),Color("7c6769"))
	elif _motion in ["scatter","pour"]:
		for i: int in 7:
			var p: float = fposmod(t*1.7+i*0.14,1.0)
			var at: Vector2 = center+Vector2(-31+p*26,-51+p*p*49)
			draw_rect(Rect2(at.round(),Vector2(2,3)),TEAL if _motion=="pour" else Color("ad81d0"))
	elif _motion=="fan":
		VineStyle.glow(self,center+Vector2(0,62),35,Color("e79950"),sin(t*PI)*0.5)
	elif _motion=="rest":
		VineStyle.glow(self,center,45,TEAL,sin(t*PI)*0.25)

func _draw_result() -> void:
	var result: Dictionary = session.result()
	_text(String(result.quality),Vector2(330,104),TEAL)
	_paragraph(String(result.name),Vector2(330,123),32,2,GOLD)
	_paragraph(String(result.description),Vector2(330,165),61,1,TEXT)
	_text("SO HAST DU ES GEKOCHT",Vector2(330,205),DIM)
	var y: int = 221
	for note: String in result.notes as Array:
		_text("- "+note,Vector2(330,y),TEXT)
		y += 15
	_button(_choice_rect(2),"NOCH EIN TÖPFCHEN","ENTER ODER KLICK",true)
	_text("IM KOCHBUCH NOTIERT" if _remembered else "REZEPT FÜR DIESE RUNDE GEMERKT",Vector2(70,270),TEAL)

func _draw_steps() -> void:
	draw_line(Vector2(357,57),Vector2(559,57),Color("160f21"),7)
	draw_line(Vector2(357,55),Vector2(559,55),Color("655061"),2)
	for i: int in 3:
		var center: Vector2 = Vector2(364+i*96,56)
		var complete: bool = session.started and session.stage>i
		var active: bool = session.stage==i and page!=Page.PREPARE
		var ink: Color = TEAL if complete else (GOLD if active else Color("887b8f"))
		if active: VineStyle.glow(self,center,19,GOLD,0.13+sin(_time*2.0)*0.025)
		var rim: PackedVector2Array = []
		for corner: Vector2 in [Vector2(-9,-14),Vector2(8,-14),Vector2(14,-8),Vector2(14,8),Vector2(7,14),Vector2(-9,14),Vector2(-14,8),Vector2(-14,-7)]: rim.append(center+corner)
		draw_colored_polygon(rim,Color("120e1c"))
		for j: int in rim.size(): rim[j]=center+(rim[j]-center)*0.83
		draw_colored_polygon(rim,Color("4c3949"))
		draw_line(center-Vector2(8,8),center+Vector2(-8,8),Color("655061"),2)
		draw_line(center-Vector2(9,10),center+Vector2(9,-10),Color("85697a"),2)
		if i==0:
			for j: int in 3: draw_rect(Rect2(center+Vector2(j*4-6,-2-j%2*4),Vector2(3,10+j%2*4)),ink)
		elif i==1:
			for offset: Vector2 in [Vector2(-4,0),Vector2(3,2),Vector2(0,-5)]:
				draw_rect(Rect2(center+offset-Vector2(2,2),Vector2(5,5)),ink)
				draw_rect(Rect2(center+offset-Vector2(1,2),Vector2(2,1)),TEXT if active else Color("a896b6"))
			VineStyle.leaf(self,center+Vector2(2,-7),1,-1,3,VineStyle.LEAF,VineStyle.LEAF_LIGHT)
		else:
			draw_line(center+Vector2(-7,-3),center+Vector2(7,-3),ink,2)
			draw_rect(Rect2(center+Vector2(-5,-1),Vector2(10,5)),ink)
			draw_rect(Rect2(center+Vector2(-3,4),Vector2(6,2)),ink)
		_text(["01 BASIS","02 GEFÜHL","03 ABSCHLUSS"][i],center+Vector2(-22,21),ink)
		if complete: _text("+",center+Vector2(15,-6),TEAL)

func _draw_skill() -> void:
	VineStyle.paper(self,Rect2(318,210,288,100),1.0,0.05,721)
	_text("DEN RICHTIGEN MOMENT SPÜREN",Vector2(331,221),GOLD)
	var rail: Rect2 = Rect2(334,246,256,17)
	draw_rect(rail.grow(3),Color("120e1c"))
	draw_rect(rail,Color("49394b"))
	draw_rect(Rect2(rail.position+Vector2(87,0),Vector2(82,17)),Color("63664d"))
	draw_rect(Rect2(rail.position+Vector2(114,0),Vector2(28,17)),Color("bc9453"))
	draw_rect(Rect2(rail.position+Vector2(119,2),Vector2(18,13)),GOLD.darkened(0.12))
	for i: int in 17:
		draw_rect(Rect2(334+i*16,259,1,4),Color("241b2b"))
	var x: float = roundf(334+timing.position*256)
	VineStyle.glow(self,Vector2(462,253),19,GOLD,0.11+sin(_time*3.0)*0.03)
	draw_line(Vector2(x,240),Vector2(x,267),Color("120d1c"),5)
	draw_line(Vector2(x,240),Vector2(x,267),TEXT,2)
	VineStyle.leaf(self,Vector2(x,239),1,-1,4,TEAL,Color("c7f7d4"))
	_text("[ENTER] BEREIT MACHEN" if page==Page.SKILL_READY else "[LEERTASTE / ENTER] BEEREN LOSLASSEN",Vector2(334,283),GOLD)
	_text("STARTET ERST, WENN DU BEREIT BIST" if page==Page.SKILL_READY else "GOLDENE MITTE = BESONDERS SANFT",Vector2(334,297),DIM)

func _draw_hit_stamp() -> void:
	var perfect: bool = session.timing_grade=="perfect"
	_text("GOLDENE MITTE!" if perfect else ("GUTER MOMENT" if session.timing_grade=="good" else "MIT GEFÜHL ABRUNDEN"),Vector2(357,271),GOLD if perfect else TEAL,2)

func _draw_book() -> void:
	draw_texture_rect(BOOK_ART,Rect2(310,78,304,240),false)
	var ink: Color = Color("48323d")
	var muted: Color = Color("79615c")
	_text("KOCHBUCH",Vector2(331,94),ink,2)
	_text("DEINE ENTDECKUNGEN",Vector2(331,113),muted)
	if _book.is_empty():
		_paragraph("Noch keine Notizen. Dein erstes Gericht wird hier festgehalten.",Vector2(332,143),26,1,ink)
		_paragraph("Ein Rezept. Viele eigene Wege. Koche, koste und entdecke.",Vector2(478,131),26,1,ink)
		return
	_book_selection = clampi(_book_selection,0,mini(5,_book.size()-1))
	var keys: Array = _book.keys()
	for i: int in mini(6,keys.size()):
		var entry: Dictionary = _book[keys[i]]
		var at: Vector2 = Vector2(331,128+i*27)
		if i==_book_selection:
			draw_rect(Rect2(at-Vector2(5,3),Vector2(124,25)),Color(0.29,0.32,0.22,0.15))
			VineStyle.leaf(self,at+Vector2(-3,6),1,-1,3,Color("4f6350"),Color("70825d"))
		_paragraph(String(entry.name),at+Vector2(5,0),25,1,ink)
	var selected: Dictionary = _book[keys[_book_selection]]
	_paragraph(String(selected.name),Vector2(478,97),27,1,ink)
	_paragraph(String(selected.get("quality","DEINE VARIATION")),Vector2(478,125),27,1,muted)
	_paragraph(String(selected.get("description","")),Vector2(478,153),27,1,ink)
	_text("DEINE HANDGRIFFE",Vector2(478,218),muted)
	var y: int = 234
	for note: String in selected.get("notes",[]) as Array:
		_paragraph(note,Vector2(478,y),27,1,ink)
		y += 23
	_text("KLICK / PFEILE: BLÄTTERN",Vector2(333,298),muted)

func _draw_footer() -> void:
	draw_set_transform(_origin()+Vector2(0,360),0,Vector2(1,-1))
	draw_texture_rect(ROOTS,Rect2(0,0,640,48),false)
	draw_set_transform(_origin())
	VineStyle.paper(self,Rect2(23,321,185 if _book_open else 117,20),1.0,0.1,971)
	VineStyle.paper(self,Rect2(542,321,76,20),1.0,0.1,973)
	_text("[B] KOCHBUCH" if not _book_open else "[B] ZURÜCK ZUM KESSEL",Vector2(28,328),GOLD)
	_text("[ESC] ZURÜCK",Vector2(548,328),DIM)
