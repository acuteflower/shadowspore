shader_type canvas_item;
render_mode unshaded, blend_add;
#include "res://assets/shaders/daylight.gdshaderinc"
uniform vec4 shafts[4]; // origin, length, width. Fixed world positions at crown gaps.
uniform int shaft_count = 0;
uniform float air = 1.0;
uniform float noon_alpha = 0.035;
uniform float gold_alpha = 0.095;
varying vec2 world_position;
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy; }
void fragment() {
	vec2 p = floor(world_position);
	float glow = 0.0;
	for (int i = 0; i < 4; i++) {
		if (i >= shaft_count) { break; }
		vec2 delta = p - shafts[i].xy;
		float along = dot(delta, vec2(0.6, 0.8));
		float across = abs(dot(delta, vec2(0.8, -0.6)));
		float width = shafts[i].w * (0.45 + 0.55 * clamp(along / shafts[i].z, 0.0, 1.0));
		float edge = 1.0 - smoothstep(width * 0.4, width, across);
		float ends = smoothstep(0.0, 14.0, along) * (1.0 - smoothstep(shafts[i].z * 0.55, shafts[i].z, along));
		float broken = 0.65 + 0.35 * sin(along * 0.12 + g_day_clock * 0.4);
		glow = max(glow, edge * ends * broken);
	}
	float light = day_cloud(p) * (1.0 - day_cover(p) * 0.55);
	COLOR = vec4(mix(vec3(1.0, 0.96, 0.72), vec3(1.0, 0.73, 0.36), g_day_gold), glow * light * g_day_strength * (noon_alpha + gold_alpha * g_day_gold) * air);
}
