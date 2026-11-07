shader_type canvas_item;
render_mode unshaded;
// The boss entrance screen (src/ui/boss_intro.gd). One quad over the whole picture that reads what has been drawn so far (the world and the HUD)
// and, driven by the script, plays:
//  - bars: two black bars of shadow smoke snap shut from the top and the bottom (a ragged, flickering lip with a thin violet edge, a dithered
//    shadow cast into the picture); the same bars open again at the end
//  - dusk: the colours drain into cold violet, the blacks crush, shadow smoke creeps in from the sides
//  - focus: the dark closes in round the boss (a dithered vignette that is centred on it, not on the screen)
//  - flash: "shadow lightning": for a few frames the picture turns negative (shadows burn violet, lights go dark) and cracks of white-magenta
//    light run across it; glitch = rows slip sideways and split in colour
//  - shock / ring: the touchdown: a dithered white-violet flash and a ring of pressure that bends the picture as it runs outwards
// Everything on the 640x360 art pixel grid (view_size), like the map and the death screen.

uniform sampler2D screen : hint_screen_texture, filter_nearest, repeat_disable;
uniform vec2 view_size = vec2(640.0, 360.0);
uniform float time = 0.0;
uniform float night = 0.0;
uniform float bars = 0.0; // 0 open .. 1 shut (the slam overshoots a little)
uniform float bar_px = 40.0;
uniform float dusk = 0.0;
uniform float flash = 0.0;
uniform float flash_seed = 0.0;
uniform float glitch = 0.0;
uniform vec2 focus = vec2(0.5, 0.4); // the boss, as a fraction of the view
uniform float focus_amt = 0.0;
uniform float shock = 0.0;
uniform float ring = 0.0; // 0..1 how far the ring has run
uniform float ring_on = 0.0;
uniform float edge_heat = 0.0; // 0 violet .. 1 hot magenta-white lip on the bars

#include "res://assets/shaders/map_veil.gdshaderinc"

const vec3 HOT = vec3(1.0, 0.84, 0.96);

float bar_wobble(float x, float seed) {
	float slow = (vnoise(vec2(x * 0.06 + seed, time * 1.3)) - 0.5) * 7.0;
	float cell = floor(x / 3.0);
	float flick = floor(time * 7.0);
	float fingers = pow(hash21(vec2(cell, flick + seed)), 6.0) * 13.0; // thin tendrils of the dark that reach into the picture
	float notch = -pow(hash21(vec2(cell + 91.0, flick + seed)), 9.0) * 5.0;
	return (slow + fingers + notch) * smoothstep(0.1, 1.0, bars);
}

void fragment() {
	vec2 p = floor(UV * view_size);
	vec2 P = p + 0.5;
	vec2 fpx = focus * view_size;
	float dfoc = length(P - fpx);

	// the ring of pressure bends the picture
	float rr = ring * 460.0;
	float band = ring_on * (1.0 - smoothstep(0.0, 18.0, abs(dfoc - rr))) * (1.0 - ring);
	vec2 sp = p + normalize(P - fpx + vec2(0.001)) * band * 8.0;

	// rows slip sideways
	float row = floor(P.y / 3.0);
	float tk = floor(time * 16.0);
	float g = glitch * step(0.84, hash21(vec2(row, tk)));
	sp.x += g * (hash21(vec2(row, tk + 9.0)) - 0.5) * 52.0;
	vec3 col = texture(screen, clamp((sp + 0.5) / view_size, vec2(0.0), vec2(1.0))).rgb;
	if (g > 0.0) {
		col.r = texture(screen, clamp((sp + vec2(5.0, 0.5)) / view_size, vec2(0.0), vec2(1.0))).r;
		col.b = texture(screen, clamp((sp + vec2(-5.0, 0.5)) / view_size, vec2(0.0), vec2(1.0))).b;
	}

	// dusk: cold violet, crushed blacks
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 grey = vec3(lum) * vec3(0.82, 0.72, 1.0);
	vec3 dark = pow(mix(col, grey, 0.6), vec3(1.2)) * 0.82 + VOID1 * 0.22;
	col = mix(col, dark, dusk);

	// the dark closes in round the boss
	if (focus_amt > 0.0) {
		float d = dfoc / view_size.y;
		float v = smoothstep(0.3, 0.85, d) * focus_amt;
		float q = floor(v * 5.0 + bayer(p) * 0.99) / 5.0;
		col = mix(col, VOID0, q * 0.66);
		float haze = (1.0 - smoothstep(0.0, 0.22, d)) * focus_amt; // a cold violet breath round the boss lifts it out of the dark
		float hq = floor(haze * 4.0 + bayer(p) * 0.99) / 4.0;
		col = mix(col, col + VIO5 * 0.35, hq * 0.45);
	}

	// shadow smoke creeping in from the sides
	float side = min(P.x, view_size.x - P.x);
	float creep = dusk * 64.0;
	if (creep > 1.0) {
		float ts = 1.0 - smoothstep(0.0, creep, side + (fbm(P * 0.05 + vec2(time * 0.2, 0.0)) - 0.5) * 36.0);
		if (ts > bayer(p) * 0.92 + 0.05) col = fog_smoke(P, p, 0.4);
	}

	// shadow lightning
	if (flash > 0.0) {
		float inv = clamp(1.0 - dot(col, vec3(0.299, 0.587, 0.114)), 0.0, 1.0);
		float lv = floor(inv * 4.0 + bayer(p) * 0.8) / 4.0;
		vec3 neg = lv < 0.25 ? VOID1 : (lv < 0.5 ? VIO5 : (lv < 0.75 ? VIO7 : VIO8)); // the glaring white-lilac burn
		float c = fbm(P * 0.027 + vec2(flash_seed * 7.3, flash_seed * 3.1));
		float ridge = 1.0 - smoothstep(0.0, 0.022, abs(c - 0.5));
		if (ridge > 0.45) neg = mix(HOT, MAGENTA, hash21(p + flash_seed) * 0.45);
		else if (ridge > 0.12 && bayer(p + 1.0) < 0.6) neg = mix(neg, VIO6, 0.7);
		// the lightning is not everywhere at once: organic blobs of the picture flip, more of them the stronger the flash
		float region = fbm(P * 0.011 + vec2(flash_seed * 1.7, flash_seed * 0.9));
		float cover = 1.0 - smoothstep(flash * 1.15 - 0.12, flash * 1.15, region);
		cover = cover > 0.0 ? step(bayer(p) * 0.6, cover) : 0.0;
		col = mix(col, neg, cover * 0.9);
	}

	// the touchdown
	if (shock > 0.0) {
		float core = 0.3 + 0.7 * (1.0 - smoothstep(0.1, 0.8, dfoc / view_size.y));
		if (bayer(p) < shock * core) col = mix(col, HOT, 0.75);
	}
	if (ring_on > 0.0 && abs(dfoc - rr) < 1.6) col = mix(col, VIO8, (1.0 - ring) * 0.9);

	// the bars
	if (bars > 0.002) {
		float top = bars * bar_px + bar_wobble(P.x, 0.0);
		float bot = view_size.y - (bars * bar_px + bar_wobble(P.x, 5.0));
		if (P.y < top || P.y > bot) {
			vec3 smoke = fog_smoke(P, p, 1.0) * 0.5;
			col = mix(VOID0, smoke, 0.55);
			float into = P.y < top ? top - P.y : P.y - bot;
			// faint veins of light inside the dark
			float vein = 1.0 - smoothstep(0.0, 0.03, abs(fbm(P * 0.045 + vec2(time * 0.05, 4.0)) - 0.5));
			if (vein > 0.5 && into < 22.0 && bayer(p) < 0.5) col = mix(col, VIO5, 0.35 + 0.4 * edge_heat);
		} else {
			float dt = min(P.y - top, bot - P.y);
			if (dt < 1.0) col = mix(VIO6, HOT, edge_heat);
			else if (dt < 2.0) col = mix(col, VIO5, 0.55);
			else if (dt < 14.0 && bayer(p) < (1.0 - dt / 14.0) * 0.8) col = mix(col, VOID0, 0.7); // the shadow cast into the picture
		}
	}

	COLOR = vec4(col, 1.0);
}
