shader_type canvas_item;
#include "res://assets/shaders/daylight.gdshaderinc"
// Lights the meadow over large areas so the tiles never read as a grid: sunlit and shaded
// patches, and slow drifting mist shadows. The patches blend smoothly between the palette's
// greens (they used to switch whole palette steps with a Bayer dither, which showed as hard,
// blocky patches); only the grass blades stay crisp whole-step pixels.
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
// The Hexenwald's greens: the same six steps in cold, dark blue-green with a violet lean (docs/hexenwald_konzept.md, section 4).
// Each tile pixel keeps its step; `g_gloom` (BiomeBlend, 0 meadow .. 1 Hexenwald) decides which ramp it is read from.
const vec3 HEX[6] = vec3[6](
	vec3(0.0510, 0.0588, 0.1020),
	vec3(0.0745, 0.1176, 0.1490),
	vec3(0.1059, 0.1725, 0.1765),
	vec3(0.1529, 0.2392, 0.2196),
	vec3(0.2196, 0.3137, 0.2471),
	vec3(0.3137, 0.4078, 0.2824)
);
const float SOFT = 0.06; // half width of a patch edge, in noise units (bigger = softer light patches)

uniform float patch_size = 110.0; // px per sunlit/shaded patch
uniform float mist_size = 85.0; // px per drifting shadow
uniform float mist_speed = 1.0;
global uniform float g_dew;
global uniform float g_night; // 0..1 night (DayNight): moonlit patches and ground mist
global uniform sampler2D g_town_wear : filter_linear, repeat_disable; // the town's trodden ground (TownWear: R8, one pixel per 8 px cell)
global uniform vec4 g_town_wear_rect; // world px of that picture: x, y, w, h (w = 0: no town)
global uniform sampler2D g_gloom : filter_linear, repeat_disable; // BiomeBlend: how much of the Hexenwald's palette each place has (R8, one pixel per 4 x 4 tiles)
global uniform vec4 g_gloom_rect; // world px of that picture: x, y, w, h (w = 0: none)
uniform float golden : hint_range(0.0, 1.0) = 0.0; // TimeManager.golden_amount(): warmer sun spots
uniform float sun : hint_range(0.0, 1.0) = 0.0; // TimeManager.sun_amount(): more sunlit meadow, sun flecks, cloud shadows

varying vec2 world_px;

vec3 ramp(int i, float gloom) {
	return mix(RAMP[i], HEX[i], gloom);
}

// Integer hash (callers pass whole numbers, or whole numbers plus an offset: the fraction is dropped). The old sin() hash lost its
// precision at world coordinates, so neighbouring noise cells got the same value and the sun patches showed hard squares.
float hash(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p)) + ivec2(65536));
	uint h = q.x * 1597334677u ^ q.y * 3812015801u;
	h = (h ^ (h >> 16u)) * 2246822519u;
	h = (h ^ (h >> 13u)) * 3266489917u;
	h ^= h >> 16u;
	return float(h >> 8u) / 16777216.0;
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
int blade_shift(vec2 px, float macro, float wear) {
	vec2 cell = floor(vec2(px.x / 4.0, px.y / 6.0));
	float h = hash(cell + vec2(3.0, 1103.0));
	float density = (0.34 + 0.24 * smoothstep(0.55, 0.3, macro)) * (1.0 - smoothstep(0.15, 0.7, wear)); // trodden ground grows few blades
	if (h > density) {
		return 0;
	}
	float h2 = hash(cell + vec2(2909.0, 9.0));
	float h3 = hash(cell + vec2(5021.0, 7717.0));
	float h4 = hash(cell + vec2(941.0, 4441.0));
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
	float effect_time = g_day_strength > 0.001 ? g_day_clock : TIME;
	int idx = -1;
	for (int i = 0; i < 6; i++) {
		if (distance(c.rgb, RAMP[i]) < 0.015) {
			idx = i;
		}
	}
	if (idx >= 0) {
		int tip = 0;
		float wear = 0.0; // how trodden the ground is here (the town, 0..1)
		if (g_town_wear_rect.z > 0.0) {
			vec2 wuv = (px - g_town_wear_rect.xy) / g_town_wear_rect.zw;
			if (wuv.x >= 0.0 && wuv.y >= 0.0 && wuv.x < 1.0 && wuv.y < 1.0) {
				wear = texture(g_town_wear, wuv).r;
			}
		}
		float gloom = 0.0; // the Hexenwald's share of the palette here; the edge is ragged where it is neither 0 nor 1
		if (g_gloom_rect.z > 0.0) {
			gloom = texture(g_gloom, (px - g_gloom_rect.xy) / g_gloom_rect.zw).r;
			gloom = clamp(gloom + (fbm(px / 19.0 + vec2(40.0, 13.0)) - 0.5) * 0.7 * (1.0 - abs(2.0 * gloom - 1.0)), 0.0, 1.0);
		}
		float macro = fbm(px / patch_size + vec2(3.7, 1.9));
		float mist = fbm(px / mist_size + vec2(effect_time * 0.016, effect_time * 0.007) * mist_speed + vec2(11.0, 5.0));
		float day = g_day_strength; // golden hour has its own light budget
		float shift = 0.0; // in palette steps, now fractional
		float spot = 0.0;
		float lit = 1.0 - 0.85 * gloom; // little sun reaches the Hexenwald
		shift += lit * smoothstep(0.62 - 0.08 * sun - SOFT, 0.62 - 0.08 * sun + SOFT, macro); // sunlit meadow (wider at midday)
		shift += lit * smoothstep(0.78 - 0.10 * sun - SOFT, 0.78 - 0.10 * sun + SOFT, macro);
		shift -= 1.0 - smoothstep(0.38 - SOFT, 0.38 + SOFT, macro); // shaded, mossy
		shift -= 1.0 - smoothstep(0.22 - SOFT, 0.22 + SOFT, macro);
		shift -= 1.0 - smoothstep(0.32 + 0.14 * gloom - SOFT, 0.32 + 0.14 * gloom + SOFT, mist); // a drifting shadow (more of them in the Hexenwald)
		shift -= 0.45 * gloom;
		if (day > 0.0) {
			// small drifting flecks of full sun, and big slow cloud shadows: the contrast is what reads as bright
			float fleck = fbm(px / 38.0 + vec2(effect_time * 0.020, effect_time * 0.012) + vec2(21.0, 8.0));
			float cloud = day_cloud(px);
			spot = smoothstep(0.63 - SOFT, 0.63 + SOFT, fleck) * day * day_local(px) * (1.0 - 0.8 * gloom);
			shift += spot;
			shift -= (1.0 - cloud) * day * 0.65;
			// dappled light: patches of sun that reach the shaded ground through the boughs, drifting with the wind
			shift += day_dapple(px) * day_cover(px) * day * 0.7 * (1.0 - 0.8 * gloom);
		}
		float f = clamp(float(idx) + shift, 0.0, 5.0); // fractional ramp position: blend two neighbouring greens
		int lo = int(floor(f));
		int hi = min(lo + 1, 5);
		c.rgb = mix(ramp(lo, gloom), ramp(hi, gloom), fract(f));
		if (idx >= 1 && idx <= 4) {
			tip = blade_shift(px, macro, wear); // the blades stay crisp: whole palette steps, one pixel wide
			if (tip != 0) {
				c.rgb = ramp(clamp(int(floor(f + 0.5)) + tip, 0, 5), gloom);
			}
		}
		if (wear > 0.02) { // trodden earth: dithered earth pixels that grow denser with the wear
			float earthy = smoothstep(0.12, 0.8, wear);
			if (hash(px + vec2(811.0, 17.0)) < earthy * 1.15) {
				float tone = fbm(px / 5.0 + vec2(2.0, 9.0));
				c.rgb = mix(c.rgb, mix(vec3(0.33, 0.27, 0.21), vec3(0.58, 0.48, 0.36), clamp(tone * 1.3 + 0.08 * shift, 0.0, 1.0)), 0.85);
			}
		}
		if (g_night > 0.0) {
			// the night grade: greens lose their green and lean violet (the tint is multiplied over this)
			float luma = dot(c.rgb, vec3(0.30, 0.59, 0.11));
			c.rgb = mix(c.rgb, vec3(luma * 1.08, luma * 0.78, luma * 1.38), 0.16 * g_night);
		}
		if (spot > 0.0) { // a spot of full sun: warm, near white highlight above the palette's top green
			c.rgb = mix(c.rgb, mix(vec3(1.0, 0.98, 0.78), vec3(1.0, 0.80, 0.45), golden), 0.20 * day * spot * smoothstep(3.0, 4.0, f));
		}
		if (shift < 0.0) {
			c.rgb = mix(c.rgb, vec3(0.20, 0.22, 0.40), (0.16 + 0.16 * gloom) * clamp(-shift, 0.0, 1.0)); // shade leans cool violet (more in the Hexenwald)
		}
		// colour drifts: the meadow is not one green. Broad, slow regions lean lime-yellow (sunny leas) or blue-teal (cool hollows), and sunlit
		// patches take a warm cast, so the day has more colour than the six palette greens alone; the Hexenwald keeps its own ramp.
		float region = fbm(px / 340.0 + vec2(91.0, 17.0)) - 0.5;
		float warm = clamp(shift, 0.0, 2.0) * 0.5;
		vec3 cast = vec3(1.0 + 0.30 * region, 1.0 + 0.05 * region, 1.0 - 0.45 * region);
		cast = mix(cast, cast * vec3(1.08, 1.02, 0.82), warm * (0.35 + 0.65 * sun));
		c.rgb *= mix(vec3(1.0), cast, 1.0 - gloom);
		if (tip == 3 && g_dew > 0.0 && hash(px + vec2(3301.0, 77.0)) > 0.5) {
			// morning dew: a blade tip now and then catches a pale glint
			float tw = step(0.6, fract(effect_time * 0.25 + hash(px) * 9.0));
			c.rgb = mix(c.rgb, vec3(0.93, 1.0, 0.93), 0.85 * g_dew * tw);
		}
	}
	if (g_wet > 0.01) {
		// the wet world (docs/wetter_konzept.md 6.3): darker and cooler ground, puddles that mirror the sky with rings in the rain, splashes
		c.rgb *= mix(vec3(1.0), vec3(0.84, 0.88, 0.95), g_wet * 0.8);
		float rl = rain_local(px) * (1.0 - 0.8 * day_cover(px));
		float pm = 0.0;
		if (g_puddle > 0.02) {
			// puddles gather in hollows: a broad "puddly" region decides where, a warped noise shapes each one (ragged, lobed, never round)
			float hollow = vnoise(px / 150.0 + vec2(51.0, 9.0)); // one cheap octave: most of the ground is dry and stops right here
			float warp = (hollow < 0.2 ? 0.0 : vnoise(px / 8.0 + vec2(7.0, 61.0)) - 0.5);
			float pn = hollow < 0.2 ? 0.0 : fbm(px / 27.0 + vec2(133.0, 41.0) + warp * 0.55) + 0.55 * (hollow - 0.5);
			float pthr = 0.815 - 0.12 * g_puddle;
			float depth = clamp((pn - pthr) / 0.08, 0.0, 1.0);
			float edge = hash(px + vec2(311.0, 5.0)); // the shore is dithered, so the pool dissolves into the mud
			pm = pn > pthr + 0.018 * edge ? 1.0 : 0.0;
			// wet mud round the water: darker, a little browner
			float mud = smoothstep(pthr - 0.08, pthr - 0.005, pn) * (1.0 - pm);
			c.rgb = mix(c.rgb, c.rgb * vec3(0.60, 0.56, 0.55), 0.85 * mud);
			if (pm > 0.5) {
				// the sky in the water: a vertical gradient wobbled by the ripples, darker and bluer towards the middle (deep), clearer at the edge
				float wob = vnoise(px / 5.0 + vec2(TIME * 0.05, 0.0)) - 0.5;
				float gy = clamp(0.5 + 0.5 * sin((px.y + wob * 14.0) / 9.0), 0.0, 1.0);
				vec3 sky_day = mix(vec3(0.44, 0.60, 0.74), vec3(0.78, 0.89, 0.95), gy * (0.25 + 0.75 * sun));
				vec3 sky_night = mix(vec3(0.10, 0.12, 0.26), vec3(0.26, 0.30, 0.52), gy);
				vec3 sky = mix(sky_day, sky_night, g_night);
				vec3 deep = mix(vec3(0.15, 0.26, 0.36), vec3(0.05, 0.07, 0.15), g_night);
				vec3 water = mix(sky, deep, 0.55 * depth);
				c.rgb = mix(c.rgb * 0.6, water, 0.55 + 0.30 * smoothstep(0.0, 0.5, depth)); // shallow: the ground still shows through
				// the reflection breaks up in short, wobbling pixel streaks (a bush or a trunk standing in the mirror)
				float streak = hash(vec2(floor((px.x + wob * 6.0) / 3.0), floor(px.y / 2.0) + 17.0));
				if (streak > 0.93) { c.rgb = mix(c.rgb, mix(vec3(0.93, 0.97, 1.0), vec3(0.62, 0.68, 0.95), g_night), 0.22 + 0.18 * (1.0 - depth)); }
				if (streak < 0.05) { c.rgb *= 0.88; }
				// a thin bright rim where the water meets the land
				if (depth < 0.12) { c.rgb = mix(c.rgb, vec3(0.86, 0.92, 0.98), 0.20 * (1.0 - g_night * 0.6)); }
				vec2 rc = floor(px / 11.0);
				float rh = hash(rc + vec2(7.0, 3.0));
				if (rh < 0.55 * rl) {
					float ph = fract(TIME * 0.9 + rh * 17.0);
					vec2 centre = (rc + 0.25 + 0.5 * vec2(hash(rc + 1.0), hash(rc + 2.0))) * 11.0;
					vec2 dv = (px + 0.5 - centre) * vec2(1.0, 1.6); // rings lie flat on the ground (3/4 view)
					float rd = length(dv);
					if (ph < 0.85 && abs(rd - ph * 5.5) < 0.72) { c.rgb = mix(c.rgb, vec3(0.92, 0.96, 1.0), 0.6 * (1.0 - ph)); }
				}
			}
		}
		if (pm < 0.5 && rl > 0.05) {
			vec2 sc = floor(px / 10.0);
			float sh = hash(sc + vec2(23.0, 5.0));
			if (sh < 0.16 * rl) {
				float sp = fract(TIME * 2.2 + sh * 11.0);
				vec2 at = floor(vec2(hash(sc + 4.0), hash(sc + 9.0)) * 8.0) + 1.0;
				vec2 lp = px - sc * 10.0;
				if (sp < 0.34) {
					if (lp == at) { c.rgb = mix(c.rgb, vec3(0.88, 0.94, 1.0), 0.55); }
					else if (sp > 0.12 && (lp == at + vec2(2.0, -1.0) || lp == at + vec2(-2.0, -1.0))) { c.rgb = mix(c.rgb, vec3(0.88, 0.94, 1.0), 0.32); } // the crown of the splash
				}
			}
		}
	}
	c.rgb = day_grade(c.rgb, px, 0.45);
	COLOR = c;
}
