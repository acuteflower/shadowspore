shader_type canvas_item;
#include "res://assets/shaders/daylight.gdshaderinc"
render_mode blend_mix;

// Pressed-turf 2-zone trail underlay directly beneath LivingGrass v4 (z_index = -10):
// - Toroidal camera-centered ring-buffer sampling (repeat_enable + border fade = infinite Open World support!)
// - Pixel-dithered cool damp moss core + directional laid-down blade streaks + subtle sunlit outer parting rim
// - Set `debug_overlay > 0.0` in GrassLab to visualize the raw crush & bend vector field.

uniform vec2 field_origin = vec2(-256.0, -256.0);
uniform float field_size = 512.0;
uniform sampler2D deform_tex : filter_linear, repeat_enable;
uniform float debug_overlay : hint_range(0.0, 1.0) = 0.0;

varying vec2 v_world_px;

float trail_hash(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p)) + ivec2(65536));
	uint h = q.x * 1597334677u ^ q.y * 3812015801u;
	h = (h ^ (h >> 16u)) * 2246822519u;
	h ^= h >> 16u;
	return float(h >> 8u) / 16777216.0;
}

void vertex() {
	v_world_px = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 px = floor(v_world_px);
	vec2 rel = px - field_origin;
	float edge = min(min(rel.x, field_size - rel.x), min(rel.y, field_size - rel.y));
	if (edge <= 2.0) {
		discard;
	}
	float win_fade = smoothstep(2.0, 14.0, edge);
	vec4 def = texture(deform_tex, fract(px / field_size));
	float crush = def.b * win_fade;
	vec2 bend = (def.rg - vec2(0.5)) * 2.0 * win_fade;

	if (debug_overlay > 0.01) {
		if (crush < 0.03 && length(bend) < 0.05) {
			discard;
		}
		vec3 dbg = vec3(0.5 + bend.x * 0.5, 0.5 + bend.y * 0.5, crush);
		COLOR = vec4(dbg, max(crush * 0.72, length(bend) * 0.45) * debug_overlay);
	} else {
		// Organic pixel-dithered pressed-turf core + directional laid-flat blade streaks
		float grain = trail_hash(px);
		float mask = smoothstep(0.11, 0.74, crush);
		if (mask <= 0.01 || grain > mask * 0.94 + 0.10) {
			discard;
		}
		vec2 dir = length(bend) > 0.08 ? normalize(bend) : vec2(1.0, 0.0);
		float across = dot(px, vec2(-dir.y, dir.x));
		float along = dot(px, dir);
		// Fine directional crushed-blade striations aligned with the parting/stride vector
		float streak = sin(across * 1.65 + sin(along * 0.24) * 1.15 + grain * 2.1);
		float blade_rib = step(0.46, streak) * step(0.32, fract(along * 0.18 + grain));
		vec3 dark_moss = vec3(0.09, 0.20, 0.19);
		vec3 damp_soil = vec3(0.15, 0.25, 0.20);
		vec3 bent_sheen = vec3(0.28, 0.50, 0.34);
		vec3 col = mix(dark_moss, damp_soil, smoothstep(0.54, 0.92, crush) * 0.46);
		col = mix(col, bent_sheen, (step(0.40, streak) * 0.24 + blade_rib * 0.18) * (0.75 + 0.25 * (1.0 - mask)));
		col = day_grade(col, px, 0.45);
		float alpha = mask * (0.39 + 0.16 * step(0.50, grain));
		COLOR = vec4(col, alpha);
	}
}
