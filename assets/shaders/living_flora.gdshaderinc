// LivingFlora 2.0 Shared Displacement (`living_flora.gdshaderinc`):
// - Whole-art-pixel parabolic WorldWind sway with per-stem column phase (`cell_w`)
// - Radial 2-sided physical parting around walking actors (`actors[8]: vec4(wx, wy, radius, strength)`)
//   so multi-stem herbs & shrubs part left & right around Ellie's legs instead of skewing as one stiff card!
// - Radial sword-slash / shadow-step gust shockwave (`slash_wave: vec4(wx, wy, radius, strength)`)
// - Subtle rain-weight head droop (`rain_droop`) & occasional raindrop leaf-tap twitch!

global uniform vec2 g_wind_dir;
global uniform float g_wind_gust;
global uniform float g_wind_clock;
global uniform float g_night;

uniform vec2 frame_size = vec2(32.0, 36.0);
uniform float pivot_row = 31.0;
uniform float amount = 1.8;
uniform float flutter = 0.32;
uniform float cell_w = 5.0;
uniform vec2 origin = vec2(0.0);
uniform float phase_seed = 0.0;
uniform bool use_model_origin = true;

uniform vec4 actors[8];
uniform vec4 slash_wave = vec4(0.0);
uniform float flora_rain = 0.0;

varying vec4 modulate_in;
varying vec2 v_world_origin;
varying float v_flip_sign;

vec2 living_flora_uv(vec2 uv, vec2 size) {
	vec2 px = uv * size;
	float col_idx = floor(px.x / frame_size.x);
	float row_idx = floor(px.y / frame_size.y);
	float local_x = px.x - col_idx * frame_size.x;
	float local_y = px.y - row_idx * frame_size.y;

	float row = floor(local_y);
	float h = max(pivot_row - row, 0.0) / 16.0;
	if (h <= 0.001) {
		return uv;
	}

	vec2 w_origin = use_model_origin ? v_world_origin : origin;
	float pulse = 0.5 + 0.5 * sin(dot(w_origin, g_wind_dir) * 0.014 - g_wind_clock * 1.6);
	float gust_s = (g_wind_gust <= 1.1) ? g_wind_gust : (1.1 + 0.9 * tanh((g_wind_gust - 1.1) * 0.35));
	float wind = g_wind_dir.x * (0.12 + gust_s * (0.35 + 0.65 * pulse));

	float phase = use_model_origin ? (fract((w_origin.x * 0.37 + w_origin.y * 0.91) * 0.15915494) * 6.2831853) : phase_seed;
	float cell = floor(px.x / max(cell_w, 2.0));
	float tick = floor(g_wind_clock * 12.0) / 12.0;
	float ripple = sin(tick * 2.4 + row * 0.11 + cell * 1.9 + phase) * flutter;
	float bend_curve = pow(h, 1.38);
	float shift_world_x = (wind * amount + ripple) * bend_curve;

	// Radial physical parting around walking players/creatures (`actors[8]`):
	// Each vertical stem strip checks its own world X relative to the actor -> left stems bend left, right stems bend right!
	float stem_world_x = w_origin.x + (local_x - frame_size.x * 0.5) * v_flip_sign;
	for (int i = 0; i < 8; i++) {
		vec4 a = actors[i];
		if (a.z <= 0.1 || a.w <= 0.001) {
			continue;
		}
		vec2 d_root = w_origin - a.xy;
		// Elliptical 3/4 distance check around actor feet
		float dist = length(vec2(d_root.x, d_root.y * 1.45));
		if (dist < a.z) {
			float w_act = (1.0 - dist / a.z);
			w_act = w_act * w_act * a.w;
			float dx = stem_world_x - a.x;
			float dir_x = (abs(dx) > 0.6) ? sign(dx) : ((fract(phase * 0.31) > 0.5) ? 1.0 : -1.0);
			shift_world_x += dir_x * w_act * (2.6 + amount * 0.85) * min(h * 1.25, 1.8);
		}
	}

	// Sword-slash / Shadow-Step gust ring!
	if (slash_wave.z > 0.5 && slash_wave.w > 0.01) {
		vec2 ds = w_origin - slash_wave.xy;
		float sd = length(ds);
		if (sd < slash_wave.z) {
			float sw_k = (1.0 - sd / slash_wave.z) * slash_wave.w;
			float s_dir = (abs(ds.x) > 0.5) ? sign(ds.x) : 1.0;
			shift_world_x += s_dir * sw_k * 3.8 * bend_curve;
		}
	}

	// Raindrop tap twitch & gentle rain-weight droop on upper flower heads!
	float droop_y = 0.0;
	if (flora_rain > 0.08) {
		float drop_hash = fract(sin(cell * 91.7 + floor(g_wind_clock * 5.0) * 17.3 + phase) * 43758.5453);
		if (drop_hash > 0.91 && h > 0.35) {
			droop_y = 1.0;
		} else if (flora_rain > 0.42 && h > 0.65 && abs(local_x - frame_size.x * 0.5) > 2.5) {
			droop_y = 1.0;
		}
	}

	// Convert world X shift into texture UV X shift (respecting horizontal sprite flip!)
	float shift_tex_x = floor(shift_world_x * v_flip_sign + 0.5);
	float x_clamped = clamp(floor(px.x) - shift_tex_x, col_idx * frame_size.x, (col_idx + 1.0) * frame_size.x - 1.0);
	float y_clamped = clamp(floor(px.y) - droop_y, row_idx * frame_size.y, (row_idx + 1.0) * frame_size.y - 1.0);
	return vec2((x_clamped + 0.5) / size.x, (y_clamped + 0.5) / size.y);
}
