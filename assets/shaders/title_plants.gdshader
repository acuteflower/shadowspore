shader_type canvas_item;
render_mode unshaded;
// The plants of the title logo (tufts, leaves, shelf-plants and the big spore flower): they sway in whole art pixels, rooted pixels stay.
#include "res://assets/shaders/title_sway.gdshaderinc"

void fragment() {
	ivec2 size = textureSize(TEXTURE, 0);
	ivec2 p = ivec2(floor(UV * vec2(size)));
	vec4 result = vec4(0.0);
	for (int o = -MAX_SHIFT; o <= MAX_SHIFT; o++) {
		ivec2 src = ivec2(p.x - o, p.y);
		if (src.x < 0 || src.x >= size.x) {
			continue;
		}
		if (o != 0 && sway_weight(src) <= 0.0) {
			continue;
		}
		if (sway_offset(src) != o) {
			continue;
		}
		if (plant_cut(src) > grow) {
			continue;
		}
		vec4 c = texelFetch(TEXTURE, src, 0);
		if (c.a > 0.0) {
			result = c;
		}
	}
	// rooted pixels (the collar and the roots at the foot) always lie on top
	vec4 own = texelFetch(TEXTURE, p, 0);
	if (own.a > 0.0 && sway_weight(p) <= 0.0 && plant_cut(p) <= grow) {
		result = own;
	}
	COLOR = result;
}
