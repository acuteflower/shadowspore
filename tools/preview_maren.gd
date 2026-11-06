extends Node2D
## Godot --path . res://tools/preview_maren.tscn: real Settler sprite selection, eight views.
const NAMES: PackedStringArray = ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
const CLIPS: PackedStringArray = ["idle", "walk", "run", "work"]
var figures: Array[Settler] = []
var elapsed: float = 0.0
var title: Label

func _ready() -> void:
	var bg: ColorRect = ColorRect.new()
	bg.size = Vector2(640, 360)
	bg.color = Color("262232")
	add_child(bg)
	var rig: Dictionary = DataRegistry.table("maren_rig")
	for sector: int in 8:
		var figure: Settler = Settler.new()
		add_child(figure)
		figure.set_process(false)
		figure._rig = rig
		figure._sector = sector
		figure._sprite = figure._make_sprite("res://assets/characters/maren.png")
		figure.position = Vector2(80 + 160 * (sector % 4), 145 + 165 * (sector / 4))
		figure.scale = Vector2(2.0, 2.0)
		figures.append(figure)
		var label: Label = Label.new()
		label.text = NAMES[sector]
		label.position = Vector2(16 + 160 * (sector % 4), 28 + 165 * (sector / 4))
		add_child(label)
	title = Label.new()
	title.position = Vector2(230, 3)
	add_child(title)

func _process(delta: float) -> void:
	elapsed += delta
	var clip: String = CLIPS[int(elapsed / 4.0) % CLIPS.size()]
	title.text = "MAREN  -  " + clip.to_upper()
	for figure: Settler in figures:
		figure._clip = clip
		figure._clip_time = elapsed
		figure._show()
