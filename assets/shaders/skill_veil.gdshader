shader_type canvas_item;
render_mode unshaded;

uniform vec2 view_size = vec2(640.0, 360.0);
uniform vec2 center = vec2(0.0);
uniform float zoom = 1.0;
uniform float time = 0.0;
uniform float night = 0.0;
uniform float opening = 1.0;
uniform int light_count = 0;
uniform vec4 lights[32]; // xy graph position, z animated clearing radius

#include "res://assets/shaders/map_veil.gdshaderinc"

void fragment() {
	vec2 P = floor(UV * view_size) + 0.5;
	vec2 p = P - 0.5;
	vec2 w = center + (P - view_size * 0.5) / zoom;
	float m = 0.0;
	for (int i = 0; i < 32; i++) {
		if (i >= light_count) break;
		float distance_to_clear = length(w - lights[i].xy) - lights[i].z;
		m = max(m, 1.0 - smoothstep(-14.0, 14.0, distance_to_clear));
	}
	float e = veil_discovery_edge(w, m);
	vec3 col;
	if (e > 0.0) {
		// Explored space stays quiet: no stars or dotted grid beneath the skills.
		col = mix(VOID0, VOID1, 0.22 + fbm(w * 0.018 + vec2(time * 0.005, 0.0)) * 0.38);
		col *= mix(vec3(1.0), vec3(0.66, 0.66, 0.96), night * 0.8);
		if (e < 0.06) {
			float t = e / 0.06;
			if (bayer(p) > t * 1.1) col = mix(col, VOID1, 0.75);
			if (t < 0.45 && hash21(p + floor(time * 3.0)) > 0.78) col = VIO7;
		}
	} else {
		col = fog_smoke(w, p, smoothstep(0.0, -0.45, e));
		if (e > -0.06 && hash21(p * 1.7 + floor(time * 2.0)) > 0.82) col = mix(col, VIO6, 0.7);
	}
	col = veil_frame(col, P, view_size);
	COLOR = veil_opening(col, P, view_size, view_size * vec2(0.54, 0.64), opening);
}
