// Shared world-space noise, toroidal ring-buffer deformation sampling, environment coupling
// (puddles, rain, wear, biomes) and parabolic vertex displacement for LivingGrass (lit + night glow).
// Included AFTER `daylight.gdshaderinc` so all global daylight/weather uniforms are already declared.

global uniform float g_wind_clock;
global uniform vec2 g_wind_dir;
global uniform float g_wind_gust;
global uniform float g_dew;
global uniform float g_night;
global uniform sampler2D g_town_wear : filter_linear, repeat_disable;
global uniform vec4 g_town_wear_rect;
global uniform sampler2D g_gloom : filter_linear, repeat_disable;
global uniform sampler2D g_arid : filter_linear, repeat_disable;
global uniform vec4 g_gloom_rect;

uniform vec2 field_origin = vec2(-256.0, -256.0);
uniform float field_size = 512.0;
uniform sampler2D deform_tex : filter_linear, repeat_enable;
uniform vec4 actors[4]; // (world_x, world_y, shadow_radius, weight)

// Integer hash synced with ground_tone.gdshader so macro light & puddle shapes match pixel-for-pixel.
float lg_hash(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p)) + ivec2(65536));
	uint h = q.x * 1597334677u ^ q.y * 3812015801u;
	h = (h ^ (h >> 16u)) * 2246822519u;
	h = (h ^ (h >> 13u)) * 3266489917u;
	h ^= h >> 16u;
	return float(h >> 8u) / 16777216.0;
}

float lg_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(lg_hash(i), lg_hash(i + vec2(1.0, 0.0)), f.x),
		mix(lg_hash(i + vec2(0.0, 1.0)), lg_hash(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

float lg_fbm(vec2 p) {
	return lg_vnoise(p) * 0.58 + lg_vnoise(p * 2.07 + 7.3) * 0.28 + lg_vnoise(p * 4.1 - 3.1) * 0.14;
}

// Samples the camera-centered toroidal ring-buffer (512x512 px window) cleanly with zero wrap-around ghosting.
vec4 lg_sample_deform(vec2 world_pos) {
	vec2 rel = world_pos - field_origin;
	float edge = min(min(rel.x, field_size - rel.x), min(rel.y, field_size - rel.y));
	if (edge <= 2.0) {
		return vec4(0.5, 0.5, 0.0, 0.5);
	}
	float fade = smoothstep(2.0, 14.0, edge);
	vec4 raw = texture(deform_tex, fract(world_pos / field_size));
	return mix(vec4(0.5, 0.5, 0.0, 0.5), raw, fade);
}

// Exact twin of ground_tone.gdshader puddle heightfield so living grass never stands dry inside mirror puddles.
float lg_puddle_mask(vec2 px, float arid) {
	float pud_here = g_puddle * (1.0 - smoothstep(0.18, 0.48, arid));
	if (pud_here <= 0.02) {
		return 0.0;
	}
	float hollow = lg_vnoise(px / 150.0 + vec2(51.0, 9.0));
	if (hollow < 0.2) {
		return 0.0;
	}
	float warp = lg_vnoise(px / 8.0 + vec2(7.0, 61.0)) - 0.5;
	float pn = lg_fbm(px / 27.0 + vec2(133.0, 41.0) + warp * 0.55) + 0.55 * (hollow - 0.5);
	float pthr = 0.815 - 0.12 * pud_here;
	return smoothstep(pthr - 0.015, pthr + 0.035, pn);
}

void lg_sample_env(vec2 foot, out float gloom, out float arid, out float wear) {
	gloom = 0.0;
	arid = 0.0;
	wear = 0.0;
	if (g_gloom_rect.z > 0.0) {
		vec2 buv = (foot - g_gloom_rect.xy) / g_gloom_rect.zw;
		if (buv.x >= 0.0 && buv.y >= 0.0 && buv.x <= 1.0 && buv.y <= 1.0) {
			gloom = texture(g_gloom, buv).r;
			arid = texture(g_arid, buv).r;
		}
	}
	if (g_town_wear_rect.z > 0.0) {
		vec2 wuv = (foot - g_town_wear_rect.xy) / g_town_wear_rect.zw;
		if (wuv.x >= 0.0 && wuv.y >= 0.0 && wuv.x <= 1.0 && wuv.y <= 1.0) {
			wear = texture(g_town_wear, wuv).r;
		}
	}
}

// Shared parabolic vertex displacement for both lit grass and unlit night-glow layers (100% pixel-synced).
void lg_displace_vertex(
	inout vec2 vert,
	vec2 uv,
	vec2 foot,
	vec4 custom,
	float gloom,
	float arid,
	float wear,
	out float out_crush,
	out float out_bend_len,
	out float out_sheen,
	out float out_wet,
	out float out_keep
) {
	vec4 def = lg_sample_deform(foot);
	vec2 bend = (def.rg - vec2(0.5)) * 2.0;
	float crush = clamp(def.b, 0.0, 1.0);
	float wobble = (def.a - 0.5) * 2.0;
	out_crush = crush;
	out_bend_len = clamp(length(bend), 0.0, 1.4);

	float h = clamp(uv.y, 0.0, 1.0);
	float phase = custom.g * 6.2831853;
	float flex = custom.b;
	float hscale = custom.a;

	// Puddle / trodden path / deep desert graceful thinning (hash-frayed organic edges)
	float puddle = lg_puddle_mask(floor(foot), arid);
	float tuft_h = fract(custom.g * 7.31 + foot.x * 0.013 + foot.y * 0.019);
	float keep = 1.0;
	if (puddle > 0.35 + 0.35 * tuft_h) {
		keep = 0.0;
	} else if (wear > 0.38 + 0.38 * tuft_h) {
		keep = 0.0;
	} else if (arid > 0.44 + 0.24 * tuft_h) {
		keep = 0.0;
	}
	out_keep = keep;

	// Stepped 15 Hz pixel-crisp animation clock so tips move cleanly in whole art pixels without jitter
	float clock = floor(g_wind_clock * 15.0) / 15.0;
	vec2 wdir = length(g_wind_dir) > 0.01 ? normalize(g_wind_dir) : vec2(0.96, 0.28);
	float g_soft = g_wind_gust <= 1.1 ? g_wind_gust : 1.1 + 0.85 * tanh((g_wind_gust - 1.1) * 0.35);

	// Rolling meadow gust wave + organic spatial domain warp
	float warp = sin(foot.y * 0.042 + foot.x * 0.019) * 1.15 + cos(foot.x * 0.031 - foot.y * 0.027) * 0.65;
	float wave_arg = dot(foot, wdir) * 0.024 - clock * 1.95 + warp;
	float wave = pow(0.5 + 0.5 * sin(wave_arg), 2.2);
	float breeze = (0.14 + g_soft * (0.30 + 0.70 * wave)) * flex;

	// Independent per-tuft dance: every tuft has its own natural period & micro-flutter
	float indie_a = sin(clock * (1.85 + flex * 1.65) + phase) * (0.45 + 0.55 * breeze);
	float indie_b = sin(clock * 4.35 + phase * 3.17) * 0.28 * (0.35 + g_soft);
	float free_sway = 1.0 - 0.85 * crush;

	// Wetness weight & active raindrop micro-tremor
	float wet_here = g_wet * (1.0 - smoothstep(0.18, 0.48, arid));
	out_wet = wet_here;
	float rain_l = rain_local(foot) * (1.0 - 0.75 * day_cover(foot)) * (1.0 - smoothstep(0.18, 0.48, arid));
	float rain_dip = 0.0;
	if (rain_l > 0.05) {
		float drop_cyc = fract(clock * 1.9 + custom.g * 17.3);
		float hit = step(0.91 - 0.14 * rain_l, drop_cyc) * (1.0 - smoothstep(0.91, 1.0, drop_cyc));
		rain_dip = hit * (1.4 + 1.2 * rain_l) * free_sway;
	}
	float wet_droop = wet_here * 1.35 * (1.0 - 0.4 * crush);

	vec2 wind_disp = (wdir * breeze * 2.45 + vec2(indie_a * 1.25 + indie_b, indie_a * 0.28)) * free_sway;
	// True parabolic arch (enabled by our 5-row subdivided tuft mesh!):
	// lower stem stays planted in the soil, mid-stem curves organically, tips sweep & fold cleanly.
	float arch = pow(h, 1.38);
	float roll = pow(h, 1.16);
	vec2 part_disp = bend * vec2(5.8 + 4.2 * crush, 2.2 + 1.6 * crush) + vec2(wobble * 2.4, -abs(wobble) * 0.5);
	float flatten_y = (crush * 7.4 + min(out_bend_len, 1.0) * 1.5) * hscale * roll;

	// Edge fraying: tufts right beside paths, puddles or desert edge grow slightly shorter
	float env_trim = max(max(puddle * 0.45, smoothstep(0.15, 0.65, wear) * 0.42), smoothstep(0.20, 0.60, arid) * 0.35);
	float height_trim = ((1.0 - hscale) * 3.0 + env_trim * 5.0) * h;

	vert.x += round((wind_disp.x + part_disp.x) * arch);
	vert.y += round((wind_disp.y + part_disp.y + wet_droop + rain_dip) * arch + flatten_y + height_trim);

	out_sheen = wave * clamp(g_soft, 0.0, 1.2) * free_sway;
}
