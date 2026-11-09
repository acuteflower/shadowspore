shader_type canvas_item;
#include "res://assets/shaders/daylight.gdshaderinc"
varying vec2 day_position;
// The lit pass: the pixels that are built, with the world's light (see build_pixels.gdshaderinc).
#include "res://assets/shaders/build_pixels.gdshaderinc"

varying vec4 tint;

void vertex() {
	day_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	tint = COLOR;
}

void fragment() {
	float flight;
	float ghost;
	COLOR = bp_pixel(TEXTURE, UV, flight, ghost) * tint;
	COLOR.rgb = day_grade(COLOR.rgb, day_position, 0.5);
}
