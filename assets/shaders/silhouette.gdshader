shader_type canvas_item;
render_mode unshaded;
// Sculpted bright silhouette for the loading screen: keeps every sprite in a unified moonlit
// lavender-to-starlight silhouette family while retaining subtle 3-step internal luminance
// contours (so hair, cloaks, feathers, petals and crystal facets stay crisp at 1x pixel scale).
// Supports 4x4 Bayer pixel-dithered emergence (`appear`), light-rift dissolution (`dissolve`),
// and optional emissive accents (`glow_tex` + `wave_tex` for flora buds and the waystone crown).

uniform vec4 shade : source_color = vec4(0.68, 0.58, 0.93, 1.0); // #ad94ed
uniform vec4 body : source_color = vec4(0.85, 0.79, 0.99, 1.0); // #d9c9fc
uniform vec4 bright : source_color = vec4(0.95, 0.92, 1.0, 1.0); // #f2ebff
uniform vec4 rim : source_color = vec4(1.0, 0.99, 0.97, 1.0); // #fffdf7
uniform float rim_strength : hint_range(0.0, 1.0) = 0.9;
uniform float sculpt : hint_range(0.0, 1.0) = 0.85;
uniform float cutoff : hint_range(0.0, 1.0) = 0.55;
uniform float appear : hint_range(0.0, 1.0) = 1.0;
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flare_color : source_color = vec4(0.62, 0.98, 0.94, 1.0); // #9efaf0
uniform sampler2D glow_tex : hint_default_transparent, filter_nearest;
uniform sampler2D wave_tex : hint_default_white, filter_nearest;
uniform float glow_amount : hint_range(0.0, 2.0) = 0.0;
uniform float wave_progress : hint_range(0.0, 1.5) = 1.5;
uniform vec4 glow_tint : source_color = vec4(0.52, 0.96, 0.91, 1.0); // #85f5e8

float bayer4(vec2 p) {
	int x = int(mod(p.x + 4096.0, 4.0));
	int y = int(mod(p.y + 4096.0, 4.0));
	int i = x + y * 4;
	float m[16] = float[16](
		0.0, 8.0, 2.0, 10.0,
		12.0, 4.0, 14.0, 6.0,
		3.0, 11.0, 1.0, 9.0,
		15.0, 7.0, 13.0, 5.0
	);
	return (m[i] + 0.5) / 16.0;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (c.a < cutoff) {
		discard;
	}
	vec2 px = floor(UV / TEXTURE_PIXEL_SIZE);
	float d = bayer4(px);
	if (appear < 1.0 && d >= appear) {
		discard;
	}
	if (dissolve > 0.0 && d < dissolve) {
		discard;
	}

	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	vec3 sculpted = lum < 0.20 ? shade.rgb : (lum < 0.48 ? body.rgb : bright.rgb);
	vec3 col = mix(body.rgb, sculpted, sculpt);

	vec2 t = TEXTURE_PIXEL_SIZE;
	float open_top = 1.0 - step(cutoff, texture(TEXTURE, UV + vec2(0.0, -t.y)).a);
	float open_front = 1.0 - step(cutoff, texture(TEXTURE, UV + vec2(t.x, 0.0)).a);
	float open_back = 1.0 - step(cutoff, texture(TEXTURE, UV + vec2(-t.x, 0.0)).a);
	float lit_edge = clamp(open_top + open_front, 0.0, 1.0);
	if (open_back > 0.5 && lit_edge < 0.5) {
		col = mix(col, shade.rgb, 0.65 * sculpt);
	}
	col = mix(col, rim.rgb, lit_edge * rim_strength);

	if (glow_amount > 0.001) {
		vec4 g = texture(glow_tex, UV);
		vec4 w = texture(wave_tex, UV);
		float reached = step(w.r, wave_progress);
		float g_lum = dot(g.rgb, vec3(0.299, 0.587, 0.114));
		float emit = g.a * smoothstep(0.15, 0.85, g_lum) * reached * clamp(glow_amount, 0.0, 1.5);
		vec3 gcol = mix(glow_tint.rgb, vec3(1.0), 0.4 * g_lum);
		col = mix(col, gcol, clamp(emit, 0.0, 1.0));
		if (wave_progress > 0.002 && wave_progress < 1.12) {
			float front = (1.0 - smoothstep(0.0, 0.055, abs(wave_progress - w.r))) * w.a;
			col = mix(col, mix(glow_tint.rgb, vec3(1.0), 0.55), clamp(front, 0.0, 1.0));
		}
	}

	if (dissolve > 0.0) {
		float bloom = smoothstep(0.0, 0.6, dissolve);
		col = mix(col, mix(flare_color.rgb, vec3(1.0), smoothstep(0.25, 0.9, dissolve)), bloom);
	}

	COLOR = vec4(col, 1.0);
}
