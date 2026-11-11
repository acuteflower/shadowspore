shader_type canvas_item;
#include "res://assets/shaders/daylight.gdshaderinc"
varying vec2 daylight_position;
varying vec2 local_px; // the sprite's own pixel space (feet near the origin): the shadow step's dissolve front runs in it
// Flashes the sprite in `flash_color` (white by default). `flash` 1 = fully tinted, 0 = normal.
// `wound` 0..1 is how much blood she has lost: the colours drain towards a cool grey (the skin goes pale) and blood spreads over her body
// from a wound at the waist, following the baked `blood_map` of the current sheet. It starts gently and is strong at the end.

uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float wound : hint_range(0.0, 1.0) = 0.0;
uniform float soak : hint_range(0.0, 1.0) = 0.0; // soaked from the water: darker, richer colours, glints on the lit pixels (Player._wet)
uniform float bandage : hint_range(0.0, 1.0) = 0.0; // 1 = draw the bandage (the pixels the blood map marks with alpha 254)
uniform sampler2D blood_map : filter_nearest, hint_default_white; // baked blood thresholds, same layout as the colour sheet (tools/art_hero3d.py blood)
// The shadow step (Player._animate_step): `step_mode` 1 = she dissolves from the leading edge backwards into the void, 2 = she condenses
// out of it from her core outwards; `step_amt` 0..1 runs each, `step_dir` is the step direction on screen, `step_seed` changes every glitch tick.
uniform int step_mode = 0;
uniform float step_amt : hint_range(0.0, 1.0) = 0.0;
uniform vec2 step_dir = vec2(1.0, 0.0);
uniform float step_seed = 0.0;
// Nebelschleier (VeilFx, docs/magie_konzept.md): `veil` 0..1 veiled, `veil_keep` how much of her stays (drifting mist holes eat the rest),
// `veil_seed` changes with every glitch tick (rows slip sideways).
uniform float veil : hint_range(0.0, 1.0) = 0.0;
uniform float veil_keep : hint_range(0.0, 1.0) = 0.5;
uniform float veil_seed = 0.0;

float veil_hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1)) + veil_seed * 3.17) * 15731.743);
}

float veil_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5453);
	float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(127.1, 311.7))) * 43758.5453);
	float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	daylight_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	local_px = VERTEX;
}

float step_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + step_seed * 17.31) * 43758.5453);
}

// One pixel of the shadow step: x = 1 while the pixel is still there, y = how deep in the void band it sits (0 = body, 1 = the bright rim).
vec2 step_cover(vec2 px) {
	vec2 p = floor(px) + 0.5 - vec2(0.0, -24.0);
	float grain = step_hash(floor(px)) * 0.32 + step_hash(vec2(floor(px.y), 3.0)) * 0.18;
	float edge;
	if (step_mode == 1) {
		float along = dot(p, normalize(step_dir)) / 15.0; // about -1 at her back .. 1 at her front
		edge = along + grain - mix(1.45, -1.55, step_amt);
	} else {
		float r = length(p / vec2(10.0, 21.0)); // her core outwards
		edge = r + grain - mix(-0.05, 1.5, step_amt);
	}
	return vec2(edge > 0.0 ? 0.0 : 1.0, clamp(1.0 + edge / 0.38, 0.0, 1.0));
}

void fragment() {
	if (wound > 0.0 && COLOR.a > 0.01) {
		float lum = dot(COLOR.rgb, vec3(0.3, 0.59, 0.11));
		vec3 pale = vec3(lum * 0.93, lum * 0.98, lum * 1.06);
		COLOR.rgb = mix(COLOR.rgb, pale, wound * 0.6);
		vec4 map = texture(blood_map, UV);
		if (map.a > 0.5 && wound * 0.99 > map.r) {
			// blood lies on the cloth, the skin and the hair as they are shaded: the baked map says where (it grows from the wound), the colour
			// underneath keeps the form, so it is darker in the folds and wet and bright on the lit side; the outline stays ink
			float wet = smoothstep(0.5, 0.85, lum);
			vec3 blood = mix(vec3(0.22, 0.015, 0.05), vec3(0.5, 0.045, 0.1), smoothstep(0.1, 0.7, lum));
			blood = mix(blood, vec3(0.86, 0.26, 0.3), wet * 0.45);
			float ink = 1.0 - smoothstep(0.06, 0.16, lum);
			COLOR.rgb = mix(blood, COLOR.rgb * vec3(0.5, 0.3, 0.34), ink);
		}
	}
	if (bandage > 0.5 && COLOR.a > 0.01) {
		vec4 band_map = texture(blood_map, UV);
		if (band_map.a > 0.5 && band_map.a < 0.999) {
			// a wrap of old linen round the waist: the shading underneath keeps the form, a fine weave breaks it up, the outline stays ink
			float lum = dot(COLOR.rgb, vec3(0.3, 0.59, 0.11));
			vec3 cloth = mix(vec3(0.40, 0.34, 0.33), vec3(0.95, 0.89, 0.80), smoothstep(0.04, 0.45, lum));
			vec2 px = UV * vec2(textureSize(blood_map, 0));
			if (mod(floor(px.x) + floor(px.y), 4.0) < 1.0) {
				cloth *= 0.86;
			}
			float ink = 1.0 - smoothstep(0.06, 0.16, lum);
			COLOR.rgb = mix(cloth, COLOR.rgb, ink * 0.8);
		}
	}
	if (soak > 0.0 && COLOR.a > 0.01) {
		float wl = dot(COLOR.rgb, vec3(0.3, 0.59, 0.11));
		vec3 soaked = mix(vec3(wl), COLOR.rgb, 1.25) * 0.8;
		COLOR.rgb = mix(COLOR.rgb, soaked, soak * 0.85);
		vec2 wpx = floor(UV * vec2(textureSize(TEXTURE, 0)));
		if (wl > 0.55 && mod(wpx.x + wpx.y * 2.0, 7.0) < 1.0) {
			COLOR.rgb += vec3(0.1, 0.14, 0.14) * soak;
		}
	}
	COLOR.rgb = day_grade(COLOR.rgb, daylight_position, 1.0);
	COLOR.rgb = mix(COLOR.rgb, flash_color.rgb, flash);
	if (veil > 0.0 && COLOR.a > 0.01) {
		vec2 cell = floor(local_px);
		vec2 vtex = 1.0 / vec2(textureSize(TEXTURE, 0));
		// whole rows slip sideways now and then
		if (veil_hash(vec2(cell.y * 0.53, 2.0)) > 1.0 - 0.22 * veil) {
			float shift = (veil_hash(vec2(cell.y, 4.0)) < 0.5 ? -1.0 : 1.0) * (1.0 + floor(veil_hash(vec2(cell.y, 6.0)) * 3.0));
			vec4 slipped = texture(TEXTURE, UV + vec2(shift * vtex.x, 0.0));
			COLOR.rgb = slipped.a > 0.01 ? slipped.rgb : COLOR.rgb * 0.4;
		}
		// her colours wash into the mist: shadows lilac-dark, lights pale lilac
		float vl = dot(COLOR.rgb, vec3(0.3, 0.59, 0.11));
		vec3 misted = mix(vec3(0.16, 0.13, 0.34), vec3(0.74, 0.68, 1.0), smoothstep(0.05, 0.9, vl));
		COLOR.rgb = mix(COLOR.rgb, misted, 0.5 * veil);
		// mist holes drift through her (dithered against a 4x4 Bayer grid, so the edges stay pixel art)
		float flow = veil_noise(cell * vec2(0.16, 0.11) + vec2(TIME * 0.7, -TIME * 1.1)) * 0.65 + veil_noise(cell * 0.4 + vec2(-TIME * 1.6, TIME * 0.5)) * 0.35;
		int bi = int(mod(cell.x, 4.0)) + int(mod(cell.y, 4.0)) * 4;
		float bayer = (float((bi * 7 + (bi / 4) * 3) % 16) + 0.5) / 16.0;
		float keep = mix(1.0, veil_keep, veil);
		float eaten = flow * 0.7 + bayer * 0.3;
		if (eaten > keep + 0.12) {
			COLOR.a = 0.0;
		} else if (eaten > keep + 0.085) {
			COLOR.rgb = mix(COLOR.rgb, vec3(0.8, 0.74, 1.0), 0.45); // the pale rim of a hole
		}
		COLOR.a *= mix(1.0, 0.55 + 0.45 * veil_keep, veil);
	}
	if (step_mode > 0 && COLOR.a > 0.01) {
		// glitch: whole pixel rows slip along the step, more of them the further the void has eaten in
		vec2 tex_px = 1.0 / vec2(textureSize(TEXTURE, 0));
		float row = floor(local_px.y);
		float slip = step_hash(vec2(row * 0.37, 11.0));
		float busy = step_mode == 1 ? step_amt : 1.0 - step_amt;
		if (slip > 1.0 - 0.38 * busy) {
			float shift = (step_hash(vec2(row, 5.0)) < 0.5 ? -1.0 : 1.0) * (1.0 + floor(step_hash(vec2(row, 7.0)) * 3.0));
			vec4 slipped = texture(TEXTURE, UV + vec2(shift * tex_px.x, 0.0));
			if (slipped.a > 0.01) {
				COLOR.rgb = mix(COLOR.rgb, slipped.rgb, 0.85);
			} else {
				COLOR.rgb *= 0.25;
			}
			COLOR.rgb = mix(COLOR.rgb, vec3(0.62, 0.36, 1.0), 0.18 * busy);
		}
		vec2 cover = step_cover(local_px);
		if (cover.x < 0.5) {
			COLOR.a = 0.0;
		} else if (cover.y > 0.0) {
			// the void band: black flesh going in, a cold violet rim at the front, magenta sparks flickering in it
			vec3 void_col = mix(vec3(0.016, 0.008, 0.035), vec3(0.15, 0.07, 0.29), smoothstep(0.35, 0.8, cover.y));
			if (cover.y > 0.82) {
				void_col = vec3(0.66, 0.42, 1.0);
			}
			if (step_hash(floor(local_px) + 0.5) > 0.9 && cover.y > 0.4) {
				void_col = vec3(1.0, 0.24, 0.86);
			}
			COLOR.rgb = mix(COLOR.rgb, void_col, smoothstep(0.0, 0.25, cover.y));
		}
	}
}
