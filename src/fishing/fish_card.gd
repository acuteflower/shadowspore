class_name FishCard
extends Node2D
## The catch card: a leaf of bark paper that unfurls above her head (owner only, drawn unlit so night does not tint it).

const SIDE: Texture2D = preload("res://assets/fishing/fish_side.png")
const ORDER: Array[String] = ["silverling", "copper_loach", "moon_trout", "gold_carp", "glimmer_loach", "veil_eel", "abyss_pike"]
const RARITY: Dictionary = {"common": "b8b8c8", "uncommon": "6fd08c", "rare": "5aa8ff", "epic": "b47aff", "legendary": "ffb347"}
const SIZE: Vector2 = Vector2(128, 56)
const OPEN: float = 0.3
const HOLD: float = 3.4
const CLOSE: float = 0.5

var _species: String = ""
var _length: int = 0
var _record: bool = false
var _prime: bool = false
var _age: float = 99.0


func bind(component: FishingComponent) -> void:
	component.caught.connect(show_catch)
	z_index = 40
	position = Vector2(0, -78)
	material = Unlit.material()
	set_process(false)


func show_catch(species: String, length: int, is_record: bool, prime: bool = false) -> void:
	_species = species
	_length = length
	_record = is_record
	_prime = prime
	_age = 0.0
	set_process(true)


func is_showing() -> bool:
	return _age < OPEN + HOLD + CLOSE


func _process(delta: float) -> void:
	_age += delta
	queue_redraw()
	if not is_showing():
		set_process(false)


func _draw() -> void:
	if not is_showing() or _species == "":
		return
	var spec: Dictionary = FishingRules.species_table()[_species] as Dictionary
	var open: float = clampf(_age / OPEN, 0.0, 1.0)
	var fade: float = clampf((OPEN + HOLD + CLOSE - _age) / CLOSE, 0.0, 1.0)
	var rise: float = (1.0 - open) * 6.0
	var width: float = SIZE.x * (0.25 + 0.75 * open)
	var rect: Rect2 = Rect2(Vector2(-width * 0.5, -SIZE.y * 0.5 + rise).round(), Vector2(roundf(width), SIZE.y))
	VineStyle.paper(self, rect, fade * open, 0.0, 11)
	if open < 1.0:
		return
	var rarity: Color = Color(String(RARITY.get(String(spec["rarity"]), "b8b8c8")))
	var edge: float = 0.5 + 0.5 * sin(_age * 4.0)
	draw_rect(Rect2(rect.position + Vector2(3, SIZE.y - 5), Vector2(SIZE.x - 6, 1)), Color(rarity, 0.5 * fade * (0.6 + 0.4 * edge)))
	draw_texture_rect_region(SIDE, Rect2(rect.position + Vector2(6, 8), Vector2(48, 24)), Rect2(0, ORDER.find(_species) * 24, 48, 24), Color(1, 1, 1, fade))
	var x: int = int(rect.position.x) + 60
	PixelText.draw(self, String(spec["name"]), Vector2i(x, int(rect.position.y) + 8), Color(rarity, fade), Color(0.07, 0.05, 0.13, fade))
	PixelText.draw(self, "%d CM" % _length, Vector2i(x, int(rect.position.y) + 18), Color(0.91, 0.89, 0.96, fade))
	var row: int = 28
	if _prime:
		PixelText.draw(self, "PRACHTEXEMPLAR X2", Vector2i(x - 4, int(rect.position.y) + row), Color("fff0b0", fade), Color(0.07, 0.05, 0.13, fade))
		row += 10
	if _record:
		PixelText.draw(self, "NEUER REKORD", Vector2i(x, int(rect.position.y) + row), Color(0.9, 0.77, 0.41, fade))
