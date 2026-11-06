shader_type canvas_item;
// Lights the meadow over large areas so the tiles never read as a grid: sunlit and shaded
// patches (dithered, one palette step apart), and slow drifting mist shadows.
// Works on the six greens of the grass atlas (keep RAMP in sync with tools/art_grass.py);
// flowers, stones and the like keep their own colours.
// On top of the flat greens tiny blades of grass are scattered over the world (1 px wide, 2-3 px tall,
// some light, some dark, more in the shade), their tips sway a little in the wind: depth and texture.

const vec3 RAMP[6] = vec3[6](
	vec3(0.1333, 0.2824, 0.2353),
	vec3(0.1843, 0.3843, 0.3059),
	vec3(0.2431, 0.4902, 0.3373),
	vec3(0.3333, 0.5961, 0.3725),
	vec3(0.4863, 0.7255, 0.4275),
	vec3(0.6588, 0.8627, 0.5490)
);
const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

uniform float patch_size = 110.0; // px per sunlit/shaded patch
uniform float mist_size = 85.0; // px per drifting shadow
uniform float mist_speed = 1.0;
global uniform float g_dew;
global uniform float g_night; // 0..1 night (DayNight): moonlit patches and ground mist
uniform float golden : hint_range(0.0, 1.0) = 0.0; // TimeManager.golden_amount(): warmer sun spots
uniform float sun : hint_range(0.0, 1.0) = 0.0; // TimeManager.sun_amount(): more sunlit meadow, sun flecks, cloud shadows

varying vec2 world_px;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.58 + vnoise(p * 2.07 + 7.3) * 0.28 + vnoise(p * 4.1 - 3.1) * 0.14;
}

// A scattering of little blades and tufts: returns how many ramp steps this pixel moves (0 = none).
// The grid cells are 4 x 6 px, a cell holds at most one blade (sometimes with a short one beside it)
// whose foot is inside it. Light blades are lit along their whole length, dark ones sit in the turf.
int blade_shift(vec2 px, float macro) {
	vec2 cell = floor(vec2(px.x / 4.0, px.y / 6.0));
	float h = hash(cell + 3.3);
	float density = 0.34 + 0.24 * smoothstep(0.55, 0.3, macro);
	if (h > density) {
		return 0;
	}
	float h2 = hash(cell + 9.1);
	float h3 = hash(cell + 21.7);
	float h4 = hash(cell + 41.3);
	float foot_x = floor(cell.x * 4.0) + 1.0 + floor(h2 * 2.0);
	float foot_y = cell.y * 6.0 + 4.0 + floor(h4 * 2.0);
	float height = 2.0 + floor(h3 * 3.0); // 2 to 4
	bool dark = h4 > 0.55;
	float sway = floor(sin(TIME * 1.3 + cell.x * 0.7 + cell.y * 0.4) * 0.6 + 0.5);
	float up = foot_y - px.y; // 0 at the foot, growing upwards
	for (int i = 0; i < 2; i++) {
		float blade_h = i == 0 ? height : height - 1.0; // the second blade is the short one beside it
		if ((i == 1 && h2 < 0.7) || blade_h < 2.0) {
			continue;
		}
		if (up < 0.0 || up >= blade_h) {
			continue;
		}
		float lean = up >= blade_h - 1.0 ? sway : 0.0;
		if (px.x != foot_x + float(i) + lean) {
			continue;
		}
		if (up == 0.0) {
			return -2; // the foot sits in shadow
		}
		if (up == blade_h - 1.0) {
			return dark ? 1 : 3; // the tip catches the light
		}
		return dark ? -2 : 2;
	}
	return 0;
}

void vertex() {
	world_px = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 px = floor(world_px);
	int idx = -1;
	for (int i = 0; i < 6; i++) {
		if (distance(c.rgb, RAMP[i]) < 0.015) {
			idx = i;
		}
	}
	if (idx >= 0) {
		int tip = 0;
		float dither = BAYER[int(mod(px.y, 4.0)) * 4 + int(mod(px.x, 4.0))] / 16.0 - 0.5;
		float macro = fbm(px / patch_size + vec2(3.7, 1.9));
		float mist = fbm(px / mist_size + vec2(TIME * 0.016, TIME * 0.007) * mist_speed + vec2(11.0, 5.0));
		float shift = 0.0;
		float spot = 0.0;
		shift += macro > 0.62 - 0.08 * sun + dither * 0.10 ? 1.0 : 0.0; // sunlit meadow (wider at midday)
		shift += macro > 0.78 - 0.10 * sun + dither * 0.06 ? 1.0 : 0.0;
		shift -= macro < 0.38 + dither * 0.10 ? 1.0 : 0.0; // shaded, mossy
		shift -= macro < 0.22 + dither * 0.06 ? 1.0 : 0.0;
		shift -= mist < 0.32 + dither * 0.10 ? 1.0 : 0.0; // a drifting shadow
		if (sun > 0.5) {
			// small drifting flecks of full sun, and big slow cloud shadows: the contrast is what reads as bright
			float fleck = fbm(px / 38.0 + vec2(TIME * 0.020, TIME * 0.012) + vec2(21.0, 8.0));
			float cloud = fbm(px / 300.0 + vec2(TIME * 0.010, TIME * 0.004) + vec2(40.0, 17.0));
			spot = fleck > 0.63 + dither * 0.08 ? 1.0 : 0.0;
			shift += spot;
			shift -= cloud < 0.33 + dither * 0.06 ? 1.0 : 0.0;
			if (macro < 0.45) {
				// dappled light: patches of sun that reach the shaded ground through the boughs, drifting with the wind
				float dap = vnoise(px / 6.0 + vec2(TIME * 0.05, TIME * 0.03));
				shift += dap > 0.72 + dither * 0.08 ? 1.0 : 0.0;
			}
		}
		if (idx >= 1 && idx <= 4) {
			tip = blade_shift(px, macro);
			shift += float(tip);
		}
		int new_idx = clamp(idx + int(shift), 0, 5);
		c.rgb = RAMP[new_idx];
		if (g_night > 0.0) {
			// the night grade: greens lose their green and lean violet (the tint is multiplied over this)
			float luma = dot(c.rgb, vec3(0.30, 0.59, 0.11));
			c.rgb = mix(c.rgb, vec3(luma * 1.08, luma * 0.78, luma * 1.38), 0.16 * g_night);
		}
		if (spot > 0.0 && new_idx >= 4) { // a spot of full sun: warm, near white highlight above the palette's top green
			c.rgb = mix(c.rgb, mix(vec3(1.0, 0.98, 0.78), vec3(1.0, 0.80, 0.45), golden), 0.42 * sun);
		}
		if (shift < 0.0) {
			c.rgb = mix(c.rgb, vec3(0.20, 0.22, 0.40), 0.16); // shade leans cool violet
		}
		if (tip == 3 && g_dew > 0.0 && hash(px + 3.0) > 0.5) {
			// morning dew: a blade tip now and then catches a pale glint
			float tw = step(0.6, fract(TIME * 0.25 + hash(px) * 9.0));
			c.rgb = mix(c.rgb, vec3(0.93, 1.0, 0.93), 0.85 * g_dew * tw);
		}
	}
	COLOR = c;
}
