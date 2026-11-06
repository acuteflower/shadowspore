extends Node
var failures: int = 0
var checks: int = 0
const BOOK: String = "user://cooking_test_only.json"
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/cooking-"+name+".png")
func _run() -> void:
	var variants: Dictionary = {}
	var layout: CookingWindow = CookingWindow.new()
	for dry: bool in [false,true]:
		for a: int in 3:
			for b: int in 3:
				for c: int in 3:
					var session: CookingSession = CookingSession.new("glimmer_pot",dry)
					check(session.choose(0).is_empty() and session.stage==0,"cannot cook before starting")
					session.begin()
					for step: int in 3:
						var choice: int = [a,b,c][step]
						check(session.choices().size()==3,"each moment offers three choices")
						for mode: String in ["look","smell","taste"]:
							check(not session.observation(mode).is_empty(),"sensory clue exists")
							check(layout._wrap(session.observation(mode),33).size()<=5,"all routes fit the observation panel")
						if step==1:
							check(session.choose(choice).is_empty(),"timing cannot be bypassed by choices")
							check(not session.resolve_timing([0.5,0.62,0.92][choice]).is_empty(),"timing commits")
						else: check(not session.choose(choice).is_empty(),"choice commits")
					check(session.done() and session.history.size()==3,"three moments complete the recipe")
					var result: Dictionary = session.result()
					check(not result.is_empty() and (result.notes as Array).size()==3,"result preserves exact method")
					check(session.choose(0).is_empty(),"finished recipe cannot accept more choices")
					variants[result.variant] = true
	check(variants.size()>=5,"cooking methods yield genuinely different dishes")
	layout.free()
	var rescued: CookingSession = CookingSession.new()
	rescued.begin(); rescued.choose(1); rescued.resolve_timing(0.5); rescued.choose(0)
	check(rescued.result().variant=="rescued","a dark roast can be rescued with perfect timing")
	var burnt: CookingSession = CookingSession.new("glimmer_pot",true)
	burnt.begin(); burnt.choose(1); burnt.resolve_timing(0.92); burnt.choose(2)
	check(burnt.result().variant=="smoky","ignoring strong heat leaves bitterness")
	check(CookingBook.remember(rescued.result(),BOOK),"recipe discovery writes isolated test book")
	check(CookingBook.read(BOOK).size()==1,"discovery survives reload")
	check(CookingBook.remember(rescued.result(),BOOK) and CookingBook.read(BOOK).size()==1,"same discovery does not duplicate")
	var meter: CookingTiming = CookingTiming.new()
	meter.begin()
	meter.advance(0.8)
	var position: float = meter.position
	meter.begin()
	for frame: int in 80: meter.advance(0.01)
	check(is_equal_approx(meter.position,position),"timing independent of frame rate")
	check(not meter.hit().is_empty() and meter.hit().is_empty(),"a gesture commits once")
	check(CookingTiming.grade(0.5)=="perfect" and CookingTiming.grade(0.62)=="good" and CookingTiming.grade(0.92)=="rough","three meaningful timing bands")
	check(CookingTiming.grade(0.45)==CookingTiming.grade(0.55),"symmetric target")
	meter.begin(); meter.advance(11.0)
	check(meter.position>=0.0 and meter.position<=1.0,"long gestures bounce inside the rail")
	var stopped: float = meter.position
	meter.hit(); meter.advance(1.0)
	check(meter.position==stopped,"committed marker stays still")
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await get_tree().process_frame
	var player: Player = world._players.get_child(0) as Player
	player.get_node("OpeningGuide").set_process(false)
	player.quests.set_physics_process(false)
	var inventory: Array = player.inventory.slots.duplicate(true)
	var equipment: Dictionary = player.inventory.equipment.duplicate(true)
	var menu: PauseMenu = player._hud.get_node("PauseMenu") as PauseMenu
	menu._set_open(true)
	menu._select_tab(3)
	var button: bool = false
	for item: Dictionary in menu._items:
		if String(item.get("action",""))=="cook": button=true
	check(button,"developer tab offers cooking")
	menu._run_action("cook")
	await get_tree().process_frame
	var opened: CanvasLayer = get_tree().root.get_node_or_null("CookingLayer") as CanvasLayer
	check(opened != null and opened.get_child(0) is CookingWindow,"developer button opens actual kitchen")
	if opened != null: (opened.get_child(0) as CookingWindow).close()
	await get_tree().process_frame
	check(not get_tree().paused and not InputManager.ui_blocking,"menu-launched kitchen releases input on close")
	# Use the real window with an isolated recipe book, never touch actual discoveries.
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer=40
	get_tree().root.add_child(layer)
	var kitchen: CookingWindow = CookingWindow.new()
	layer.add_child(kitchen)
	kitchen.start(player,BOOK)
	check(get_tree().paused and InputManager.ui_blocking and not player._hud.visible,"kitchen owns pause and input")
	await get_tree().create_timer(0.5,true).timeout
	await shot("prepare")
	kitchen.begin_cooking()
	kitchen._process(2.0)
	check(kitchen.page==CookingWindow.Page.MOMENT,"fire starts first observation")
	var reading: int = kitchen.session.stage
	await get_tree().create_timer(0.3,true).timeout
	check(kitchen.session.stage==reading,"waiting never advances or burns a decision")
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_R
	key.pressed = true
	kitchen._input(key)
	check(kitchen._sense=="smell" and kitchen.session.stage==reading,"keyboard smelling is free and does not consume a turn")
	var pad: InputEventJoypadButton = InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_RIGHT_SHOULDER
	pad.pressed = true
	kitchen._input(pad)
	check(kitchen._sense=="taste","controller can select tasting")
	kitchen._sense = "look"
	for stage: int in 3:
		for action: Dictionary in kitchen.session.choices():
			check(PixelText.width(String(action.name))*2<=250,"choice label fits card")
		for mode: String in ["look","smell","taste"]:
			check(kitchen._wrap(kitchen.session.observation(mode),33).size()<=5,"observation fits reading area")
		if stage==0: await shot("moment")
		if stage==1:
			check(kitchen.page==CookingWindow.Page.SKILL_READY,"second moment waits for explicit start")
			await shot("skill-ready")
			kitchen.start_skill()
			kitchen.timing.advance((0.5-0.12)/kitchen.timing.speed)
			kitchen._book_open=true
			var held: float = kitchen.timing.position
			kitchen._process(0.3)
			check(kitchen.timing.position==held,"reading the book pauses the gesture")
			kitchen._book_open=false
			# Hold the visual frame still to capture the actual target and marker.
			kitchen.set_process(false)
			await shot("skill")
			key.keycode=KEY_SPACE
			kitchen._input(key)
			check(kitchen.session.timing_grade=="perfect","space releases berries into gold zone")
			kitchen.hit_skill()
			check(kitchen.session.stage==2,"repeated timing hit ignored")
			kitchen.set_process(true)
		else: kitchen.choose([1,2,0][stage])
		var committed: int = kitchen.session.stage
		kitchen.choose(0)
		check(kitchen.session.stage==committed,"animation blocks repeated choice")
		if stage==1: await shot("pour")
		kitchen._process(2.0)
	check(kitchen.page==CookingWindow.Page.RESULT and kitchen._remembered,"served dish is recorded")
	await shot("result")
	for variant_b: float in [0.5,0.62,0.92]:
		var example: CookingSession = CookingSession.new()
		example.begin(); example.choose(0); example.resolve_timing(variant_b); example.choose(1)
		CookingBook.remember(example.result(),BOOK)
	kitchen._book=CookingBook.read(BOOK)
	kitchen._book_open=true
	await shot("book")
	var old_selection: int = kitchen._book_selection
	key.keycode=KEY_DOWN
	kitchen._input(key)
	check(kitchen._book_selection!=old_selection,"journal supports keyboard page selection")
	kitchen._click(Vector2(350,135))
	check(kitchen._book_selection==0,"journal supports clicking discoveries")
	kitchen._book_open=false
	kitchen._click(kitchen._choice_rect(2).get_center())
	check(kitchen.page==CookingWindow.Page.PREPARE,"result button starts a fresh pot")
	kitchen.close()
	await get_tree().process_frame
	check(not get_tree().paused and not InputManager.ui_blocking and player._hud.visible,"closing restores game and HUD")
	check(player.inventory.slots==inventory and player.inventory.equipment==equipment,"tasting kitchen does not mutate inventory")
	var abort_layer: CanvasLayer = CanvasLayer.new()
	get_tree().root.add_child(abort_layer)
	var abort_window: CookingWindow = CookingWindow.new()
	abort_layer.add_child(abort_window)
	abort_window.start(player,BOOK)
	abort_window.begin_cooking()
	abort_layer.queue_free()
	await get_tree().process_frame
	check(not get_tree().paused and not InputManager.ui_blocking and player._hud.visible,"unexpected window removal releases pause and input")
	DirAccess.remove_absolute(BOOK)
	DirAccess.remove_absolute(BOOK+".tmp")
	print("COOKING: %d checks, %d failures, %d dish variants" % [checks,failures,variants.size()])
	get_tree().quit(1 if failures else 0)
