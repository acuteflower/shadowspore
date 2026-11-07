shader_type canvas_item;
render_mode unshaded;
// The mood of the boss fight (src/ui/boss_aura.gd), a quad over the whole picture UNDER the HUD that reads what has been drawn so far.
//  - dusk: the colours drain a little into cold violet, the blacks crush (a heavier, more oppressive night while the fight goes on)
//  - vignette: a ragged, dithered dark closes in from the edges and breathes with the heartbeat of the shadow creatures; at the brink a hot magenta lip
//  - glitch: now and then (and at the big moments of the fight) rows slip sideways, the red and blue channels split, blocks jump; `neg` flashes the picture negative for a frame or two
//  - warp: at the highest level the whole picture breathes (rows wobble by a pixel)
// Everything on the 640x360 art pixel grid (view_size).

uniform sampler2D screen : hint_screen_texture, filter_nearest, repeat_disable;
uniform vec2 view_size = vec2(640.0, 360.0);
uniform float time = 0.0;
uniform float night = 0.0;
uniform float dusk = 0.0;
uniform float vignette = 0.0;
uniform float pulse = 0.0;
uniform float glitch = 0.0;
uniform float glitch_seed = 0.0;
uniform float neg = 0.0;
uniform float warp = 0.0;
uniform float heat = 0.0; // 0 violet .. 1 magenta (the later phases)

#include "res://assets/shaders/map_veil.gdshaderinc"

void fragment() {
	vec2 p = floor(UV * view_size);
	vec2 P = p + 0.5;
	vec2 sp = p;

	// the picture breathes
	if (warp > 0.0) {
		sp.x += floor(sin(P.y * 0.09 + time * 2.4) * warp * 1.6 + 0.5);
		sp.y += floor(sin(P.x * 0.07 + time * 1.9) * warp * 0.9 + 0.5);
	}
	// glitch: thin rows and big blocks slip, the colour channels split
	float tk = floor(time * 18.0) + glitch_seed;
	float row = floor(P.y / 2.0);
	float g_row = glitch * step(0.8, hash21(vec2(row, tk)));
	float block_h = 8.0 + 30.0 * hash21(vec2(tk, 4.0));
	float block = floor(P.y / block_h);
	float g_blk = glitch * step(0.72, hash21(vec2(block, tk + 7.0)));
	sp.x += g_row * (hash21(vec2(row, tk + 9.0)) - 0.5) * 44.0 + g_blk * (hash21(vec2(block, tk + 3.0)) - 0.5) * 120.0;
	float split = (g_row + g_blk) * 5.0 + glitch * 1.5 * step(0.5, hash21(vec2(tk, 1.0)));
	vec2 uv0 = clamp((sp + 0.5) / view_size, vec2(0.0), vec2(1.0));
	vec3 col = texture(screen, uv0).rgb;
	if (split > 0.0) {
		col.r = texture(screen, clamp((sp + vec2(split, 0.5)) / view_size, vec2(0.0), vec2(1.0))).r;
		col.b = texture(screen, clamp((sp + vec2(-split, 0.5)) / view_size, vec2(0.0), vec2(1.0))).b;
	}
	// a few violet specks of noise while it glitches
	if (glitch > 0.0 && hash21(p + tk) > 0.9965) {
		col = mix(col, mix(VIO5, MAGENTA, heat) * 1.6, 0.8);
	}

	// dusk
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 tint = mix(vec3(0.82, 0.70, 1.0), vec3(1.0, 0.66, 0.96), heat * 0.6);
	vec3 dark = pow(mix(col, vec3(lum) * tint, 0.5), vec3(1.14)) * 0.86 + VOID1 * 0.18;
	col = mix(col, dark, dusk);

	// the dark from the edges: dithered, ragged, breathing
	vec2 q = (P / view_size - 0.5) * vec2(1.55, 1.0);
	float d = length(q) + (vnoise(P * 0.045 + vec2(time * 0.25, 0.0)) - 0.5) * 0.14;
	float v = smoothstep(0.34, 0.92, d) * vignette * (0.88 + 0.3 * pulse);
	float qv = floor(v * 5.0 + bayer(p) * 0.99) / 5.0;
	col = mix(col, VOID0 * 1.4, qv * 0.72);
	// a hot lip on the brink of the dark
	float lip = qv * (1.0 - qv) * 4.0;
	col += mix(VIO5, MAGENTA, heat) * lip * 0.16 * (0.5 + pulse);

	// negative
	if (neg > 0.0) {
		// only in a few bands and blocks of the picture, and the negative keeps the shapes (it is mixed with the picture, not a flat fill)
		float nb = floor(P.y / (14.0 + 40.0 * hash21(vec2(tk, 8.0))));
		float inside = step(0.55, hash21(vec2(nb, tk + 21.0)));
		vec3 inv = vec3(1.0) - col;
		inv = mix(inv, vec3(dot(inv, vec3(0.33))) * vec3(0.9, 0.55, 1.0), 0.5) * 0.7;
		col = mix(col, inv, neg * inside);
	}
	COLOR = vec4(col, 1.0);
}
