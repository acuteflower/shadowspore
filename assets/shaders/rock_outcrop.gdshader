shader_type canvas_item;
#include "res://assets/shaders/daylight.gdshaderinc"

// RockOutcrop Shader (LivingRock 1.0):
// - World-synced day/night & directional sun-side lighting (`day_grade` + `day_sun_side`)
// - Rain-wet slate & greywacke darkening + crisp top-left sky specular along rock bevels (`g_wet`)
// - Pickaxe impact glint (`hit_flash`)
// - Synchronized Bayer 4x4 pixel-dither occlusion (`iris_player`) on upper rock crests so tall
//   s3/s4 formations never hide Ellie while keeping their stone base 100% solid!

global uniform float g_night;

uniform vec2 frame_size = vec2(68.0, 56.0);
uniform float feet_y_px = 46.0;
uniform float highlight = 0.68;
uniform float sun_side = 0.85;
uniform float hit_flash = 0.0;
uniform vec4 iris_player = vec4(0.0, 0.0, 0.0, 0.0); // (world_x, world_y, radius_px, strength 0..1)

varying vec2 v_world_pos;
varying vec4 v_modulate;

float bayer4_rock(vec2 frag_xy) {
	ivec2 p = ivec2(mod(floor(frag_xy), 4.0));
	int idx = p.y * 4 + p.x;
	float m[16] = float[16](
		0.0, 8.0, 2.0, 10.0,
		12.0, 4.0, 14.0, 6.0,
		3.0, 11.0, 1.0, 9.0,
		15.0, 7.0, 13.0, 5.0
	);
	return (m[idx] + 0.5) / 16.0;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	v_modulate = COLOR;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a < 0.02) {
		discard;
	}

	vec2 tex_size = vec2(textureSize(TEXTURE, 0));
	float local_y = mod(UV.y * tex_size.y, max(frame_size.y, 1.0));
	float h_above_feet = max(0.0, feet_y_px - local_y);

	// Upper-crest Bayer 4x4 occlusion dither ONLY above base (`h_above_feet > 12 px`)
	if (iris_player.w > 0.01 && iris_player.z > 1.0 && h_above_feet > 12.0) {
		vec2 rel_p = (v_world_pos - iris_player.xy) * vec2(1.0, 0.86);
		float d_norm = length(rel_p) / iris_player.z;
		if (d_norm < 1.0) {
			float h_guard = smoothstep(12.0, 22.0, h_above_feet);
			float hole = (1.0 - smoothstep(0.25, 1.0, d_norm)) * iris_player.w * h_guard * 0.76;
			if (bayer4_rock(floor(v_world_pos)) < hole) {
				discard;
			}
		}
	}

	vec3 col = tex.rgb * v_modulate.rgb;
	col = day_grade(col, v_world_pos, highlight);

	if (sun_side > 0.0 && g_sun_side.y > 0.002) {
		float flip = dFdx(UV.x) < 0.0 ? -1.0 : 1.0;
		float col_idx = floor((UV.x * tex_size.x) / max(frame_size.x, 1.0));
		float lo = (col_idx * frame_size.x + 1.0) / tex_size.x;
		float hi = ((col_idx + 1.0) * frame_size.x - 1.0) / tex_size.x;
		vec2 step_x = vec2(TEXTURE_PIXEL_SIZE.x * flip, 0.0);
		float dl;
		float dr;
		SUN_EDGE(dl, UV, -step_x, lo, hi)
		SUN_EDGE(dr, UV, step_x, lo, hi)
		col = mix(col, day_sun_side(col, dl, dr, v_world_pos), sun_side);
	}

	// Rain-wet stone: richer cool-slate darkening + crisp sky reflection along bright upper bevels
	if (g_wet > 0.02) {
		float luma = dot(tex.rgb, vec3(0.30, 0.59, 0.11));
		col *= mix(vec3(1.0), vec3(0.70, 0.74, 0.85), g_wet * 0.62);
		if (luma > 0.56) {
			float bevel_sheen = smoothstep(0.56, 0.78, luma) * g_wet * (1.0 - 0.55 * g_night);
			col += vec3(0.10, 0.14, 0.19) * bevel_sheen;
		}
	}

	// Crisp mineral impact flash on pickaxe strike
	if (hit_flash > 0.01) {
		col = mix(col, vec3(0.95, 0.94, 0.88), hit_flash * 0.42);
	}

	COLOR = vec4(col, tex.a * v_modulate.a);
}
