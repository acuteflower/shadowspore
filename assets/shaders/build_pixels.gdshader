shader_type canvas_item;
// The lit pass: the pixels that are built, with the world's light (see build_pixels.gdshaderinc).
#include "res://assets/shaders/build_pixels.gdshaderinc"

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	float flight;
	float ghost;
	COLOR = bp_pixel(TEXTURE, UV, flight, ghost) * tint;
}
