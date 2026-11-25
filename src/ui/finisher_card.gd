class_name FinisherCard
extends Control
## Finisher V2 (docs/finisher_v2_konzept.md): the name of a finisher, shown once per save the first time she performs it
## (flag `name_card_flag` in data/finishers.json settings). The word condenses out of smoke in the small shadow face (`VoidTitle`), stutters
## with a glitch on impact, holds for a breath and crumbles upwards. Local to her own machine, CanvasLayer 40 (over the HUD), real time.

const REVEAL: float = 0.42
const HOLD_UNTIL: float = 1.05
const DISSOLVE: float = 0.45

var _text: String = ""
var _title: VoidTitle = null
var _layer: CanvasLayer = null
var _t: float = 0.0


static func play(host: Node, text: String) -> FinisherCard:
	var card: FinisherCard = FinisherCard.new()
	card._text = text
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "FinisherCardLayer"
	layer.layer = 40
	card._layer = layer
	layer.add_child(card)
	host.get_tree().root.add_child(layer)
	return card


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title = VoidTitle.new()
	_title.setup(_text, "small", 5.0)
	_title.set_ink(0.6)
	add_child(_title)
	_fit()
	_title.set_look(0.0, 0.0, 1.0, 0.0, 0.0)


func _fit() -> void:
	var view: Vector2 = get_viewport().get_visible_rect().size
	if size != view:
		size = view
	var cap: float = float(((VoidTitle.metrics()["faces"] as Dictionary)["small"] as Dictionary)["cap"])
	_title.place(Vector2(roundf(size.x * 0.5 - _title.ink_size.x * 0.5), roundf(size.y * 0.26 - cap * 0.5)))


func _process(delta: float) -> void:
	_t += delta / maxf(Engine.time_scale, 0.05)
	_fit()
	var reveal: float = clampf(_t / REVEAL, 0.0, 1.0) * 1.4
	var dissolve: float = clampf((_t - HOLD_UNTIL) / DISSOLVE, 0.0, 1.0)
	var impact: float = clampf(1.0 - _t / 0.3, 0.0, 1.0)
	var glitch: float = maxf(impact, 0.5 if fmod(_t * 6.1, 1.0) < 0.08 else 0.0)
	_title.set_look(reveal, dissolve, glitch, smoothstep(0.0, 0.6, _t), 0.3 + 0.5 * smoothstep(0.2, 1.2, _t))
	if dissolve >= 1.0:
		_layer.queue_free()
