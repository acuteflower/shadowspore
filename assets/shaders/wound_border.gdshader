shader_type canvas_item;
// The permanent bleeding border of the wounded state, drawn on the game's own art-pixel grid (360 rows high), no smooth gradients:
//  - a dark, dithered vignette that only darkens (never a pink wash),
//  - clotted blood creeping in from every edge, deeper in the corners, its outline wobbling from 2D noise in screen space
//    (no angle around the middle, so there is no seam), dark at the edge and wetter towards its lip,
//  - a one-pixel wet lip lit from the upper left,
//  - thin branching capillaries reaching further in,
//  - the heartbeat (lub-dub) running from the edges inwards along blood and veins,
//  - slow drops that run down from the top edge, swell at the tip and fade,
//  - the picture under it (the world: the border sits below the HUD's vines) is reddened and drained a little, stronger
//    towards the edges, and its rows slip sideways in whole art pixels, pulled inwards with every heartbeat.
// `grow` 0..1 unrolls it (hurt) or withdraws it (healed), `phase` = seconds since the last heartbeat, `flash` = the jolt
// when she becomes wounded.

uniform float grow : hint_range(0.0, 1.0) = 0.0;
uniform float phase = 0.0;
uniform float time = 0.0;
uniform float flash = 0.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;

const vec3 INK = vec3(0.07, 0.004, 0.03);
const vec3 DARK = vec3(0.22, 0.02, 0.06);
const vec3 MID = vec3(0.42, 0.04, 0.10);
const vec3 BRIGHT = vec3(0.66, 0.08, 0.15);
const vec3 WET = vec3(0.93, 0.36, 0.38);

float hash(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.03 + 7.1) * 0.3 + vnoise(p * 4.1 + 13.7) * 0.15;
}

float bayer(vec2 a) {
	ivec2 c = ivec2(mod(a, 4.0));
	int i = c.x + c.y * 4;
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}

// The double heartbeat `t` seconds after it began.
float heart(float t) {
	float lub = t >= 0.0 ? exp(-t * 9.0) : 0.0;
	float dub = t >= 0.28 ? 0.7 * exp(-(t - 0.28) * 11.0) : 0.0;
	return max(lub, dub);
}

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 size = vec2(floor(360.0 * aspect), 360.0);
	vec2 a = floor(UV * size); // art pixel
	float dx = min(a.x, size.x - 1.0 - a.x);
	float dy = min(a.y, size.y - 1.0 - a.y);
	float k = 30.0; // soft minimum: the corners sit deeper
	float e = -k * log(exp(-dx / k) + exp(-dy / k)) + k * 0.69;

	float g = grow;
	// the beat travels inwards: deeper pixels feel it a little later
	float pulse = heart(phase - e * 0.006) * g;

	// outline of the clotted blood
	vec2 drift = vec2(time * 0.35, -time * 0.22);
	float n = fbm((a + drift) / 26.0);
	float lobes = fbm(a / 70.0 + 3.0);
	float reach = g * (2.0 + n * 12.0 + lobes * lobes * 46.0) + pulse * 2.5 + flash * 18.0;
	float inner = reach - e; // > 0 inside the blood

	// capillaries: thin ridges of noise, warped, reaching further in
	vec2 w = a / 22.0 + vec2(fbm(a / 40.0 - drift * 0.02), fbm(a / 40.0 + 5.0)) * 1.6;
	float ridge = 1.0 - abs(vnoise(w) * 2.0 - 1.0);
	float ridge2 = 1.0 - abs(vnoise(w * 2.1 + 9.0) * 2.0 - 1.0);
	float vein_reach = reach + g * (10.0 + lobes * 22.0);
	float vein_fade = clamp((vein_reach - e) / 14.0, 0.0, 1.0);
	bool vein = (ridge > 0.955 || (ridge2 > 0.97 && vein_fade > 0.45)) && vein_fade > bayer(a + 2.0) * 0.9;

	// drops running down from the top edge: two pixels wide, short, a round bead at the tip that swells before it falls
	float col_id = floor(a.x / 14.0);
	float drop_x = col_id * 14.0 + 2.0 + floor(hash(vec2(col_id, 3.0)) * 9.0);
	bool drop = false;
	bool bead = false;
	float off = a.x - drop_x;
	if (hash(vec2(col_id, 11.0)) < 0.45 && off >= -1.0 && off <= 2.0) {
		float period = 6.0 + hash(vec2(col_id, 5.0)) * 8.0;
		float cyc = fract(time / period + hash(vec2(col_id, 8.0)));
		vec2 top = vec2(drop_x, 0.0);
		float top_reach = g * (2.0 + fbm((top + drift) / 26.0) * 12.0 + pow(fbm(top / 70.0 + 3.0), 2.0) * 46.0);
		float len = smoothstep(0.0, 0.8, cyc) * (4.0 + hash(vec2(col_id, 2.0)) * 14.0) * g;
		float tip = top_reach + len;
		float alive = 1.0 - smoothstep(0.82, 1.0, cyc);
		bool stem = off >= 0.0 && off <= 1.0 && a.y < tip - 1.0 && a.y > top_reach - 3.0;
		bool round = a.y >= tip - 2.0 && a.y <= tip + 1.0 && (off >= 0.0 && off <= 1.0 || (a.y >= tip - 1.0 && a.y <= tip && cyc > 0.3));
		drop = (stem || round) && alive > bayer(a) * 0.95 && len > 1.0;
		bead = drop && round;
	}
	vec4 c = vec4(0.0);
	// 1. vignette: darkens only, dithered into four steps
	float vig = smoothstep(70.0, 0.0, e) * (0.22 + 0.12 * pulse) * g;
	vig = floor(vig * 4.0 + bayer(a)) / 4.0;
	c = vec4(INK, vig);

	// 2. the dithered skirt just outside the blood
	if (inner > -5.0 && inner <= 0.0 && (inner + 5.0) / 5.0 > bayer(a)) {
		c = vec4(DARK, 0.75);
	}
	// 3. veins
	if (vein && inner <= 0.0) {
		float lit = heart(phase - e * 0.006 - 0.05) * g;
		vec3 vc = mix(DARK, BRIGHT, clamp(vein_fade * 0.6 + lit * 0.8, 0.0, 1.0));
		c = vec4(vc, 0.95);
	}
	// 4. the blood itself
	if (inner > 0.0) {
		float depth = clamp(inner / 16.0, 0.0, 1.0);
		vec3 bc = mix(MID, INK, depth); // clotted and dark at the screen edge, wetter towards the lip
		float mott = vnoise(a / 3.0 + 40.0);
		bc = mix(bc, DARK, step(0.72, mott) * 0.6);
		bc = mix(bc, BRIGHT, step(0.9, mott) * (1.0 - depth) * 0.7);
		bc = mix(bc, BRIGHT, pulse * (1.0 - depth) * 0.55);
		c = vec4(bc, 0.97);
		if (inner < 1.6) { // the wet lip, lit from the upper left
			vec2 pos = a / size - 0.5;
			float light = clamp(0.5 - pos.x * 0.9 - pos.y * 0.9, 0.0, 1.0);
			c.rgb = mix(MID, WET, smoothstep(0.35, 1.0, light) * (0.55 + 0.45 * pulse));
			c.rgb = mix(c.rgb, BRIGHT, 0.35 + 0.4 * pulse);
		} else if (inner < 3.0) {
			c.rgb = mix(c.rgb, MID, 0.6);
		}
	}
	// 5. drops
	if (drop) {
		c = vec4(bead ? BRIGHT : MID, 0.97);
		if (bead && a.y <= floor(UV.y * size.y) && off == 0.0) {
			c.rgb = mix(BRIGHT, WET, 0.5); // a glint on the bead's upper left
		}
	}

	// the jolt when she becomes wounded: the border flares
	c.rgb = mix(c.rgb, WET, flash * 0.35 * step(0.0, inner));
	c.a = clamp(c.a * min(1.0, g * 3.0 + flash), 0.0, 1.0);

	// the world under it: rows slip sideways and the picture is pulled inwards on the beat, in whole art pixels
	float edge = pow(clamp(1.0 - e / 200.0, 0.0, 1.0), 2.2); // 1 at the screen edge, 0 deep inside
	float sway = (vnoise(vec2(a.y / 9.0, time * 0.9)) - 0.5) * 2.0;
	float slip = floor(sway * (0.6 + edge * 2.4) * g + 0.5);
	vec2 to_mid = normalize(size * 0.5 - a + 0.001);
	vec2 pull = floor(to_mid * (pulse * edge * 2.2 + flash * edge * 3.0) + 0.5);
	vec2 shift = vec2(slip, 0.0) + pull;
	vec3 world = texture(screen_tex, SCREEN_UV - shift / size).rgb;
	float grey = dot(world, vec3(0.3, 0.55, 0.15));
	float red = g * (0.1 + 0.38 * edge + 0.08 * pulse) + flash * 0.25;
	vec3 drained = mix(world, vec3(grey), red * 0.5);
	vec3 tinted = mix(drained, grey * vec3(1.7, 0.42, 0.5) + vec3(0.07, 0.0, 0.02), red * 0.85); // the light itself turns to blood
	COLOR = vec4(mix(tinted, c.rgb, c.a), 1.0);
}
