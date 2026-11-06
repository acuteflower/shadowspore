shader_type canvas_item;
render_mode unshaded;
// The death screen. One quad over the whole screen that reads what has been drawn so far (the world and the
// HUD) and, driven by the script (src/ui/death_screen.gd), plays:
//  - dusk: the colours drain, shadow smoke creeps in from the edges of the screen
//  - eyes: two big glowing magenta eyes open in the dark (the same eyes as the shadow creatures and the void)
//  - bite: black jaws with ragged teeth slam shut from top and bottom (a quarter stays open as the frame of
//    the maw), shock = the white flash, shake = the picture jolts
//  - eaten: what is left of the picture is torn: bands slip sideways, the image wobbles and is pulled
//    towards the middle, colours split, the shadow eats holes with glowing violet rims
//  - cover / release: coming back. The shadow floods the screen from the edges, then retreats from the
//    middle (the heroine) as a ragged wave and shows the clean world (alpha 0).
// Everything on the 640x360 art pixel grid (view_size), like the map.

uniform sampler2D screen : hint_screen_texture, filter_nearest, repeat_disable;
uniform vec2 view_size = vec2(640.0, 360.0);
uniform float time = 0.0;
uniform float dusk = 0.0;
uniform float eyes = 0.0; // 0 shut .. 1 wide open
uniform float eye_scale = 1.0;
uniform float eye_alpha = 1.0;
uniform vec2 eye_at = vec2(0.5, 0.42); // between the eyes, as a fraction of the view
uniform vec2 look = vec2(0.0); // where the pupils look, -1..1
uniform float bite = 0.0; // 0 jaws away .. 1 shut
uniform float eaten = 0.0;
uniform float shock = 0.0;
uniform float shake = 0.0;
uniform float cover = 0.0;
uniform float release = 0.0;
uniform float night = 0.0;

const vec3 VOID0 = vec3(0.016, 0.008, 0.031);
const vec3 VOID1 = vec3(0.04, 0.022, 0.075);
const vec3 VOID2 = vec3(0.075, 0.045, 0.135);
const vec3 VOID3 = vec3(0.12, 0.072, 0.22);
const vec3 VIO5 = vec3(0.353, 0.212, 0.722);
const vec3 VIO6 = vec3(0.541, 0.302, 1.0);
const vec3 VIO7 = vec3(0.690, 0.420, 1.0);
const vec3 VIO8 = vec3(0.925, 0.824, 1.0);
const vec3 MAGENTA = vec3(1.0, 0.31, 0.85);
const vec3 MAGENTA_D = vec3(0.62, 0.08, 0.5);
const vec3 HOT = vec3(1.0, 0.84, 0.96);
const vec3 INK = vec3(0.071, 0.047, 0.11);
const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

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

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v / 0.9375;
}

float bayer(vec2 p) {
	ivec2 i = ivec2(mod(floor(p), 4.0));
	return BAYER[i.y * 4 + i.x] / 16.0;
}

// shadow smoke in five violet-black tones with thin glowing tendrils
vec3 smoke(vec2 p, float lift) {
	vec2 q = p * 0.014;
	vec2 flow = vec2(time * 0.05, -time * 0.035);
	float a = fbm(q + flow + 2.0 * vec2(fbm(q * 0.7 - flow), fbm(q * 0.7 + 3.0 + flow)));
	float t = a * 4.0 - 0.7 + lift + (bayer(p) - 0.5) * 0.85;
	int k = int(clamp(floor(t), 0.0, 3.0));
	vec3 c = k == 0 ? VOID0 : (k == 1 ? VOID1 : (k == 2 ? VOID2 : VOID3));
	float b = fbm(q * 1.8 - flow * 2.0 + 9.0);
	if (abs(b - 0.5) < 0.012 && bayer(p + 1.0) < 0.7) c = mix(c, mix(VIO5, MAGENTA, 0.25 + night * 0.2), 0.55);
	return c;
}

// the picture, torn
vec3 world(vec2 p) {
	vec2 q = (p + 0.5) / view_size;
	float tick = floor(time * 30.0);
	q += (vec2(hash21(vec2(tick, 1.0)), hash21(vec2(tick, 2.0))) - 0.5) * shake * 0.035;
	float band = floor(p.y / 5.0);
	float slip = (hash21(vec2(band, floor(time * 7.0))) - 0.5) * 2.0;
	q.x += slip * eaten * 0.03 * step(0.6, hash21(vec2(band, 7.0)));
	q += (vec2(fbm(p * 0.03 + time * 0.25), fbm(p * 0.03 + 9.0 - time * 0.25)) - 0.5) * 0.06 * eaten;
	vec2 d = q - vec2(0.5);
	q = vec2(0.5) + d * (1.0 - 0.14 * eaten * (1.0 - smoothstep(0.0, 0.7, length(d))));
	float split = floor(eaten * 3.0 + shake * 3.0) / view_size.x;
	vec3 c = vec3(texture(screen, q + vec2(split, 0.0)).r, texture(screen, q).g, texture(screen, q - vec2(split, 0.0)).b);
	float grey = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(c, vec3(grey) * vec3(0.78, 0.74, 0.98), clamp(dusk * 0.85 + eaten * 0.1, 0.0, 1.0));
	c *= 1.0 - dusk * 0.4 - eaten * 0.15;
	return c;
}

// one eye: returns the colour (rgb) and how much of the pixel it covers (a); `side` -1 left, +1 right.
// Like everything of the shadows it is not clean: rows slip sideways, the lid melts and flickers, drips run down.
vec4 eye(vec2 P, vec2 centre, float side, out float glow) {
	float gl = 0.55 + 0.45 * clamp(shock + shake, 0.0, 1.0);
	float ev = eyes * (hash21(vec2(floor(time * 18.0), side + 40.0)) > 0.93 ? 0.3 : 1.0); // now and then it gutters
	float w = 34.0 * eye_scale;
	float h = 17.0 * ev * eye_scale;
	vec2 e = P - centre;
	float row = floor(P.y / 2.0);
	float tk = floor(time * 11.0);
	float slice = step(0.7, hash21(vec2(row, tk + side * 3.0)));
	e.x += (hash21(vec2(row, tk)) - 0.5) * 12.0 * gl * slice; // rows tear sideways
	float x = e.x / w;
	float tilt = -side * x * 0.22 * w * 0.35; // inner corners sink: angry
	float ey = e.y - tilt;
	float hd = length(vec2(e.x / (w * 1.9), e.y / (h * 2.6 + 10.0 * eye_scale)));
	glow = pow(clamp(1.0 - hd, 0.0, 1.0), 2.0) * ev;
	if (abs(x) >= 1.15 || h < 0.5) return vec4(0.0);
	float melt = (vnoise(vec2(e.x * 0.3, time * 4.0 + side * 9.0)) - 0.5) * 5.0 * gl * min(1.0, h / 6.0);
	float lid = h * pow(max(1.0 - x * x, 0.0), 0.8) + melt;
	float inside = lid - abs(ey);
	if (abs(x) >= 1.0) inside = -1.0;
	if (inside < 0.0) {
		// drips running down out of the lower lid
		float dy = ey - lid;
		float col = floor(e.x / 2.0);
		float hh = hash21(vec2(col, side + 12.0));
		float len = (5.0 + 26.0 * hash21(vec2(col, side + 31.0))) * ev * eye_scale * (0.65 + 0.35 * sin(time * 2.5 + hh * 20.0));
		if (ey > 0.0 && dy > 0.0 && dy < len && hh > 0.72 && mod(e.x, 2.0) < 1.0 && abs(x) < 0.9) {
			return vec4(mix(MAGENTA, MAGENTA_D, dy / len) * (bayer(P) < 0.85 ? 1.0 : 0.5), 1.0);
		}
		return vec4(0.0);
	}
	if (inside < 1.2) return vec4(INK, 1.0); // dark rim
	// iris: deep magenta at the corners, hot towards the slit
	float px = e.x - look.x * 7.0 * eye_scale;
	float d = abs(px) / (w * 0.75);
	float heat = clamp(1.0 - d, 0.0, 1.0);
	heat = heat * heat + (bayer(P) - 0.5) * 0.35 + (hash21(P + tk) - 0.5) * 0.18 * gl; // the colour crawls
	vec3 col = heat > 0.62 ? HOT : (heat > 0.28 ? MAGENTA : MAGENTA_D);
	// the slit pupil, shivering, now and then split in two
	float pw = (1.6 + 1.6 * (0.5 + 0.5 * sin(time * 3.0)) + hash21(vec2(tk, side)) * 1.2 * gl) * eye_scale;
	bool two = hash21(vec2(tk + 7.0, side)) > 0.8;
	float pdist = two ? abs(abs(px) - 4.0 * eye_scale) : abs(px);
	if (pdist < pw && abs(ey - look.y * 3.0) < h * 0.88) col = VOID0;
	else if (pdist < pw + 1.0 && abs(ey - look.y * 3.0) < h * 0.88) col = mix(col, HOT, 0.6);
	// a shine up in the corner
	if (inside > 2.0 && e.x < -w * 0.35 && e.x > -w * 0.5 && ey < -h * 0.25 && ey > -h * 0.55) col = HOT;
	return vec4(col, 1.0);
}

void fragment() {
	vec2 p = floor(UV * view_size);
	vec2 P = p + 0.5;
	float edge = min(min(P.x, view_size.x - P.x), min(P.y, view_size.y - P.y)); // px to the nearest screen edge
	float edge_n = clamp(edge / (view_size.y * 0.5), 0.0, 1.0);

	vec3 col = world(p);

	// the dark creeps in from the edges
	float creep = (dusk * 0.55 + eaten * 0.35) * 85.0;
	float noise_e = (fbm(P * 0.05 + vec2(time * 0.2, 0.0)) - 0.5) * 36.0;
	float t = 1.0 - smoothstep(0.0, max(creep, 1.0), edge + noise_e);
	if (creep > 1.0 && t > bayer(p) * 0.92 + 0.05) col = smoke(P, 0.0);

	// the shadow eats holes in the picture, violet where it bites
	if (eaten > 0.0) {
		float hole = fbm(P * 0.04 + vec2(time * 0.04, 3.0));
		float limit = eaten * (0.1 + 0.26 * (1.0 - smoothstep(0.0, 0.6, edge_n))); // mostly at the edges, the middle stays a torn picture
		if (hole < limit) col = smoke(P, 0.3);
		else if (hole < limit + 0.03 && bayer(p) < 0.8) col = mix(VIO7, MAGENTA, hash21(p) * 0.5);
	}

	// the eyes
	if (eyes > 0.001) {
		vec2 c = view_size * eye_at;
		float sep = 56.0 * eye_scale;
		float g0;
		float g1;
		vec4 left = eye(P, c + vec2(-sep, 0.0), -1.0, g0);
		vec4 right = eye(P, c + vec2(sep, 0.0), 1.0, g1);
		float g = max(g0, g1) * eye_alpha;
		float step_g = floor(g * 4.0 + bayer(p) * 0.9) / 4.0;
		col = mix(col, MAGENTA, clamp(step_g, 0.0, 1.0) * 0.55);
		float tk = floor(time * 9.0);
		if (hash21(vec2(tk, 3.0)) > 0.45 && left.a == 0.0 && right.a == 0.0) { // a ghost of the eyes, split in colour
			float ox = (hash21(vec2(tk, 4.0)) - 0.5) * 22.0;
			float gg0;
			float gg1;
			vec4 ghost_l = eye(P + vec2(ox, 1.0), c + vec2(-sep, 0.0), -1.0, gg0);
			vec4 ghost_r = eye(P + vec2(ox, 1.0), c + vec2(sep, 0.0), 1.0, gg1);
			if (ghost_l.a > 0.0 || ghost_r.a > 0.0) col = mix(col, VIO6, 0.4 * eye_alpha);
		}
		if (left.a > 0.0) col = mix(col, left.rgb, eye_alpha);
		if (right.a > 0.0) col = mix(col, right.rgb, eye_alpha);
		// corrupted blocks round them
		vec2 blk = floor(P / vec2(16.0, 3.0));
		float roll = hash21(blk + floor(time * 9.0) * 7.0);
		if (roll > 0.985 && g > 0.05) col = roll > 0.994 ? MAGENTA * 0.85 : VOID0;
	}

	// the jaws: a torn gum line with ragged, uneven teeth from top and bottom; rows slip, strands hang from the teeth
	if (bite > 0.001) {
		float gl = 0.55 + 0.45 * clamp(shock + shake, 0.0, 1.0);
		float tk = floor(time * 8.0);
		float reach = bite * (view_size.y * 0.5 + 14.0);
		float row3 = floor(P.y / 3.0);
		float torn = step(0.78, hash21(vec2(row3, tk + 9.0)));
		float xs = P.x + (hash21(vec2(row3, tk)) - 0.5) * 18.0 * gl * torn; // some rows tear sideways
		float xw = xs + vnoise(vec2(xs * 0.05, 3.0)) * 34.0 + sin(xs * 0.11) * 5.0;
		float tooth = floor(xw / 14.0);
		float f = fract(xw / 14.0 + (hash21(vec2(tooth, 8.0)) - 0.5) * 0.5); // leaning teeth
		float tri = pow(1.0 - abs(f * 2.0 - 1.0), 0.65 + hash21(vec2(tooth, 4.0)) * 0.5);
		tri *= 1.0 + 0.3 * sin(f * 19.0 + tooth); // a notch in the flank
		float jag = (hash21(vec2(floor(xs / 3.0), tk)) - 0.5) * 7.0 * gl * step(0.55, hash21(vec2(floor(xs / 3.0), tk + 5.0)));
		float grow = min(bite * 2.0, 1.0);
		float broken_t = hash21(vec2(tooth, 17.0)) > 0.76 ? 0.28 : 1.0; // broken or missing teeth
		float broken_b = hash21(vec2(tooth, 23.0)) > 0.76 ? 0.28 : 1.0;
		float len_top = (7.0 + 24.0 * hash21(vec2(tooth, 5.0))) * grow * broken_t;
		float len_bot = (7.0 + 24.0 * hash21(vec2(tooth, 11.0))) * grow * broken_b;
		float line_top = reach + len_top * tri - 6.0 + jag;
		float line_bot = view_size.y - reach - len_bot * tri + 6.0 - jag;
		float below_top = line_top - P.y; // > 0 inside the upper jaw
		float above_bot = P.y - line_bot; // > 0 inside the lower jaw
		float inside = max(below_top, above_bot);
		if (inside > 0.0) {
			vec3 flesh = mix(VOID0, smoke(P, -0.6), 0.55);
			float vein = abs(fbm(P * 0.022 + vec2(0.0, time * 0.08)) - 0.5);
			float pulse = 0.55 + 0.45 * sin(time * 2.4);
			if (vein < 0.014 && bayer(p) < 0.8) flesh = mix(flesh, MAGENTA, 0.65 * pulse);
			if (inside < 1.6) flesh = hash21(vec2(floor(P.x / 2.0), tk)) > 0.88 ? MAGENTA : VIO5; // the wet lip glitters
			else if (inside < 3.0 && bayer(p) < 0.6) flesh = mix(flesh, VIO6, 0.5);
			if (f < 0.12 && inside < 12.0 + len_top) flesh = mix(flesh, VIO7, 0.35); // a lit flank on every tooth
			col = flesh;
		} else {
			// strands hanging from the teeth into the picture, swaying and flickering
			float strand_col = floor(xs / 2.0);
			float hs = hash21(vec2(strand_col, 61.0));
			float sway = sin(time * 2.2 + hs * 30.0) * 1.5;
			float reach_s = (6.0 + 34.0 * hash21(vec2(strand_col, 73.0))) * grow * (0.6 + 0.4 * sin(time * 3.0 + hs * 40.0));
			if (hs > 0.8 && mod(xs + floor(sway), 2.0) < 1.0) {
				float dt = P.y - line_top;
				float db = line_bot - P.y;
				float dd = dt > 0.0 && dt < reach_s ? dt : (db > 0.0 && db < reach_s ? db : -1.0);
				if (dd > 0.0) col = dd > reach_s - 3.0 ? MAGENTA : mix(VIO5, VOID0, dd / reach_s);
			}
		}
	}

	col = mix(col, vec3(1.0, 0.92, 1.0), shock);

	// coming back: the shadow floods in from the edges, then retreats from the middle
	float alpha = 1.0;
	if (cover > 0.0 || release > 0.0) {
		float flood = cover * 1.8 + (fbm(P * 0.045 + time * 0.2) - 0.5) * 0.8;
		if (flood > edge_n + (bayer(p) - 0.5) * 0.12) col = smoke(P, 0.2);
		else if (cover >= 1.0) col = smoke(P, 0.2);
		if (release > 0.0) {
			float reach = release * length(view_size) * 1.25;
			float wipe = reach - length(P - view_size * 0.5) + (fbm(P * 0.05 + time * 0.1) - 0.5) * 70.0;
			if (wipe > 7.0) alpha = 0.0;
			else if (wipe > 0.0) col = mix(VIO8, VIO6, wipe / 7.0) * (bayer(p) < 0.8 ? 1.0 : 0.4);
		}
	}
	COLOR = vec4(col, alpha);
}
