class_name SwordSlashFx
extends Node2D
## Hand-crafted animated pixel-art sword swing VFX (`assets/fx/sword_slash_*.png`).
## Renders on an unrotated, integer-snapped canvas via `sword_slash.gdshader` so every pixel
## locks cleanly to Shadowspore's 640x360 pixel grid while supporting arbitrary 360-degree aim,
## 3/4 top-down perspective foreshortening, overlapping combo swings, hit-stop freeze, and
## optional custom weapon `fx` palette remapping (while defaulting to normal Tempered Steel).

enum Kind {
	FOREHAND = 0,
	BACKHAND = 1,
	THRUST = 2,
	UPPERCUT = 3,
	WHIRLWIND = 4,
	HEAVY = 5,
}

const SHADER_PATH: String = "res://assets/shaders/sword_slash.gdshader"

const SHEET_META: Dictionary = {
	Kind.FOREHAND: {
		"path": "res://assets/fx/sword_slash_forehand.png",
		"frames": 10,
		"size": Vector2(96.0, 96.0),
		"pivot": Vector2(48.0, 48.0),
		"base_reach": 40.5,
		"sheet_sweep": -1.0,
		"squash_y": 0.78,
		"after_life": 0.25,
		"peak_frame": 2.0,
		"drift_px": 3.5,
	},
	Kind.BACKHAND: {
		"path": "res://assets/fx/sword_slash_backhand.png",
		"frames": 10,
		"size": Vector2(96.0, 96.0),
		"pivot": Vector2(48.0, 48.0),
		"base_reach": 41.5,
		"sheet_sweep": 1.0,
		"squash_y": 0.78,
		"after_life": 0.25,
		"peak_frame": 2.0,
		"drift_px": 4.0,
	},
	Kind.THRUST: {
		"path": "res://assets/fx/sword_slash_thrust.png",
		"frames": 10,
		"size": Vector2(96.0, 64.0),
		"pivot": Vector2(16.0, 32.0),
		"base_reach": 70.0,
		"sheet_sweep": 1.0,
		"squash_y": 0.86,
		"after_life": 0.27,
		"peak_frame": 2.0,
		"drift_px": 5.5,
	},
	Kind.UPPERCUT: {
		"path": "res://assets/fx/sword_slash_uppercut.png",
		"frames": 10,
		"size": Vector2(104.0, 104.0),
		"pivot": Vector2(52.0, 52.0),
		"base_reach": 44.5,
		"sheet_sweep": 1.0,
		"squash_y": 0.80,
		"after_life": 0.28,
		"peak_frame": 2.0,
		"drift_px": 4.5,
	},
	Kind.WHIRLWIND: {
		"path": "res://assets/fx/sword_slash_whirlwind.png",
		"frames": 12,
		"size": Vector2(112.0, 112.0),
		"pivot": Vector2(56.0, 56.0),
		"base_reach": 47.0,
		"sheet_sweep": -1.0,
		"squash_y": 0.72,
		"after_life": 0.31,
		"peak_frame": 3.0,
		"drift_px": 1.0,
	},
	Kind.HEAVY: {
		"path": "res://assets/fx/sword_slash_heavy.png",
		"frames": 12,
		"size": Vector2(112.0, 112.0),
		"pivot": Vector2(56.0, 56.0),
		"base_reach": 48.0,
		"sheet_sweep": -1.0,
		"squash_y": 0.84,
		"after_life": 0.34,
		"peak_frame": 3.0,
		"drift_px": 5.5,
	},
}

static var _shader: Shader = null
static var _textures: Dictionary = {}
static var _white_tex: ImageTexture = null

var _kind: int = Kind.FOREHAND
var _frames: int = 10
var _peak_frame: float = 2.0
var _active_dur: float = 0.09
var _total_dur: float = 0.34
var _age: float = 0.0
var _hit_flash: float = 0.0
var _aim: Vector2 = Vector2.RIGHT
var _drift_px: float = 4.0
var _anchor_local: Vector2 = Vector2(0.0, -22.0)
var _canvas_size: Vector2 = Vector2(136.0, 136.0)
var _mat: ShaderMaterial = null
var _finished: bool = false


static func _get_shader() -> Shader:
	if _shader == null:
		_shader = load(SHADER_PATH) as Shader
	return _shader


static func _get_sheet(kind: int) -> Texture2D:
	if not _textures.has(kind):
		var meta: Dictionary = SHEET_META.get(kind, SHEET_META[Kind.FOREHAND]) as Dictionary
		_textures[kind] = load(String(meta["path"])) as Texture2D
	return _textures[kind] as Texture2D


static func _get_white_tex() -> ImageTexture:
	if _white_tex == null:
		var img: Image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white_tex = ImageTexture.create_from_image(img)
	return _white_tex


static func create(
	kind: int,
	anchor_local: Vector2,
	aim_dir: Vector2,
	reach_px: float,
	screen_turn: float,
	active_duration: float,
	power_scale: float = 1.0,
	use_custom_palette: bool = false,
	edge_col: Color = Color("aac8ff"),
	core_col: Color = Color("f2f7ff"),
	depth_pass: int = 0
) -> SwordSlashFx:
	var fx: SwordSlashFx = SwordSlashFx.new()
	fx._setup(kind, anchor_local, aim_dir, reach_px, screen_turn, active_duration, power_scale, use_custom_palette, edge_col, core_col, depth_pass)
	return fx


func _setup(
	kind: int,
	anchor_local: Vector2,
	aim_dir: Vector2,
	reach_px: float,
	screen_turn: float,
	active_duration: float,
	power_scale: float,
	use_custom_palette: bool,
	edge_col: Color,
	core_col: Color,
	depth_pass: int = 0
) -> void:
	_kind = kind if SHEET_META.has(kind) else Kind.FOREHAND
	var meta: Dictionary = SHEET_META[_kind] as Dictionary
	var sheet: Texture2D = _get_sheet(_kind)
	var frame_sz: Vector2 = meta["size"] as Vector2
	var pivot: Vector2 = meta["pivot"] as Vector2
	_frames = int(meta["frames"])
	_peak_frame = float(meta["peak_frame"])
	_active_dur = clampf(active_duration, 0.055, 0.24)
	_total_dur = _active_dur + float(meta["after_life"])
	_aim = aim_dir.normalized() if aim_dir.length_squared() > 0.0001 else Vector2.RIGHT
	_drift_px = float(meta["drift_px"]) * clampf(power_scale, 0.85, 1.25)
	_anchor_local = anchor_local

	# Scale slash cleanly to match actual sword reach (Design Guide: "Was man sieht, trifft").
	var base_reach: float = float(meta["base_reach"])
	var scale_f: float = clampf((reach_px / maxf(base_reach, 1.0)) * power_scale, 0.78, 1.38)
	if _kind == Kind.THRUST:
		scale_f = clampf((reach_px * 1.18 / base_reach) * power_scale, 0.72, 1.28)

	# 3/4 top-down perspective basis:
	# Always faces exact 360-degree aim, matches the blade's real screen sweep direction (`screen_turn`),
	# and applies gentle world-Y perspective foreshortening without ever collapsing edge-on!
	var perp: Vector2 = Vector2(-_aim.y, _aim.x)
	var sheet_sweep: float = float(meta["sheet_sweep"])
	var flip_v: float = 1.0 if (_kind == Kind.THRUST or (screen_turn * sheet_sweep >= 0.0)) else -1.0

	var squash_y: float = float(meta["squash_y"])
	if _kind == Kind.HEAVY:
		# Overhead chop reads taller when aiming left/right, wider 3/4 cleave when aiming up/down
		squash_y = lerpf(0.78, 0.94, absf(_aim.x))

	var b0: Vector2 = _aim * scale_f
	var b1: Vector2 = perp * (flip_v * scale_f)
	if _kind != Kind.THRUST:
		b0.y *= squash_y
		b1.y *= squash_y
	else:
		# Thrust narrows slightly less vertically so the supersonic shock-ring reads boldly in all directions
		b0.y *= lerpf(0.88, 1.0, absf(_aim.x))
		b1.y *= lerpf(0.88, 1.0, absf(_aim.y))

	# Invert 2x2 matrix M = [b0, b1] for pixel-locked fragment lookup
	var det: float = b0.x * b1.y - b0.y * b1.x
	if absf(det) < 0.001:
		det = 0.001 if det >= 0.0 else -0.001
	var inv_x: Vector2 = Vector2(b1.y, -b1.x) / det
	var inv_y: Vector2 = Vector2(-b0.y, b0.x) / det

	# Size the unrotated pixel canvas generously to hold the full transformed frame without clipping
	var max_extent: float = maxf(frame_sz.x, frame_sz.y) * scale_f + 24.0
	if _kind == Kind.THRUST:
		max_extent = (frame_sz.x - pivot.x) * scale_f * 2.0 + 24.0
	var dim: float = float(ceili(max_extent / 2.0) * 2)
	_canvas_size = Vector2(dim, dim)

	# Forward pivot shift for thrust so the spear shoots cleanly out from Ellie's shoulder/hand
	var pivot_shift: Vector2 = Vector2.ZERO
	if _kind == Kind.THRUST:
		pivot_shift = _aim * 4.0
	elif _kind == Kind.HEAVY:
		pivot_shift = _aim * 5.0 + Vector2(0.0, 2.0)
	elif _kind != Kind.WHIRLWIND:
		pivot_shift = _aim * 3.0

	_mat = ShaderMaterial.new()
	_mat.shader = _get_shader()
	_mat.set_shader_parameter(&"sheet_tex", sheet)
	_mat.set_shader_parameter(&"canvas_px", _canvas_size)
	_mat.set_shader_parameter(&"frame_size", frame_sz)
	_mat.set_shader_parameter(&"sheet_size", Vector2(frame_sz.x * float(_frames), frame_sz.y))
	_mat.set_shader_parameter(&"frame_pivot", pivot)
	_mat.set_shader_parameter(&"frame_index", 0.0)
	_mat.set_shader_parameter(&"inv_x", inv_x)
	_mat.set_shader_parameter(&"inv_y", inv_y)
	_mat.set_shader_parameter(&"pivot_shift", pivot_shift)
	_mat.set_shader_parameter(&"depth_pass", depth_pass)
	_mat.set_shader_parameter(&"hit_flash", 0.0)
	_mat.set_shader_parameter(&"opacity", 1.0)
	_mat.set_shader_parameter(&"use_custom_palette", use_custom_palette)
	if use_custom_palette:
		var ramp: Array[Color] = _build_custom_ramp(edge_col, core_col)
		_mat.set_shader_parameter(&"col_dark", ramp[0])
		_mat.set_shader_parameter(&"col_shadow", ramp[1])
		_mat.set_shader_parameter(&"col_mid", ramp[2])
		_mat.set_shader_parameter(&"col_core", ramp[3])
		_mat.set_shader_parameter(&"col_edge", ramp[4])

	material = _mat
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	position = _anchor_local.round()
	# Keep z_index = 0 so parent Y-sort anchors (`SlashBack` behind Ellie, `SlashFront` in front)
	# control exact occlusion with Ellie's body, silver hair, and world entities.
	z_index = 0
	queue_redraw()


## Derives a crisp 5-tone palette ramp from a unique weapon's `fx.trail_edge` and `fx.trail_core`
## (`sword_rift` violet, `blade_starlight` aqua/gold, or future themed swords).
static func _build_custom_ramp(edge_col: Color, core_col: Color) -> Array[Color]:
	var deep_indigo: Color = Color(0.09, 0.06, 0.22, 0.94)
	var c_dark: Color = edge_col.darkened(0.62).lerp(deep_indigo, 0.35)
	c_dark.a = 0.94
	var c_shadow: Color = edge_col.darkened(0.28)
	c_shadow.a = 0.98
	var c_mid: Color = edge_col.lerp(core_col, 0.22)
	c_mid.a = 1.0
	var c_core: Color = edge_col.lerp(core_col, 0.78)
	c_core.a = 1.0
	var c_edge: Color = core_col.lightened(0.45).lerp(Color.WHITE, 0.55)
	c_edge.a = 1.0
	return [c_dark, c_shadow, c_mid, c_core, c_edge]


func trigger_hit_flash() -> void:
	_hit_flash = 1.0
	if _mat != null:
		_mat.set_shader_parameter(&"hit_flash", _hit_flash)


func is_done() -> bool:
	return _finished


## Steps animation time deterministically (called by AttackComponent so hit-stop & previews stay exact!).
func step(delta: float) -> bool:
	if _finished:
		return false
	_age += maxf(delta, 0.0)
	if _age >= _total_dur:
		_finished = true
		visible = false
		return false
	if _hit_flash > 0.0:
		_hit_flash = maxf(_hit_flash - delta * 9.5, 0.0)
	# Non-linear choreography curve:
	# Whip swiftly through frames 0..peak_frame during the active blade cut, then pace
	# cleanly through kinetic breakup & lingering star glints!
	var f_idx: int = 0
	if _age < _active_dur:
		var u_act: float = clampf(_age / maxf(_active_dur, 0.001), 0.0, 1.0)
		f_idx = clampi(int(floor(u_act * (_peak_frame + 0.99))), 0, _frames - 1)
	else:
		var u_post: float = clampf((_age - _active_dur) / maxf(_total_dur - _active_dur, 0.001), 0.0, 1.0)
		var rem: float = float(_frames - 1) - _peak_frame
		f_idx = clampi(int(floor(_peak_frame + 1.0 + u_post * rem)), 0, _frames - 1)

	# Subtle forward momentum drift along aim as the slash shears through air
	var drift_u: float = clampf(_age / maxf(_total_dur, 0.001), 0.0, 1.0)
	var drift_ease: float = 1.0 - pow(1.0 - drift_u, 2.0)
	position = (_anchor_local + _aim * (_drift_px * drift_ease)).round()

	if _mat != null:
		_mat.set_shader_parameter(&"frame_index", float(f_idx))
		_mat.set_shader_parameter(&"hit_flash", _hit_flash)
	return true


func _draw() -> void:
	draw_texture_rect(_get_white_tex(), Rect2(-_canvas_size * 0.5, _canvas_size), false)
