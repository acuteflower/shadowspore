shader_type canvas_item;
render_mode unshaded;
#include "res://assets/shaders/daylight.gdshaderinc"
#include "res://assets/shaders/night_noise.gdshaderinc"
// Falling rain, rain curtains and mist (docs/wetter_konzept.md section 6.1). No particles: three depth layers of one-pixel streaks (a far, a middle and a near
// sheet, each scrolling a little differently with the camera), laid out per pixel column. The streaks are SHEARED by the wind (`slant`, from WorldWind
// and its gusts), so rain, grass and crowns lean the same way; in a storm they fly almost flat. How much falls at a pixel comes from the weather's own cloud
// field (rain_local): a rain cell with a ragged edge passes over, under the dense crowns (g_day_cover) only a few drops get through, and the drops that
// do come down from the crown rims are fatter. On top, diagonal veils of rain sweep along the wind in gusts, and mist banks (fog) drift in dithered pixels.
// Whole art pixels everywhere; the ground splashes live in ground_tone / river_water (they must lie UNDER trees and people).

uniform vec2 world_origin = vec2(0.0);
uniform vec2 view_px = vec2(640.0, 360.0);
uniform float slant = 0.15; // pixels a drop drifts sideways per pixel it falls (wind)
uniform float fall = 1.0; // fall speed factor
uniform float gust : hint_range(0.0, 1.0) = 0.0;
uniform float storm : hint_range(0.0, 1.0) = 0.0;
uniform float fog : hint_range(0.0, 1.0) = 0.0;
uniform float visibility : hint_range(0.0, 1.0) = 1.0;
uniform float clock = 0.0;
uniform vec3 ambient : source_color = vec3(1.0);
uniform vec2 wind_dir = vec2(1.0, 0.0);
uniform vec3 tint : source_color = vec3(1.0); // the Hexenwald's rain is a little green

// One sheet of streaks. Returns 0 (nothing) or the brightness step 1..3 (tail, body, head) of the streak at this pixel.
int streak(vec2 s, float parallax, float period, float len, float speed, float dens, float seed, float rate, float shear) {
	vec2 p = s + floor(world_origin * parallax);
	float u = p.x - (p.y - view_px.y * 0.5) * shear;
	float col = floor(u);
	float h1 = n_hash(vec2(col, seed));
	if (h1 > dens * rate) { return 0; }
	float h2 = n_hash(vec2(col, seed + 17.0));
	float sp = speed * (0.85 + 0.3 * h2) * fall;
	float ph = fract((p.y - clock * sp) / period + h2 * 7.0);
	float l = len / period;
	if (ph >= l) { return 0; }
	float k = ph / l; // 0 tail .. 1 head (the head leads: it is lower)
	return k > 0.78 ? 3 : (k > 0.34 ? 2 : 1);
}

void fragment() {
	vec2 s = floor(UV * view_px + 0.001);
	vec2 w = world_origin + s;
	float rate = rain_local(w);
	float canopy = day_cover(w);
	float dry = 1.0 - 0.82 * canopy;
	float r = rate * dry;
	vec4 out_color = vec4(0.0);
	if (r > 0.01) {
		int fa = streak(s, 0.80, 36.0, 5.0, 150.0, 0.20, 3.0, r, slant * 0.85);
		int mi = streak(s, 1.00, 48.0, 8.0, 235.0, 0.12, 11.0, r, slant);
		int ne = streak(s, 1.25, 72.0, 13.0, 360.0, 0.06, 29.0, r, slant * 1.12);
		float a = 0.0;
		vec3 col = vec3(0.0);
		if (fa > 0) { col = vec3(0.56, 0.66, 0.82); a = 0.10 + 0.035 * float(fa); }
		if (mi > 0) { col = vec3(0.70, 0.80, 0.93); a = 0.16 + 0.05 * float(mi); }
		if (ne > 0) { col = vec3(0.90, 0.95, 1.0); a = 0.22 + 0.07 * float(ne); }
		if (a > 0.0) { out_color = vec4(col * tint * ambient, a * (1.0 + 0.7 * storm) * visibility); }
	}
	// fatter drops fall from the crown rims onto the ground under the trees
	if (canopy > 0.4 && rate > 0.05) {
		vec2 cell_size = vec2(22.0, 18.0);
		vec2 cell = floor(w / cell_size);
		float hh = n_hash(cell + 91.0);
		if (hh < 0.30 * rate) {
			float per = 0.9 + hh * 3.0;
			float ph = fract(clock / per + hh * 13.0);
			vec2 local = w - cell * cell_size;
			float x = floor(n_hash(cell + 5.0) * 20.0) + 1.0;
			float y = 2.0 + ph / 0.34 * 14.0;
			if (ph < 0.34 && floor(local.x) == x && floor(local.y) >= floor(y) && floor(local.y) <= floor(y) + 1.0) {
				out_color = vec4(vec3(0.86, 0.93, 1.0) * ambient, 0.5 * visibility);
			}
		}
	}
	// veils of rain sweeping along the wind
	if (rate > 0.12) {
		vec2 wd = normalize(wind_dir);
		float along = dot(w, wd);
		float perp = dot(w, vec2(-wd.y, wd.x));
		float band = n_vnoise(vec2(perp / 64.0, (along - clock * (46.0 + 90.0 * storm)) / 250.0));
		float veil = smoothstep(0.62, 0.86, band) * rate * (0.2 + 0.5 * max(gust, storm)) * dry;
		if (veil > n_bayer(s) * 0.92 + 0.04 && out_color.a < 0.3) {
			out_color = vec4(vec3(0.66, 0.73, 0.84) * tint * ambient, (0.07 + 0.05 * storm) * visibility);
		}
	}
	// mist banks (the weather's fog, dawn mist after rain)
	if (fog > 0.02) {
		float m = n_fbm(w / 120.0 + vec2(clock * 0.012, clock * 0.005) + 21.0);
		float bank = smoothstep(0.36, 0.76, m) * fog;
		if (bank > n_bayer(s) * 0.95 + 0.03 && out_color.a < 0.25) {
			out_color = vec4(vec3(0.82, 0.86, 0.90) * ambient, (0.08 + 0.07 * fog) * visibility);
		}
	}
	COLOR = out_color;
}
