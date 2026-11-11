shader_type canvas_item;
render_mode unshaded;
// The tear in the air of Ellie's shadow step (ShadowStepFx), drawn in the language of the void spider's birth mouth (shadow_birth.gdshader):
// a ragged wound of ink built from jagged knots that rips open from its middle outwards, mottled black-violet flesh inside, a cold rim,
// branching veins reaching out of it with light pulsing outwards along them, rare violet glints, a thin glowing seam where it is widest,
// whole pixel rows slipping sideways (glitch), the ground warping at its lips, and a stochastic crumble when it snaps shut.
// Every step gets its own `seed`, so no two tears look alike. The quad is SIZE pixels, the tear stands in its middle.
uniform sampler2D ground : hint_screen_texture, repeat_disable, filter_nearest;
uniform float age = 0.0;      // seconds since this tear started (veins pulse, edges live)
uniform float open_amt = 0.0; // 0 shut .. 1 fully torn open
uniform float close_amt = 0.0; // 0 .. 1 crumbling away
uniform float seed = 0.0;
uniform float lean = 0.0;     // the tear leans a little, every step another way
const vec2 SIZE = vec2(44.0, 76.0);
const int KNOTS = 7;
const float BAYER[16] = float[16](0.,8.,2.,10.,12.,4.,14.,6.,3.,11.,1.,9.,15.,7.,13.,5.);

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233)) + seed * 91.7) * 43758.5453); }

vec2 knot(float i) {
	// top to bottom, every knot torn sideways a little; the ends run thin
	float y = (i - 3.0) * 9.5;
	return vec2((hash(vec2(i, 8.1)) - 0.5) * (i == 0.0 || i == 6.0 ? 4.0 : 11.0) + y * lean, y + (hash(vec2(i, 9.3)) - 0.5) * 4.0);
}

float segment(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 0.001), 0.0, 1.0);
	return length(p - a - ab * t);
}

void fragment() {
	vec2 pixel = floor(UV * SIZE);
	float tick = floor(age * 30.0);
	// glitch: rows (in pairs) slip sideways by whole pixels, more of them while it tears and while it crumbles
	float row = floor(pixel.y * 0.5);
	float unrest = 0.12 + 0.35 * (1.0 - open_amt) * step(0.01, open_amt) + 0.45 * close_amt;
	if (hash(vec2(row, tick)) < unrest) {
		pixel.x += (hash(vec2(row, tick + 3.0)) < 0.5 ? -1.0 : 1.0) * (1.0 + floor(hash(vec2(row, tick + 7.0)) * 2.0));
	}
	vec2 p = pixel + 0.5 - SIZE * 0.5;
	float t = floor(age * 12.0) / 12.0;
	float bite = (hash(floor(pixel * 0.5)) - 0.5) * 1.5;
	float wound = 100.0;
	float spine = 100.0;
	float branch = 100.0;
	float pulse = 0.0;
	for (int i = 0; i < KNOTS - 1; i++) {
		float k = float(i);
		vec2 a = knot(k);
		vec2 b = knot(k + 1.0);
		float delay = abs(k - 2.5) * 0.11 + hash(vec2(k, 12.0)) * 0.12;
		float spread = smoothstep(delay, delay + 0.42, open_amt);
		// it rips from the middle: each piece grows from its inner end
		if (k < 2.5) { a = mix(b, a, spread); } else { b = mix(a, b, spread); }
		float swell = smoothstep(0.25 + delay, 0.9 + delay, open_amt);
		float centre = 1.0 - abs(k - 2.5) / 3.0; // widest in the middle
		float width = (0.7 + hash(vec2(k, 4.0)) * 1.0 + swell * (2.0 + 2.6 * centre + hash(vec2(k, 5.0)) * 1.6)) * spread;
		width *= 1.0 - close_amt * 0.7;
		width += sin(t * 2.6 + k * 2.7 + p.y * 0.31) * swell * 0.7; // a living, uneven lip
		float d = segment(p, a, b);
		wound = min(wound, d - width + bite);
		spine = min(spine, d);
		// one vein per piece reaches out sideways, forks once
		// not every piece grows one; they run out diagonally (up from the upper half, down from the lower) and bend as they go
		vec2 root = mix(knot(k), knot(k + 1.0), hash(vec2(k, 16.0)));
		float side = hash(vec2(k, 17.0)) > 0.5 ? 1.0 : -1.0;
		float drift = (k < 2.5 ? -1.0 : 1.0) * (0.4 + hash(vec2(k, 18.0)) * 1.1);
		float len1 = 3.0 + hash(vec2(k, 19.0)) * 8.0;
		vec2 elbow = root + vec2(side, drift) * len1;
		vec2 tip = elbow + vec2(side * (0.4 + hash(vec2(k, 23.0))), drift * (0.6 + hash(vec2(k, 20.0)) * 1.4)) * (2.0 + hash(vec2(k, 21.0)) * 7.0);
		float grows = step(0.32, hash(vec2(k, 24.0)));
		float reach = smoothstep(delay + 0.15, delay + 0.75, open_amt) * (1.0 - close_amt) * grows;
		float dbranch = min(segment(p, root, mix(root, elbow, reach)), segment(p, elbow, mix(elbow, tip, reach)));
		float branch_width = (0.45 + hash(vec2(k, 22.0)) * 0.8) * reach;
		branch = min(branch, dbranch - branch_width);
		if (dbranch < branch_width + 1.0) {
			pulse = max(pulse, 0.5 + 0.5 * sin(length(p - root) * 0.9 - age * 16.0 + k * 1.7)); // light runs outwards along it
		}
	}
	float h = hash(pixel);
	float stipple = BAYER[int(mod(pixel.y, 4.0)) * 4 + int(mod(pixel.x, 4.0))] / 16.0;
	float inside = 1.0 - step(0.0, wound);
	float on_branch = 1.0 - step(0.0, branch);
	float rim = (1.0 - smoothstep(-1.0, 1.6, wound)) * (1.0 - inside);
	// the flesh of the void: mottled in 2x2 grains, lighter just inside the lip, a glowing seam down the middle where it gapes widest
	vec3 dark = mix(vec3(0.024, 0.012, 0.045), vec3(0.085, 0.05, 0.15), hash(floor(pixel * 0.5) + 7.0) * 0.85);
	if (wound > -1.6 && stipple < 0.55) { dark = vec3(0.14, 0.085, 0.27); }
	if (spine < 0.75 && open_amt > 0.55 && hash(vec2(floor(pixel.y * 0.5), tick)) > 0.62) { dark = hash(pixel + tick) > 0.9 ? vec3(0.95, 0.3, 0.85) : vec3(0.3, 0.19, 0.55); } // the seam only glimmers here and there
	if (h > 0.965 && sin(age * 9.0 + h * 40.0) > 0.2) { dark = vec3(0.6, 0.4, 1.0); }
	vec3 vein = mix(vec3(0.2, 0.12, 0.4), vec3(0.66, 0.54, 0.94), pulse * pulse);
	// the lip is not an outline: mostly a dark violet bruise, lit only on the side the light comes from (upper left) and broken by grain
	float lit_side = step(0.0, -p.x - p.y * 0.3);
	vec3 lip = mix(vec3(0.17, 0.1, 0.31), vec3(0.49, 0.34, 0.88), lit_side * step(0.45, hash(floor(pixel * 0.5) + 3.0)));
	vec3 col = inside > 0.5 ? dark : (on_branch > 0.5 ? vein : lip);
	// the ground (and whatever stands behind) warps at the lips
	float warp = (1.0 - smoothstep(1.0, 5.0, abs(wound))) * open_amt * (1.0 - close_amt);
	vec2 shift = vec2(sin(p.y * 0.4 + t * 3.0), cos(p.x * 0.3 - t * 2.0)) * warp * 1.6;
	vec3 behind = texture(ground, SCREEN_UV + shift * SCREEN_PIXEL_SIZE).rgb;
	float ink = max(inside, on_branch * 0.9);
	float rim_a = rim * (stipple < 0.5 ? 0.7 : 0.0) * step(0.18, hash(pixel + 31.0));
	col = mix(behind, col, max(ink, rim_a));
	float alpha = max(max(ink, rim_a), warp * 0.6);
	// snapping shut: the same outward stochastic crumble as the creatures' footprints
	if (h < close_amt * (0.7 + length(p) / 40.0) || open_amt <= 0.0) { alpha = 0.0; }
	COLOR = vec4(col, alpha);
}
