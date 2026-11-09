shader_type canvas_item;
#include "res://assets/shaders/daylight.gdshaderinc"
varying vec2 daylight_position;
#include "res://assets/shaders/flora_wind.gdshaderinc"
void vertex() {
	daylight_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	modulate_in = COLOR;
}
void fragment() {
	COLOR = texture(TEXTURE, wind_uv(UV, vec2(textureSize(TEXTURE, 0)))) * modulate_in;
	COLOR.rgb = day_grade(COLOR.rgb, daylight_position, 0.7);
}
