shader_type canvas_item;
#include "res://assets/shaders/daylight.gdshaderinc"
render_mode blend_mix;

// Lit pixel-art shader for embedded ground props (antique stone slabs, stepping stones,
// weathered moon-ring rondell, woodland roots, leaf litter, mossy stones & mushrooms).
// Syncs macro dappled sunlight, rain wetness sheen & balanced night lighting with LivingGrass & GroundSurfaces.

global uniform float g_night;
global uniform float g_dew;

varying vec2 v_world_px;

float gp_hash(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p)) + ivec2(65536));
	uint h = q.x * 1597334677u ^ q.y * 3812015801u;
	h = (h ^ (h >> 16u)) * 2246822519u;
	h ^= h >> 16u;
	return float(h >> 8u) / 16777216.0;
}

float gp_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(gp_hash(i), gp_hash(i + vec2(1.0, 0.0)), f.x),
		mix(gp_hash(i + vec2(0.0, 1.0)), gp_hash(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

void vertex() {
	v_world_px = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV) * COLOR;
	if (tex.a < 0.02) {
		discard;
	}
	vec2 px = floor(v_world_px);
	vec3 col = tex.rgb;

	// Macro woodland sun/shade dappled modulation synced with GroundSurfaces & LivingGrass
	float macro = gp_vnoise(px / 110.0 + vec2(3.7, 1.9)) * 0.65 + gp_vnoise(px / 52.0 + vec2(11.0, 5.0)) * 0.35;
	float day_w = 1.0 - g_night * 0.8;
	if (macro < 0.40) {
		col *= mix(vec3(1.0), vec3(0.78, 0.84, 0.95), smoothstep(0.40, 0.22, macro) * 0.42 * day_w);
	} else if (macro > 0.60) {
		col *= mix(vec3(1.0), mix(vec3(1.06, 1.04, 0.96), vec3(1.16, 1.07, 0.88), g_day_gold), smoothstep(0.60, 0.78, macro) * 0.35 * day_w);
	}

	// Warm golden-hour glint on antique bronze / gold filigree inlays!
	bool is_gold_inlay = (col.r > col.b * 1.32 && col.g > col.b * 1.14 && col.r > 0.42);
	if (is_gold_inlay && day_w > 0.1) {
		col = mix(col, vec3(1.0, 0.90, 0.58), (0.14 + 0.32 * g_day_gold) * day_w);
	}

	// Rain & morning-dew pooling: recessed carved grooves catch a crisp sky-mirror water glint,
	// while planar stone faces darken with cool wet sheen!
	float moisture = max(g_wet, g_dew * 0.65);
	if (moisture > 0.01) {
		float luma = dot(col, vec3(0.30, 0.59, 0.11));
		if (!is_gold_inlay && luma < 0.29 && moisture > 0.24) {
			float rip = 0.5 + 0.5 * sin(px.x * 0.45 + px.y * 0.31);
			col = mix(col, vec3(0.46, 0.68, 0.78) + vec3(0.10) * rip, clamp((moisture - 0.24) * 0.62, 0.0, 0.48));
		} else {
			col *= mix(vec3(1.0), vec3(0.76, 0.82, 0.92), g_wet * 0.68);
			float spec = smoothstep(0.52, 0.84, luma);
			col = mix(col, max(col, vec3(0.74, 0.86, 0.96)), spec * g_wet * 0.28 * (1.0 - 0.55 * g_night));
		}
	}

	// Balanced nocturnal stone & humus tone
	if (g_night > 0.01) {
		float luma = dot(col, vec3(0.30, 0.59, 0.11));
		float bright_tame = smoothstep(0.48, 0.90, luma);
		col *= mix(vec3(1.0), vec3(0.74, 0.82, 0.95), g_night * (0.20 + 0.28 * bright_tame));
	}

	col = day_grade(col, px, 0.45);
	COLOR = vec4(col, tex.a);
}
