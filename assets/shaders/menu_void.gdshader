shader_type canvas_item;
render_mode unshaded;
// The main menu's void ("Licht ist Land", docs/hauptmenue_konzept.md): the camp is a clearing of land in the abyss, drawn in the same language as the
// world's edge (void_edge.gdshader): towards the rim the ground is scorched and dithered, little void blooms flicker in it, a bright dashed lip marks
// where the land ends, beyond it the banded violet haze with ribbons, stars and rising motes (abyss.gdshaderinc). The fire holds the clearing open,
// the cursor carries its own little island of land. The abyss beats slowly (lub-dub). Whole art pixels, dithered.

uniform vec2 size = vec2(640.0, 360.0); // the visible picture in art pixels
uniform vec2 fire = vec2(468.0, 286.0);
uniform vec2 radii = vec2(300.0, 150.0); // the clearing round the fire (ellipse)
uniform float land = 1.0; // 0 = void everywhere, 1 = the full clearing, more = the void is driven out
uniform vec2 light = vec2(-999.0, -999.0); // the cursor's light
uniform float light_r = 46.0;
uniform float cursor_on = 1.0;
uniform float time = 0.0;
uniform float night = 1.0;
uniform float flash = 0.0; // warm white over everything (leaving)

#include "res://assets/shaders/map_veil.gdshaderinc"
#include "res://assets/shaders/abyss.gdshaderinc"

void fragment() {
	vec2 wp = floor(UV * size);
	vec2 c = wp + 0.5;
	float beat = abyss_beat(time);
	float glow = 1.0 + 0.3 * beat;
	float macro = fbm(wp * 0.012 + 3.7 + vec2(time * 0.02, 0.0));
	float fine = vnoise(wp * vec2(0.22, 0.26) + 11.3);
	// signed distance to the rim in pixels (>0 on the land)
	vec2 q = (c - fire) / radii;
	float edge_r = land * (1.0 - 0.22 * macro - 0.05 * fine) * (1.0 - 0.012 * beat);
	float e = (edge_r - length(q)) * min(radii.x, radii.y);
	vec2 b2 = min(c, size - c);
	float border = min(b2.x, b2.y) - 20.0 - macro * 26.0 + fine * 3.0;
	e = min(e, border + max(land - 1.0, 0.0) * 400.0);
	float pool = cursor_on > 0.5 ? light_r - length(c - light) + (fine - 0.5) * 5.0 : -100000.0;
	e = max(e, pool);

	vec4 col = vec4(0.0);
	if (e >= 0.0) {
		// the land side: scorched towards the rim, then the lip
		float width = mix(18.0, 40.0, fbm(wp * 0.007 + 90.0));
		float t = 1.0 - clamp(e / width, 0.0, 1.0);
		float level = floor(t * t * 3.4 + bayer(wp));
		if (level >= 1.0) {
			col = vec4(level >= 3.0 ? VOID1 : VOID2, level >= 3.0 ? 0.88 : (level >= 2.0 ? 0.62 : 0.34));
		}
		if (e < width * 0.5 && hash21(wp + 5.0) < t * 0.28) {
			col = vec4(VOID2, 0.95); // crumbling bits
		}
		// void blooms: small flickering crosses of light in the scorched ground
		vec2 bc = floor(wp / 13.0);
		float bh = hash21(bc + 7.0);
		if (bh > 0.9 && e < width * 0.8) {
			vec2 bp = bc * 13.0 + 3.0 + floor(vec2(hash21(bc + 8.0), hash21(bc + 9.0)) * 7.0);
			vec2 k = abs(c - bp - 0.5);
			float arm = 0.5 + 0.5 * sin(time * (1.5 + bh * 2.0) + bh * 40.0) > 0.55 ? 2.0 : 1.0;
			if ((k.x < 0.6 && k.y < arm) || (k.y < 0.6 && k.x < arm)) {
				col = vec4(k.x < 0.6 && k.y < 0.6 ? VIO8 : VIO7, 1.0);
			}
		}
		// the lip: where the ground ends, a bright dashed line
		if (e < 1.6 + fine && vnoise(wp * 0.4 + time * 0.2) > 0.3) {
			col = vec4(mix(VIO6, VIO8, vnoise(wp * 0.9)) * glow, 1.0);
		} else if (e < 4.0 && col.a < 0.9) {
			col = vec4(VOID1, 0.9);
		}
	} else {
		float h = -e;
		col = vec4(abyss(wp, h, glow), 1.0);
		// a hot rim just beyond the lip
		if (h < 8.0 && bayer(wp) < (1.0 - h / 8.0) * 0.6 && fine > 0.35) {
			col = vec4(mix(VIO5, VIO6, 1.0 - h / 8.0) * glow, 1.0);
		}
	}
	col = mix(col, vec4(1.0, 0.95, 0.85, 1.0), clamp(flash, 0.0, 1.0));
	COLOR = col;
}
