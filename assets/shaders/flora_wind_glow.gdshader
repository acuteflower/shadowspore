shader_type canvas_item;
render_mode unshaded;
#include "res://assets/shaders/flora_wind.gdshaderinc"
void vertex() {
	modulate_in = COLOR;
}
void fragment() {
	COLOR = texture(TEXTURE, wind_uv(UV, vec2(textureSize(TEXTURE, 0)))) * modulate_in;
}
