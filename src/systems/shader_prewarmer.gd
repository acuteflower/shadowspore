extends CanvasLayer
## Renders 2x2 textured quads and a small PointLight2D behind the opaque loading veil so GPU driver
## shader/PSO compilation completes before the world is revealed. Skipped in `--headless` by the launcher.

const SHADERS: Array[String] = [
	"res://assets/shaders/ground_tone.gdshader",
	"res://assets/shaders/glow_layer.gdshader",
	"res://assets/shaders/relief.gdshader",
	"res://assets/shaders/flora_wind.gdshader",
	"res://assets/shaders/flora_wind_glow.gdshader",
	"res://assets/shaders/clover_clumps.gdshader",
	"res://assets/shaders/clover_clumps_glow.gdshader",
	"res://assets/shaders/meadow_details.gdshader",
	"res://assets/shaders/river_water.gdshader",
	"res://assets/shaders/river_glow.gdshader",
	"res://assets/shaders/river_flora.gdshader",
	"res://assets/shaders/day_sprite.gdshader",
	"res://assets/shaders/day_shafts.gdshader",
	"res://assets/shaders/sun_glow.gdshader",
	"res://assets/shaders/sun_shadow.gdshader",
	"res://assets/shaders/shadow_silhouette_flora.gdshader",
	"res://assets/shaders/shadow_silhouette_rows.gdshader",
	"res://assets/shaders/night_moon.gdshader",
	"res://assets/shaders/night_fog.gdshader",
	"res://assets/shaders/weather_rain.gdshader",
	"res://assets/shaders/weather_flash.gdshader",
	"res://assets/shaders/heat_haze.gdshader",
	"res://assets/shaders/damage_vignette.gdshader",
	"res://assets/shaders/sneak_vignette.gdshader",
	"res://assets/shaders/mood_grade.gdshader",
	"res://assets/shaders/hit_flash.gdshader",
	"res://assets/shaders/hud_reveal.gdshader",
	"res://assets/shaders/vine_breathe.gdshader",
	"res://assets/shaders/vine_breathe_glow.gdshader",
	"res://assets/shaders/wound_border.gdshader",
	"res://assets/shaders/waystone_beam.gdshader",
	"res://assets/shaders/world_map.gdshader",
	"res://assets/shaders/blueprint.gdshader",
	"res://assets/shaders/build_pixels.gdshader",
	"res://assets/shaders/build_pixels_glow.gdshader",
	"res://assets/shaders/void_edge.gdshader",
	"res://assets/shaders/void_rift.gdshader",
	"res://assets/shaders/shadow_emission.gdshader",
	"res://assets/shaders/shadow_patch.gdshader",
	"res://assets/shaders/shadow_silhouette.gdshader",
]


func _ready() -> void:
	layer = 1
	process_mode = Node.PROCESS_MODE_ALWAYS
	var img: Image = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	var lit_sprite: Sprite2D = Sprite2D.new()
	lit_sprite.texture = tex
	lit_sprite.position = Vector2(16.0, 16.0)
	add_child(lit_sprite)
	var light: PointLight2D = PointLight2D.new()
	light.position = Vector2(16.0, 16.0)
	LightTexture.apply(light, 24)
	add_child(light)
	for path: String in SHADERS:
		if not ResourceLoader.exists(path):
			continue
		var shader: Shader = load(path) as Shader
		if shader == null:
			continue
		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture = tex
		sprite.position = Vector2(16.0, 16.0)
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = shader
		sprite.material = mat
		add_child(sprite)
