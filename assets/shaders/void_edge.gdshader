shader_type canvas_item;
render_mode unshaded; // the edge shines against the night tint
global uniform float g_sun; // 0..1 sun height (DayNight)
// The edge of the world: the Void has eaten the land. One quad that follows the camera paints
//  - on the land side (up to a few tiles in): scorched, dithered ground, glowing cracks that pulse
//    towards the edge, flickering void blooms, a bright dashed lip where the ground crumbles away
//  - in the void: swirling violet haze that glows brightest at the edge, ribbons of light, stars,
//    and motes rising out of the abyss.
// Everything is computed per pixel on the 1:1 world grid. The coast comes from a baked signed
// distance texture (1 px per tile, 128 = coast, 8 steps per tile, >128 land).

uniform sampler2D sdf : filter_linear, repeat_disable;
uniform vec2 origin = vec2(0.0); // world pixel of the quad's top-left corner
uniform vec2 view_size = vec2(640.0, 360.0); // quad size in pixels
uniform float time = 0.0;
uniform float night = 0.0; // 0 day .. 1 night
uniform float world_tiles = 1100.0;

const float TILE = 16.0;
const float RIM_MAX = 10.0; // tiles: nothing is drawn on land beyond this

const vec3 VOID0 = vec3(0.016, 0.008, 0.031);
const vec3 VOID1 = vec3(0.027, 0.016, 0.051);
const vec3 VOID2 = vec3(0.055, 0.035, 0.098);
const vec3 VOID3 = vec3(0.102, 0.063, 0.188);
const vec3 VOID4 = vec3(0.133, 0.090, 0.251);
const vec3 VIO5 = vec3(0.353, 0.212, 0.722);
const vec3 VIO6 = vec3(0.541, 0.302, 1.0);
const vec3 VIO7 = vec3(0.690, 0.420, 1.0);
const vec3 VIO8 = vec3(0.925, 0.824, 1.0);
const vec3 MAGENTA = vec3(1.0, 0.31, 0.85);
const vec3 TEAL = vec3(0.235, 0.753, 0.776);
const vec3 TEAL_L = vec3(0.471, 0.957, 0.902);
const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 hash22(vec2 p) {
	float a = hash21(p);
	return vec2(a, hash21(p + a + 19.19));
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

// F1, F2 and the id of the nearest feature point of a cellular pattern
vec3 worley(vec2 p) {
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash22(ip + g);
			float d = length(g + o - fp);
			if (d < f1) {
				f2 = f1;
				f1 = d;
				id = hash21(ip + g + 3.1);
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return vec3(f1, f2, id);
}

float sample_sdf(vec2 world_px) {
	vec2 suv = world_px / TILE / world_tiles;
	if (suv.x < 0.0 || suv.y < 0.0 || suv.x > 1.0 || suv.y > 1.0) {
		return -16.0;
	}
	return (textureLod(sdf, suv, 0.0).r * 255.0 - 128.0) / 8.0;
}

void fragment() {
	vec2 px = floor(UV * view_size);
	vec2 wp = origin + px;
	float d = sample_sdf(wp + 0.5);
	if (d > RIM_MAX) {
		COLOR = vec4(0.0);
	} else {
		float dark = smoothstep(0.15, 0.85, night); // 0 = peaceful day, 1 = eerie night
		float calm = 1.0 - dark;
		float ph = fract(time * 0.16);
		float beat = exp(-ph * 8.0) + 0.55 * exp(-abs(ph - 0.24) * 16.0); // lub-dub of the abyss
		float glow = mix(0.62, 1.15, dark) * (1.0 + 0.3 * beat * dark + 0.04 * sin(time * 0.5) * calm);
		float macro = fbm(wp * 0.012 + 3.7); // where the void bites deeper (large scale)
		float fine = vnoise(wp * vec2(0.22, 0.26) + 11.3); // raggedness at pixel scale
		float chew = (0.08 + 0.42 * macro) * (0.35 + 0.65 * fine) * mix(0.6, 1.0, dark); // tiles of land the void has eaten
		float e = d - chew;
		vec4 col = vec4(0.0);

		if (e >= 0.0) {
			// ---------- the land side
			float width = mix(1.8, 5.2, fbm(wp * 0.007 + 90.0)) * mix(0.8, 1.3, dark); // how far the scorching reaches (further at night)
			float r = e;
			float t = 1.0 - clamp(r / width, 0.0, 1.0);
			// scorched, dithered ground
			float level = floor(t * t * 3.4 + bayer(wp));
			if (level >= 1.0) {
				float a = (level >= 3.0 ? 0.88 : (level >= 2.0 ? 0.62 : 0.34)) * mix(0.72, 1.0, dark);
				col = vec4(level >= 3.0 ? VOID1 : VOID2, a);
			}
			// crumbling bits: grass pixels missing near the edge
			if (r < width * 0.5 && hash21(wp + 5.0) < t * 0.28) {
				col = vec4(VOID2, 0.95);
			}
			// cracks: cell edges of a warped cellular pattern, pulsing towards the edge
			// the cracks only reach r < width * 1.725 (vein_zone <= 1, dark * crawl <= 1), so the cellular pattern is only worked out near the edge
			if (r < width * 1.75) {
			float vein_zone = smoothstep(0.35, 0.65, fbm(wp * 0.015 + 40.0)); // variable: some stretches have none
			vec2 wq = wp / 11.0 + vec2(vnoise(wp * 0.07), vnoise(wp * 0.07 + 8.0)) * 0.9;
			vec3 w = worley(wq);
			float edge_px = (w.y - w.x) * 11.0;
			float crawl = 0.5 + 0.5 * sin(time * 0.45 + w.z * 6.28); // at night the cracks creep out and pull back
			if (edge_px < 1.15 && r < width * (0.45 + 0.7 * vein_zone) * (1.0 + 0.5 * dark * crawl) && vein_zone > 0.05) {
				float pulse = 0.5 + 0.5 * sin(r * 3.2 - time * 2.4 + w.z * 6.28);
				float near = 1.0 - clamp(r / (width * 1.1), 0.0, 1.0);
				vec3 crack = mix(VIO5, VIO7, near);
				crack = mix(crack, VIO8, pulse * pulse * near);
				crack = mix(crack, vec3(0.78, 0.74, 0.96), calm * 0.3); // by day: pale lavender
				crack = mix(crack, MAGENTA, dark * pulse * pulse * near * 0.75); // by night: hot flashes
				col = vec4(mix(VOID3, crack * glow, 0.35 + 0.65 * pulse), 1.0);
			}
			}
			// void blooms: small flickering crosses of light in the scorched ground
			vec2 bc = floor(wp / 13.0);
			vec2 bh = hash22(bc + 7.0);
			if (bh.x > 0.9 && r < width * 0.8) {
				vec2 bp = bc * 13.0 + 3.0 + bh * 7.0;
				vec2 k = abs(wp + 0.5 - bp);
				float flick = 0.5 + 0.5 * sin(time * (1.5 + bh.y * 2.0) + bh.x * 40.0);
				float arm = flick > mix(-1.0, 0.55, dark) ? 2.0 : 1.0; // steady by day, flickering at night
				if ((k.x < 0.6 && k.y < arm) || (k.y < 0.6 && k.x < arm)) {
					col = vec4(k.x < 0.6 && k.y < 0.6 ? VIO8 : VIO7, 1.0);
				}
			}
			// Voidbloom: a rare large flower of light that has grown in the scorched ground
			vec2 fc = floor(wp / 44.0);
			vec2 fh = hash22(fc + 101.0);
			if (fh.x > 0.84 && r > 0.5 && r < width * 0.9) {
				vec2 fp = fc * 44.0 + 8.0 + fh * 28.0;
				if (sample_sdf(fp) > 1.2) {
					vec2 k = wp + 0.5 - fp;
					float pulse = 0.5 + 0.5 * sin(time * 1.4 + fh.y * 30.0);
					float ak = abs(k.x);
					float bk = abs(k.y);
					float arm = 3.0 + pulse * 1.6;
					float rad = length(k);
					bool petal = (bk < 0.7 && ak < arm) || (ak < 0.7 && bk < arm) || (abs(ak - bk) < 0.7 && ak < 2.7 && ak > 0.5);
					if (rad < 1.3) {
						col = vec4(VIO8, 1.0);
					} else if (petal) {
						col = vec4(mix(VIO6, VIO7, pulse) * glow, 1.0);
					} else if (rad < 8.0 && bayer(wp) < (1.0 - rad / 8.0) * 0.55 * (0.55 + 0.45 * pulse)) {
						col = vec4(VIO5 * glow, 0.8);
					}
				}
			}
			// the lip: where the ground ends, a bright dashed line
			if (r < 0.1 + 0.05 * fine && vnoise(wp * 0.4 + time * 0.2) > 0.3) {
				col = vec4(mix(VIO6, VIO8, vnoise(wp * 0.9)) * glow, 1.0);
				col.rgb = mix(col.rgb, vec3(1.0, 0.86, 0.45), g_sun * step(0.93, vnoise(wp * 0.9 + floor(time * 0.6) * 3.1)) * 0.85); // gold glints at midday
			} else if (r < 0.26 && col.a < 0.9) {
				col = vec4(VOID1, 0.9); // the darkened edge under the lip
			}
		} else {
			// ---------- the void
			float h = max(-d, 0.0); // tiles into the void
			float haze = exp(-h * 0.5); // glow from the edge
			vec2 pp = wp * 0.55 + vec2(time * 0.9, time * 0.4);
			vec2 q = pp * 0.03;
			vec2 warp = vec2(fbm(q + vec2(0.0, time * 0.012)), fbm(q + vec2(5.2, 1.3) - vec2(time * 0.01, 0.0)));
			float n = fbm(q + warp * 1.7);
			float vapor = vnoise(vec2(wp.x * 0.07, wp.y * 0.022 + time * 0.3)); // columns of haze rising
			float level = n * (0.35 + 0.7 * haze) + haze * (0.36 + 0.4 * vapor);
			float band = floor(level * 4.6 + bayer(wp));
			vec3 base = VOID0;
			if (band >= 5.0) {
				base = VIO5;
			} else if (band >= 4.0) {
				base = VOID4;
			} else if (band >= 3.0) {
				base = VOID3;
			} else if (band >= 2.0) {
				base = VOID2;
			} else if (band >= 1.0) {
				base = VOID1;
			}
			base = mix(base, base + vec3(0.03, 0.04, 0.11), calm * (0.35 + 0.65 * haze)); // by day the dark lifts to a soft indigo
			base *= mix(1.0, 0.78, dark); // by night it sinks deeper
			col = vec4(base, 1.0);

			// ribbons of light: thin contour lines of a drifting, warped noise field
			float ribbon = fbm(q * 0.9 + warp * 2.4 + vec2(time * 0.004, 0.0));
			float line = abs(ribbon - 0.5);
			if (line < 0.011 + 0.012 * haze) {
				float flow = 0.5 + 0.5 * sin(wp.x * 0.07 - wp.y * 0.05 - time * 1.1 + ribbon * 40.0);
				vec3 rc = mix(VOID3, mix(VIO5, VIO7, haze), flow * flow);
				rc = mix(rc, MAGENTA * 0.8, dark * 0.3 * flow * flow);
				col = vec4(rc * mix(0.6, 1.0, haze) * glow, 1.0);
			}

			// stars (parallax 0.35)
			vec2 sp = wp * 0.35 + vec2(time * 0.3, 0.0);
			vec2 sc = floor(sp / 6.0);
			float sh = hash21(sc + 61.0);
			if (sh > mix(0.972, 0.955, dark)) {
				vec2 spos = floor(hash22(sc + 13.0) * 6.0);
				if (floor(sp - sc * 6.0) == spos) {
					float tw = 0.5 + 0.5 * sin(time * (1.0 + sh * 3.0) + sh * 90.0);
					vec3 sc_col = sh > 0.99 ? TEAL_L : mix(VIO7, VIO8, tw);
					col = vec4(sc_col * (0.55 + 0.45 * tw), 1.0);
				}
			}

			// lurkers: pairs of eyes that open in the deep at night
			if (dark > 0.3 && h > 3.0) {
				const float EC = 132.0;
				vec2 ec = floor(wp / EC);
				vec2 eh = hash22(ec + 211.0);
				if (eh.x < 0.55 * smoothstep(0.3, 0.8, dark)) {
					vec2 ep = floor(ec * EC + 14.0 + eh * (EC - 28.0)) + vec2(0.0, floor(sin(time * 0.15 + eh.y * 6.28) * 2.0));
					float cyc = fract(time * 0.035 + eh.y * 5.0);
					float open_amt = smoothstep(0.08, 0.14, cyc) * (1.0 - smoothstep(0.62, 0.70, cyc));
					bool blink = fract(time * 0.31 + eh.x * 9.0) > 0.93;
					if (open_amt > 0.5 && !blink && sample_sdf(ep) < -3.0) {
						vec2 k = wp - ep;
						bool eye = (k.y == -1.0 && (k.x == -4.0 || k.x == 4.0)) || (k.y == 0.0 && (k.x == -3.0 || k.x == -2.0 || k.x == 2.0 || k.x == 3.0));
						if (eye) {
							col = vec4(mix(MAGENTA, vec3(1.0, 0.82, 0.92), 0.4 * beat) * glow, 1.0);
						} else if (abs(k.y) < 6.0 && abs(k.x) < 11.0 && bayer(wp) < 0.32 * (1.0 - length(k * vec2(0.09, 0.17)))) {
							col = vec4(0.30, 0.04, 0.24, 1.0);
						}
					}
				}
			}

			// the edge itself: a hot glowing rim just beyond the lip
			if (h < 0.5) {
				float k = 1.0 - h / 0.5;
				if (bayer(wp) < k * 0.6 && fine > 0.35) {
					col = vec4(mix(VIO5, VIO6, k) * glow, 1.0);
				}
			}
		}

		// ---------- motes rising out of the abyss (void and the scorched rim)
		float nearness = 1.0 - clamp((d < 0.0 ? -d : d * 1.6) / 8.0, 0.0, 1.0);
		if (nearness > 0.0) {
			vec2 cell = floor(wp / vec2(18.0, 30.0));
			float mh = hash21(cell + 31.0);
			if (mh > mix(0.88, 0.78, dark)) {
				float life = fract(time * (0.08 + mh * 0.07) + mh * 7.0);
				vec2 mp = cell * vec2(18.0, 30.0) + vec2(2.0 + hash21(cell + 2.0) * 14.0 + sin(life * 6.28 + mh * 20.0) * 2.0, 30.0 - life * 30.0);
				if ((floor(mp) == wp || floor(mp) + vec2(0.0, 1.0) == wp) && life > 0.05 && life < 0.95) {
					float fade = sin(life * 3.14159);
					vec3 mc = mix(VIO7, mh > 0.93 ? TEAL_L : VIO8, 0.5 + 0.5 * fade);
					mc = mix(mc, vec3(1.0, 0.92, 0.78), calm * 0.45); // pale gold by day, like pollen
					col = vec4(mc * glow, fade * nearness > 0.25 ? 1.0 : 0.0);
				}
			}
		}
		COLOR = col;
	}
}
