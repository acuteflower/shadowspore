shader_type canvas_item;
render_mode unshaded;
#include "res://assets/shaders/daylight.gdshaderinc"
#include "res://assets/shaders/night_noise.gdshaderinc"
// Falling rain, rain curtains and mist (docs/wetter_konzept.md section 6.1). No particles: three depth layers of one-pixel streaks (a far, a middle and a near
// sheet, each scrolling a little differently with the camera), laid out per pixel column. The streaks are SHEARED by the wind (`slant`, from WorldWind
// and its gusts), so rain, grass and crowns lean the same way; in a storm they fly almost flat. How much falls at a pixel comes from the weather's own cloud
// field (rain_local): a rain cell with a ragged edge passes over, under the dense crowns (g_day_cover) only a few drops get through, and the drops that
// do come down from the crown rims are fatter. On top, smooth diagonal veils of rain sweep along the wind in gusts, and smooth mist banks (fog) drift across the screen.
// Raindrops stay whole art pixels; veils and mist are smooth at screen resolution (like night_fog.gdshader) so they never show Bayer dots at 2x+; ground splashes live in ground_tone / river_water.

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
global uniform sampler2D g_arid : filter_linear, repeat_disable;
global uniform vec4 g_gloom_rect;

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

float desert_dry_at(vec2 pos) {
	float arid = 0.0;
	if (g_gloom_rect.z > 0.0) {
		vec2 auv = (pos - g_gloom_rect.xy) / g_gloom_rect.zw;
		if (all(greaterThanEqual(auv, vec2(0.0))) && all(lessThanEqual(auv, vec2(1.0)))) {
			arid = texture(g_arid, auv).r;
		}
	}
	return 1.0 - smoothstep(0.18, 0.45, arid);
}

vec4 over_blend(vec4 fg, vec4 bg) {
	float a = fg.a + bg.a * (1.0 - fg.a);
	if (a <= 0.0001) { return vec4(0.0); }
	return vec4((fg.rgb * fg.a + bg.rgb * bg.a * (1.0 - fg.a)) / a, a);
}

void fragment() {
	vec2 s = floor(UV * view_px + 0.001);
	vec2 w = world_origin + s;
	vec2 w_smooth = world_origin + UV * view_px;
	float desert_dry = desert_dry_at(w);
	float rate = rain_local(w) * desert_dry;
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
	// smooth rain veils and mist banks (continuous at screen resolution, with a hair of noise against 8-bit banding)
	float desert_dry_s = desert_dry_at(w_smooth);
	float fog_here = fog * desert_dry_s;
	float rate_s = rain_local(w_smooth) * desert_dry_s;
	vec4 atm = vec4(0.0);
	if (fog_here > 0.02) {
		float m = n_fbm(w_smooth / 120.0 + vec2(clock * 0.012, clock * 0.005) + 21.0);
		float bank = smoothstep(0.36, 0.76, m) * fog_here;
		float mist_a = bank * (0.09 + 0.08 * fog_here) * visibility;
		if (mist_a > 0.001) {
			atm = vec4(vec3(0.82, 0.86, 0.90) * ambient, mist_a);
		}
	}
	if (rate_s > 0.12) {
		vec2 wd = normalize(wind_dir);
		float along = dot(w_smooth, wd);
		float perp = dot(w_smooth, vec2(-wd.y, wd.x));
		float band = n_vnoise(vec2(perp / 64.0, (along - clock * (46.0 + 90.0 * storm)) / 250.0));
		float dry_s = 1.0 - 0.82 * day_cover(w_smooth);
		float veil = smoothstep(0.62, 0.86, band) * rate_s * (0.2 + 0.5 * max(gust, storm)) * dry_s;
		float veil_a = veil * (0.08 + 0.06 * storm) * visibility;
		if (veil_a > 0.001) {
			atm = over_blend(vec4(vec3(0.66, 0.73, 0.84) * tint * ambient, veil_a), atm);
		}
	}
	if (atm.a > 0.001) {
		float noise = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
		atm.a = clamp(atm.a + noise / 255.0, 0.0, 1.0);
		out_color = over_blend(out_color, atm);
	}
	COLOR = out_color;
}
