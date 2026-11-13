shader_type canvas_item;
render_mode unshaded;
// The build menu's big card: the chosen piece puts itself together in a loop with the real build look (build_pixels.gdshaderinc), unlit for the UI:
// built pixels as they are, falling ones teal-white, the rest as blueprint dots.
#include "res://assets/shaders/build_pixels.gdshaderinc"

void fragment() {
	float flight;
	float ghost;
	vec4 c = bp_pixel(TEXTURE, UV, flight, ghost);
	vec3 teal = vec3(0.47, 0.96, 0.90);
	if (flight > 0.0) {
		COLOR = vec4(mix(c.rgb, mix(teal, vec3(1.0), flight * 0.6), 0.7), 1.0);
	} else if (c.a > 0.0) {
		COLOR = c;
	} else if (ghost > 0.0) {
		COLOR = vec4(teal * 0.85, ghost * 0.55);
	} else {
		COLOR = vec4(0.0);
	}
}
