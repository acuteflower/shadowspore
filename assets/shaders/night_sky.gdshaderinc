// The night sky as water mirrors it (docs/wasserspiegelung.md): stars, the Milky Way and the moon with its phase and glade.
// Stars, Milky Way, moon and moon glade stay anchored in world space (drifting only slowly over the night and with water ripples,
// completely independent of Ellie / the camera). Needs river_noise.gdshaderinc, daylight.gdshaderinc (clouds) before it.
// Additive light; call it from an unshaded pass (river_glow.gdshader / water_v2_glow.gdshader), the CanvasModulate night tint would swallow it otherwise.
global uniform vec4 g_sky_view; // world px: top left of the camera view, view size (NightAtmosphere)
global uniform vec4 g_sky; // x night progress 0..1 (dusk .. dawn), y moon phase 0 new .. 0.5 full .. 1, z sky strength 0..1 (0 = day/indoors), w moon brightness

// The reflected sky at world pixel `px` on water whose surface slides rows sideways by `wobble` px. `rough` 0 calm .. 1+ choppy.
vec3 night_sky_at(vec2 px, float wobble, float rough, float t) {
	if (g_sky.z < 0.01) { return vec3(0.0); }
	float row = floor(px.y);
	float slide = floor(sin(row * 0.61 + t * 2.1) * wobble + sin(row * 0.17 - t * 0.83 + px.x * 0.013) * wobble * 0.7 + 0.5);
	vec2 wp = vec2(px.x + slide, px.y); // world art pixel (sky reflection stays put when Ellie moves)
	// the sky turns slowly over the night, independently of the camera
	vec2 turn = vec2(g_sky.x * 46.0, -g_sky.x * 14.0);
	vec2 st = wp + floor(turn);
	// clouds hide it (their shadow on the ground is where the sky above this water is covered)
	float cover = smoothstep(0.2, 0.75, cloud_thick(px)); // thin veils let the stars through
	cover = max(cover, 0.85 * g_storm);
	float open = 1.0 - cover;
	vec3 sky = vec3(0.0);
	// a breath of sky light: the water is a little brighter than the night ground, more under a bright moon
	sky += vec3(0.010, 0.016, 0.034) * (0.6 + 0.6 * g_sky.w) * mix(1.0, 0.5, cover);
	// clouds reflect as a dim grey sheen when the moon lights them
	sky += vec3(0.020, 0.022, 0.030) * cover * g_sky.w * (1.0 - g_storm);
	// the Milky Way: faint dusty bands across the world sky, anchored in world space
	vec2 vb = st / vec2(640.0, 360.0);
	float band_phase = vb.y - 0.62 + vb.x * 0.55 + sin(vb.x * 5.0) * 0.04;
	float band_dist = abs(fract(band_phase / 1.6 + 0.5) - 0.5) * 1.6;
	float band = 1.0 - smoothstep(0.0, 0.17, band_dist);
	float dust = vnoise(st / 7.0) * 0.6 + vnoise(st / 2.5) * 0.4;
	float lane = smoothstep(0.42, 0.7, vnoise(st / 15.0 + 3.0)); // dark lanes in it
	sky += vec3(0.030, 0.030, 0.046) * band * smoothstep(0.45, 0.8, dust) * (1.0 - 0.7 * lane) * open * (1.15 - 0.4 * g_sky.w);
	// ripple crests catch nothing for a moment: stars wink
	float crest = sin(px.y * 0.93 + floor(px.x / 7.0) * 1.9 - t * mix(0.9, 2.2, clamp(rough, 0.0, 1.0)));
	float wink = crest > mix(0.93, 0.6, clamp(rough, 0.0, 1.0)) ? 0.15 : 1.0;
	// stars: one candidate per 5x5 cell, more in the band, few bright ones, colour by temperature
	vec2 cell = floor(st / 5.0);
	float h = hash21(cell + 101.0);
	float dens = 0.16 + 0.2 * band;
	if (h < dens) {
		vec2 at = cell * 5.0 + floor(vec2(hash21(cell + 7.0), hash21(cell + 13.0)) * 5.0);
		vec2 d = st - at;
		float mag = pow(hash21(cell + 29.0), 3.0); // most are faint
		float tw = 0.75 + 0.25 * sin(t * (1.5 + h * 9.0) + h * 70.0); // the sky's own twinkle
		float temp = hash21(cell + 41.0);
		vec3 tint = temp < 0.2 ? vec3(0.75, 0.85, 1.0) : (temp > 0.88 ? vec3(1.0, 0.84, 0.66) : vec3(0.92, 0.94, 1.0));
		float b = (0.16 + 0.75 * mag) * tw;
		if (d == vec2(0.0)) { sky += tint * b * wink * open; }
		else if (mag > 0.55 && rough < 0.6 && abs(d.x) + abs(d.y) == 1.0) { sky += tint * b * 0.28 * wink * open; } // a bright star's cross on calm water
		else if (mag > 0.4 && rough >= 0.6 && d.y == 0.0 && abs(d.x) == 1.0) { sky += tint * b * 0.3 * wink * open; } // choppy: smeared sideways
	}
	// the moon (anchored in world space on a periodic sky tile so it stays put when Ellie moves)
	float phase = g_sky.y;
	float lit_part = 0.5 - 0.5 * cos(6.2831853 * phase); // 0 new .. 1 full
	if (lit_part > 0.02) {
		float p = g_sky.x;
		vec2 moon_tile = vec2(840.0, 640.0);
		vec2 moon_origin = floor(moon_tile * vec2(mix(0.86, 0.14, p), 0.34 - 0.16 * sin(3.14159 * p))); // rises east, sets west
		vec2 m_diff = wp - moon_origin;
		vec2 m_rel = m_diff - moon_tile * floor(m_diff / moon_tile + 0.5);
		float radius = 7.5;
		float choppy = clamp(rough, 0.0, 1.4);
		// the disc breaks a little more than the rest: each row slides on its own, choppy water stretches it sideways
		float row_cut = floor(sin(row * 1.37 + t * 1.7) * choppy * 2.2 + 0.5);
		vec2 dm = vec2(m_rel.x + row_cut, m_rel.y);
		dm.x /= 1.0 + 0.6 * choppy;
		float r = length(dm + 0.5);
		float glow_amt = lit_part * g_sky.w * open;
		if (r < radius) {
			// the disc: phase (mirrored: a reflection is upside down), dark seas, a brighter limb-lit rim on the lit side, earthshine on the dark part
			vec2 u = (dm + 0.5) / radius;
			u.y = -u.y;
			float limb = sqrt(max(1.0 - u.y * u.y, 0.0));
			float k = cos(6.2831853 * phase);
			float edge = phase < 0.5 ? u.x - limb * k : -limb * k - u.x;
			bool lit = edge > 0.0;
			vec2 mu = floor(u * radius);
			float sea = smoothstep(0.55, 0.62, vnoise(mu / 3.1 + vec2(4.3, 1.7))) * 0.40 + smoothstep(0.6, 0.66, vnoise(mu / 1.7 + 9.0)) * 0.14;
			float crater = step(0.93, hash21(mu + 17.0)) * 0.12;
			float limb_dark = 0.78 + 0.22 * sqrt(max(1.0 - dot(u, u), 0.0));
			vec3 moonc = vec3(1.0, 0.98, 0.90) * (1.0 - sea - crater) * limb_dark;
			// a soft terminator one pixel wide: the dithered grey of the sunrise line on the moon
			if (lit && edge < 0.12 && bayer4(px) > 0.5) { moonc *= 0.55; }
			// ripple crests cut thin dark lines through the image
			float cut = (rough < 0.25 || mod(row, 3.0) != 0.0 || fract(t * 0.7 + row * 0.13) > 0.4) ? 1.0 : 0.45;
			sky += (lit ? moonc * 0.95 * g_sky.w : vec3(0.035, 0.045, 0.07) * (1.0 - lit_part)) * open * cut;
		} else if (r < radius + 18.0) {
			// halo, dithered so it stays pixel art: an inner bright ring and a wide faint one
			float halo = exp(-(r - radius) / 3.0) * 0.55 + exp(-(r - radius) / 9.0) * 0.25;
			if (halo * glow_amt > bayer4(px) * 1.1) { sky += vec3(0.12, 0.14, 0.18) * glow_amt; }
		}
		// the glade: on any ripple the moon breaks into short bright dashes stacked in rows, stretching towards the viewer (+y)
		// and a little above; calm water keeps it short and narrow, a river or rain throws it long and wide and makes it dance
		float dx = m_rel.x;
		float dy = m_rel.y;
		float reach = 80.0 + 150.0 * choppy;
		if (dy > -reach * 0.3 && dy < reach && r > radius - 1.0) {
			float along = dy > 0.0 ? dy / reach : -dy / (reach * 0.3);
			float width = radius * 1.2 + abs(dy) * (0.10 + 0.12 * choppy) + 8.0 * choppy;
			float across = abs(dx) / width;
			float inside = (1.0 - smoothstep(0.25, 1.0, across)) * (1.0 - smoothstep(0.05, 1.0, along));
			float gband = floor(wp.y / 2.0);
			if (mod(wp.y, 2.0) < 1.0 && inside > 0.01) {
				float dir = hash21(vec2(gband, 3.0)) > 0.5 ? 1.0 : -1.0;
				float seg_len = 3.0 + floor(hash21(vec2(gband, 9.0)) * 4.0);
				float drift = floor(dir * t * (2.0 + 6.0 * choppy) * (0.6 + hash21(vec2(gband, 5.0))));
				float seg = floor((wp.x + drift) / seg_len);
				float gap = mod(wp.x + drift, seg_len) < seg_len - 1.0 ? 1.0 : 0.0; // a dark pixel between dashes
				float pulse = 0.5 + 0.5 * sin(t * (1.2 + choppy * 2.0) + gband * 1.9 + seg * 0.7);
				if (gap > 0.5 && hash21(vec2(seg, gband) + 61.0) < inside * (0.55 + 0.35 * pulse)) {
					float bright = 0.55 + 0.75 * inside;
					sky += vec3(0.95, 0.94, 0.84) * bright * glow_amt;
				}
			}
		}
	}
	return sky * g_sky.z;
}
