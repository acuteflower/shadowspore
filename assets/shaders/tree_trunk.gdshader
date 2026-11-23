shader_type canvas_item;
#include "res://assets/shaders/daylight.gdshaderinc"

global uniform float g_night;

uniform vec2 frame_size = vec2(196.0, 200.0);
uniform float highlight = 0.72;
uniform float sun_side = 0.90;
uniform float stemflow = 0.0;   // 0..1 rainwater streaming down dark bark furrows
uniform float corruption = 0.0; // 0..1 void ash crust
uniform float heal_flash = 0.0; // 0..1 golden consecration pulse
uniform vec4 iris_player = vec4(0.0, 0.0, 0.0, 0.0); // (world_x, world_y, radius_px, strength 0..1)

varying vec2 v_world_pos;
varying vec4 v_modulate;

float bayer4_trunk(vec2 frag_xy) {
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

	// Synchronized Bayer 4x4 Pixel-Dither Iris on upper trunk/boughs so inner wood never pops out over dithered leaves!
	if (iris_player.w > 0.01 && iris_player.z > 1.0) {
		vec2 rel_p = (v_world_pos - iris_player.xy) * vec2(1.0, 0.82);
		float d_norm = length(rel_p) / iris_player.z;
		if (d_norm < 1.0) {
			float hole = (1.0 - smoothstep(0.28, 1.0, d_norm)) * iris_player.w * 0.78;
			if (bayer4_trunk(floor(v_world_pos)) < hole) {
				discard;
			}
		}
	}

	vec2 tex_size = vec2(textureSize(TEXTURE, 0));
	vec3 col = tex.rgb * v_modulate.rgb;

	if (corruption > 0.01) {
		float luma = dot(col, vec3(0.30, 0.59, 0.11));
		vec3 ash = mix(vec3(0.11, 0.09, 0.17), vec3(0.46, 0.42, 0.54), clamp(luma * 1.2, 0.0, 1.0));
		col = mix(col, ash, corruption * 0.80);
	}

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

	// Hydrological stemflow: dark wet bark channels & cool sky sheen along vertical rhytidome grooves
	float wet_amt = max(g_wet, stemflow);
	if (wet_amt > 0.02) {
		vec2 px = floor(UV * tex_size);
		float groove = fract(sin(px.x * 19.7 + floor(px.y * 0.25) * 3.1) * 43758.5);
		col *= mix(vec3(1.0), vec3(0.72, 0.76, 0.86), wet_amt * (0.45 + 0.35 * groove));
		if (stemflow > 0.25 && groove > 0.82) {
			float trickle = step(0.86, fract(px.y * 0.09 - g_day_clock * 1.8 + groove * 7.0));
			col += vec3(0.08, 0.12, 0.16) * trickle * stemflow * (1.0 - 0.5 * g_night);
		}
	}

	if (heal_flash > 0.01) {
		col = mix(col, vec3(1.0, 0.92, 0.64), heal_flash * 0.65);
	}

	COLOR = vec4(col, tex.a * v_modulate.a);
}
