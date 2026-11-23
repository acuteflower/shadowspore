// Shared 3-frequency pixel-quantized canopy cluster aerodynamics for LivingTree 2.0:
// 1. Primary bough-lever sway driven by WorldWind at the cluster's true world-space branch anchor
// 2. Internal 11x9 px sub-cluster cellular breathing (breaks monolithic block motion)
// 3. 12 Hz stepped outer leaf-fan rustle at the cluster periphery
// All UV shifts snap to integer art texels -> zero subpixel blur, 100% synced across lit, glow & SunShadows!

global uniform vec2 g_wind_dir;
global uniform float g_wind_gust;
global uniform float g_wind_clock;

uniform vec2 frame_size = vec2(196.0, 200.0);
uniform vec2 anchor_px = vec2(98.0, 108.0);
uniform vec2 world_anchor = vec2(0.0, 0.0);
uniform float stiffness = 1.0;
uniform float flutter = 0.42;
uniform float phase_seed = 0.0;
uniform float wind_exposure = 1.0;
uniform float rain_droop = 0.0;

vec2 canopy_wind_uv(vec2 uv, vec2 tex_size, out float out_gust, out float out_dist) {
	vec2 px = uv * tex_size;
	float col = floor(px.x / max(frame_size.x, 1.0));
	vec2 local_px = vec2(px.x - col * frame_size.x, mod(px.y, max(frame_size.y, 1.0)));

	vec2 rel = local_px - anchor_px;
	float dist = length(rel * vec2(0.85, 1.12)) / 34.0;
	out_dist = dist;
	float lever = clamp(pow(clamp(dist, 0.0, 2.2), 1.32), 0.0, 2.5) / max(stiffness, 0.35);

	vec2 wdir = length(g_wind_dir) > 0.01 ? normalize(g_wind_dir) : vec2(1.0, 0.0);
	float g_soft = g_wind_gust <= 1.2 ? g_wind_gust : 1.2 + 1.1 * tanh((g_wind_gust - 1.2) * 0.35);
	float pulse = 0.5 + 0.5 * sin(dot(world_anchor, wdir) * 0.019 - g_wind_clock * 1.72 + phase_seed * 0.35);
	float gust_force = (0.14 + g_soft * (0.32 + 0.68 * pulse)) * wind_exposure;
	out_gust = gust_force;

	float primary_x = wdir.x * gust_force * 2.15 * lever;
	float primary_y = (wdir.y * 0.30 * gust_force + abs(primary_x) * 0.13) * lever + rain_droop * 1.65 * clamp(dist, 0.0, 1.35);

	// Sub-cluster cellular wave so sections within one bough cloud breathe organically
	vec2 sub_cell = floor(local_px / vec2(11.0, 9.0));
	float sub_h = fract(sin(dot(sub_cell, vec2(12.9898, 78.233)) + phase_seed) * 43758.5453);
	float sub_wave = sin(g_wind_clock * 2.15 + sub_h * 6.2831853) * (0.26 + 0.42 * clamp(g_soft, 0.0, 1.8));

	// Crisp 12 Hz pixel-stepped leaf-fan rustle on outer foliage tips
	float tick12 = floor(g_wind_clock * 12.0) / 12.0;
	float leaf_cell = floor((local_px.x + local_px.y * 0.5) / 4.0);
	float rim_w = smoothstep(0.28, 1.05, dist);
	float leaf_rustle = sin(tick12 * 6.1 + leaf_cell * 2.37 + phase_seed * 3.1) * flutter * clamp(0.32 + g_soft * 0.78, 0.0, 1.85) * rim_w;
	float leaf_bob = sin(tick12 * 4.3 + sub_h * 6.2831853) * flutter * 0.32 * rim_w;

	float dx = floor(primary_x + sub_wave * lever * 0.62 + leaf_rustle + 0.5);
	float dy = floor(primary_y + leaf_bob + 0.5);

	float x_min = col * frame_size.x + 1.0;
	float x_max = (col + 1.0) * frame_size.x - 2.0;
	float sx = clamp(floor(px.x) - dx, x_min, x_max);
	float sy = clamp(floor(px.y) - dy, 1.0, frame_size.y - 2.0);
	return vec2((sx + 0.5) / tex_size.x, (sy + 0.5) / tex_size.y);
}
