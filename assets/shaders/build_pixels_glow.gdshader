shader_type canvas_item;
render_mode unshaded;
// The unlit pass over a site (plain alpha, so the dots read on bright grass too): falling pixels shine teal-white until they land, the unfinished rest shows as a dotted blueprint (see build_pixels.gdshaderinc).
#include "res://assets/shaders/build_pixels.gdshaderinc"
uniform float flash = 0.0; // the foundation stone: for a moment the whole unbuilt shape lights up as a wire frame

void fragment() {
	float flight;
	float ghost;
	vec4 c = bp_pixel(TEXTURE, UV, flight, ghost);
	vec3 teal = vec3(0.47, 0.96, 0.90);
	if (flight > 0.0) {
		COLOR = vec4(mix(teal, vec3(1.0), flight * 0.6), 0.45 + 0.55 * flight);
	} else if (ghost > 0.0) {
		COLOR = vec4(teal * 0.85, ghost * 0.6);
	} else {
		COLOR = vec4(0.0);
	}
	if (flash > 0.0 && c.a <= 0.0 && texture(TEXTURE, UV).a > 0.5) {
		COLOR = vec4(mix(teal, vec3(1.0), flash * 0.5), max(COLOR.a, flash * 0.85));
	}
}
