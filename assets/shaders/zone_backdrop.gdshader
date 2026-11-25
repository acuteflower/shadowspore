shader_type canvas_item;
// The canopy sea beyond a zone's edge (docs/v2_zonenwelt_atlas_konzept.md 3.4, "Waldmeer"): world-anchored crowns seen
// from above, lit from the upper left, swaying a pixel with the wind, hazing into the dark with distance. Drawn by
// `ZoneBackdrop` (a Sprite2D whose texture is the mask: R = coverage, G = depth 0 at the edge .. 1 far out).
// Whole crowns appear or not by the mask at their centre, so the canopy never ends in a cut line. World-lit.

global uniform vec2 g_wind_dir;
global uniform float g_wind_clock;

uniform sampler2D mask_tex : filter_linear, repeat_disable; // = the sprite's texture (helpers cannot read TEXTURE)
uniform vec4 rect_px; // the sprite's world rect: origin xy, size zw
uniform float cell = 52.0;
uniform vec3 haze : source_color = vec3(0.043, 0.063, 0.055);
uniform vec3 c_gap : source_color = vec3(0.047, 0.067, 0.058);
uniform vec3 c_dark : source_color = vec3(0.082, 0.122, 0.098);
uniform vec3 c_mid : source_color = vec3(0.129, 0.192, 0.141);
uniform vec3 c_lit : source_color = vec3(0.196, 0.282, 0.180);
uniform vec3 c_top : source_color = vec3(0.282, 0.380, 0.243);
uniform vec3 c_cool : source_color = vec3(0.110, 0.106, 0.169);
uniform vec3 cliff_hi : source_color = vec3(0.286, 0.310, 0.365);
uniform vec3 cliff_mid : source_color = vec3(0.196, 0.216, 0.275);
uniform vec3 cliff_dark : source_color = vec3(0.118, 0.133, 0.184);
uniform vec3 cliff_haze : source_color = vec3(0.102, 0.137, 0.188);

varying vec2 world;

float h21(vec2 p) {
	p = mod(p, 1024.0);
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec4 mask_at(vec2 w) {
	return texture(mask_tex, (w - rect_px.xy) / rect_px.zw);
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 p = floor(world) + 0.5;
	vec4 m4 = mask_at(p);
	vec2 m = m4.rg;
	float cliff_m = m4.b;

	// Rocky coastal cliff rim & misty coastal far-view (no tree canopy on cliff borders!)
	if (cliff_m > 0.02 && m.r < 0.05) {
		float strata = vnoise(vec2(p.x / 18.0, p.y / 7.5)) * 0.55 + vnoise(vec2(p.x / 6.0, p.y / 3.0)) * 0.30 + vnoise(p / 34.0) * 0.15;
		float ledge = fract(p.y / 14.0 + vnoise(p / 24.0) * 0.9);
		float band = strata + smoothstep(0.0, 0.22, ledge) * 0.18 - smoothstep(0.75, 1.0, ledge) * 0.24;
		vec3 ccol = band > 0.64 ? cliff_hi : (band > 0.38 ? cliff_mid : cliff_dark);
		// Cool aerial coastal mist with distance from the cliff edge
		float mist = clamp(m.g, 0.0, 1.0);
		ccol = mix(ccol, cliff_haze, mist * 0.78);
		float edge_dither = step(h21(floor(p / 2.0) + 0.21) * 0.32 + 0.18, cliff_m);
		COLOR = vec4(ccol, edge_dither * smoothstep(0.02, 0.18, cliff_m));
	} else if (m.r <= 0.005) {
		// Water or seamless meadow border: completely transparent so ocean / neighbour shows cleanly.
		COLOR = vec4(0.0);
	} else {
		vec2 wd = length(g_wind_dir) > 0.01 ? normalize(g_wind_dir) : vec2(1.0, 0.0);
		vec2 base = floor(p / cell);
		float best = -1.0;
		vec2 best_c = vec2(0.0);
		float best_r = 1.0;
		float best_id = 0.0;
		for (int j = -1; j <= 1; j++) {
			for (int i = -1; i <= 1; i++) {
				vec2 id = base + vec2(float(i), float(j));
				float a = h21(id);
				float b = h21(id + 17.3);
				vec2 c = (id + vec2(0.15 + 0.7 * a, 0.15 + 0.7 * b)) * cell;
				c += floor(wd * sin(g_wind_clock * 1.1 + a * 6.283) * 1.4 + 0.5);
				float r = cell * (0.56 + 0.3 * h21(id + 3.1));
				vec2 rel = (p - c) * vec2(1.0, 1.18);
				float ang = atan(rel.y, rel.x);
				float lobe = 1.0 + 0.1 * sin(ang * (5.0 + floor(a * 3.0)) + b * 6.283) + 0.06 * (vnoise(p / 5.0) - 0.5);
				float d = length(rel) * lobe / r;
				float h = 1.0 - d * d + 0.22 * h21(id + 9.7);
				if (d < 1.0 && h > best) {
					best = h;
					best_c = c;
					best_r = r;
					best_id = a;
				}
			}
		}
		vec3 col;
		float alpha;
		float lives = mask_at(best_c).r;
		if (best > 0.0 && lives > 0.32 + 0.3 * best_id) {
			vec2 n = (p - best_c) / best_r;
			float lit = clamp(0.55 - dot(n, vec2(0.62, 0.78)) * 0.62 - dot(n, n) * 0.28, 0.0, 1.0);
			lit += (vnoise(p / 3.0) - 0.5) * 0.3 + (vnoise(p / 9.0 + best_id * 7.0) - 0.5) * 0.18;
			float rim = smoothstep(0.82, 1.0, length(n));
			lit -= rim * 0.35;
			float step4 = floor(clamp(lit, 0.0, 0.999) * 5.0);
			col = step4 < 1.0 ? c_dark : step4 < 2.0 ? mix(c_dark, c_mid, 0.55) : step4 < 3.0 ? c_mid : step4 < 4.0 ? c_lit : c_top;
			if (step4 < 1.0 && h21(floor(p / 2.0)) < 0.35) {
				col = mix(col, c_cool, 0.5); // cold shade deep in the crowns
			}
			alpha = 1.0;
		} else {
			col = c_gap;
			alpha = step(h21(floor(p / 2.0) + 0.37) * 0.4 + 0.45, m.r); // dithered edge of the dark between the crowns
		}
		col = mix(col, haze, clamp(m.g, 0.0, 1.0) * 0.72);
		COLOR = vec4(col, alpha * step(0.01, m.r + lives));
	}
}
