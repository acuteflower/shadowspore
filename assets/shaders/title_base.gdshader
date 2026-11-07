shader_type canvas_item;
render_mode unshaded;
// The letters of the title logo. Idle: two quiet things happen on them:
//  - a glint: a diagonal band of light drifts across the lit edges now and then (in 3 hard steps, so it stays pixel art),
//  - a glitch: for a moment a few rows of the SHADOW word slip sideways (like the shadow creatures do), set by the script.
// Build-up (build_on = 1): every pixel has an arrival time (order_map R, normalised 0..1; G = 255 slides in sideways, else it falls from
// above) and lands in its place (same idea as build_pixels.gdshader). Pixels that are still missing show as a dotted teal blueprint.

uniform float time = 0.0;
uniform float glint_pos = -100.0;   // x of the band's centre along the diagonal, far off the picture when idle
uniform float glint_width = 9.0;
uniform float glint_strength = 0.16;
uniform vec4 glint_tint : source_color = vec4(0.78, 0.9, 1.0, 1.0);
uniform vec4 glitch = vec4(0.0, 0.0, 0.0, 0.0); // y, rows, shift, y limit (the rows of SHADOW)
uniform float glitch2_y = -10.0;
uniform float glitch2_shift = 0.0;

uniform sampler2D order_map : filter_nearest;
uniform float build_on = 0.0;
uniform float build_t = 2.0;       // position in the order (0..1 and more)
uniform float fall_span = 0.09;    // how long (in the same unit) a pixel is on its way
uniform float fall_px = 7.0;
uniform float slide_px = 12.0;
uniform float blueprint = 0.0;     // 0..1, the dotted draft of what is missing
uniform float flash = 0.0;         // the blow when the last letter lands

void fragment() {
	ivec2 size = textureSize(TEXTURE, 0);
	ivec2 p = ivec2(floor(UV * vec2(size)));
	vec4 c = vec4(0.0);
	float fresh = 0.0;
	if (build_on > 0.5) {
		int dir = (p.y % 2 == 0) ? 1 : -1;
		for (int k = 12; k >= 0; k--) {
			for (int mode = 0; mode < 2; mode++) {
				ivec2 s = mode == 0 ? ivec2(p.x, p.y + k) : ivec2(p.x - dir * k, p.y);
				if (mode == 0 && float(k) > fall_px) {
					continue;
				}
				if (s.x < 0 || s.y < 0 || s.x >= size.x || s.y >= size.y) {
					continue;
				}
				vec4 t = texelFetch(TEXTURE, s, 0);
				if (t.a <= 0.0) {
					continue;
				}
				vec4 m = texelFetch(order_map, s, 0);
				bool slide = m.g > 0.5;
				if (slide != (mode == 1)) {
					continue;
				}
				float q = (build_t - m.r) / fall_span;
				if (q < 0.0) {
					continue;
				}
				int off = q >= 1.0 ? 0 : int(floor((1.0 - q) * (1.0 - q) * (slide ? slide_px : fall_px) + 0.5));
				if (off != k) {
					continue;
				}
				c = t;
				fresh = q < 1.0 ? 1.0 : clamp(1.0 - (q - 1.0) * 1.6, 0.0, 1.0);
			}
		}
		if (c.a > 0.0) {
			COLOR = vec4(clamp(mix(c.rgb, vec3(0.82, 1.0, 0.95), fresh * 0.55) + vec3(0.35, 0.4, 0.55) * flash, 0.0, 1.0), 1.0);
		} else {
			vec4 own = texelFetch(TEXTURE, p, 0);
			if (own.a > 0.0 && blueprint > 0.0 && (p.x + p.y) % 2 == 0) {
				float soon = clamp(1.0 - (texelFetch(order_map, p, 0).r - build_t) * 6.0, 0.0, 1.0);
				COLOR = vec4(vec3(0.1, 0.32, 0.36) * (0.5 + 0.7 * soon) * blueprint, 1.0);
			} else {
				discard;
			}
		}
	} else {
		int sx = 0;
		float fy = float(p.y);
		if (fy >= glitch.x && fy < glitch.x + glitch.y && fy < glitch.w) {
			sx = int(glitch.z);
		}
		if (fy >= glitch2_y && fy < glitch2_y + 1.0 && fy < glitch.w) {
			sx = int(glitch2_shift);
		}
		ivec2 src = ivec2(clamp(p.x - sx, 0, size.x - 1), p.y);
		c = texelFetch(TEXTURE, src, 0);
		if (c.a <= 0.0) {
			discard;
		}
		float lum = dot(c.rgb, vec3(0.3, 0.55, 0.15));
		float d = abs((float(p.x) + float(p.y) * 0.7) - glint_pos);
		float band = clamp(1.0 - d / glint_width, 0.0, 1.0);
		band = floor(band * 3.0) / 3.0;
		float lit = smoothstep(0.28, 0.6, lum);
		COLOR = vec4(clamp(c.rgb + glint_tint.rgb * band * glint_strength * (0.4 + lit) + vec3(0.35, 0.4, 0.55) * flash, 0.0, 1.0), 1.0);
	}
}
