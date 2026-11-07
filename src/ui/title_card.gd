class_name TitleCard
extends CanvasLayer
## The title card: the SHADOWSPORE logo on its own night, over everything (layer 97). The story shows it once, in the black after Ellie has gone to sleep (SleepScene),
## and the developer menu can show it again. Sequence: black, the night fades in, the logo builds itself (TitleLogo.play_build), holds, and is taken apart again
## (TitleLogo.play_exit), then the card fades to black and `finished` fires. Any of interact / primary action / accept / cancel or a click skips ahead (after a
## short guard): during the build it completes it, during the hold it starts the exit. Runs in real time, so pause and time scale do not matter.

signal finished

const BACKDROP: Shader = preload("res://assets/shaders/title_backdrop.gdshader")
const LOGO_SIZE: Vector2 = Vector2(440.0, 240.0)
const FADE_IN: float = 0.9
const FADE_OUT: float = 0.6

enum Stage { FADE_IN, BUILD, HOLD, EXIT, FADE_OUT, DONE }

var hold_time: float = 2.8 ## seconds the finished logo stays
var input_guard: float = 0.8 ## seconds before a key press counts
var exit_time: float = 1.8

var stage: Stage = Stage.FADE_IN
var _t0_usec: int = 0
var _stage_t0: float = 0.0
var _black: ColorRect
var _backdrop: ColorRect
var _material: ShaderMaterial
var _logo: TitleLogo
var _shake: float = 0.0
var _shake_t0: float = 0.0


## Shows the card over everything; `await card.finished`.
static func show_card(host: Node) -> TitleCard:
	var card: TitleCard = TitleCard.new()
	card.name = "TitleCard"
	host.get_tree().root.add_child(card)
	return card


func _ready() -> void:
	layer = 97
	process_mode = Node.PROCESS_MODE_ALWAYS
	_t0_usec = Time.get_ticks_usec()
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_black)
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = BACKDROP
	_backdrop.material = _material
	_backdrop.modulate.a = 0.0
	add_child(_backdrop)
	_logo = TitleLogo.new()
	_logo.visible = false
	add_child(_logo)
	_logo.built.connect(_on_built)
	_logo.exited.connect(_on_exited)
	_logo.impact.connect(_on_impact)
	get_viewport().size_changed.connect(_layout)
	_layout()


func clock() -> float:
	return float(Time.get_ticks_usec() - _t0_usec) / 1000000.0


func _layout() -> void:
	var view: Vector2 = get_viewport().get_visible_rect().size
	_material.set_shader_parameter("size", view)
	_logo.position = ((view - LOGO_SIZE) / 2.0).floor() + Vector2(0.0, -6.0)


func _set_stage(s: Stage) -> void:
	stage = s
	_stage_t0 = clock()


## Skips ahead: completes the build, or ends the hold.
func skip() -> void:
	match stage:
		Stage.FADE_IN:
			_start_build()
		Stage.BUILD:
			_logo.skip_build()
		Stage.HOLD:
			_start_exit()


func _start_build() -> void:
	_backdrop.modulate.a = 1.0
	_set_stage(Stage.BUILD)
	_logo.play_build()


func _start_exit() -> void:
	_set_stage(Stage.EXIT)
	_logo.play_exit(exit_time)


func _on_built() -> void:
	if stage == Stage.BUILD:
		_set_stage(Stage.HOLD)


func _on_exited() -> void:
	_set_stage(Stage.FADE_OUT)


func _on_impact() -> void:
	_shake = 2.0
	_shake_t0 = clock()


func _process(_delta: float) -> void:
	var t: float = clock()
	_material.set_shader_parameter("time", t)
	var age: float = t - _stage_t0
	match stage:
		Stage.FADE_IN:
			_backdrop.modulate.a = clampf(age / FADE_IN, 0.0, 1.0)
			if age >= FADE_IN:
				_start_build()
		Stage.HOLD:
			if age >= hold_time:
				_start_exit()
		Stage.FADE_OUT:
			_backdrop.modulate.a = 1.0 - clampf(age / FADE_OUT, 0.0, 1.0)
			if age >= FADE_OUT:
				_set_stage(Stage.DONE)
				finished.emit()
				queue_free()
	# the blow of the build: the logo jolts for a moment, in whole pixels
	var view: Vector2 = get_viewport().get_visible_rect().size
	var base: Vector2 = ((view - LOGO_SIZE) / 2.0).floor() + Vector2(0.0, -6.0)
	var s: float = _shake * exp(-(t - _shake_t0) * 9.0)
	_logo.position = base + Vector2(roundf(sin(t * 83.0) * s), roundf(cos(t * 67.0) * s))


func _input(event: InputEvent) -> void:
	if clock() < input_guard or stage == Stage.DONE or stage == Stage.FADE_OUT or stage == Stage.EXIT:
		return
	var pressed: bool = false
	if event is InputEventMouseButton:
		pressed = (event as InputEventMouseButton).pressed
	elif event is InputEventKey or event is InputEventJoypadButton:
		pressed = event.is_pressed() and not event.is_echo() and (event.is_action_pressed("interact") or event.is_action_pressed("action_primary") or event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"))
	if pressed:
		get_viewport().set_input_as_handled()
		skip()
