shader_type canvas_item;
render_mode unshaded;
// Recessed astral mirror-water shader for the two Star Bridge reflection basins (docs/sternensaal_konzept.md):
// - Pixel-locked via floor(UV * basin_size)
// - Deep night-sapphire & violet water with top-left recessed stone overhang shadow
// - Reflected drifting pixel stars (1x1 + twinkling 3x3 cross stars) subtly displaced by integer ripples
// - Crisp horizontal pixel water-ripple streaks and Bayer-dithered turquoise rim reflections

uniform vec2 basin_size = vec2(44.0, 162.0);
uniform vec2 cam_offset = vec2(0.0, 0.0);
uniform float time = 0.0;
uniform float mirror_seed = 0.0;

const vec3 OVERHANG = vec3(0.016, 0.012, 0.047); // #04030c deep cosmic recess shadow
const vec3 SAP0     = vec3(0.024, 0.027, 0.086); // #060716 abyssal space water
const vec3 SAP1     = vec3(0.047, 0.067, 0.165); // #0c112a
const vec3 SAP2     = vec3(0.075, 0.118, 0.251); // #131e40
const vec3 SAP3     = vec3(0.110, 0.184, 0.333); // #1c2f55

const vec3 TEAL0    = vec3(0.165, 0.549, 0.580); // #2a8c94
const vec3 TEAL1    = vec3(0.235, 0.753, 0.776); // #3cc0c6
const vec3 TEAL2    = vec3(0.471, 0.957, 0.902); // #78f4e6
const vec3 TEAL3    = vec3(0.816, 1.000, 0.973); // #d0fff8
const vec3 GOLD2    = vec3(0.902, 0.769, 0.408); // #e6c468
const vec3 GOLD3    = vec3(1.000, 0.941, 0.690); // #fff0b0
const vec3 STAR_SIL = vec3(0.831, 0.824, 0.918); // #d4d2ea

const float BAYER[16] = float[16](
	0.0,  8.0,  2.0, 10.0,
	12.0, 4.0, 14.0,  6.0,
	3.0, 11.0,  1.0,  9.0,
	15.0, 7.0, 13.0,  5.0
);

float hash21(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p)) + ivec2(32768));
	q = q * 1664525u + 1013904223u;
	q.x += q.y * 1664525u;
	q.y += q.x * 1664525u;
	q ^= q >> 16u;
	q.x += q.y * 1664525u;
	q.y += q.x * 1664525u;
	q ^= q >> 16u;
	return float(q.x) * (1.0 / 4294967296.0);
}

float bayer(vec2 p) {
	ivec2 i = ivec2(mod(floor(p), 4.0));
	return BAYER[i.y * 4 + i.x] / 16.0;
}

void fragment() {
	vec2 p = floor(UV * basin_size);
	float by = bayer(p);

	// 1. Deep night-sapphire water base with Bayer-dithered depth gradient
	float u_norm = p.x / max(basin_size.x, 1.0);
	float v_norm = p.y / max(basin_size.y, 1.0);
	float swell = 0.25 * sin(p.y * 0.065 - time * 0.9 + mirror_seed) + 0.18 * cos(p.x * 0.12 + time * 0.6);
	float grad = v_norm * 1.65 + u_norm * 0.75 + swell + (by - 0.5) * 0.85;
	int k = int(clamp(floor(grad), 0.0, 3.0));
	vec3 col = k == 0 ? SAP0 : (k == 1 ? SAP1 : (k == 2 ? SAP2 : SAP3));

	// 2. Integer horizontal ripple offset for reflected stars
	float ripple_shift = round(sin(p.y * 0.32 - time * 2.1 + mirror_seed) * 0.68);
	vec2 sp = vec2(p.x + ripple_shift, p.y) - floor(cam_offset * 0.22) + vec2(mirror_seed * 13.0, floor(time * 1.4));

	// Fine reflected 1x1 stars
	vec2 c1 = floor(sp / 11.0);
	vec2 l1 = sp - c1 * 11.0;
	float h1 = hash21(c1 + vec2(29.0, 47.0));
	if (h1 > 0.74) {
		vec2 pos1 = floor(vec2(1.0) + vec2(hash21(c1 + vec2(3.0, 9.0)), hash21(c1 + vec2(17.0, 5.0))) * 9.0);
		if (l1.x == pos1.x && l1.y == pos1.y) {
			float tw1 = 0.5 + 0.5 * sin(time * 1.8 + h1 * 41.0);
			if (tw1 > 0.25) {
				col = fract(h1 * 19.0) > 0.45 ? STAR_SIL : TEAL2;
			}
		}
	}

	// Larger reflected 3x3 cross-stars (gold & turquoise)
	vec2 sp2 = vec2(p.x + ripple_shift, p.y) - floor(cam_offset * 0.35) + vec2(mirror_seed * 7.0, floor(time * 0.8));
	vec2 c2 = floor(sp2 / 24.0);
	vec2 l2 = sp2 - c2 * 24.0;
	float h2 = hash21(c2 + vec2(83.0, 61.0));
	if (h2 > 0.76) {
		vec2 pos2 = floor(vec2(3.0) + vec2(hash21(c2 + vec2(11.0, 2.0)), hash21(c2 + vec2(23.0, 19.0))) * 18.0);
		vec2 d2 = abs(l2 - pos2);
		bool gold_star = fract(h2 * 13.3) > 0.48;
		float tw2 = 0.5 + 0.5 * sin(time * 1.5 + h2 * 53.0);
		if (d2.x == 0.0 && d2.y == 0.0) {
			col = gold_star ? GOLD3 : TEAL3;
		} else if (tw2 > 0.38 && ((d2.x == 1.0 && d2.y == 0.0) || (d2.x == 0.0 && d2.y == 1.0))) {
			col = gold_star ? GOLD2 : TEAL1;
		}
	}

	// 3. Crisp horizontal 1px pixel water-ripple streaks gliding gently
	float row_h = hash21(vec2(p.y, 13.0 + mirror_seed));
	if (row_h > 0.80) {
		float dir = fract(row_h * 9.7) > 0.5 ? 1.0 : -1.0;
		float band_len = 5.0 + floor(fract(row_h * 27.1) * 6.0);
		float cycle = basin_size.x + band_len + 8.0;
		float head = mod(fract(row_h * 43.3) * cycle + time * (2.6 + fract(row_h * 5.1) * 1.8) * dir + cycle * 10.0, cycle) - 4.0;
		float dx = p.x - head;
		if (dx >= 0.0 && dx < band_len && p.x > 2.0 && p.x < basin_size.x - 2.0 && p.y > 4.0) {
			bool mid_px = dx >= 1.5 && dx <= band_len - 2.5;
			col = mid_px ? (fract(row_h * 31.0) > 0.78 ? GOLD2 : TEAL2) : mix(col, TEAL0, 0.75);
		}
	}

	// 4. Delicate turquoise rim reflections & top-left recessed stone overhang shadow
	float d_right = (basin_size.x - 1.0) - p.x;
	float d_bot   = (basin_size.y - 1.0) - p.y;
	float rim_lit = max(
		1.0 - clamp(d_right / 3.5, 0.0, 1.0),
		1.0 - clamp(d_bot / 3.5, 0.0, 1.0)
	);
	float shimmer = 0.75 + 0.25 * sin(time * 2.0 + (p.x + p.y) * 0.2 + mirror_seed);
	if (rim_lit * shimmer > by * 0.85 + 0.12) {
		col = mix(col, d_right < 1.2 || d_bot < 1.2 ? TEAL2 : TEAL0, 0.65);
	}

	// Subtle teal rim glint right along the inner shadow border
	if ((p.x == 2.0 && p.y >= 3.0) || (p.y == 3.0 && p.x >= 2.0)) {
		if (by < 0.45 + 0.2 * sin(time * 1.7 + p.y * 0.15)) {
			col = mix(col, TEAL0, 0.50);
		}
	}

	// Top 3px and Left 2px submerged marble curb shadow (top-left light source!)
	if (p.y < 2.0 || p.x < 1.0) {
		col = OVERHANG;
	} else if (p.y < 3.0 || p.x < 2.0) {
		col = mix(OVERHANG, col, 0.42);
	}

	COLOR = vec4(col, 1.0);
}
