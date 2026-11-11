class_name VeilGhost
extends Node2D
## Nebelschleier's IRRSPUR (tier III, docs/magie_konzept.md): the mist double a veiled player leaves where the veil fell. A copy of her
## picture at that moment, washed lilac, glitching and flickering, mist curling off it; it stands `seconds` long and then frays apart from
## the top. Shadow creatures that hunted her go to where they last saw her, which is exactly here. Cosmetic, every peer, in the y-sorted
## world so it sorts like a person.

const MIST: Color = Color("b9aaff")
const PALE: Color = Color("f2eeff")

var seconds: float = 3.0
var _sprite: Sprite2D
var _t: float = 0.0
var _seed: float = 0.0
var _motes: Array[Vector3] = []


static func leave(player: Player, seconds: float) -> void:
	var source: Sprite2D = player.get_node_or_null("Sprite2D") as Sprite2D
	var world: Node = player.get_tree().get_first_node_in_group("world")
	if source == null or world == null:
		return
	var ghost: VeilGhost = VeilGhost.new()
	ghost.seconds = seconds
	ghost.position = player.global_position
	var copy: Sprite2D = Sprite2D.new()
	copy.texture = source.texture
	copy.hframes = source.hframes
	copy.vframes = source.vframes
	copy.frame = source.frame
	copy.offset = source.offset
	copy.position = source.position
	copy.flip_h = source.flip_h
	copy.centered = source.centered
	if source.material is ShaderMaterial:
		var mat: ShaderMaterial = (source.material as ShaderMaterial).duplicate() as ShaderMaterial
		mat.set_shader_parameter("veil", 1.0)
		mat.set_shader_parameter("veil_keep", 0.62)
		mat.set_shader_parameter("flash", 0.0)
		copy.material = mat
	ghost._sprite = copy
	ghost.add_child(copy)
	world.add_child(ghost)


func _ready() -> void:
	_seed = randf() * 50.0
	var air: Node2D = Node2D.new()
	air.z_index = 3
	air.material = SpellZone.add_material()
	air.draw.connect(func() -> void: _draw_mist(air))
	add_child(air)
	set_meta("air", air)


func _process(delta: float) -> void:
	_t += delta
	var life: float = clampf((seconds - _t) / 0.8, 0.0, 1.0) * clampf(_t / 0.2, 0.0, 1.0)
	if _sprite != null and _sprite.material is ShaderMaterial:
		var mat: ShaderMaterial = _sprite.material as ShaderMaterial
		mat.set_shader_parameter("veil_seed", floorf(_t * 9.0) + _seed)
		mat.set_shader_parameter("veil_keep", 0.62 * life)
	if _sprite != null:
		_sprite.modulate = Color(0.85, 0.8, 1.15, (0.75 + 0.25 * sin(_t * 23.0)) * life) ## it flickers like a bad picture
		_sprite.position.x = roundf(sin(_t * 3.1) * 0.6) if randf() > 0.05 else float(randi() % 3 - 1) * 2.0
	if randf() < delta * 14.0 * life:
		_motes.append(Vector3(randf_range(-7.0, 7.0), randf_range(-38.0, -4.0), 0.8))
	for i: int in range(_motes.size() - 1, -1, -1):
		var m: Vector3 = _motes[i]
		m.z -= delta
		m.y -= delta * 12.0
		if m.z <= 0.0:
			_motes.remove_at(i)
		else:
			_motes[i] = m
	(get_meta("air") as Node2D).queue_redraw()
	if _t >= seconds:
		queue_free()


func _draw_mist(canvas: Node2D) -> void:
	for m: Vector3 in _motes:
		canvas.draw_rect(Rect2(Vector2(roundf(m.x), roundf(m.y)), Vector2.ONE), Color(MIST if m.z > 0.4 else PALE, m.z * 0.6))
