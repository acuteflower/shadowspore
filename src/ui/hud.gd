extends CanvasLayer
## Local player's HUD. Created by the owning Player only. It grows in (`open`): every vine unrolls from where it is rooted, see
## assets/shaders/hud_reveal.gdshader; until then it is not drawn at all. `open` runs by itself a frame after the HUD is built, unless the
## intro is running (only the wound border stays active until she is out).

const REVEAL: Shader = preload("res://assets/shaders/hud_reveal.gdshader")
const PARTS: Array[Dictionary] = [ ## node, where it is rooted (viewport 0..1), delay and duration (s)
	{"node": "ClockVine", "origin": Vector2(0.0, 0.07), "delay": 0.0, "time": 1.5},
	{"node": "PurseVine", "origin": Vector2(1.0, 0.07), "delay": 0.2, "time": 1.5},
	{"node": "Hotbar", "origin": Vector2(0.5, 1.0), "delay": 0.4, "time": 1.4},
	{"node": "HealthBar", "origin": Vector2(0.37, 0.97), "delay": 0.95, "time": 1.2},
	{"node": "StaminaBar", "origin": Vector2(0.63, 0.97), "delay": 0.95, "time": 1.2},
	{"node": "QuestVine", "origin": Vector2(1.0, 0.2), "delay": 0.5, "time": 1.3},
	{"node": "BlinkIcon", "origin": Vector2(0.58, 1.0), "delay": 1.2, "time": 0.9},
]

var _intro_active: bool = false
var _intro_parts: Array[Dictionary] = []
var _story_quests: QuestComponent
var _story_world: bool = false
var _opened: bool = false
var _was_locked: bool = false ## the story held parts of the HUD back until now
var _prepared: Array[Dictionary] = [] ## {node, material, children: [[child, material, use_parent]]}

const IDLE_HIDE_SECONDS: float = 10.0 ## no input, no cursor movement and no movement of her for this long: the HUD fades away
const IDLE_FADE_OUT: float = 1.4 ## seconds to fade away
const IDLE_FADE_IN: float = 0.25 ## seconds to come back on activity
const IDLE_PARTS: Array[String] = ["ClockVine", "PurseVine", "Hotbar", "HealthBar", "StaminaBar", "BlinkIcon", "StatusTags", "QuestVine", "HintCard", "FishingHud"]

var _player: Node2D
var _idle_time: float = 0.0
var _idle_alpha: float = 1.0 ## 1 = HUD shown, 0 = hidden by idling
var _cover_alpha: Dictionary = {} ## part name -> fade of the full-screen menus (QuestVine, HintCard)
var _last_pos: Vector2 = Vector2.INF
var _fold_base: Dictionary = {} ## part -> its offsets from hud.tscn, before the hotbar fold moved it


## Any real input or cursor movement counts as activity.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).relative != Vector2.ZERO:
			_idle_time = 0.0
	elif event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		_idle_time = 0.0
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.25:
		_idle_time = 0.0


## True while something keeps the HUD up even without input (menus, cutscenes, fishing, taking damage).
func _holds_hud(covered: bool) -> bool:
	if covered or _intro_active or InputManager.ui_blocking or InputManager.menu_open:
		return true
	if _player != null and is_instance_valid(_player):
		if _last_pos != Vector2.INF and _player.global_position.distance_squared_to(_last_pos) > 0.0001:
			return true
		_last_pos = _player.global_position
		var fishing: FishingComponent = _player.get("fishing") as FishingComponent
		if fishing != null and fishing.state != FishingComponent.S.IDLE:
			return true
	return false


func _on_player_damaged(_amount: float, _from: Vector2, _knockback: float) -> void:
	_idle_time = 0.0


func _apply_idle_fade(delta: float, covered: bool) -> void:
	if _holds_hud(covered):
		_idle_time = 0.0
	else:
		_idle_time += delta
	var fade_out: bool = _idle_time >= IDLE_HIDE_SECONDS
	var speed: float = 1.0 / (IDLE_FADE_OUT if fade_out else IDLE_FADE_IN)
	_idle_alpha = move_toward(_idle_alpha, 0.0 if fade_out else 1.0, delta * speed)
	for part: String in IDLE_PARTS:
		var node: CanvasItem = get_node_or_null(part) as CanvasItem
		if node != null:
			node.modulate.a = _idle_alpha * float(_cover_alpha.get(part, 1.0))


## Full-screen menus cover the quest branch and tutorial card.
func _process(delta: float) -> void:
	var skills: SkillTreeWindow = get_node_or_null("SkillTreeWindow") as SkillTreeWindow
	var progress: ProgressWindow = get_node_or_null("ProgressWindow") as ProgressWindow
	var pause: CanvasItem = get_node_or_null("PauseMenu") as CanvasItem
	var covered: bool = $InventoryWindow.visible or $MapWindow.visible or $QuestJournal.visible or (skills != null and skills.visible) or (progress != null and progress.visible) or (pause != null and pause.visible) ## the Escape menu too
	var boss: BossBar = get_node_or_null("BossBar") as BossBar
	if boss != null:
		boss.set_covered(covered)
	for part: String in ["QuestVine", "HintCard"]:
		_cover_alpha[part] = move_toward(float(_cover_alpha.get(part, 1.0)), 0.0 if covered else 1.0, delta * 8.0)
	_apply_idle_fade(delta, covered)
	_follow_hotbar_fold()


## The folded hotbar sinks and draws in: the sap vines stay on its ends, the skill crystal sinks and fades with the pendants.
func _follow_hotbar_fold() -> void:
	var bar: Hotbar = $Hotbar as Hotbar
	if bar == null:
		return
	_shift_part("Hotbar", Vector2(0.0, bar.drop))
	_shift_part("HealthBar", Vector2(bar.inset, bar.drop))
	_shift_part("StaminaBar", Vector2(-bar.inset, bar.drop))
	_shift_part("BlinkIcon", Vector2(-bar.inset, bar.drop + bar.sink))
	_shift_part("StatusTags", Vector2(0.0, bar.drop)) ## burning and the like stay above the health vine
	($BlinkIcon as CanvasItem).self_modulate.a = bar.shown


func _shift_part(part: String, by: Vector2) -> void:
	var node: Control = get_node_or_null(part) as Control
	if node == null:
		return
	if not _fold_base.has(part):
		_fold_base[part] = Rect2(node.offset_left, node.offset_top, node.offset_right, node.offset_bottom) ## (left, top, right, bottom) as laid out in hud.tscn
	var base: Rect2 = _fold_base[part]
	node.offset_left = base.position.x + by.x
	node.offset_right = base.size.x + by.x
	node.offset_top = base.position.y + by.y
	node.offset_bottom = base.size.y + by.y


func _ready() -> void:
	$Hotbar.visibility_changed.connect(func() -> void: _sync_hotbar_bars.call_deferred())
	process_mode = Node.PROCESS_MODE_ALWAYS ## the HUD keeps moving while the Escape menu pauses the game


## `player` is untyped on purpose: the player scene preloads this HUD.
func bind(player: Node) -> void:
	_player = player as Node2D
	if player.health != null:
		player.health.damaged.connect(_on_player_damaged)
	$SneakVignette.bind(player.stealth)
	$StaminaBar.bind(player.stamina)
	$HealthBar.bind(player.health)
	$PurseVine.bind(player.progress)
	$ClockVine.bind(player)
	$DamageVignette.bind(player.health)
	var border: WoundBorder = WoundBorder.new() ## the permanent red border of the wounded state
	border.name = "WoundBorder"
	add_child(border)
	move_child(border, $DamageVignette.get_index() + 1)
	border.bind(player)
	$DeathScreen.bind(player)
	$PauseMenu.bind(player)
	$BlinkIcon.bind(player.stepper) ## the skill crystal shows the shadow step (the blink is archived)
	$Hotbar.bind(player.inventory)
	$Hotbar.bind_progress(player.progress)
	$InventoryWindow.bind(player.inventory, $Hotbar)
	$MapWindow.bind(player)
	$SkillTreeWindow.bind(player)
	$ProgressWindow.bind(player)
	$QuestJournal.bind(player)
	var tags: StatusTags = StatusTags.new() ## burning and the like, above the left end of the health vine
	tags.name = "StatusTags"
	tags.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	tags.offset_left = -198.0
	tags.offset_right = -20.0
	tags.offset_top = -72.0
	tags.offset_bottom = -52.0
	add_child(tags)
	tags.bind(player.effects)
	var boss_bar: BossBar = BossBar.new() ## the boss's health: `get_tree().call_group("boss_bar", "track", name, health)`
	boss_bar.name = "BossBar"
	add_child(boss_bar)
	var fishing_hud: FishingHud = FishingHud.new() ## the rod's bait tags (docs/fishing.md)
	fishing_hud.name = "FishingHud"
	add_child(fishing_hud)
	fishing_hud.bind(player)
	var river_book: RiverBook = RiverBook.new()
	river_book.name = "RiverBook"
	add_child(river_book)
	river_book.bind(player)
	if player.quests != null:
		var quest_vine: QuestVine = QuestVine.new()
		quest_vine.name = "QuestVine"
		quest_vine.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		quest_vine.offset_left = -(QuestVine.LENGTH + 24.0)
		quest_vine.offset_top = 80.0
		quest_vine.offset_right = 0.0
		quest_vine.offset_bottom = 252.0
		add_child(quest_vine)
		quest_vine.bind(player, player.quests, player.tracked)
		var dialogue: DialogueBox = DialogueBox.new() ## speech scenes (the quest steps start them)
		dialogue.name = "DialogueBox"
		add_child(dialogue)
		dialogue.bind(player.quests)
		var speech: SpeechBox = SpeechBox.new() ## what is said while she steers (the barks)
		speech.name = "SpeechBox"
		add_child(speech)
		speech.bind(player.quests, dialogue)
		var bubbles: BubbleRunner = BubbleRunner.new() ## in-world overhead speech bubbles (falls back to SpeechBox)
		bubbles.name = "BubbleRunner"
		add_child(bubbles)
		bubbles.bind(player, speech)
		var hint: HintCard = HintCard.new() ## the sneaking tutorial card
		hint.name = "HintCard"
		add_child(hint)
		hint.bind(player.quests, dialogue, player.tracked)
	_story_world = get_tree().get_first_node_in_group("world") is WorldLevel
	_story_quests = player.quests
	if _story_quests != null:
		_story_quests.changed.connect(_refresh_story_hud)
	_refresh_story_hud()
	_prepare()
	_open_when_visible.call_deferred()


## Every vine gets its own reveal material (its children use it too), at 0: nothing of it shows.
func _prepare(only: Array = []) -> void:
	for part: Dictionary in PARTS:
		if not only.is_empty() and not String(part.node) in only:
			continue
		var node: Control = get_node_or_null(String(part.node)) as Control
		if node == null:
			continue
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = REVEAL
		material.set_shader_parameter("origin", part.origin)
		material.set_shader_parameter("reveal", 0.0)
		var saved: Array = []
		for child: Node in node.find_children("*", "CanvasItem", true, false):
			var item: CanvasItem = child as CanvasItem
			saved.append([item, item.material, item.use_parent_material])
			item.use_parent_material = true
		_prepared.append({"part": part, "node": node, "original": node.material, "material": material, "children": saved})
		node.material = material


func _open_when_visible() -> void:
	await get_tree().process_frame
	if visible and not _intro_active:
		open()


## The HUD grows in from its roots (about 2.5 s).
func open() -> void:
	if _opened:
		return
	_opened = true
	var tween: Tween = create_tween().set_parallel(true)
	for i: int in _prepared.size():
		var part: Dictionary = _prepared[i].part as Dictionary
		tween.tween_property(_prepared[i].material as ShaderMaterial, "shader_parameter/reveal", 1.0, float(part.time)).set_delay(float(part.delay)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(_finish_reveal)


## Back to normal drawing: the widgets' own materials return.
func _finish_reveal() -> void:
	for entry: Dictionary in _prepared:
		(entry.node as Control).material = entry.original as Material
		for saved: Array in entry.children:
			var item: CanvasItem = saved[0] as CanvasItem
			if is_instance_valid(item):
				item.material = saved[1] as Material
				item.use_parent_material = bool(saved[2])
	_prepared.clear()


## These systems are introduced later. The quest flag is persisted with quest state;
## the knight/combat sequence that will unlock it is deliberately not implemented yet.
func _refresh_story_hud() -> void:
	var unlocked: bool = not _story_world or (_story_quests != null and _story_quests.has_flag("hud_unlocked"))
	var config: Dictionary = DataRegistry.get_entry("ground", "story_start")
	var grow: bool = unlocked and _story_world and _was_locked and _opened and not _intro_active and _prepared.is_empty()
	if grow: ## the vines that were held back grow in from their roots when she first leaves the hut
		_prepare(config.get("hidden_hud", []) as Array)
	for part: String in config.get("hidden_hud", []) as Array:
		var node: CanvasItem = get_node_or_null(part) as CanvasItem
		if node != null:
			node.visible = unlocked
	_sync_hotbar_bars()
	if grow:
		_opened = false
		open()
	_was_locked = not unlocked


## Keep the wound overlay alive beneath the cinematic fade; suspend other HUD parts.
func begin_intro() -> void:
	$QuestJournal.interrupt()
	var skills: SkillTreeWindow = get_node_or_null("SkillTreeWindow") as SkillTreeWindow
	if skills != null and skills._owns_input:
		skills._finish_close()
	var progress: ProgressWindow = get_node_or_null("ProgressWindow") as ProgressWindow
	if progress != null and progress._owns_input:
		progress._finish_close()
	_intro_active = true
	_intro_parts.clear()
	for child: Node in get_children():
		if child is CanvasItem and not child is WoundBorder and not child is PauseMenu and not child is DialogueBox:
			_intro_parts.append({"node": child, "visible": (child as CanvasItem).visible, "processing": child.is_processing()})
			(child as CanvasItem).hide()
			child.set_process(false)

func end_intro() -> void:
	for state: Dictionary in _intro_parts:
		if is_instance_valid(state.node):
			(state.node as CanvasItem).visible = bool(state.visible)
			(state.node as Node).set_process(bool(state.processing))
	_intro_parts.clear()
	_intro_active = false
	_refresh_story_hud()
	open()

func _sync_hotbar_bars() -> void:
	if _intro_active:
		return
	$HealthBar.visible = $Hotbar.visible
	$StaminaBar.visible = $Hotbar.visible
